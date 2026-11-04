import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  OffboardingError,
  bumpingOptions,
  commitSeparation,
  deathPayments,
  decideBenefitEnd,
  draftRoe,
  endAssignment,
  finalPayDeadline,
  finalPayItems,
  groupTerminations,
  previewSeparation,
  recordBump,
  recordLayoff,
  runBenefitCase,
  scheduleAccessRemoval,
  statutoryNotice,
  statutorySeverance,
  terminationDocument,
  transferEmployer,
  type SeparationInput,
} from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");

function load(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(join(root, path), "utf8")) as Record<string, unknown>;
}

const standards = load("rules/employment-standards/ca-2026.json") as {
  jurisdictions: Record<string, { termination_notice: { bands: { from_months?: number; from_years?: number; weeks: number }[]; status: string } }>;
};
const separation = load("rules/employment-standards/ca-2026-separation-additions.json") as {
  jurisdictions: Record<
    string,
    {
      statutory_severance: {
        status: string;
        exists: boolean | null;
        cite?: string;
        weeks_per_year_of_service?: number;
        prorated_for_part_years?: boolean;
        max_weeks?: number;
        min_service_years?: number;
        applies_when_any?: { employer_ontario_payroll_at_least?: number; qualifying_group_termination?: boolean }[];
        rule?: string;
        days_wages_per_year_of_service?: number;
        minimum_days_wages?: number;
        min_service_months?: number;
      };
      final_pay_deadline: {
        status: string;
        cite?: string;
        employer_ends: { rule: string; days_after_end?: number; hours_after_end?: number; or?: string } | null;
        employee_quits: { rule: string; days_after_end?: number; hours_after_end?: number; or?: string } | null;
      };
      group_termination: { status: string; cite?: string; thresholds: { count: number; within_weeks: number } | null };
      temporary_layoff: { status: string; cite?: string; max_weeks: number | null; within_weeks: number | null };
    }
  >;
};
const benefitCases = (
  load("tests/assignments/several_positions_cases.json") as {
    cases: { id: string; kind: string; input: Parameters<typeof runBenefitCase>[0] }[];
  }
).cases.filter((item) => item.kind === "benefits");

function throws(code: string, run: () => void): void {
  assert.throws(run, (error: unknown) => error instanceof OffboardingError && error.code === code);
}

test("OFF-002 Ontario six years is six weeks and British Columbia four years is four weeks", () => {
  const ontario = statutoryNotice(standards.jurisdictions.ON.termination_notice, { years: 6, months: 0 }, false);
  assert.equal(ontario.weeks, 6);
  assert.equal(ontario.status, "verify_at_load");
  assert.equal(ontario.blocked, true);
  const britishColumbia = statutoryNotice(standards.jurisdictions.BC.termination_notice, { years: 4, months: 0 }, false);
  assert.equal(britishColumbia.weeks, 4);
  assert.equal(britishColumbia.blocked, true);
  const below = statutoryNotice(standards.jurisdictions.ON.termination_notice, { years: 0, months: 1 }, false);
  assert.equal(below.weeks, 0);
  assert.equal(below.matched, null);
  throws("RULE_NOT_VERIFIED", () => statutoryNotice(standards.jurisdictions.ON.termination_notice, { years: 6, months: 0 }, true));
  const checked = statutoryNotice({ ...standards.jurisdictions.ON.termination_notice, status: "checked" }, { years: 6, months: 0 }, true);
  assert.equal(checked.weeks, 6);
  assert.equal(checked.blocked, false);
});

test("OFF-003 Ontario and federal severance come from the separation file", () => {
  const ontario = separation.jurisdictions.ON.statutory_severance;
  const shown = statutorySeverance({
    rule: ontario,
    serviceYears: "6",
    serviceMonths: 72,
    employerPayroll: "2500000.00",
    qualifyingGroupTermination: false,
    apply: false,
  });
  assert.equal(shown.applies, true);
  assert.equal(shown.weeks, "6.00");
  assert.equal(shown.cite, "Employment Standards Act, 2000, ss. 63-65");
  assert.equal(shown.blocked, true);
  const capped = statutorySeverance({
    rule: { ...ontario, status: "checked" },
    serviceYears: "30",
    serviceMonths: 360,
    employerPayroll: "2500000.00",
    qualifyingGroupTermination: false,
    apply: true,
  });
  assert.equal(capped.weeks, "26.00");
  const part = statutorySeverance({
    rule: { ...ontario, status: "checked" },
    serviceYears: "5.5",
    serviceMonths: 66,
    employerPayroll: "2499999.99",
    qualifyingGroupTermination: true,
    apply: true,
  });
  assert.equal(part.weeks, "5.50");
  const short = statutorySeverance({
    rule: { ...ontario, status: "checked" },
    serviceYears: "4",
    serviceMonths: 48,
    employerPayroll: "9000000.00",
    qualifyingGroupTermination: false,
    apply: true,
  });
  assert.equal(short.applies, false);
  const lowPayroll = statutorySeverance({
    rule: { ...ontario, status: "checked" },
    serviceYears: "6",
    serviceMonths: 72,
    employerPayroll: "2499999.99",
    qualifyingGroupTermination: false,
    apply: true,
  });
  assert.equal(lowPayroll.applies, false);
  throws("RULE_NOT_VERIFIED", () =>
    statutorySeverance({
      rule: ontario,
      serviceYears: "6",
      serviceMonths: 72,
      employerPayroll: "2500000.00",
      qualifyingGroupTermination: false,
      apply: true,
    }),
  );
  const federal = separation.jurisdictions.FED.statutory_severance;
  const fed = statutorySeverance({
    rule: { ...federal, status: "checked" },
    serviceYears: "1",
    serviceMonths: 12,
    employerPayroll: "0.00",
    qualifyingGroupTermination: false,
    apply: true,
  });
  assert.equal(fed.applies, true);
  assert.equal(fed.days, "5.00");
  const longer = statutorySeverance({
    rule: { ...federal, status: "checked" },
    serviceYears: "4",
    serviceMonths: 48,
    employerPayroll: "0.00",
    qualifyingGroupTermination: false,
    apply: true,
  });
  assert.equal(longer.days, "8.00");
  const early = statutorySeverance({
    rule: { ...federal, status: "checked" },
    serviceYears: "0.5",
    serviceMonths: 6,
    employerPayroll: "0.00",
    qualifyingGroupTermination: false,
    apply: true,
  });
  assert.equal(early.applies, false);
  throws("RULE_NOT_VERIFIED", () =>
    statutorySeverance({
      rule: separation.jurisdictions.BC.statutory_severance,
      serviceYears: "6",
      serviceMonths: 72,
      employerPayroll: "0.00",
      qualifyingGroupTermination: false,
      apply: true,
    }),
  );
});

test("OFF-004 final pay deadlines and an off-cycle final run", () => {
  const ontario = separation.jurisdictions.ON.final_pay_deadline;
  const later = finalPayDeadline({
    rule: { ...ontario, status: "checked" },
    initiatedBy: "employer",
    endDate: "2027-03-15",
    nextRegularPayDay: "2027-03-20",
    apply: true,
  });
  assert.equal(later.deadline, "2027-03-22");
  assert.equal(later.offCycle, false);
  const payDay = finalPayDeadline({
    rule: { ...ontario, status: "checked" },
    initiatedBy: "employee",
    endDate: "2027-03-15",
    nextRegularPayDay: "2027-03-31",
    apply: true,
  });
  assert.equal(payDay.deadline, "2027-03-31");
  assert.equal(payDay.offCycle, false);
  const britishColumbia = separation.jurisdictions.BC.final_pay_deadline;
  const employer = finalPayDeadline({
    rule: { ...britishColumbia, status: "checked" },
    initiatedBy: "employer",
    endDate: "2027-03-15",
    nextRegularPayDay: "2027-03-20",
    apply: true,
  });
  assert.equal(employer.deadline, "2027-03-17");
  assert.equal(employer.offCycle, true);
  const quit = finalPayDeadline({
    rule: { ...britishColumbia, status: "checked" },
    initiatedBy: "employee",
    endDate: "2027-03-15",
    nextRegularPayDay: "2027-03-31",
    apply: true,
  });
  assert.equal(quit.deadline, "2027-03-21");
  assert.equal(quit.offCycle, true);
  const shown = finalPayDeadline({
    rule: ontario,
    initiatedBy: "employer",
    endDate: "2027-03-15",
    nextRegularPayDay: "2027-03-20",
    apply: false,
  });
  assert.equal(shown.deadline, "2027-03-22");
  assert.equal(shown.blocked, true);
  assert.equal(shown.cite, "Employment Standards Act, 2000, s. 11(5)");
  throws("RULE_NOT_VERIFIED", () =>
    finalPayDeadline({
      rule: ontario,
      initiatedBy: "employer",
      endDate: "2027-03-15",
      nextRegularPayDay: "2027-03-20",
      apply: true,
    }),
  );
  throws("RULE_NOT_VERIFIED", () =>
    finalPayDeadline({
      rule: separation.jurisdictions.FED.final_pay_deadline,
      initiatedBy: "employer",
      endDate: "2027-03-15",
      nextRegularPayDay: "2027-03-20",
      apply: true,
    }),
  );
});

function separationInput(overrides: Partial<SeparationInput> = {}): SeparationInput {
  const notice = { ...standards.jurisdictions.ON.termination_notice, status: "checked" };
  const severance = { ...separation.jurisdictions.ON.statutory_severance, status: "checked" };
  const deadline = { ...separation.jurisdictions.ON.final_pay_deadline, status: "checked" };
  const benefits = benefitCases.find((item) => item.id === "BEN-011");
  if (benefits === undefined) throw new Error("BEN-011 missing");
  const input: SeparationInput = {
    personId: "person-1",
    employmentId: "employment-1",
    reason: "termination_without_cause",
    initiatedBy: "employer",
    noticeDate: "2027-02-01",
    lastDayWorked: "2027-03-12",
    terminationDate: "2027-03-15",
    quebecWorkLocation: false,
    service: { years: 6, months: 0 },
    serviceYears: "6",
    serviceMonths: 72,
    employerPayroll: "2500000.00",
    qualifyingGroupTermination: false,
    vacationOwing: "840.50",
    nextRegularPayDay: "2027-03-20",
    assignments: [
      {
        assignmentId: "A1",
        personId: "person-1",
        employmentId: "employment-1",
        payrollAccountId: "CITY",
        leavePlanId: "VAC",
        positionId: "POS1",
      },
    ],
    positionHolders: [{ positionId: "POS1", assignmentId: "A1" }],
    futureChangeSetIds: ["future-raise"],
    notice,
    severance,
    deadline,
    benefits: {
      enrolment: benefits.input.enrolment,
      ending: benefits.input.ending,
      rules: benefits.input.rules,
      jurisdictionRules: benefits.input.jurisdictionRules,
      acknowledgement: null,
    },
    finalItems: [
      { code: "wages", amount: "1200.00", workStart: "2027-03-01", workEnd: "2027-03-12", kind: "wages" },
      { code: "ot", amount: "80.00", workStart: "2027-03-01", workEnd: "2027-03-12", kind: "overtime" },
      { code: "bank", amount: "40.00", workStart: "2027-03-01", workEnd: "2027-03-12", kind: "banked" },
      { code: "vac", amount: "840.50", workStart: "2027-03-01", workEnd: "2027-03-15", kind: "vacation" },
      { code: "hol", amount: "150.00", workStart: "2027-02-01", workEnd: "2027-02-28", kind: "holiday" },
      { code: "lieu", amount: "2100.00", workStart: "2027-03-16", workEnd: "2027-04-26", kind: "pay_in_lieu" },
      { code: "sev", amount: "4200.00", workStart: "2027-03-16", workEnd: "2027-06-07", kind: "severance" },
      {
        code: "retire",
        amount: "500.00",
        workStart: "2027-03-15",
        workEnd: "2027-03-15",
        kind: "retiring_allowance",
        rrspDirectTransfer: true,
      },
    ],
    recovery: { amount: "25.00", authorization: "25.00" },
    protectedMinimum: "500.00",
    gross: "9000.00",
    roe: {
      reasonMap: { termination_without_cause: "A", death: "K" },
      deadlineDays: 5,
      finalPayPeriodEnd: "2027-03-15",
      periods: [{ number: 1, amount: "1200.00", hours: "70" }],
      vacation: { block: "17A", amount: "840.50" },
      severance: { block: "17B", amount: "4200.00" },
      amended: false,
    },
    access: {
      dismissal: false,
      removeAt: "2027-03-15T17:00:00Z",
      now: "2027-03-15T12:00:00Z",
      equipment: [{ id: "laptop-1" }],
    },
    slipTreatment: null,
    screenLanguage: "en-CA",
  };
  return { ...input, ...overrides };
}

test("OFF-001 preview shows each figure and commit is one employment.terminate change set", () => {
  const preview = previewSeparation(separationInput());
  assert.equal(preview.notice.weeks, 6);
  assert.equal(preview.severance.weeks, "6.00");
  assert.equal(preview.vacationOwing, "840.50");
  assert.equal(preview.finalPay.deadline, "2027-03-22");
  assert.equal(preview.benefits.length, 1);
  const coverage = preview.benefits[0];
  assert.ok(coverage && "coverageUntil" in coverage);
  if (coverage && "coverageUntil" in coverage) assert.equal(coverage.coverageUntil, "2027-06-07");
  assert.equal(preview.blocked, false);
  const filed = previewSeparation(
    separationInput({
      notice: standards.jurisdictions.ON.termination_notice,
      severance: separation.jurisdictions.ON.statutory_severance,
      deadline: separation.jurisdictions.ON.final_pay_deadline,
    }),
  );
  assert.equal(filed.notice.weeks, 6);
  assert.equal(filed.blocked, true);
  throws("RULE_NOT_VERIFIED", () =>
    commitSeparation(
      separationInput({
        notice: standards.jurisdictions.ON.termination_notice,
      }),
    ),
  );
  const change = commitSeparation(separationInput());
  assert.equal(change.kind, "employment.terminate");
  assert.equal(change.events.join(","), "payroll,benefits,idp,offboarding_tasks");
  assert.deepEqual(change.positionsVacated, ["POS1"]);
  assert.deepEqual(change.cancelChangeSetIds, ["future-raise"]);
  assert.ok(change.operations.some((operation) => operation.op === "end_assignment" && operation.assignmentId === "A1"));
  assert.ok(change.operations.some((operation) => operation.op === "cancel_change_set"));
  assert.equal(change.roes.length, 1);
  assert.equal(change.roes[0]?.payrollAccountId, "CITY");
  assert.equal(change.offCycleFinal, false);
  assert.equal(change.finalItems.find((item) => item.kind === "retiring_allowance")?.rrspDirectTransfer, true);
  assert.equal(change.finalItems.find((item) => item.kind === "recovery")?.amount, "25.00");
});

test("OFF-005 a recovery needs a written authorization and stays above the protected minimum", () => {
  const items = [
    { code: "wages", amount: "1000", workStart: "2027-03-01", workEnd: "2027-03-12", kind: "wages" },
  ];
  throws("INPUT_REQUIRED", () =>
    finalPayItems({ items, recovery: { amount: "10.00", authorization: null }, protectedMinimum: "100.00", gross: "1000.00" }),
  );
  throws("RECOVERY_EXCEEDS_AUTHORIZATION", () =>
    finalPayItems({
      items,
      recovery: { amount: "40.00", authorization: "25.00" },
      protectedMinimum: "100.00",
      gross: "1000.00",
    }),
  );
  throws("RECOVERY_BELOW_PROTECTED_MINIMUM", () =>
    finalPayItems({
      items,
      recovery: { amount: "600.00", authorization: "600.00" },
      protectedMinimum: "500.00",
      gross: "1000.00",
    }),
  );
  const kept = finalPayItems({
    items,
    recovery: { amount: "100.00", authorization: "100.00" },
    protectedMinimum: "500.00",
    gross: "1000.00",
  });
  assert.equal(kept.find((item) => item.kind === "wages")?.amount, "1000.00");
  assert.equal(kept.find((item) => item.kind === "recovery")?.amount, "100.00");
});

test("OFF-006 a record of employment is drafted per payroll account and can be amended", () => {
  const first = draftRoe({
    payrollAccountId: "LIB",
    separationReason: "layoff",
    reasonMap: { layoff: "A" },
    periods: [{ number: 1, amount: "800", hours: "40" }],
    vacation: { block: "17A", amount: "100" },
    severance: { block: "17B", amount: "0" },
    deadlineDays: 5,
    finalPayPeriodEnd: "2027-03-15",
    amended: false,
  });
  assert.equal(first.reasonCode, "A");
  assert.equal(first.dueDate, "2027-03-20");
  assert.equal(first.blocks[0]?.block, "17A");
  assert.equal(first.blocks[1]?.block, "17B");
  assert.equal(first.periods[0]?.amount, "800.00");
  const amended = draftRoe({
    payrollAccountId: "LIB",
    separationReason: "layoff",
    reasonMap: { layoff: "A" },
    periods: [{ number: 1, amount: "810.00", hours: "40" }],
    vacation: { block: "17A", amount: "100.00" },
    severance: { block: "17B", amount: "0.00" },
    deadlineDays: 5,
    finalPayPeriodEnd: "2027-03-15",
    amended: true,
  });
  assert.equal(amended.amended, true);
  throws("REASON_UNMAPPED", () =>
    draftRoe({
      payrollAccountId: "LIB",
      separationReason: "other",
      reasonMap: { layoff: "A" },
      periods: [{ number: 1, amount: "1.00", hours: "1" }],
      vacation: { block: "17A", amount: "0.00" },
      severance: { block: "17B", amount: "0.00" },
      deadlineDays: 5,
      finalPayPeriodEnd: "2027-03-15",
      amended: false,
    }),
  );
});

test("OFF-007 group counts warn from a checked edition and the file itself is not verified", () => {
  throws("RULE_NOT_VERIFIED", () =>
    groupTerminations({
      rule: separation.jurisdictions.ON.group_termination,
      establishmentId: "plant",
      endings: [],
      asOf: "2027-03-15",
      proposed: 1,
      apply: true,
    }),
  );
  const quiet = groupTerminations({
    rule: { status: "checked", thresholds: { count: 3, within_weeks: 4 }, cite: "caller edition" },
    establishmentId: "plant",
    endings: [
      { establishmentId: "plant", date: "2027-03-01" },
      { establishmentId: "other", date: "2027-03-02" },
    ],
    asOf: "2027-03-15",
    proposed: 1,
    apply: true,
  });
  assert.equal(quiet.count, 1);
  assert.equal(quiet.warn, false);
  assert.equal(quiet.ministryForm, null);
  const warn = groupTerminations({
    rule: { status: "checked", thresholds: { count: 3, within_weeks: 4 }, cite: "caller edition" },
    establishmentId: "plant",
    endings: [
      { establishmentId: "plant", date: "2027-03-01" },
      { establishmentId: "plant", date: "2027-03-10" },
    ],
    asOf: "2027-03-15",
    proposed: 1,
    apply: true,
  });
  assert.equal(warn.count, 2);
  assert.equal(warn.threshold, 3);
  assert.equal(warn.warn, true);
  assert.ok(warn.ministryForm?.["en-CA"].includes("ministry"));
  assert.ok(warn.ministryForm?.["fr-CA"].includes("ministère"));
});

test("OFF-008 a layoff keeps the recall date and alerts before the checked deemed date", () => {
  throws("RULE_NOT_VERIFIED", () =>
    recordLayoff({
      rule: separation.jurisdictions.ON.temporary_layoff,
      startDate: "2027-01-04",
      expectedRecallDate: "2027-03-01",
      asOf: "2027-03-25",
      alertLeadDays: 10,
      separationReason: "layoff",
      reasonMap: { layoff: "A" },
      apply: true,
    }),
  );
  const laid = recordLayoff({
    rule: { status: "checked", max_weeks: 13, cite: "caller edition" },
    startDate: "2027-01-01",
    expectedRecallDate: "2027-03-01",
    asOf: "2027-03-25",
    alertLeadDays: 10,
    separationReason: "layoff",
    reasonMap: { layoff: "A" },
    apply: true,
  });
  assert.equal(laid.expectedRecallDate, "2027-03-01");
  assert.equal(laid.deemedOn, "2027-04-02");
  assert.equal(laid.alert, true);
  assert.equal(laid.roeReasonCode, "A");
  const early = recordLayoff({
    rule: { status: "checked", max_weeks: 13, cite: "caller edition" },
    startDate: "2027-01-01",
    expectedRecallDate: "2027-03-01",
    asOf: "2027-03-01",
    alertLeadDays: 10,
    separationReason: "layoff",
    reasonMap: { layoff: "A" },
    apply: true,
  });
  assert.equal(early.alert, false);
});

test("OFF-009 bumping options follow seniority and qualifications, and recall uses the agreement's days", () => {
  const options = bumpingOptions({
    employeeSeniority: "10",
    qualifications: ["a", "b"],
    grouping: "clerical",
    positions: [
      { positionId: "P2", incumbentSeniority: "8", requiredQualifications: ["a", "b"], grouping: "clerical" },
      { positionId: "P1", incumbentSeniority: null, requiredQualifications: ["a"], grouping: "clerical" },
      { positionId: "P3", incumbentSeniority: "12", requiredQualifications: ["a"], grouping: "clerical" },
      { positionId: "P4", incumbentSeniority: "4", requiredQualifications: ["c"], grouping: "clerical" },
      { positionId: "P5", incumbentSeniority: null, requiredQualifications: ["a"], grouping: "other" },
    ],
  });
  assert.deepEqual(
    options.map((option) => option.positionId),
    ["P1", "P2"],
  );
  const offer = recordBump({ positionId: "P2", offerDate: "2027-03-01", response: "declined", recallDays: 90 });
  assert.equal(offer.response, "declined");
  assert.equal(offer.recallExpiry, "2027-05-30");
});

test("OFF-010 PLAT-013 access is removed at the set time, immediately on dismissal, and late after five minutes", () => {
  const onTime = scheduleAccessRemoval({
    dismissal: false,
    removeAt: "2027-03-15T17:00:00Z",
    now: "2027-03-15T17:04:00Z",
    equipment: [{ id: "laptop-1" }],
  });
  assert.equal(onTime.removed, true);
  assert.equal(onTime.late, false);
  assert.equal(onTime.assetTasks[0]?.equipmentId, "laptop-1");
  assert.ok(onTime.assetTasks[0]?.["fr-CA"].includes("équipement"));
  const exact = scheduleAccessRemoval({
    dismissal: false,
    removeAt: "2027-03-15T17:00:00Z",
    now: "2027-03-15T17:05:00Z",
    equipment: [],
  });
  assert.equal(exact.removed, true);
  assert.equal(exact.late, false);
  const late = scheduleAccessRemoval({
    dismissal: false,
    removeAt: "2027-03-15T17:00:00Z",
    now: "2027-03-15T17:06:00Z",
    equipment: [],
  });
  assert.equal(late.removed, true);
  assert.equal(late.late, true);
  const waiting = scheduleAccessRemoval({
    dismissal: false,
    removeAt: "2027-03-15T17:00:00Z",
    now: "2027-03-15T16:00:00Z",
    equipment: [],
  });
  assert.equal(waiting.removed, false);
  const dismissal = scheduleAccessRemoval({
    dismissal: true,
    removeAt: "2027-03-15T17:00:00Z",
    now: "2027-03-15T09:00:00Z",
    equipment: [{ id: "keys" }],
  });
  assert.equal(dismissal.removed, true);
  assert.equal(dismissal.late, false);
  assert.equal(dismissal.removeAt, "2027-03-15T09:00:00Z");
});

test("OFF-011 death pays the estate and does not guess the slip", () => {
  throws("INPUT_REQUIRED", () => deathPayments({ slipTreatment: null, screenLanguage: "en-CA" }));
  const paid = deathPayments({ slipTreatment: "estate", screenLanguage: "fr-CA" });
  assert.equal(paid.payee, "estate");
  assert.equal(paid.slipTreatment, "estate");
  assert.equal(paid.benefitsClaim, true);
  assert.ok(paid.template.includes("succession"));
  const change = commitSeparation(
    separationInput({
      reason: "death",
      slipTreatment: "T4",
      roe: {
        reasonMap: { death: "K", termination_without_cause: "A" },
        deadlineDays: 5,
        finalPayPeriodEnd: "2027-03-15",
        periods: [{ number: 1, amount: "100.00", hours: "10" }],
        vacation: { block: "17A", amount: "0.00" },
        severance: { block: "17B", amount: "0.00" },
        amended: false,
      },
    }),
  );
  assert.equal(change.death?.payee, "estate");
  assert.equal(change.death?.slipTreatment, "T4");
  assert.equal(change.roes[0]?.reasonCode, "K");
});

test("OFF-012 letters are in English and French, and Quebec requires French", () => {
  const english = terminationDocument({
    kind: "letter",
    screenLanguage: "en-CA",
    quebecWorkLocation: false,
    terminationDate: "2027-03-15",
  });
  assert.equal(english.language, "en-CA");
  assert.ok(english.text.includes("2027-03-15"));
  const french = terminationDocument({
    kind: "release",
    screenLanguage: "fr-CA",
    quebecWorkLocation: true,
    terminationDate: "2027-03-15",
  });
  assert.ok(french.text.includes("quittance"));
  const reference = terminationDocument({
    kind: "reference",
    screenLanguage: "fr-CA",
    quebecWorkLocation: false,
    terminationDate: "2027-03-15",
  });
  assert.ok(reference.text.includes("référence"));
  throws("FRENCH_REQUIRED_FOR_QUEBEC", () =>
    terminationDocument({
      kind: "letter",
      screenLanguage: "en-CA",
      quebecWorkLocation: true,
      terminationDate: "2027-03-15",
    }),
  );
});

test("ENT-016 one assignment ends and earnings continue on the same account", () => {
  const effects = endAssignment({
    interruptionDays: 7,
    ended: {
      assignmentId: "A1",
      personId: "jordan",
      employmentId: "city",
      payrollAccountId: "CITY",
      leavePlanId: "VAC-A",
      positionId: "POS1",
      nextEarningsDate: "2027-03-31",
      weeklyHours: "20.00",
      endDate: "2027-03-31",
    },
    remaining: [
      {
        assignmentId: "A2",
        personId: "jordan",
        employmentId: "city",
        payrollAccountId: "CITY",
        leavePlanId: "VAC-B",
        positionId: "POS2",
        nextEarningsDate: "2027-04-07",
        weeklyHours: "20.00",
      },
    ],
    positionHolders: [{ positionId: "POS2", assignmentId: "A2" }],
    continuingDuesObligation: false,
    hoursDropShare: "0.25",
    constructiveDismissal: false,
    layoff: false,
  });
  assert.deepEqual(effects.roes, []);
  assert.equal(effects.leaveSettles, true);
  assert.equal(effects.benefitsReevaluated, true);
  assert.equal(effects.positionVacated, true);
  assert.equal(effects.duesStopped, true);
  assert.equal(effects.hoursDropReview, true);
  assert.equal(effects.statutoryNoticeTriggered, false);
  assert.equal(effects.changeSetKind, "assignment.end");
  assert.equal(effects.futureShiftsCancelled, true);
});

test("ENT-017 the library account gets a record of employment and the city job stays", () => {
  const effects = endAssignment({
    interruptionDays: 7,
    ended: {
      assignmentId: "A3",
      personId: "jordan",
      employmentId: "library",
      payrollAccountId: "LIB",
      leavePlanId: "VAC-L",
      positionId: "POS3",
      nextEarningsDate: "2027-03-31",
      weeklyHours: "15.00",
      endDate: "2027-03-31",
    },
    remaining: [
      {
        assignmentId: "A1",
        personId: "jordan",
        employmentId: "city",
        payrollAccountId: "CITY",
        leavePlanId: "VAC-C",
        positionId: "POS1",
        nextEarningsDate: "2027-04-01",
        weeklyHours: "35.00",
      },
    ],
    positionHolders: [
      { positionId: "POS3", assignmentId: "A3" },
      { positionId: "POS1", assignmentId: "A1" },
    ],
    continuingDuesObligation: false,
    hoursDropShare: "0.90",
    constructiveDismissal: false,
    layoff: false,
  });
  assert.deepEqual(effects.roes, [{ personId: "jordan", payrollAccountId: "LIB" }]);
  assert.equal(effects.changeSetKind, "employment.terminate");
  assert.equal(effects.positionVacated, true);
  assert.equal(effects.benefitsReevaluated, true);
});

test("ENT-031 a transfer to another employer opens a new employment and carries seniority only when configured", () => {
  const plain = transferEmployer({ fromPayrollAccountId: "CITY", toPayrollAccountId: "POLICE", carrySeniority: false });
  assert.equal(plain.newEmployment, true);
  assert.equal(plain.newPayrollAccountId, "POLICE");
  assert.equal(plain.roePayrollAccountId, "CITY");
  assert.equal(plain.seniorityCarried, false);
  const carried = transferEmployer({ fromPayrollAccountId: "CITY", toPayrollAccountId: "POLICE", carrySeniority: true });
  assert.equal(carried.seniorityCarried, true);
});

test("BEN-034 British Columbia waits for the common-law caution and Ontario does not", () => {
  const britishColumbia = benefitCases.find((item) => item.id === "BEN-003");
  const ontario = benefitCases.find((item) => item.id === "BEN-011");
  const unverified = benefitCases.find((item) => item.id === "BEN-008");
  if (britishColumbia === undefined || ontario === undefined || unverified === undefined) throw new Error("case missing");
  throws("CAUTION_NOT_ACKNOWLEDGED", () =>
    decideBenefitEnd(
      britishColumbia.input.enrolment,
      britishColumbia.input.ending,
      britishColumbia.input.rules,
      britishColumbia.input.jurisdictionRules,
      null,
    ),
  );
  throws("INPUT_REQUIRED", () =>
    decideBenefitEnd(
      britishColumbia.input.enrolment,
      britishColumbia.input.ending,
      britishColumbia.input.rules,
      britishColumbia.input.jurisdictionRules,
      { caution: "benefits.common_law_notice", reason: "  " },
    ),
  );
  const decided = decideBenefitEnd(
    britishColumbia.input.enrolment,
    britishColumbia.input.ending,
    britishColumbia.input.rules,
    britishColumbia.input.jurisdictionRules,
    { caution: "benefits.common_law_notice", reason: "Counsel confirmed the end date." },
  );
  assert.ok(decided.warnings.includes("COMMON_LAW_REVIEW"));
  const kept = decideBenefitEnd(
    ontario.input.enrolment,
    ontario.input.ending,
    ontario.input.rules,
    ontario.input.jurisdictionRules,
    null,
  );
  assert.equal(kept.coverageUntil, "2027-06-07");
  assert.deepEqual(kept.warnings, []);
  throws("CAUTION_NOT_ACKNOWLEDGED", () =>
    decideBenefitEnd(
      unverified.input.enrolment,
      unverified.input.ending,
      unverified.input.rules,
      unverified.input.jurisdictionRules,
      null,
    ),
  );
});
