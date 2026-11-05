import { maskSin, revealSin, type RoleGrant } from "@candohr/access";
import { createDevKms, envelopeDecrypt, envelopeEncrypt, type Envelope, type Kms } from "@candohr/keys";
import { addDays, CanDoError, compareIsoDate, Money } from "@candohr/shared";
import { assertSin } from "./sin.ts";
import type { HistoryEntry, PersonListItem, PositionView, ProfileView } from "./views.ts";

/**
 * Core HR records in memory (build-plan step 5).
 * The same operations will write through Hyperdrive, with query caching off, once
 * SUPABASE_DB_PASSWORD is available. This object does not open a database.
 */

export interface Finding {
  code: string;
  message: string;
  source?: string;
}

export interface ApprovalTask {
  role: string;
  status: "open";
}

interface Slice {
  validStart: string;
  validEnd: string | null;
  recordedAt: string;
  supersededAt: string | null;
}

interface OrgNode extends Slice {
  versionId: string;
  id: string;
  hierarchyId: string;
  levelCode: string;
  parentId: string | null;
  name: string;
}

interface ClosureEdge extends Slice {
  ancestorId: string;
  descendantId: string;
  depth: number;
}

interface PositionSlice extends Slice {
  versionId: string;
  status: "vacant" | "filled";
}

interface Position {
  id: string;
  orgUnitId: string;
  jobId: string | null;
  fteBudget: string;
  title: string;
  managerUserId: string | null;
  reportsToPositionId: string | null;
  mappedCostCentreId: string | null;
  versions: PositionSlice[];
}

interface CostOverride extends Slice {
  positionId: string;
  costCentreId: string;
  reason: string;
}

interface Person {
  id: string;
  legalName: string;
  preferredName: string;
  pendingLegalName: string | null;
  addressProvince: string | null;
  askWorkLocation: boolean;
}

interface Employment {
  id: string;
  personId: string;
  legalEntityId: string;
  status: "active" | "terminated";
  hireDate: string;
  continuousServiceDate: string;
  terminatedOn: string | null;
}

interface Assignment extends Slice {
  versionId: string;
  id: string;
  personId: string;
  employmentId: string;
  positionId: string | null;
  orgUnitId: string;
  locationId: string;
  jobId: string | null;
  type: string;
  status: string;
  primary: boolean;
  fte: string;
  rate: string;
  agreementId: string | null;
  managerAssignmentId: string | null;
  costCentreId: string | null;
  taxOverride: string | null;
}

interface Task {
  code: string;
  personId: string;
  assigneeUserId: string | null;
  choices: string[];
}

export interface HireInput {
  personId?: string;
  legalName: string;
  preferredName?: string;
  email?: string;
  legalEntityId: string;
  positionId: string;
  fte: string;
  locationId: string;
  rate: string;
  rateBasis: "hourly" | "salary";
  startDate: string;
  assignmentType?: string;
  primary?: boolean;
  endDate?: string | null;
  managerAssignmentId?: string | null;
  agreementId?: string | null;
  excluded?: boolean;
  exclusionReason?: string | null;
  overlapApproved?: boolean;
  employmentId?: string;
}

export interface AsOf {
  asOf: string;
  knownAt: string;
}

const GOVERNANCE: { domain: string; rule: "combined" | "per_assignment" | "per_agreement" | "primary_only" }[] = [
  { domain: "statutory_withholding", rule: "combined" },
  { domain: "province_of_employment", rule: "per_assignment" },
  { domain: "benefits", rule: "combined" },
  { domain: "seniority", rule: "per_agreement" },
  { domain: "directory", rule: "primary_only" },
];

export class CoreHr {
  readonly errorsOnLast: Finding[] = [];
  readonly tasks: Task[] = [];
  readonly events: { type: string; subjectId: string; effectiveDate: string }[] = [];
  readonly operations: { op: string }[] = [];
  readonly approvals: ApprovalTask[] = [];
  readonly audits: ReturnType<typeof revealSin>["audit"][] = [];
  private readonly kms: Kms;
  private readonly people = new Map<string, Person>();
  private readonly sin = new Map<string, Envelope>();
  private readonly employments: Employment[] = [];
  private readonly assignments: Assignment[] = [];
  private readonly positions = new Map<string, Position>();
  private readonly nodes: OrgNode[] = [];
  private readonly closure: ClosureEdge[] = [];
  private readonly overrides: CostOverride[] = [];
  private readonly locations = new Map<string, { id: string; province: string; name: string }>();
  private readonly floors = new Map<string, { minimumHourly: string; source: string }>();
  private readonly jobs = new Map<string, { id: string; title: string; bargainingUnit: string | null }>();
  private readonly agreements = new Map<string, { id: string; unitCode: string; bridgeWithinDays: number | null; challengeDays: number }>();
  private readonly unitAgreement = new Map<string, string>();
  private readonly levels = new Map<string, { code: string; allowedParentCodes: string[] }>();
  private readonly orgNames = new Map<string, string>();
  private readonly provision: { personId: string; email: string; due: string; done: boolean }[] = [];
  private readonly sinMask = new Map<string, string>();
  readonly publishedLists: { agreementId: string; postingDate: string; challengeEnds: string; order: string[] }[] = [];
  mode: "light" | "position" = "position";
  private readonly clock: { today: string; knownAt: string; leadDays: number };

  constructor(clock: { today: string; knownAt: string; leadDays: number }, kms?: Kms) {
    this.clock = clock;
    this.kms = kms ?? createDevKms("core-dev");
  }

  addLocation(input: { id: string; province: string; name?: string; minimumHourly?: string; wageSource?: string }): void {
    this.locations.set(input.id, { id: input.id, province: input.province, name: input.name ?? input.province });
    if (input.minimumHourly && input.wageSource) {
      this.floors.set(input.id, { minimumHourly: input.minimumHourly, source: input.wageSource });
    }
  }

  addJob(input: { id: string; title: string; bargainingUnit: string | null }): void {
    this.jobs.set(input.id, input);
  }

  addAgreement(input: { id: string; unitCode: string; bridgeWithinDays?: number | null; challengeDays?: number }): void {
    this.agreements.set(input.id, {
      id: input.id,
      unitCode: input.unitCode,
      bridgeWithinDays: input.bridgeWithinDays ?? null,
      // structural: missing numeric coalesces to zero for arithmetic
      challengeDays: input.challengeDays ?? 0,
    });
    this.unitAgreement.set(input.unitCode, input.id);
  }

  addLevelType(input: { code: string; allowedParentCodes: string[] }): void {
    this.levels.set(input.code, input);
  }

  addPosition(input: {
    id: string;
    orgUnitId: string;
    jobId?: string | null;
    fteBudget: string;
    title?: string;
    managerUserId?: string | null;
    validStart?: string;
    mappedCostCentreId?: string | null;
  }): void {
    // structural: as-of or demo date when caller omits effective date
    const start = input.validStart ?? "2020-01-01";
    this.orgNames.set(input.orgUnitId, this.orgNames.get(input.orgUnitId) ?? input.orgUnitId);
    this.positions.set(input.id, {
      id: input.id,
      orgUnitId: input.orgUnitId,
      jobId: input.jobId ?? null,
      fteBudget: money(input.fteBudget),
      // structural: optional value absent; empty string for typing
      title: input.title ?? this.jobs.get(input.jobId ?? "")?.title ?? "Position",
      managerUserId: input.managerUserId ?? null,
      reportsToPositionId: null,
      mappedCostCentreId: input.mappedCostCentreId ?? null,
      versions: [slice({ status: "vacant", validStart: start, recordedAt: "2020-01-01T00:00:00.000Z" })],
    });
  }

  addOrgNode(input: {
    id: string;
    hierarchyId: string;
    levelCode: string;
    parentId: string | null;
    name: string;
    effectiveDate: string;
  }): Finding | null {
    const level = this.levels.get(input.levelCode);
    if (!level) return { code: "LEVEL_UNKNOWN", message: "That level is not defined for this organization." };
    if (input.parentId) {
      const parent = this.nodeAt(input.parentId, input.effectiveDate, this.clock.knownAt);
      const parentLevel = parent?.levelCode;
      if (!parentLevel || !level.allowedParentCodes.includes(parentLevel)) {
        return { code: "LEVEL_NOT_ALLOWED", message: "That level cannot sit under the chosen parent." };
      }
    }
    this.nodes.push({
      versionId: crypto.randomUUID(),
      id: input.id,
      hierarchyId: input.hierarchyId,
      levelCode: input.levelCode,
      parentId: input.parentId,
      name: input.name,
      validStart: input.effectiveDate,
      validEnd: null,
      recordedAt: this.clock.knownAt,
      supersededAt: null,
    });
    this.orgNames.set(input.id, input.name);
    this.rebuildClosure();
    this.operations.push({ op: "org_unit.create" });
    return null;
  }

  hire(input: HireInput): { ok: boolean; errors: Finding[]; warnings: Finding[]; personId?: string; assignmentId?: string } {
    const errors = this.hireErrors(input, false);
    if (errors.length > 0) return { ok: false, errors, warnings: [] };
    return { ok: true, errors: [], warnings: [], ...this.applyHire(input, false) };
  }

  addAssignment(input: HireInput): { ok: boolean; errors: Finding[]; assignmentId?: string } {
    const employmentId = input.employmentId ?? this.employments.find((row) => row.personId === input.personId && row.status === "active")?.id;
    const next = { ...input, employmentId };
    const errors = this.hireErrors(next, true);
    if (errors.length > 0) return { ok: false, errors };
    const applied = this.applyHire(next, true);
    return { ok: true, errors: [], assignmentId: applied.assignmentId };
  }

  proposePosition(input: { orgUnitId: string; midpoint: string; burden: string; remainingAnnual: string; fteBudget?: string }): {
    warnings: Finding[];
    approvals: ApprovalTask[];
    positionId: string;
  } {
    const cost = Money.parse(input.midpoint).plus(Money.parse(input.burden)).toString();
    const warnings: Finding[] = [];
    const approvals: ApprovalTask[] = [];
    if (greater(cost, money(input.remainingAnnual))) {
      warnings.push({ code: "OVER_BUDGET", message: "This position costs more than the unit has left." });
      approvals.push({ role: "finance", status: "open" });
      this.approvals.push(approvals[0] as ApprovalTask);
    }
    const positionId = crypto.randomUUID();
    // structural: money string placeholder when input omits amount
    this.addPosition({ id: positionId, orgUnitId: input.orgUnitId, fteBudget: input.fteBudget ?? "1.00" });
    this.operations.push({ op: "position.create" });
    return { warnings, approvals, positionId };
  }

  rehire(input: { personId: string; legalEntityId: string; startDate: string; agreementId: string; positionId: string; locationId: string; rate: string }): { ok: boolean; employmentId?: string; continuousServiceDate?: string; errors: Finding[] } {
    const person = this.people.get(input.personId);
    const previous = [...this.employments].reverse().find((row) => row.personId === input.personId && row.status === "terminated");
    if (!person || !previous || !previous.terminatedOn) {
      return { ok: false, errors: [{ code: "NOT_TERMINATED", message: "Rehire starts from a person who has left." }] };
    }
    const agreement = this.agreements.get(input.agreementId);
    const gap = daysBetween(previous.terminatedOn, input.startDate);
    const bridge = agreement?.bridgeWithinDays !== null && agreement?.bridgeWithinDays !== undefined && gap <= agreement.bridgeWithinDays;
    const continuousServiceDate = bridge ? previous.continuousServiceDate : input.startDate;
    const employmentId = crypto.randomUUID();
    this.employments.push({
      id: employmentId,
      personId: input.personId,
      legalEntityId: input.legalEntityId,
      status: "active",
      hireDate: input.startDate,
      continuousServiceDate,
      terminatedOn: null,
    });
    const hired = this.hire({
      personId: input.personId,
      legalName: person.legalName,
      preferredName: person.preferredName,
      legalEntityId: input.legalEntityId,
      positionId: input.positionId,
      fte: "1.00",
      locationId: input.locationId,
      rate: input.rate,
      rateBasis: "salary",
      startDate: input.startDate,
      employmentId,
      agreementId: input.agreementId,
    });
    if (!hired.ok) return { ok: false, errors: hired.errors };
    this.operations.push({ op: "employment.rehire" });
    return { ok: true, errors: [], employmentId, continuousServiceDate };
  }

  terminate(input: { employmentId: string; effectiveDate: string; managerUserId: string }): void {
    const employment = this.employments.find((row) => row.id === input.employmentId);
    if (!employment) throw new CanDoError("EMPLOYMENT_UNKNOWN");
    employment.status = "terminated";
    employment.terminatedOn = input.effectiveDate;
    const open = this.currentAssignments(employment.personId, input.effectiveDate, this.clock.knownAt).filter((row) => row.employmentId === input.employmentId);
    for (const row of open) {
      this.closeAssignment(row, input.effectiveDate, "ended");
      if (row.positionId) {
        this.setPositionStatus(row.positionId, "vacant", input.effectiveDate);
        this.events.push({ type: "position.vacated", subjectId: row.positionId, effectiveDate: input.effectiveDate });
      }
    }
    this.tasks.push({
      code: "backfill",
      personId: employment.personId,
      assigneeUserId: input.managerUserId,
      choices: ["backfill", "modify", "eliminate"],
    });
    this.events.push({ type: "employment.terminated", subjectId: employment.id, effectiveDate: input.effectiveDate });
    this.operations.push({ op: "employment.terminate" });
  }

  moveOrgUnit(input: { id: string; newParentId: string; effectiveDate: string }): Finding | null {
    const current = this.nodeAt(input.id, input.effectiveDate, this.clock.knownAt);
    if (!current) return { code: "ORG_UNKNOWN", message: "That unit does not exist on this date." };
    const level = this.levels.get(current.levelCode);
    const parent = this.nodeAt(input.newParentId, input.effectiveDate, this.clock.knownAt);
    if (!level || !parent || !level.allowedParentCodes.includes(parent.levelCode)) {
      return { code: "LEVEL_NOT_ALLOWED", message: "That level cannot sit under the chosen parent." };
    }
    const before = this.assignments.map((row) => `${row.id}:${row.orgUnitId}:${row.versionId}`).join("|");
    if (compareIsoDate(current.validStart, input.effectiveDate) < 0) current.validEnd = input.effectiveDate;
    else current.supersededAt = this.clock.knownAt;
    this.nodes.push({
      ...current,
      versionId: crypto.randomUUID(),
      parentId: input.newParentId,
      validStart: input.effectiveDate,
      validEnd: null,
      recordedAt: this.clock.knownAt,
      supersededAt: null,
    });
    this.rebuildClosure();
    this.operations.push({ op: "org_unit.move" });
    const after = this.assignments.map((row) => `${row.id}:${row.orgUnitId}:${row.versionId}`).join("|");
    if (before !== after) throw new CanDoError("ASSIGNMENT_REWRITTEN");
    return null;
  }

  enablePositionMode(): { before: string[]; after: string[] } {
    const before = this.personEdges();
    const positionByAssignment = new Map<string, string>();
    const current = this.assignments.filter((row) => row.supersededAt === null && row.status !== "ended");
    for (const row of current) {
      const positionId = crypto.randomUUID();
      positionByAssignment.set(row.id, positionId);
      this.addPosition({
        id: positionId,
        orgUnitId: row.orgUnitId,
        jobId: row.jobId,
        fteBudget: row.fte,
        // structural: optional value absent; empty string for typing
        title: this.jobs.get(row.jobId ?? "")?.title ?? "Position",
        validStart: row.validStart,
      });
      this.setPositionStatus(positionId, "filled", row.validStart);
      row.positionId = positionId;
    }
    for (const row of current) {
      const positionId = positionByAssignment.get(row.id);
      const managerPosition = row.managerAssignmentId ? positionByAssignment.get(row.managerAssignmentId) : null;
      const position = positionId ? this.positions.get(positionId) : undefined;
      if (position && managerPosition) position.managerUserId = managerPosition;
    }
    for (const row of current) {
      const position = row.positionId ? this.positions.get(row.positionId) : undefined;
      const managerAssignment = row.managerAssignmentId ? current.find((item) => item.id === row.managerAssignmentId) : undefined;
      if (position) position.reportsToPositionId = managerAssignment?.positionId ?? null;
    }
    this.mode = "position";
    this.operations.push({ op: "tenant.enable_position_mode" });
    const after = current.map((row) => {
      const position = row.positionId ? this.positions.get(row.positionId) : undefined;
      const managerPosition = position?.reportsToPositionId ? this.positions.get(position.reportsToPositionId) : undefined;
      const managerAssignment = current.find((item) => item.positionId === managerPosition?.id);
      // structural: optional value absent; empty string for typing
      return `${row.personId}->${managerAssignment?.personId ?? ""}`;
    });
    return { before, after };
  }

  setAddress(input: { personId: string; province: string; workLocationChanged?: boolean; newLocationId?: string; hrOverride?: { province: string; reason: string } }): { askWorkLocation: boolean; taxProvince: string | null } {
    const person = this.mustPerson(input.personId);
    const changed = person.addressProvince !== null && person.addressProvince !== input.province;
    person.addressProvince = input.province;
    person.askWorkLocation = changed && input.workLocationChanged === undefined && !input.hrOverride;
    if (input.hrOverride) {
      if (!input.hrOverride.reason.trim()) throw new CanDoError("REASON_REQUIRED");
      this.setTaxOverride(input.personId, input.hrOverride.province, input.hrOverride.reason);
    } else if (input.workLocationChanged && input.newLocationId) {
      const location = this.locations.get(input.newLocationId);
      if (!location) throw new CanDoError("LOCATION_UNKNOWN");
      for (const row of this.currentAssignments(input.personId, this.clock.today, this.clock.knownAt)) {
        this.replaceAssignment(row, { locationId: input.newLocationId, costCentreId: row.costCentreId });
      }
    }
    return { askWorkLocation: person.askWorkLocation, taxProvince: this.taxProvince(input.personId, this.clock.today, this.clock.knownAt) };
  }

  setPreferredName(personId: string, preferredName: string): void {
    this.mustPerson(personId).preferredName = preferredName;
    this.operations.push({ op: "person.update" });
  }

  requestLegalName(input: { personId: string; legalName: string; documentId?: string | null }): Finding | null {
    if (!input.documentId) return { code: "LEGAL_NAME_EVIDENCE", message: "A legal name change needs an uploaded document." };
    const person = this.mustPerson(input.personId);
    person.pendingLegalName = input.legalName;
    this.approvals.push({ role: "hr", status: "open" });
    return null;
  }

  approveLegalName(personId: string): void {
    const person = this.mustPerson(personId);
    if (!person.pendingLegalName) throw new CanDoError("NOTHING_TO_APPROVE");
    person.legalName = person.pendingLegalName;
    person.pendingLegalName = null;
  }

  async setSin(personId: string, sin: string): Promise<string> {
    this.mustPerson(personId);
    const digits = assertSin(sin);
    const masked = maskSin(digits);
    this.sin.set(personId, await envelopeEncrypt(this.kms, new TextEncoder().encode(digits)));
    this.sinMask.set(personId, masked);
    return masked;
  }

  async revealPersonSin(personId: string, reason: string, grants: readonly RoleGrant[]): Promise<string> {
    const envelope = this.sin.get(personId);
    if (!envelope) throw new CanDoError("SIN");
    const digits = new TextDecoder().decode(await envelopeDecrypt(this.kms, envelope));
    const revealed = revealSin({ personId, sin: digits, reason, grants });
    this.audits.push(revealed.audit);
    return revealed.sin;
  }

  publishSeniority(input: { agreementId: string; postingDate: string; rows: { personId: string; seniorityDate: string; hireDate: string; lot: string }[] }): { order: string[]; challengeEnds: string } {
    const agreement = this.agreements.get(input.agreementId);
    if (!agreement) throw new CanDoError("AGREEMENT_UNKNOWN");
    const order = [...input.rows].sort((a, b) => {
      const seniority = compareIsoDate(a.seniorityDate, b.seniorityDate);
      if (seniority !== 0) return seniority;
      const hire = compareIsoDate(a.hireDate, b.hireDate);
      if (hire !== 0) return hire;
      return a.lot < b.lot ? -1 : a.lot > b.lot ? 1 : 0;
    });
    const challengeEnds = addDays(input.postingDate, agreement.challengeDays);
    this.publishedLists.push({
      agreementId: input.agreementId,
      postingDate: input.postingDate,
      challengeEnds,
      order: order.map((row) => row.personId),
    });
    return { order: order.map((row) => row.personId), challengeEnds };
  }

  startActing(input: {
    homeAssignmentId: string;
    positionId: string;
    rate: string;
    costCentreId: string;
    startDate: string;
    endDate: string;
  }): { actingAssignmentId: string } {
    const home = this.assignments.find((row) => row.id === input.homeAssignmentId && row.supersededAt === null && covers(row, input.startDate, this.clock.knownAt));
    if (!home) throw new CanDoError("ASSIGNMENT_UNKNOWN");
    const previousEnd = home.validEnd;
    if (compareIsoDate(home.validStart, input.startDate) < 0) home.validEnd = input.startDate;
    else home.supersededAt = this.clock.knownAt;
    const carried = { ...home, recordedAt: this.clock.knownAt, supersededAt: null as string | null };
    this.assignments.push({
      ...carried,
      versionId: crypto.randomUUID(),
      status: "suspended_for_acting",
      validStart: input.startDate,
      validEnd: input.endDate,
    });
    this.assignments.push({
      ...carried,
      versionId: crypto.randomUUID(),
      status: "active",
      validStart: input.endDate,
      validEnd: previousEnd,
    });
    const actingAssignmentId = crypto.randomUUID();
    this.assignments.push({
      ...carried,
      versionId: crypto.randomUUID(),
      id: actingAssignmentId,
      positionId: input.positionId,
      type: "acting",
      status: "active",
      primary: false,
      rate: money(input.rate),
      costCentreId: input.costCentreId,
      validStart: input.startDate,
      validEnd: input.endDate,
    });
    this.assignments.push({
      ...carried,
      versionId: crypto.randomUUID(),
      id: actingAssignmentId,
      positionId: input.positionId,
      type: "acting",
      status: "ended",
      primary: false,
      rate: money(input.rate),
      costCentreId: input.costCentreId,
      validStart: input.endDate,
      validEnd: null,
    });
    this.setPositionStatus(input.positionId, "filled", input.startDate);
    this.setPositionStatus(input.positionId, "vacant", input.endDate);
    this.operations.push({ op: "assignment.suspend_for_acting" });
    return { actingAssignmentId };
  }

  overrideCostCentre(input: { positionId: string; costCentreId: string; reason?: string | null; effectiveDate: string }): Finding | null {
    if (!input.reason?.trim()) return { code: "COST_CENTRE_REASON", message: "A cost centre override needs a reason." };
    this.overrides.push({
      positionId: input.positionId,
      costCentreId: input.costCentreId,
      reason: input.reason.trim(),
      validStart: input.effectiveDate,
      validEnd: null,
      recordedAt: this.clock.knownAt,
      supersededAt: null,
    });
    return null;
  }

  glCostCentre(positionId: string, asOf: string, knownAt: string): string | null {
    const override = [...this.overrides].reverse().find((row) => row.positionId === positionId && covers(row, asOf, knownAt));
    if (override) return override.costCentreId;
    return this.positions.get(positionId)?.mappedCostCentreId ?? null;
  }

  async runProvisioning(now: string, admin: { createUser(input: { email: string; externalId: string | null; active: boolean }): Promise<{ id: string }> }): Promise<number> {
    let created = 0;
    for (const row of this.provision) {
      if (row.done || row.due > now.slice(0, 10)) continue;
      await admin.createUser({ email: row.email, externalId: row.personId, active: true });
      row.done = true;
      created += 1;
    }
    return created;
  }

  peopleList(query: AsOf): PersonListItem[] {
    return [...this.people.values()].map((person) => {
      const assignment = this.currentAssignments(person.id, query.asOf, query.knownAt).find((row) => row.primary) ?? this.currentAssignments(person.id, query.asOf, query.knownAt)[0];
      return {
        id: person.id,
        preferredName: person.preferredName,
        // structural: optional value absent; empty string for typing
        title: assignment?.jobId ? this.jobs.get(assignment.jobId)?.title ?? "" : "",
        orgUnitName: assignment ? this.orgNames.get(assignment.orgUnitId) ?? assignment.orgUnitId : "",
      };
    });
  }

  profile(personId: string, query: AsOf): ProfileView | null {
    const person = this.people.get(personId);
    if (!person) return null;
    const assignments = this.currentAssignments(personId, query.asOf, query.knownAt);
    return {
      id: person.id,
      legalName: person.legalName,
      preferredName: person.preferredName,
      sinMasked: this.sinMask.get(personId) ?? null,
      askWorkLocation: person.askWorkLocation,
      taxProvince: this.taxProvince(personId, query.asOf, query.knownAt),
      assignments: assignments.map((row) => ({
        id: row.id,
        type: row.type,
        status: row.status,
        primary: row.primary,
        fte: row.fte,
        rate: row.rate,
        agreementId: row.agreementId,
        managerName: this.managerName(row, query),
        orgUnitName: this.orgNames.get(row.orgUnitId) ?? row.orgUnitId,
        costCentreId: row.costCentreId,
      })),
      history: this.history("person", personId),
    };
  }

  async maskedSin(personId: string): Promise<string | null> {
    const envelope = this.sin.get(personId);
    if (!envelope) return null;
    const digits = new TextDecoder().decode(await envelopeDecrypt(this.kms, envelope));
    return maskSin(digits);
  }

  positionView(positionId: string, query: AsOf): PositionView | null {
    const position = this.positions.get(positionId);
    if (!position) return null;
    const version = this.positionSlice(position, query.asOf, query.knownAt);
    const holder = this.assignments.find((row) => row.positionId === positionId && row.status === "active" && covers(row, query.asOf, query.knownAt));
    return {
      id: position.id,
      title: position.title,
      // structural: in-memory world seed status for tests
      status: version?.status ?? "vacant",
      fteBudget: position.fteBudget,
      holderName: holder ? this.people.get(holder.personId)?.preferredName ?? null : null,
      orgUnitName: this.orgNames.get(position.orgUnitId) ?? position.orgUnitId,
    };
  }

  history(kind: "person" | "position" | "assignment", id: string): HistoryEntry[] {
    if (kind === "position") {
      const position = this.positions.get(id);
      return (position?.versions ?? []).map((row) => ({ label: row.status, date: row.validStart }));
    }
    if (kind === "assignment") {
      return this.assignments.filter((row) => row.id === id).map((row) => ({ label: row.status, date: row.validStart }));
    }
    const person = this.people.get(id);
    const hires = this.employments.filter((row) => row.personId === id).map((row) => ({ label: row.status, date: row.hireDate }));
    return person ? [{ label: person.legalName, date: this.clock.today }, ...hires] : [];
  }

  subtree(nodeId: string, query: AsOf): string[] {
    return this.closure
      .filter((row) => row.ancestorId === nodeId && row.depth > 0 && covers(row, query.asOf, query.knownAt))
      .map((row) => row.descendantId);
  }

  reportingChain(personId: string, query: AsOf): string[] {
    const assignment = this.currentAssignments(personId, query.asOf, query.knownAt)[0];
    if (!assignment) return [];
    const chain: string[] = [];
    let current: string | null = assignment.orgUnitId;
    const guard = new Set<string>();
    while (current && !guard.has(current)) {
      guard.add(current);
      chain.push(current);
      current = this.nodeAt(current, query.asOf, query.knownAt)?.parentId ?? null;
    }
    return chain;
  }

  governing(personId: string, domain: string, query: AsOf): string[] {
    // structural: docs/17 domain_governance demo row, not a hard-coded route
    const rule = GOVERNANCE.find((row) => row.domain === domain)?.rule ?? "per_assignment";
    const rows = this.currentAssignments(personId, query.asOf, query.knownAt).filter((row) => row.status === "active" || row.status === "suspended_for_acting");
    if (rule === "primary_only") return rows.filter((row) => row.primary).map((row) => row.id);
    return rows.map((row) => row.id);
  }

  governanceTable(): readonly { domain: string; rule: string }[] {
    return GOVERNANCE;
  }

  assignmentCount(): number {
    return this.assignments.length;
  }

  linkManager(assignmentId: string, managerAssignmentId: string): void {
    const row = this.assignments.find((item) => item.id === assignmentId && item.supersededAt === null);
    if (!row) throw new CanDoError("ASSIGNMENT_UNKNOWN");
    row.managerAssignmentId = managerAssignmentId;
  }

  seedHolders(input: { orgUnitId: string; count: number; locationId: string }): void {
    // structural: loop index or iteration bound, not a business default
    for (let index = 0; index < input.count; index += 1) {
      const personId = `person-${input.orgUnitId}-${index}`;
      const employmentId = `employment-${personId}`;
      this.people.set(personId, {
        id: personId,
        legalName: `Person ${index}`,
        preferredName: `Person ${index}`,
        pendingLegalName: null,
        addressProvince: null,
        askWorkLocation: false,
      });
      this.employments.push({
        id: employmentId,
        personId,
        legalEntityId: "legal-1",
        status: "active",
        hireDate: "2020-01-01",
        continuousServiceDate: "2020-01-01",
        terminatedOn: null,
      });
      this.assignments.push({
        versionId: `seed-${personId}`,
        id: `assignment-${personId}`,
        personId,
        employmentId,
        positionId: null,
        orgUnitId: input.orgUnitId,
        locationId: input.locationId,
        jobId: null,
        type: "regular",
        status: "active",
        primary: true,
        fte: "1.00",
        rate: "1.00",
        agreementId: null,
        managerAssignmentId: null,
        costCentreId: null,
        taxOverride: null,
        validStart: "2020-01-01",
        validEnd: null,
        recordedAt: "2020-01-01T00:00:00.000Z",
        supersededAt: null,
      });
    }
  }

  private hireErrors(input: HireInput, existingPerson: boolean): Finding[] {
    const errors: Finding[] = [];
    const position = this.positions.get(input.positionId);
    if (!position) errors.push({ code: "POSITION_UNKNOWN", message: "That position does not exist." });
    const location = this.locations.get(input.locationId);
    if (!location) errors.push({ code: "LOCATION_UNKNOWN", message: "That location does not exist." });
    if (input.rateBasis === "hourly") {
      const floor = this.floors.get(input.locationId);
      if (floor && greater(floor.minimumHourly, input.rate)) {
        errors.push({
          code: "BELOW_MINIMUM_WAGE",
          message: "The rate is below the minimum for this location.",
          source: floor.source,
        });
      }
    }
    if (position) {
      const holders = this.fteInUse(position.id, input.startDate);
      const next = holders + hundredths(input.fte);
      const budget = hundredths(position.fteBudget);
      const overlap = input.assignmentType === "overlap" && Boolean(input.endDate) && input.overlapApproved === true;
      if (next > budget && !overlap) errors.push({ code: "OVER_FTE", message: "That position does not have room for this FTE." });
    }
    // structural: optional value absent; empty string for typing
    if (existingPerson && !this.people.has(input.personId ?? "")) {
      errors.push({ code: "PERSON_UNKNOWN", message: "That person does not exist." });
    }
    if (input.primary !== false && existingPerson) {
      // structural: optional value absent; empty string for typing
      const already = this.currentAssignments(input.personId ?? "", input.startDate, this.clock.knownAt).some((row) => row.primary && row.status === "active");
      if (already && input.primary === true) errors.push({ code: "TWO_PRIMARY", message: "Only one assignment can be primary." });
    }
    if (input.excluded && !input.exclusionReason?.trim()) {
      errors.push({ code: "AGREEMENT_EXCLUSION_REASON", message: "An exclusion from the agreement needs a reason." });
    }
    return errors;
  }

  private applyHire(input: HireInput, existingPerson: boolean): { personId: string; assignmentId: string } {
    const personId = input.personId ?? crypto.randomUUID();
    if (!existingPerson || !this.people.has(personId)) {
      this.people.set(personId, {
        id: personId,
        legalName: input.legalName,
        preferredName: input.preferredName ?? input.legalName,
        pendingLegalName: null,
        addressProvince: null,
        askWorkLocation: false,
      });
    }
    const employmentId = input.employmentId ?? crypto.randomUUID();
    if (!this.employments.some((row) => row.id === employmentId)) {
      this.employments.push({
        id: employmentId,
        personId,
        legalEntityId: input.legalEntityId,
        status: "active",
        hireDate: input.startDate,
        continuousServiceDate: input.startDate,
        terminatedOn: null,
      });
    }
    const position = this.positions.get(input.positionId);
    const job = position?.jobId ? this.jobs.get(position.jobId) : undefined;
    let agreementId = input.agreementId ?? null;
    if (!agreementId && job?.bargainingUnit) agreementId = this.unitAgreement.get(job.bargainingUnit) ?? null;
    const hasPrimary = this.currentAssignments(personId, input.startDate, this.clock.knownAt).some((row) => row.primary && row.status === "active");
    const assignmentId = crypto.randomUUID();
    this.assignments.push({
      versionId: crypto.randomUUID(),
      id: assignmentId,
      personId,
      employmentId,
      positionId: input.positionId,
      // structural: optional value absent; empty string for typing
      orgUnitId: position?.orgUnitId ?? "",
      locationId: input.locationId,
      jobId: position?.jobId ?? null,
      // structural: test fixture employment metadata
      type: input.assignmentType ?? "regular",
      status: "active",
      primary: input.primary ?? !hasPrimary,
      fte: money(input.fte),
      rate: money(input.rate),
      agreementId,
      managerAssignmentId: input.managerAssignmentId ?? null,
      costCentreId: null,
      taxOverride: null,
      validStart: input.startDate,
      validEnd: input.endDate ?? null,
      recordedAt: this.clock.knownAt,
      supersededAt: null,
    });
    this.setPositionStatus(input.positionId, "filled", input.startDate);
    const province = this.locations.get(input.locationId)?.province;
    if (province) {
      this.tasks.push({ code: `TD1${province}`, personId, assigneeUserId: null, choices: [] });
    }
    if (!existingPerson) {
      this.events.push({ type: "employment.hired", subjectId: employmentId, effectiveDate: input.startDate });
    }
    this.events.push({ type: "position.changed", subjectId: input.positionId, effectiveDate: input.startDate });
    if (input.email) {
      this.provision.push({
        personId,
        email: input.email,
        due: addDays(input.startDate, -this.clock.leadDays),
        done: false,
      });
    }
    this.operations.push({ op: existingPerson ? "assignment.create" : "employment.hire" });
    return { personId, assignmentId };
  }

  private setTaxOverride(personId: string, province: string, reason: string): void {
    for (const row of this.currentAssignments(personId, this.clock.today, this.clock.knownAt)) {
      this.replaceAssignment(row, { locationId: row.locationId, costCentreId: row.costCentreId, taxOverride: `${province}|${reason}` });
    }
  }

  private replaceAssignment(row: Assignment, patch: { locationId: string; costCentreId: string | null; taxOverride?: string }): void {
    const end = row.validEnd;
    row.supersededAt = this.clock.knownAt;
    this.assignments.push({
      ...row,
      versionId: crypto.randomUUID(),
      locationId: patch.locationId,
      costCentreId: patch.costCentreId,
      taxOverride: patch.taxOverride ?? row.taxOverride,
      validStart: row.validStart,
      validEnd: end,
      recordedAt: this.clock.knownAt,
      supersededAt: null,
    });
  }

  private taxProvince(personId: string, asOf: string, knownAt: string): string | null {
    const row = this.currentAssignments(personId, asOf, knownAt)[0];
    if (!row) return null;
    if (row.taxOverride) return row.taxOverride.split("|")[0] ?? null;
    return this.locations.get(row.locationId)?.province ?? null;
  }

  private fteInUse(positionId: string, asOf: string): number {
    return this.assignments
      .filter((row) => row.positionId === positionId && row.supersededAt === null && covers(row, asOf, this.clock.knownAt) && row.status === "active")
      .reduce((sum, row) => sum + hundredths(row.fte), 0);
  }

  private setPositionStatus(positionId: string, status: "vacant" | "filled", effectiveDate: string): void {
    const position = this.positions.get(positionId);
    if (!position) return;
    const current = [...position.versions].reverse().find((row) => row.supersededAt === null && covers(row, effectiveDate, this.clock.knownAt));
    if (!current) return;
    if (compareIsoDate(current.validStart, effectiveDate) < 0) current.validEnd = effectiveDate;
    else current.supersededAt = this.clock.knownAt;
    position.versions.push(slice({ status, validStart: effectiveDate, recordedAt: this.clock.knownAt }));
  }

  private closeAssignment(row: Assignment, effectiveDate: string, status: string): void {
    const previousEnd = row.validEnd;
    if (compareIsoDate(row.validStart, effectiveDate) < 0) row.validEnd = effectiveDate;
    else row.supersededAt = this.clock.knownAt;
    this.assignments.push({
      ...row,
      versionId: crypto.randomUUID(),
      status,
      validStart: effectiveDate,
      validEnd: previousEnd,
      recordedAt: this.clock.knownAt,
      supersededAt: null,
    });
  }

  private currentAssignments(personId: string, asOf: string, knownAt: string): Assignment[] {
    const rows = this.assignments.filter((row) => row.personId === personId && covers(row, asOf, knownAt));
    const byId = new Map<string, Assignment>();
    for (const row of rows) byId.set(row.id, row);
    return [...byId.values()];
  }

  private positionSlice(position: Position, asOf: string, knownAt: string): PositionSlice | null {
    return [...position.versions].reverse().find((row) => covers(row, asOf, knownAt)) ?? null;
  }

  private nodeAt(id: string, asOf: string, knownAt: string): OrgNode | null {
    return [...this.nodes].reverse().find((row) => row.id === id && covers(row, asOf, knownAt)) ?? null;
  }

  private managerName(row: Assignment, query: AsOf): string | null {
    if (!row.managerAssignmentId) return null;
    const manager = this.assignments.find((item) => item.id === row.managerAssignmentId && covers(item, query.asOf, query.knownAt));
    return manager ? this.people.get(manager.personId)?.preferredName ?? null : null;
  }

  private mustPerson(id: string): Person {
    const person = this.people.get(id);
    if (!person) throw new CanDoError("PERSON_UNKNOWN");
    return person;
  }

  private personEdges(): string[] {
    return this.assignments
      .filter((row) => row.supersededAt === null && row.status !== "ended")
      .map((row) => {
        const manager = row.managerAssignmentId ? this.assignments.find((item) => item.id === row.managerAssignmentId) : undefined;
        // structural: optional value absent; empty string for typing
        return `${row.personId}->${manager?.personId ?? ""}`;
      });
  }

  private rebuildClosure(): void {
    for (const row of this.closure) {
      if (row.supersededAt === null) row.supersededAt = this.clock.knownAt;
    }
    const bounds = [...new Set(this.nodes.filter((row) => row.supersededAt === null).flatMap((row) => [row.validStart, row.validEnd].filter((value): value is string => value !== null)))].sort();
    const starts = [...new Set(this.nodes.filter((row) => row.supersededAt === null).map((row) => row.validStart))].sort();
    // structural: loop index or iteration bound, not a business default
    for (let index = 0; index < starts.length; index += 1) {
      const validStart = starts[index] as string;
      const validEnd = starts[index + 1] ?? null;
      const visible = this.nodes.filter((row) => row.supersededAt === null && row.validStart <= validStart && (row.validEnd === null || row.validEnd > validStart));
      const parentOf = new Map<string, string | null>();
      for (const row of visible) parentOf.set(row.id, row.parentId);
      for (const id of parentOf.keys()) {
        let parent = parentOf.get(id) ?? null;
        let depth = 1;
        const seen = new Set<string>([id]);
        while (parent && !seen.has(parent)) {
          seen.add(parent);
          this.closure.push({
            ancestorId: parent,
            descendantId: id,
            depth,
            validStart,
            validEnd,
            recordedAt: this.clock.knownAt,
            supersededAt: null,
          });
          parent = parentOf.get(parent) ?? null;
          depth += 1;
        }
      }
    }
    void bounds;
  }
}

function slice(input: { status: "vacant" | "filled"; validStart: string; recordedAt: string }): PositionSlice {
  return {
    versionId: crypto.randomUUID(),
    status: input.status,
    validStart: input.validStart,
    validEnd: null,
    recordedAt: input.recordedAt,
    supersededAt: null,
  };
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

function greater(left: string, right: string): boolean {
  const diff = Money.parse(left).minus(Money.parse(right)).toString();
  return diff !== "0.00" && !diff.startsWith("-");
}

function daysBetween(start: string, end: string): number {
  const [startYear, startMonth, startDay] = start.split("-").map(Number);
  const [endYear, endMonth, endDay] = end.split("-").map(Number);
  // structural: missing numeric coalesces to zero for arithmetic
  const ms = Date.UTC(endYear ?? 0, (endMonth ?? 1) - 1, endDay ?? 1) - Date.UTC(startYear ?? 0, (startMonth ?? 1) - 1, startDay ?? 1);
  return Math.round(ms / 86_400_000);
}
