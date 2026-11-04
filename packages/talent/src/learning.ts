import { addDays, addMonths, daysBetween } from "./dates.ts";
import { D, money } from "./decimal.ts";
import { fail } from "./errors.ts";
import { completeRoute, sameTenant, type Approval } from "./routes.ts";
import { screen, type ScreenLang } from "./text.ts";

export type LawRequirement = {
  requirement_code: string;
  before_work: boolean;
  due_days: number | null;
  frequency_months: number | null;
  status: string;
};

export type TrainingRule = {
  source: "law" | "organization";
  requirementCode: string | null;
  dueDays: number | null;
  frequencyMonths: number | null;
  graceDays: number;
  beforeWork: boolean;
};

export function loadLawRequirements(requirements: readonly LawRequirement[]): LawRequirement[] {
  return requirements.slice();
}

export function acceptTrainingRule(rule: TrainingRule, law: LawRequirement | null): TrainingRule {
  if (rule.source === "law") {
    if (law === null) fail("INPUT_REQUIRED");
    if (law.status === "verify_at_load") fail("RULE_NOT_VERIFIED");
    if (rule.graceDays > 0) fail("TRAINING_RULE_LOOSER_THAN_LAW");
    if (law.before_work && !rule.beforeWork) fail("TRAINING_RULE_LOOSER_THAN_LAW");
    if (law.due_days !== null && (rule.dueDays === null || rule.dueDays > law.due_days)) fail("TRAINING_RULE_LOOSER_THAN_LAW");
    if (law.frequency_months !== null && (rule.frequencyMonths === null || rule.frequencyMonths > law.frequency_months)) {
      fail("TRAINING_RULE_LOOSER_THAN_LAW");
    }
  }
  return rule;
}

export function waiveAssignment(requiredByLaw: boolean): void {
  if (requiredByLaw) fail("LEGAL_TASK_CANNOT_BE_WAIVED");
}

export function assignTraining(input: { personType: string; employmentId: string | null; language: string }): { assigned: true; language: string } {
  if (input.personType === "employee" && (input.employmentId === null || input.employmentId.trim() === "")) fail("INPUT_REQUIRED");
  return { assigned: true, language: input.language };
}

export function signOffTraining(input: { learnerId: string; signerId: string }): { signerId: string } {
  if (input.learnerId === input.signerId) fail("SIGNOFF_REQUIRED");
  return { signerId: input.signerId };
}

export function completeMandatory(input: {
  outsideScheduledHours: boolean;
  minutes: number | null;
}): { timesheetMinutes: number | null } {
  if (input.outsideScheduledHours && (input.minutes === null || input.minutes <= 0)) fail("INPUT_REQUIRED");
  return { timesheetMinutes: input.outsideScheduledHours ? input.minutes : null };
}

export function nextDueOn(input: { dueOn: string; completedOn: string; frequencyMonths: number; earlyWindowDays: number }): string {
  const windowStart = addDays(input.dueOn, -input.earlyWindowDays);
  if (input.completedOn >= windowStart && input.completedOn <= input.dueOn) return addMonths(input.dueOn, input.frequencyMonths);
  return addMonths(input.completedOn, input.frequencyMonths);
}

export function lawChangeDue(input: { effectiveOn: string; lawDueDays: number | null; organizationDueDays: number }): string {
  const days = input.lawDueDays === null ? input.organizationDueDays : input.lawDueDays;
  return addDays(input.effectiveOn, days);
}

export type Notice = { who: "employee" | "manager" | "hr"; on: string };

export function learningNotices(input: {
  dueOn: string;
  employeeDaysBefore: readonly number[];
  managerDaysAfter: number;
  hrDaysAfter: number;
  graceDays: number;
}): Notice[] {
  const due = addDays(input.dueOn, input.graceDays);
  const notices: Notice[] = [];
  for (const days of input.employeeDaysBefore) notices.push({ who: "employee", on: addDays(due, -days) });
  notices.push({ who: "manager", on: addDays(due, input.managerDaysAfter) });
  notices.push({ who: "hr", on: addDays(due, input.hrDaysAfter) });
  return notices;
}

export function verifyCredential(input: { holderId: string; verifierId: string }): { valid: true } {
  if (input.holderId === input.verifierId) fail("SELF_APPROVAL");
  if (input.verifierId.trim() === "") fail("INPUT_REQUIRED");
  return { valid: true };
}

export function credentialAlerts(input: { expiresOn: string; employeeDays: readonly number[]; managerHrDays: readonly number[] }): Notice[] {
  const notices: Notice[] = [];
  for (const days of input.employeeDays) notices.push({ who: "employee", on: addDays(input.expiresOn, -days) });
  for (const days of input.managerHrDays) {
    const on = days === 0 ? input.expiresOn : addDays(input.expiresOn, -days);
    notices.push({ who: "manager", on });
    notices.push({ who: "hr", on });
  }
  return notices;
}

export function credentialValid(input: { verified: boolean; expiresOn: string; on: string }): boolean {
  if (!input.verified) return false;
  return input.on < input.expiresOn;
}

export function continuingEducation(input: { requiredHours: string; completedHours: string }): { completed: string; remaining: string } {
  const required = new D(input.requiredHours);
  const completed = new D(input.completedHours);
  const remaining = required.minus(completed);
  return { completed: money(input.completedHours), remaining: money(remaining.lt(0) ? "0" : remaining.toFixed()) };
}

export function apprenticeshipHours(input: { onTheJob: string; technical: string }): { onTheJob: string; technical: string } {
  return { onTheJob: money(input.onTheJob), technical: money(input.technical) };
}

export function publishShift(input: {
  credentialRequiredByLaw: boolean;
  credentialValid: boolean;
  otherGap: boolean;
  cautionAcknowledged: boolean;
  cautionReason: string;
}): { ready: boolean } {
  if (input.credentialRequiredByLaw && !input.credentialValid) fail("CREDENTIAL_REQUIRED_BY_LAW");
  if (input.otherGap && (!input.cautionAcknowledged || input.cautionReason.trim() === "")) fail("CAUTION_NOT_ACKNOWLEDGED");
  return { ready: !input.otherGap };
}

export function skillsVisible(optedIn: boolean): boolean {
  return optedIn;
}

export function agreeDevelopmentPlan(input: { employeeAgreed: boolean; managerAgreed: boolean }): { agreed: true } {
  if (!input.employeeAgreed || !input.managerAgreed) fail("PLAN_NOT_AGREED");
  return { agreed: true };
}

export function changeDevelopmentPlan(input: { by: string; reason: string; before: string; after: string }): typeof input {
  if (input.by.trim() === "" || input.reason.trim() === "") fail("INPUT_REQUIRED");
  return input;
}

export function trainingRequestRoute(input: {
  cost: string;
  hrAbove: string | null;
  steps: readonly { role: string }[];
  approvals: readonly Approval[];
  employeeId: string;
  overBudget: boolean;
  budgetCaution: boolean;
  budgetReason: string;
}): { needsHr: boolean } {
  if (input.hrAbove === null) fail("SETTING_NOT_SET");
  const needsHr = new D(input.cost).gt(new D(input.hrAbove));
  const steps = needsHr ? input.steps : input.steps.filter((step) => step.role !== "hr");
  completeRoute({ steps, approvals: input.approvals, blockedApproverIds: [input.employeeId] });
  if (input.overBudget && (!input.budgetCaution || input.budgetReason.trim() === "")) fail("CAUTION_NOT_ACKNOWLEDGED");
  return { needsHr };
}

export function markForCra(marked: boolean): void {
  if (!marked) fail("INPUT_REQUIRED");
}

export type RepaymentRule = { id: string; kind: string; method: "none" | "prorated" | "full"; months: number; minCost: string; maxCost: string | null };

export function repaymentFor(input: {
  kind: string;
  cost: string;
  rules: readonly RepaymentRule[];
  withoutRule: "hr_decides" | "none" | null;
}): { rule: RepaymentRule | null; hrDecides: boolean } {
  const cost = new D(input.cost);
  const matched = input.rules.filter((rule) => {
    if (rule.kind !== input.kind) return false;
    if (cost.lt(new D(rule.minCost))) return false;
    if (rule.maxCost !== null && cost.gt(new D(rule.maxCost))) return false;
    return true;
  });
  if (matched.length > 1) fail("REPAYMENT_RULE_AMBIGUOUS");
  if (matched.length === 1) return { rule: matched[0], hrDecides: false };
  if (input.withoutRule === null) fail("SETTING_NOT_SET");
  if (input.withoutRule === "hr_decides") return { rule: null, hrDecides: true };
  return { rule: null, hrDecides: false };
}

export function reimburse(input: { agreementRequired: boolean; agreementSigned: boolean; craMarked: boolean }): { reimbursed: true } {
  if (!input.craMarked) fail("INPUT_REQUIRED");
  if (input.agreementRequired && !input.agreementSigned) fail("REPAYMENT_AGREEMENT_REQUIRED");
  return { reimbursed: true };
}

export function repaymentOwed(input: { cost: string; months: number; monthsWorked: number; authorization: string | null }): { owed: string; recoverable: boolean } {
  const remaining = input.months - input.monthsWorked;
  const owed = new D(input.cost).mul(remaining).div(input.months);
  const amount = money(owed.toFixed());
  if (new D(amount).gt(0) && (input.authorization === null || input.authorization.trim() === "")) {
    return { owed: amount, recoverable: false };
  }
  return { owed: amount, recoverable: new D(amount).gt(0) };
}

export function grantClaim(input: { amount: string; eligible: string }): { amount: string } {
  if (new D(input.amount).gt(new D(input.eligible))) fail("INPUT_REQUIRED");
  return { amount: money(input.amount) };
}

export function mentorSession(input: { mentorId: string; learnerId: string; seats: number; taken: number }): { waitlisted: boolean } {
  if (input.mentorId === input.learnerId) fail("INPUT_REQUIRED");
  if (input.taken >= input.seats) fail("SESSION_FULL");
  return { waitlisted: false };
}

export function catalogueItem(input: { kind: "lms_link" | "session" | "partner_link"; url: string; language: ScreenLang }): { playsInCanDo: false; url: string; note: string } {
  if (input.url.trim() === "") fail("INPUT_REQUIRED");
  return { playsInCanDo: false, url: input.url, note: screen[input.language].noPlayer };
}

export function suggestFromRules(rules: readonly { code: string; reason: string }[]): { code: string; reason: string }[] {
  return rules.slice();
}

export function recordQuebecSpend(amount: string): { eligible: string } {
  return { eligible: money(amount) };
}

export function quebecObligationReport(): never {
  fail("QUEBEC_PHASE_2");
}

export function readLearning<T>(recordTenant: string, readerTenant: string, rows: readonly T[]): T[] {
  return sameTenant(recordTenant, readerTenant, rows);
}

export function noticeOn(notices: readonly Notice[], who: Notice["who"], on: string): boolean {
  return notices.some((notice) => notice.who === who && notice.on === on);
}

export function daysFrom(from: string, to: string): number {
  return daysBetween(from, to);
}
