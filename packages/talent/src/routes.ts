import { fail } from "./errors.ts";

export type Approval = { role: string; approverId: string };

/** A route is the organization's. An empty route is not a default route. */
export function completeRoute(input: {
  steps: readonly { role: string }[];
  approvals: readonly Approval[];
  blockedApproverIds: readonly string[];
}): void {
  if (input.steps.length === 0) fail("INPUT_REQUIRED");
  for (const approval of input.approvals) {
    if (input.blockedApproverIds.includes(approval.approverId)) fail("SELF_APPROVAL");
  }
  for (const step of input.steps) {
    const matched = input.approvals.some((approval) => approval.role === step.role);
    if (!matched) fail("ROUTE_APPROVALS_MISSING");
  }
}

export function sameTenant<T>(recordTenant: string, readerTenant: string, rows: readonly T[]): T[] {
  if (recordTenant !== readerTenant) return [];
  return rows.slice();
}
