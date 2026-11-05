import {
  CanDoError,
  readAsOf,
  writeVersion,
  type AttributeMap,
  type ConflictResolution,
  type VersionRow,
} from "@candohr/shared";
import { runCascade, type CascadeRule } from "./cascade.ts";
import { attributesOf, eventTypeFor, publicChange, subjectOf, targetId } from "./registry.ts";
import type { AuditEntry, DomainEvent, Operation, World } from "./types.ts";

export interface CommitInput {
  world: World;
  operations: readonly Operation[];
  changeSetId: string;
  tenantId: string;
  actorId: string;
  effectiveDate: string;
  knownAt: string;
  isCorrection: boolean;
  conflictResolution?: ConflictResolution;
  rules?: readonly CascadeRule[];
  /** True when the effective date is in the past and the person has not chosen change or correction. */
  choiceMissing: boolean;
  today: string;
}

export interface CommitResult {
  world: World;
  operations: Operation[];
  audits: AuditEntry[];
  outbox: DomainEvent[];
  error?: CanDoError;
}

/**
 * Applies every operation, including cascade additions, on a copy of the world.
 * If any operation fails, the caller's world is returned untouched: no version,
 * audit row, or outbox event from this attempt remains.
 */
export function commitOperations(input: CommitInput): CommitResult {
  const original = input.world;
  let operations: Operation[];
  try {
    operations = runCascade(original, input.operations, input.rules).operations;
  } catch (error) {
    return { world: original, operations: [...input.operations], audits: [], outbox: [], error: asError(error) };
  }
  const next = structuredClone(original);
  const auditFrom = next.audits.length;
  const outboxFrom = next.outbox.length;
  try {
    const seenSubjects = new Set<string>();
    for (const op of operations) {
      applyOperation(next, op, input, seenSubjects);
    }
    return {
      world: next,
      operations,
      audits: next.audits.slice(auditFrom),
      outbox: next.outbox.slice(outboxFrom),
    };
  } catch (error) {
    return { world: original, operations, audits: [], outbox: [], error: asError(error) };
  }
}

function applyOperation(world: World, op: Operation, input: CommitInput, seenSubjects: Set<string>): void {
  const set = attributesOf(op.set);
  switch (op.op) {
    case "assignment.update":
    case "assignment.create":
    case "assignment.end":
    case "compensation.set_rate":
      writeAssignment(world, op, set, input);
      break;
    case "employment.terminate":
      terminateEmployment(world, op);
      break;
    case "employment.hire":
    case "employment.rehire":
      hireEmployment(world, op);
      break;
    case "payroll_profile.update":
      updateProfile(world, op, set);
      break;
    case "position.freeze":
      setPositionStatus(world, op, "frozen");
      break;
    case "position.eliminate":
      setPositionStatus(world, op, "eliminated");
      break;
    case "position.create":
    case "position.update":
      upsertPosition(world, op, set);
      break;
    case "person.create":
    case "person.update":
      upsertPerson(world, op, set);
      break;
    case "org_unit.create":
    case "org_unit.update":
    case "org_unit.move":
    case "org_unit.close":
      upsertOrgUnit(world, op, set);
      break;
    case "agreement.activate_version":
      activateAgreement(world, op, set);
      break;
    case "time.correct":
      break;
    default:
      throw new CanDoError("UNKNOWN_OPERATION");
  }
  const subject = subjectOf(op);
  pushAudit(world, {
    action: op.op,
    subjectType: subject.type,
    subjectId: subject.id,
    changeSetId: input.changeSetId,
    actorId: input.actorId,
    before: null,
    after: redactAfter(set),
    occurredAt: input.knownAt,
  });
  if (!seenSubjects.has(subject.key)) {
    seenSubjects.add(subject.key);
    world.outbox.push(eventFor(world, op, input, subject, set));
  }
}

function writeAssignment(world: World, op: Operation, set: AttributeMap, input: CommitInput): void {
  // structural: optional value absent; empty string for typing
  const id = op.assignmentId ?? op.targetId ?? "";
  if (op.op === "assignment.end") set = { ...set, status: "ended" };
  if (op.op === "compensation.set_rate" && set.rate === undefined && set.amount !== undefined) {
    set = { rate: set.amount };
  }
  const existing = world.assignments[id];
  if (!existing && op.op !== "assignment.create") {
    throw new CanDoError("ASSIGNMENT_UNKNOWN");
  }
  if (input.choiceMissing && input.effectiveDate < input.today && op.op !== "assignment.end") {
    throw new CanDoError("MUST_CHOOSE_CHANGE_OR_CORRECTION");
  }
  const patch = Object.keys(set).length > 0 ? set : { status: "open" };
  // structural: in-memory merge strategy for tests, not platform.setting()
  const resolution: ConflictResolution = input.conflictResolution ?? "merge";
  if (!existing) {
    world.assignments[id] = {
      id,
      employmentId: typeof set.employmentId === "string" ? set.employmentId : "",
      personId: typeof set.personId === "string" ? set.personId : "",
      positionId: typeof set.positionId === "string" ? set.positionId : null,
      version: 1,
      versions: [
        {
          versionId: crypto.randomUUID(),
          entityId: id,
          validStart: input.effectiveDate,
          validEnd: null,
          recordedAt: input.knownAt,
          supersededAt: null,
          changeSetId: input.changeSetId,
          attributes: { ...patch },
          explicitKeys: Object.keys(patch),
        },
      ],
    };
    return;
  }
  const written = writeVersion(existing.versions, {
    entityId: id,
    kind: input.isCorrection ? "correction" : "change",
    effectiveDate: input.effectiveDate,
    knownAt: input.knownAt,
    changeSetId: input.changeSetId,
    patch,
    conflictResolution: resolution,
  });
  if (written.conflicts.length > 0 && !input.conflictResolution) {
    throw new CanDoError("FUTURE_CONFLICT");
  }
  existing.versions = written.versions;
  existing.version += 1;
  if (typeof patch.orgUnitId === "string") {
    /* org unit lives on the version row */
  }
  if (typeof patch.positionId === "string") existing.positionId = patch.positionId;
  if (patch.status === "ended" && existing.positionId) {
    vacateIfEmpty(world, existing.positionId, id);
  }
}

function vacateIfEmpty(world: World, positionId: string, endedAssignmentId: string): void {
  const holders = Object.values(world.assignments).filter((assignment) => {
    if (assignment.id === endedAssignmentId) return false;
    if (assignment.positionId !== positionId) return false;
    const current = [...assignment.versions].reverse().find((row) => row.supersededAt === null);
    return current?.attributes.status !== "ended";
  });
  const position = world.positions[positionId];
  if (position && holders.length === 0 && position.status === "active") {
    position.status = "vacant";
  }
}

function terminateEmployment(world: World, op: Operation): void {
  // structural: optional value absent; empty string for typing
  const id = op.employmentId ?? op.targetId ?? "";
  const employment = world.employments[id];
  if (!employment) throw new CanDoError("EMPLOYMENT_UNKNOWN");
  employment.status = "terminated";
}

function hireEmployment(world: World, op: Operation): void {
  const id = op.employmentId ?? op.targetId ?? crypto.randomUUID();
  world.employments[id] = world.employments[id] ?? {
    id,
    // structural: optional value absent; empty string for typing
    personId: op.personId ?? "",
    status: "active",
    assignmentIds: [],
  };
}

function updateProfile(world: World, op: Operation, set: AttributeMap): void {
  // structural: optional value absent; empty string for typing
  const assignmentId = op.assignmentId ?? op.targetId ?? "";
  const profile = world.profiles[assignmentId];
  if (!profile) throw new CanDoError("PROFILE_UNKNOWN");
  if (typeof set.taxProvince === "string") profile.taxProvince = set.taxProvince;
  if (set.overridden === true) profile.overridden = true;
}

function setPositionStatus(world: World, op: Operation, status: "frozen" | "eliminated"): void {
  // structural: optional value absent; empty string for typing
  const id = op.positionId ?? op.targetId ?? "";
  const position = world.positions[id];
  if (!position) throw new CanDoError("POSITION_UNKNOWN");
  position.status = status;
  position.version += 1;
}

function upsertPosition(world: World, op: Operation, set: AttributeMap): void {
  const id = op.positionId ?? op.targetId ?? crypto.randomUUID();
  // structural: nullish coalescing for optional input in tests or adapters
  const current = world.positions[id] ?? { id, status: "active" as const, version: 0, orgUnitId: "" };
  if (typeof set.orgUnitId === "string") current.orgUnitId = set.orgUnitId;
  if (set.status === "vacant" || set.status === "active" || set.status === "frozen" || set.status === "eliminated") {
    current.status = set.status;
  }
  current.version += 1;
  world.positions[id] = current;
}

function upsertPerson(world: World, op: Operation, set: AttributeMap): void {
  const id = op.personId ?? op.targetId ?? crypto.randomUUID();
  // structural: nullish coalescing for optional input in tests or adapters
  const current = world.people[id] ?? { id, attributes: {} };
  current.attributes = { ...current.attributes, ...set };
  world.people[id] = current;
}

function upsertOrgUnit(world: World, op: Operation, set: AttributeMap): void {
  const id = op.orgUnitId ?? op.targetId ?? crypto.randomUUID();
  // structural: nullish coalescing for optional input in tests or adapters
  const current = world.orgUnits[id] ?? { id, parentId: null, status: "active" };
  if (typeof set.parentId === "string") current.parentId = set.parentId;
  if (op.op === "org_unit.close") current.status = "closed";
  world.orgUnits[id] = current;
}

function activateAgreement(world: World, op: Operation, set: AttributeMap): void {
  const id = targetId(op);
  world.agreements[id] = { id, version: typeof set.version === "string" ? set.version : null };
}

function pushAudit(world: World, entry: Omit<AuditEntry, "auditId">): void {
  world.audits.push({ auditId: world.nextAuditId, ...entry });
  world.nextAuditId += 1;
}

function eventFor(
  world: World,
  op: Operation,
  input: CommitInput,
  subject: { type: string; id: string; key: string },
  set: AttributeMap,
): DomainEvent {
  const assignment = world.assignments[subject.id];
  const changes: DomainEvent["changes"] = {};
  for (const [key, value] of Object.entries(set)) {
    changes[key] = publicChange(key, null, value);
  }
  return {
    eventId: crypto.randomUUID(),
    type: eventTypeFor(op.op),
    version: 1,
    tenantId: input.tenantId,
    occurredAt: input.knownAt,
    effectiveDate: input.effectiveDate,
    changeSetId: input.changeSetId,
    subject: {
      type: subject.type,
      id: subject.id,
      employmentId: assignment?.employmentId,
      personId: assignment?.personId,
    },
    changes,
    actor: { type: "user", id: input.actorId },
    subjectKey: subject.key,
    publishedAt: null,
  };
}

function redactAfter(set: AttributeMap): AttributeMap {
  const out: AttributeMap = {};
  for (const [key, value] of Object.entries(set)) {
    out[key] = key === "rate" || key === "salary" || key === "sin" || key === "banking" ? null : (value ?? null);
  }
  return out;
}

function asError(error: unknown): CanDoError {
  if (error instanceof CanDoError) return error;
  return new CanDoError("COMMIT_FAILED");
}

/** Used by validation to see future-row conflicts without keeping the write. */
export function previewConflicts(
  versions: readonly VersionRow[],
  input: {
    entityId: string;
    effectiveDate: string;
    knownAt: string;
    changeSetId: string;
    patch: AttributeMap;
    isCorrection: boolean;
  },
): { code: string; field?: string }[] {
  try {
    const written = writeVersion(versions, {
      entityId: input.entityId,
      kind: input.isCorrection ? "correction" : "change",
      effectiveDate: input.effectiveDate,
      knownAt: input.knownAt,
      changeSetId: input.changeSetId,
      patch: input.patch,
      conflictResolution: "keep",
    });
    return written.conflicts.map((conflict) => ({ code: "FUTURE_CONFLICT", field: conflict.key }));
  } catch (error) {
    if (error instanceof CanDoError) return [{ code: error.code }];
    return [{ code: "COMMIT_FAILED" }];
  }
}

export function visibleRow(versions: readonly VersionRow[], entityId: string, asOf: string, knownAt: string): VersionRow | null {
  return readAsOf(versions, entityId, asOf, knownAt);
}
