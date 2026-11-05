import { CanDoError, compareIsoDate, type ConflictResolution } from "@candohr/shared";
import { buildApprovals } from "./approval.ts";
import { referencedPositionId, runCascade, type CascadeRule } from "./cascade.ts";
import { commitOperations, previewConflicts } from "./commit.ts";
import { attributesOf, isKnownOperation, versionKey } from "./registry.ts";
import type {
  ApprovalDirectory,
  ApprovalRoute,
  ChangeSetRecord,
  ChangeSource,
  Operation,
  ValidationResult,
  World,
} from "./types.ts";
import { SOURCES } from "./types.ts";

export interface CreateInput {
  kind?: string;
  reasonCode?: string;
  effectiveDate?: string;
  isCorrection?: boolean;
  operations?: Operation[];
  baseVersions?: Record<string, number>;
  comment?: string;
  source?: string;
  budgetImpact?: string;
  conflictResolution?: ConflictResolution;
}

const EMPTY_DIRECTORY: ApprovalDirectory = {
  candidates: () => [],
  onLeave: () => null,
  isSubordinateOnOtherAssignment: () => false,
};

export interface ServiceFailure {
  ok: false;
  status: number;
  code: string;
  detail: string;
  current?: Record<string, number>;
}

export interface ServiceSuccess<T> {
  ok: true;
  status: number;
  body: T;
}

export class ChangeSetService {
  readonly sets = new Map<string, ChangeSetRecord>();
  private readonly idempotency = new Map<string, string>();
  private nextNumber = 1;
  private world: World;
  private readonly options: {
    tenantId: string;
    today: string;
    requestedBy?: string;
    now?: () => string;
    routes?: ApprovalRoute[];
    directory?: ApprovalDirectory;
    rules?: CascadeRule[];
  };

  constructor(
    world: World,
    options: {
      tenantId: string;
      today: string;
      requestedBy?: string;
      now?: () => string;
      routes?: ApprovalRoute[];
      directory?: ApprovalDirectory;
      rules?: CascadeRule[];
    },
  ) {
    this.world = world;
    this.options = options;
  }

  get books(): World {
    return this.world;
  }

  create(input: CreateInput, userId: string, idempotencyKey?: string): ServiceSuccess<ChangeSetRecord> | ServiceFailure {
    if (idempotencyKey) {
      const existingId = this.idempotency.get(idempotencyKey);
      const existing = existingId ? this.sets.get(existingId) : undefined;
      if (existing) return { ok: true, status: 201, body: existing };
    }
    const kind = input.kind;
    const reasonCode = input.reasonCode;
    const effectiveDate = input.effectiveDate;
    const operations = input.operations;
    if (!kind || !reasonCode || !effectiveDate || !operations || operations.length < 1) {
      return fail(400, "INVALID_CHANGE_SET", "A change set needs a kind, a reason, a date, and at least one operation.");
    }
    for (const op of operations) {
      if (!op.op || !isKnownOperation(op.op)) {
        return fail(400, "UNKNOWN_OPERATION", "That operation is not in the catalogue.");
      }
    }
    // structural: optional value absent; empty string for typing
    const source = (SOURCES as readonly string[]).includes(input.source ?? "") ? (input.source as ChangeSource) : "api";
    const record: ChangeSetRecord = {
      changeSetId: crypto.randomUUID(),
      number: this.nextNumber,
      tenantId: this.options.tenantId,
      kind,
      reasonCode,
      effectiveDate,
      isCorrection: input.isCorrection,
      operations: operations.map(copyOp),
      baseVersions: { ...(input.baseVersions ?? {}) },
      status: "draft",
      source,
      requestedBy: userId,
      requestedAt: this.now(),
      committedAt: null,
      comment: input.comment,
      budgetImpact: input.budgetImpact,
      conflictResolution: input.conflictResolution,
      approvals: [],
      approvalMode: "none",
      activity: [],
    };
    this.nextNumber += 1;
    this.sets.set(record.changeSetId, record);
    if (idempotencyKey) this.idempotency.set(idempotencyKey, record.changeSetId);
    return { ok: true, status: 201, body: record };
  }

  list(status?: string): { items: ChangeSetRecord[]; nextCursor: string | null } {
    const items = [...this.sets.values()].filter((row) => !status || row.status === status);
    return { items, nextCursor: null };
  }

  get(id: string): ServiceSuccess<ChangeSetRecord> | ServiceFailure {
    const row = this.sets.get(id);
    if (!row) return fail(404, "NOT_FOUND", "No change set has that id.");
    return { ok: true, status: 200, body: row };
  }

  /**
   * Runs the rules and the cascade in preview. The business rows are not changed.
   */
  validate(id: string): ServiceSuccess<ValidationResult> | ServiceFailure {
    const row = this.sets.get(id);
    if (!row) return fail(404, "NOT_FOUND", "No change set has that id.");
    const versionConflict = this.versionConflict(row);
    if (versionConflict) {
      return {
        ok: false,
        status: 409,
        code: "VERSION_CONFLICT",
        detail: "Someone else saved this record after the form was opened.",
        current: versionConflict,
      };
    }
    const result = this.inspect(row);
    row.validation = result;
    if (result.errors.length === 0) row.status = "validated";
    return { ok: true, status: 200, body: result };
  }

  submit(
    id: string,
    body: { acknowledgedWarnings?: string[]; comment?: string; isCorrection?: boolean; conflictResolution?: ConflictResolution },
  ): ServiceSuccess<ChangeSetRecord> | ServiceFailure {
    const row = this.sets.get(id);
    if (!row) return fail(404, "NOT_FOUND", "No change set has that id.");
    const versionConflict = this.versionConflict(row);
    if (versionConflict) {
      return {
        ok: false,
        status: 409,
        code: "VERSION_CONFLICT",
        detail: "Someone else saved this record after the form was opened.",
        current: versionConflict,
      };
    }
    if (body.isCorrection !== undefined) row.isCorrection = body.isCorrection;
    if (body.conflictResolution) row.conflictResolution = body.conflictResolution;
    if (body.comment) row.comment = body.comment;
    const result = this.inspect(row);
    row.validation = result;
    if (result.errors.length > 0) {
      // structural: nullish coalescing for optional input in tests or adapters
      return fail(422, result.errors[0]?.code ?? "INVALID", result.errors[0]?.message ?? "Fix the errors before submitting.");
    }
    const acknowledged = new Set(body.acknowledgedWarnings ?? []);
    const pending = result.warnings.filter((warning) => !acknowledged.has(warning.code));
    if (pending.length > 0) {
      return fail(422, "WARNINGS_NOT_ACKNOWLEDGED", "Acknowledge each warning before submitting.");
    }
    if (result.warnings.some((warning) => warning.code === "FUTURE_CONFLICT") && !row.conflictResolution) {
      return fail(422, "FUTURE_CONFLICT", "Choose keep, replace, or merge for the future change.");
    }
    try {
      const built = buildApprovals(row, this.options.routes ?? [], this.options.directory ?? EMPTY_DIRECTORY, this.now());
      row.approvals = built.steps;
      row.approvalMode = built.mode;
      row.activity.push(...built.activity);
    } catch (error) {
      if (error instanceof CanDoError) return fail(422, error.code, error.code);
      throw error;
    }
    if (row.approvals.length > 0) {
      row.status = "pending_approval";
      return { ok: true, status: 200, body: row };
    }
    return this.finish(row);
  }

  decide(
    id: string,
    userId: string,
    body: { decision?: string; comment?: string; step?: number },
  ): ServiceSuccess<ChangeSetRecord> | ServiceFailure {
    const row = this.sets.get(id);
    if (!row) return fail(404, "NOT_FOUND", "No change set has that id.");
    if (userId === row.requestedBy) {
      return fail(403, "SELF_APPROVAL_BLOCKED", "You cannot approve your own request.");
    }
    if (body.decision !== "approve" && body.decision !== "reject") {
      return fail(400, "DECISION", "Choose approve or reject.");
    }
    const open = row.approvals.filter((step) => step.status === "open");
    const pool = row.approvalMode === "parallel" ? open : open.slice(0, 1);
    const step = pool.find((item) => item.assignee === userId && (body.step === undefined || item.step === body.step));
    if (!step) return fail(403, "NOT_THE_APPROVER", "This step is waiting for someone else.");
    step.decidedAt = this.now();
    step.comment = body.comment;
    if (body.decision === "reject") {
      step.status = "rejected";
      row.status = "rejected";
      row.activity.push({
        action: "approval.rejected",
        actorId: userId,
        principalUserId: step.principalUserId,
        delegateUserId: step.principalUserId ? userId : null,
        at: step.decidedAt,
      });
      return { ok: true, status: 200, body: row };
    }
    step.status = "approved";
    row.activity.push({
      action: "approval.approved",
      actorId: userId,
      principalUserId: step.principalUserId,
      delegateUserId: step.principalUserId ? userId : null,
      at: step.decidedAt,
    });
    const stillOpen = row.approvals.some((item) => item.status === "open");
    if (stillOpen) {
      row.status = "pending_approval";
      return { ok: true, status: 200, body: row };
    }
    row.status = "approved";
    return this.finish(row);
  }

  private finish(row: ChangeSetRecord): ServiceSuccess<ChangeSetRecord> | ServiceFailure {
    const committed = commitOperations({
      world: this.world,
      operations: row.operations,
      changeSetId: row.changeSetId,
      tenantId: row.tenantId,
      actorId: row.requestedBy,
      effectiveDate: row.effectiveDate,
      knownAt: this.now(),
      isCorrection: row.isCorrection === true,
      conflictResolution: row.conflictResolution,
      rules: this.options.rules,
      choiceMissing: this.choiceMissing(row),
      today: this.options.today,
    });
    if (committed.error) {
      return fail(422, committed.error.code, committed.error.code);
    }
    this.world = committed.world;
    row.operations = committed.operations;
    row.committedAt = this.now();
    row.status = compareIsoDate(row.effectiveDate, this.options.today) > 0 ? "scheduled" : "committed";
    return { ok: true, status: 200, body: row };
  }

  private inspect(row: ChangeSetRecord): ValidationResult {
    const errors: ValidationResult["errors"] = [];
    const warnings: ValidationResult["warnings"] = [];
    if (this.choiceMissing(row)) {
      errors.push({
        code: "MUST_CHOOSE_CHANGE_OR_CORRECTION",
        message: "This date is in the past. Choose New change or Correction.",
      });
    }
    row.operations.forEach((op, operationIndex) => {
      if (!isKnownOperation(op.op)) {
        errors.push({ code: "UNKNOWN_OPERATION", message: "That operation is not in the catalogue.", operationIndex });
      }
      const positionId = referencedPositionId(this.world, op);
      if (positionId && (op.op === "assignment.update" || op.op === "assignment.create")) {
        const position = this.world.positions[positionId];
        if (position?.status === "frozen") {
          errors.push({
            code: "POSITION_FROZEN",
            message: "That position is frozen on this date, so it cannot be filled or changed.",
            operationIndex,
          });
        }
      }
      if (!this.choiceMissing(row) && (op.op === "assignment.update" || op.op === "compensation.set_rate")) {
        // structural: optional value absent; empty string for typing
        const id = op.assignmentId ?? op.targetId ?? "";
        const assignment = this.world.assignments[id];
        const patch = attributesOf(op.set);
        if (op.op === "compensation.set_rate" && patch.rate === undefined && typeof op.set?.amount === "string") {
          patch.rate = op.set.amount;
        }
        if (assignment && Object.keys(patch).length > 0) {
          const conflicts = previewConflicts(assignment.versions, {
            entityId: id,
            effectiveDate: row.effectiveDate,
            knownAt: this.now(),
            changeSetId: row.changeSetId,
            patch,
            isCorrection: row.isCorrection === true,
          });
          for (const conflict of conflicts) {
            if (conflict.code === "FUTURE_CONFLICT") {
              warnings.push({
                code: "FUTURE_CONFLICT",
                message: "A later approved change sets a different value. Choose keep, replace, or merge.",
                operationIndex,
                field: conflict.field,
              });
            } else if (conflict.code !== "OK") {
              errors.push({ code: conflict.code, message: conflict.code, operationIndex, field: conflict.field });
            }
          }
        } else if (!assignment && op.op === "assignment.update") {
          errors.push({ code: "ASSIGNMENT_UNKNOWN", message: "That assignment does not exist.", operationIndex });
        }
      }
    });
    let consequences: ValidationResult["consequences"] = [];
    let cascaded: Operation[] = row.operations;
    try {
      const outcome = runCascade(this.world, row.operations, this.options.rules);
      consequences = outcome.consequences;
      cascaded = outcome.operations;
      for (const warning of outcome.warnings) warnings.push(warning);
    } catch (error) {
      if (error instanceof CanDoError) {
        errors.push({ code: error.code, message: "The follow-on changes did not settle." });
      } else {
        throw error;
      }
    }
    if (warnings.some((warning) => warning.code === "FUTURE_CONFLICT")) {
      consequences.push({
        kind: "conflict_future_change",
        description: "A future change sets one of these fields differently.",
      });
    }
    void cascaded;
    return { errors, warnings, consequences };
  }

  private choiceMissing(row: ChangeSetRecord): boolean {
    return compareIsoDate(row.effectiveDate, this.options.today) < 0 && row.isCorrection === undefined;
  }

  private versionConflict(row: ChangeSetRecord): Record<string, number> | null {
    const current: Record<string, number> = {};
    let mismatch = false;
    for (const op of row.operations) {
      const key = versionKey(op);
      if (!key || row.baseVersions[key] === undefined) continue;
      const actual = this.currentVersion(key);
      if (actual !== row.baseVersions[key]) {
        mismatch = true;
        current[key] = actual;
      }
    }
    return mismatch ? current : null;
  }

  private currentVersion(key: string): number {
    const [type, id] = key.split(":");
    // structural: in-memory version lookup for tests; missing id or version reads as zero
    if (type === "assignment") return this.world.assignments[id ?? ""]?.version ?? 0;
    // structural: optional value absent; empty string for typing
    if (type === "position") return this.world.positions[id ?? ""]?.version ?? 0;
    return 0;
  }

  private now(): string {
    return this.options.now ? this.options.now() : new Date().toISOString();
  }
}

function copyOp(op: Operation): Operation {
  return { ...op, set: op.set ? { ...op.set } : undefined };
}

function fail(status: number, code: string, detail: string): ServiceFailure {
  return { ok: false, status, code, detail };
}
