import Decimal from "decimal.js";
import { add, cmp, div, hours, sub, sum, TimeError } from "./money.ts";

export type LedgerEntry = { date: string; hours: string; kind: "opening" | "accrual" | "taken" | "adjustment" };

export function leaveBalance(entries: LedgerEntry[], asOf: string): string {
  const included = entries.filter((entry) => entry.date <= asOf);
  const credits = sum(included.filter((entry) => entry.kind !== "taken").map((entry) => hours(entry.hours)));
  const taken = sum(included.filter((entry) => entry.kind === "taken").map((entry) => hours(entry.hours)));
  return sub(credits, taken);
}

export function planCycleStart(input: {
  yearBasis: "calendar" | "fiscal" | "hire" | "service" | "plan_entry";
  on: string;
  fiscalMonthDay?: string;
  hireDate?: string;
  serviceDate?: string;
  planEntryDate?: string;
}): string {
  if (input.yearBasis === "calendar") return `${input.on.slice(0, 4)}-01-01`;
  if (input.yearBasis === "fiscal") {
    if (!input.fiscalMonthDay) throw new TimeError("INPUT_REQUIRED");
    return anniversaryOnOrBefore(`${input.on.slice(0, 4)}-${input.fiscalMonthDay}`, input.on);
  }
  const anchor = input.yearBasis === "hire" ? input.hireDate : input.yearBasis === "service" ? input.serviceDate : input.planEntryDate;
  if (!anchor) throw new TimeError("INPUT_REQUIRED");
  return anniversaryOnOrBefore(anchor, input.on);
}

export function tierStepDate(input: { basis: "plan_year" | "hire" | "service" | "plan_entry"; on: string; planYearStart?: string; hireDate?: string; serviceDate?: string; planEntryDate?: string }): string {
  if (input.basis === "plan_year") {
    if (!input.planYearStart) throw new TimeError("INPUT_REQUIRED");
    return input.planYearStart;
  }
  return planCycleStart({
    yearBasis: input.basis,
    on: input.on,
    hireDate: input.hireDate,
    serviceDate: input.serviceDate,
    planEntryDate: input.planEntryDate,
  });
}

function anniversaryOnOrBefore(anchor: string, on: string): string {
  const monthDay = anchor.slice(5);
  const year = Number(on.slice(0, 4));
  const candidate = `${year}-${monthDay}`;
  return candidate <= on ? candidate : `${year - 1}-${monthDay}`;
}

export function validateCarryOver(mode?: string): "none" | "limited" | "unlimited" {
  if (mode === "none" || mode === "limited" || mode === "unlimited") return mode;
  throw new TimeError("LEAVE_CARRYOVER_INVALID");
}

export function carryOverHours(input: { balance: string; statutoryHours: string; mode: "none" | "limited" | "unlimited"; limitHours?: string }): string {
  const balance = hours(input.balance);
  const statutory = hours(input.statutoryHours);
  const keptStatutory = cmp(balance, statutory) > 0 ? statutory : balance;
  const extra = cmp(balance, statutory) > 0 ? sub(balance, statutory) : "0.00";
  if (input.mode === "unlimited") return balance;
  if (input.mode === "none") return keptStatutory;
  if (!input.limitHours) throw new TimeError("LEAVE_CARRYOVER_INVALID");
  const keptExtra = cmp(extra, hours(input.limitHours)) > 0 ? hours(input.limitHours) : extra;
  return add(keptStatutory, keptExtra);
}

export function requestAgainstBalance(input: { available: string; requested: string; negativeLimitHours?: string }): { balanceAfter: string } {
  const limit = input.negativeLimitHours === undefined ? "0.00" : hours(input.negativeLimitHours);
  const after = sub(hours(input.available), hours(input.requested));
  if (cmp(after, sub("0.00", limit)) < 0) throw new TimeError("LEAVE_BALANCE_INSUFFICIENT");
  return { balanceAfter: after };
}

const PAYOUT_STARTER: Record<string, "all" | "none"> = {
  vacation: "all",
  sick: "none",
  personal: "none",
};

export function terminationPayout(input: { category: string; payout?: "all" | "law" | "none" }): "all" | "law" | "none" {
  if (input.category === "vacation" && input.payout === "none") throw new TimeError("LEAVE_PAYOUT_BELOW_LAW");
  if (input.payout) return input.payout;
  const starter = PAYOUT_STARTER[input.category];
  if (!starter) throw new TimeError("INPUT_REQUIRED");
  return starter;
}

export function greaterLeaveDays(input: { agreementDays: string; statuteDays: string; agreementSource: string; statuteSource: string }): { days: string; source: string } {
  if (cmp(hours(input.agreementDays), hours(input.statuteDays)) >= 0) {
    return { days: hours(input.agreementDays), source: input.agreementSource };
  }
  return { days: hours(input.statuteDays), source: input.statuteSource };
}

export const PROTECTED_CATEGORIES = ["domestic_violence", "medical", "family_caregiver", "disability", "workers_compensation"];

export function assertLeaveProtection(input: { category: string; protected: boolean }): void {
  if (input.category === "domestic_violence" && !input.protected) throw new TimeError("LEAVE_REASON_MUST_BE_PROTECTED");
}

export function leaveVisibility(input: { category: string; leaveType: string; reason: string; audience: "manager" | "hr" | "coworker"; protectedCategories?: string[] }): { label: string; reason?: string } {
  if (input.audience === "coworker") return { label: "away" };
  const protectedCategories = input.protectedCategories ?? PROTECTED_CATEGORIES;
  const isProtected = input.category === "domestic_violence" || protectedCategories.includes(input.category);
  if (input.audience === "hr") return { label: input.leaveType, reason: input.reason };
  if (isProtected) return { label: "protected leave" };
  return { label: input.leaveType };
}

export function recordSickNote(): never {
  throw new TimeError("SICK_NOTE_NOT_ALLOWED");
}

const NEVER_COUNT = new Set([
  "medical",
  "pregnancy",
  "parental",
  "family_caregiver",
  "bereavement",
  "domestic_violence",
  "indigenous_practices",
  "civic",
  "public_health",
  "disability",
  "workers_compensation",
  "union_business",
]);

export function issueAttendanceStage(input: {
  programEnabled: boolean;
  statutory?: boolean;
  protectedReason?: boolean;
  category?: string;
  stage: number;
  disciplinary: boolean;
  accommodationConsidered: boolean;
  hrReviewed: boolean;
  openedBy: string;
  reviewerId?: string;
}): { issued: true } {
  if (!input.programEnabled) throw new TimeError("ATTENDANCE_PROGRAM_OFF");
  if (input.statutory || input.protectedReason || (input.category && NEVER_COUNT.has(input.category))) {
    throw new TimeError("ATTENDANCE_PROTECTED_ABSENCE");
  }
  if (input.stage > 1 && !input.accommodationConsidered) throw new TimeError("ACCOMMODATION_NOT_CONSIDERED");
  if (input.disciplinary && (!input.hrReviewed || !input.reviewerId || input.reviewerId === input.openedBy)) {
    throw new TimeError("HR_REVIEW_REQUIRED");
  }
  return { issued: true };
}

export function longAbsencePrompt(consecutiveWorkingDays: number, afterDays = 5): { promptHr: boolean } {
  return { promptHr: consecutiveWorkingDays >= afterDays + 1 };
}

export function teamAvailability(input: { minimum?: number; away: number; teamSize: number; blackout: boolean }): { level: "green" | "amber" | "red" | "unknown" } {
  if (input.blackout) return { level: "red" };
  if (input.minimum === undefined) return { level: "unknown" };
  const remaining = input.teamSize - input.away - 1;
  if (remaining > input.minimum) return { level: "green" };
  if (remaining === input.minimum) return { level: "amber" };
  return { level: "red" };
}

export function declineLeave(input: { statutory: boolean; category?: "staffing" | "blackout" | "balance" | "other"; reason?: string }): { declined: true; category: string; reason: string } {
  if (!input.category || !input.reason || input.reason.trim() === "") throw new TimeError("INPUT_REQUIRED");
  if (input.statutory && (input.category === "staffing" || input.category === "blackout")) {
    throw new TimeError("STATUTORY_LEAVE_NOT_REFUSABLE");
  }
  return { declined: true, category: input.category, reason: input.reason };
}

export function holidaysFor(input: {
  year: number;
  locationJurisdiction: string;
  regulatory: "federal" | "provincial";
  calendar: { name: string; monthDay: string; jurisdiction: string }[];
}): { name: string; date: string; jurisdiction: string }[] {
  return input.calendar
    .filter((row) => row.jurisdiction === input.locationJurisdiction || (input.regulatory === "federal" && row.jurisdiction === "FED"))
    .map((row) => ({ name: row.name, date: `${input.year}-${row.monthDay}`, jurisdiction: row.jurisdiction }));
}

export function openLongLeave(kind: "parental" | "pregnancy" | "compassionate"): {
  kind: string;
  statusChange: true;
  roeTrigger: true;
  benefitsContinuationChoice: true;
  seniorityContinuation: true;
  returnToWorkTask: true;
} {
  return {
    kind,
    statusChange: true,
    roeTrigger: true,
    benefitsContinuationChoice: true,
    seniorityContinuation: true,
    returnToWorkTask: true,
  };
}

export function splitLeaveRequest(input: {
  assignments: { id: string; approverId: string }[];
  decisions?: { assignmentId: string; declined: boolean }[];
}): { components: { assignmentId: string; approverId: string }[]; status: "pending" | "approved" | "partially_approved" | "declined" } {
  const components = input.assignments.map((assignment) => ({ assignmentId: assignment.id, approverId: assignment.approverId }));
  const decisions = input.decisions ?? [];
  if (decisions.length === 0) return { components, status: "pending" };
  const declined = decisions.filter((decision) => decision.declined).length;
  if (declined === 0) return { components, status: "approved" };
  if (declined === decisions.length && decisions.length === components.length) return { components, status: "declined" };
  return { components, status: "partially_approved" };
}

export function leavePlanFor(plans: { code: string; priority: number }[]): { code: string } {
  if (plans.length === 0) throw new TimeError("LEAVE_PLAN_MISSING");
  const best = Math.min(...plans.map((plan) => plan.priority));
  const winners = plans.filter((plan) => plan.priority === best);
  if (winners.length > 1) throw new TimeError("LEAVE_PLAN_AMBIGUOUS");
  return { code: winners[0].code };
}

export function statutoryVacationTopUp(input: { plans: { code: string; hours: string; primary?: boolean }[]; statutoryMinimumHours: string }): { topUpHours: string; planCode: string; total: string } {
  if (input.plans.length === 0) throw new TimeError("LEAVE_PLAN_MISSING");
  const total = sum(input.plans.map((plan) => hours(plan.hours)));
  const minimum = hours(input.statutoryMinimumHours);
  const topUpHours = cmp(total, minimum) < 0 ? sub(minimum, total) : "0.00";
  const primary = input.plans.find((plan) => plan.primary) ?? input.plans[0];
  return { topUpHours, planCode: primary.code, total };
}

export function allocateByShare(total: string, parts: { id: string; weight: string }[]): { id: string; amount: string }[] {
  const weightSum = parts.reduce((totalWeight, part) => totalWeight.plus(part.weight), new Decimal(0));
  if (weightSum.isZero()) throw new TimeError("INPUT_REQUIRED");
  const totalCents = new Decimal(total).times(100);
  const raw = parts.map((part, index) => {
    const exact = totalCents.times(part.weight).div(weightSum);
    const floor = exact.floor();
    return { id: part.id, index, floor, frac: exact.minus(floor) };
  });
  let remainder = totalCents.minus(raw.reduce((totalFloor, part) => totalFloor.plus(part.floor), new Decimal(0)));
  const order = [...raw].sort((left, right) => right.frac.comparedTo(left.frac) || left.index - right.index);
  const extra = new Map<string, Decimal>();
  for (const part of order) {
    if (remainder.lte(0)) break;
    extra.set(part.id, new Decimal(1));
    remainder = remainder.minus(1);
  }
  return raw.map((part) => ({
    id: part.id,
    amount: part.floor.plus(extra.get(part.id) ?? 0).div(100).toFixed(2),
  }));
}

export function employerHolidayPay(input: {
  assignments: { id: string; wages: string; agreementHoliday: string; cashInLieu: string }[];
  divisor: string;
}): { statutory: string; agreement: string; paid: string; greater: "statute" | "agreement"; allocation: { id: string; amount: string }[] } {
  const wages = sum(input.assignments.map((assignment) => assignment.wages));
  const statutory = div(wages, input.divisor);
  const agreement = sum(input.assignments.map((assignment) => add(assignment.agreementHoliday, assignment.cashInLieu)));
  const paid = cmp(agreement, statutory) > 0 ? agreement : statutory;
  return {
    statutory,
    agreement,
    paid,
    greater: cmp(agreement, statutory) > 0 ? "agreement" : "statute",
    allocation: allocateByShare(paid, input.assignments.map((assignment) => ({ id: assignment.id, weight: assignment.wages }))),
  };
}

export function settleBankedTime(input: {
  unusedHours: string;
  policy?: { action: "pay_out" | "carry_over" | "carry_then_pay"; carryLimitHours?: string };
  lawCapHours?: string;
}): { carried: string; paid: string } {
  if (!input.policy) throw new TimeError("BANKED_TIME_POLICY_MISSING");
  const unused = hours(input.unusedHours);
  let carried = "0.00";
  let paid = "0.00";
  if (input.policy.action === "pay_out") paid = unused;
  else if (input.policy.action === "carry_over") carried = unused;
  else {
    const limit = hours(input.policy.carryLimitHours ?? "0.00");
    carried = cmp(unused, limit) > 0 ? limit : unused;
    paid = sub(unused, carried);
  }
  if (input.lawCapHours !== undefined && cmp(carried, hours(input.lawCapHours)) > 0) {
    paid = add(paid, sub(carried, hours(input.lawCapHours)));
    carried = hours(input.lawCapHours);
  }
  return { carried, paid };
}

export function requestBankedPayout(input: {
  policy?: { employeePayoutRequests: boolean };
  hours: string;
  balance: string;
  requesterId: string;
  approverId: string;
  routeComplete: boolean;
}): { paidHours: string } {
  if (!input.policy) throw new TimeError("BANKED_TIME_POLICY_MISSING");
  if (!input.policy.employeePayoutRequests) throw new TimeError("BANKED_PAYOUT_NOT_ALLOWED");
  if (input.requesterId === input.approverId) throw new TimeError("SELF_APPROVAL");
  if (!input.routeComplete) throw new TimeError("ROUTE_APPROVALS_MISSING");
  if (cmp(hours(input.hours), hours(input.balance)) > 0) throw new TimeError("INPUT_REQUIRED");
  return { paidHours: hours(input.hours) };
}
