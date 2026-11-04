import { addDays, addMonths, daysBetween } from "./dates.ts";
import { D, fixed } from "./decimal.ts";
import { fail } from "./errors.ts";
import { completeRoute, sameTenant, type Approval } from "./routes.ts";

export type CriticalWeights = Record<string, number>;

export function criticalWeightsValid(weights: CriticalWeights): void {
  let total = 0;
  for (const value of Object.values(weights)) total += value;
  if (total !== 100) fail("CRITICAL_WEIGHTS_INVALID");
}

export function scoreCriticalRole(input: {
  weights: CriticalWeights;
  scores: Record<string, number>;
  requiredByLaw: boolean;
  legalBasis: string;
}): { score: string } {
  criticalWeightsValid(input.weights);
  if (input.requiredByLaw && input.legalBasis.trim() === "") fail("INPUT_REQUIRED");
  const keys = Object.keys(input.weights);
  let weighted = new D(0);
  for (const key of keys) {
    if (!(key in input.scores)) fail("CRITICAL_SCORE_INVALID");
    const score = input.scores[key];
    if (score < 1 || score > 5) fail("CRITICAL_SCORE_INVALID");
    weighted = weighted.plus(new D(score).mul(input.weights[key]));
  }
  for (const key of Object.keys(input.scores)) {
    if (!(key in input.weights)) fail("CRITICAL_SCORE_INVALID");
  }
  return { score: fixed(weighted.div(100), 2) };
}

export function confirmCritical(scorerId: string, confirmerId: string): { confirmed: true } {
  if (scorerId === confirmerId) fail("SELF_APPROVAL");
  return { confirmed: true };
}

export function missingPlanReminder(hasPlan: boolean): { remindHr: boolean } {
  return { remindHr: !hasPlan };
}

export function recordFlightRisk(input: { by: string; subjectId: string; level: "low" | "medium" | "high"; note: string }): { level: string; note: string; modelScore: null } {
  if (input.by === input.subjectId) fail("SELF_REVIEW");
  if (input.note.trim() === "") fail("INPUT_REQUIRED");
  return { level: input.level, note: input.note, modelScore: null };
}

export function recordRetirement(input: { sharedByEmployee: boolean; source: string }): { shared: true; source: string } {
  if (!input.sharedByEmployee) fail("INPUT_REQUIRED");
  if (input.source.trim() === "") fail("INPUT_REQUIRED");
  return { shared: true, source: input.source };
}

export function recordVacancyDate(input: { on: string; reason: string }): { on: string } {
  if (input.on.trim() === "") fail("INPUT_REQUIRED");
  return { on: input.on };
}

export function openTalentReview(enabled: boolean): void {
  if (!enabled) fail("FEATURE_OFF");
}

export function openNineBox(enabled: boolean): void {
  if (!enabled) fail("FEATURE_OFF");
}

export function assessPotential(input: {
  assessorId: string;
  subjectId: string;
  criteria: readonly string[];
  scores: Record<string, string>;
  openToSuccession: boolean;
  aspiration: string | null;
}): { aspirationShown: string } {
  if (input.assessorId === input.subjectId) fail("SELF_REVIEW");
  for (const key of Object.keys(input.scores)) {
    if (!input.criteria.includes(key)) fail("POTENTIAL_CRITERION_UNKNOWN");
  }
  for (const criterion of input.criteria) {
    if (!(criterion in input.scores) || input.scores[criterion].trim() === "") fail("INPUT_REQUIRED");
  }
  if (!input.openToSuccession) return { aspirationShown: input.aspiration === null ? "not stated" : input.aspiration };
  return { aspirationShown: input.aspiration === null || input.aspiration.trim() === "" ? "not stated" : input.aspiration };
}

export type Placement = { box: string; reason: string; by: string };

export function movePlacement(input: { from: string; to: string; reason: string; by: string; history: Placement[] }): Placement[] {
  if (input.from !== input.to && input.reason.trim() === "") fail("PLACEMENT_REASON_REQUIRED");
  const history = input.history.slice();
  history.push({ box: input.to, reason: input.reason, by: input.by });
  return history;
}

export function biasPrompt(input: {
  enabled: boolean;
  minimum: number;
  groups: readonly { name: string; people: number; lowPotential: number }[];
}): { shown: boolean; percents: { name: string; lowPotentialPercent: string }[] } {
  if (!input.enabled) return { shown: false, percents: [] };
  for (const group of input.groups) {
    if (group.people < input.minimum) return { shown: false, percents: [] };
  }
  return {
    shown: true,
    percents: input.groups.map((group) => ({
      name: group.name,
      lowPotentialPercent: fixed(new D(group.lowPotential).mul(100).div(group.people), 1),
    })),
  };
}

export type ViewLog = { subject: string; viewerId: string; at: string };

export function viewSuccession(input: {
  namedIds: readonly string[];
  hr: boolean;
  viewerId: string;
  subject: string;
  at: string;
  log: ViewLog[];
}): { allowed: boolean; log: ViewLog[] } {
  const allowed = input.hr || input.namedIds.includes(input.viewerId);
  const log = input.log.slice();
  if (allowed) log.push({ subject: input.subject, viewerId: input.viewerId, at: input.at });
  return { allowed, log };
}

export function successionReadiness(value: string, list: readonly string[]): string {
  if (!list.includes(value)) fail("LIST_VALUE_UNKNOWN");
  return value;
}

export function languageGap(input: { required: string; held: string }): { gap: boolean } {
  return { gap: input.held !== input.required };
}

export function approveSuccessionPlan(input: {
  steps: readonly { role: string }[];
  approvals: readonly Approval[];
  ownerId: string;
  requiredByLaw: boolean;
  emergencySuccessorId: string | null;
  reviewMonths: number;
  approvedOn: string;
}): { approved: true; reviewOn: string } {
  completeRoute({ steps: input.steps, approvals: input.approvals, blockedApproverIds: [input.ownerId] });
  if (input.requiredByLaw && (input.emergencySuccessorId === null || input.emergencySuccessorId.trim() === "")) {
    fail("EMERGENCY_SUCCESSOR_REQUIRED");
  }
  return { approved: true, reviewOn: addMonths(input.approvedOn, input.reviewMonths) };
}

export function planReviewNotice(input: { reviewOn: string; on: string; reminderDays: number }): "remind" | "quiet" | "overdue" {
  const days = daysBetween(input.on, input.reviewOn);
  if (days < 0) return "overdue";
  if (days === input.reminderDays) return "remind";
  return "quiet";
}

export function changeApprovedPlan(): { routeAgain: true; priorApprovalCounts: false } {
  return { routeAgain: true, priorApprovalCounts: false };
}

export function unionizedPlan(): { developmentOnly: true } {
  return { developmentOnly: true };
}

export function directHireUnionized(input: { acknowledged: boolean; reason: string }): { allowed: true } {
  if (!input.acknowledged || input.reason.trim() === "") fail("CAUTION_NOT_ACKNOWLEDGED");
  return { allowed: true };
}

const SECRET = /\b(password|pin|token|secret)\b/i;

export function continuitySheet(input: { contacts: string; access: string; notes: string; reviewMonths: number; writtenOn: string }): { updateDue: string } {
  if (SECRET.test(input.contacts) || SECRET.test(input.access) || SECRET.test(input.notes)) fail("SECRET_NOT_ALLOWED");
  return { updateDue: addMonths(input.writtenOn, input.reviewMonths) };
}

export function seeContinuity(input: { viewerId: string; incumbentId: string; successorId: string; managerId: string; hr: boolean }): boolean {
  if (input.hr) return true;
  return input.viewerId === input.incumbentId || input.viewerId === input.successorId || input.viewerId === input.managerId;
}

export function applyToPool(input: { nominationsOnly: boolean; applicantIsSubject: boolean }): void {
  if (input.nominationsOnly) fail("POOL_CLOSED_TO_APPLICATIONS");
  if (!input.applicantIsSubject) fail("INPUT_REQUIRED");
}

export function approvePoolMember(input: {
  steps: readonly { role: string }[];
  approvals: readonly Approval[];
  nominatorId: string;
  nomineeId: string;
}): { approved: true } {
  completeRoute({ steps: input.steps, approvals: input.approvals, blockedApproverIds: [input.nominatorId, input.nomineeId] });
  return { approved: true };
}

export function declineApplication(reason: string): { declined: true; reason: string } {
  if (reason.trim() === "") fail("INPUT_REQUIRED");
  return { declined: true, reason };
}

export function proposeCareerStep(input: { fromJob: string; toJob: string; observed: boolean }): { proposed: true; fromJob: string; toJob: string } {
  if (!input.observed) fail("INPUT_REQUIRED");
  return { proposed: true, fromJob: input.fromJob, toJob: input.toJob };
}

export function openWorkforce(enabled: boolean): void {
  if (!enabled) fail("FEATURE_OFF");
}

const SEGMENT_SCOPES = ["org_unit", "job", "job_family", "career_level", "location", "agreement", "employment_type", "employer"];

export function defineSegment(scope: string): { scope: string } {
  if (!SEGMENT_SCOPES.includes(scope)) fail("SEGMENT_SCOPE_UNKNOWN");
  return { scope };
}

export function uploadHistory(input: { fileName: string; year: string; loadedYears: readonly string[] }): { year: string } {
  if (input.fileName.trim() === "") fail("INPUT_REQUIRED");
  if (input.loadedYears.includes(input.year)) fail("INPUT_REQUIRED");
  return { year: input.year };
}

export function historySummary(input: { people: number; years: number; separations: number; thinPeople: number; thinYears: number }): {
  thin: boolean;
  rate: string | null;
} {
  const thin = input.people < input.thinPeople || input.years < input.thinYears;
  if (thin || input.years === 0) return { thin, rate: null };
  return { thin: false, rate: fixed(new D(input.separations).mul(100).div(input.people).div(input.years), 2) };
}

export function supplyRate(input: {
  thin: boolean;
  source: "own" | "next_level" | "planner";
  parentRate: string | null;
  plannerRate: string | null;
  reason: string;
}): { rate: string; source: string } {
  if (input.source === "own" && input.thin) fail("HISTORY_TOO_THIN");
  if (input.source === "planner") {
    if (input.reason.trim() === "") fail("SUPPLY_RATE_REASON_REQUIRED");
    if (input.plannerRate === null) fail("INPUT_REQUIRED");
    return { rate: input.plannerRate, source: "planner" };
  }
  if (input.parentRate === null || input.parentRate.trim() === "") fail("INPUT_REQUIRED");
  return { rate: input.parentRate, source: "next_level" };
}

export function demandFte(input: { volume: string; perFte: string }): { fte: string } {
  return { fte: fixed(new D(input.volume).div(input.perFte), 2) };
}

export function saveScenario(input: { locked: boolean; copy: boolean }): { version: number } {
  if (input.locked && !input.copy) fail("SCENARIO_VERSION_LOCKED");
  return { version: input.copy ? 2 : 1 };
}

export function draftGapStrategy(kind: string): { kind: string; draft: true; applied: false } {
  return { kind, draft: true, applied: false };
}

export function releaseReduction(input: {
  unionized: boolean;
  drafted: boolean;
  labourReviewerId: string | null;
  releaserId: string;
  cautionAcknowledged: boolean;
  cautionReason: string;
}): { released: true } {
  if (!input.drafted) fail("INPUT_REQUIRED");
  if (input.unionized) {
    if (input.labourReviewerId === null || input.labourReviewerId.trim() === "" || input.labourReviewerId === input.releaserId) {
      fail("LABOUR_RELATIONS_REVIEW_REQUIRED");
    }
    if (!input.cautionAcknowledged || input.cautionReason.trim() === "") fail("CAUTION_NOT_ACKNOWLEDGED");
  }
  return { released: true };
}

export function positionPlan(input: {
  kind: string | null;
  fiscalYear: string | null;
  steps: readonly { role: string }[];
  approvals: readonly Approval[];
  ownerId: string;
}): { approved: true } {
  if (input.kind === null || input.kind.trim() === "" || input.fiscalYear === null || input.fiscalYear.trim() === "") fail("INPUT_REQUIRED");
  completeRoute({ steps: input.steps, approvals: input.approvals, blockedApproverIds: [input.ownerId] });
  return { approved: true };
}

export function costAssumption(input: { kind: string; reason: string; agreementId: string | null }): { kept: true } {
  if (input.reason.trim() === "") fail("INPUT_REQUIRED");
  if (input.kind === "agreement_increase" && (input.agreementId === null || input.agreementId.trim() === "")) fail("INPUT_REQUIRED");
  return { kept: true };
}

export function readSuccession<T>(recordTenant: string, readerTenant: string, rows: readonly T[]): T[] {
  return sameTenant(recordTenant, readerTenant, rows);
}

export function remindOn(on: string, days: number): string {
  return addDays(on, -days);
}
