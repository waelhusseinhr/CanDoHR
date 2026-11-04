import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  TalentError,
  adverseInForce,
  calibrate,
  changeAfterRelease,
  checkinNudge,
  chooseRating,
  combinedRating,
  createReview,
  decideHrReview,
  feedbackVisible,
  openCycle,
  openPerformanceSetup,
  probationOutcome,
  rateSections,
  ratingAllowed,
  readPerformance,
  releaseReview,
  requestFeedback,
  reviewerFor,
  screen,
  setRaterGroupMin,
  signReview,
  startPip,
  submitPip,
  suggestRating,
  agreeGoal,
  amendGoal,
  approvePip,
  extendPip,
  pipEnd,
  recordStrengths,
  type PerformanceSettings,
} from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const performanceSql = readFileSync(join(root, "schema/0014_performance_decisions.sql"), "utf8");

function insertDefault(sql: string, key: string): string {
  const re = new RegExp(
    `\\('${key}',\\s*'[^']+',\\s*'[^']+',\\s*(?:NULL|'(?:[^']|'')*'),\\s*(NULL|'(?:[^']|'')*')`,
  );
  const match = re.exec(sql);
  if (!match) throw new Error(`setting ${key} is not in the schema file`);
  if (match[1] === "NULL") return "";
  return match[1].slice(1, -1).replaceAll("''", "'");
}

function insertMin(sql: string, key: string): number {
  const re = new RegExp(`\\('${key}'[\\s\\S]{0,1200}?'decided',\\s*(\\d+),`);
  const match = re.exec(sql);
  if (!match) throw new Error(`minimum for ${key} is not in the schema file`);
  return Number(match[1]);
}

function updatedDefault(sql: string, key: string): string {
  const re = new RegExp(`SET default_value = ('(?:[^']|'')*')[\\s\\S]{0,600}?setting_key = '${key}'`);
  const match = re.exec(sql);
  if (!match) throw new Error(`updated default for ${key} is not in the schema file`);
  return match[1].slice(1, -1).replaceAll("''", "'");
}

function json<T>(value: string): T {
  return JSON.parse(value) as T;
}

function expectCode(code: string, fn: () => void): void {
  assert.throws(fn, (error: unknown) => {
    assert.ok(error instanceof TalentError);
    assert.equal(error.code, code);
    return true;
  });
}

const scale = json<{ levels: { value: number }[] }>(insertDefault(performanceSql, "performance.rating_scale_starter"));
const weights = json<{ goals: number; competencies: number }>(insertDefault(performanceSql, "performance.weights_starter"));
const hrConcerns = json<string[]>(insertDefault(performanceSql, "performance.hr_review_concerns"));
const sunset = json<{ months: number | null }>(insertDefault(performanceSql, "performance.non_union_sunset"));
const raterFloor = insertMin(performanceSql, "performance.rater_group_min");
const sectionDays = Number(updatedDefault(performanceSql, "reviews.min_section_days"));
const overallMethod = json<string>(updatedDefault(performanceSql, "reviews.overall_method"));
const settings: PerformanceSettings = {
  scalePoints: scale.levels.length,
  weights,
  calibration: insertDefault(performanceSql, "performance.calibration") === "true",
  feedback360: json<string>(insertDefault(performanceSql, "performance.feedback_360_use")),
  newHireMonths: Number(insertDefault(performanceSql, "performance.new_hire_no_rating_months")),
  minSectionDays: sectionDays,
  overallMethod,
  raterGroupMin: Number(insertDefault(performanceSql, "performance.rater_group_min")),
  raterGroupMax: Number(insertDefault(performanceSql, "performance.rater_group_max")),
  raterGroupFloor: raterFloor,
  checkinNudgeDays: Number(insertDefault(performanceSql, "performance.checkin_nudge_days")),
  pipDefaultDays: Number(insertDefault(performanceSql, "performance.pip_default_days")),
  hrConcerns,
  nonUnionSunsetMonths: sunset.months,
};

const oneUp = [{ role: "one_up" }];
const hrRoute = [{ role: "hr" }];

test("PERF-001 reviewer is the manager on the review due date", () => {
  assert.deepEqual(reviewerFor({ managerId: "cy" }, "2026-04-30"), { managerId: "cy", asOf: "2026-04-30" });
  assert.deepEqual(reviewerFor({ managerId: "ben" }, "2026-12-31"), { managerId: "ben", asOf: "2026-12-31" });
  expectCode("INPUT_REQUIRED", () => reviewerFor({ managerId: " " }, "2026-12-31"));
  const sections = rateSections({
    minDays: settings.minSectionDays,
    language: "en-CA",
    sections: [
      { assignmentId: "clerk", managerId: "cy", start: "2026-01-01", end: "2026-04-30", daysWorked: 120, comments: "winter", rating: 3 },
      { assignmentId: "clerk", managerId: "ben", start: "2026-05-01", end: "2026-12-31", daysWorked: 200, comments: "summer", rating: 4 },
    ],
  });
  assert.equal(sections.rated.length, 2);
  assert.equal(sections.rated[0].managerId, "cy");
  assert.equal(sections.rated[1].managerId, "ben");
});

test("PERF-002 goals cascade and both people agree", () => {
  const agreed = agreeGoal({
    level: "individual",
    departmentId: "roads",
    employeeAgreed: true,
    managerAgreed: true,
    parentGoalId: "team-goal",
  });
  assert.equal(agreed.agreed, true);
  assert.equal(agreed.parentGoalId, "team-goal");
  expectCode("GOAL_NOT_AGREED", () =>
    agreeGoal({ level: "individual", departmentId: "roads", employeeAgreed: true, managerAgreed: false, parentGoalId: "team-goal" }),
  );
  const amended = amendGoal({
    before: "close 40 files",
    after: "close 36 files",
    authorId: "ben",
    reason: "April vacancy",
    at: "2026-05-02",
  });
  assert.equal(amended.before, "close 40 files");
  assert.equal(amended.after, "close 36 files");
  assert.equal(amended.authorId, "ben");
});

test("PERF-003 calibration blocks release and keeps the reason", () => {
  expectCode("CALIBRATION_REQUIRED", () =>
    releaseReview({
      calibrationRequired: settings.calibration,
      calibrated: false,
      steps: oneUp,
      approvals: [{ role: "one_up", approverId: "director" }],
      reviewingManagerId: "ben",
      employeeId: "ana",
      concerns: [],
      hrConcerns: settings.hrConcerns,
      hrReviewedBy: null,
    }),
  );
  const history = calibrate({ from: 4, to: 3, by: "director", reason: "team distribution", history: [] });
  assert.equal(history[0].stage, "calibration");
  assert.equal(history[0].reason, "team distribution");
});

test("PERF-004 probation outcome drafts a change set", () => {
  assert.equal(probationOutcome("pass").changeSetKind, "employment.status_changed");
  assert.equal(probationOutcome("fail").changeSetKind, "employment.status_changed");
  assert.equal(probationOutcome("extend").changeSetKind, "employment.probation_extended");
});

test("PERF-005 agreement rating limits and sunset months", () => {
  expectCode("RATING_NOT_ALLOWED", () =>
    ratingAllowed({
      ratingMode: "agreement_form",
      reviewType: "year_end",
      hiredOn: "2020-01-01",
      cycleEnd: "2026-12-31",
      newHireMonths: settings.newHireMonths,
    }),
  );
  expectCode("RATING_NOT_ALLOWED", () =>
    ratingAllowed({
      ratingMode: "development_only",
      reviewType: "year_end",
      hiredOn: "2020-01-01",
      cycleEnd: "2026-12-31",
      newHireMonths: settings.newHireMonths,
    }),
  );
  expectCode("INPUT_REQUIRED", () =>
    adverseInForce({
      basis: "agreement",
      agreementSunsetMonths: null,
      organizationMonths: settings.nonUnionSunsetMonths,
      recordedOn: "2025-01-01",
      asOf: "2026-01-01",
    }),
  );
  const inForce = adverseInForce({
    basis: "agreement",
    agreementSunsetMonths: 12,
    organizationMonths: null,
    recordedOn: "2025-01-01",
    asOf: "2025-12-01",
  });
  assert.equal(inForce.inForce, true);
  assert.equal(inForce.hrKeeps, true);
});

test("PERF-006 a short period after protected leave is comments only", () => {
  expectCode("SECTION_TOO_SHORT_TO_RATE", () =>
    rateSections({
      minDays: settings.minSectionDays,
      language: "fr-CA",
      sections: [
        { assignmentId: "clerk", managerId: "ben", start: "2026-10-01", end: "2026-12-31", daysWorked: 60, comments: "retour", rating: 3 },
      ],
    }),
  );
  const comments = rateSections({
    minDays: settings.minSectionDays,
    language: "fr-CA",
    sections: [
      { assignmentId: "clerk", managerId: "ben", start: "2026-10-01", end: "2026-12-31", daysWorked: 60, comments: "retour", rating: null },
    ],
  });
  assert.equal(comments.rated.length, 0);
  assert.equal(comments.commentsOnly[0].text, screen["fr-CA"].commentsOnly);
});

test("PERF-007 improvement plan safeguards", () => {
  expectCode("PIP_CAUSES_NOT_REVIEWED", () => submitPip({ causesRuledOut: ["expectations", "training", "accommodation"] }));
  const causes = submitPip({ causesRuledOut: ["expectations", "training", "workload", "accommodation"] });
  assert.equal(causes.causesRuledOut.length, 4);
  expectCode("PIP_DURING_PROTECTED_LEAVE", () =>
    approvePip({
      steps: hrRoute,
      approvals: [{ role: "hr", approverId: "hr-1" }],
      managerId: "ben",
      employeeId: "ana",
      onProtectedLeave: true,
      protectedGround: false,
      cautionAcknowledged: false,
      cautionReason: "",
    }),
  );
  expectCode("SELF_APPROVAL", () =>
    approvePip({
      steps: hrRoute,
      approvals: [{ role: "hr", approverId: "ben" }],
      managerId: "ben",
      employeeId: "ana",
      onProtectedLeave: false,
      protectedGround: false,
      cautionAcknowledged: false,
      cautionReason: "",
    }),
  );
});

test("PERF-008 suggested rating and no combined rating", () => {
  const suggested = suggestRating("4", "2", settings.weights, settings.scalePoints);
  assert.equal(suggested, 3);
  expectCode("RATING_REASON_REQUIRED", () => chooseRating(suggested, 2, ""));
  assert.equal(chooseRating(suggested, 2, "April files were late").rating, 2);
  assert.equal(combinedRating(settings.overallMethod, [3, 4]), null);
});

test("PERF-009 one-up look and HR on a listed concern", () => {
  expectCode("HR_REVIEW_REQUIRED", () =>
    releaseReview({
      calibrationRequired: true,
      calibrated: true,
      steps: oneUp,
      approvals: [{ role: "one_up", approverId: "director" }],
      reviewingManagerId: "ben",
      employeeId: "ana",
      concerns: ["differs_from_suggestion"],
      hrConcerns: settings.hrConcerns,
      hrReviewedBy: null,
    }),
  );
  expectCode("SELF_APPROVAL", () =>
    releaseReview({
      calibrationRequired: true,
      calibrated: true,
      steps: oneUp,
      approvals: [{ role: "one_up", approverId: "ana" }],
      reviewingManagerId: "ben",
      employeeId: "ana",
      concerns: [],
      hrConcerns: settings.hrConcerns,
      hrReviewedBy: null,
    }),
  );
});

test("PERF-010 signing means seen, and only HR changes a released rating", () => {
  expectCode("INPUT_REQUIRED", () => signReview({ seen: false, comment: "I have a comment" }));
  assert.equal(signReview({ seen: true, comment: "Please ask HR" }).comment, "Please ask HR");
  expectCode("INPUT_REQUIRED", () => decideHrReview({ outcome: "uphold", reason: "", by: "hr-1" }));
  const decided = decideHrReview({ outcome: "uphold", reason: "the section matches the file", by: "hr-1" });
  assert.equal(decided.by, "hr-1");
  expectCode("INPUT_REQUIRED", () => changeAfterRelease({ actorIsHr: false, from: 3, to: 2, by: "ben", reason: "I disagree", history: [] }));
  const changed = changeAfterRelease({ actorIsHr: true, from: 3, to: 2, by: "hr-1", reason: "file review", history: [] });
  assert.equal(changed.employeeTold, true);
  assert.equal(changed.history[0].stage, "after_final");
});

test("PERF-011 360 groups stay hidden under the minimum and stay developmental", () => {
  assert.equal(settings.raterGroupMin, 3);
  assert.equal(settings.raterGroupMax, 5);
  expectCode("FEEDBACK_DEVELOPMENT_ONLY", () =>
    requestFeedback({
      cycleUse: settings.feedback360,
      purpose: "ratings",
      nomineeId: "peer",
      subjectId: "ana",
      group: "peer",
      groupCount: 3,
      groupMax: settings.raterGroupMax,
    }),
  );
  assert.equal(feedbackVisible({ group: "peer", answered: 2, minimum: settings.raterGroupMin }), false);
  assert.equal(feedbackVisible({ group: "manager", answered: 1, minimum: settings.raterGroupMin }), true);
  assert.equal(screen["en-CA"].nudge.length > 0, true);
  assert.notEqual(screen["en-CA"].commentsOnly, screen["fr-CA"].commentsOnly);
});

test("PERF-012 check-in nudges and sunset clauses", () => {
  assert.equal(settings.checkinNudgeDays, 30);
  assert.equal(checkinNudge({ lastCheckin: "2026-03-01", on: "2026-03-31", nudgeDays: settings.checkinNudgeDays, language: "en-CA" }).nudge, true);
  assert.equal(checkinNudge({ lastCheckin: "2026-03-01", on: "2026-03-20", nudgeDays: 7, language: "fr-CA" }).text, screen["fr-CA"].nudge);
  const kept = adverseInForce({
    basis: "non_union",
    agreementSunsetMonths: null,
    organizationMonths: settings.nonUnionSunsetMonths,
    recordedOn: "2024-01-01",
    asOf: "2026-06-01",
  });
  assert.equal(kept.inForce, true);
  assert.equal(kept.hrKeeps, true);
});

test("PERF-020 setup copies the schema defaults", () => {
  assert.equal(settings.scalePoints, 5);
  assert.deepEqual(settings.weights, { goals: 50, competencies: 50 });
  assert.equal(settings.calibration, true);
  assert.equal(settings.feedback360, "development_only");
  assert.equal(settings.minSectionDays, 90);
  assert.equal(settings.overallMethod, "none");
  assert.equal(settings.raterGroupMin, 3);
  assert.equal(settings.raterGroupFloor, 3);
  assert.equal(insertDefault(performanceSql, "performance.ai_writing_help"), "false");
  assert.deepEqual(openPerformanceSetup(settings).weights, settings.weights);
});

test("PERF-021 a 360 minimum under the floor is refused", () => {
  expectCode("SETTING_BELOW_MINIMUM", () => setRaterGroupMin(settings.raterGroupFloor - 1, settings.raterGroupFloor));
  expectCode("SETTING_BELOW_MINIMUM", () => openPerformanceSetup({ ...settings, raterGroupMin: 2 }));
});

test("PERF-022 a cycle copies weights and refuses a total other than 100", () => {
  const copied = openCycle(settings);
  assert.equal(copied.copiedFromSettings, true);
  assert.deepEqual(copied.weights, settings.weights);
  expectCode("PERFORMANCE_WEIGHTS_INVALID", () => openCycle(settings, { goals: 60, competencies: 50 }));
});

test("PERF-023 a department goal needs a department and an individual goal needs both agreements", () => {
  expectCode("INPUT_REQUIRED", () =>
    agreeGoal({ level: "department", departmentId: null, employeeAgreed: true, managerAgreed: true, parentGoalId: null }),
  );
  expectCode("GOAL_NOT_AGREED", () =>
    agreeGoal({ level: "individual", departmentId: "roads", employeeAgreed: true, managerAgreed: false, parentGoalId: "dept" }),
  );
});

test("PERF-024 an amendment names the author and the reason", () => {
  expectCode("INPUT_REQUIRED", () => amendGoal({ before: "40", after: "36", authorId: "", reason: "vacancy", at: "2026-05-02" }));
  const kept = amendGoal({ before: "40", after: "36", authorId: "ben", reason: "vacancy", at: "2026-05-02" });
  assert.equal(kept.before, "40");
  assert.equal(kept.after, "36");
});

test("PERF-025 strengths stay side by side", () => {
  const kept = recordStrengths({
    employee: { strengths: "files", develop: "french" },
    manager: { strengths: "judgment", develop: "pace" },
  });
  assert.equal(kept.employee.strengths, "files");
  assert.equal(kept.manager.develop, "pace");
});

test("PERF-026 a review states its rating mode", () => {
  expectCode("INPUT_REQUIRED", () => createReview({ ratingMode: null, ratingModeSource: "cycle" }));
  assert.equal(createReview({ ratingMode: "rated", ratingModeSource: "cycle" }).ratingMode, "rated");
});

test("PERF-027 two periods are rated and an overlap is refused", () => {
  const rated = rateSections({
    minDays: settings.minSectionDays,
    language: "en-CA",
    sections: [
      { assignmentId: "clerk", managerId: "cy", start: "2026-01-01", end: "2026-04-30", daysWorked: 120, comments: "q1", rating: 3 },
      { assignmentId: "clerk", managerId: "ben", start: "2026-05-01", end: "2026-12-31", daysWorked: 200, comments: "rest", rating: 3 },
    ],
  });
  assert.equal(rated.rated.length, 2);
  expectCode("INPUT_REQUIRED", () =>
    rateSections({
      minDays: settings.minSectionDays,
      language: "en-CA",
      sections: [
        { assignmentId: "clerk", managerId: "cy", start: "2026-01-01", end: "2026-04-30", daysWorked: 120, comments: "q1", rating: 3 },
        { assignmentId: "clerk", managerId: "cy", start: "2026-04-01", end: "2026-06-30", daysWorked: 91, comments: "overlap", rating: 3 },
      ],
    }),
  );
});

test("PERF-028 a different rating needs a reason", () => {
  assert.equal(suggestRating("4", "2", settings.weights, settings.scalePoints), 3);
  expectCode("RATING_REASON_REQUIRED", () => chooseRating(3, 2, " "));
});

test("PERF-029 sixty days is comments only", () => {
  expectCode("SECTION_TOO_SHORT_TO_RATE", () =>
    rateSections({
      minDays: settings.minSectionDays,
      language: "en-CA",
      sections: [{ assignmentId: "second", managerId: "ben", start: "2026-06-01", end: "2026-07-31", daysWorked: 60, comments: "short", rating: 3 }],
    }),
  );
  const comments = rateSections({
    minDays: settings.minSectionDays,
    language: "en-CA",
    sections: [{ assignmentId: "second", managerId: "ben", start: "2026-06-01", end: "2026-07-31", daysWorked: 60, comments: "short", rating: null }],
  });
  assert.equal(comments.commentsOnly[0].text, screen["en-CA"].commentsOnly);
});

test("PERF-030 the default method has no combined rating", () => {
  assert.equal(settings.overallMethod, "none");
  assert.equal(combinedRating("none", [3, 4]), null);
});

test("PERF-031 mid-year, development-only and a November hire are not rated", () => {
  expectCode("RATING_NOT_ALLOWED", () =>
    ratingAllowed({ ratingMode: "rated", reviewType: "mid_year", hiredOn: "2020-01-01", cycleEnd: "2026-12-31", newHireMonths: settings.newHireMonths }),
  );
  expectCode("RATING_NOT_ALLOWED", () =>
    ratingAllowed({ ratingMode: "development_only", reviewType: "year_end", hiredOn: "2020-01-01", cycleEnd: "2026-12-31", newHireMonths: settings.newHireMonths }),
  );
  expectCode("RATING_NOT_ALLOWED", () =>
    ratingAllowed({ ratingMode: "rated", reviewType: "year_end", hiredOn: "2026-11-02", cycleEnd: "2026-12-31", newHireMonths: settings.newHireMonths }),
  );
  ratingAllowed({ ratingMode: "rated", reviewType: "year_end", hiredOn: "2020-01-01", cycleEnd: "2026-12-31", newHireMonths: settings.newHireMonths });
});

test("PERF-032 calibration keeps a reason", () => {
  expectCode("RATING_CHANGE_REASON_REQUIRED", () => calibrate({ from: 4, to: 3, by: "director", reason: "", history: [] }));
  const history = calibrate({ from: 4, to: 3, by: "director", reason: "distribution", history: [] });
  assert.equal(history[0].stage, "calibration");
  assert.equal(history[0].from, 4);
  assert.equal(history[0].to, 3);
});

test("PERF-033 release waits for calibration and the one-up approval", () => {
  expectCode("CALIBRATION_REQUIRED", () =>
    releaseReview({
      calibrationRequired: true,
      calibrated: false,
      steps: oneUp,
      approvals: [{ role: "one_up", approverId: "director" }],
      reviewingManagerId: "ben",
      employeeId: "ana",
      concerns: [],
      hrConcerns: settings.hrConcerns,
      hrReviewedBy: null,
    }),
  );
  expectCode("ROUTE_APPROVALS_MISSING", () =>
    releaseReview({
      calibrationRequired: true,
      calibrated: true,
      steps: oneUp,
      approvals: [],
      reviewingManagerId: "ben",
      employeeId: "ana",
      concerns: [],
      hrConcerns: settings.hrConcerns,
      hrReviewedBy: null,
    }),
  );
});

test("PERF-034 the reviewing manager and the employee cannot approve", () => {
  for (const approverId of ["ben", "ana"]) {
    expectCode("SELF_APPROVAL", () =>
      releaseReview({
        calibrationRequired: true,
        calibrated: true,
        steps: oneUp,
        approvals: [{ role: "one_up", approverId }],
        reviewingManagerId: "ben",
        employeeId: "ana",
        concerns: [],
        hrConcerns: settings.hrConcerns,
        hrReviewedBy: null,
      }),
    );
  }
});

test("PERF-035 HR looks when the rating differs from the suggestion", () => {
  const input = {
    calibrationRequired: true,
    calibrated: true,
    steps: oneUp,
    approvals: [{ role: "one_up", approverId: "director" }],
    reviewingManagerId: "ben",
    employeeId: "ana",
    concerns: ["differs_from_suggestion"],
    hrConcerns: settings.hrConcerns,
    hrReviewedBy: null as string | null,
  };
  expectCode("HR_REVIEW_REQUIRED", () => releaseReview(input));
  assert.equal(releaseReview({ ...input, hrReviewedBy: "hr-1" }).released, true);
});

test("PERF-036 dropping protected leave releases after the one-up look", () => {
  const concerns = settings.hrConcerns.filter((concern) => concern !== "protected_leave");
  assert.equal(
    releaseReview({
      calibrationRequired: true,
      calibrated: true,
      steps: oneUp,
      approvals: [{ role: "one_up", approverId: "director" }],
      reviewingManagerId: "ben",
      employeeId: "ana",
      concerns: ["protected_leave"],
      hrConcerns: concerns,
      hrReviewedBy: null,
    }).released,
    true,
  );
});

test("PERF-037 signing means the employee has seen it", () => {
  expectCode("INPUT_REQUIRED", () => signReview({ seen: false, comment: "I disagree" }));
  assert.equal(signReview({ seen: true, comment: "Please ask HR" }).comment, "Please ask HR");
  expectCode("INPUT_REQUIRED", () => decideHrReview({ outcome: "uphold", reason: "", by: "hr-1" }));
});

test("PERF-038 a change after release tells the employee", () => {
  expectCode("RATING_CHANGE_REASON_REQUIRED", () =>
    changeAfterRelease({ actorIsHr: true, from: 3, to: 4, by: "hr-1", reason: " ", history: [] }),
  );
  const changed = changeAfterRelease({ actorIsHr: true, from: 3, to: 4, by: "hr-1", reason: "corrected the section", history: [] });
  assert.equal(changed.employeeTold, true);
  assert.equal(changed.history[0].stage, "after_final");
});

test("PERF-039 360 results stay developmental unless the cycle says otherwise", () => {
  expectCode("FEEDBACK_DEVELOPMENT_ONLY", () =>
    requestFeedback({
      cycleUse: settings.feedback360,
      purpose: "ratings",
      nomineeId: "peer",
      subjectId: "ana",
      group: "peer",
      groupCount: 1,
      groupMax: settings.raterGroupMax,
    }),
  );
});

test("PERF-040 an employee cannot nominate herself and a group has a maximum", () => {
  expectCode("SELF_REVIEW", () =>
    requestFeedback({
      cycleUse: "development_only",
      purpose: "development",
      nomineeId: "ana",
      subjectId: "ana",
      group: "peer",
      groupCount: 1,
      groupMax: settings.raterGroupMax,
    }),
  );
  expectCode("FEEDBACK_RATERS_OVER_MAX", () =>
    requestFeedback({
      cycleUse: "development_only",
      purpose: "development",
      nomineeId: "peer-6",
      subjectId: "ana",
      group: "peer",
      groupCount: settings.raterGroupMax + 1,
      groupMax: settings.raterGroupMax,
    }),
  );
});

test("PERF-041 a rater group is shown from the minimum and the manager group always is", () => {
  assert.equal(feedbackVisible({ group: "peer", answered: 2, minimum: settings.raterGroupMin }), false);
  assert.equal(feedbackVisible({ group: "peer", answered: settings.raterGroupMin, minimum: settings.raterGroupMin }), true);
  assert.equal(feedbackVisible({ group: "manager", answered: 0, minimum: settings.raterGroupMin }), true);
});

test("PERF-042 check-in nudges follow the organization's days", () => {
  assert.equal(checkinNudge({ lastCheckin: null, on: "2026-04-10", nudgeDays: settings.checkinNudgeDays, language: "en-CA" }).nudge, true);
  assert.equal(checkinNudge({ lastCheckin: "2026-03-31", on: "2026-04-10", nudgeDays: settings.checkinNudgeDays, language: "en-CA" }).nudge, false);
  assert.equal(checkinNudge({ lastCheckin: "2026-03-31", on: "2026-04-10", nudgeDays: 7, language: "en-CA" }).nudge, true);
  assert.equal(settings.checkinNudgeDays, 30);
});

test("PERF-043 every cause is ruled out", () => {
  expectCode("PIP_CAUSES_NOT_REVIEWED", () => submitPip({ causesRuledOut: ["expectations", "training", "accommodation"] }));
});

test("PERF-044 a plan with no end uses the default length", () => {
  assert.equal(settings.pipDefaultDays, 60);
  assert.equal(pipEnd("2026-01-15", null, settings.pipDefaultDays), "2026-03-16");
  assert.equal(pipEnd("2026-01-15", "2026-04-01", settings.pipDefaultDays), "2026-04-01");
});

test("PERF-045 the plan route is HR and not the manager or the employee", () => {
  expectCode("ROUTE_APPROVALS_MISSING", () =>
    approvePip({
      steps: hrRoute,
      approvals: [],
      managerId: "ben",
      employeeId: "ana",
      onProtectedLeave: false,
      protectedGround: false,
      cautionAcknowledged: false,
      cautionReason: "",
    }),
  );
  expectCode("SELF_APPROVAL", () =>
    approvePip({
      steps: hrRoute,
      approvals: [{ role: "hr", approverId: "ana" }],
      managerId: "ben",
      employeeId: "ana",
      onProtectedLeave: false,
      protectedGround: false,
      cautionAcknowledged: false,
      cautionReason: "",
    }),
  );
  assert.equal(
    approvePip({
      steps: hrRoute,
      approvals: [{ role: "hr", approverId: "hr-1" }],
      managerId: "ben",
      employeeId: "ana",
      onProtectedLeave: false,
      protectedGround: false,
      cautionAcknowledged: false,
      cautionReason: "",
    }).approved,
    true,
  );
});

test("PERF-046 the employee acknowledges the plan before it starts", () => {
  expectCode("INPUT_REQUIRED", () => startPip(false));
  assert.equal(startPip(true).started, true);
  expectCode("INPUT_REQUIRED", () => extendPip({ reason: "", end: "2026-05-01", previousEnd: "2026-03-16" }));
  expectCode("INPUT_REQUIRED", () => extendPip({ reason: "more coaching", end: "2026-03-16", previousEnd: "2026-03-16" }));
  assert.equal(extendPip({ reason: "more coaching", end: "2026-05-01", previousEnd: "2026-03-16" }).end, "2026-05-01");
});

test("PERF-047 a plan does not start during parental leave", () => {
  expectCode("PIP_DURING_PROTECTED_LEAVE", () =>
    approvePip({
      steps: hrRoute,
      approvals: [{ role: "hr", approverId: "hr-1" }],
      managerId: "ben",
      employeeId: "ana",
      onProtectedLeave: true,
      protectedGround: false,
      cautionAcknowledged: true,
      cautionReason: "noted",
    }),
  );
});

test("PERF-048 a possible protected ground needs the caution", () => {
  expectCode("CAUTION_NOT_ACKNOWLEDGED", () =>
    approvePip({
      steps: hrRoute,
      approvals: [{ role: "hr", approverId: "hr-1" }],
      managerId: "ben",
      employeeId: "ana",
      onProtectedLeave: false,
      protectedGround: true,
      cautionAcknowledged: false,
      cautionReason: "",
    }),
  );
  assert.equal(
    approvePip({
      steps: hrRoute,
      approvals: [{ role: "hr", approverId: "hr-1" }],
      managerId: "ben",
      employeeId: "ana",
      onProtectedLeave: false,
      protectedGround: true,
      cautionAcknowledged: true,
      cautionReason: "accommodation review recorded",
    }).approved,
    true,
  );
});

test("PERF-049 non-union sunset months come from the organization", () => {
  assert.equal(settings.nonUnionSunsetMonths, null);
  const open = adverseInForce({
    basis: "non_union",
    agreementSunsetMonths: null,
    organizationMonths: null,
    recordedOn: "2024-01-01",
    asOf: "2026-06-01",
  });
  assert.equal(open.inForce, true);
  assert.equal(open.hrKeeps, true);
  const closed = adverseInForce({
    basis: "non_union",
    agreementSunsetMonths: null,
    organizationMonths: 24,
    recordedOn: "2024-01-01",
    asOf: "2026-01-01",
  });
  assert.equal(closed.inForce, false);
  expectCode("INPUT_REQUIRED", () =>
    adverseInForce({
      basis: "agreement",
      agreementSunsetMonths: null,
      organizationMonths: 24,
      recordedOn: "2024-01-01",
      asOf: "2026-01-01",
    }),
  );
});

test("PERF-050 another organization reads no performance rows", () => {
  assert.deepEqual(readPerformance("north", "south", [{ id: "review-1" }]), []);
});
