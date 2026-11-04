import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  TalentError,
  actionPlan,
  announcement,
  anonymousMessage,
  approveCashAward,
  approvePublic,
  attachToReview,
  celebrationOptIn,
  changeOpenSurvey,
  confirmPayroll,
  decideIdea,
  directoryExtra,
  flagComment,
  givePoints,
  giveRecognition,
  giveReward,
  handleFlag,
  importResults,
  lifecycleSurvey,
  milestonesDue,
  milestoneReminder,
  observance,
  openSurvey,
  participation,
  readEngagement,
  readReminders,
  recognitionNotice,
  removeRecognition,
  requestPublic,
  screen,
  setGroupMinimum,
  submitAnswer,
  surveyAudience,
  surveyBreakdown,
  surveyMinimum,
  surveyMode,
  surveyNotice,
  surveyScores,
  voteIdea,
  wellbeingLink,
  type FlagRules,
  type GiftYear,
} from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const engagementSql = readFileSync(join(root, "schema/0017_engagement_decisions.sql"), "utf8");
const compensationSql = readFileSync(join(root, "schema/0011_compensation_decisions.sql"), "utf8");
const giftFile = JSON.parse(readFileSync(join(root, "rules/recognition/ca-2026-gifts-and-awards.json"), "utf8")) as {
  years: GiftYear[];
};
const flagFile = JSON.parse(readFileSync(join(root, "rules/engagement/comment-flag-rules.json"), "utf8")) as FlagRules & {
  status: string;
};

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

const mode = json<string>(insertDefault(engagementSql, "engagement.default_mode"));
const groupMinimum = Number(insertDefault(engagementSql, "engagement.min_group_size"));
const groupFloor = insertMin(engagementSql, "engagement.min_group_size");
const selfMinimum = Number(insertDefault(compensationSql, "privacy.min_group_size_self_id"));
const actionDays = Number(insertDefault(engagementSql, "engagement.action_plan_days"));
const milestoneYears = json<number[]>(insertDefault(engagementSql, "recognition.milestone_years"));
const milestoneDays = Number(insertDefault(engagementSql, "recognition.milestone_reminder_days"));
const readDays = json<number[]>(insertDefault(engagementSql, "announcements.read_reminder_days"));
const smsOn = insertDefault(engagementSql, "announcements.sms_for_urgent") === "true";
const giftYear = giftFile.years.find((year) => year.tax_year === 2026);
if (giftYear === undefined) throw new Error("2026 gift year is not in the recognition file");
const values = ["service", "respect", "teamwork"];
const publicRoute = [{ role: "hr" }];
const cashRoute = [{ role: "manager_manager" }, { role: "hr" }];
const qualifyingCard = { prepaid: true, cannotConvertToCash: true, singleRetailer: true };

test("ENG-001 survey answers carry no person and small groups stay hidden", () => {
  assert.equal(groupMinimum, 5);
  assert.equal(groupFloor, 3);
  assert.equal(selfMinimum, 10);
  expectCode("SETTING_BELOW_MINIMUM", () => setGroupMinimum(groupFloor - 1, groupFloor));
  const stored = submitAnswer({
    open: true,
    personId: null,
    itemKnown: true,
    mode: "confidential",
    tenure: "1-2",
    answeredOn: "2026-10-01",
    timeOfDay: null,
  });
  assert.equal(stored.personId, null);
  assert.equal(stored.answeredOn, "2026-10-01");
  expectCode("SUBMISSION_ATTRIBUTE_NOT_ALLOWED", () =>
    submitAnswer({ open: true, personId: "ana", itemKnown: true, mode: "confidential", tenure: null, answeredOn: "2026-10-01", timeOfDay: null }),
  );
  const scores = surveyScores({ items: [{ id: "workload", scores: ["4", "4", "4", "4"] }], minimum: groupMinimum });
  assert.equal(scores[0].shown, false);
  const town = { id: "town", covered: true, law: "Municipal Freedom of Information and Protection of Privacy Act" };
  expectCode("SURVEY_MODE_NOT_ALLOWED", () => surveyMode({ employers: [town], requested: "confidential" }));
  assert.equal(surveyMode({ employers: [town], requested: "anonymous" }), "anonymous");
});

test("ENG-002 milestones and the CRA gift limits", () => {
  assert.equal(giftYear.status, "official");
  assert.equal(giftYear.non_cash_annual_limit, 500);
  const due = milestonesDue({ serviceOn: "2021-11-29", years: milestoneYears, from: "2026-01-01", to: "2026-12-31" });
  assert.deepEqual(due, [{ on: "2026-11-29", years: 5 }]);
  assert.equal(milestoneReminder({ on: due[0].on, reminderDays: milestoneDays }), "2026-10-30");
  const first = giveReward({
    year: giftYear,
    kind: "non_cash",
    occasion: "recognition",
    amount: "300.00",
    serviceYears: 3,
    yearsSinceLongService: null,
    priorNonCash: "0.00",
    priorLongService: "0.00",
    card: null,
  });
  assert.equal(first.taxable, "0.00");
  const second = giveReward({
    year: giftYear,
    kind: "non_cash",
    occasion: "recognition",
    amount: "300.00",
    serviceYears: 3,
    yearsSinceLongService: null,
    priorNonCash: "300.00",
    priorLongService: "0.00",
    card: null,
  });
  assert.equal(second.taxable, "100.00");
  assert.equal(second.confirm, "to_confirm");
  assert.equal(second.payCode, "AWARD-BENEFIT");
});

test("ENG-003 recognition starts private and only the recipient can share it", () => {
  const given = giveRecognition({ giverId: "ben", recipientId: "ana", value: "service", values });
  assert.equal(given.visibility, "private");
  expectCode("RECIPIENT_CONSENT_REQUIRED", () => requestPublic({ byId: "ben", recipientId: "ana", hasRoute: true }));
  requestPublic({ byId: "ana", recipientId: "ana", hasRoute: true });
  expectCode("RECIPIENT_CONSENT_REQUIRED", () => attachToReview({ byId: "ben", recipientId: "ana", reviewSubjectId: "ana" }));
  assert.equal(attachToReview({ byId: "ana", recipientId: "ana", reviewSubjectId: "ana" }).attached, true);
  assert.equal(recognitionNotice("en-CA"), screen["en-CA"].recognitionPrivate);
  assert.equal(recognitionNotice("fr-CA"), screen["fr-CA"].recognitionPrivate);
});

test("ENG-004 an action plan is due from the organization's days and shows the team wording", () => {
  assert.equal(actionDays, 60);
  expectCode("INPUT_REQUIRED", () => actionPlan({ closesOn: "2026-10-23", days: actionDays, actions: ["one"], on: "2026-10-24", language: "en-CA" }));
  const plan = actionPlan({
    closesOn: "2026-10-23",
    days: actionDays,
    actions: ["staff the desk", "publish the notes"],
    on: "2026-12-23",
    language: "fr-CA",
  });
  assert.equal(plan.dueOn, "2026-12-22");
  assert.equal(plan.late, true);
  assert.equal(plan.teamText, screen["fr-CA"].youSaid);
});

test("ENG-005 results under the minimum are hidden and a roll-up can be shown", () => {
  const programs = surveyScores({
    items: [
      { id: "item-1", scores: ["4", "4", "4", "4", "4", "4"] },
      { id: "workload", scores: ["4", "4", "4", "4"] },
    ],
    minimum: groupMinimum,
  });
  assert.equal(programs[0].shown, true);
  assert.equal(programs[0].average, "4.00");
  assert.equal(programs[1].shown, false);
  const outreach = surveyScores({ items: [{ id: "item-1", scores: ["3", "3", "3"] }], minimum: groupMinimum });
  assert.equal(outreach[0].shown, false);
  const rollup = surveyScores({
    items: [{ id: "item-1", scores: ["4", "4", "4", "4", "4", "4", "3", "3", "3"] }],
    minimum: groupMinimum,
  });
  assert.equal(rollup[0].shown, true);
});

test("ENG-006 a flagged comment goes to the named contact with no identity", () => {
  expectCode("ESCALATION_CONTACT_REQUIRED", () =>
    openSurvey({ opensOn: "2026-10-01", closesOn: "2026-10-23", openComments: true, contactId: null, unionConsultation: false, cautionAcknowledged: false }),
  );
  const flagged = flagComment({ text: "The tone was threatening", rules: flagFile, contactId: "hr-1" });
  assert.equal(flagged.flagged, true);
  assert.equal(flagged.category, "harassment");
  assert.equal(flagged.personId, null);
  assert.equal(flagged.contactId, "hr-1");
  assert.equal(flagComment({ text: "There were threats", rules: flagFile, contactId: "hr-1" }).flagged, false);
  assert.equal(handleFlag("spoke with the unit").note, "spoke with the unit");
  assert.equal(surveyNotice("en-CA"), screen["en-CA"].speakUp);
  assert.notEqual(surveyNotice("en-CA"), surveyNotice("fr-CA"));
});

test("ENG-007 imports under the minimum are refused and union consultation needs the caution", () => {
  expectCode("INPUT_REQUIRED", () =>
    importResults({ intoCanDoSurvey: false, groups: [{ selfIdentified: false, size: 4 }], namesAPerson: false, unitMinimum: groupMinimum, selfMinimum }),
  );
  expectCode("INPUT_REQUIRED", () =>
    importResults({ intoCanDoSurvey: false, groups: [{ selfIdentified: true, size: 8 }], namesAPerson: false, unitMinimum: groupMinimum, selfMinimum }),
  );
  expectCode("INPUT_REQUIRED", () =>
    importResults({ intoCanDoSurvey: true, groups: [{ selfIdentified: false, size: 20 }], namesAPerson: false, unitMinimum: groupMinimum, selfMinimum }),
  );
  expectCode("CAUTION_NOT_ACKNOWLEDGED", () =>
    openSurvey({ opensOn: "2026-10-01", closesOn: "2026-10-23", openComments: false, contactId: null, unionConsultation: true, cautionAcknowledged: false }),
  );
  assert.equal(
    openSurvey({ opensOn: "2026-10-01", closesOn: "2026-10-23", openComments: false, contactId: null, unionConsultation: true, cautionAcknowledged: true }).open,
    true,
  );
});

test("ENG-008 a return-from-leave survey does not name the leave", () => {
  expectCode("INPUT_REQUIRED", () => lifecycleSurvey({ event: null, leaveName: null }));
  expectCode("INPUT_REQUIRED", () => lifecycleSurvey({ event: "return_from_leave", leaveName: "parental" }));
  const sent = lifecycleSurvey({ event: "return_from_leave", leaveName: null });
  assert.equal(sent.namesLeave, false);
  assert.equal(sent.event, "return_from_leave");
});

test("ENG-009 points stay inside the budget and a cash award uses the route", () => {
  expectCode("POINTS_BUDGET_EXCEEDED", () => givePoints({ amount: 50, budget: null, spent: 0 }));
  const first = givePoints({ amount: 60, budget: 100, spent: 0 });
  assert.equal(first.left, 40);
  expectCode("POINTS_BUDGET_EXCEEDED", () => givePoints({ amount: 50, budget: 100, spent: first.spent }));
  expectCode("SELF_APPROVAL", () =>
    approveCashAward({
      steps: cashRoute,
      approvals: [
        { role: "manager_manager", approverId: "proposer" },
        { role: "hr", approverId: "hr-1" },
      ],
      proposerId: "proposer",
      recipientId: "ana",
    }),
  );
  assert.equal(
    approveCashAward({
      steps: cashRoute,
      approvals: [
        { role: "manager_manager", approverId: "director" },
        { role: "hr", approverId: "hr-1" },
      ],
      proposerId: "proposer",
      recipientId: "ana",
    }).approved,
    true,
  );
});

test("ENG-010 announcements use a known audience and SMS is only for an urgent alert", () => {
  expectCode("AUDIENCE_SCOPE_UNKNOWN", () => announcement({ audience: "teams", channel: "app", urgent: false, smsEnabled: smsOn }));
  expectCode("SMS_URGENT_ONLY", () => announcement({ audience: "organization", channel: "sms", urgent: false, smsEnabled: true }));
  expectCode("FEATURE_OFF", () => announcement({ audience: "organization", channel: "sms", urgent: true, smsEnabled: false }));
  assert.equal(announcement({ audience: "organization", channel: "sms", urgent: true, smsEnabled: true }).channel, "sms");
  assert.equal(readReminders({ publishedOn: "2026-03-01", on: "2026-03-04", days: readDays, read: false }), true);
  assert.equal(readReminders({ publishedOn: "2026-03-01", on: "2026-03-05", days: readDays, read: false }), false);
  assert.equal(readReminders({ publishedOn: "2026-03-01", on: "2026-03-08", days: readDays, read: false }), true);
});

test("ENG-011 one vote and an anonymous message keep no person", () => {
  assert.equal(voteIdea({ alreadyVoted: false }).voted, true);
  expectCode("INPUT_REQUIRED", () => voteIdea({ alreadyVoted: true }));
  expectCode("INPUT_REQUIRED", () => decideIdea({ decision: "declined", reason: "", hr: true }));
  expectCode("INPUT_REQUIRED", () => decideIdea({ decision: "accepted", reason: "useful", hr: false }));
  const message = anonymousMessage({ text: "the desk is short", secretHash: "hash-1" });
  assert.equal(message.personId, null);
  assert.equal(message.timeOfDay, null);
});

test("ENG-012 observances are not paid holidays and directory extras are the employee's", () => {
  assert.equal(observance({ name: "National Indigenous Peoples Day" }).paidHoliday, false);
  assert.equal(wellbeingLink({ name: "employee assistance" }).healthData, null);
  assert.equal(directoryExtra({ addedByEmployee: false, text: "pronouns" }).shown, false);
  assert.equal(directoryExtra({ addedByEmployee: true, text: "pronouns" }).text, "pronouns");
});

test("ENG-020 setup copies the engagement defaults", () => {
  assert.equal(mode, "confidential");
  assert.equal(groupMinimum, 5);
  assert.equal(groupFloor, 3);
  assert.equal(actionDays, 60);
  assert.equal(milestoneDays, 30);
  assert.deepEqual(readDays, [3, 7]);
  assert.equal(smsOn, true);
  assert.equal(giftYear.long_service_limit, 500);
  assert.equal(flagFile.status, "draft");
});

test("ENG-021 a covered employer names the law", () => {
  expectCode("INPUT_REQUIRED", () => surveyMode({ employers: [{ id: "town", covered: true, law: "" }], requested: "anonymous" }));
});

test("ENG-022 a survey waits until coverage is recorded", () => {
  expectCode("INPUT_REQUIRED", () => surveyMode({ employers: [{ id: "society", covered: null, law: null }], requested: "confidential" }));
});

test("ENG-023 a covered employer runs anonymous surveys only", () => {
  const society = { id: "society", covered: false, law: null };
  const town = { id: "town", covered: true, law: "MFIPPA" };
  assert.equal(surveyMode({ employers: [society], requested: "confidential" }), "confidential");
  assert.equal(surveyMode({ employers: [town], requested: "anonymous" }), "anonymous");
  expectCode("SURVEY_MODE_NOT_ALLOWED", () => surveyMode({ employers: [town], requested: "confidential" }));
  expectCode("SURVEY_MODE_NOT_ALLOWED", () => surveyMode({ employers: [society, town], requested: "confidential" }));
});

test("ENG-024 audience, a survey minimum and a lifecycle event", () => {
  expectCode("AUDIENCE_SCOPE_UNKNOWN", () => surveyAudience("teams"));
  expectCode("SURVEY_MIN_GROUP_BELOW_ORGANIZATION", () => surveyMinimum(4, groupMinimum));
  assert.equal(surveyMinimum(groupMinimum, groupMinimum), groupMinimum);
  expectCode("INPUT_REQUIRED", () => lifecycleSurvey({ event: " ", leaveName: null }));
});

test("ENG-025 opening needs dates, a contact for comments, and the consultation caution", () => {
  expectCode("INPUT_REQUIRED", () =>
    openSurvey({ opensOn: null, closesOn: "2026-10-23", openComments: false, contactId: null, unionConsultation: false, cautionAcknowledged: false }),
  );
  expectCode("ESCALATION_CONTACT_REQUIRED", () =>
    openSurvey({ opensOn: "2026-10-01", closesOn: "2026-10-23", openComments: true, contactId: "", unionConsultation: false, cautionAcknowledged: false }),
  );
  expectCode("CAUTION_NOT_ACKNOWLEDGED", () =>
    openSurvey({ opensOn: "2026-10-01", closesOn: "2026-10-23", openComments: false, contactId: null, unionConsultation: true, cautionAcknowledged: false }),
  );
});

test("ENG-026 an open survey is locked", () => {
  expectCode("SURVEY_LOCKED", () => changeOpenSurvey());
});

test("ENG-027 an answer has no person, a known item, and an open survey", () => {
  expectCode("SUBMISSION_ATTRIBUTE_NOT_ALLOWED", () =>
    submitAnswer({ open: true, personId: "ana", itemKnown: true, mode: "confidential", tenure: null, answeredOn: "2026-10-01", timeOfDay: null }),
  );
  expectCode("ANSWER_UNKNOWN_ITEM", () =>
    submitAnswer({ open: true, personId: null, itemKnown: false, mode: "confidential", tenure: null, answeredOn: "2026-10-01", timeOfDay: null }),
  );
  expectCode("SURVEY_NOT_OPEN", () =>
    submitAnswer({ open: false, personId: null, itemKnown: true, mode: "confidential", tenure: null, answeredOn: "2026-10-24", timeOfDay: null }),
  );
  expectCode("SURVEY_LOCKED", () => changeOpenSurvey());
  expectCode("SUBMISSION_ATTRIBUTE_NOT_ALLOWED", () =>
    submitAnswer({ open: true, personId: null, itemKnown: true, mode: "anonymous", tenure: null, answeredOn: "2026-10-01", timeOfDay: "09:00" }),
  );
});

test("ENG-028 an anonymous answer does not keep tenure", () => {
  expectCode("SUBMISSION_ATTRIBUTE_NOT_ALLOWED", () =>
    submitAnswer({ open: true, personId: null, itemKnown: true, mode: "anonymous", tenure: "5-10", answeredOn: "2026-10-01", timeOfDay: null }),
  );
});

test("ENG-029 the draft keyword list flags threatening and not the word threats", () => {
  assert.equal(flagFile.status, "draft");
  const flagged = flagComment({ text: "That message was threatening.", rules: flagFile, contactId: "hr-1" });
  assert.equal(flagged.category, "harassment");
  assert.equal(flagged.personId, null);
  assert.equal(flagComment({ text: "threats were made", rules: flagFile, contactId: "hr-1" }).flagged, false);
  assert.equal(flagComment({ text: "Il y a une menace", rules: flagFile, contactId: "hr-1" }).category, "harassment");
  expectCode("INPUT_REQUIRED", () => handleFlag(" "));
});

test("ENG-030 imported results that name a person or a small group are refused", () => {
  expectCode("INPUT_REQUIRED", () =>
    importResults({ intoCanDoSurvey: false, groups: [{ selfIdentified: false, size: 4 }], namesAPerson: false, unitMinimum: groupMinimum, selfMinimum }),
  );
  expectCode("INPUT_REQUIRED", () =>
    importResults({ intoCanDoSurvey: false, groups: [{ selfIdentified: true, size: 8 }], namesAPerson: false, unitMinimum: groupMinimum, selfMinimum }),
  );
  expectCode("INPUT_REQUIRED", () =>
    importResults({ intoCanDoSurvey: false, groups: [{ selfIdentified: false, size: 12 }], namesAPerson: true, unitMinimum: groupMinimum, selfMinimum }),
  );
  expectCode("INPUT_REQUIRED", () =>
    importResults({ intoCanDoSurvey: true, groups: [{ selfIdentified: false, size: 12 }], namesAPerson: false, unitMinimum: groupMinimum, selfMinimum }),
  );
});

test("ENG-031 six answers show an average and four do not", () => {
  const scores = surveyScores({
    items: [
      { id: "item-1", scores: ["4", "4", "4", "4", "4", "4"] },
      { id: "workload", scores: ["5", "4", "3", "4"] },
    ],
    minimum: groupMinimum,
  });
  assert.equal(scores[0].average, "4.00");
  assert.equal(scores[1].shown, false);
  assert.equal(surveyScores({ items: [{ id: "outreach", scores: ["4", "4", "4"] }], minimum: groupMinimum })[0].shown, false);
  assert.equal(surveyScores({ items: [{ id: "all", scores: ["4", "4", "4", "4", "4", "4", "4", "4", "4"] }], minimum: groupMinimum })[0].shown, true);
});

test("ENG-032 a breakdown under the minimum is hidden", () => {
  const tenure = surveyBreakdown({
    groups: [
      { name: "under-2", size: 5, selfIdentified: false },
      { name: "over-2", size: 4, selfIdentified: false },
    ],
    unitMinimum: groupMinimum,
    selfMinimum,
  });
  assert.equal(tenure[0].shown, true);
  assert.equal(tenure[1].shown, false);
  const identified = surveyBreakdown({
    groups: [{ name: "group", size: 6, selfIdentified: true }],
    unitMinimum: groupMinimum,
    selfMinimum,
  });
  assert.equal(identified[0].shown, false);
});

test("ENG-033 participation under the minimum is hidden", () => {
  assert.equal(participation({ invited: 2, minimum: groupMinimum }).shown, false);
  assert.equal(participation({ invited: groupMinimum, minimum: groupMinimum }).shown, true);
});

test("ENG-034 the action plan is due 22 December and needs two actions", () => {
  const plan = actionPlan({
    closesOn: "2026-10-23",
    days: actionDays,
    actions: ["listen", "publish"],
    on: "2026-12-01",
    language: "en-CA",
  });
  assert.equal(plan.dueOn, "2026-12-22");
  assert.equal(plan.late, false);
  expectCode("INPUT_REQUIRED", () => actionPlan({ closesOn: "2026-10-23", days: actionDays, actions: [], on: "2026-12-23", language: "en-CA" }));
  assert.equal(actionPlan({ closesOn: "2026-10-23", days: actionDays, actions: ["a", "b"], on: "2026-12-23", language: "en-CA" }).late, true);
});

test("ENG-035 recognition uses the organization's values and starts private", () => {
  expectCode("SELF_RECOGNITION", () => giveRecognition({ giverId: "ana", recipientId: "ana", value: "service", values }));
  expectCode("RECIPIENT_CONSENT_REQUIRED", () => requestPublic({ byId: "ben", recipientId: "ana", hasRoute: true }));
  expectCode("LIST_VALUE_UNKNOWN", () => giveRecognition({ giverId: "ben", recipientId: "ana", value: "speed", values }));
});

test("ENG-036 only the recipient asks to make recognition public, and a route is required", () => {
  expectCode("RECIPIENT_CONSENT_REQUIRED", () => requestPublic({ byId: "ben", recipientId: "ana", hasRoute: true }));
  expectCode("INPUT_REQUIRED", () => requestPublic({ byId: "ana", recipientId: "ana", hasRoute: false }));
});

test("ENG-037 HR approves a public recognition and the recipient and sender do not", () => {
  expectCode("ROUTE_APPROVALS_MISSING", () =>
    approvePublic({ steps: publicRoute, approvals: [], recipientId: "ana", giverId: "ben" }),
  );
  expectCode("SELF_APPROVAL", () =>
    approvePublic({ steps: publicRoute, approvals: [{ role: "hr", approverId: "ana" }], recipientId: "ana", giverId: "ben" }),
  );
  expectCode("SELF_APPROVAL", () =>
    approvePublic({ steps: publicRoute, approvals: [{ role: "hr", approverId: "ben" }], recipientId: "ana", giverId: "ben" }),
  );
  assert.equal(
    approvePublic({ steps: publicRoute, approvals: [{ role: "hr", approverId: "hr-1" }], recipientId: "ana", giverId: "ben" }).public,
    true,
  );
});

test("ENG-038 only the recipient attaches recognition to their own review", () => {
  expectCode("RECIPIENT_CONSENT_REQUIRED", () => attachToReview({ byId: "ben", recipientId: "ana", reviewSubjectId: "ana" }));
  expectCode("INPUT_REQUIRED", () => attachToReview({ byId: "ana", recipientId: "ana", reviewSubjectId: "dee" }));
});

test("ENG-039 removing recognition needs a reason", () => {
  expectCode("INPUT_REQUIRED", () => removeRecognition(""));
  assert.equal(removeRecognition("duplicate").removed, true);
});

test("ENG-040 points cannot pass the giver's budget", () => {
  expectCode("POINTS_BUDGET_EXCEEDED", () => givePoints({ amount: 50, budget: null, spent: 0 }));
  const spent = givePoints({ amount: 60, budget: 100, spent: 0 });
  assert.equal(spent.left, 40);
  expectCode("POINTS_BUDGET_EXCEEDED", () => givePoints({ amount: 50, budget: 100, spent: 60 }));
});

test("ENG-041 a missing gift year and a year still to verify are refused", () => {
  expectCode("GIFT_RULE_MISSING", () =>
    giveReward({
      year: null,
      kind: "non_cash",
      occasion: "recognition",
      amount: "50.00",
      serviceYears: 1,
      yearsSinceLongService: null,
      priorNonCash: "0.00",
      priorLongService: "0.00",
      card: null,
    }),
  );
  expectCode("RULE_NOT_VERIFIED", () =>
    giveReward({
      year: { ...giftYear, status: "verify_at_load" },
      kind: "non_cash",
      occasion: "recognition",
      amount: "50.00",
      serviceYears: 1,
      yearsSinceLongService: null,
      priorNonCash: "0.00",
      priorLongService: "0.00",
      card: null,
    }),
  );
});

test("ENG-042 non-cash gifts use the file limit", () => {
  const first = giveReward({
    year: giftYear,
    kind: "non_cash",
    occasion: "special",
    amount: "300.00",
    serviceYears: 2,
    yearsSinceLongService: null,
    priorNonCash: "0.00",
    priorLongService: "0.00",
    card: null,
  });
  assert.equal(first.taxable, "0.00");
  assert.equal(first.payCode, null);
  const second = giveReward({
    year: giftYear,
    kind: "non_cash",
    occasion: "special",
    amount: "300.00",
    serviceYears: 2,
    yearsSinceLongService: null,
    priorNonCash: "300.00",
    priorLongService: "0.00",
    card: null,
  });
  assert.equal(second.taxable, "100.00");
  assert.equal(second.confirm, "to_confirm");
  assert.equal(second.payCode, "AWARD-BENEFIT");
});

test("ENG-043 a gift card needs its terms and a card usable anywhere is taxable in full", () => {
  expectCode("INPUT_REQUIRED", () =>
    giveReward({
      year: giftYear,
      kind: "gift_card",
      occasion: "recognition",
      amount: "100.00",
      serviceYears: 4,
      yearsSinceLongService: null,
      priorNonCash: "0.00",
      priorLongService: "0.00",
      card: null,
    }),
  );
  const afterLimit = giveReward({
    year: giftYear,
    kind: "gift_card",
    occasion: "recognition",
    amount: "100.00",
    serviceYears: 4,
    yearsSinceLongService: null,
    priorNonCash: "500.00",
    priorLongService: "0.00",
    card: qualifyingCard,
  });
  assert.equal(afterLimit.taxable, "100.00");
  assert.equal(afterLimit.bucket, "non_cash");
  const anywhere = giveReward({
    year: giftYear,
    kind: "gift_card",
    occasion: "recognition",
    amount: "80.00",
    serviceYears: 4,
    yearsSinceLongService: null,
    priorNonCash: "0.00",
    priorLongService: "0.00",
    card: { prepaid: true, cannotConvertToCash: true, singleRetailer: false },
  });
  assert.equal(anywhere.taxable, "80.00");
  assert.equal(anywhere.bucket, "taxable");
});

test("ENG-044 a long-service award uses its own limit and a short gap uses the general limit", () => {
  const award = giveReward({
    year: giftYear,
    kind: "non_cash",
    occasion: "long_service",
    amount: "600.00",
    serviceYears: 10,
    yearsSinceLongService: null,
    priorNonCash: "0.00",
    priorLongService: "0.00",
    card: null,
  });
  assert.equal(award.taxable, "100.00");
  assert.equal(award.bucket, "long_service");
  const soon = giveReward({
    year: giftYear,
    kind: "non_cash",
    occasion: "long_service",
    amount: "100.00",
    serviceYears: 12,
    yearsSinceLongService: 2,
    priorNonCash: "500.00",
    priorLongService: "0.00",
    card: null,
  });
  assert.equal(soon.bucket, "non_cash");
  assert.equal(soon.taxable, "100.00");
  const early = giveReward({
    year: giftYear,
    kind: "non_cash",
    occasion: "long_service",
    amount: "100.00",
    serviceYears: 2,
    yearsSinceLongService: null,
    priorNonCash: "0.00",
    priorLongService: "0.00",
    card: null,
  });
  assert.equal(early.bucket, "non_cash");
  assert.equal(early.taxable, "0.00");
});

test("ENG-045 a reward for meeting targets is taxable in full", () => {
  const tablet = giveReward({
    year: giftYear,
    kind: "non_cash",
    occasion: "performance",
    amount: "250.00",
    serviceYears: 8,
    yearsSinceLongService: null,
    priorNonCash: "0.00",
    priorLongService: "0.00",
    card: null,
  });
  assert.equal(tablet.taxable, "250.00");
  assert.equal(tablet.bucket, "taxable");
  assert.equal(tablet.payCode, "AWARD-BENEFIT");
});

test("ENG-046 a cash award is not approved by its proposer or its recipient", () => {
  expectCode("ROUTE_APPROVALS_MISSING", () =>
    approveCashAward({ steps: cashRoute, approvals: [], proposerId: "proposer", recipientId: "ana" }),
  );
  expectCode("SELF_APPROVAL", () =>
    approveCashAward({
      steps: cashRoute,
      approvals: [
        { role: "manager_manager", approverId: "proposer" },
        { role: "hr", approverId: "hr-1" },
      ],
      proposerId: "proposer",
      recipientId: "ana",
    }),
  );
  expectCode("SELF_APPROVAL", () =>
    approveCashAward({
      steps: cashRoute,
      approvals: [
        { role: "manager_manager", approverId: "director" },
        { role: "hr", approverId: "ana" },
      ],
      proposerId: "proposer",
      recipientId: "ana",
    }),
  );
  assert.equal(
    approveCashAward({
      steps: cashRoute,
      approvals: [
        { role: "manager_manager", approverId: "director" },
        { role: "hr", approverId: "hr-1" },
      ],
      proposerId: "proposer",
      recipientId: "ana",
    }).approved,
    true,
  );
});

test("ENG-047 payroll confirms the taxable amount and the proposer does not", () => {
  expectCode("SELF_APPROVAL", () => confirmPayroll({ proposerId: "proposer", confirmerId: "proposer", taxable: "100.00" }));
  const confirmed = confirmPayroll({ proposerId: "proposer", confirmerId: "payroll", taxable: "100.00" });
  assert.equal(confirmed.confirmed, true);
  assert.equal(confirmed.taxable, "100.00");
  const cash = giveReward({
    year: giftYear,
    kind: "cash",
    occasion: "recognition",
    amount: "100.00",
    serviceYears: 6,
    yearsSinceLongService: null,
    priorNonCash: "0.00",
    priorLongService: "0.00",
    card: null,
  });
  assert.equal(cash.taxable, "100.00");
  assert.equal(cash.payCode, "AWARD-CASH");
});

test("ENG-048 a five-year milestone is listed and the manager is reminded 30 days before", () => {
  const due = milestonesDue({ serviceOn: "2021-11-29", years: milestoneYears, from: "2026-11-01", to: "2026-11-30" });
  assert.deepEqual(due, [{ on: "2026-11-29", years: 5 }]);
  assert.equal(milestoneReminder({ on: "2026-11-29", reminderDays: milestoneDays }), "2026-10-30");
});

test("ENG-049 a birthday opt-in needs a day and a real month", () => {
  expectCode("INPUT_REQUIRED", () => celebrationOptIn({ day: null, month: 6 }));
  expectCode("INPUT_REQUIRED", () => celebrationOptIn({ day: 15, month: 13 }));
  assert.deepEqual(celebrationOptIn({ day: 15, month: 6 }), { day: 15, month: 6 });
});

test("ENG-050 SMS is urgent only and a switched-off channel is off", () => {
  expectCode("AUDIENCE_SCOPE_UNKNOWN", () => announcement({ audience: "teams", channel: "email", urgent: false, smsEnabled: true }));
  expectCode("SMS_URGENT_ONLY", () => announcement({ audience: "org_unit", channel: "sms", urgent: false, smsEnabled: true }));
  expectCode("SMS_URGENT_ONLY", () => announcement({ audience: "employer", channel: "sms", urgent: false, smsEnabled: smsOn }));
  expectCode("FEATURE_OFF", () => announcement({ audience: "person_type", channel: "sms", urgent: true, smsEnabled: false }));
});

test("ENG-051 an unread notice is reminded on the organization's days", () => {
  assert.deepEqual(readDays, [3, 7]);
  assert.equal(readReminders({ publishedOn: "2026-03-01", on: "2026-03-04", days: readDays, read: false }), true);
  assert.equal(readReminders({ publishedOn: "2026-03-01", on: "2026-03-05", days: readDays, read: false }), false);
  assert.equal(readReminders({ publishedOn: "2026-03-01", on: "2026-03-08", days: readDays, read: false }), true);
  assert.equal(readReminders({ publishedOn: "2026-03-01", on: "2026-03-04", days: readDays, read: true }), false);
});

test("ENG-052 a second vote and a decision without HR are refused", () => {
  expectCode("INPUT_REQUIRED", () => voteIdea({ alreadyVoted: true }));
  expectCode("INPUT_REQUIRED", () => decideIdea({ decision: "declined", reason: "", hr: true }));
  expectCode("INPUT_REQUIRED", () => decideIdea({ decision: "accepted", reason: "we will try it", hr: false }));
  assert.equal(decideIdea({ decision: "accepted", reason: "we will try it", hr: true }).decision, "accepted");
});

test("ENG-053 an anonymous message stores the secret and not a person or a time", () => {
  const stored = anonymousMessage({ text: "please look at the desk", secretHash: "abc" });
  assert.equal(stored.personId, null);
  assert.equal(stored.timeOfDay, null);
  assert.equal(stored.secretHash, "abc");
});

test("ENG-054 an observance is not a paid holiday", () => {
  assert.equal(observance({ name: "Remembrance Day" }).paidHoliday, false);
  assert.equal(wellbeingLink({ name: "crisis line" }).healthData, null);
  assert.equal(directoryExtra({ addedByEmployee: true, text: "she/her" }).shown, true);
});

test("ENG-055 another organization reads no engagement rows", () => {
  assert.deepEqual(readEngagement("north", "south", [{ id: "survey" }]), []);
});
