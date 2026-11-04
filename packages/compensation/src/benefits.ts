import { addDays } from "./dates.ts";
import { HUNDRED, ZERO, dec, moneyStr } from "./decimal.ts";
import { fail } from "./errors.ts";
import { approveSteps, type Step } from "./compensation.ts";
import { fill, screen, type ScreenLang } from "./text.ts";

function present(value: unknown): boolean {
  return value !== undefined && value !== null && value !== "";
}

export type WaitingRule = { kind: "months"; months: number } | { kind: "first_of_month_after"; months: number };

export function validateWaiting(rule: { kind?: string; months?: number; text?: string } | null): WaitingRule {
  if (rule === null || rule === undefined) fail("INPUT_REQUIRED", "waiting");
  if (rule.text !== undefined) fail("WAITING_RULE_INVALID", rule.text);
  if (rule.kind === "weeks") fail("WAITING_RULE_INVALID");
  if ((rule.kind === "months" || rule.kind === "first_of_month_after") && typeof rule.months === "number") {
    return { kind: rule.kind, months: rule.months };
  }
  fail("WAITING_RULE_INVALID");
}

export function combinedFte(assignments: { fte: string; inScope: boolean }[]): string {
  let total = ZERO;
  for (const assignment of assignments) {
    if (assignment.inScope) total = total.plus(dec(assignment.fte));
  }
  return moneyStr(total);
}

export function enrolmentTask(input: {
  assignments: { fte: string; inScope: boolean }[];
  minFte: string;
  waitingMet: boolean;
  fteNow: string;
}): { task: "enrol" | null; proposedEnd: boolean; applied: false } {
  if (!present(input.minFte)) fail("INPUT_REQUIRED", "minFte");
  const eligible = dec(combinedFte(input.assignments)).gte(dec(input.minFte)) && input.waitingMet;
  const dropped = dec(input.fteNow).lt(dec(input.minFte));
  return { task: eligible && !dropped ? "enrol" : null, proposedEnd: dropped, applied: false };
}

export function lifeEventWindow(input: { planDays: number | null; orgDays: number | null }): number {
  if (input.planDays !== null && input.planDays !== undefined) return input.planDays;
  if (input.orgDays !== null && input.orgDays !== undefined) return input.orgDays;
  fail("SETTING_NOT_SET", "benefits.life_event_window_days");
}

export function electionCosts(input: {
  employeePerPay: string;
  employerPerPay: string;
  taxTiming: "pre_tax" | "post_tax";
  benefitKind: string;
  jurisdiction: string;
  taxableBenefitRule: string | null;
}): { employee: string; employer: string; taxTiming: string; taxableBenefit: string | null } {
  if (input.jurisdiction === "QC" && input.benefitKind === "health" && input.taxableBenefitRule === "employer_paid") {
    fail("QUEBEC_PHASE_2");
  }
  let taxable: string | null = null;
  if (input.taxableBenefitRule === "employer_paid") taxable = input.employerPerPay;
  return {
    employee: input.employeePerPay,
    employer: input.employerPerPay,
    taxTiming: input.taxTiming,
    taxableBenefit: taxable,
  };
}

export function premiumArrears(input: { netPay: string; premium: string; recoveryRule: string }): { taken: string; arrears: string; coverageCancelled: false } {
  if (!present(input.recoveryRule)) fail("INPUT_REQUIRED", "arrears_recovery");
  const net = dec(input.netPay);
  const premium = dec(input.premium);
  if (input.recoveryRule === "skip" || net.lte(ZERO)) {
    return { taken: moneyStr(ZERO), arrears: moneyStr(premium), coverageCancelled: false };
  }
  const taken = net.lt(premium) ? net : premium;
  return { taken: moneyStr(taken), arrears: moneyStr(premium.minus(taken)), coverageCancelled: false };
}

export function leaveContribution(input: {
  statutory: boolean;
  declineForStaffing: boolean;
  method: string;
  offered: string[];
  classRule: string | null;
}): { method: string } {
  if (input.statutory && input.declineForStaffing) fail("STATUTORY_LEAVE_FOLLOWS_LAW");
  if (!input.statutory && !present(input.classRule)) fail("LEAVE_BENEFIT_RULE_MISSING");
  let allowed = false;
  for (const way of input.offered) if (way === input.method) allowed = true;
  if (!allowed) fail("LEAVE_CONTRIBUTION_METHOD_NOT_ALLOWED");
  return { method: input.method };
}

export function variableHoursProposal(input: { averageHours: string; testHours: string }): { proposal: "eligible" | "not_eligible"; applied: false } {
  const proposal = dec(input.averageHours).gte(dec(input.testHours)) ? "eligible" : "not_eligible";
  return { proposal, applied: false };
}

export function requireLateEnrolment(rule: string | null): string {
  if (!present(rule)) fail("INPUT_REQUIRED", "late_enrolment");
  return String(rule);
}

export function evidenceOfInsurability(input: { planKind: string; required: boolean }): { required: boolean } {
  if (input.planKind === "life") return { required: input.required };
  return { required: false };
}

export function openEnrolment(input: { didNothing: boolean; elections: string[]; flex: boolean; flexDefault: string | null }): { elections: string[] } {
  if (!input.didNothing) return { elections: input.elections };
  if (input.flex) {
    if (!present(input.flexDefault)) fail("INPUT_REQUIRED", "flexDefault");
    return { elections: [String(input.flexDefault)] };
  }
  return { elections: input.elections };
}

export function governingAgreement(input: { agreements: string[]; choice?: string; reason?: string }): { agreement: string } {
  if (input.agreements.length === 1) return { agreement: input.agreements[0] };
  if (!present(input.choice)) fail("GOVERNING_AGREEMENT_NOT_SET");
  if (!present(input.reason)) fail("INPUT_REQUIRED", "reason");
  let found = false;
  for (const agreement of input.agreements) if (agreement === input.choice) found = true;
  if (!found) fail("GOVERNING_AGREEMENT_NOT_SET");
  return { agreement: String(input.choice) };
}

export function cobOrder(input: { plans: string[]; order?: string[]; reason?: string }): { order: string[] } {
  if (input.plans.length < 2) return { order: input.plans };
  if (input.order === undefined || input.order.length === 0) fail("COB_ORDER_NOT_SET");
  if (!present(input.reason)) fail("INPUT_REQUIRED", "reason");
  return { order: input.order };
}

export function premiumAdjustment(input: { reachesBackMonths: number; allowedMonths: number | null; hrApprovedOlder: boolean }): { olderNeedsHr: boolean; applied: boolean } {
  if (input.allowedMonths === null || input.allowedMonths === undefined) fail("SETTING_NOT_SET", "benefits.premium_retro_months");
  const older = input.reachesBackMonths > input.allowedMonths;
  if (older && !input.hrApprovedOlder) return { olderNeedsHr: true, applied: false };
  return { olderNeedsHr: older, applied: true };
}

export function approveInvoice(input: { differencesListed: boolean; preparerId: string; approverId: string; steps: Step[] }): { approved: boolean } {
  if (!input.differencesListed) fail("INPUT_REQUIRED", "differences");
  if (input.approverId === input.preparerId) fail("SELF_APPROVAL");
  approveSteps(input.preparerId, input.steps);
  return { approved: true };
}

export function ageOutNotice(input: { birthday: string; leadDays: number }): { noticeOn: string; askProofOfStudies: true } {
  return { noticeOn: addDays(input.birthday, -input.leadDays), askProofOfStudies: true };
}

export type OptOutRule = { basis: string; drugRequiresOtherPrivatePlan: boolean } | null;

export function optOut(input: { kind: string; proof?: string; rule: OptOutRule; otherPrivatePlan: boolean }): { allowed: boolean; basis: string | null } {
  if ((input.kind === "dental" || input.kind === "health") && !present(input.proof)) {
    return { allowed: false, basis: "proof" };
  }
  if (input.kind === "drug") {
    if (input.rule === null) fail("JURISDICTION_RULE_MISSING");
    if (input.rule.drugRequiresOtherPrivatePlan && !input.otherPrivatePlan) {
      return { allowed: false, basis: input.rule.basis };
    }
  }
  if (!present(input.proof) && input.kind !== "drug") return { allowed: false, basis: "proof" };
  return { allowed: true, basis: input.rule === null ? null : input.rule.basis };
}

export function pensionSplit(input: {
  ytdBefore: string;
  thisPay: string;
  ympe: string;
  rateBelow: string;
  rateAbove: string;
  employeeShare: string;
  box52Rule: { kind: string; percent?: string; amount?: string } | null;
}): { below: string; above: string; employee: string; employer: string; box52: string } {
  if (!present(input.ympe) || !present(input.rateBelow) || !present(input.rateAbove)) fail("INPUT_REQUIRED", "pension");
  const room = dec(input.ympe).minus(dec(input.ytdBefore));
  const roomLeft = room.gt(ZERO) ? room : ZERO;
  const pay = dec(input.thisPay);
  const below = pay.lt(roomLeft) ? pay : roomLeft;
  const above = pay.minus(below);
  const contribution = below.mul(dec(input.rateBelow)).plus(above.mul(dec(input.rateAbove)));
  const employee = contribution.mul(dec(input.employeeShare));
  const employer = contribution.minus(employee);
  if (input.box52Rule === null) fail("INPUT_REQUIRED", "box52");
  let box = ZERO;
  if (input.box52Rule.kind === "percent_of_employer") {
    if (!present(input.box52Rule.percent)) fail("INPUT_REQUIRED", "box52");
    box = employer.mul(dec(input.box52Rule.percent)).div(HUNDRED);
  } else if (input.box52Rule.kind === "amount") {
    if (!present(input.box52Rule.amount)) fail("INPUT_REQUIRED", "box52");
    box = dec(input.box52Rule.amount);
  } else fail("INPUT_REQUIRED", "box52");
  return {
    below: moneyStr(below),
    above: moneyStr(above),
    employee: moneyStr(employee),
    employer: moneyStr(employer),
    box52: moneyStr(box),
  };
}

export function mandatoryPension(input: { mandatory: boolean; eligibilityDate: string }): {
  enrolled: boolean;
  effective: string;
  employeeTold: boolean;
  hrConfirmTask: boolean;
  contributions: "next_pay";
} {
  if (!input.mandatory) fail("INPUT_REQUIRED", "membership");
  return {
    enrolled: true,
    effective: input.eligibilityDate,
    employeeTold: true,
    hrConfirmTask: true,
    contributions: "next_pay",
  };
}

export function spendingImport(input: {
  balance: string;
  carryForward: string;
  runOut: string;
  claims?: unknown;
  wellnessAmount?: string;
}): { balance: string; carryForward: string; runOut: string; payrollAmount: string | null } {
  if (input.claims !== undefined) fail("NO_CLAIM_DETAILS");
  return {
    balance: input.balance,
    carryForward: input.carryForward,
    runOut: input.runOut,
    payrollAmount: present(input.wellnessAmount) ? String(input.wellnessAmount) : null,
  };
}

export function enrolmentComparison(input: { lang: ScreenLang; options: { code: string; perPay: string }[] }): { comparison: string; options: string[] } {
  const copy = screen[input.lang];
  if (copy === undefined) fail("INTERFACE_LANGUAGE_NOT_AVAILABLE");
  return {
    comparison: copy.comparison,
    options: input.options.map((option) => fill(copy.option, { code: option.code, amount: option.perPay })),
  };
}

export function enrolmentAssistant(): never {
  fail("FEATURE_OFF");
}

export function advisorView(input: {
  capability: string;
  people: { personId: string; cost: string }[];
  askPerson: boolean;
}): { count: number; cost: string; people: { personId: string }[] | null; refusedIndividual: boolean } {
  let cost = ZERO;
  for (const person of input.people) cost = cost.plus(dec(person.cost));
  if (input.capability === "plan_costs") {
    return { count: input.people.length, cost: moneyStr(cost), people: null, refusedIndividual: input.askPerson };
  }
  return {
    count: input.people.length,
    cost: moneyStr(cost),
    people: input.people.map((person) => ({ personId: person.personId })),
    refusedIndividual: false,
  };
}

export function trustOrder(contractOrder: string[]): { order: string[]; chosenByCanDo: false } {
  if (contractOrder.length === 0) fail("INPUT_REQUIRED", "trustOrder");
  return { order: contractOrder, chosenByCanDo: false };
}

export function changesSince(previous: { personId: string; action: string }[], current: { personId: string; action: string }[]): { personId: string; action: string }[] {
  const prior = new Map<string, string>();
  for (const row of previous) prior.set(row.personId, row.action);
  const changed: { personId: string; action: string }[] = [];
  for (const row of current) {
    if (prior.get(row.personId) !== row.action) changed.push(row);
  }
  return changed;
}
