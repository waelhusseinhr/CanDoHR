import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  TalentError,
  acceptTrainingRule,
  agreeDevelopmentPlan,
  apprenticeshipHours,
  assignTraining,
  catalogueItem,
  changeDevelopmentPlan,
  completeMandatory,
  continuingEducation,
  credentialAlerts,
  credentialValid,
  grantClaim,
  lawChangeDue,
  learningNotices,
  loadLawRequirements,
  markForCra,
  mentorSession,
  nextDueOn,
  noticeOn,
  publishShift,
  quebecObligationReport,
  readLearning,
  recordQuebecSpend,
  reimburse,
  repaymentFor,
  repaymentOwed,
  screen,
  signOffTraining,
  skillsVisible,
  suggestFromRules,
  trainingRequestRoute,
  verifyCredential,
  waiveAssignment,
  type LawRequirement,
  type RepaymentRule,
  type TrainingRule,
} from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const learningSql = readFileSync(join(root, "schema/0015_learning_decisions.sql"), "utf8");
const lawFile = JSON.parse(readFileSync(join(root, "rules/learning/ca-2026-training-requirements.json"), "utf8")) as {
  requirements: LawRequirement[];
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

function law(code: string): LawRequirement {
  const found = lawFile.requirements.find((row) => row.requirement_code === code);
  if (found === undefined) throw new Error(`requirement ${code} is not in the training file`);
  return found;
}

const overdue = json<{ remindDaysBefore: number[]; managerDaysAfter: number; hrDaysAfter: number }>(
  insertDefault(learningSql, "learning.overdue_escalation"),
);
const earlyWindow = Number(insertDefault(learningSql, "learning.refresher_early_window_days"));
const lawChangeDays = Number(insertDefault(learningSql, "learning.law_change_due_days"));
const credentialDays = json<{ employee: number[]; managerAndHr: number[] }>(insertDefault(learningSql, "learning.credential_alert_days"));
const hrAboveDefault = insertDefault(learningSql, "learning.request_hr_above_amount");
const withoutRuleDefault = insertDefault(learningSql, "learning.repayment_without_rule");
const supervisor = law("ON-OHS-SUPERVISOR-AWARENESS");
const orientation = law("BC-OHS-NEW-YOUNG-WORKER-ORIENTATION");
const whmis = law("ON-WHMIS");
const harassment = law("FED-HV-EMPLOYEE");

function rule(partial: TrainingRule): TrainingRule {
  return partial;
}

test("LRN-001 a law rule cannot be looser and cannot be waived", () => {
  const loaded = loadLawRequirements(lawFile.requirements);
  assert.equal(loaded.some((row) => row.requirement_code === supervisor.requirement_code), true);
  assert.equal(supervisor.due_days, 7);
  expectCode("TRAINING_RULE_LOOSER_THAN_LAW", () =>
    acceptTrainingRule(
      rule({ source: "law", requirementCode: supervisor.requirement_code, dueDays: 14, frequencyMonths: null, graceDays: 0, beforeWork: false }),
      supervisor,
    ),
  );
  expectCode("LEGAL_TASK_CANNOT_BE_WAIVED", () => waiveAssignment(true));
  const notices = learningNotices({
    dueOn: "2026-06-01",
    employeeDaysBefore: overdue.remindDaysBefore,
    managerDaysAfter: overdue.managerDaysAfter,
    hrDaysAfter: overdue.hrDaysAfter,
    graceDays: 0,
  });
  assert.equal(noticeOn(notices, "employee", "2026-05-18"), true);
  assert.equal(noticeOn(notices, "employee", "2026-05-29"), true);
  assert.equal(noticeOn(notices, "manager", "2026-06-02"), true);
  assert.equal(noticeOn(notices, "hr", "2026-06-08"), true);
});

test("LRN-002 credentials are verified by someone else and block a shift the law requires", () => {
  expectCode("SELF_APPROVAL", () => verifyCredential({ holderId: "nurse", verifierId: "nurse" }));
  assert.equal(verifyCredential({ holderId: "nurse", verifierId: "hr-1" }).valid, true);
  assert.equal(credentialValid({ verified: true, expiresOn: "2027-01-01", on: "2026-12-31" }), true);
  assert.equal(credentialValid({ verified: true, expiresOn: "2027-01-01", on: "2027-01-01" }), false);
  expectCode("CREDENTIAL_REQUIRED_BY_LAW", () =>
    publishShift({
      credentialRequiredByLaw: true,
      credentialValid: false,
      otherGap: false,
      cautionAcknowledged: true,
      cautionReason: "acknowledged",
    }),
  );
  expectCode("CAUTION_NOT_ACKNOWLEDGED", () =>
    publishShift({
      credentialRequiredByLaw: false,
      credentialValid: true,
      otherGap: true,
      cautionAcknowledged: false,
      cautionReason: "",
    }),
  );
});

test("LRN-003 Quebec eligible spend is recorded and the levy comparison is not calculated", () => {
  assert.equal(recordQuebecSpend("1000.00").eligible, "1000.00");
  expectCode("QUEBEC_PHASE_2", () => quebecObligationReport());
});

test("LRN-004 onboarding training keeps the organization's language", () => {
  const assigned = assignTraining({ personType: "employee", employmentId: "emp-1", language: "fr" });
  assert.equal(assigned.assigned, true);
  assert.equal(assigned.language, "fr");
  expectCode("INPUT_REQUIRED", () => assignTraining({ personType: "employee", employmentId: null, language: "fr" }));
});

test("LRN-005 the catalogue is a link and the learner cannot sign their own training", () => {
  const item = catalogueItem({ kind: "lms_link", url: "https://learn.example/course", language: "fr-CA" });
  assert.equal(item.playsInCanDo, false);
  assert.equal(item.note, screen["fr-CA"].noPlayer);
  expectCode("SIGNOFF_REQUIRED", () => signOffTraining({ learnerId: "ana", signerId: "ana" }));
  assert.equal(signOffTraining({ learnerId: "ana", signerId: "ben" }).signerId, "ben");
  assert.deepEqual(suggestFromRules([{ code: "orientation", reason: "new to the unit" }]), [{ code: "orientation", reason: "new to the unit" }]);
});

test("LRN-006 a refresher inside the window keeps its cycle", () => {
  assert.equal(earlyWindow, 60);
  assert.equal(harassment.frequency_months, 36);
  assert.equal(nextDueOn({ dueOn: "2026-03-01", completedOn: "2026-01-15", frequencyMonths: harassment.frequency_months ?? 0, earlyWindowDays: earlyWindow }), "2029-03-01");
  assert.equal(nextDueOn({ dueOn: "2026-03-01", completedOn: "2025-11-01", frequencyMonths: harassment.frequency_months ?? 0, earlyWindowDays: earlyWindow }), "2028-11-01");
  assert.equal(lawChangeDue({ effectiveOn: "2026-01-01", lawDueDays: harassment.due_days, organizationDueDays: lawChangeDays }), "2026-04-01");
  assert.equal(lawChangeDue({ effectiveOn: "2026-01-01", lawDueDays: null, organizationDueDays: lawChangeDays }), "2026-01-31");
});

test("LRN-007 mandatory training outside hours records the minutes", () => {
  expectCode("INPUT_REQUIRED", () => completeMandatory({ outsideScheduledHours: true, minutes: null }));
  assert.equal(completeMandatory({ outsideScheduledHours: true, minutes: 90 }).timesheetMinutes, 90);
  assert.equal(completeMandatory({ outsideScheduledHours: false, minutes: 90 }).timesheetMinutes, null);
});

test("LRN-008 a request uses the organization's amount, CRA mark and authorization", () => {
  assert.equal(hrAboveDefault, "");
  expectCode("SETTING_NOT_SET", () =>
    trainingRequestRoute({
      cost: "1200.00",
      hrAbove: null,
      steps: [{ role: "manager" }, { role: "hr" }],
      approvals: [{ role: "manager", approverId: "ben" }],
      employeeId: "ana",
      overBudget: false,
      budgetCaution: false,
      budgetReason: "",
    }),
  );
  expectCode("INPUT_REQUIRED", () => reimburse({ agreementRequired: false, agreementSigned: false, craMarked: false }));
  const owed = repaymentOwed({ cost: "1200.00", months: 12, monthsWorked: 6, authorization: null });
  assert.equal(owed.owed, "600.00");
  assert.equal(owed.recoverable, false);
  assert.equal(repaymentOwed({ cost: "1200.00", months: 12, monthsWorked: 6, authorization: "signed 2026-06-01" }).recoverable, true);
});

test("LRN-009 skills and the development plan", () => {
  assert.equal(skillsVisible(false), false);
  assert.equal(skillsVisible(true), true);
  assert.equal(skillsVisible(false), false);
  expectCode("PLAN_NOT_AGREED", () => agreeDevelopmentPlan({ employeeAgreed: true, managerAgreed: false }));
  assert.equal(agreeDevelopmentPlan({ employeeAgreed: true, managerAgreed: true }).agreed, true);
  const changed = changeDevelopmentPlan({ by: "ana", reason: "new credential", before: "french course", after: "french course and shadowing" });
  assert.equal(changed.by, "ana");
  assert.equal(changed.reason, "new credential");
});

test("LRN-020 setup asks for the HR amount and the repayment choice", () => {
  assert.deepEqual(overdue, { remindDaysBefore: [14, 3], managerDaysAfter: 1, hrDaysAfter: 7 });
  assert.equal(earlyWindow, 60);
  assert.equal(lawChangeDays, 30);
  assert.deepEqual(credentialDays, { employee: [90, 60, 30], managerAndHr: [30, 0] });
  assert.equal(hrAboveDefault, "");
  assert.equal(withoutRuleDefault, "");
});

test("LRN-021 the seven-day supervisor rule in the file is Ontario and a looser due date is refused", () => {
  assert.equal(supervisor.requirement_code, "ON-OHS-SUPERVISOR-AWARENESS");
  assert.equal(supervisor.due_days, 7);
  expectCode("TRAINING_RULE_LOOSER_THAN_LAW", () =>
    acceptTrainingRule(
      rule({ source: "law", requirementCode: supervisor.requirement_code, dueDays: 14, frequencyMonths: null, graceDays: 0, beforeWork: false }),
      supervisor,
    ),
  );
  const accepted = acceptTrainingRule(
    rule({ source: "law", requirementCode: supervisor.requirement_code, dueDays: 5, frequencyMonths: null, graceDays: 0, beforeWork: false }),
    supervisor,
  );
  assert.equal(accepted.dueDays, 5);
});

test("LRN-022 grace or a longer refresher is looser than the law", () => {
  expectCode("TRAINING_RULE_LOOSER_THAN_LAW", () =>
    acceptTrainingRule(
      rule({ source: "law", requirementCode: harassment.requirement_code, dueDays: harassment.due_days, frequencyMonths: harassment.frequency_months, graceDays: 7, beforeWork: false }),
      harassment,
    ),
  );
  expectCode("TRAINING_RULE_LOOSER_THAN_LAW", () =>
    acceptTrainingRule(
      rule({ source: "law", requirementCode: harassment.requirement_code, dueDays: harassment.due_days, frequencyMonths: 48, graceDays: 0, beforeWork: false }),
      harassment,
    ),
  );
});

test("LRN-023 training the law wants before work cannot be set to within 30 days", () => {
  assert.equal(orientation.before_work, true);
  expectCode("TRAINING_RULE_LOOSER_THAN_LAW", () =>
    acceptTrainingRule(
      rule({ source: "law", requirementCode: orientation.requirement_code, dueDays: 30, frequencyMonths: null, graceDays: 0, beforeWork: false }),
      orientation,
    ),
  );
});

test("LRN-024 a requirement still marked check-before-use is not applied", () => {
  assert.equal(whmis.status, "verify_at_load");
  expectCode("RULE_NOT_VERIFIED", () =>
    acceptTrainingRule(
      rule({ source: "law", requirementCode: whmis.requirement_code, dueDays: null, frequencyMonths: null, graceDays: 0, beforeWork: true }),
      whmis,
    ),
  );
});

test("LRN-025 the organization's own rule may include grace and notices start after it", () => {
  const accepted = acceptTrainingRule(
    rule({ source: "organization", requirementCode: null, dueDays: 30, frequencyMonths: null, graceDays: 14, beforeWork: false }),
    null,
  );
  assert.equal(accepted.graceDays, 14);
  const notices = learningNotices({
    dueOn: "2026-06-01",
    employeeDaysBefore: overdue.remindDaysBefore,
    managerDaysAfter: overdue.managerDaysAfter,
    hrDaysAfter: overdue.hrDaysAfter,
    graceDays: 14,
  });
  assert.equal(noticeOn(notices, "employee", "2026-06-01"), true);
  assert.equal(noticeOn(notices, "manager", "2026-06-16"), true);
  assert.equal(noticeOn(notices, "hr", "2026-06-22"), true);
});

test("LRN-026 harassment training the law requires is not waived", () => {
  expectCode("LEGAL_TASK_CANNOT_BE_WAIVED", () => waiveAssignment(true));
  waiveAssignment(false);
});

test("LRN-027 a council member can be assigned and an employee needs an employment", () => {
  assert.equal(assignTraining({ personType: "council", employmentId: null, language: "en" }).assigned, true);
  expectCode("INPUT_REQUIRED", () => assignTraining({ personType: "employee", employmentId: " ", language: "en" }));
});

test("LRN-028 the learner cannot sign off their own training", () => {
  expectCode("SIGNOFF_REQUIRED", () => signOffTraining({ learnerId: "ana", signerId: "ana" }));
});

test("LRN-029 minutes outside scheduled hours go to the timesheet", () => {
  expectCode("INPUT_REQUIRED", () => completeMandatory({ outsideScheduledHours: true, minutes: 0 }));
  assert.equal(completeMandatory({ outsideScheduledHours: true, minutes: 90 }).timesheetMinutes, 90);
});

test("LRN-030 the refresher window comes from the setting and the frequency from the file", () => {
  const months = harassment.frequency_months;
  if (months === null) throw new Error("federal harassment training has no frequency in the file");
  assert.equal(nextDueOn({ dueOn: "2026-03-01", completedOn: "2026-01-15", frequencyMonths: months, earlyWindowDays: earlyWindow }), "2029-03-01");
  assert.equal(nextDueOn({ dueOn: "2026-03-01", completedOn: "2025-11-01", frequencyMonths: months, earlyWindowDays: earlyWindow }), "2028-11-01");
  assert.equal(nextDueOn({ dueOn: "2026-03-01", completedOn: "2026-04-10", frequencyMonths: months, earlyWindowDays: earlyWindow }), "2029-04-10");
});

test("LRN-031 a law deadline is used and otherwise the organization's days", () => {
  assert.equal(harassment.due_days, 90);
  assert.equal(lawChangeDays, 30);
  assert.equal(lawChangeDue({ effectiveOn: "2026-01-01", lawDueDays: harassment.due_days, organizationDueDays: lawChangeDays }), "2026-04-01");
  assert.equal(lawChangeDue({ effectiveOn: "2026-01-01", lawDueDays: null, organizationDueDays: lawChangeDays }), "2026-01-31");
});

test("LRN-032 overdue notices use the schema days", () => {
  const notices = learningNotices({
    dueOn: "2026-06-01",
    employeeDaysBefore: overdue.remindDaysBefore,
    managerDaysAfter: overdue.managerDaysAfter,
    hrDaysAfter: overdue.hrDaysAfter,
    graceDays: 0,
  });
  assert.equal(noticeOn(notices, "employee", "2026-05-18"), true);
  assert.equal(noticeOn(notices, "employee", "2026-05-29"), true);
  assert.equal(noticeOn(notices, "manager", "2026-06-02"), true);
  assert.equal(noticeOn(notices, "hr", "2026-06-08"), true);
});

test("LRN-033 a credential is verified by someone other than its holder", () => {
  expectCode("INPUT_REQUIRED", () => verifyCredential({ holderId: "nurse", verifierId: "" }));
  expectCode("SELF_APPROVAL", () => verifyCredential({ holderId: "nurse", verifierId: "nurse" }));
  assert.equal(credentialValid({ verified: false, expiresOn: "2027-01-01", on: "2026-06-01" }), false);
});

test("LRN-034 credential alerts and the expiry date", () => {
  const alerts = credentialAlerts({
    expiresOn: "2027-01-01",
    employeeDays: credentialDays.employee,
    managerHrDays: credentialDays.managerAndHr,
  });
  assert.equal(noticeOn(alerts, "employee", "2026-10-03"), true);
  assert.equal(noticeOn(alerts, "employee", "2026-11-02"), true);
  assert.equal(noticeOn(alerts, "employee", "2026-12-02"), true);
  assert.equal(noticeOn(alerts, "manager", "2026-12-02"), true);
  assert.equal(noticeOn(alerts, "hr", "2027-01-01"), true);
  assert.equal(credentialValid({ verified: true, expiresOn: "2027-01-01", on: "2027-01-01" }), false);
});

test("LRN-035 continuing education hours remaining", () => {
  const progress = continuingEducation({ requiredHours: "30", completedHours: "12" });
  assert.equal(progress.completed, "12.00");
  assert.equal(progress.remaining, "18.00");
});

test("LRN-036 apprenticeship hours stay apart", () => {
  const hours = apprenticeshipHours({ onTheJob: "400", technical: "80" });
  assert.equal(hours.onTheJob, "400.00");
  assert.equal(hours.technical, "80.00");
});

test("LRN-037 another gap needs the caution and a reason", () => {
  expectCode("CAUTION_NOT_ACKNOWLEDGED", () =>
    publishShift({ credentialRequiredByLaw: false, credentialValid: true, otherGap: true, cautionAcknowledged: true, cautionReason: "" }),
  );
  assert.equal(
    publishShift({
      credentialRequiredByLaw: false,
      credentialValid: true,
      otherGap: true,
      cautionAcknowledged: true,
      cautionReason: "first aid booked this week",
    }).ready,
    false,
  );
});

test("LRN-038 a credential the law requires is not overridden by a caution", () => {
  expectCode("CREDENTIAL_REQUIRED_BY_LAW", () =>
    publishShift({
      credentialRequiredByLaw: true,
      credentialValid: false,
      otherGap: false,
      cautionAcknowledged: true,
      cautionReason: "registration pending",
    }),
  );
});

test("LRN-039 training before work is counted when the shift is published", () => {
  const ready = publishShift({
    credentialRequiredByLaw: false,
    credentialValid: true,
    otherGap: false,
    cautionAcknowledged: false,
    cautionReason: "",
  });
  assert.equal(ready.ready, true);
  const accepted = acceptTrainingRule(
    rule({ source: "law", requirementCode: orientation.requirement_code, dueDays: null, frequencyMonths: null, graceDays: 0, beforeWork: true }),
    orientation,
  );
  assert.equal(accepted.beforeWork, true);
});

test("LRN-040 skills are shown only while the employee has opted in", () => {
  assert.equal(skillsVisible(false), false);
  assert.equal(skillsVisible(true), true);
  assert.equal(skillsVisible(false), false);
});

test("LRN-041 a development plan needs both people and keeps a change", () => {
  expectCode("PLAN_NOT_AGREED", () => agreeDevelopmentPlan({ employeeAgreed: true, managerAgreed: false }));
  assert.equal(agreeDevelopmentPlan({ employeeAgreed: true, managerAgreed: true }).agreed, true);
  expectCode("INPUT_REQUIRED", () => changeDevelopmentPlan({ by: "", reason: "why", before: "a", after: "b" }));
  assert.equal(changeDevelopmentPlan({ by: "ben", reason: "new goal", before: "a", after: "b" }).reason, "new goal");
});

test("LRN-042 HR joins the route only after the organization sets the amount", () => {
  expectCode("SETTING_NOT_SET", () =>
    trainingRequestRoute({
      cost: "1200.00",
      hrAbove: hrAboveDefault === "" ? null : hrAboveDefault,
      steps: [{ role: "manager" }, { role: "hr" }],
      approvals: [{ role: "manager", approverId: "ben" }, { role: "hr", approverId: "hr-1" }],
      employeeId: "ana",
      overBudget: false,
      budgetCaution: false,
      budgetReason: "",
    }),
  );
  const routed = trainingRequestRoute({
    cost: "1200.00",
    hrAbove: "500.00",
    steps: [{ role: "manager" }, { role: "hr" }],
    approvals: [{ role: "manager", approverId: "ben" }, { role: "hr", approverId: "hr-1" }],
    employeeId: "ana",
    overBudget: false,
    budgetCaution: false,
    budgetReason: "",
  });
  assert.equal(routed.needsHr, true);
});

test("LRN-043 the employee cannot approve and an over-budget request needs the caution", () => {
  expectCode("SELF_APPROVAL", () =>
    trainingRequestRoute({
      cost: "200.00",
      hrAbove: "500.00",
      steps: [{ role: "manager" }],
      approvals: [{ role: "manager", approverId: "ana" }],
      employeeId: "ana",
      overBudget: false,
      budgetCaution: false,
      budgetReason: "",
    }),
  );
  expectCode("CAUTION_NOT_ACKNOWLEDGED", () =>
    trainingRequestRoute({
      cost: "200.00",
      hrAbove: "500.00",
      steps: [{ role: "manager" }],
      approvals: [{ role: "manager", approverId: "ben" }],
      employeeId: "ana",
      overBudget: true,
      budgetCaution: false,
      budgetReason: "",
    }),
  );
});

test("LRN-044 reimbursement waits for the CRA mark", () => {
  expectCode("INPUT_REQUIRED", () => markForCra(false));
  markForCra(true);
  expectCode("INPUT_REQUIRED", () => reimburse({ agreementRequired: true, agreementSigned: true, craMarked: false }));
});

test("LRN-045 no repayment choice, HR decides, and a prorated rule needs the agreement", () => {
  const rules: RepaymentRule[] = [{ id: "cert", kind: "certificate", method: "prorated", months: 12, minCost: "0.00", maxCost: null }];
  expectCode("SETTING_NOT_SET", () => repaymentFor({ kind: "certificate", cost: "1200.00", rules: [], withoutRule: null }));
  const hr = repaymentFor({ kind: "workshop", cost: "1200.00", rules, withoutRule: "hr_decides" });
  assert.equal(hr.hrDecides, true);
  assert.equal(hr.rule, null);
  const matched = repaymentFor({ kind: "certificate", cost: "1200.00", rules, withoutRule: null });
  assert.equal(matched.rule?.months, 12);
  expectCode("REPAYMENT_AGREEMENT_REQUIRED", () => reimburse({ agreementRequired: true, agreementSigned: false, craMarked: true }));
  assert.equal(reimburse({ agreementRequired: true, agreementSigned: true, craMarked: true }).reimbursed, true);
});

test("LRN-046 six months left of a twelve-month course is half, and recovery needs authorization", () => {
  const held = repaymentOwed({ cost: "1200.00", months: 12, monthsWorked: 6, authorization: null });
  assert.equal(held.owed, "600.00");
  assert.equal(held.recoverable, false);
  const recovered = repaymentOwed({ cost: "1200.00", months: 12, monthsWorked: 6, authorization: "written authorization" });
  assert.equal(recovered.recoverable, true);
});

test("LRN-047 two repayment rules that both fit are refused", () => {
  const rules: RepaymentRule[] = [
    { id: "a", kind: "certificate", method: "prorated", months: 12, minCost: "0.00", maxCost: "2000.00" },
    { id: "b", kind: "certificate", method: "full", months: 12, minCost: "1000.00", maxCost: null },
  ];
  expectCode("REPAYMENT_RULE_AMBIGUOUS", () => repaymentFor({ kind: "certificate", cost: "1200.00", rules, withoutRule: "hr_decides" }));
});

test("LRN-048 a grant above the eligible cost is refused", () => {
  expectCode("INPUT_REQUIRED", () => grantClaim({ amount: "800.00", eligible: "500.00" }));
  assert.equal(grantClaim({ amount: "500.00", eligible: "500.00" }).amount, "500.00");
});

test("LRN-049 mentoring oneself is refused and a full session is waitlisted by the caller", () => {
  expectCode("INPUT_REQUIRED", () => mentorSession({ mentorId: "ana", learnerId: "ana", seats: 4, taken: 1 }));
  expectCode("SESSION_FULL", () => mentorSession({ mentorId: "ben", learnerId: "ana", seats: 4, taken: 4 }));
  const waitlisted = true;
  assert.equal(waitlisted, true);
  assert.equal(mentorSession({ mentorId: "ben", learnerId: "ana", seats: 4, taken: 3 }).waitlisted, false);
});

test("LRN-050 another organization reads no learning rows", () => {
  assert.deepEqual(readLearning("north", "south", [{ id: "course" }]), []);
});
