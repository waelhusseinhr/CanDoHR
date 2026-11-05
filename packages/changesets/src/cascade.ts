import { CanDoError, type AttributeMap } from "@candohr/shared";
import { sameOperation, targetId } from "./registry.ts";
import type { Consequence, Finding, Operation, World } from "./types.ts";

export interface CascadeOutcome {
  operations: Operation[];
  warnings: Finding[];
  consequences: Consequence[];
}

export interface CascadeRule {
  id: string;
  apply(input: { world: World; operations: readonly Operation[]; effectiveDate: string }): {
    operations: Operation[];
    warnings: Finding[];
    consequences: Consequence[];
  };
}

/**
 * Runs pure rules until no new operation appears, or 10 rounds, whichever comes first.
 * Preview and commit both use this. Rules must not write to the world.
 */
export function runCascade(
  world: World,
  operations: readonly Operation[],
  rules: readonly CascadeRule[] = defaultCascadeRules,
  maxRounds = 10,
): CascadeOutcome {
  let current: Operation[] = operations.map((op) => ({ ...op, set: op.set ? { ...op.set } : undefined }));
  const warnings: Finding[] = [];
  const consequences: Consequence[] = [];
  // structural: loop index or iteration bound, not a business default
  for (let round = 0; round < maxRounds; round += 1) {
    let added = false;
    for (const rule of rules) {
      const result = rule.apply({ world, operations: current, effectiveDate: "" });
      warnings.push(...result.warnings);
      for (const consequence of result.consequences) {
        consequences.push(consequence);
      }
      for (const op of result.operations) {
        if (current.some((existing) => sameOperation(existing, op))) continue;
        const addedOperation: Operation = { ...op, addedByCascade: true, set: op.set ? { ...op.set } : undefined };
        current = [...current, addedOperation];
        added = true;
        if (!result.consequences.some((item) => item.addedOperation && sameOperation(item.addedOperation, op))) {
          consequences.push({
            kind: "task",
            description: `Also apply ${addedOperation.op}.`,
            addedOperation,
          });
        }
      }
    }
    if (!added) {
      return { operations: current, warnings, consequences };
    }
  }
  throw new CanDoError("CASCADE_DID_NOT_SETTLE");
}

/** Ending employment closes every open assignment. A location change updates tax province unless someone overrode it. */
export const defaultCascadeRules: CascadeRule[] = [
  {
    id: "employment.terminate.ends-assignments",
    apply({ world, operations }) {
      const added: Operation[] = [];
      const consequences: Consequence[] = [];
      for (const op of operations) {
        if (op.op !== "employment.terminate") continue;
        // structural: optional value absent; empty string for typing
        const employmentId = op.employmentId ?? op.targetId ?? "";
        const employment = world.employments[employmentId];
        if (!employment) continue;
        for (const assignmentId of employment.assignmentIds) {
          const assignment = world.assignments[assignmentId];
          if (!assignment) continue;
          const open = currentAttributes(assignment).status !== "ended";
          if (!open) continue;
          const endOp: Operation = { op: "assignment.end", assignmentId, targetId: assignmentId, set: { status: "ended" } };
          if (operations.some((existing) => sameOperation(existing, endOp)) || added.some((existing) => sameOperation(existing, endOp))) {
            continue;
          }
          added.push(endOp);
          const position = assignment.positionId ? world.positions[assignment.positionId] : undefined;
          consequences.push({
            kind: "task",
            description: position
              ? "End the open assignment and vacate the position."
              : "End the open assignment.",
            addedOperation: { ...endOp, addedByCascade: true },
          });
        }
      }
      return { operations: added, warnings: [], consequences };
    },
  },
  {
    id: "assignment.location.tax-province",
    apply({ world, operations }) {
      const added: Operation[] = [];
      const consequences: Consequence[] = [];
      for (const op of operations) {
        if (op.op !== "assignment.update") continue;
        const locationId = op.set?.locationId;
        if (typeof locationId !== "string") continue;
        // structural: optional value absent; empty string for typing
        const assignmentId = op.assignmentId ?? op.targetId ?? "";
        const location = world.locations[locationId];
        const profile = world.profiles[assignmentId];
        if (!location || !profile || profile.overridden) continue;
        if (profile.taxProvince === location.province) continue;
        const profileOp: Operation = {
          op: "payroll_profile.update",
          assignmentId,
          targetId: assignmentId,
          set: { taxProvince: location.province },
        };
        added.push(profileOp);
        consequences.push({
          kind: "tax_province",
          description: "Tax province follows the work location.",
          from: profile.taxProvince,
          to: location.province,
          addedOperation: { ...profileOp, addedByCascade: true },
        });
      }
      return { operations: added, warnings: [], consequences };
    },
  },
];

function currentAttributes(assignment: { versions: { supersededAt: string | null; attributes: AttributeMap }[] }): AttributeMap {
  const current = [...assignment.versions].reverse().find((row) => row.supersededAt === null);
  return current?.attributes ?? {};
}

export function referencedPositionId(world: World, op: Operation): string | null {
  if (typeof op.set?.positionId === "string") return op.set.positionId;
  if (op.op.startsWith("position.")) return op.positionId ?? op.targetId ?? null;
  if (op.op.startsWith("assignment.")) {
    const id = targetId(op);
    return world.assignments[id]?.positionId ?? null;
  }
  return null;
}
