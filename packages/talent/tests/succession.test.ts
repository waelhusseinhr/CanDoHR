import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  TalentError,
  applyToPool,
  approvePoolMember,
  approveSuccessionPlan,
  assessPotential,
  biasPrompt,
  changeApprovedPlan,
  confirmCritical,
  continuitySheet,
  costAssumption,
  criticalWeightsValid,
  declineApplication,
  defineSegment,
  demandFte,
  directHireUnionized,
  draftGapStrategy,
  historySummary,
  languageGap,
  missingPlanReminder,
  movePlacement,
  openNineBox,
  openTalentReview,
  openWorkforce,
  planReviewNotice,
  positionPlan,
  proposeCareerStep,
  readSuccession,
  recordFlightRisk,
  recordRetirement,
  recordVacancyDate,
  releaseReduction,
  saveScenario,
  scoreCriticalRole,
  seeContinuity,
  successionReadiness,
  supplyRate,
  unionizedPlan,
  uploadHistory,
  viewSuccession,
} from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const successionSql = readFileSync(join(root, "schema/0016_succession_workforce_decisions.sql"), "utf8");
const compensationSql = readFileSync(join(root, "schema/0011_compensation_decisions.sql"), "utf8");

function insertDefault(sql: string, key: string): string {
  const re = new RegExp(
    `\\('${key}',\\s*'[^']+',\\s*'[^']+',\\s*(?:NULL|'(?:[^']|'')*'),\\s*(NULL|'(?:[^']|'')*')`,
  );
  const match = re.exec(sql);
  if (!match) throw new Error(`setting ${key} is not in the schema file`);
  if (match[1] === "NULL") return "";
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

const weights = json<Record<string, number>>(insertDefault(successionSql, "succession.critical_weights"));
const criteria = json<{ criteria: { code: string }[] }>(insertDefault(successionSql, "succession.potential_criteria")).criteria.map(
  (row) => row.code,
);
const reviewMonths = Number(insertDefault(successionSql, "succession.plan_review_months"));
const reminderDays = Number(insertDefault(successionSql, "succession.plan_review_reminder_days"));
const continuityMonths = Number(insertDefault(successionSql, "succession.continuity_review_months"));
const thin = json<{ minPeople: number; minYears: number }>(insertDefault(successionSql, "workforce.thin_history"));
const biasMinimum = Number(insertDefault(compensationSql, "privacy.min_group_size_self_id"));
const reviewsOn = insertDefault(successionSql, "succession.talent_review_enabled") === "true";
const nineOn = insertDefault(successionSql, "succession.nine_box_enabled") === "true";
const workforceOn = insertDefault(successionSql, "workforce.planning_enabled") === "true";
const biasOn = insertDefault(successionSql, "succession.bias_prompts") === "true";
const readiness = ["ready_now", "one_to_two_years", "three_years_or_more"];
const planRoute = [{ role: "hr" }];
const poolRoute = [{ role: "pool_owner" }];
const positionRoute = [{ role: "finance" }, { role: "hr" }, { role: "executive" }];

test("SUCC-001 critical scores use the organization's weights and HR confirms", () => {
  criticalWeightsValid(weights);
  const scored = scoreCriticalRole({
    weights,
    scores: { impact: 5, hardToReplace: 4, singlePointOfFailure: 5, marketScarcity: 3, requiredByLaw: 5 },
    requiredByLaw: false,
    legalBasis: "",
  });
  assert.equal(scored.score, "4.40");
  expectCode("SELF_APPROVAL", () => confirmCritical("leader", "leader"));
  assert.equal(confirmCritical("leader", "hr-1").confirmed, true);
  expectCode("INPUT_REQUIRED", () =>
    scoreCriticalRole({
      weights,
      scores: { impact: 5, hardToReplace: 4, singlePointOfFailure: 5, marketScarcity: 3, requiredByLaw: 5 },
      requiredByLaw: true,
      legalBasis: "",
    }),
  );
});

test("SUCC-002 a succession plan uses the organization's route and list", () => {
  expectCode("INPUT_REQUIRED", () =>
    approveSuccessionPlan({
      steps: [],
      approvals: [],
      ownerId: "owner",
      requiredByLaw: false,
      emergencySuccessorId: null,
      reviewMonths,
      approvedOn: "2026-01-15",
    }),
  );
  expectCode("LIST_VALUE_UNKNOWN", () => successionReadiness("soon", readiness));
  assert.equal(successionReadiness("ready_now", readiness), "ready_now");
  const approved = approveSuccessionPlan({
    steps: planRoute,
    approvals: [{ role: "hr", approverId: "hr-1" }],
    ownerId: "owner",
    requiredByLaw: true,
    emergencySuccessorId: "ben",
    reviewMonths,
    approvedOn: "2026-01-15",
  });
  assert.equal(approved.reviewOn, "2027-01-15");
  assert.equal(changeApprovedPlan().priorApprovalCounts, false);
});

test("SUCC-003 a position plan names its kind and year and uses the route", () => {
  expectCode("INPUT_REQUIRED", () =>
    positionPlan({ kind: null, fiscalYear: "2026", steps: positionRoute, approvals: [], ownerId: "leader" }),
  );
  expectCode("INPUT_REQUIRED", () =>
    positionPlan({ kind: "workforce", fiscalYear: "2026", steps: [], approvals: [], ownerId: "leader" }),
  );
});

test("SUCC-004 a cost assumption states why and names the agreement", () => {
  expectCode("INPUT_REQUIRED", () => costAssumption({ kind: "overtime", reason: "", agreementId: null }));
  expectCode("INPUT_REQUIRED", () => costAssumption({ kind: "agreement_increase", reason: "grid", agreementId: null }));
  assert.equal(costAssumption({ kind: "overtime", reason: "last winter's call-outs", agreementId: null }).kept, true);
});

test("SUCC-005 talent reviews, the nine-box and workforce planning stay off", () => {
  assert.equal(reviewsOn, false);
  assert.equal(nineOn, false);
  assert.equal(workforceOn, false);
  expectCode("FEATURE_OFF", () => openTalentReview(reviewsOn));
  expectCode("FEATURE_OFF", () => openNineBox(nineOn));
  expectCode("FEATURE_OFF", () => openWorkforce(workforceOn));
  openTalentReview(true);
  openNineBox(true);
  assert.equal(missingPlanReminder(false).remindHr, true);
});

test("SUCC-006 succession data is shown only to the people named and every view is logged", () => {
  const named = viewSuccession({ namedIds: ["ben", "hr-1"], hr: false, viewerId: "ben", subject: "clerk", at: "2026-06-01", log: [] });
  assert.equal(named.allowed, true);
  assert.equal(named.log.length, 1);
  const outsider = viewSuccession({ namedIds: ["ben"], hr: false, viewerId: "dee", subject: "clerk", at: "2026-06-01", log: [] });
  assert.equal(outsider.allowed, false);
  assert.equal(outsider.log.length, 0);
  const vacancy = recordVacancyDate({ on: "2027-03-01", reason: "work authorization" });
  assert.deepEqual(vacancy, { on: "2027-03-01" });
  assert.equal(seeContinuity({ viewerId: "analyst", incumbentId: "clerk", successorId: "ben", managerId: "owner", hr: false }), false);
});

test("SUCC-007 flight risk is the manager's note and the aspiration is shown", () => {
  expectCode("SELF_REVIEW", () => recordFlightRisk({ by: "ana", subjectId: "ana", level: "medium", note: "looking" }));
  const recorded = recordFlightRisk({ by: "ben", subjectId: "ana", level: "medium", note: "asked about other cities" });
  assert.equal(recorded.modelScore, null);
  assert.equal(recorded.level, "medium");
  const shown = assessPotential({
    assessorId: "ben",
    subjectId: "dee",
    criteria,
    scores: { learning_agility: "moderate", leadership: "moderate", aspiration: "low", engagement: "high" },
    openToSuccession: false,
    aspiration: "stay in roads",
  });
  assert.equal(shown.aspirationShown, "stay in roads");
});

test("SUCC-008 potential, the nine-box and bias prompts", () => {
  expectCode("SELF_REVIEW", () =>
    assessPotential({
      assessorId: "ana",
      subjectId: "ana",
      criteria,
      scores: { learning_agility: "high", leadership: "high", aspiration: "high", engagement: "high" },
      openToSuccession: true,
      aspiration: "clerk",
    }),
  );
  expectCode("PLACEMENT_REASON_REQUIRED", () => movePlacement({ from: "moderate_high", to: "high_high", reason: "", by: "ben", history: [] }));
  const moved = movePlacement({ from: "moderate_high", to: "high_high", reason: "led the election file", by: "ben", history: [] });
  assert.equal(moved[0].box, "high_high");
  const hidden = biasPrompt({ enabled: biasOn, minimum: biasMinimum, groups: [{ name: "part-time", people: 1, lowPotential: 1 }] });
  assert.equal(hidden.shown, false);
});

test("SUCC-009 a unionized plan is for development and a direct hire needs the caution", () => {
  assert.equal(unionizedPlan().developmentOnly, true);
  expectCode("CAUTION_NOT_ACKNOWLEDGED", () => directHireUnionized({ acknowledged: false, reason: "" }));
  assert.equal(directHireUnionized({ acknowledged: true, reason: "the agreement allows this appointment" }).allowed, true);
});

test("SUCC-010 a continuity sheet refuses a password and is reviewed on the organization's cycle", () => {
  expectCode("SECRET_NOT_ALLOWED", () =>
    continuitySheet({ contacts: "admin password is on the card", access: "vault", notes: "where the vault is", reviewMonths: continuityMonths, writtenOn: "2026-01-15" }),
  );
  expectCode("SECRET_NOT_ALLOWED", () =>
    continuitySheet({ contacts: "clerk", access: "vault", notes: "the PIN is 1234", reviewMonths: continuityMonths, writtenOn: "2026-01-15" }),
  );
  const sheet = continuitySheet({
    contacts: "deputy clerk",
    access: "the vault in the clerk's office",
    notes: "election binders are on the second shelf",
    reviewMonths: continuityMonths,
    writtenOn: "2026-01-15",
  });
  assert.equal(sheet.updateDue, "2027-01-15");
  assert.equal(seeContinuity({ viewerId: "clerk", incumbentId: "clerk", successorId: "ben", managerId: "owner", hr: false }), true);
  assert.equal(seeContinuity({ viewerId: "ben", incumbentId: "clerk", successorId: "ben", managerId: "owner", hr: false }), true);
});

test("SUCC-011 pools and career steps", () => {
  expectCode("POOL_CLOSED_TO_APPLICATIONS", () => applyToPool({ nominationsOnly: true, applicantIsSubject: true }));
  expectCode("INPUT_REQUIRED", () => applyToPool({ nominationsOnly: false, applicantIsSubject: false }));
  applyToPool({ nominationsOnly: false, applicantIsSubject: true });
  expectCode("SELF_APPROVAL", () =>
    approvePoolMember({
      steps: poolRoute,
      approvals: [{ role: "pool_owner", approverId: "nominator" }],
      nominatorId: "nominator",
      nomineeId: "ana",
    }),
  );
  const step = proposeCareerStep({ fromJob: "analyst", toJob: "deputy clerk", observed: true });
  assert.equal(step.proposed, true);
  expectCode("INPUT_REQUIRED", () => proposeCareerStep({ fromJob: "analyst", toJob: "deputy clerk", observed: false }));
});

test("SUCC-012 supply, demand, locked scenarios and a unionized reduction", () => {
  const analysts = historySummary({ people: 3, years: 1, separations: 1, thinPeople: thin.minPeople, thinYears: thin.minYears });
  assert.equal(analysts.thin, true);
  assert.equal(analysts.rate, null);
  expectCode("HISTORY_TOO_THIN", () => supplyRate({ thin: true, source: "own", parentRate: null, plannerRate: null, reason: "" }));
  assert.equal(demandFte({ volume: "360", perFte: "12" }).fte, "30.00");
  expectCode("SCENARIO_VERSION_LOCKED", () => saveScenario({ locked: true, copy: false }));
  assert.equal(saveScenario({ locked: true, copy: true }).version, 2);
  assert.equal(draftGapStrategy("hire").applied, false);
  expectCode("LABOUR_RELATIONS_REVIEW_REQUIRED", () =>
    releaseReduction({
      unionized: true,
      drafted: true,
      labourReviewerId: "planner",
      releaserId: "planner",
      cautionAcknowledged: true,
      cautionReason: "reviewed",
    }),
  );
});

test("SUCC-020 setup leaves reviews off and bias prompts on", () => {
  assert.equal(reviewsOn, false);
  assert.equal(nineOn, false);
  assert.equal(workforceOn, false);
  assert.equal(biasOn, true);
  assert.deepEqual(weights, { impact: 20, hardToReplace: 20, singlePointOfFailure: 20, marketScarcity: 20, requiredByLaw: 20 });
  assert.equal(reviewMonths, 12);
  assert.equal(reminderDays, 30);
  assert.equal(continuityMonths, 12);
  assert.deepEqual(thin, { minPeople: 10, minYears: 2 });
  assert.equal(biasMinimum, 10);
});

test("SUCC-021 a score outside 1 to 5 is refused", () => {
  expectCode("CRITICAL_SCORE_INVALID", () =>
    scoreCriticalRole({
      weights,
      scores: { impact: 5, hardToReplace: 4, singlePointOfFailure: 5, marketScarcity: 3 },
      requiredByLaw: false,
      legalBasis: "",
    }),
  );
  expectCode("CRITICAL_SCORE_INVALID", () =>
    scoreCriticalRole({
      weights,
      scores: { impact: 6, hardToReplace: 4, singlePointOfFailure: 5, marketScarcity: 3, requiredByLaw: 5 },
      requiredByLaw: false,
      legalBasis: "",
    }),
  );
});

test("SUCC-022 a role the law requires states its legal basis", () => {
  expectCode("INPUT_REQUIRED", () =>
    scoreCriticalRole({
      weights,
      scores: { impact: 5, hardToReplace: 5, singlePointOfFailure: 5, marketScarcity: 5, requiredByLaw: 5 },
      requiredByLaw: true,
      legalBasis: " ",
    }),
  );
});

test("SUCC-023 weights have to add to 100", () => {
  expectCode("CRITICAL_WEIGHTS_INVALID", () => criticalWeightsValid({ impact: 40, hardToReplace: 40, singlePointOfFailure: 40 }));
});

test("SUCC-024 equal weights on 5, 4, 5, 3 and 5 score 4.40", () => {
  assert.equal(
    scoreCriticalRole({
      weights,
      scores: { impact: 5, hardToReplace: 4, singlePointOfFailure: 5, marketScarcity: 3, requiredByLaw: 5 },
      requiredByLaw: false,
      legalBasis: "",
    }).score,
    "4.40",
  );
  expectCode("SELF_APPROVAL", () => confirmCritical("leader", "leader"));
  assert.equal(confirmCritical("leader", "hr-1").confirmed, true);
});

test("SUCC-025 a critical role with no plan reminds HR", () => {
  assert.equal(missingPlanReminder(false).remindHr, true);
  assert.equal(missingPlanReminder(true).remindHr, false);
});

test("SUCC-026 flight risk has no model score", () => {
  expectCode("SELF_REVIEW", () => recordFlightRisk({ by: "ana", subjectId: "ana", level: "high", note: "note" }));
  assert.equal(recordFlightRisk({ by: "ben", subjectId: "ana", level: "medium", note: "asked about other cities" }).modelScore, null);
  expectCode("INPUT_REQUIRED", () => recordFlightRisk({ by: "ben", subjectId: "ana", level: "low", note: " " }));
});

test("SUCC-027 retirement is recorded only when the employee shared it and the source is named", () => {
  expectCode("INPUT_REQUIRED", () => recordRetirement({ sharedByEmployee: false, source: "employee" }));
  expectCode("INPUT_REQUIRED", () => recordRetirement({ sharedByEmployee: true, source: "" }));
  assert.equal(recordRetirement({ sharedByEmployee: true, source: "employee" }).source, "employee");
});

test("SUCC-028 a vacancy date does not carry its reason", () => {
  assert.deepEqual(recordVacancyDate({ on: "2027-04-30", reason: "work authorization ends" }), { on: "2027-04-30" });
});

test("SUCC-029 talent reviews and the nine-box are off until switched on", () => {
  expectCode("FEATURE_OFF", () => openTalentReview(false));
  expectCode("FEATURE_OFF", () => openNineBox(false));
});

test("SUCC-030 a switched-on nine-box can be opened", () => {
  openNineBox(true);
});

test("SUCC-031 potential uses only the organization's criteria", () => {
  expectCode("SELF_REVIEW", () =>
    assessPotential({
      assessorId: "ana",
      subjectId: "ana",
      criteria,
      scores: Object.fromEntries(criteria.map((code) => [code, "moderate"])),
      openToSuccession: true,
      aspiration: "clerk",
    }),
  );
  expectCode("POTENTIAL_CRITERION_UNKNOWN", () =>
    assessPotential({
      assessorId: "ben",
      subjectId: "ana",
      criteria,
      scores: { ...Object.fromEntries(criteria.map((code) => [code, "moderate"])), flight: "high" },
      openToSuccession: true,
      aspiration: "clerk",
    }),
  );
  const partial: Record<string, string> = {};
  partial[criteria[0]] = "moderate";
  expectCode("INPUT_REQUIRED", () =>
    assessPotential({
      assessorId: "ben",
      subjectId: "ana",
      criteria,
      scores: partial,
      openToSuccession: true,
      aspiration: "clerk",
    }),
  );
});

test("SUCC-032 an aspiration is shown, or not stated", () => {
  assert.equal(
    assessPotential({
      assessorId: "ben",
      subjectId: "dee",
      criteria,
      scores: Object.fromEntries(criteria.map((code) => [code, "moderate"])),
      openToSuccession: false,
      aspiration: "stay in the role",
    }).aspirationShown,
    "stay in the role",
  );
  assert.equal(
    assessPotential({
      assessorId: "ben",
      subjectId: "ana",
      criteria,
      scores: Object.fromEntries(criteria.map((code) => [code, "high"])),
      openToSuccession: true,
      aspiration: null,
    }).aspirationShown,
    "not stated",
  );
});

test("SUCC-033 a nine-box move keeps its reason", () => {
  expectCode("PLACEMENT_REASON_REQUIRED", () => movePlacement({ from: "moderate_high", to: "high_high", reason: "", by: "ben", history: [] }));
  const history = movePlacement({ from: "moderate_high", to: "high_high", reason: "led the file", by: "ben", history: [] });
  assert.equal(history.length, 1);
  assert.equal(history[0].reason, "led the file");
});

test("SUCC-034 bias prompts wait until every group meets the minimum", () => {
  assert.equal(biasMinimum, 10);
  assert.equal(biasPrompt({ enabled: true, minimum: biasMinimum, groups: [{ name: "part-time", people: 1, lowPotential: 1 }] }).shown, false);
  const shown = biasPrompt({
    enabled: true,
    minimum: biasMinimum,
    groups: [
      { name: "full-time", people: 11, lowPotential: 7 },
      { name: "part-time", people: 11, lowPotential: 2 },
    ],
  });
  assert.equal(shown.shown, true);
  assert.equal(shown.percents[0].lowPotentialPercent, "63.6");
  assert.equal(shown.percents[1].lowPotentialPercent, "18.2");
  assert.equal(biasPrompt({ enabled: false, minimum: biasMinimum, groups: [{ name: "full-time", people: 11, lowPotential: 7 }] }).shown, false);
});

test("SUCC-035 only a named person or HR opens the review", () => {
  const participant = viewSuccession({ namedIds: ["ben"], hr: false, viewerId: "ben", subject: "review-1", at: "2026-06-01", log: [] });
  assert.equal(participant.allowed, true);
  assert.equal(participant.log[0].viewerId, "ben");
  const other = viewSuccession({ namedIds: ["ben"], hr: false, viewerId: "dee", subject: "review-1", at: "2026-06-01", log: participant.log });
  assert.equal(other.allowed, false);
  assert.equal(other.log.length, 1);
});

test("SUCC-036 a plan needs its route and readiness comes from the organization's list", () => {
  expectCode("INPUT_REQUIRED", () =>
    approveSuccessionPlan({
      steps: [],
      approvals: [],
      ownerId: "owner",
      requiredByLaw: false,
      emergencySuccessorId: "ben",
      reviewMonths,
      approvedOn: "2026-01-15",
    }),
  );
  expectCode("LIST_VALUE_UNKNOWN", () => successionReadiness("soon", readiness));
});

test("SUCC-037 a language gap is the required level against the level held", () => {
  assert.equal(languageGap({ required: "fr-B", held: "fr-A" }).gap, true);
  assert.equal(languageGap({ required: "fr-B", held: "fr-B" }).gap, false);
  const dee = assessPotential({
    assessorId: "ben",
    subjectId: "dee",
    criteria,
    scores: Object.fromEntries(criteria.map((code) => [code, "moderate"])),
    openToSuccession: false,
    aspiration: "not interested",
  });
  assert.equal(dee.aspirationShown, "not interested");
});

test("SUCC-038 the owner cannot approve and a role the law requires needs an emergency successor", () => {
  expectCode("ROUTE_APPROVALS_MISSING", () =>
    approveSuccessionPlan({
      steps: planRoute,
      approvals: [],
      ownerId: "owner",
      requiredByLaw: true,
      emergencySuccessorId: "ben",
      reviewMonths,
      approvedOn: "2026-01-15",
    }),
  );
  expectCode("SELF_APPROVAL", () =>
    approveSuccessionPlan({
      steps: planRoute,
      approvals: [{ role: "hr", approverId: "owner" }],
      ownerId: "owner",
      requiredByLaw: true,
      emergencySuccessorId: "ben",
      reviewMonths,
      approvedOn: "2026-01-15",
    }),
  );
  expectCode("EMERGENCY_SUCCESSOR_REQUIRED", () =>
    approveSuccessionPlan({
      steps: planRoute,
      approvals: [{ role: "hr", approverId: "hr-1" }],
      ownerId: "owner",
      requiredByLaw: true,
      emergencySuccessorId: null,
      reviewMonths,
      approvedOn: "2026-01-15",
    }),
  );
});

test("SUCC-039 an approved plan sets the next review and the reminder stops", () => {
  const approved = approveSuccessionPlan({
    steps: planRoute,
    approvals: [{ role: "hr", approverId: "hr-1" }],
    ownerId: "owner",
    requiredByLaw: true,
    emergencySuccessorId: "ben",
    reviewMonths,
    approvedOn: "2026-01-15",
  });
  assert.equal(approved.reviewOn, "2027-01-15");
  assert.equal(missingPlanReminder(true).remindHr, false);
});

test("SUCC-040 the owner is reminded on the reminder day", () => {
  assert.equal(reminderDays, 30);
  assert.equal(planReviewNotice({ reviewOn: "2026-06-01", on: "2026-05-02", reminderDays }), "remind");
  assert.equal(planReviewNotice({ reviewOn: "2026-06-01", on: "2026-05-03", reminderDays }), "quiet");
  assert.equal(planReviewNotice({ reviewOn: "2026-06-01", on: "2026-06-02", reminderDays }), "overdue");
});

test("SUCC-041 a change to an approved plan goes through the route again", () => {
  const again = changeApprovedPlan();
  assert.equal(again.routeAgain, true);
  assert.equal(again.priorApprovalCounts, false);
});

test("SUCC-042 a unionized plan is development only and a direct hire needs a reason", () => {
  assert.equal(unionizedPlan().developmentOnly, true);
  expectCode("CAUTION_NOT_ACKNOWLEDGED", () => directHireUnionized({ acknowledged: true, reason: " " }));
  assert.equal(directHireUnionized({ acknowledged: true, reason: "posting waived under the agreement" }).allowed, true);
});

test("SUCC-043 continuity notes cannot hold a password, a PIN or a token", () => {
  expectCode("SECRET_NOT_ALLOWED", () =>
    continuitySheet({ contacts: "password: winter", access: "office", notes: "binders", reviewMonths: continuityMonths, writtenOn: "2026-02-01" }),
  );
  expectCode("SECRET_NOT_ALLOWED", () =>
    continuitySheet({ contacts: "deputy", access: "office", notes: "PIN on the card", reviewMonths: continuityMonths, writtenOn: "2026-02-01" }),
  );
  assert.equal(
    continuitySheet({ contacts: "deputy", access: "vault in the clerk's office", notes: "binders", reviewMonths: continuityMonths, writtenOn: "2026-02-01" }).updateDue,
    "2027-02-01",
  );
});

test("SUCC-044 the incumbent and the interim successor see the sheet", () => {
  assert.equal(seeContinuity({ viewerId: "clerk", incumbentId: "clerk", successorId: "ben", managerId: "owner", hr: false }), true);
  assert.equal(seeContinuity({ viewerId: "ben", incumbentId: "clerk", successorId: "ben", managerId: "owner", hr: false }), true);
  assert.equal(seeContinuity({ viewerId: "analyst", incumbentId: "clerk", successorId: "ben", managerId: "owner", hr: false }), false);
  assert.equal(seeContinuity({ viewerId: "hr-1", incumbentId: "clerk", successorId: "ben", managerId: "owner", hr: true }), true);
});

test("SUCC-045 a nominations-only pool is closed and nobody applies for someone else", () => {
  expectCode("POOL_CLOSED_TO_APPLICATIONS", () => applyToPool({ nominationsOnly: true, applicantIsSubject: false }));
  expectCode("INPUT_REQUIRED", () => applyToPool({ nominationsOnly: false, applicantIsSubject: false }));
});

test("SUCC-046 the nominator and the nominee cannot approve the pool", () => {
  expectCode("ROUTE_APPROVALS_MISSING", () =>
    approvePoolMember({ steps: poolRoute, approvals: [], nominatorId: "ben", nomineeId: "ana" }),
  );
  expectCode("SELF_APPROVAL", () =>
    approvePoolMember({
      steps: poolRoute,
      approvals: [{ role: "pool_owner", approverId: "ben" }],
      nominatorId: "ben",
      nomineeId: "ana",
    }),
  );
  expectCode("SELF_APPROVAL", () =>
    approvePoolMember({
      steps: poolRoute,
      approvals: [{ role: "pool_owner", approverId: "ana" }],
      nominatorId: "ben",
      nomineeId: "ana",
    }),
  );
  assert.equal(
    approvePoolMember({
      steps: poolRoute,
      approvals: [{ role: "pool_owner", approverId: "owner" }],
      nominatorId: "ben",
      nomineeId: "ana",
    }).approved,
    true,
  );
});

test("SUCC-047 a declined application names the reason", () => {
  expectCode("INPUT_REQUIRED", () => declineApplication(" "));
  assert.equal(declineApplication("the pool is for supervisors").declined, true);
});

test("SUCC-048 an observed move is proposed as a career step", () => {
  assert.equal(proposeCareerStep({ fromJob: "analyst", toJob: "deputy clerk", observed: true }).toJob, "deputy clerk");
});

test("SUCC-049 workforce planning is off and a segment scope is a known one", () => {
  expectCode("FEATURE_OFF", () => openWorkforce(false));
  expectCode("SEGMENT_SCOPE_UNKNOWN", () => defineSegment("teams"));
  assert.equal(defineSegment("org_unit").scope, "org_unit");
});

test("SUCC-050 history needs a file and a year that is not already loaded", () => {
  expectCode("INPUT_REQUIRED", () => uploadHistory({ fileName: "", year: "2024", loadedYears: [] }));
  expectCode("INPUT_REQUIRED", () => uploadHistory({ fileName: "turnover.csv", year: "2024", loadedYears: ["2024"] }));
  assert.equal(uploadHistory({ fileName: "turnover.csv", year: "2025", loadedYears: ["2024"] }).year, "2025");
});

test("SUCC-051 a thin segment does not use its own rate", () => {
  const analysts = historySummary({ people: 3, years: 1, separations: 1, thinPeople: thin.minPeople, thinYears: thin.minYears });
  assert.equal(analysts.thin, true);
  assert.equal(analysts.rate, null);
  const department = historySummary({ people: 40, years: 2, separations: 4, thinPeople: thin.minPeople, thinYears: thin.minYears });
  assert.equal(department.thin, false);
  assert.equal(department.rate, "5.00");
  assert.equal(supplyRate({ thin: true, source: "next_level", parentRate: department.rate, plannerRate: null, reason: "" }).rate, "5.00");
});

test("SUCC-052 a thin own rate, a planner rate without a reason, and a missing parent rate are refused", () => {
  expectCode("HISTORY_TOO_THIN", () => supplyRate({ thin: true, source: "own", parentRate: "5.00", plannerRate: null, reason: "" }));
  expectCode("SUPPLY_RATE_REASON_REQUIRED", () => supplyRate({ thin: true, source: "planner", parentRate: null, plannerRate: "4.00", reason: "" }));
  expectCode("INPUT_REQUIRED", () => supplyRate({ thin: false, source: "next_level", parentRate: null, plannerRate: null, reason: "" }));
});

test("SUCC-053 demand is volume divided by the organization's ratio", () => {
  assert.equal(demandFte({ volume: "360", perFte: "12" }).fte, "30.00");
});

test("SUCC-054 a locked scenario is copied rather than changed", () => {
  expectCode("SCENARIO_VERSION_LOCKED", () => saveScenario({ locked: true, copy: false }));
  assert.equal(saveScenario({ locked: true, copy: true }).version, 2);
  assert.equal(saveScenario({ locked: false, copy: false }).version, 1);
});

test("SUCC-055 a unionized reduction needs a draft, labour relations and the caution", () => {
  expectCode("INPUT_REQUIRED", () =>
    releaseReduction({ unionized: true, drafted: false, labourReviewerId: "labour", releaserId: "planner", cautionAcknowledged: true, cautionReason: "reviewed" }),
  );
  expectCode("LABOUR_RELATIONS_REVIEW_REQUIRED", () =>
    releaseReduction({ unionized: true, drafted: true, labourReviewerId: null, releaserId: "planner", cautionAcknowledged: true, cautionReason: "reviewed" }),
  );
  expectCode("LABOUR_RELATIONS_REVIEW_REQUIRED", () =>
    releaseReduction({ unionized: true, drafted: true, labourReviewerId: "planner", releaserId: "planner", cautionAcknowledged: true, cautionReason: "reviewed" }),
  );
  expectCode("CAUTION_NOT_ACKNOWLEDGED", () =>
    releaseReduction({ unionized: true, drafted: true, labourReviewerId: "labour", releaserId: "planner", cautionAcknowledged: false, cautionReason: "" }),
  );
  assert.equal(
    releaseReduction({
      unionized: true,
      drafted: true,
      labourReviewerId: "labour",
      releaserId: "planner",
      cautionAcknowledged: true,
      cautionReason: "the agreement was reviewed",
    }).released,
    true,
  );
});

test("SUCC-056 a position plan states its kind, its year and its route", () => {
  expectCode("INPUT_REQUIRED", () => positionPlan({ kind: "", fiscalYear: "2027", steps: positionRoute, approvals: [], ownerId: "leader" }));
  expectCode("INPUT_REQUIRED", () =>
    positionPlan({ kind: "position", fiscalYear: "2027", steps: [], approvals: [], ownerId: "leader" }),
  );
});

test("SUCC-057 the department leader cannot approve their own plan", () => {
  expectCode("SELF_APPROVAL", () =>
    positionPlan({
      kind: "position",
      fiscalYear: "2027",
      steps: positionRoute,
      approvals: [
        { role: "finance", approverId: "finance" },
        { role: "hr", approverId: "hr-1" },
        { role: "executive", approverId: "leader" },
      ],
      ownerId: "leader",
    }),
  );
  expectCode("ROUTE_APPROVALS_MISSING", () =>
    positionPlan({
      kind: "position",
      fiscalYear: "2027",
      steps: positionRoute,
      approvals: [
        { role: "finance", approverId: "finance" },
        { role: "hr", approverId: "hr-1" },
      ],
      ownerId: "leader",
    }),
  );
  assert.equal(
    positionPlan({
      kind: "position",
      fiscalYear: "2027",
      steps: positionRoute,
      approvals: [
        { role: "finance", approverId: "finance" },
        { role: "hr", approverId: "hr-1" },
        { role: "executive", approverId: "cao" },
      ],
      ownerId: "leader",
    }).approved,
    true,
  );
});

test("SUCC-058 an assumption without a reason or an agreement is refused", () => {
  expectCode("INPUT_REQUIRED", () => costAssumption({ kind: "overtime", reason: "", agreementId: null }));
  expectCode("INPUT_REQUIRED", () => costAssumption({ kind: "agreement_increase", reason: "the next grid", agreementId: "" }));
});

test("SUCC-059 another organization reads no succession rows", () => {
  assert.deepEqual(readSuccession("north", "south", [{ id: "plan" }]), []);
});
