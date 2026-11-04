import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { ChunkStore, money } from "@candohr/disbursement";
import {
  acceptOffer,
  acknowledgeCaution,
  addSupporter,
  applyExtension,
  applyWithoutAccount,
  approveCaution,
  approveConversion,
  approveEnding,
  calendarEnd,
  changeApprovedTerms,
  changeExpiry,
  checkInDates,
  closeLapsed,
  declineAgreementConversion,
  decideApplication,
  employmentStandard,
  escalateUndecided,
  escalationLevel,
  evaluateConversion,
  expiryDate,
  financeRequired,
  flagAgreementConversion,
  generateTasks,
  hireChangeSet,
  leaveCaution,
  legalDue,
  mattersForViewer,
  messageBatch,
  openMatters,
  openRequisition,
  outcomeNotice,
  postingIsInternal,
  preboardingAccess,
  rankInternal,
  recordApproval,
  rehireSignal,
  remindersDue,
  renderOfferLetter,
  requestConversion,
  retentionUntil,
  routeComplete,
  routeFor,
  routeForOffer,
  scoresVisibleTo,
  section87,
  sendOffer,
  signContract,
  startCheck,
  storeCandidateDocument,
  storeMatchScore,
  submitScore,
  suggestSupporters,
  unionNoticeReminder,
  validatePosting,
  visibleToReviewer,
  waiveLegalTask,
  type PlanItem,
  type StandardsBundle,
  type WorkflowRoute,
  RecruitError,
} from "../src/index.ts";

const root = new URL("../../../", import.meta.url);
const bundle: StandardsBundle = {
  edition: JSON.parse(readFileSync(new URL("rules/employment-standards/ca-2026.json", root), "utf8")),
  recruitment: JSON.parse(readFileSync(new URL("rules/employment-standards/ca-2026-recruitment-additions.json", root), "utf8")),
  separation: JSON.parse(readFileSync(new URL("rules/employment-standards/ca-2026-separation-additions.json", root), "utf8")),
};

function code(fn: () => void): string {
  try {
    fn();
  } catch (error) {
    if (error instanceof RecruitError) return error.code;
    throw error;
  }
  return "";
}

const position = {
  id: "pos-1",
  status: "vacant" as const,
  title: "Clerk",
  unitId: "unit-1",
  locationId: "loc-1",
  agreementId: "agr-1",
  gradeMin: "25.00",
  gradeMax: "32.00",
  fte: "1.00",
  jurisdiction: "ON",
};

test("REC-001 REC-018 a requisition prefills the vacant position and funding must add to 100", () => {
  const opened = openRequisition({
    position,
    typeCode: "replace",
    typeCategory: "replacement",
    employmentType: "regular",
    funding: [
      { costCentreId: "cc-1", fundingSourceId: "fs-1", share: "60.00" },
      { costCentreId: "cc-2", fundingSourceId: "fs-2", share: "30.00" },
      { costCentreId: "cc-3", fundingSourceId: "fs-3", share: "10.00" },
    ],
    postingRequiredByAgreement: false,
    knownExemptions: ["casual"],
    commitment: "1000.00",
    remainingBudget: "5000.00",
  });
  assert.equal(opened.prefilled.title, "Clerk");
  assert.equal(opened.prefilled.unitId, "unit-1");
  assert.equal(opened.prefilled.gradeMin, "25.00");
  assert.equal(code(() => openRequisition({ ...openedInput(), funding: [
    { costCentreId: "cc-1", fundingSourceId: "fs-1", share: "60.00" },
    { costCentreId: "cc-2", fundingSourceId: "fs-2", share: "30.00" },
  ] })), "REQUISITION_FUNDING_NOT_100");
  assert.equal(code(() => openRequisition({ ...openedInput(), position: { ...position, status: "frozen" } })), "POSITION_FROZEN");
  const created = openRequisition({ ...openedInput(), typeCategory: "new_position", position: { ...position, status: "filled" } });
  assert.deepEqual(created.changeSet.operations.map((operation) => operation.type), ["position.create", "requisition.open"]);
  assert.equal(code(() => openRequisition({ ...openedInput(), exemptionCode: "unknown" })), "POSTING_EXEMPTION_UNKNOWN");
});

function openedInput() {
  return {
    position,
    typeCode: "replace",
    typeCategory: "replacement" as const,
    employmentType: "regular",
    funding: [
      { costCentreId: "cc-1", fundingSourceId: "fs-1", share: "60.00" },
      { costCentreId: "cc-2", fundingSourceId: "fs-2", share: "40.00" },
    ],
    postingRequiredByAgreement: false,
    knownExemptions: ["casual"],
    commitment: "1000.00",
    remainingBudget: "5000.00",
  };
}

test("REC-002 REC-016 REC-017 routes are the organization's, with no default and no self-approval", () => {
  const routes: WorkflowRoute[] = [
    { id: "high", kind: "requisition", priority: 1, conditions: { overBudget: true }, steps: [{ capability: "finance", mode: "all", approvers: ["fin"], escalateTo: "hr" }] },
    { id: "low", kind: "requisition", priority: 2, conditions: {}, steps: [{ capability: "hr", mode: "any", approvers: ["hr-a", "hr-b"], escalateTo: "exec" }] },
  ];
  assert.equal(routeFor(routes, "requisition", { overBudget: false }).id, "low");
  assert.equal(routeFor(routes, "requisition", { overBudget: true }).id, "high");
  assert.equal(code(() => routeFor(routes, "requisition", {})), "ROUTE_FACT_MISSING");
  assert.equal(code(() => routeFor(routes, "offer", {})), "ROUTE_NOT_FOUND");
  const route = routes[1];
  assert.equal(code(() => recordApproval(route, [], "hr-a", "hr-a", 0)), "SELF_APPROVAL");
  const approvals = recordApproval(route, [], "manager", "hr-a", 0);
  assert.equal(routeComplete(route, approvals), true);
  assert.deepEqual(escalateUndecided(route.steps[0], false, "2026-02-02", "2026-02-01"), { escalated: true, to: "exec" });
  const caution = { code: "endings.open_cases", textShown: "HR review", needsReason: true, needsApproval: true };
  const ack = acknowledgeCaution(caution, [], { subjectType: "change_set", subjectId: "cs-1", reason: "reviewed", acknowledgedBy: "hr-a" });
  assert.equal(ack.textShown, "HR review");
  assert.equal(code(() => acknowledgeCaution(caution, [ack], { subjectType: "change_set", subjectId: "cs-1", reason: "again", acknowledgedBy: "hr-b" })), "CAUTION_ACK_IMMUTABLE");
  assert.equal(code(() => approveCaution(ack, "hr-a")), "SELF_APPROVAL");
  assert.equal(approveCaution(ack, "hr-b").approvedBy, "hr-b");
});

test("REC-015 a caution that needs a reason is refused without one", () => {
  const caution = { code: "recruit.posting_required", textShown: "The agreement requires a posting", needsReason: true, needsApproval: false };
  assert.equal(code(() => acknowledgeCaution(caution, [], { subjectType: "requisition", subjectId: "rq-1", reason: "  ", acknowledgedBy: "hr" })), "CAUTION_REASON_REQUIRED");
  const ack = acknowledgeCaution(caution, [], { subjectType: "requisition", subjectId: "rq-1", reason: "named recall", acknowledgedBy: "hr" });
  assert.equal(ack.textShown, caution.textShown);
});

test("REC-019 a named hire without a required posting waits for the caution", () => {
  const caution = { code: "recruit.posting_required", textShown: "Posting required", needsReason: true, needsApproval: false };
  const base = { ...openedInput(), namedCandidateId: "cand-1", postingRequiredByAgreement: true, caution };
  assert.equal(code(() => openRequisition(base)), "CAUTION_NOT_ACKNOWLEDGED");
  const acknowledgement = acknowledgeCaution(caution, [], { subjectType: "requisition", subjectId: "rq-1", reason: "recall list exhausted", acknowledgedBy: "hr" });
  assert.equal(openRequisition({ ...base, acknowledgement }).prefilled.title, "Clerk");
});

test("REC-003 REC-005 REC-020 REC-021 postings follow the pay-transparency rule for the location", () => {
  const on = employmentStandard(bundle, "ON", "pay_transparency");
  const width = String(on.max_range_width);
  const base = {
    publicPosting: true,
    employerHeadcount: Number(on.applies_to_employers_with),
    jurisdiction: "ON",
    payMin: "40000.00",
    payMax: money(String(Number(width) + 40000)),
    payShown: true,
    payBasis: "range" as const,
    incumbentCount: 4,
    incumbentAverageMin: 3,
    incumbentAverageFloor: 3,
    vacancyExists: true,
    requiresCanadianExperience: false,
    aiScreeningOn: true,
    questions: [{ code: "availability" }],
    frenchRequired: false,
    requisitionApproved: true,
    openedOn: "2026-01-01",
    asOf: "2026-01-01",
    seniorityOrder: "on" as const,
    missingRequirement: "flag" as const,
  };
  const tooWide = { ...base, payMax: money(String(Number(width) + 40000 + 1)) };
  assert.equal(code(() => validatePosting(bundle, { ...tooWide, payMax: "90001.00" })), "PAY_RANGE_TOO_WIDE");
  assert.equal(code(() => validatePosting(bundle, { ...base, payShown: false })), "PAY_NOT_SHOWN");
  assert.equal(code(() => validatePosting(bundle, { ...base, vacancyExists: null })), "VACANCY_NOT_STATED");
  assert.equal(code(() => validatePosting(bundle, { ...base, requiresCanadianExperience: true })), "CANADIAN_EXPERIENCE_NOT_ALLOWED");
  assert.equal(validatePosting(bundle, base).aiUseStatement, "ai_use_disclosed");
  assert.equal(code(() => validatePosting(bundle, { ...base, missingRequirement: undefined })), "SETTING_NOT_SET");
  assert.equal(code(() => validatePosting(bundle, { ...base, payBasis: "incumbents_average", incumbentCount: 2 })), "INCUMBENT_AVERAGE_UNAVAILABLE");
  assert.equal(code(() => validatePosting(bundle, { ...base, jurisdiction: "BC" })), "RULE_NOT_VERIFIED");
  assert.equal(code(() => validatePosting(bundle, { ...base, jurisdiction: "PE" })), "RULE_NOT_VERIFIED");
  const verifiedBc = structuredCopy(bundle, "BC");
  const removed = validatePosting(verifiedBc, { ...base, jurisdiction: "BC", questions: [{ code: "pay_history" }, { code: "availability" }], payMin: "20.00", payMax: "25.00" });
  assert.deepEqual(removed.questions.map((question) => question.code), ["availability"]);
  assert.equal(code(() => validatePosting(verifiedBc, { ...base, jurisdiction: "BC", payShown: false })), "PAY_NOT_SHOWN");
  const notice = outcomeNotice(bundle, "ON", "2026-01-01", "2026-02-15", 0);
  assert.equal(notice.dueOn, "2026-02-15");
  assert.equal(notice.atRisk, true);
  assert.equal(code(() => validatePosting(bundle, { ...base, frenchRequired: true })), "FRENCH_REQUIRED_FOR_QUEBEC");
});

function structuredCopy(source: StandardsBundle, jurisdiction: string): StandardsBundle {
  const edition = structuredClone(source.edition);
  const row = edition.jurisdictions?.[jurisdiction]?.pay_transparency;
  if (row) row.status = "secondary";
  return { ...source, edition };
}

test("REC-004 internal applicants follow the agreement's seniority rule", () => {
  assert.equal(postingIsInternal("2026-01-01", 5, "2026-01-04"), true);
  assert.equal(postingIsInternal("2026-01-01", 5, "2026-01-06"), false);
  const ranked = rankInternal("relatively_equal_then_seniority", [
    { id: "b", name: "Bea", seniorityDate: "2020-01-01", score: "8.00", internal: true },
    { id: "a", name: "Ada", seniorityDate: "2018-01-01", score: "8.00", internal: true },
  ], true);
  assert.deepEqual(ranked.map((row) => row.id), ["a", "b"]);
  assert.equal(ranked[0].reason, "assessment_score");
  assert.equal(ranked[1].reason, "relatively_equal_then_seniority");
  const caution = { code: "recruit.seniority_order", textShown: "Seniority order is off", needsReason: true, needsApproval: false };
  assert.equal(code(() => validatePosting(bundle, {
    publicPosting: false,
    employerHeadcount: 10,
    jurisdiction: "ON",
    payShown: true,
    payMin: "20.00",
    payMax: "25.00",
    payBasis: "range",
    incumbentCount: 0,
    incumbentAverageMin: 3,
    incumbentAverageFloor: 3,
    vacancyExists: true,
    requiresCanadianExperience: false,
    aiScreeningOn: false,
    questions: [],
    frenchRequired: false,
    requisitionApproved: true,
    openedOn: "2026-01-01",
    asOf: "2026-01-01",
    seniorityOrder: "off",
    seniorityOverride: { cautionCode: caution.code, subjectType: "posting", subjectId: "p", textShown: caution.textShown, reason: "", acknowledgedBy: "hr" },
    seniorityCaution: caution,
    missingRequirement: "flag",
  })), "CAUTION_NOT_ACKNOWLEDGED");
  assert.equal(unionNoticeReminder(true, false).remind, true);
});

test("REC-006 REC-014 REC-022 scores lock, and AI stays off until the organization switches it on", () => {
  assert.equal(code(() => storeMatchScore(false, "70.00", ["skill"])), "MATCH_SUGGESTIONS_OFF");
  storeMatchScore(true, "70.00", ["skill"]);
  assert.equal(code(() => storeMatchScore(true, "70.00", [])), "MATCH_WITHOUT_REASONS");
  assert.equal(visibleToReviewer({ id: "a", name: "Ada", photoRef: "photo", seniorityDate: "2020-01-01", score: "1.00", internal: false }, true).name, undefined);
  assert.equal(code(() => decideApplication({ outcome: "screened_out", decidedByKind: "requirement_rule", decidedOn: "2026-01-02", missingRequirements: ["licence"], missingRequirement: "flag" })), "REQUIREMENT_RULE_NOT_ALLOWED");
  decideApplication({ outcome: "screened_out", decidedByKind: "requirement_rule", decidedOn: "2026-01-02", missingRequirements: ["licence"], missingRequirement: "screen_out" });
  assert.equal(code(() => decideApplication({ outcome: "rejected", decidedByKind: "person", decidedOn: "2026-01-02", missingRequirements: [], missingRequirement: "flag" })), "APPLICATION_DECISION_UNSIGNED");
  const locked = submitScore([], "p1", "4");
  assert.equal(code(() => submitScore(locked, "p1", "5")), "SCORE_LOCKED");
  assert.equal(scoresVisibleTo(locked, "p2").length, 0);
  const both = submitScore(locked, "p2", "3");
  assert.equal(scoresVisibleTo(both, "p2").length, 2);
});

test("REC-007 REC-008 REC-024 REC-025 REC-026 REC-027 an offer becomes a hire only after the contract is signed", () => {
  const inside: WorkflowRoute = { id: "in", kind: "offer", priority: 1, conditions: {}, steps: [] };
  const outside: WorkflowRoute = { id: "out", kind: "offer", priority: 1, conditions: {}, steps: [{ capability: "finance", mode: "all", approvers: ["fin"] }] };
  assert.equal(routeForOffer({ pay: "40.00", rangeMin: "25.00", rangeMax: "32.00" }, inside, outside).id, "out");
  const letter = renderOfferLetter({ "en-CA": "Offer", "fr-CA": "Offre" }, ["en-CA", "fr-CA"]);
  assert.equal(letter["fr-CA"], "Offre");
  const approved = { id: "off-1", pay: "30.00", rangeMin: "25.00", rangeMax: "32.00", status: "approved" as const, approvals: [{ approverId: "hr" }], accepted: false, contractSigned: false, internal: true, tellSupervisor: false, conditions: [] };
  const revised = changeApprovedTerms(approved, "31.00", true);
  assert.equal(revised.status, "draft");
  assert.equal(revised.approvals.length, 0);
  assert.equal(code(() => startCheck(approved, "criminal_record", true)), "CHECK_BEFORE_CONDITIONAL_OFFER");
  const sent = sendOffer({ ...approved, status: "approved" });
  assert.equal(code(() => startCheck({ ...sent, status: "sent" }, "criminal_record", false)), "CONSENT_REQUIRED");
  assert.equal(code(() => hireChangeSet(sent, { candidateFields: { legalName: "Ada" }, positionId: "pos-1", rate: "30.00", startDate: "2026-03-01", payGroupId: "pg" })), "HIRE_BEFORE_CONTRACT_SIGNED");
  const accepted = acceptOffer({ ...sent, status: "sent" });
  assert.equal(accepted.tellSupervisor, true);
  assert.equal(code(() => signContract({ ...accepted, accepted: false })), "CONTRACT_BEFORE_ACCEPTANCE");
  const signed = signContract(accepted);
  assert.equal(code(() => hireChangeSet(signed, { candidateFields: { legalName: "Ada" }, positionId: "pos-1", rate: "30.00", startDate: "2026-03-01", payGroupId: "pg" })), "INPUT_REQUIRED");
  const hired = hireChangeSet(signed, { personId: "person-1", movement: "transfer", candidateFields: { legalName: "Ada" }, positionId: "pos-1", rate: "30.00", startDate: "2026-03-01", payGroupId: "pg" });
  assert.equal(hired.operations[0].type, "assignment.add");
  assert.equal(hired.mapped.legalName, "Ada");
  assert.equal(hired.events[1].type, "employment.hired");
  const expiry = expiryDate("2026-01-02", 5, (iso) => {
    const day = new Date(`${iso}T00:00:00Z`).getUTCDay();
    return day !== 0 && day !== 6;
  });
  assert.equal(expiry, "2026-01-09");
  assert.equal(code(() => changeExpiry("employee", ["hr", "hiring_manager"])), "SETTING_VALUE_NOT_ALLOWED");
  assert.deepEqual(rehireSignal({ signal: "eligible", reason: "private", note: "private" }), { signal: "eligible" });
  assert.equal(code(() => messageBatch(" ")), "MESSAGE_REASON_REQUIRED");
});

test("REC-009 REC-010 REC-028 REC-029 REC-030 REC-031 onboarding tasks, supporters, and escalation", () => {
  const sql = readFileSync(new URL("schema/0009_recruitment_onboarding.sql", root), "utf8");
  const items = starterItems(sql);
  const tasks = generateTasks(items, { welcomeVideos: { enabled: false, required: false }, buddyProgram: { enabled: false, required: false }, checkInSurveys: { enabled: false, required: false } }, "2026-11-02");
  assert.equal(tasks.length, 22);
  assert.equal(tasks.some((task) => task.itemCode === "welcome_videos"), false);
  const sin = legalDue(bundle, "2026-11-02", "2026-11-02");
  assert.equal(sin.organizationDue, "2026-11-02");
  assert.equal(sin.legalDue, "2026-11-05");
  assert.equal(code(() => waiveLegalTask()), "LEGAL_TASK_CANNOT_BE_WAIVED");
  assert.deepEqual(preboardingAccess("2026-10-01", "2026-11-02").scopes, ["preboarding"]);
  const exemption = section87(true, "2026-11-15", false);
  assert.equal(exemption.hrTaskDue, "2026-11-14");
  assert.equal(exemption.deductionsContinue, true);
  assert.equal(section87(true, "2026-11-15", true).deductionsContinue, false);
  const setting = { ownerReminderDaysBefore: 2, managerAfterDaysOverdue: 1, hrAfterDaysOverdue: 3 };
  assert.equal(escalationLevel("2026-11-02", "2026-11-04", setting, 0)?.notify, "owner_manager");
  assert.equal(escalationLevel("2026-11-01", "2026-11-04", setting, 0)?.notify, "hr");
  const hire = "person-new";
  assert.equal(addSupporter({ role: "mentor", supporterId: "m", hireId: hire, scopeNote: "caseload", from: "2026-11-02", to: "2027-02-02", buddyEnabled: false }).role, "mentor");
  assert.equal(addSupporter({ role: "trainer", supporterId: "t", hireId: hire, scopeNote: "desk", from: "2026-11-02", to: "2026-12-02", buddyEnabled: false }).role, "trainer");
  assert.equal(code(() => addSupporter({ role: "buddy", supporterId: "b", hireId: hire, scopeNote: "floor", from: "2026-11-02", to: "2026-12-02", buddyEnabled: false })), "FEATURE_OFF");
  const buddy = addSupporter({ role: "buddy", supporterId: "b", hireId: hire, scopeNote: "floor", from: "2026-11-02", to: "2026-12-02", buddyEnabled: true });
  assert.equal(buddy.scopeNote, "floor");
  assert.equal(suggestSupporters([{ personId: hire, unitId: "u", locationId: "l" }, { personId: "near", unitId: "u", locationId: "l" }, { personId: "far", unitId: "other", locationId: "l" }], { personId: hire, unitId: "u", locationId: "l" })[0].reason, "same_org_unit");
});

function starterItems(sql: string): PlanItem[] {
  const items: PlanItem[] = [];
  for (const line of sql.split("\n")) {
    const match = line.match(/\('core_new_hire',\s*'([^']+)',\s*\d+,\s*'([^']+)',\s*'[^']+',\s*(NULL|'[^']*'),\s*'([^']+)',\s*'([^']+)',\s*(-?\d+),\s*(?:NULL|'[^']*'),\s*(true|false),\s*(NULL|'[^']*')/);
    if (!match) continue;
    items.push({
      itemCode: match[1],
      phase: match[2],
      formCode: match[3] === "NULL" ? null : match[3].replaceAll("'", ""),
      ownerKind: match[4],
      dueEvent: match[5],
      dueOffsetDays: Number(match[6]),
      required: match[7] === "true",
      extra: match[8] === "NULL" ? null : match[8].replaceAll("'", ""),
    });
  }
  return items;
}

test("REC-011 REC-032 REC-033 REC-034 REC-035 REC-036 probation ends, extends, and passes when nobody decides", () => {
  const probation = { id: "pr-1", measure: "calendar_months" as const, requiredAmount: 3, extendedBy: 0, startedOn: "2026-01-05", status: "in_progress" as const, kind: "employer" };
  assert.equal(calendarEnd(probation), "2026-04-04");
  const dates = checkInDates(probation, [{ from: "start", days: 30 }, { from: "start", days: 60 }, { from: "end", days: 14 }]);
  assert.deepEqual(dates.map((row) => row.dueOn), ["2026-02-04", "2026-03-06", "2026-03-21"]);
  assert.equal(remindersDue("2026-04-04", "2026-03-30", [30, 15, 10, 5, 3, 2, 1])?.daysLeft, 5);
  const caution = leaveCaution({
    endsOn: "2026-04-04",
    reminderDays: [30, 15, 10, 5, 3, 2, 1],
    leaveFrom: "2026-03-30",
    leaveTo: "2026-04-02",
    holidays: [{ date: "2026-04-03", name: "Good Friday", statutory: true }],
    holidayCalendarPresent: true,
  });
  assert.equal(caution?.endsOn, "2026-04-04");
  assert.equal(caution?.holidays[0].name, "Good Friday");
  assert.equal(code(() => applyExtension(bundle, probation, { amount: 1, reason: "training", notifiedOn: "2026-04-05", approved: true }, "ON")), "EXTENSION_AFTER_END");
  assert.equal(code(() => applyExtension(bundle, probation, { amount: 1, reason: "training", notifiedOn: "2026-03-01", approved: true }, "ON")), "RULE_NOT_VERIFIED");
  const verified = structuredClone(bundle);
  const notice = verified.edition.jurisdictions?.ON?.termination_notice;
  if (notice) notice.status = "secondary";
  const past = { code: "probation.extension_past_notice_threshold", textShown: "Notice rights are not delayed", needsReason: true, needsApproval: false };
  assert.equal(code(() => applyExtension(verified, probation, { amount: 1, reason: "training", notifiedOn: "2026-03-01", approved: true, cautionDef: past }, "ON")), "CAUTION_NOT_ACKNOWLEDGED");
  const acknowledged = acknowledgeCaution(past, [], { subjectType: "probation_extension", subjectId: "ex-1", reason: "employee already has notice rights", acknowledgedBy: "manager" });
  const extended = applyExtension(verified, probation, { amount: 1, reason: "training", notifiedOn: "2026-03-01", approved: true, cautionDef: past, caution: acknowledged }, "ON");
  assert.equal(extended.status, "extended");
  assert.equal(calendarEnd(extended), "2026-05-04");
  assert.equal(code(() => applyExtension(verified, { ...probation, extendedBy: 1 }, { amount: 1, reason: "again", notifiedOn: "2026-03-01", approved: true, organizationMaximum: { amount: 1, measure: "calendar_months" }, cautionDef: past, caution: acknowledged }, "ON")), "EXTENSION_ABOVE_MAXIMUM");
  const lapsed = closeLapsed(probation, "2026-04-05");
  assert.equal(lapsed?.status, "passed");
  assert.equal(lapsed?.endedOn, "2026-04-04");
  assert.equal(lapsed?.fallback, "FB-034");
  assert.equal(lapsed?.hrTold, true);
});

test("REC-012 REC-038 a conversion the agreement requires is not declined in silence", () => {
  assert.equal(code(() => evaluateConversion([], [], "2026-01-01", "temporary", "2024-01-01")), "CONVERSION_THRESHOLDS_OFF");
  const route: WorkflowRoute = { id: "conv", kind: "conversion", priority: 1, conditions: {}, steps: [{ capability: "hr", mode: "all", approvers: ["hr"] }] };
  assert.equal(requestConversion("manager_request", route, "manager").routeId, "conv");
  const flagged = flagAgreementConversion("article 12");
  assert.equal(flagged.event, "status_conversion.flagged");
  const caution = { code: "conversion.agreement_requires", textShown: "The agreement requires this conversion", needsReason: true, needsApproval: false };
  assert.equal(code(() => declineAgreementConversion(caution, undefined)), "CAUTION_NOT_ACKNOWLEDGED");
  const acknowledgement = acknowledgeCaution(caution, [], { subjectType: "conversion", subjectId: "cv-1", reason: "the employee asked to stay temporary", acknowledgedBy: "hr" });
  declineAgreementConversion(caution, acknowledgement);
});

test("REC-013 REC-023 retention is never shorter than the law that applies", () => {
  const ontario = retentionUntil(bundle, { jurisdiction: "ON", decidedOn: "2026-01-15", postingClosedOn: "2026-01-01", organizationMonths: 6 });
  assert.equal(ontario, "2029-01-01");
  const britishColumbia = retentionUntil(bundle, { jurisdiction: "BC", decidedOn: "2026-01-15", postingClosedOn: "2026-01-01", organizationMonths: 6 });
  assert.equal(britishColumbia, "2027-01-15");
  assert.equal(code(() => retentionUntil(bundle, { jurisdiction: "AB", decidedOn: "2026-01-15", organizationMonths: 6 })), "RULE_NOT_VERIFIED");
});

test("REC-037 REC-039 an ending waits while a case or a recent grievance is open", () => {
  const grievance = { id: "case-1", category: "grievance", openedOn: "2025-01-01", closedOn: "2026-03-01", roles: ["subject"], respondentPersonId: "manager" };
  assert.equal(openMatters({ cases: [grievance], leaves: [], asOf: "2026-06-01", lookbackMonths: 12 }).length, 1);
  assert.equal(openMatters({ cases: [grievance], leaves: [], asOf: "2026-06-01", lookbackMonths: 2 }).length, 0);
  const open = openMatters({ cases: [{ ...grievance, closedOn: undefined }], leaves: [], asOf: "2026-06-01", lookbackMonths: 12 });
  assert.equal(code(() => approveEnding(open, false)), "OPEN_CASES_NOT_REVIEWED");
  approveEnding(open, true);
  assert.deepEqual(mattersForViewer(open, "manager", false), { message: "HR review required" });
  const forHr = mattersForViewer(open, "hr", true);
  assert.equal("detail" in forHr ? forHr.detail.length : 0, 1);
});

test("ENT-021 a temporary employee who meets the agreement's window is proposed for conversion", () => {
  const rule = {
    id: "local-rule",
    fromTypes: ["temporary"],
    toType: "permanent",
    windowMonths: 24,
    measuredOverWeeks: 6,
    averageHoursMin: "20.00",
    sameGrouping: true,
    countsLeaves: ["parental", "medical"],
    createsPosition: true,
    precedence: 1,
  };
  const weeks = Array.from({ length: 104 }, (_, index) => {
    const weekStart = shift(index);
    const parental = index === 40;
    return { weekStart, groupingId: "parks", scheduledHours: parental ? "8.00" : "20.00", leaveHours: parental ? "12.00" : "0.00", leaveKind: parental ? "parental" : null };
  });
  const proposed = evaluateConversion([rule], weeks, "2026-01-06", "temporary", "2024-01-06");
  assert.equal(proposed.proposed, true);
  assert.equal(proposed.leaveCounted, true);
  assert.equal(proposed.createsPosition, true);
  const approved = approveConversion(proposed, "pos-new");
  assert.equal(approved.changeSet.operations[0].type, "position.create");
  const short = evaluateConversion([rule], weeks.map((week, index) => index === 10 ? { ...week, scheduledHours: "0.00", leaveHours: "0.00", leaveKind: null } : week), "2026-01-06", "temporary", "2024-01-06");
  assert.equal(short.proposed, false);
  assert.equal(code(() => evaluateConversion([{ ...rule, precedence: undefined }, { ...rule, id: "other", precedence: undefined }], weeks, "2026-01-06", "temporary", "2024-01-06")), "UNRESOLVED_INTERACTION");
});

function shift(weeks: number): string {
  const date = new Date(Date.UTC(2024, 0, 1));
  date.setUTCDate(date.getUTCDate() + weeks * 7);
  return date.toISOString().slice(0, 10);
}

test("REC-010 candidate documents are stored in pieces, and an over-budget requisition needs finance", () => {
  const store = new ChunkStore();
  const body = new TextEncoder().encode("candidate-file");
  const stored = storeCandidateDocument(store, "doc-1", body, 4);
  assert.equal(stored.bytes, body.length);
  assert.ok(stored.parts > 1);
  const route: WorkflowRoute = { id: "plain", kind: "requisition", priority: 1, conditions: {}, steps: [{ capability: "hr", mode: "any", approvers: ["hr"] }] };
  assert.equal(code(() => financeRequired(true, route)), "ROUTE_NOT_FOUND");
  const withFinance: WorkflowRoute = { ...route, steps: [...route.steps, { capability: "finance", mode: "all", approvers: ["fin"] }] };
  financeRequired(true, withFinance);
  const over = openRequisition({ ...openedInput(), commitment: "6000.00", remainingBudget: "5000.00" });
  assert.equal(over.overBudget, true);
});

test("applying without an account needs a way to reply", () => {
  assert.equal(applyWithoutAccount({ email: "ada@example.test" }).account, false);
  assert.equal(code(() => applyWithoutAccount({})), "CANDIDATE_CONTACT_REQUIRED");
});
