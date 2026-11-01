import { CanDoError, type AttributeMap, type AttributeValue } from "@candohr/shared";
import { OPERATIONS, type Operation } from "./types.ts";

const KNOWN = new Set<string>(OPERATIONS);

const SENSITIVE = new Set(["sin", "banking", "bank", "salary", "rate", "payAmount", "health"]);

export function isKnownOperation(op: string): boolean {
  return KNOWN.has(op);
}

/** The entity id the operation writes, from either the OpenAPI field or the spec example fields. */
export function targetId(op: Operation): string {
  const id = op.targetId ?? op.assignmentId ?? op.positionId ?? op.employmentId ?? op.personId ?? op.orgUnitId ?? "";
  return id;
}

export function versionKey(op: Operation): string | null {
  const id = targetId(op);
  if (!id) return null;
  if (op.op.startsWith("assignment.") || op.op === "compensation.set_rate" || op.op === "payroll_profile.update") {
    return `assignment:${op.assignmentId ?? op.targetId ?? id}`;
  }
  if (op.op.startsWith("position.")) return `position:${op.positionId ?? op.targetId ?? id}`;
  if (op.op.startsWith("employment.")) return `employment:${op.employmentId ?? op.targetId ?? id}`;
  if (op.op.startsWith("person.")) return `person:${op.personId ?? op.targetId ?? id}`;
  if (op.op.startsWith("org_unit.")) return `org_unit:${op.orgUnitId ?? op.targetId ?? id}`;
  return null;
}

export function subjectOf(op: Operation): { type: string; id: string; key: string } {
  const id = targetId(op);
  if (op.op.startsWith("assignment.") || op.op === "compensation.set_rate" || op.op === "payroll_profile.update") {
    const assignmentId = op.assignmentId ?? op.targetId ?? id;
    return { type: "assignment", id: assignmentId, key: `assignment:${assignmentId}` };
  }
  if (op.op.startsWith("position.")) {
    const positionId = op.positionId ?? op.targetId ?? id;
    return { type: "position", id: positionId, key: `position:${positionId}` };
  }
  if (op.op.startsWith("employment.")) {
    const employmentId = op.employmentId ?? op.targetId ?? id;
    return { type: "employment", id: employmentId, key: `employment:${employmentId}` };
  }
  if (op.op.startsWith("person.")) {
    const personId = op.personId ?? op.targetId ?? id;
    return { type: "person", id: personId, key: `person:${personId}` };
  }
  if (op.op.startsWith("org_unit.")) {
    const orgUnitId = op.orgUnitId ?? op.targetId ?? id;
    return { type: "org_unit", id: orgUnitId, key: `org_unit:${orgUnitId}` };
  }
  if (op.op === "agreement.activate_version") {
    return { type: "agreement", id, key: `agreement:${id}` };
  }
  if (op.op === "time.correct") {
    return { type: "timesheet", id, key: `timesheet:${id}` };
  }
  return { type: "unknown", id, key: `unknown:${id}` };
}

export function eventTypeFor(op: string): string {
  switch (op) {
    case "person.create":
      return "person.created";
    case "person.update":
      return "person.updated";
    case "employment.hire":
      return "employment.hired";
    case "employment.rehire":
      return "employment.rehired";
    case "employment.terminate":
      return "employment.terminated";
    case "position.eliminate":
      return "position.eliminated";
    case "compensation.set_rate":
      return "rate.changed";
    case "agreement.activate_version":
      return "agreement.version_activated";
    case "time.correct":
      return "time.corrected";
    default:
      if (op.startsWith("assignment.")) return "assignment.changed";
      if (op.startsWith("position.")) return "position.changed";
      if (op.startsWith("org_unit.")) return "org.changed";
      if (op.startsWith("employment.")) return "employment.status_changed";
      return "assignment.changed";
  }
}

export function attributesOf(set: AttributeMap | undefined): AttributeMap {
  if (!set) return {};
  const out: AttributeMap = {};
  for (const [key, value] of Object.entries(set)) {
    if (typeof value === "number") {
      throw new CanDoError("MONEY_NUMBER");
    }
    if (value !== null && typeof value !== "string" && typeof value !== "boolean") {
      throw new CanDoError("ATTRIBUTE");
    }
    out[key] = value as AttributeValue;
  }
  return out;
}

/** Sensitive fields are marked changed and the value is left out (api/events.yaml). */
export function publicChange(key: string, from: unknown, to: unknown): { from?: unknown; to?: unknown; changed?: boolean } {
  if (SENSITIVE.has(key)) return { changed: true };
  return { from, to };
}

export function sameOperation(left: Operation, right: Operation): boolean {
  return left.op === right.op && targetId(left) === targetId(right) && stable(left.set) === stable(right.set);
}

function stable(value: AttributeMap | undefined): string {
  if (!value) return "";
  return JSON.stringify(Object.keys(value).sort().map((key) => [key, value[key]]));
}
