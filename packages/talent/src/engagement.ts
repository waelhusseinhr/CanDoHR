import { addDays, daysBetween } from "./dates.ts";
import { D, fixed, money } from "./decimal.ts";
import { fail } from "./errors.ts";
import { completeRoute, sameTenant, type Approval } from "./routes.ts";
import { screen, type ScreenLang } from "./text.ts";

const AUDIENCES = ["organization", "employer", "org_unit", "person_type"];

export type EmployerCoverage = { id: string; covered: boolean | null; law: string | null };

export function surveyMode(input: { employers: readonly EmployerCoverage[]; requested: "confidential" | "anonymous" }): "confidential" | "anonymous" {
  for (const employer of input.employers) {
    if (employer.covered === null) fail("INPUT_REQUIRED");
    if (employer.covered && (employer.law === null || employer.law.trim() === "")) fail("INPUT_REQUIRED");
  }
  const covered = input.employers.some((employer) => employer.covered === true);
  if (covered && input.requested !== "anonymous") fail("SURVEY_MODE_NOT_ALLOWED");
  return input.requested;
}

export function surveyAudience(scope: string): string {
  if (!AUDIENCES.includes(scope)) fail("AUDIENCE_SCOPE_UNKNOWN");
  return scope;
}

export function surveyMinimum(surveyMin: number, organizationMin: number): number {
  if (surveyMin < organizationMin) fail("SURVEY_MIN_GROUP_BELOW_ORGANIZATION");
  return surveyMin;
}

export function setGroupMinimum(value: number, floor: number): void {
  if (value < floor) fail("SETTING_BELOW_MINIMUM");
}

export function lifecycleSurvey(input: { event: string | null; leaveName: string | null }): { event: string; namesLeave: false } {
  if (input.event === null || input.event.trim() === "") fail("INPUT_REQUIRED");
  if (input.event === "return_from_leave" && input.leaveName !== null) fail("INPUT_REQUIRED");
  return { event: input.event, namesLeave: false };
}

export function openSurvey(input: {
  opensOn: string | null;
  closesOn: string | null;
  openComments: boolean;
  contactId: string | null;
  unionConsultation: boolean;
  cautionAcknowledged: boolean;
}): { open: true } {
  if (input.opensOn === null || input.closesOn === null) fail("INPUT_REQUIRED");
  if (input.openComments && (input.contactId === null || input.contactId.trim() === "")) fail("ESCALATION_CONTACT_REQUIRED");
  if (input.unionConsultation && !input.cautionAcknowledged) fail("CAUTION_NOT_ACKNOWLEDGED");
  return { open: true };
}

export function changeOpenSurvey(): never {
  fail("SURVEY_LOCKED");
}

export function submitAnswer(input: {
  open: boolean;
  personId: string | null;
  itemKnown: boolean;
  mode: "confidential" | "anonymous";
  tenure: string | null;
  answeredOn: string;
  timeOfDay: string | null;
}): { answeredOn: string; personId: null } {
  if (!input.open) fail("SURVEY_NOT_OPEN");
  if (input.personId !== null) fail("SUBMISSION_ATTRIBUTE_NOT_ALLOWED");
  if (!input.itemKnown) fail("ANSWER_UNKNOWN_ITEM");
  if (input.mode === "anonymous" && input.tenure !== null) fail("SUBMISSION_ATTRIBUTE_NOT_ALLOWED");
  if (input.timeOfDay !== null) fail("SUBMISSION_ATTRIBUTE_NOT_ALLOWED");
  return { answeredOn: input.answeredOn, personId: null };
}

export type FlagRules = { categories: Record<string, { en: readonly string[]; fr: readonly string[] }> };

function matchesTerm(text: string, term: string): boolean {
  const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^\\p{L}\\p{N}])${escaped}([^\\p{L}\\p{N}]|$)`, "iu").test(text);
}

export function flagComment(input: { text: string; rules: FlagRules; contactId: string }): { flagged: boolean; category: string | null; contactId: string; personId: null } {
  for (const [category, words] of Object.entries(input.rules.categories)) {
    const terms = words.en.concat(words.fr);
    for (const term of terms) {
      if (matchesTerm(input.text, term)) return { flagged: true, category, contactId: input.contactId, personId: null };
    }
  }
  return { flagged: false, category: null, contactId: input.contactId, personId: null };
}

export function handleFlag(note: string): { note: string } {
  if (note.trim() === "") fail("INPUT_REQUIRED");
  return { note };
}

export function importResults(input: {
  intoCanDoSurvey: boolean;
  groups: readonly { selfIdentified: boolean; size: number }[];
  namesAPerson: boolean;
  unitMinimum: number;
  selfMinimum: number;
}): void {
  if (input.intoCanDoSurvey || input.namesAPerson) fail("INPUT_REQUIRED");
  for (const group of input.groups) {
    const minimum = group.selfIdentified ? input.selfMinimum : input.unitMinimum;
    if (group.size < minimum) fail("INPUT_REQUIRED");
  }
}

export function surveyScores(input: {
  items: readonly { id: string; scores: readonly string[] }[];
  minimum: number;
}): { id: string; shown: boolean; average: string | null }[] {
  return input.items.map((item) => {
    if (item.scores.length < input.minimum) return { id: item.id, shown: false, average: null };
    let total = new D(0);
    for (const score of item.scores) total = total.plus(score);
    return { id: item.id, shown: true, average: fixed(total.div(item.scores.length), 2) };
  });
}

export function surveyBreakdown(input: { groups: readonly { name: string; size: number; selfIdentified: boolean }[]; unitMinimum: number; selfMinimum: number }): { name: string; shown: boolean }[] {
  return input.groups.map((group) => ({
    name: group.name,
    shown: group.size >= (group.selfIdentified ? input.selfMinimum : input.unitMinimum),
  }));
}

export function participation(input: { invited: number; minimum: number }): { shown: boolean } {
  return { shown: input.invited >= input.minimum };
}

export function actionPlan(input: { closesOn: string; days: number; actions: readonly string[]; on: string; language: ScreenLang }): { dueOn: string; agreed: boolean; late: boolean; teamText: string } {
  const dueOn = addDays(input.closesOn, input.days);
  if (input.actions.length < 2) fail("INPUT_REQUIRED");
  return { dueOn, agreed: true, late: input.on > dueOn, teamText: screen[input.language].youSaid };
}

export function giveRecognition(input: {
  giverId: string;
  recipientId: string;
  value: string;
  values: readonly string[];
}): { visibility: "private"; value: string } {
  if (input.giverId === input.recipientId) fail("SELF_RECOGNITION");
  if (!input.values.includes(input.value)) fail("LIST_VALUE_UNKNOWN");
  return { visibility: "private", value: input.value };
}

export function requestPublic(input: { byId: string; recipientId: string; hasRoute: boolean }): void {
  if (input.byId !== input.recipientId) fail("RECIPIENT_CONSENT_REQUIRED");
  if (!input.hasRoute) fail("INPUT_REQUIRED");
}

export function approvePublic(input: {
  steps: readonly { role: string }[];
  approvals: readonly Approval[];
  recipientId: string;
  giverId: string;
}): { public: true } {
  completeRoute({ steps: input.steps, approvals: input.approvals, blockedApproverIds: [input.recipientId, input.giverId] });
  return { public: true };
}

export function attachToReview(input: { byId: string; recipientId: string; reviewSubjectId: string }): { attached: true } {
  if (input.byId !== input.recipientId) fail("RECIPIENT_CONSENT_REQUIRED");
  if (input.reviewSubjectId !== input.recipientId) fail("INPUT_REQUIRED");
  return { attached: true };
}

export function removeRecognition(reason: string): { removed: true } {
  if (reason.trim() === "") fail("INPUT_REQUIRED");
  return { removed: true };
}

export function givePoints(input: { amount: number; budget: number | null; spent: number }): { spent: number; left: number } {
  if (input.budget === null) fail("POINTS_BUDGET_EXCEEDED");
  if (input.spent + input.amount > input.budget) fail("POINTS_BUDGET_EXCEEDED");
  const spent = input.spent + input.amount;
  return { spent, left: input.budget - spent };
}

export type GiftYear = {
  tax_year: number;
  non_cash_annual_limit: number;
  long_service_limit: number;
  long_service_min_years: number;
  long_service_interval_years: number;
  status: string;
};

export function giveReward(input: {
  year: GiftYear | null;
  kind: "cash" | "near_cash" | "gift_card" | "non_cash";
  occasion: "special" | "recognition" | "long_service" | "performance";
  amount: string;
  serviceYears: number;
  yearsSinceLongService: number | null;
  priorNonCash: string;
  priorLongService: string;
  card: { prepaid: boolean; cannotConvertToCash: boolean; singleRetailer: boolean } | null;
}): { taxable: string; payCode: string | null; confirm: "to_confirm" | null; bucket: string } {
  if (input.year === null) fail("GIFT_RULE_MISSING");
  if (input.year.status === "verify_at_load") fail("RULE_NOT_VERIFIED");
  const amount = new D(input.amount);
  const cash = input.kind === "cash";
  if (input.kind === "gift_card" && input.card === null) fail("INPUT_REQUIRED");
  const cardFails = input.kind === "gift_card" && input.card !== null && (!input.card.prepaid || !input.card.cannotConvertToCash || !input.card.singleRetailer);
  const full = cash || input.kind === "near_cash" || cardFails || input.occasion === "performance";
  if (full) {
    return { taxable: money(input.amount), payCode: cash ? "AWARD-CASH" : "AWARD-BENEFIT", confirm: "to_confirm", bucket: cash ? "cash" : "taxable" };
  }
  const longService = input.occasion === "long_service" && input.serviceYears >= input.year.long_service_min_years && (input.yearsSinceLongService === null || input.yearsSinceLongService >= input.year.long_service_interval_years);
  const limit = new D(String(longService ? input.year.long_service_limit : input.year.non_cash_annual_limit));
  const prior = new D(longService ? input.priorLongService : input.priorNonCash);
  const before = prior.gt(limit) ? prior.minus(limit) : new D(0);
  const afterBase = prior.plus(amount);
  const after = afterBase.gt(limit) ? afterBase.minus(limit) : new D(0);
  const taxable = after.minus(before);
  return {
    taxable: money(taxable.toFixed()),
    payCode: taxable.gt(0) ? "AWARD-BENEFIT" : null,
    confirm: taxable.gt(0) ? "to_confirm" : null,
    bucket: longService ? "long_service" : "non_cash",
  };
}

export function approveCashAward(input: {
  steps: readonly { role: string }[];
  approvals: readonly Approval[];
  proposerId: string;
  recipientId: string;
}): { approved: true } {
  completeRoute({ steps: input.steps, approvals: input.approvals, blockedApproverIds: [input.proposerId, input.recipientId] });
  return { approved: true };
}

export function confirmPayroll(input: { proposerId: string; confirmerId: string; taxable: string }): { confirmed: true; taxable: string } {
  if (input.proposerId === input.confirmerId) fail("SELF_APPROVAL");
  return { confirmed: true, taxable: money(input.taxable) };
}

export function milestonesDue(input: { serviceOn: string; years: readonly number[]; from: string; to: string }): { on: string; years: number }[] {
  const found: { on: string; years: number }[] = [];
  for (const year of input.years) {
    const on = addYears(input.serviceOn, year);
    if (on >= input.from && on <= input.to) found.push({ on, years: year });
  }
  return found;
}

function addYears(iso: string, years: number): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!match) fail("DATE");
  return `${String(Number(match[1]) + years).padStart(4, "0")}-${match[2]}-${match[3]}`;
}

export function milestoneReminder(input: { on: string; reminderDays: number }): string {
  return addDays(input.on, -input.reminderDays);
}

export function celebrationOptIn(input: { day: number | null; month: number | null }): { day: number; month: number } {
  if (input.day === null || input.month === null) fail("INPUT_REQUIRED");
  if (input.month < 1 || input.month > 12 || input.day < 1 || input.day > 31) fail("INPUT_REQUIRED");
  return { day: input.day, month: input.month };
}

export function announcement(input: { audience: string; channel: "app" | "email" | "sms"; urgent: boolean; smsEnabled: boolean }): { channel: string } {
  surveyAudience(input.audience);
  if (input.channel === "sms" && !input.smsEnabled) fail("FEATURE_OFF");
  if (input.channel === "sms" && !input.urgent) fail("SMS_URGENT_ONLY");
  return { channel: input.channel };
}

export function readReminders(input: { publishedOn: string; on: string; days: readonly number[]; read: boolean }): boolean {
  if (input.read) return false;
  return input.days.includes(daysBetween(input.publishedOn, input.on));
}

export function voteIdea(input: { alreadyVoted: boolean }): { voted: true } {
  if (input.alreadyVoted) fail("INPUT_REQUIRED");
  return { voted: true };
}

export function decideIdea(input: { decision: string; reason: string; hr: boolean }): { decision: string } {
  if (input.decision === "declined" && input.reason.trim() === "") fail("INPUT_REQUIRED");
  if (!input.hr) fail("INPUT_REQUIRED");
  return { decision: input.decision };
}

export function anonymousMessage(input: { text: string; secretHash: string }): { personId: null; timeOfDay: null; secretHash: string; text: string } {
  if (input.secretHash.trim() === "") fail("INPUT_REQUIRED");
  return { personId: null, timeOfDay: null, secretHash: input.secretHash, text: input.text };
}

export function observance(input: { name: string }): { name: string; paidHoliday: false } {
  return { name: input.name, paidHoliday: false };
}

export function wellbeingLink(input: { name: string }): { name: string; healthData: null } {
  return { name: input.name, healthData: null };
}

export function directoryExtra(input: { addedByEmployee: boolean; text: string }): { shown: boolean; text: string } {
  return { shown: input.addedByEmployee, text: input.addedByEmployee ? input.text : "" };
}

export function readEngagement<T>(recordTenant: string, readerTenant: string, rows: readonly T[]): T[] {
  return sameTenant(recordTenant, readerTenant, rows);
}

export function surveyNotice(language: ScreenLang): string {
  return screen[language].speakUp;
}

export function recognitionNotice(language: ScreenLang): string {
  return screen[language].recognitionPrivate;
}
