import { addDays, addMonths, daysBetween } from "./dates.ts";
import { D } from "./decimal.ts";
import { fail } from "./errors.ts";
import { completeRoute, sameTenant, type Approval } from "./routes.ts";
import { screen, type ScreenLang } from "./text.ts";

export type Weights = { goals: number; competencies: number };

export type PerformanceSettings = {
  scalePoints: number;
  weights: Weights;
  calibration: boolean;
  feedback360: string;
  newHireMonths: number;
  minSectionDays: number;
  overallMethod: string;
  raterGroupMin: number;
  raterGroupMax: number;
  raterGroupFloor: number;
  checkinNudgeDays: number;
  pipDefaultDays: number;
  hrConcerns: readonly string[];
  nonUnionSunsetMonths: number | null;
};

export function openPerformanceSetup(settings: PerformanceSettings): PerformanceSettings {
  if (settings.raterGroupMin < settings.raterGroupFloor) fail("SETTING_BELOW_MINIMUM");
  return settings;
}

export function setRaterGroupMin(value: number, floor: number): void {
  if (value < floor) fail("SETTING_BELOW_MINIMUM");
}

export function openCycle(settings: PerformanceSettings, weights?: Weights): {
  weights: Weights;
  calibration: boolean;
  feedback360: string;
  newHireMonths: number;
  copiedFromSettings: boolean;
} {
  const chosen = weights === undefined ? settings.weights : weights;
  if (chosen.goals + chosen.competencies !== 100) fail("PERFORMANCE_WEIGHTS_INVALID");
  return {
    weights: chosen,
    calibration: settings.calibration,
    feedback360: settings.feedback360,
    newHireMonths: settings.newHireMonths,
    copiedFromSettings: weights === undefined,
  };
}

export function suggestRating(goalScore: string, competencyScore: string, weights: Weights, scalePoints: number): number {
  if (weights.goals + weights.competencies !== 100) fail("PERFORMANCE_WEIGHTS_INVALID");
  const score = new D(goalScore).mul(weights.goals).plus(new D(competencyScore).mul(weights.competencies)).div(100);
  const rounded = score.toDecimalPlaces(0, D.ROUND_HALF_UP).toNumber();
  if (rounded < 1) return 1;
  if (rounded > scalePoints) return scalePoints;
  return rounded;
}

export function chooseRating(suggested: number, chosen: number, reason: string): { rating: number; reason: string } {
  if (chosen !== suggested && reason.trim() === "") fail("RATING_REASON_REQUIRED");
  return { rating: chosen, reason };
}

export function agreeGoal(input: {
  level: string;
  departmentId: string | null;
  employeeAgreed: boolean;
  managerAgreed: boolean;
  parentGoalId: string | null;
}): { agreed: true; parentGoalId: string | null } {
  if (input.level === "department" && (input.departmentId === null || input.departmentId.trim() === "")) fail("INPUT_REQUIRED");
  if (input.level === "individual" && (!input.employeeAgreed || !input.managerAgreed)) fail("GOAL_NOT_AGREED");
  return { agreed: true, parentGoalId: input.parentGoalId };
}

export function amendGoal(input: {
  before: string;
  after: string;
  authorId: string;
  reason: string;
  at: string;
}): { before: string; after: string; authorId: string; reason: string; at: string } {
  if (input.authorId.trim() === "" || input.reason.trim() === "") fail("INPUT_REQUIRED");
  return input;
}

export function recordStrengths(input: {
  employee: { strengths: string; develop: string };
  manager: { strengths: string; develop: string };
}): typeof input {
  return { employee: input.employee, manager: input.manager };
}

export function createReview(input: { ratingMode: string | null; ratingModeSource: string }): { ratingMode: string; ratingModeSource: string } {
  if (input.ratingMode === null || input.ratingMode.trim() === "") fail("INPUT_REQUIRED");
  return { ratingMode: input.ratingMode, ratingModeSource: input.ratingModeSource };
}

export function ratingAllowed(input: {
  ratingMode: string;
  reviewType: string;
  hiredOn: string;
  cycleEnd: string;
  newHireMonths: number;
}): void {
  if (input.ratingMode === "development_only" || input.ratingMode === "agreement_form" || input.ratingMode === "not_rated") {
    fail("RATING_NOT_ALLOWED");
  }
  if (input.reviewType === "mid_year") fail("RATING_NOT_ALLOWED");
  const cutoff = addMonths(input.cycleEnd, -input.newHireMonths);
  if (input.hiredOn > cutoff) fail("RATING_NOT_ALLOWED");
}

export type SectionDraft = {
  assignmentId: string;
  managerId: string;
  start: string;
  end: string;
  daysWorked: number;
  comments: string;
  rating: number | null;
};

export function rateSections(input: {
  minDays: number;
  sections: readonly { assignmentId: string; managerId: string; start: string; end: string; daysWorked: number; comments: string; rating: number | null }[];
  language: ScreenLang;
}): { rated: SectionDraft[]; commentsOnly: { assignmentId: string; text: string }[] } {
  const rated: SectionDraft[] = [];
  const commentsOnly: { assignmentId: string; text: string }[] = [];
  for (const section of input.sections) {
    for (const other of rated) {
      if (other.assignmentId === section.assignmentId && section.start <= other.end && other.start <= section.end) {
        fail("INPUT_REQUIRED", "sections for the same position overlap");
      }
    }
    if (section.daysWorked < input.minDays) {
      if (section.rating !== null) fail("SECTION_TOO_SHORT_TO_RATE");
      commentsOnly.push({ assignmentId: section.assignmentId, text: screen[input.language].commentsOnly });
      continue;
    }
    rated.push(section);
  }
  return { rated, commentsOnly };
}

export function combinedRating(method: string, ratings: readonly number[]): number | null {
  if (method === "none") return null;
  if (ratings.length === 0) return null;
  let total = new D(0);
  for (const rating of ratings) total = total.plus(rating);
  return total.div(ratings.length).toDecimalPlaces(0, D.ROUND_HALF_UP).toNumber();
}

export function reviewerFor(line: { managerId: string }, dueDate: string): { managerId: string; asOf: string } {
  if (line.managerId.trim() === "") fail("INPUT_REQUIRED");
  return { managerId: line.managerId, asOf: dueDate };
}

export type RatingChange = { stage: string; from: number; to: number; by: string; reason: string };

export function calibrate(input: { from: number; to: number; by: string; reason: string; history: RatingChange[] }): RatingChange[] {
  if (input.from !== input.to && input.reason.trim() === "") fail("RATING_CHANGE_REASON_REQUIRED");
  const next = input.history.slice();
  if (input.from !== input.to) next.push({ stage: "calibration", from: input.from, to: input.to, by: input.by, reason: input.reason });
  return next;
}

export function releaseReview(input: {
  calibrationRequired: boolean;
  calibrated: boolean;
  steps: readonly { role: string }[];
  approvals: readonly Approval[];
  reviewingManagerId: string;
  employeeId: string;
  concerns: readonly string[];
  hrConcerns: readonly string[];
  hrReviewedBy: string | null;
}): { released: true } {
  if (input.calibrationRequired && !input.calibrated) fail("CALIBRATION_REQUIRED");
  completeRoute({
    steps: input.steps,
    approvals: input.approvals,
    blockedApproverIds: [input.reviewingManagerId, input.employeeId],
  });
  const needsHr = input.concerns.some((concern) => input.hrConcerns.includes(concern));
  if (needsHr && (input.hrReviewedBy === null || input.hrReviewedBy.trim() === "" || input.hrReviewedBy === input.reviewingManagerId)) {
    fail("HR_REVIEW_REQUIRED");
  }
  return { released: true };
}

export function signReview(input: { seen: boolean; comment: string }): { seen: true; comment: string } {
  if (!input.seen) fail("INPUT_REQUIRED");
  return { seen: true, comment: input.comment };
}

export function decideHrReview(input: { outcome: string; reason: string; by: string }): { outcome: string; reason: string; by: string } {
  if (input.reason.trim() === "" || input.by.trim() === "") fail("INPUT_REQUIRED");
  return input;
}

export function changeAfterRelease(input: {
  actorIsHr: boolean;
  from: number;
  to: number;
  by: string;
  reason: string;
  history: RatingChange[];
}): { history: RatingChange[]; employeeTold: true } {
  if (!input.actorIsHr) fail("INPUT_REQUIRED");
  if (input.reason.trim() === "" || input.by.trim() === "") fail("RATING_CHANGE_REASON_REQUIRED");
  const history = input.history.slice();
  history.push({ stage: "after_final", from: input.from, to: input.to, by: input.by, reason: input.reason });
  return { history, employeeTold: true };
}

export function requestFeedback(input: {
  cycleUse: string;
  purpose: string;
  nomineeId: string;
  subjectId: string;
  group: string;
  groupCount: number;
  groupMax: number;
}): { purpose: string } {
  if (input.purpose === "ratings" && input.cycleUse !== "informs_ratings") fail("FEEDBACK_DEVELOPMENT_ONLY");
  if (input.nomineeId === input.subjectId) fail("SELF_REVIEW");
  if (input.group !== "manager" && input.groupCount > input.groupMax) fail("FEEDBACK_RATERS_OVER_MAX");
  return { purpose: input.purpose };
}

export function feedbackVisible(input: { group: string; answered: number; minimum: number }): boolean {
  if (input.group === "manager") return true;
  return input.answered >= input.minimum;
}

export function checkinNudge(input: { lastCheckin: string | null; on: string; nudgeDays: number; language: ScreenLang }): { nudge: boolean; text: string } {
  if (input.lastCheckin === null) return { nudge: true, text: screen[input.language].nudge };
  const elapsed = daysBetween(input.lastCheckin, input.on);
  return { nudge: elapsed >= input.nudgeDays, text: screen[input.language].nudge };
}

const PIP_CAUSES = ["expectations", "training", "workload", "accommodation"] as const;

export function submitPip(input: { causesRuledOut: readonly string[] }): { causesRuledOut: string[] } {
  for (const cause of PIP_CAUSES) {
    if (!input.causesRuledOut.includes(cause)) fail("PIP_CAUSES_NOT_REVIEWED");
  }
  return { causesRuledOut: input.causesRuledOut.slice() };
}

export function pipEnd(start: string, end: string | null, defaultDays: number): string {
  if (end === null || end.trim() === "") return addDays(start, defaultDays);
  return end;
}

export function approvePip(input: {
  steps: readonly { role: string }[];
  approvals: readonly Approval[];
  managerId: string;
  employeeId: string;
  onProtectedLeave: boolean;
  protectedGround: boolean;
  cautionAcknowledged: boolean;
  cautionReason: string;
}): { approved: true } {
  if (input.onProtectedLeave) fail("PIP_DURING_PROTECTED_LEAVE");
  if (input.protectedGround && (!input.cautionAcknowledged || input.cautionReason.trim() === "")) fail("CAUTION_NOT_ACKNOWLEDGED");
  completeRoute({ steps: input.steps, approvals: input.approvals, blockedApproverIds: [input.managerId, input.employeeId] });
  return { approved: true };
}

export function startPip(acknowledged: boolean): { started: true } {
  if (!acknowledged) fail("INPUT_REQUIRED");
  return { started: true };
}

export function extendPip(input: { reason: string; end: string; previousEnd: string }): { end: string; reason: string } {
  if (input.reason.trim() === "" || input.end <= input.previousEnd) fail("INPUT_REQUIRED");
  return { end: input.end, reason: input.reason };
}

export function probationOutcome(outcome: "pass" | "extend" | "fail"): { changeSetKind: string } {
  if (outcome === "extend") return { changeSetKind: "employment.probation_extended" };
  return { changeSetKind: "employment.status_changed" };
}

export function adverseInForce(input: {
  basis: "agreement" | "non_union";
  agreementSunsetMonths: number | null;
  organizationMonths: number | null;
  recordedOn: string;
  asOf: string;
}): { inForce: boolean; hrKeeps: true } {
  if (input.basis === "agreement" && input.agreementSunsetMonths === null) fail("INPUT_REQUIRED");
  const months = input.basis === "agreement" ? input.agreementSunsetMonths : input.organizationMonths;
  if (months === null) return { inForce: true, hrKeeps: true };
  const sunset = addMonths(input.recordedOn, months);
  return { inForce: input.asOf < sunset, hrKeeps: true };
}

export function readPerformance<T>(recordTenant: string, readerTenant: string, rows: readonly T[]): T[] {
  return sameTenant(recordTenant, readerTenant, rows);
}
