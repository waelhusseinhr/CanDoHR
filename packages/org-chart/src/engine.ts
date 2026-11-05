import {
  ChangeSetService,
  SessionHub,
  addAssignment,
  addEmployment,
  addLocation,
  addPosition,
  emptyWorld,
  type ApprovalDirectory,
  type ApprovalRoute,
  type ChangeSetRecord,
  type Consequence,
  type Finding,
  type Operation,
} from "@candohr/changesets";
import { Money, addDays, compareIsoDate, readAsOf } from "@candohr/shared";
import { layoutChart, type PlacedNode } from "./layout.ts";

/**
 * Org chart in memory (build-plan step 6).
 * Boxes are a view of the same effective-dated records as the profile.
 * Saving a move writes a change set. The rows will go through Hyperdrive,
 * with query caching off, once SUPABASE_DB_PASSWORD is available.
 * This object does not open a database.
 */

interface Slice {
  validStart: string;
  validEnd: string | null;
  recordedAt: string;
  supersededAt: string | null;
}

interface ReportEdge extends Slice {
  positionId: string;
  reportsToPositionId: string | null;
}

interface UnitEdge extends Slice {
  id: string;
  parentId: string | null;
  name: string;
  province: string;
  costCentreId: string;
  hierarchyId: string;
}

interface Holder extends Slice {
  assignmentId: string;
  positionId: string;
  personId: string;
  name: string;
  fte: string;
}

interface PositionBox {
  id: string;
  title: string;
  orgUnitId: string;
  fteBudget: string;
  annualCost: string;
}

export interface ChartNode {
  id: string;
  kind: "position" | "person" | "org_unit";
  title: string;
  orgUnitId: string;
  vacant: boolean;
  badges: string[];
  holders: { assignmentId: string; displayName: string; acting: boolean }[];
  hasChildren: boolean;
}

export interface ChartEdge {
  from: string;
  to: string;
  kind: "solid" | "dotted" | "acting";
}

export interface ChartView {
  asOf: string;
  nodes: ChartNode[];
  edges: ChartEdge[];
}

export interface MoveInput {
  subject: { type: "position" | "person_assignment" | "org_unit" | "multiple"; id: string; ids?: string[] };
  target: { type: "position" | "vacant_position" | "org_unit" | "person_assignment"; id: string };
  effectiveDate: string;
  interpretation?: "move_position" | "transfer_to_vacancy" | "create_position" | "temporary_reporting";
  overlapApproved?: boolean;
  endDate?: string | null;
  reasonCode?: string;
  planId?: string | null;
  isCorrection?: boolean;
  conflictResolution?: "keep" | "replace" | "merge";
  costImpact?: string;
  requestedBy?: string;
}

export interface MoveResult {
  ok: boolean;
  interpretations: { code: string; label: string }[];
  changeSetId?: string;
  status?: string;
  validation: { errors: Finding[]; warnings: Finding[]; consequences: Consequence[] };
  operations: Operation[];
}

export interface PlanSummary {
  planId: string;
  name: string;
  status: "open" | "submitted" | "approved" | "discarded";
  moveCount: number;
  headcountDelta: number;
  annualCostDelta: string;
  changeSetId?: string;
  operationCount: number;
}

interface StoredMove {
  effectiveDate: string;
  operations: Operation[];
  costImpact: string;
  changeSetId: string;
}

interface PlanRecord {
  planId: string;
  name: string;
  asOf: string;
  status: PlanSummary["status"];
  members: string[];
  moves: StoredMove[];
  changeSetId?: string;
}

const INTERPRETATIONS = [
  { code: "move_position", label: "Move their position under that manager" },
  { code: "transfer_to_vacancy", label: "Move them into a vacant position on that team" },
  { code: "create_position", label: "Create a new position on that team" },
  { code: "temporary_reporting", label: "Change who they report to for a while" },
] as const;

export class OrgChart {
  readonly sessions = new SessionHub();
  readonly retroRequests: { personId: string; effectiveDate: string }[] = [];
  private readonly clock: { today: string; knownAt: string; finalizedThrough: string };
  private readonly changes: ChangeSetService;
  private readonly positions = new Map<string, PositionBox>();
  private readonly reports: ReportEdge[] = [];
  private readonly units: UnitEdge[] = [];
  private readonly holders: Holder[] = [];
  private readonly plans = new Map<string, PlanRecord>();
  private readonly directory: ApprovalDirectory;
  readonly placed: PlacedNode[] = [];

  constructor(
    clock: { today: string; knownAt: string; finalizedThrough?: string },
    options?: { directory?: ApprovalDirectory; routes?: ApprovalRoute[] },
  ) {
    this.clock = {
      today: clock.today,
      knownAt: clock.knownAt,
      // structural: as-of or demo date when caller omits effective date
      finalizedThrough: clock.finalizedThrough ?? "1970-01-01",
    };
    this.directory = options?.directory ?? {
      candidates: () => [],
      onLeave: () => null,
      isSubordinateOnOtherAssignment: () => false,
    };
    const routes = options?.routes ?? [
      {
        mode: "sequential" as const,
        matches: (row: ChangeSetRecord) => row.kind === "cross_province",
        steps: [{ role: "hr" }],
      },
    ];
    this.changes = new ChangeSetService(emptyWorld(), {
      tenantId: "tenant-1",
      today: clock.today,
      now: () => clock.knownAt,
      directory: this.directory,
      routes,
    });
  }

  addUnit(input: {
    id: string;
    parentId: string | null;
    name: string;
    province: string;
    costCentreId: string;
    hierarchyId?: string;
    effectiveDate?: string;
  }): void {
    this.units.push({
      id: input.id,
      parentId: input.parentId,
      name: input.name,
      province: input.province,
      costCentreId: input.costCentreId,
      hierarchyId: input.hierarchyId ?? "management", // structural: demo hierarchy id when caller omits it
      // structural: as-of or demo date when caller omits effective date
      validStart: input.effectiveDate ?? "2020-01-01",
      validEnd: null,
      recordedAt: "2020-01-01T00:00:00.000Z",
      supersededAt: null,
    });
    this.changes.books.orgUnits[input.id] = { id: input.id, parentId: input.parentId, status: "active" };
  }

  addBox(input: {
    positionId: string;
    title: string;
    orgUnitId: string;
    reportsToPositionId: string | null;
    fteBudget?: string;
    annualCost?: string;
    validStart?: string;
    holder?: { personId: string; name: string; assignmentId: string; fte?: string; rate?: string; laterRate?: { date: string; rate: string } };
  }): void {
    // structural: as-of or demo date when caller omits effective date
    const start = input.validStart ?? "2020-01-01";
    this.positions.set(input.positionId, {
      id: input.positionId,
      title: input.title,
      orgUnitId: input.orgUnitId,
      fteBudget: money(input.fteBudget ?? "1.00"), // structural: demo FTE when seeding chart fixtures
      // structural: nullish coalescing for optional input in tests or adapters
      annualCost: money(input.annualCost ?? "0.00"),
    });
    addPosition(this.changes.books, { id: input.positionId, orgUnitId: input.orgUnitId, status: input.holder ? "active" : "vacant" });
    this.reports.push({
      positionId: input.positionId,
      reportsToPositionId: input.reportsToPositionId,
      validStart: start,
      validEnd: null,
      recordedAt: "2020-01-01T00:00:00.000Z",
      supersededAt: null,
    });
    if (!input.holder) return;
    const fte = money(input.holder.fte ?? "1.00"); // structural: demo FTE when seeding holder fixtures
    // structural: money string placeholder when input omits amount
    const rate = money(input.holder.rate ?? "1.00");
    this.holders.push({
      assignmentId: input.holder.assignmentId,
      positionId: input.positionId,
      personId: input.holder.personId,
      name: input.holder.name,
      fte,
      validStart: start,
      validEnd: null,
      recordedAt: "2020-01-01T00:00:00.000Z",
      supersededAt: null,
    });
    addEmployment(this.changes.books, { id: `employment-${input.holder.personId}`, personId: input.holder.personId });
    // structural: nullish coalescing for optional input in tests or adapters
    addLocation(this.changes.books, { id: `loc-${input.orgUnitId}`, province: this.unitAt(input.orgUnitId, start)?.province ?? "MB" });
    const later = input.holder.laterRate
      ? [
          {
            validStart: input.holder.laterRate.date,
            attributes: {
              rate: money(input.holder.laterRate.rate),
              orgUnitId: input.orgUnitId,
              positionId: input.positionId,
              status: "open",
            },
            explicitKeys: ["rate"],
          },
        ]
      : [];
    addAssignment(this.changes.books, {
      id: input.holder.assignmentId,
      employmentId: `employment-${input.holder.personId}`,
      personId: input.holder.personId,
      positionId: input.positionId,
      orgUnitId: input.orgUnitId,
      locationId: `loc-${input.orgUnitId}`,
      rate,
      validStart: start,
      validEnd: input.holder.laterRate?.date ?? null,
      recordedAt: "2020-01-01T00:00:00.000Z",
      explicitKeys: ["orgUnitId", "positionId", "locationId", "rate", "status"],
      later,
    });
  }

  /** One parent and `count - 1` direct reports. Used to time a large chart. */
  seedWide(count: number): void {
    this.addUnit({ id: "wide", parentId: null, name: "Wide", province: "MB", costCentreId: "cc-wide" });
    this.addBox({ positionId: "wide-root", title: "Root", orgUnitId: "wide", reportsToPositionId: null, fteBudget: "1.00" });
    // structural: loop index or iteration bound, not a business default
    for (let index = 1; index < count; index += 1) {
      this.addBox({
        positionId: `wide-${index}`,
        title: `Box ${index}`,
        orgUnitId: "wide",
        reportsToPositionId: "wide-root",
        fteBudget: "1.00",
      });
    }
  }

  chart(query: { asOf: string; rootId?: string; depth?: number; planId?: string | null; hierarchyId?: string }): ChartView {
    const hierarchyId = query.hierarchyId ?? "management"; // structural: demo hierarchy id for chart queries
    // structural: org-chart query default depth for demos
    const depth = query.depth ?? 3;
    const parents = this.reportParents(query.asOf);
    if (query.planId) this.overlayPlan(parents, query.planId, query.asOf);
    const nodes: ChartNode[] = [];
    const edges: ChartEdge[] = [];
    const roots = query.rootId ? [query.rootId] : [...this.positions.values()].filter((box) => !parents.get(box.id)).map((box) => box.id);
    const seen = new Set<string>();
    const walk = (id: string, level: number): void => {
      if (seen.has(id) || level > depth) return;
      seen.add(id);
      const box = this.positions.get(id);
      if (!box) return;
      const unit = this.unitAt(box.orgUnitId, query.asOf);
      if (unit && unit.hierarchyId !== hierarchyId && hierarchyId !== "management") return;
      const holders = this.holdersAt(id, query.asOf);
      const upcoming = this.reports.find((row) => row.positionId === id && row.supersededAt === null && row.validStart > query.asOf);
      const badges = upcoming ? [`upcoming_change:${upcoming.validStart}`] : [];
      const children = [...parents.entries()].filter((entry) => entry[1] === id).map((entry) => entry[0]);
      nodes.push({
        id,
        kind: "position",
        title: box.title,
        orgUnitId: box.orgUnitId,
        vacant: holders.length === 0,
        badges,
        holders: holders.map((row) => ({ assignmentId: row.assignmentId, displayName: row.name, acting: false })),
        hasChildren: children.length > 0,
      });
      for (const child of children) {
        edges.push({ from: id, to: child, kind: "solid" });
        walk(child, level + 1);
      }
    };
    for (const root of roots) walk(root, 0);
    return { asOf: query.asOf, nodes, edges };
  }

  layout(query: { asOf: string; depth?: number }): PlacedNode[] {
    const view = this.chart(query);
    const placed = layoutChart(view.nodes, view.edges);
    this.placed.splice(0, this.placed.length, ...placed);
    return placed;
  }

  managerAsOf(personId: string, asOf: string): string | null {
    const holder = this.holders.find((row) => row.personId === personId && covers(row, asOf, this.clock.knownAt));
    if (!holder) return null;
    const parentId = this.reportParents(asOf).get(holder.positionId);
    if (!parentId) return null;
    return this.holdersAt(parentId, asOf)[0]?.name ?? null;
  }

  timesheetApprover(personId: string, date: string): string | null {
    return this.managerAsOf(personId, date);
  }

  parentAsOf(unitId: string, asOf: string): string | null {
    return this.unitAt(unitId, asOf)?.parentId ?? null;
  }

  rateAsOf(assignmentId: string, asOf: string): string | null {
    const row = readAsOf(this.changes.books.assignments[assignmentId]?.versions ?? [], assignmentId, asOf, this.clock.knownAt);
    const rate = row?.attributes.rate;
    return typeof rate === "string" ? rate : null;
  }

  orgUnitAsOf(assignmentId: string, asOf: string): string | null {
    const row = readAsOf(this.changes.books.assignments[assignmentId]?.versions ?? [], assignmentId, asOf, this.clock.knownAt);
    const orgUnitId = row?.attributes.orgUnitId;
    return typeof orgUnitId === "string" ? orgUnitId : null;
  }

  move(input: MoveInput): MoveResult {
    const ambiguous = this.interpretationsFor(input);
    if (ambiguous && !input.interpretation) {
      return { ok: true, interpretations: [...INTERPRETATIONS], validation: emptyValidation(), operations: [] };
    }
    const operations = this.operationsFor(input);
    const errors = this.errorsFor(input, operations);
    const consequences = this.consequencesFor(input, operations);
    if (errors.length > 0) {
      return { ok: false, interpretations: [], validation: { errors, warnings: [], consequences }, operations };
    }
    const kind = this.crossProvince(input) ? "cross_province" : "org_chart_move";
    const created = this.changes.create(
      {
        kind,
        // structural: nullish coalescing for optional input in tests or adapters
        reasonCode: input.reasonCode ?? "reorganization",
        effectiveDate: input.effectiveDate,
        isCorrection: input.isCorrection,
        operations,
        source: "org_chart",
        conflictResolution: input.conflictResolution,
      },
      // structural: demo identifiers, not organization data
      input.requestedBy ?? "hr-admin",
    );
    if (!created.ok) {
      return {
        ok: false,
        interpretations: [],
        validation: { errors: [{ code: created.code, message: created.detail }], warnings: [], consequences },
        operations,
      };
    }
    if (input.planId) {
      const plan = this.plans.get(input.planId);
      if (!plan) {
        return { ok: false, interpretations: [], validation: { errors: [{ code: "PLAN_UNKNOWN", message: "That plan does not exist." }], warnings: [], consequences }, operations };
      }
      plan.moves.push({
        effectiveDate: input.effectiveDate,
        operations,
        // structural: nullish coalescing for optional input in tests or adapters
        costImpact: money(input.costImpact ?? "0.00"),
        changeSetId: created.body.changeSetId,
      });
      return {
        ok: true,
        interpretations: [],
        changeSetId: created.body.changeSetId,
        status: "draft",
        validation: { errors: [], warnings: [], consequences },
        operations,
      };
    }
    const submitted = this.changes.submit(created.body.changeSetId, {
      isCorrection: input.isCorrection,
      conflictResolution: input.conflictResolution,
    });
    if (!submitted.ok) {
      return {
        ok: false,
        interpretations: [],
        changeSetId: created.body.changeSetId,
        validation: { errors: [{ code: submitted.code, message: submitted.detail }], warnings: [], consequences },
        operations,
      };
    }
    this.afterSave(submitted.body);
    return {
      ok: true,
      interpretations: [],
      changeSetId: submitted.body.changeSetId,
      status: submitted.body.status,
      validation: { errors: [], warnings: submitted.body.validation?.warnings ?? [], consequences },
      operations: submitted.body.operations,
    };
  }

  decide(changeSetId: string, userId: string): MoveResult {
    const decided = this.changes.decide(changeSetId, userId, { decision: "approve" });
    if (!decided.ok) {
      return { ok: false, interpretations: [], validation: { errors: [{ code: decided.code, message: decided.detail }], warnings: [], consequences: [] }, operations: [] };
    }
    this.afterSave(decided.body);
    return {
      ok: true,
      interpretations: [],
      changeSetId,
      status: decided.body.status,
      validation: decided.body.validation ?? emptyValidation(),
      operations: decided.body.operations,
    };
  }

  createPlan(input: { name: string; asOf: string; members?: string[] }): PlanSummary {
    const planId = crypto.randomUUID();
    this.plans.set(planId, { planId, name: input.name, asOf: input.asOf, status: "open", members: input.members ?? [], moves: [] });
    return this.planSummary(planId);
  }

  // structural: test and demo actor id, not a route default
  approvePlan(planId: string, requestedBy = "hr-admin"): PlanSummary {
    const plan = this.mustPlan(planId);
    const operations = plan.moves.flatMap((move) => move.operations.map((op) => ({ ...op, set: op.set ? { ...op.set } : undefined })));
    if (operations.length === 0) throw new Error("PLAN_EMPTY");
    const created = this.changes.create(
      {
        kind: "plan_submit",
        reasonCode: "reorganization",
        effectiveDate: plan.asOf,
        operations,
        source: "org_chart",
        conflictResolution: "merge",
      },
      requestedBy,
    );
    if (!created.ok) throw new Error(created.code);
    const submitted = this.changes.submit(created.body.changeSetId, { conflictResolution: "merge" });
    if (!submitted.ok) throw new Error(submitted.code);
    this.afterSave(submitted.body);
    plan.status = "approved";
    plan.changeSetId = submitted.body.changeSetId;
    return this.planSummary(planId);
  }

  planSummary(planId: string): PlanSummary {
    const plan = this.mustPlan(planId);
    const annual = plan.moves.reduce((sum, move) => sum.plus(Money.parse(move.costImpact)), Money.parse("0.00"));
    // structural: missing numeric coalesces to zero for arithmetic
    const operationCount = plan.changeSetId ? (this.changes.sets.get(plan.changeSetId)?.operations.length ?? 0) : plan.moves.reduce((sum, move) => sum + move.operations.length, 0);
    return {
      planId,
      name: plan.name,
      status: plan.status,
      moveCount: plan.moves.length,
      headcountDelta: 0,
      annualCostDelta: annual.toString(),
      changeSetId: plan.changeSetId,
      operationCount,
    };
  }

  compare(left: string, right: string): { moved: string[]; added: string[]; removed: string[] } {
    const before = this.reportParents(left);
    const after = this.reportParents(right);
    const ids = new Set([...before.keys(), ...after.keys(), ...this.positions.keys()]);
    const moved: string[] = [];
    const added: string[] = [];
    const removed: string[] = [];
    for (const id of ids) {
      const from = before.get(id) ?? null;
      const to = after.get(id) ?? null;
      if (from === to) continue;
      if (from === null) added.push(id);
      else if (to === null) removed.push(id);
      else moved.push(id);
    }
    return { moved, added, removed };
  }

  subscribe(sessionId: string, units: readonly string[]): void {
    this.sessions.subscribe({ sessionId, userId: sessionId, units, canSee: () => true });
  }

  private afterSave(row: ChangeSetRecord): void {
    if (row.status !== "committed" && row.status !== "scheduled") return;
    for (const op of row.operations) this.applyOperation(op, row.effectiveDate);
    const units = new Set<string>();
    for (const op of row.operations) {
      const unit = typeof op.set?.orgUnitId === "string" ? op.set.orgUnitId : op.orgUnitId;
      if (unit) units.add(unit);
      const positionId = op.positionId;
      const box = positionId ? this.positions.get(positionId) : undefined;
      if (box) units.add(box.orgUnitId);
    }
    if (row.kind === "cross_province" && compareIsoDate(row.effectiveDate, this.clock.finalizedThrough) <= 0) {
      const unitId = row.operations.find((op) => op.op === "org_unit.move")?.orgUnitId;
      if (unitId) {
        for (const personId of this.peopleInUnit(unitId, row.effectiveDate)) {
          this.retroRequests.push({ personId, effectiveDate: row.effectiveDate });
        }
      }
    }
    this.sessions.publish({ type: "org.changed", asOf: row.effectiveDate, units: [...units].filter((unit) => unit.length > 0) });
  }

  private applyOperation(op: Operation, effectiveDate: string): void {
    if (op.op === "position.update" && op.positionId && typeof op.set?.reportsToPositionId === "string") {
      this.spliceReports(op.positionId, op.set.reportsToPositionId, effectiveDate);
    }
    if (op.op === "position.update" && op.positionId && op.set?.reportsToPositionId === null) {
      this.spliceReports(op.positionId, null, effectiveDate);
    }
    if (op.op === "org_unit.move" && op.orgUnitId && (typeof op.set?.parentId === "string" || op.set?.parentId === null)) {
      this.spliceUnit(op.orgUnitId, typeof op.set.parentId === "string" ? op.set.parentId : null, effectiveDate);
    }
    if (op.op === "assignment.update" && op.assignmentId && typeof op.set?.positionId === "string") {
      this.spliceHolder(op.assignmentId, op.set.positionId, effectiveDate, typeof op.set.validEnd === "string" ? op.set.validEnd : null);
    }
    if (op.op === "position.create" && op.positionId) {
      const orgUnitId = typeof op.set?.orgUnitId === "string" ? op.set.orgUnitId : "";
      const title = typeof op.set?.title === "string" ? op.set.title : "Position";
      const reportsTo = typeof op.set?.reportsToPositionId === "string" ? op.set.reportsToPositionId : null;
      if (!this.positions.has(op.positionId)) {
        this.positions.set(op.positionId, { id: op.positionId, title, orgUnitId, fteBudget: "1.00", annualCost: "0.00" });
        this.reports.push({
          positionId: op.positionId,
          reportsToPositionId: reportsTo,
          validStart: effectiveDate,
          validEnd: null,
          recordedAt: this.clock.knownAt,
          supersededAt: null,
        });
      }
    }
  }

  private operationsFor(input: MoveInput): Operation[] {
    if (input.subject.type === "multiple") {
      return (input.subject.ids ?? []).map((assignmentId) => ({
        op: "assignment.update",
        assignmentId,
        targetId: assignmentId,
        set: {
          positionId: input.target.id,
          ...(input.endDate ? { validEnd: input.endDate } : {}),
          ...(input.overlapApproved ? { assignmentType: "overlap" } : {}),
        },
      }));
    }
    if (input.subject.type === "org_unit") {
      return [{ op: "org_unit.move", orgUnitId: input.subject.id, targetId: input.subject.id, set: { parentId: input.target.id } }];
    }
    if (input.subject.type === "position" || input.interpretation === "move_position") {
      const positionId = input.subject.type === "position" ? input.subject.id : this.positionOfAssignment(input.subject.id);
      return [{ op: "position.update", positionId, targetId: positionId, set: { reportsToPositionId: input.target.id } }];
    }
    if (input.interpretation === "create_position") {
      const positionId = crypto.randomUUID();
      // structural: optional value absent; empty string for typing
      const orgUnitId = this.positions.get(input.target.id)?.orgUnitId ?? "";
      return [
        { op: "position.create", positionId, targetId: positionId, set: { orgUnitId, reportsToPositionId: input.target.id, title: "New position" } },
        { op: "assignment.update", assignmentId: input.subject.id, targetId: input.subject.id, set: { positionId } },
      ];
    }
    if (input.interpretation === "temporary_reporting") {
      return [{ op: "assignment.update", assignmentId: input.subject.id, targetId: input.subject.id, set: { managerPositionId: input.target.id, temporary: "true" } }];
    }
    if (input.subject.type === "person_assignment" && input.target.type === "org_unit") {
      return [{ op: "assignment.update", assignmentId: input.subject.id, targetId: input.subject.id, set: { orgUnitId: input.target.id } }];
    }
    return [{ op: "assignment.update", assignmentId: input.subject.id, targetId: input.subject.id, set: { positionId: input.target.id } }];
  }

  private errorsFor(input: MoveInput, operations: Operation[]): Finding[] {
    const errors: Finding[] = [];
    const incoming = operations.filter((op) => op.op === "assignment.update" && typeof op.set?.positionId === "string");
    if (incoming.length === 0) return errors;
    const positionId = input.target.id;
    const box = this.positions.get(positionId);
    if (!box) return [{ code: "POSITION_UNKNOWN", message: "That position does not exist." }];
    const overlap = input.overlapApproved === true && Boolean(input.endDate);
    const used = this.holdersAt(positionId, input.effectiveDate).reduce((sum, row) => sum + hundredths(row.fte), 0);
    const added = incoming.reduce((sum, op) => {
      const holder = this.holders.find((row) => row.assignmentId === op.assignmentId);
      // structural: money string placeholder when input omits amount
      return sum + hundredths(holder?.fte ?? "1.00");
    }, 0);
    if (used + added > hundredths(box.fteBudget) && !overlap) {
      errors.push({ code: "OVER_FTE", message: "That position does not have room for this FTE." });
    }
    return errors;
  }

  private consequencesFor(input: MoveInput, operations: Operation[]): Consequence[] {
    const consequences: Consequence[] = [];
    if (operations.some((op) => op.op === "org_unit.move")) {
      const from = this.unitAt(input.subject.id, this.clock.today);
      const to = this.unitAt(input.target.id, this.clock.today);
      consequences.push({ kind: "approver", description: "Approval chains under this unit change." });
      consequences.push({ kind: "cost_centre", description: "Cost centres follow the unit from the effective date.", from: from?.costCentreId, to: to?.costCentreId });
      consequences.push({ kind: "task", description: "Security scopes for this subtree are reviewed." });
      consequences.push({ kind: "agreement", description: "Seniority groupings are recomputed from the effective date." });
      if (from && to && from.province !== to.province) {
        consequences.push({ kind: "tax_province", description: "The work province changes, so the tax province changes.", from: from.province, to: to.province });
        consequences.push({ kind: "location_province", description: "The establishment province changes.", from: from.province, to: to.province });
      }
      if (compareIsoDate(input.effectiveDate, this.clock.finalizedThrough) <= 0) {
        const count = this.peopleInUnit(input.subject.id, input.effectiveDate).length;
        consequences.push({ kind: "retro", description: `Retro pay will be requested for ${count} employees.` });
      }
    }
    if (compareIsoDate(input.effectiveDate, this.clock.today) < 0 && input.isCorrection === undefined) {
      consequences.push({ kind: "retro", description: "A past date needs a choice between a new fact and a correction." });
    }
    return consequences;
  }

  private interpretationsFor(input: MoveInput): boolean {
    if (input.subject.type !== "person_assignment" || input.target.type === "vacant_position" || input.target.type === "org_unit") return false;
    const holders = this.holdersAt(input.target.id, input.effectiveDate);
    return holders.length > 0;
  }

  private crossProvince(input: MoveInput): boolean {
    if (input.subject.type !== "org_unit") return false;
    const from = this.unitAt(input.subject.id, input.effectiveDate);
    const to = this.unitAt(input.target.id, input.effectiveDate);
    return Boolean(from && to && from.province !== to.province);
  }

  private peopleInUnit(unitId: string, asOf: string): string[] {
    const people = new Set<string>();
    for (const box of this.positions.values()) {
      if (box.orgUnitId !== unitId) continue;
      for (const holder of this.holdersAt(box.id, asOf)) people.add(holder.personId);
    }
    return [...people];
  }

  private reportParents(asOf: string): Map<string, string | null> {
    const parents = new Map<string, string | null>();
    for (const box of this.positions.values()) {
      const edge = [...this.reports].reverse().find((row) => row.positionId === box.id && covers(row, asOf, this.clock.knownAt));
      parents.set(box.id, edge?.reportsToPositionId ?? null);
    }
    return parents;
  }

  private overlayPlan(parents: Map<string, string | null>, planId: string, asOf: string): void {
    const plan = this.plans.get(planId);
    if (!plan) return;
    for (const move of plan.moves) {
      if (compareIsoDate(move.effectiveDate, asOf) > 0) continue;
      for (const op of move.operations) {
        if (op.op === "position.update" && op.positionId && typeof op.set?.reportsToPositionId === "string") {
          parents.set(op.positionId, op.set.reportsToPositionId);
        }
      }
    }
  }

  private holdersAt(positionId: string, asOf: string): Holder[] {
    return this.holders.filter((row) => row.positionId === positionId && covers(row, asOf, this.clock.knownAt));
  }

  private unitAt(id: string, asOf: string): UnitEdge | null {
    return [...this.units].reverse().find((row) => row.id === id && covers(row, asOf, this.clock.knownAt)) ?? null;
  }

  private positionOfAssignment(assignmentId: string): string {
    // structural: optional value absent; empty string for typing
    return this.holders.find((row) => row.assignmentId === assignmentId)?.positionId ?? "";
  }

  private spliceReports(positionId: string, reportsToPositionId: string | null, effectiveDate: string): void {
    for (const row of this.reports) {
      if (row.positionId !== positionId || row.supersededAt !== null) continue;
      if (compareIsoDate(row.validStart, effectiveDate) < 0 && (row.validEnd === null || compareIsoDate(row.validEnd, effectiveDate) > 0)) {
        row.validEnd = effectiveDate;
      } else if (compareIsoDate(row.validStart, effectiveDate) >= 0) {
        row.supersededAt = this.clock.knownAt;
      }
    }
    this.reports.push({
      positionId,
      reportsToPositionId,
      validStart: effectiveDate,
      validEnd: null,
      recordedAt: this.clock.knownAt,
      supersededAt: null,
    });
  }

  private spliceUnit(id: string, parentId: string | null, effectiveDate: string): void {
    const current = this.unitAt(id, effectiveDate) ?? this.units.find((row) => row.id === id);
    if (!current) return;
    if (compareIsoDate(current.validStart, effectiveDate) < 0) current.validEnd = effectiveDate;
    else current.supersededAt = this.clock.knownAt;
    this.units.push({
      ...current,
      parentId,
      validStart: effectiveDate,
      validEnd: null,
      recordedAt: this.clock.knownAt,
      supersededAt: null,
    });
  }

  private spliceHolder(assignmentId: string, positionId: string, effectiveDate: string, validEnd: string | null): void {
    const current = this.holders.find((row) => row.assignmentId === assignmentId && row.supersededAt === null && covers(row, effectiveDate, this.clock.knownAt));
    if (!current) return;
    if (compareIsoDate(current.validStart, effectiveDate) < 0) current.validEnd = effectiveDate;
    else current.supersededAt = this.clock.knownAt;
    this.holders.push({
      ...current,
      positionId,
      validStart: effectiveDate,
      validEnd,
      recordedAt: this.clock.knownAt,
      supersededAt: null,
    });
  }

  private mustPlan(planId: string): PlanRecord {
    const plan = this.plans.get(planId);
    if (!plan) throw new Error("PLAN_UNKNOWN");
    return plan;
  }
}

export function nextMonday(isoDate: string): string {
  const start = new Date(`${isoDate}T00:00:00.000Z`);
  const day = start.getUTCDay();
  const delta = day === 1 ? 7 : (8 - day) % 7;
  return addDays(isoDate, delta === 0 ? 7 : delta);
}

function emptyValidation(): { errors: Finding[]; warnings: Finding[]; consequences: Consequence[] } {
  return { errors: [], warnings: [], consequences: [] };
}

function covers(row: Slice, asOf: string, knownAt: string): boolean {
  if (row.validStart > asOf) return false;
  if (row.validEnd !== null && row.validEnd <= asOf) return false;
  if (row.recordedAt > knownAt) return false;
  if (row.supersededAt !== null && row.supersededAt <= knownAt) return false;
  return true;
}

function money(value: string): string {
  return Money.parse(value).toString();
}

function hundredths(value: string): number {
  return Number(money(value).replace(".", ""));
}
