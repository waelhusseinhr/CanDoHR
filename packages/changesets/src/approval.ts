import { CanDoError, Money } from "@candohr/shared";
import type { Activity, ApprovalDirectory, ApprovalRoute, ApprovalStep, ChangeSetRecord } from "./types.ts";

/** Transfers whose budget impact is over $10,000 go to HR, then finance, in that order (PLAT-005). */
export function transferOverBudgetRoute(): ApprovalRoute {
  return {
    mode: "sequential",
    matches(changeSet) {
      if (changeSet.kind !== "transfer" || !changeSet.budgetImpact) return false;
      const over = Money.parse(changeSet.budgetImpact).minus(Money.parse("10000.00")).toString();
      return over !== "0.00" && !over.startsWith("-");
    },
    steps: [{ role: "hrbp" }, { role: "finance" }],
  };
}

export interface BuiltApprovals {
  mode: "sequential" | "parallel" | "none";
  steps: ApprovalStep[];
  activity: Activity[];
}

/**
 * Picks who may approve. Skips the requester and anyone who reports to the requester
 * on another assignment. An approver who is away is replaced by their delegate, and both names are kept.
 */
export function buildApprovals(
  changeSet: ChangeSetRecord,
  routes: readonly ApprovalRoute[],
  directory: ApprovalDirectory,
  at: string,
): BuiltApprovals {
  const route = routes.find((item) => item.matches(changeSet));
  if (!route) return { mode: "none", steps: [], activity: [] };
  const activity: Activity[] = [];
  const steps: ApprovalStep[] = route.steps.map((step, index) => {
    const picked = pickAssignee(step.role, changeSet, directory);
    if (picked.principalUserId) {
      activity.push({
        action: "approval.delegated",
        actorId: picked.principalUserId,
        principalUserId: picked.principalUserId,
        delegateUserId: picked.assignee,
        at,
      });
    }
    return {
      step: index + 1,
      role: step.role,
      assignee: picked.assignee,
      principalUserId: picked.principalUserId,
      status: "open",
      decidedAt: null,
    };
  });
  return { mode: route.mode, steps, activity };
}

function pickAssignee(
  role: string,
  changeSet: ChangeSetRecord,
  directory: ApprovalDirectory,
): { assignee: string; principalUserId: string | null } {
  const candidates = directory.candidates(role, changeSet);
  for (const candidate of candidates) {
    if (candidate === changeSet.requestedBy) continue;
    if (directory.isSubordinateOnOtherAssignment(candidate, changeSet.requestedBy)) continue;
    const leave = directory.onLeave(candidate);
    if (leave) return { assignee: leave.delegateUserId, principalUserId: candidate };
    return { assignee: candidate, principalUserId: null };
  }
  throw new CanDoError("NO_APPROVER");
}

export function assertCanDecide(changeSet: ChangeSetRecord, userId: string, stepNumber?: number): ApprovalStep {
  if (userId === changeSet.requestedBy) {
    throw new CanDoError("SELF_APPROVAL_BLOCKED");
  }
  const open = changeSet.approvals.filter((step) => step.status === "open");
  if (open.length === 0) throw new CanDoError("NOTHING_TO_APPROVE");
  const current = changeSet.approvalMode === "parallel" ? open : [open[0]].filter((step): step is ApprovalStep => step !== undefined);
  const target = stepNumber === undefined ? current : current.filter((step) => step.step === stepNumber);
  const step = target.find((item) => item.assignee === userId);
  if (!step) throw new CanDoError("NOT_THE_APPROVER");
  return step;
}
