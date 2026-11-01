import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { PayrollError } from "@candohr/payroll-engine";
import {
  PayRunError,
  activateGarnishment,
  advancePayRun,
  applyPostTaxDeductions,
  approvePayRun,
  approveVoluntaryDeduction,
  approveWithHolds,
  assertRulePin,
  assignBuckets,
  bucketCountFor,
  bucketMessages,
  changeStatutoryEdition,
  controlTotals,
  createPayGroup,
  dayEarnings,
  draftWarnings,
  excludeCoveredDays,
  explain,
  finalizeLiveRun,
  distributeLargestRemainder,
  fiscalShares,
  leaseSubjects,
  loadStarterCodes,
  offCycleForHold,
  paySubject,
  pinInputs,
  planPayDate,
  providerAccess,
  reconcileOpening,
  recoverAdvance,
  reviewRun,
  saveDeductionCode,
  saveOneTimePayment,
  segmentDays,
  simulatePay,
  stackPremiums,
  statementRange,
  taxMethodFor,
  taxYearOf,
  vacationRuleFor,
  writeOffArrears,
  ytdAmount,
  ytdWritesOn,
} from "../src/index.ts";

const samplePay = {
  province: "ON",
  pay_date: "2026-03-13",
  P: 52,
  I: 1000,
  B: 0,
  PM: 12,
  apply_cpp_exemption: true,
};

function code(run: () => unknown): string {
  try {
    run();
  } catch (error) {
    if (error instanceof PayRunError) return error.code;
    throw error;
  }
  return "";
}

test("PAY-060 approval names an approver, a complete route, and not the preparer", () => {
  assert.equal(code(() => approvePayRun({ createdBy: "a", routeComplete: true })), "INPUT_REQUIRED");
  assert.equal(code(() => approvePayRun({ createdBy: "a", approver: "b", routeComplete: false })), "ROUTE_APPROVALS_MISSING");
  assert.equal(code(() => approvePayRun({ createdBy: "a", approver: "a", routeComplete: true })), "SELF_APPROVAL");
  assert.equal(approvePayRun({ createdBy: "a", approver: "finance", routeComplete: true }), "approved");
});

test("PAY-061 and PAY-062 a failed check holds one person, or stops the run", () => {
  const review = reviewRun({
    personIds: ["ana", "ben"],
    failed: [{ personId: "ben", checkCode: "NO_BANK_ACCOUNT", reason: "No bank account" }],
  });
  assert.deepEqual(review.paidPersonIds, ["ana"]);
  assert.equal(review.holds[0]?.reason, "No bank account");
  const offCycle = offCycleForHold({ holdRunId: "run-1", personId: "ben" });
  assert.equal(offCycle.releasedInRunId, "run-1");
  assert.equal(approveWithHolds({ policy: "hold_employee", openHolds: 1 }), "approved");
  assert.equal(code(() => approveWithHolds({ policy: "stop_run", openHolds: 1 })), "PAY_RUN_HAS_FAILED_CHECKS");
  assert.equal(approveWithHolds({ policy: "stop_run", openHolds: 0 }), "approved");
});

test("PAY-063 Saturday 26 December 2026 and a bank holiday move to the previous banking day", () => {
  const saturday = planPayDate("2026-12-26");
  assert.equal(saturday.payDate, "2026-12-24");
  assert.equal(saturday.moved, true);
  assert.equal(saturday.crossesPriorYear, false);
  const canadaDay = planPayDate("2026-07-01");
  assert.equal(canadaDay.payDate, "2026-06-30");
  const newYear = planPayDate("2027-01-01");
  assert.equal(newYear.payDate, "2026-12-31");
  assert.equal(newYear.crossesPriorYear, true);
});

test("PAY-064 the first live run waits for an accepted parallel run", () => {
  assert.equal(code(() => finalizeLiveRun({ firstLive: true, parallelAccepted: false, differencesAccepted: false })), "PARALLEL_RUN_REQUIRED");
  assert.equal(code(() => finalizeLiveRun({ firstLive: true, parallelAccepted: true, differencesAccepted: false })), "PARALLEL_RUN_REQUIRED");
  assert.equal(finalizeLiveRun({ firstLive: true, parallelAccepted: true, differencesAccepted: true }), "finalized");
  assert.equal(finalizeLiveRun({ firstLive: false, parallelAccepted: false, differencesAccepted: false }), "finalized");
});

test("PAY-065 a provider is limited to what the client approved", () => {
  assert.equal(code(() => providerAccess({ capabilityKnown: false, clientApproved: true, approverIsProvider: false })), "PROVIDER_CAPABILITY_UNKNOWN");
  assert.equal(code(() => providerAccess({ capabilityKnown: true, clientApproved: false, approverIsProvider: false })), "PROVIDER_GRANT_NOT_CLIENT");
  assert.equal(code(() => providerAccess({ capabilityKnown: true, clientApproved: false, approverIsProvider: true })), "SELF_APPROVAL");
  assert.equal(providerAccess({ capabilityKnown: true, clientApproved: true, approverIsProvider: false }), "allowed");
});

test("PAY-066 and PAY-067 vacation pay follows the position, and a missing rule is named", () => {
  const rules = [
    { id: "casual", scope: { employmentType: "casual" }, rate: "0.04" },
    { id: "permanent", scope: { employmentType: "permanent" }, rate: "0.06" },
  ];
  assert.equal(vacationRuleFor(rules, { employmentType: "casual" }).rate, "0.04");
  assert.equal(vacationRuleFor(rules, { employmentType: "permanent" }).rate, "0.06");
  assert.equal(code(() => vacationRuleFor([], { employmentType: "casual" })), "VACATION_PAY_RULE_MISSING");
  assert.equal(code(() => vacationRuleFor(rules, { employmentType: "unknown" })), "PAYROLL_SCOPE_UNKNOWN");
});

test("PAY-068 a pay group waits until proration is chosen", () => {
  assert.equal(code(() => createPayGroup({})), "SETTING_NOT_SET");
  assert.equal(createPayGroup({ prorationMethod: "working_days" }).prorationMethod, "working_days");
});

test("PAY-070 only verified starter codes are copied", () => {
  const file = JSON.parse(readFileSync(fileURLToPath(new URL("../../../rules/payroll/starter-pay-codes.json", import.meta.url)), "utf8")) as {
    codes: { pay_code: string; status: string }[];
  };
  const loaded = loadStarterCodes([...file.codes, { pay_code: "REG-OK", status: "verified" }]);
  assert.deepEqual(loaded.copied.map((code) => code.pay_code), ["REG-OK"]);
  assert.equal(loaded.forPayroll.length, file.codes.length);
  assert.ok(loaded.forPayroll.every((code) => code.status === "verify_at_load"));
});

test("PAY-071 an unresolved premium combination holds the employee", () => {
  const held = stackPremiums({ combined: false });
  assert.notEqual(held, "ok");
  if (held !== "ok") assert.equal(held.checkCode, "UNRESOLVED_INTERACTION");
});

test("PAY-072 a support order stays inactive until payroll confirms it", () => {
  assert.equal(code(() => activateGarnishment({ confirmed: false })), "GARNISHMENT_NOT_CONFIRMED");
  assert.equal(activateGarnishment({ confirmed: true }), "active");
});

test("PAY-073 a voluntary deduction is a deduction and the employee cannot approve it", () => {
  assert.equal(code(() => approveVoluntaryDeduction({ kind: "earning", employeeId: "e", approverId: "payroll" })), "PAY_CODE_NOT_DEDUCTION");
  assert.equal(code(() => approveVoluntaryDeduction({ kind: "deduction", employeeId: "e", approverId: "e" })), "SELF_APPROVAL");
  assert.equal(approveVoluntaryDeduction({ kind: "deduction", employeeId: "e", approverId: "payroll" }), "approved");
});

test("PAY-074 a deduction needs a shortfall rule, and a write-off needs a reason", () => {
  assert.equal(code(() => saveDeductionCode({})), "INPUT_REQUIRED");
  assert.equal(saveDeductionCode({ shortfall: "spread" }), "saved");
  assert.equal(code(() => writeOffArrears({})), "INPUT_REQUIRED");
  assert.equal(writeOffArrears({ reason: "Statute barred" }), "written_off");
});

test("PAY-075 deductions keep the protected minimum and record the shortfall", () => {
  const outcome = applyPostTaxDeductions({
    netAfterTax: "200.00",
    protectedMinimum: "100.00",
    deductions: [
      { code: "charity", amount: "40.00", rank: "organization", shortfall: "drop" },
      { code: "parking", amount: "50.00", rank: "organization", shortfall: "spread", spreadPeriods: 3 },
      { code: "support", amount: "80.00", rank: "support", shortfall: "spread", spreadPeriods: 1 },
    ],
  });
  assert.equal(outcome.taken.find((item) => item.code === "support")?.amount, "80.00");
  assert.equal(outcome.taken.find((item) => item.code === "parking")?.amount, "20.00");
  assert.equal(outcome.taken.find((item) => item.code === "charity")?.amount, "0.00");
  assert.equal(outcome.net, "100.00");
  assert.deepEqual(outcome.arrears, [{ code: "parking", amount: "30.00", periods: 3 }]);
});

test("PAY-076 a recovery needs an authorization and cannot pass it", () => {
  assert.equal(code(() => recoverAdvance({ alreadyRecovered: "0.00", amount: "150.00" })), "RECOVERY_NOT_AUTHORIZED");
  assert.equal(recoverAdvance({ authorized: "300.00", alreadyRecovered: "150.00", amount: "150.00" }), "ok");
  assert.equal(code(() => recoverAdvance({ authorized: "300.00", alreadyRecovered: "300.00", amount: "50.00" })), "RECOVERY_ABOVE_AUTHORIZED");
});

test("PAY-080 a one-time payment for several positions names one of them", () => {
  assert.equal(code(() => saveOneTimePayment({ positionCount: 2 })), "INPUT_REQUIRED");
  assert.equal(saveOneTimePayment({ positionCount: 2, positionId: "p1" }), "saved");
  assert.equal(saveOneTimePayment({ positionCount: 1 }), "saved");
});

test("PAY-081 and ENT-018 imported YTD stays on its payroll account", () => {
  const edition = JSON.parse(
    readFileSync(fileURLToPath(new URL("../../../rules/statutory/ca-2026-01-01.json", import.meta.url)), "utf8"),
  ) as { cpp: { max_employee_contribution: number } };
  const atCeiling = edition.cpp.max_employee_contribution;
  const first = paySubject({ ...samplePay, D_cpp_ytd: atCeiling, D1_ei_ytd: 0 });
  const second = paySubject({ ...samplePay, D_cpp_ytd: 0, D1_ei_ytd: 0 });
  assert.notEqual(first.hash, second.hash);
  assert.equal(first.result.cpp_employee > second.result.cpp_employee, false);
  const rows = [
    { personId: "jordan", payrollAccountId: "city", code: "CPP", amount: "40.00" },
    { personId: "jordan", payrollAccountId: "city", code: "CPP", amount: "10.00" },
    { personId: "jordan", payrollAccountId: "library", code: "CPP", amount: "80.00" },
  ];
  assert.equal(ytdAmount(rows, "jordan", "city", "CPP"), "50.00");
  assert.equal(ytdAmount(rows, "jordan", "library", "CPP"), "80.00");
});

test("PAY-086 an active statutory edition cannot be edited", () => {
  assert.equal(code(() => changeStatutoryEdition({ status: "active", contentChanged: true, editionId: "CA-2026", source: "CRA T4127" })), "STATUTORY_EDITION_LOCKED");
  const shown = changeStatutoryEdition({ status: "draft", contentChanged: true, editionId: "CA-2026", source: "CRA T4127" });
  assert.equal(shown.source, "CRA T4127");
});

test("ENT-015 distributed amounts add up to the line", () => {
  const shares = distributeLargestRemainder("100.00", [
    { key: "operating", weight: "1" },
    { key: "grant", weight: "1" },
    { key: "other", weight: "1" },
  ]);
  const total = shares.reduce((sum, share) => sum + Number(share.amount), 0);
  assert.equal(total.toFixed(2), "100.00");
  assert.deepEqual(shares.map((share) => share.amount).sort(), ["33.33", "33.33", "33.34"]);
});

test("ENT-028 days before cut-over are left out, and opening YTD must match", () => {
  assert.deepEqual(excludeCoveredDays(["2026-06-28", "2026-06-29", "2026-06-30", "2026-07-01"], "2026-07-01"), ["2026-07-01"]);
  assert.equal(reconcileOpening([{ amount: "10.00" }, { amount: "5.50" }], "15.50"), "reconciled");
  assert.throws(() => reconcileOpening([{ amount: "10.00" }], "15.50"));
});

test("docs/06 tests 11 to 14 pin inputs, pins, buckets, and leases", () => {
  const inputs = { rate: "20.00" };
  const pinned = pinInputs(inputs);
  inputs.rate = "25.00";
  assert.equal(pinInputs({ rate: "20.00" }).snapshotSha256, pinned.snapshotSha256);
  assert.notEqual(pinInputs(inputs).snapshotSha256, pinned.snapshotSha256);

  const population = Array.from({ length: 3 }, (_unused, index) => ({
    payrollAccountId: "account",
    personId: `00000000-0000-4000-8000-00000000000${index}`,
  }));
  const one = paySubject(samplePay).hash;
  const wide = assignBuckets(population, 1);
  const narrow = assignBuckets(population, 100);
  assert.equal(bucketCountFor(2000), 4);
  assert.equal(bucketCountFor(50000), 100);
  assert.equal(bucketCountFor(200000), 256);
  assert.equal(bucketMessages("run", 2).length, 2);
  assert.equal(wide.size, 1);
  assert.equal(narrow.size, 100);
  assert.equal(one, paySubject(samplePay).hash);

  assert.throws(
    () =>
      leaseSubjects(
        [{ payRunId: "regular", payrollAccountId: "account", personId: "ana", released: false, simulation: false }],
        { payRunId: "off-cycle", simulation: false, subjects: [{ payrollAccountId: "account", personId: "ana" }] },
      ),
    (error: unknown) => error instanceof PayRunError && error.code === "SUBJECT_IN_OPEN_RUN" && error.blockingRunId === "regular",
  );
  assert.deepEqual(
    leaseSubjects(
      [{ payRunId: "regular", payrollAccountId: "account", personId: "ana", released: false, simulation: false }],
      { payRunId: "sim", simulation: true, subjects: [{ payrollAccountId: "account", personId: "ana" }] },
    ),
    [],
  );
});

test("PAY-010 a regular run follows the route and the totals match the results", () => {
  let status: "draft" | "inputs_locked" | "calculated" | "reviewed" | "approved" | "finalized" = "draft";
  const actor = { createdBy: "preparer", approver: "finance", routeComplete: true };
  status = advancePayRun({ status, to: "inputs_locked", ...actor });
  status = advancePayRun({ status, to: "calculated", ...actor });
  status = advancePayRun({ status, to: "reviewed", ...actor });
  status = advancePayRun({ status, to: "approved", ...actor });
  status = advancePayRun({ status, to: "finalized", ...actor });
  assert.equal(status, "finalized");
  assert.equal(code(() => advancePayRun({ status: "reviewed", to: "approved", createdBy: "preparer", approver: "preparer", routeComplete: true })), "SELF_APPROVAL");
  assert.deepEqual(controlTotals([{ gross: "1000.00", net: "750.10" }, { gross: "20.50", net: "20.50" }]), {
    employees: 2,
    gross: "1020.50",
    net: "770.60",
  });
});

test("PAY-011 one day of hours uses that day's rate and the edition for the pay date", () => {
  assert.equal(dayEarnings("8", "25.50"), "204.00");
  const paid = paySubject({ ...samplePay, pay_date: "2026-11-05", I: 204, P: 26 });
  assert.equal(paid.result.edition.startsWith("CA-2026"), true);
  assert.equal(taxYearOf("2026-11-05"), 2026);
});

test("PAY-012 a raise on day 6 is a second segment", () => {
  const days = Array.from({ length: 14 }, (_unused, index) => {
    const date = new Date(Date.UTC(2026, 10, 2 + index)).toISOString().slice(0, 10);
    return { date, rate: index < 5 ? "20.00" : "22.00", positionId: "p" };
  });
  const segments = segmentDays(days);
  assert.equal(segments.length, 2);
  assert.equal(segments[0]?.rate, "20.00");
  assert.equal(segments[1]?.rate, "22.00");
  assert.equal(segments[0]?.end < segments[1]!.start, true);
});

test("PAY-013 January pay of December work uses the pay date's year, and a missing edition stops", () => {
  assert.equal(taxYearOf("2027-01-08"), 2027);
  assert.throws(() => paySubject({ ...samplePay, pay_date: "2027-01-08" }), (error: unknown) => error instanceof PayrollError);
});

test("PAY-014 a period that crosses 31 March splits the amount by fiscal year", () => {
  const days = ["2026-03-25", "2026-03-31", "2026-04-01", "2026-04-07"].map((date) => ({ date }));
  const shares = fiscalShares("100.00", days, 3);
  assert.deepEqual(
    shares.map((share) => share.key),
    ["2026", "2027"],
  );
  const total = shares.reduce((sum, share) => sum + Number(share.amount), 0);
  assert.equal(total.toFixed(2), "100.00");
});

test("PAY-015 an off-cycle bonus does not take a second CPP exemption", () => {
  assert.equal(taxMethodFor("bonus"), "non_periodic");
  const cases = JSON.parse(readFileSync(fileURLToPath(new URL("../../../tests/payroll/cases.json", import.meta.url)), "utf8")) as {
    cases: { id: string; input: Record<string, unknown> }[];
  };
  const fixture = cases.cases.find((entry) => entry.id === "bonus-only-offcycle-AB");
  assert.ok(fixture);
  assert.equal(fixture.input.apply_cpp_exemption, false);
  const noSecond = paySubject(fixture.input);
  const secondExemption = paySubject({ ...fixture.input, apply_cpp_exemption: true });
  assert.equal(Number(noSecond.result.cpp_employee) > Number(secondExemption.result.cpp_employee), true);
});

test("PAY-016 a simulation writes no year-to-date and takes no lease", () => {
  const preview = simulatePay(samplePay);
  assert.equal(preview.ytdWritten, false);
  assert.deepEqual(preview.leases, []);
  assert.equal(preview.result.edition.length > 0, true);
});

test("PAY-017 twenty-seven periods use the engine's truncated CPP exemption", () => {
  const result = paySubject({ ...samplePay, P: 27, I: 1000 });
  const exemption = result.result.trace.find((entry) => entry[0] === "CPP.exemption_per_period")?.[1];
  assert.equal(exemption, "129.62");
});

test("PAY-018 the same people produce the same fingerprints in one bucket or many", () => {
  const population = Array.from({ length: 20 }, (_unused, index) => ({
    payrollAccountId: "account",
    personId: `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
  }));
  const wide = assignBuckets(population, 1);
  const narrow = assignBuckets(population, 100);
  const hashes = new Map<string, string>();
  for (const subject of population) {
    hashes.set(subject.personId, paySubject({ ...samplePay, I: 1000 + population.indexOf(subject) }).hash);
  }
  const fromWide = [...wide.values()].flat().map((subject) => hashes.get(subject.personId));
  const fromNarrow = [...narrow.values()].flat().map((subject) => hashes.get(subject.personId));
  assert.deepEqual(fromWide.sort(), fromNarrow.sort());
  assert.equal(ytdWritesOn("calculated"), false);
  assert.equal(ytdWritesOn("cancelled"), false);
  assert.equal(ytdWritesOn("finalized"), true);
  const first = statementRange(0, 100);
  const second = statementRange(1, 100);
  assert.equal(first.end < second.start, true);
});

test("PAY-019 a draft names the open run, and two accounts are two subjects", () => {
  const open = [
    { payRunId: "regular", payrollAccountId: "city", personId: "ana", released: false, simulation: false },
  ];
  assert.equal(draftWarnings(open, [{ payrollAccountId: "city", personId: "ana" }])[0]?.blockingRunId, "regular");
  assert.deepEqual(draftWarnings(open, [{ payrollAccountId: "library", personId: "ana" }]), []);
  assert.equal(
    code(() =>
      leaseSubjects(open, { payRunId: "off-cycle", simulation: false, subjects: [{ payrollAccountId: "city", personId: "ana" }] }),
    ),
    "SUBJECT_IN_OPEN_RUN",
  );
  assert.deepEqual(
    leaseSubjects(open, { payRunId: "library-run", simulation: false, subjects: [{ payrollAccountId: "library", personId: "ana" }] }).map(
      (lease) => lease.payrollAccountId,
    ),
    ["library"],
  );
});

test("PAY-030 statutory deductions, then support, then the organization's order", () => {
  const outcome = applyPostTaxDeductions({
    netAfterTax: "200.00",
    protectedMinimum: "100.00",
    deductions: [
      { code: "parking", amount: "40.00", rank: "organization", shortfall: "drop" },
      { code: "support", amount: "80.00", rank: "support", shortfall: "spread", spreadPeriods: 1 },
      { code: "tax", amount: "50.00", rank: "statutory", shortfall: "spread", spreadPeriods: 1 },
    ],
  });
  assert.equal(outcome.taken.find((item) => item.code === "tax")?.amount, "50.00");
  assert.equal(outcome.taken.find((item) => item.code === "support")?.amount, "50.00");
  assert.equal(outcome.taken.find((item) => item.code === "parking")?.amount, "0.00");
  assert.equal(outcome.net, "100.00");
});

test("PAY-052 a worker stops when the loaded rule hash is not the pin", () => {
  const pinned = pinInputs({ rate: "20.00" });
  assert.equal(assertRulePin(pinned.snapshotSha256, pinned.snapshotSha256), undefined);
  assert.equal(code(() => assertRulePin(pinned.snapshotSha256, pinInputs({ rate: "21.00" }).snapshotSha256)), "RULE_HASH_MISMATCH");
});

test("a raise splits the period, and a bonus uses the non-periodic method", () => {
  const segments = segmentDays([
    { date: "2026-11-02", rate: "20.00", positionId: "p" },
    { date: "2026-11-03", rate: "20.00", positionId: "p" },
    { date: "2026-11-04", rate: "22.00", positionId: "p" },
  ]);
  assert.equal(segments.length, 2);
  assert.equal(segments[1]?.rate, "22.00");
  assert.equal(taxMethodFor("regular"), "periodic");
  assert.equal(taxMethodFor("bonus"), "non_periodic");
  const result = paySubject(samplePay).result;
  assert.ok(explain(result).some((entry) => entry[0] === "edition"));
});
