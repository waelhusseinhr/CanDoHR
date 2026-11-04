import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  aboveMaximum,
  acknowledgementTasks,
  actingPay,
  advisorView,
  ageOutNotice,
  approveInvoice,
  approvePhilosophy,
  approvePayout,
  approveRate,
  approveStructure,
  bargainScenario,
  carrierEnrolmentFile,
  catchUpPlan,
  changesSince,
  clawback,
  cobOrder,
  combinedFte,
  commissionPayout,
  demotionPay,
  draftDisclosure,
  electionCosts,
  employeePayPage,
  enrolmentAssistant,
  enrolmentComparison,
  enrolmentTask,
  evidenceOfInsurability,
  governingAgreement,
  gradeSpread,
  hireInCycle,
  leaveContribution,
  lifeEventWindow,
  locationRanges,
  managerPayView,
  mandatoryPension,
  manualGridRate,
  meritRecommendation,
  meritWorksheet,
  openCycle,
  openEnrolment,
  optOut,
  payEquityFlags,
  payGap,
  pensionRemittance,
  pensionSplit,
  positionGrade,
  postingRange,
  premiumAdjustment,
  premiumArrears,
  prepareSurveyImport,
  progressionDraft,
  promotionRate,
  proposeCareerTargets,
  prorateIncentive,
  publishStarter,
  rangeVersion,
  recordGrant,
  releaseLetters,
  requireLateEnrolment,
  RewardsError,
  spendingImport,
  totalRewardsStatement,
  trustOrder,
  validateWaiting,
  variableHoursProposal,
  type Architecture,
  type CompetencyModel,
} from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");

function load(path: string): unknown {
  return JSON.parse(readFileSync(join(root, path), "utf8"));
}

function code(run: () => void): string {
  try {
    run();
  } catch (error) {
    if (error instanceof RewardsError) return error.code;
    throw error;
  }
  return "";
}

const route = [
  { role: "manager", approverId: "mgr", approved: true },
  { role: "hr", approverId: "hr", approved: true },
  { role: "finance", approverId: "fin", approved: true },
];

test("COMP-001 range order and compa-ratio as of a date", () => {
  const read = rangeVersion({
    asOf: "2026-06-01",
    rate: "50000.00",
    versions: [
      { effective: "2026-01-01", minimum: "45000.00", midpoint: "50000.00", maximum: "55000.00" },
      { effective: "2027-01-01", minimum: "54000.00", midpoint: "60000.00", maximum: "66000.00" },
    ],
  });
  assert.equal(read.midpoint, "50000.00");
  assert.equal(read.compaRatio, "1.000");
  assert.equal(code(() => rangeVersion({
    asOf: "2026-06-01",
    rate: "1.00",
    versions: [{ effective: "2026-01-01", minimum: "10.00", midpoint: "5.00", maximum: "12.00" }],
  })), "RANGE_ORDER");
});

test("COMP-002 union grid blocks a manual rate unless the agreement allows it", () => {
  assert.equal(manualGridRate({ gridRate: "30.00", proposed: "30.00", agreementAllowsManual: false }).source, "grid");
  assert.equal(code(() => manualGridRate({ gridRate: "30.00", proposed: "32.00", agreementAllowsManual: false })), "MANUAL_RATE_BLOCKED");
  assert.equal(code(() => manualGridRate({ gridRate: "30.00", proposed: "32.00", agreementAllowsManual: true })), "INPUT_REQUIRED");
  assert.equal(manualGridRate({ gridRate: "30.00", proposed: "32.00", agreementAllowsManual: true, reason: "red circle" }).source, "manual");
});

test("COMP-003 progression drafts a rate when the agreement hours are reached", () => {
  const step = "1820";
  assert.equal(progressionDraft({ hoursPaid: "1819", hoursStep: step, nextRate: "32.00", nextPeriodStart: "2027-01-04" }).changeSet, null);
  const draft = progressionDraft({ hoursPaid: step, hoursStep: step, nextRate: "32.00", nextPeriodStart: "2027-01-04" }).changeSet;
  assert.equal(draft?.kind, "compensation.set_rate");
  assert.equal(draft?.status, "draft");
  assert.equal(draft?.effective, "2027-01-04");
  assert.equal(draft?.confirm, "hr");
});

test("COMP-004 COMP-021 merit cycle states eligibility, guideline and letters", () => {
  const cycle = openCycle({
    year: "2027",
    eligibility: "exclude_recent_hires",
    guidelineMethod: "matrix",
    letterRelease: "after_hr_review",
    excludeHiredWithinMonths: "3",
  });
  assert.equal(cycle.guidelineMethod, "matrix");
  assert.equal(hireInCycle({ hiredOn: "2026-11-01", cycleStart: "2027-01-01", excludeHiredWithinMonths: cycle.excludeHiredWithinMonths }).eligible, false);
  assert.equal(hireInCycle({ hiredOn: "2026-09-01", cycleStart: "2027-01-01", excludeHiredWithinMonths: cycle.excludeHiredWithinMonths }).eligible, true);
  const sheet = meritWorksheet({
    rate: "60000.00",
    range: { minimum: "50000.00", midpoint: "60000.00", maximum: "70000.00" },
    rating: "3",
    guidelinePct: "3",
    spent: "1000.00",
    budget: "5000.00",
  });
  assert.equal(sheet.compaRatio, "1.000");
  assert.equal(sheet.remaining, "4000.00");
});

test("COMP-022 COMP-023 guideline exception and letter release", () => {
  assert.equal(code(() => meritRecommendation({ guidelinePct: "3", proposedPct: "6", policy: "blocked", hrApproved: true, reason: "keep" })), "OUT_OF_GUIDELINE_BLOCKED");
  assert.equal(code(() => meritRecommendation({ guidelinePct: "3", proposedPct: "6", policy: "reason_and_hr", hrApproved: false })), "CYCLE_EXCEPTION_REASON_REQUIRED");
  assert.equal(code(() => meritRecommendation({ guidelinePct: "3", proposedPct: "6", policy: "reason_and_hr", hrApproved: false, reason: "retention" })), "HR_APPROVAL_REQUIRED");
  assert.equal(meritRecommendation({ guidelinePct: "3", proposedPct: "6", policy: "reason_and_hr", hrApproved: true, reason: "retention" }).accepted, true);
  assert.equal(code(() => releaseLetters({ hrReviewed: false })), "HR_APPROVAL_REQUIRED");
  assert.equal(releaseLetters({ hrReviewed: true }).channel, "self_service");
  const past = approveRate({ effective: "2026-01-01", asOf: "2026-06-01", rate: "63000.00", submitterId: "analyst", steps: route });
  assert.equal(past.retro, true);
  assert.equal(past.kind, "compensation.set_rate");
});

test("COMP-006 pay equity compares predominance the caller recorded", () => {
  const flags = payEquityFlags({
    materialGapPct: "5",
    classes: [
      { id: "clerk", band: "G3", predominance: "female", rate: "50000", basis: "incumbent_count" },
      { id: "tech", band: "G3", predominance: "male", rate: "58000", basis: "incumbent_count" },
    ],
  });
  assert.equal(flags.flags.length, 1);
  assert.equal(flags.flags[0].basis, "incumbent_count");
});

test("COMP-008 COMP-032 total rewards statement on request in both screen languages", () => {
  const figures = { pay: "60000.00", cpp: "3000.00", ei: "900.00", pension: "4000.00", benefits: "5000.00", timeOff: "2000.00" };
  assert.equal(code(() => totalRewardsStatement({ cadence: "on_request", requested: false, lang: "en-CA", figures })), "STATEMENT_NOT_REQUESTED");
  const en = totalRewardsStatement({ cadence: "on_request", requested: true, lang: "en-CA", figures }).text;
  const fr = totalRewardsStatement({ cadence: "on_request", requested: true, lang: "fr-CA", figures }).text;
  assert.match(en, /60000\.00/);
  assert.match(fr, /60000\.00/);
  assert.notEqual(en, fr);
});

test("COMP-009 disclosure list stays unpublished while the statute is check-before-use", () => {
  const file = load("rules/compensation/salary-disclosure.json") as { statutes: Record<string, { status: string; threshold: number | null }> };
  const statute = { code: "ON_PSSDA", ...file.statutes.ON_PSSDA };
  assert.equal(statute.status, "verify_at_load");
  const people = [
    { id: "a", paid: String(statute.threshold), position: "Director" },
    { id: "b", paid: "1.00", position: "Clerk" },
  ];
  const draft = draftDisclosure({ statute, people, publish: false, hrApproved: false, financeApproved: false, preparerId: "p", approverId: "p" });
  assert.deepEqual(draft.listed.map((row) => row.id), ["a"]);
  assert.equal(draft.published, false);
  assert.equal(code(() => draftDisclosure({ statute, people, publish: true, hrApproved: true, financeApproved: true, preparerId: "p", approverId: "h" })), "RULE_NOT_VERIFIED");
});

test("COMP-010 COMP-011 philosophy and structure approval", () => {
  assert.equal(code(() => approveStructure({
    marketBased: true, philosophyCoversStart: false, routeFound: true, routeHasExecutive: true, submitterId: "a", approverId: "e",
  })), "PHILOSOPHY_NOT_APPROVED");
  assert.equal(approvePhilosophy({ submitterId: "a", approverId: "e", executive: true }).approved, true);
  assert.equal(code(() => approvePhilosophy({ submitterId: "a", approverId: "a", executive: true })), "SELF_APPROVAL");
  assert.equal(code(() => approveStructure({
    marketBased: false, philosophyCoversStart: true, routeFound: false, routeHasExecutive: false, submitterId: "a", approverId: "e",
  })), "INPUT_REQUIRED");
  assert.equal(code(() => approveStructure({
    marketBased: false, philosophyCoversStart: true, routeFound: true, routeHasExecutive: false, submitterId: "a", approverId: "e",
  })), "ROUTE_APPROVALS_MISSING");
  assert.equal(code(() => approveStructure({
    marketBased: true, philosophyCoversStart: true, routeFound: true, routeHasExecutive: true, submitterId: "a", approverId: "a",
  })), "SELF_APPROVAL");
  assert.equal(approveStructure({
    marketBased: true, philosophyCoversStart: true, routeFound: true, routeHasExecutive: true, submitterId: "a", approverId: "e",
  }).approved, true);
});

test("COMP-012 survey import uses a named generic profile until a publisher template is allowed", () => {
  const profiles = load("rules/total-rewards/survey-import-profiles.json") as { profiles: { code: string }[] };
  const prepared = prepareSurveyImport({ profiles: profiles.profiles, chosenCode: "wide_stats" });
  assert.equal(prepared.profileCode, "wide_stats");
  assert.equal(prepared.dryRun, true);
  assert.equal(code(() => prepareSurveyImport({
    profiles: profiles.profiles,
    publisherTemplate: { code: "PUB", sampleFile: false, permission: false },
  })), "INPUT_REQUIRED");
});

test("COMP-013 manager market ratios stay hidden for a restricted survey", () => {
  assert.equal(managerPayView({ ratiosEnabled: false, restrictedSurveyInRun: false, marketRatio: "1.000" }).marketRatio, null);
  assert.equal(managerPayView({ ratiosEnabled: true, restrictedSurveyInRun: true, marketRatio: "1.000" }).marketRatio, null);
  assert.equal(managerPayView({ ratiosEnabled: true, restrictedSurveyInRun: false, marketRatio: "1.000" }).marketRatio, "1.000");
});

test("COMP-014 range spread starts from the highest track in the organization's map", () => {
  const byTrack = { support: "30", professional: "40", management: "50", executive: "60" };
  assert.equal(gradeSpread({ tracks: ["support"], byTrack }), "30");
  assert.equal(gradeSpread({ tracks: ["professional", "executive"], byTrack }), "60");
  assert.equal(gradeSpread({ tracks: ["support"], byTrack, analystOverride: "33" }), "33");
});

test("COMP-015 every grade names its location group", () => {
  const rows = locationRanges([
    { grade: "G4", locationGroup: "south", minimum: "50000", maximum: "70000" },
    { grade: "G4", locationGroup: "north", minimum: "55000", maximum: "77000" },
  ]);
  assert.equal(rows.length, 2);
  assert.equal(code(() => locationRanges([{ grade: "G4", locationGroup: "", minimum: "1", maximum: "2" }])), "LOCATION_GROUP_MISMATCH");
});

test("COMP-016 catch-up date comes from the organization's months", () => {
  assert.equal(catchUpPlan({ belowOn: "2027-01-01", months: "12", cancel: false }).target, "2028-01-01");
  assert.equal(catchUpPlan({ belowOn: "2027-01-01", months: "6", cancel: false }).target, "2027-07-01");
  assert.equal(code(() => catchUpPlan({ belowOn: "2027-01-01", months: null, cancel: false })), "SETTING_NOT_SET");
  assert.equal(code(() => catchUpPlan({ belowOn: "2027-01-01", months: "12", cancel: true })), "INPUT_REQUIRED");
  assert.equal(catchUpPlan({ belowOn: "2027-01-01", months: "12", cancel: true, cancelReason: "left" }).cancelled, true);
});

test("COMP-017 pay above the maximum is flagged and is not cut automatically", () => {
  const flagged = aboveMaximum({ rate: "80000", maximum: "70000", approved: false, effective: "2027-04-01" });
  assert.equal(flagged.flagged, true);
  assert.equal(flagged.cutApplied, false);
  assert.equal(flagged.changeSet, null);
  const approved = aboveMaximum({ rate: "80000", maximum: "70000", proposal: "79000", approved: true, effective: "2027-04-01" });
  assert.equal(approved.changeSet?.rate, "79000");
  assert.equal(approved.cutApplied, false);
});

test("COMP-018 promotion floor is the new minimum and the organization's percent", () => {
  assert.equal(code(() => promotionRate({ current: "60000", proposed: "62000", newMinimum: "61000", minIncreasePct: "5" })), "PROMOTION_BELOW_RULE");
  assert.equal(promotionRate({ current: "60000", proposed: "63000", newMinimum: "61000", minIncreasePct: "5" }).rate, "63000");
  assert.equal(code(() => promotionRate({ current: "60000", proposed: "63000", newMinimum: "61000", minIncreasePct: null })), "SETTING_NOT_SET");
});

test("COMP-019 a demotion that cuts pay needs the caution and a reason", () => {
  assert.equal(code(() => demotionPay({ current: "70000", proposed: "66000", cautionAcknowledged: false })), "CAUTION_NOT_ACKNOWLEDGED");
  assert.equal(code(() => demotionPay({ current: "70000", proposed: "66000", cautionAcknowledged: true })), "CAUTION_REASON_REQUIRED");
  assert.equal(demotionPay({ current: "70000", proposed: "66000", cautionAcknowledged: true, reason: "role changed" }).rate, "66000");
});

test("COMP-020 acting pay waits until the organization chooses a method", () => {
  assert.equal(code(() => actingPay({ method: null, percent: null, current: "50000", rangeMinimum: "54000", stepsAbove: [] })), "SETTING_NOT_SET");
  assert.equal(actingPay({ method: "percent_above_current", percent: "10", current: "50000.00", rangeMinimum: "54000", stepsAbove: [] }).rate, "55000.00");
});

test("COMP-024 retention payout follows the route and not its submitter", () => {
  assert.equal(approvePayout({ submitterId: "analyst", steps: route }).approved, true);
  assert.equal(code(() => approvePayout({ submitterId: "hr", steps: route })), "SELF_APPROVAL");
});

test("COMP-025 clawback only inside the signed agreement", () => {
  assert.equal(code(() => clawback({ signed: false, authorized: "1000.00", requested: "1000.00" })), "CLAWBACK_NOT_SIGNED");
  assert.equal(code(() => clawback({ signed: true, authorized: "1000.00", requested: "1001.00" })), "CLAWBACK_NOT_SIGNED");
  assert.equal(clawback({ signed: true, authorized: "1000.00", requested: "400.00" }).recovery, "400.00");
});

test("COMP-026 incentive proration uses the eligible days the count rule supplies", () => {
  const result = prorateIncentive({ amount: "1000.00", eligibleDays: "184", periodDays: "365", countRule: "protected_leave_counts" });
  assert.equal(result.payout, "504.11");
  assert.equal(result.countRule, "protected_leave_counts");
});

test("COMP-027 commission applies the plan tiers and the route", () => {
  const result = commissionPayout({
    sales: "10000",
    tiers: [{ upTo: "5000", ratePct: "5" }, { upTo: null, ratePct: "8" }],
    cap: "1000.00",
    submitterId: "analyst",
    steps: route,
  });
  assert.equal(result.commission, "650.00");
  assert.equal(result.approved, true);
});

test("COMP-028 a phantom unit grant needs a long-term plan", () => {
  assert.equal(code(() => recordGrant({ planKind: "retention", units: "100", vesting: "3 years" })), "LTI_PLAN_REQUIRED");
  assert.deepEqual(recordGrant({ planKind: "long_term", units: "100", vesting: "3 years" }), { units: "100", vesting: "3 years" });
});

test("COMP-029 the employee pay page hides market position until the organization shows it", () => {
  const range = { minimum: "50000", midpoint: "60000", maximum: "70000" };
  const hidden = employeePayPage({
    showPhilosophy: true, showOwnRange: true, showQuartile: true, showMarket: false,
    philosophy: "Match the median", rate: "60000", range, marketRate: "62000",
  });
  assert.equal(hidden.philosophy, "Match the median");
  assert.equal(hidden.quartile, "Q3");
  assert.equal(hidden.marketRatio, null);
});

test("COMP-030 pay gap groups under the floor are hidden", () => {
  assert.equal(code(() => payGap({ floor: "8", minimumFloor: "10", groups: [] })), "SETTING_BELOW_MINIMUM");
  const result = payGap({
    floor: "10",
    minimumFloor: "10",
    groups: [
      { id: "indigenous", consented: true, count: 7 },
      { id: "women", consented: true, count: 12 },
    ],
  });
  assert.deepEqual(result.hidden, ["indigenous"]);
  assert.deepEqual(result.shown, ["women"]);
});

test("COMP-034 a bargaining scenario costs the proposal and does not change pay", () => {
  const costed = bargainScenario({ basePayroll: "100000.00", annualPct: "3", years: 3, ratify: false });
  assert.deepEqual(costed.yearPayroll, ["103000.00", "106090.00", "109272.70"]);
  assert.equal(costed.changesPay, false);
  assert.equal(code(() => bargainScenario({ basePayroll: "100000.00", annualPct: "3", years: 3, ratify: true })), "INPUT_REQUIRED");
});

test("COMP-035 TR-001 TR-003 the Unified Competency Model publishes and proposes P2 targets", () => {
  const model = load("rules/competencies/unified-competency-model.json") as CompetencyModel;
  const published = publishStarter(model);
  assert.equal(published.frameworkCode, "UCM");
  assert.equal(published.version, "1.0");
  assert.equal(published.status, "published");
  const broken = structuredClone(model);
  broken.competencies[0].indicators_status = "proposed";
  assert.equal(code(() => publishStarter(broken)), "INDICATORS_STATUS_NOT_ACCEPTED");
  const arch = load("rules/job-architecture/career-levels.json") as Architecture;
  assert.equal(arch.levels.length, 15);
  assert.ok(arch.starter_job_families.length > 0);
  const targets = proposeCareerTargets(arch, "P2");
  assert.ok(targets.length > 0);
  for (const target of targets) {
    assert.equal(target.level, 3);
    assert.equal(target.status, "proposed");
    assert.equal(target.active, false);
    assert.notEqual(target.domain, "LEAD");
  }
});

test("POSITION_GRADE_DIFFERS and posting ranges come from the structure", () => {
  assert.equal(positionGrade({ jobGrade: "G6", positionGrade: "G7" }).flag, "POSITION_GRADE_DIFFERS");
  assert.deepEqual(postingRange([{ grade: "G6", minimum: "57600", maximum: "80600" }], "G6"), { minimum: "57600", maximum: "80600" });
});

test("BEN-001 eligibility uses combined FTE and does not end coverage by itself", () => {
  assert.equal(combinedFte([
    { fte: "0.50", inScope: true },
    { fte: "0.30", inScope: true },
    { fte: "1.00", inScope: false },
  ]), "0.80");
  const opened = enrolmentTask({
    assignments: [{ fte: "0.80", inScope: true }],
    minFte: "0.60",
    waitingMet: true,
    fteNow: "0.80",
  });
  assert.equal(opened.task, "enrol");
  assert.equal(opened.applied, false);
  const dropped = enrolmentTask({
    assignments: [{ fte: "0.80", inScope: true }],
    minFte: "0.60",
    waitingMet: true,
    fteNow: "0.50",
  });
  assert.equal(dropped.task, null);
  assert.equal(dropped.proposedEnd, true);
  assert.equal(dropped.applied, false);
});

test("BEN-002 BEN-025 the life-event window is the plan's or the organization's", () => {
  assert.equal(lifeEventWindow({ planDays: 45, orgDays: 31 }), 45);
  assert.equal(lifeEventWindow({ planDays: null, orgDays: 31 }), 31);
  assert.equal(code(() => lifeEventWindow({ planDays: null, orgDays: null })), "SETTING_NOT_SET");
});

test("BEN-003 deductions and taxable benefits, with Quebec health left for phase 2", () => {
  const life = electionCosts({
    employeePerPay: "12.50",
    employerPerPay: "30.00",
    taxTiming: "post_tax",
    benefitKind: "life",
    jurisdiction: "ON",
    taxableBenefitRule: "employer_paid",
  });
  assert.equal(life.taxableBenefit, "30.00");
  assert.equal(life.taxTiming, "post_tax");
  assert.equal(code(() => electionCosts({
    employeePerPay: "0.00",
    employerPerPay: "80.00",
    taxTiming: "pre_tax",
    benefitKind: "health",
    jurisdiction: "QC",
    taxableBenefitRule: "employer_paid",
  })), "QUEBEC_PHASE_2");
});

test("BEN-004 a short premium becomes arrears and coverage stays", () => {
  const result = premiumArrears({ netPay: "100.00", premium: "150.00", recoveryRule: "arrears" });
  assert.equal(result.taken, "100.00");
  assert.equal(result.arrears, "50.00");
  assert.equal(result.coverageCancelled, false);
});

test("BEN-005 BEN-031 BEN-032 leave contributions follow the law and the organization's ways", () => {
  assert.equal(code(() => leaveContribution({
    statutory: true, declineForStaffing: true, method: "arrears_on_return", offered: ["arrears_on_return"], classRule: "keep",
  })), "STATUTORY_LEAVE_FOLLOWS_LAW");
  assert.equal(leaveContribution({
    statutory: true, declineForStaffing: false, method: "arrears_on_return", offered: ["arrears_on_return", "employer_pays"], classRule: null,
  }).method, "arrears_on_return");
  assert.equal(code(() => leaveContribution({
    statutory: true, declineForStaffing: false, method: "payroll", offered: ["arrears_on_return"], classRule: null,
  })), "LEAVE_CONTRIBUTION_METHOD_NOT_ALLOWED");
  assert.equal(code(() => leaveContribution({
    statutory: false, declineForStaffing: false, method: "arrears_on_return", offered: ["arrears_on_return"], classRule: null,
  })), "LEAVE_BENEFIT_RULE_MISSING");
});

test("BEN-006 BEN-021 carrier file, changes, and coordination left to HR", () => {
  const file = carrierEnrolmentFile([
    { personId: "A", planCode: "DENT", planKind: "dental", action: "enroll", effective: "2027-01-01", waiting: false, cobOrderSet: true },
    { personId: "B", planCode: "H1", planKind: "health", action: "enroll", effective: "2027-01-01", waiting: false, cobOrderSet: false },
    { personId: "B", planCode: "H2", planKind: "health", action: "enroll", effective: "2027-01-01", waiting: false, cobOrderSet: false },
    { personId: "C", planCode: "LIFE", planKind: "life", action: "enroll", effective: "2027-02-01", waiting: true, cobOrderSet: true },
  ]);
  assert.equal(file.body, "CANDO-CARRIER-ENROLMENT v1\nA|DENT|enroll|2027-01-01\n");
  assert.deepEqual(file.excluded.map((row) => row.code), ["COB_ORDER_NOT_SET", "COB_ORDER_NOT_SET", "WAITING"]);
  assert.deepEqual(changesSince([{ personId: "A", action: "enroll" }], [{ personId: "A", action: "waive" }]), [{ personId: "A", action: "waive" }]);
  assert.equal(acknowledgementTasks([{ personId: "A", message: "rejected" }]).length, 1);
});

test("BEN-007 BEN-039 BEN-040 pension split and CanDo remittance files", () => {
  const split = pensionSplit({
    ytdBefore: "70000.00",
    thisPay: "5000.00",
    ympe: "73200.00",
    rateBelow: "0.09",
    rateAbove: "0.146",
    employeeShare: "0.5",
    box52Rule: { kind: "percent_of_employer", percent: "100" },
  });
  assert.equal(split.below, "3200.00");
  assert.equal(split.above, "1800.00");
  assert.equal(split.employee, "275.40");
  assert.equal(split.employer, "275.40");
  assert.equal(split.box52, "275.40");
  const line = [{ personId: "P", hours: "10.00", rate: "1.25" }];
  for (const layout of ["bc_mpp", "omers", "hoopp", "lapp", "generic_trust"]) {
    assert.equal(pensionRemittance(layout, line), `CANDO-PENSION ${layout}\nP|10.00|1.25|12.50\n`);
  }
  const enrolled = mandatoryPension({ mandatory: true, eligibilityDate: "2027-03-01" });
  assert.equal(enrolled.enrolled, true);
  assert.equal(enrolled.employeeTold, true);
  assert.equal(enrolled.hrConfirmTask, true);
  assert.equal(enrolled.contributions, "next_pay");
});

test("BEN-008 BEN-020 spending accounts keep balances and drop claim lines", () => {
  const imported = spendingImport({ balance: "400.00", carryForward: "50.00", runOut: "2027-03-31", wellnessAmount: "25.00" });
  assert.equal(imported.balance, "400.00");
  assert.equal(imported.payrollAmount, "25.00");
  assert.equal(code(() => spendingImport({ balance: "1.00", carryForward: "0.00", runOut: "2027-03-31", claims: [{ drug: "secret" }] })), "NO_CLAIM_DETAILS");
});

test("BEN-009 enrolment shows both screen languages and the assistant stays off", () => {
  const options = [{ code: "A", perPay: "40.00" }, { code: "B", perPay: "55.00" }];
  const en = enrolmentComparison({ lang: "en-CA", options });
  const fr = enrolmentComparison({ lang: "fr-CA", options });
  assert.match(en.options[0], /40\.00/);
  assert.match(fr.options[0], /40\.00/);
  assert.notEqual(en.comparison, fr.comparison);
  assert.equal(code(() => enrolmentAssistant()), "FEATURE_OFF");
});

test("BEN-022 an advisor with plan costs does not see a person", () => {
  const view = advisorView({
    capability: "plan_costs",
    askPerson: true,
    people: [{ personId: "p1", cost: "10.00" }, { personId: "p2", cost: "15.00" }],
  });
  assert.equal(view.count, 2);
  assert.equal(view.cost, "25.00");
  assert.equal(view.people, null);
  assert.equal(view.refusedIndividual, true);
});

test("BEN-024 a waiting period is required and weeks are not a valid kind", () => {
  assert.equal(code(() => validateWaiting(null)), "INPUT_REQUIRED");
  assert.equal(code(() => validateWaiting({ text: "4 weeks" })), "WAITING_RULE_INVALID");
  assert.equal(code(() => validateWaiting({ kind: "weeks", months: 4 })), "WAITING_RULE_INVALID");
  assert.deepEqual(validateWaiting({ kind: "first_of_month_after", months: 3 }), { kind: "first_of_month_after", months: 3 });
});

test("BEN-026 evidence of insurability and a late-enrolment rule", () => {
  assert.equal(evidenceOfInsurability({ planKind: "life", required: true }).required, true);
  assert.equal(code(() => requireLateEnrolment(null)), "INPUT_REQUIRED");
  assert.equal(requireLateEnrolment("next_open_enrolment"), "next_open_enrolment");
});

test("BEN-027 open enrolment rolls forward, and a flex plan uses its own default", () => {
  assert.deepEqual(openEnrolment({ didNothing: true, elections: ["dental-a"], flex: false, flexDefault: null }).elections, ["dental-a"]);
  assert.deepEqual(openEnrolment({ didNothing: true, elections: [], flex: true, flexDefault: "core" }).elections, ["core"]);
});

test("BEN-028 variable-hour eligibility is proposed to HR", () => {
  const result = variableHoursProposal({ averageHours: "22", testHours: "20" });
  assert.equal(result.proposal, "eligible");
  assert.equal(result.applied, false);
});

test("BEN-029 BEN-030 HR chooses the governing agreement and the coordination order", () => {
  assert.equal(code(() => governingAgreement({ agreements: ["full-time", "part-time"] })), "GOVERNING_AGREEMENT_NOT_SET");
  assert.equal(governingAgreement({ agreements: ["full-time", "part-time"], choice: "full-time", reason: "the person asked" }).agreement, "full-time");
  assert.equal(governingAgreement({ agreements: ["only"] }).agreement, "only");
  assert.equal(code(() => cobOrder({ plans: ["a", "b"] })), "COB_ORDER_NOT_SET");
  assert.deepEqual(cobOrder({ plans: ["a", "b"], order: ["b", "a"], reason: "birthday rule in the contract" }).order, ["b", "a"]);
  assert.equal(trustOrder(["trust-a", "trust-b"]).chosenByCanDo, false);
});

test("BEN-035 premium adjustments older than the organization's months wait for HR", () => {
  assert.equal(code(() => premiumAdjustment({ reachesBackMonths: 5, allowedMonths: null, hrApprovedOlder: false })), "SETTING_NOT_SET");
  assert.equal(premiumAdjustment({ reachesBackMonths: 5, allowedMonths: 3, hrApprovedOlder: false }).applied, false);
  assert.equal(premiumAdjustment({ reachesBackMonths: 5, allowedMonths: 3, hrApprovedOlder: true }).applied, true);
});

test("BEN-036 a carrier invoice needs its differences and a different approver", () => {
  assert.equal(code(() => approveInvoice({ differencesListed: false, preparerId: "p", approverId: "h", steps: route })), "INPUT_REQUIRED");
  assert.equal(code(() => approveInvoice({ differencesListed: true, preparerId: "hr", approverId: "hr", steps: route })), "SELF_APPROVAL");
  assert.equal(approveInvoice({ differencesListed: true, preparerId: "p", approverId: "hr", steps: route }).approved, true);
});

test("BEN-037 age-out notice uses the plan's age date and lead time", () => {
  const notice = ageOutNotice({ birthday: "2027-06-15", leadDays: 60 });
  assert.equal(notice.noticeOn, "2027-04-16");
  assert.equal(notice.askProofOfStudies, true);
});

test("BEN-038 dental opt-out needs proof, and Quebec drugs follow the supplied rule", () => {
  assert.equal(optOut({ kind: "dental", rule: null, otherPrivatePlan: false }).allowed, false);
  assert.equal(code(() => optOut({ kind: "drug", rule: null, otherPrivatePlan: false })), "JURISDICTION_RULE_MISSING");
  const refused = optOut({
    kind: "drug",
    rule: { basis: "ramq", drugRequiresOtherPrivatePlan: true },
    otherPrivatePlan: false,
  });
  assert.equal(refused.allowed, false);
  assert.equal(refused.basis, "ramq");
});
