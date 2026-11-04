import { addDays } from "./dates.ts";
import { D, money } from "./decimal.ts";
import { fail } from "./errors.ts";

export type LiveAssignment = {
  assignmentId: string;
  personId: string;
  employmentId: string;
  payrollAccountId: string;
  leavePlanId: string;
  positionId: string;
  nextEarningsDate: string;
  weeklyHours: string;
};

export type EndEffects = {
  roes: { personId: string; payrollAccountId: string }[];
  leaveSettles: boolean;
  benefitsReevaluated: true;
  positionVacated: boolean;
  duesStopped: boolean;
  hoursDropReview: boolean;
  statutoryNoticeTriggered: boolean;
  changeSetKind: "assignment.end" | "employment.terminate";
  futureShiftsCancelled: true;
};

/**
 * Ending one assignment. An ROE is per payroll account and is withheld while earnings
 * continue on that account inside the caller's interruption window.
 */
export function endAssignment(input: {
  interruptionDays: number;
  ended: LiveAssignment & { endDate: string };
  remaining: readonly LiveAssignment[];
  positionHolders: readonly { positionId: string; assignmentId: string }[];
  continuingDuesObligation: boolean;
  hoursDropShare: string;
  constructiveDismissal: boolean;
  layoff: boolean;
}): EndEffects {
  if (!Number.isInteger(input.interruptionDays) || input.interruptionDays < 0) fail("DATE");
  const limit = addDays(input.ended.endDate, input.interruptionDays);
  const sameAccountContinues = input.remaining.some(
    (assignment) =>
      assignment.personId === input.ended.personId &&
      assignment.payrollAccountId === input.ended.payrollAccountId &&
      assignment.nextEarningsDate <= limit,
  );
  const roes = sameAccountContinues
    ? []
    : [{ personId: input.ended.personId, payrollAccountId: input.ended.payrollAccountId }];
  const leaveSettles = !input.remaining.some(
    (assignment) => assignment.personId === input.ended.personId && assignment.leavePlanId === input.ended.leavePlanId,
  );
  const stillHeld = input.positionHolders.some(
    (holder) => holder.positionId === input.ended.positionId && holder.assignmentId !== input.ended.assignmentId,
  );
  const employmentContinues = input.remaining.some(
    (assignment) => assignment.personId === input.ended.personId && assignment.employmentId === input.ended.employmentId,
  );
  let previous = new D(input.ended.weeklyHours);
  let after = new D(0);
  for (const assignment of input.remaining) {
    if (assignment.personId === input.ended.personId) {
      const hours = new D(assignment.weeklyHours);
      previous = previous.plus(hours);
      after = after.plus(hours);
    }
  }
  const drop = previous.minus(after);
  const hoursDropReview = previous.gt(0) && drop.div(previous).gt(new D(input.hoursDropShare));
  const statutoryNoticeTriggered = !employmentContinues || input.constructiveDismissal || input.layoff;
  return {
    roes,
    leaveSettles,
    benefitsReevaluated: true,
    positionVacated: !stillHeld,
    duesStopped: !input.continuingDuesObligation,
    hoursDropReview,
    statutoryNoticeTriggered,
    changeSetKind: employmentContinues ? "assignment.end" : "employment.terminate",
    futureShiftsCancelled: true,
  };
}

export function transferEmployer(input: {
  fromPayrollAccountId: string;
  toPayrollAccountId: string;
  carrySeniority: boolean;
}): {
  newEmployment: true;
  newPayrollAccountId: string;
  roePayrollAccountId: string;
  seniorityCarried: boolean;
} {
  if (input.fromPayrollAccountId === input.toPayrollAccountId) fail("INPUT_REQUIRED");
  if (input.fromPayrollAccountId.trim() === "" || input.toPayrollAccountId.trim() === "") fail("INPUT_REQUIRED");
  return {
    newEmployment: true,
    newPayrollAccountId: input.toPayrollAccountId,
    roePayrollAccountId: input.fromPayrollAccountId,
    seniorityCarried: input.carrySeniority,
  };
}

export type RoePeriod = { number: number; amount: string; hours: string };

export type RoeDraft = {
  payrollAccountId: string;
  reasonCode: string;
  periods: { number: number; amount: string; hours: string }[];
  blocks: { block: string; amount: string }[];
  dueDate: string;
  amended: boolean;
};

export function draftRoe(input: {
  payrollAccountId: string;
  separationReason: string;
  reasonMap: Readonly<Record<string, string>>;
  periods: readonly RoePeriod[];
  vacation: { block: string; amount: string };
  severance: { block: string; amount: string };
  deadlineDays: number;
  finalPayPeriodEnd: string;
  amended: boolean;
}): RoeDraft {
  const reasonCode = input.reasonMap[input.separationReason];
  if (reasonCode === undefined || reasonCode.trim() === "") fail("REASON_UNMAPPED");
  if (input.periods.length === 0) fail("INPUT_REQUIRED");
  if (input.vacation.block.trim() === "" || input.severance.block.trim() === "") fail("INPUT_REQUIRED");
  if (!Number.isInteger(input.deadlineDays) || input.deadlineDays < 0) fail("DATE");
  return {
    payrollAccountId: input.payrollAccountId,
    reasonCode,
    periods: input.periods.map((period) => ({
      number: period.number,
      amount: money(period.amount),
      hours: period.hours,
    })),
    blocks: [
      { block: input.vacation.block, amount: money(input.vacation.amount) },
      { block: input.severance.block, amount: money(input.severance.amount) },
    ],
    dueDate: addDays(input.finalPayPeriodEnd, input.deadlineDays),
    amended: input.amended,
  };
}
