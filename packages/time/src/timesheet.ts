import { cmp, hours, mul, sub, TimeError } from "./money.ts";

export function employeeConfirmation(confirmed: boolean, confirmedAt?: string): {
  reminders: boolean;
  payrollProceeds: true;
  employeeConfirmedAt: string | null;
} {
  return {
    reminders: !confirmed,
    payrollProceeds: true,
    employeeConfirmedAt: confirmed ? (confirmedAt ?? "recorded") : null,
  };
}

export function escalateTimesheet(input: {
  approved: boolean;
  workingDaysWaiting: number;
  escalateAfter: number;
  beforeCutoff: boolean;
  nextManagerId: string;
}): { escalateTo?: string } {
  if (!input.approved && input.beforeCutoff && input.workingDaysWaiting >= input.escalateAfter) {
    return { escalateTo: input.nextManagerId };
  }
  return {};
}

export function approveTimesheet(input: {
  employeeId: string;
  approverId: string;
  overtimeHours: string;
  route?: { minOvertimeHours: string; secondApproverId?: string; secondApproved?: boolean };
  restOrHoursBreach?: boolean;
  cautionReason?: string;
  multiRateUnverified?: boolean;
  unresolvedInteraction?: boolean;
}): { approved: true } {
  if (input.approverId === input.employeeId) throw new TimeError("SELF_APPROVAL");
  if (input.route?.secondApproverId === input.employeeId) throw new TimeError("SELF_APPROVAL");
  if (input.multiRateUnverified) throw new TimeError("RULE_NOT_VERIFIED");
  if (input.unresolvedInteraction) throw new TimeError("UNRESOLVED_INTERACTION");
  if (input.restOrHoursBreach && (!input.cautionReason || input.cautionReason.trim() === "")) {
    throw new TimeError("CAUTION_NOT_ACKNOWLEDGED");
  }
  const needsSecond = Boolean(input.route && cmp(hours(input.overtimeHours), hours(input.route.minOvertimeHours)) >= 0);
  if (needsSecond && !input.route?.secondApproved) throw new TimeError("ROUTE_APPROVALS_MISSING");
  return { approved: true };
}

export function lockUnapprovedTimesheet(): { locked: true; paidAsRecorded: true; reviewedAfterLockBy: null } {
  return { locked: true, paidAsRecorded: true, reviewedAfterLockBy: null };
}

export function reviewAfterLock(reviewerId: string): { reviewedAfterLockBy: string } {
  if (!reviewerId) throw new TimeError("INPUT_REQUIRED");
  return { reviewedAfterLockBy: reviewerId };
}

export function correctLockedPeriod(input: {
  date: string;
  fromHours: string;
  toHours: string;
  rate: string;
  lawDeadlineInDays: number;
  nextRegularInDays: number;
  aboveAmount?: string;
}): {
  retroLines: { date: string; hours: string; amount: string; ruleSource: string }[];
  run: "next_regular" | "off_cycle";
  originalEdited: false;
} {
  const difference = sub(hours(input.toHours), hours(input.fromHours));
  const amount = mul(difference, input.rate);
  const amountTrigger = Boolean(input.aboveAmount && input.aboveAmount.trim() !== "" && cmp(amount, input.aboveAmount) > 0);
  const deadlineTrigger = input.nextRegularInDays > input.lawDeadlineInDays;
  return {
    retroLines: [
      {
        date: input.date,
        hours: difference,
        amount,
        ruleSource: "time.corrected",
      },
    ],
    run: deadlineTrigger || amountTrigger ? "off_cycle" : "next_regular",
    originalEdited: false,
  };
}
