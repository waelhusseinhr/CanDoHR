/** Privileged roles lose the session after 30 idle minutes. Every session ends after 8 hours. */
const ABSOLUTE_MS = 8 * 60 * 60 * 1000;
const IDLE_PRIVILEGED_MS = 30 * 60 * 1000;

const PRIVILEGED = new Set([
  "hrbp",
  "hr_admin",
  "payroll_processor",
  "payroll_approver",
  "finance",
  "tenant_admin",
]);

export function isPrivilegedRole(roleCode: string): boolean {
  return PRIVILEGED.has(roleCode);
}

export function sessionStillValid(input: {
  issuedAtMs: number;
  lastActivityAtMs: number;
  nowMs: number;
  privileged: boolean;
}): boolean {
  if (input.nowMs - input.issuedAtMs >= ABSOLUTE_MS) return false;
  if (input.privileged && input.nowMs - input.lastActivityAtMs >= IDLE_PRIVILEGED_MS) return false;
  return true;
}
