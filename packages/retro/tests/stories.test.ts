import assert from "node:assert/strict";
import test from "node:test";
import {
  RETRO_BATCH_SIZE,
  blockEngine,
  changeAfterLock,
  chargeRetro,
  compareReplay,
  dayNumber,
  earningsTotal,
  emptySnapshot,
  isEligible,
  payRetro,
  planBatches,
  processBatch,
  progressView,
  provinceMoveRetro,
  replaySample,
  retroAfterRuleActivation,
  retroFromAgreement,
  retroFromChangeSet,
  reverseResult,
  wasPaidSource,
  type ComparedPeriod,
  type EmployeeForRetro,
  type MoneySnapshot,
} from "../src/index.ts";

function snapshot(amount: string, extras?: Partial<MoneySnapshot>): MoneySnapshot {
  return {
    lines: [{ payCode: "REG", amount }],
    pensionable: extras?.pensionable ?? amount,
    insurable: extras?.insurable ?? amount,
    pension: extras?.pension ?? "0.00",
    employerCost: extras?.employerCost ?? "0.00",
  };
}

function period(index: number, was: string, should: string, source: "stored" | "migrated" = "stored"): ComparedPeriod {
  const start = `2026-0${index}-01`;
  return {
    resultId: `result-${index}`,
    employmentId: "employment-1",
    personId: "person-1",
    periodStart: start,
    periodEnd: `2026-0${index}-14`,
    originalPayDate: `2026-0${index}-20`,
    finalized: true,
    source,
    was: snapshot(was),
    should: snapshot(should),
  };
}

test("PAY-020 a back-dated rate correction opens one request per finalized period and pays them as non-periodic", () => {
  const requests = retroFromChangeSet({
    changeSetId: "cs-rate",
    effectiveDate: "2026-01-01",
    today: "2026-04-15",
    committed: true,
    touches: ["rate"],
    periods: [period(1, "1600.00", "1760.00"), period(2, "1600.00", "1760.00"), period(3, "1600.00", "1760.00")],
  });
  assert.equal(requests.length, 3);
  assert.deepEqual(
    requests.map((row) => row.differences.find((difference) => difference.payCode === "REG")?.amount),
    ["160.00", "160.00", "160.00"],
  );
  assert.equal(retroFromChangeSet({
    changeSetId: "cs-rate",
    effectiveDate: "2026-01-01",
    today: "2026-04-15",
    committed: false,
    touches: ["rate"],
    periods: [period(1, "1600.00", "1760.00")],
  }).length, 0);

  const paid = payRetro({ requests, approved: true, payDate: "2026-04-24", runId: "run-next", qualifiesForT1198: false });
  assert.equal(paid.lines.length, 3);
  assert.equal(paid.lines.every((line) => line.taxMethod === "non_periodic" && line.taxYear === 2026 && line.retroOf.startsWith("result-")), true);
  assert.equal(paid.letter, undefined);
  assert.throws(() => payRetro({ requests, approved: false, payDate: "2026-04-24", runId: "run-next", qualifiesForT1198: false }), /RETRO_RUN_NOT_APPROVED/);
});

test("PAY-021 eight thousand employees are batched, costed, and unpaid until the retro run is approved", () => {
  const employees: EmployeeForRetro[] = Array.from({ length: 8_000 }, (_, index) => ({
    personId: `person-${index}`,
    employmentId: `employment-${index}`,
    hiredOn: "2010-01-01",
    status: index === 10 ? "terminated" : "active",
    terminatedOn: index === 10 ? "2025-06-01" : undefined,
    periods: [
      {
        ...period(1, "1000.00", "1010.00"),
        resultId: `result-${index}`,
        personId: `person-${index}`,
        employmentId: `employment-${index}`,
        periodStart: "2025-08-01",
        periodEnd: "2025-08-14",
        originalPayDate: "2025-08-22",
      },
    ],
  }));
  const requests = retroFromAgreement({
    changeSetId: "cs-agreement",
    retroFrom: "2025-05-01",
    ratificationDate: "2026-08-01",
    eligiblePopulation: "active_on_ratification_and_terminated_after_retro_from",
    employees,
  });
  assert.equal(requests.length, 8_000);
  assert.equal(requests.some((row) => row.personId === "person-10"), true);
  const activeOnly = retroFromAgreement({
    changeSetId: "cs-agreement",
    retroFrom: "2025-05-01",
    ratificationDate: "2026-08-01",
    eligiblePopulation: "active_on_ratification",
    employees,
  });
  assert.equal(activeOnly.some((row) => row.personId === "person-10"), false);

  const batches = planBatches(requests.map((row) => row.personId));
  assert.equal(batches.length, 8_000 / RETRO_BATCH_SIZE);
  let current = batches;
  for (const batch of batches) {
    const step = processBatch(current, batch.batch, "5000.00");
    assert.equal(step.wrote, true);
    const again = processBatch(step.batches, batch.batch, "9999.00");
    assert.equal(again.wrote, false);
    assert.equal(again.batches[batch.batch]?.cost, "5000.00");
    current = again.batches;
  }
  const view = progressView({ batches: current, totalEmployees: 8_000, exceptions: 0 });
  assert.deepEqual(view, { done: 8_000, total: 8_000, cost: "80000.00", exceptions: 0, paid: false });

  const paid = payRetro({
    requests: requests.slice(0, 1),
    approved: true,
    payDate: "2026-08-28",
    runId: "retro-run",
    qualifiesForT1198: true,
  });
  assert.equal(paid.lines[0]?.taxYear, 2026);
  assert.equal(paid.lines[0]?.t4Year, 2026);
  assert.equal(paid.lines[0]?.taxMethod, "non_periodic");
  assert.equal(paid.letter, undefined);
  assert.equal(paid.requests[0]?.status, "paid");
});

test("PAY-021 a same-year difference under the lump-sum line does not create a T1198 letter", () => {
  const requests = retroFromChangeSet({
    changeSetId: "cs-small",
    effectiveDate: "2026-03-01",
    today: "2026-04-01",
    committed: true,
    touches: ["agreement"],
    periods: [period(3, "1000.00", "1500.00")],
  });
  const paid = payRetro({ requests, approved: true, payDate: "2026-04-10", runId: "run", qualifiesForT1198: true });
  assert.equal(paid.letter, undefined);
});

test("PAY-022 reversing a finalized off-cycle payment negates the result, the year-to-date, and the GL", () => {
  const reversal = reverseResult({
    resultId: "off-cycle-1",
    lines: [{ payCode: "REG", amount: "500.00" }],
    ytd: [{ code: "REG", amount: "500.00" }, { code: "CPP", amount: "25.00" }],
    gl: [{ glAccount: "5000", amount: "500.00" }],
  });
  assert.equal(reversal.runType, "reversal");
  assert.equal(reversal.reversesResultId, "off-cycle-1");
  assert.equal(reversal.lines[0]?.amount, "-500.00");
  assert.equal(reversal.ytd[1]?.amount, "-25.00");
  assert.equal(reversal.gl[0]?.amount, "-500.00");
});

test("PAY-053 the nightly sample covers half a percent plus every result of a new rule, and a mismatch blocks the engine", () => {
  const results = Array.from({ length: 1_000 }, (_, index) => ({
    resultId: `r${index}`,
    rulesAffected: index === 3 || index === 9,
  }));
  const sample = replaySample(results, (ids, count) => ids.slice(ids.length - count));
  assert.equal(sample.length, 5 + 2);
  assert.equal(sample.includes("r3") && sample.includes("r9"), true);

  const match = compareReplay({
    resultId: "r1",
    storedSha: "abc",
    replaySha: "abc",
    engineVersion: "engine-1",
    blocked: new Set(),
  });
  assert.deepEqual(match, { ok: true });

  const alert = compareReplay({
    resultId: "r2",
    storedSha: "stored",
    replaySha: "tampered",
    engineVersion: "engine-1",
    blocked: new Set(),
  });
  assert.equal(alert.ok, false);
  if (!alert.ok) {
    assert.equal(alert.severity, 1);
    assert.equal(alert.resultId, "r2");
    assert.equal(alert.changed, false);
    const blocked = blockEngine(new Set(), alert.engineVersion);
    assert.throws(
      () => compareReplay({ resultId: "r3", storedSha: "a", replaySha: "a", engineVersion: "engine-1", blocked }),
      /ENGINE_VERSION_BLOCKED/,
    );
  }
});

test("docs/06 section 8 a change after lock leaves the run alone until it is finalized", () => {
  const open = changeAfterLock({
    inputsKnownAt: "2026-04-01T12:00:00Z",
    committedAt: "2026-04-01T13:00:00Z",
    affectsWorkPeriod: true,
    touches: ["rate"],
    finalized: false,
  });
  assert.deepEqual(open, { resultsUnchanged: true, retroAfterFinalization: false });
  const done = changeAfterLock({ ...{
    inputsKnownAt: "2026-04-01T12:00:00Z",
    committedAt: "2026-04-01T13:00:00Z",
    affectsWorkPeriod: true,
    touches: ["rate"],
  }, finalized: true });
  assert.equal(done.retroAfterFinalization, true);
  assert.equal(retroAfterRuleActivation({
    finalized: false,
    coversLockedPeriod: true,
    pinnedHashes: ["old"],
    activatedHash: "new",
    resultDiffers: true,
  }), false);
  assert.equal(retroAfterRuleActivation({
    finalized: true,
    coversLockedPeriod: true,
    pinnedHashes: ["old"],
    activatedHash: "new",
    resultDiffers: true,
  }), true);
});

test("CORE-022 a past cross-province move shows the tax change, then a retro request for each person", () => {
  const employees = [
    { personId: "p1", employmentId: "e1", resultId: "r1", periodStart: "2026-03-01", periodEnd: "2026-03-14" },
    { personId: "p2", employmentId: "e2", resultId: "r2", periodStart: "2026-03-01", periodEnd: "2026-03-14" },
  ];
  const preview = provinceMoveRetro({
    changeSetId: "cs-move",
    effectiveDate: "2026-03-02",
    today: "2026-04-01",
    fromProvince: "ON",
    toProvince: "MB",
    approved: false,
    employees,
  });
  assert.equal(preview.taxProvinceChange, true);
  assert.equal(preview.retroEstimate, true);
  assert.equal(preview.requests.length, 0);
  const approved = provinceMoveRetro({
    changeSetId: "cs-move",
    effectiveDate: "2026-03-02",
    today: "2026-04-01",
    fromProvince: "ON",
    toProvince: "MB",
    approved: true,
    employees,
  });
  assert.deepEqual(approved.requests.map((row) => row.personId), ["p1", "p2"]);
});

test("ENT-014 retro for a closed grant follows the post-close policy and is listed for the funder", () => {
  const successor = chargeRetro({
    amount: "210.00",
    workDate: "2027-02-12",
    source: { id: "youth-grant", closed: true, periodFinal: true, postClosePolicy: "successor", successorId: "operating" },
  });
  assert.equal(successor.fundingSourceId, "operating");
  assert.equal(successor.adjustment?.fromSourceId, "youth-grant");
  assert.equal(successor.adjustment?.amount, "210.00");
  const suspense = chargeRetro({
    amount: "210.00",
    workDate: "2027-02-12",
    source: { id: "youth-grant", closed: true, periodFinal: false, postClosePolicy: "suspense" },
  });
  assert.equal(suspense.fundingSourceId, "suspense");
  assert.equal(suspense.adjustment?.policy, "suspense");
  const open = chargeRetro({
    amount: "210.00",
    workDate: "2027-02-12",
    source: { id: "operating", closed: false, periodFinal: false, postClosePolicy: "fallback", fallbackId: "other" },
  });
  assert.equal(open.fundingSourceId, "operating");
  assert.equal(open.adjustment, null);
});

test("ENT-024 a former employee who applies on day 25 is paid, and one who applies on day 40 is not", () => {
  const rule = {
    eligiblePopulation: "terminated_on_application" as const,
    retroFrom: "2023-01-01",
    ratificationDate: "2027-06-01",
    applicationDays: 30,
  };
  const early = { status: "terminated" as const, hiredOn: "2015-01-01", terminatedOn: "2026-01-01", appliedOn: "2027-06-25" };
  const late = { ...early, appliedOn: "2027-07-10" };
  assert.equal(isEligible(early, rule), true);
  assert.equal(isEligible(late, rule), false);
  assert.equal(dayNumber("2027-06-01", "2027-06-25"), 25);
  assert.equal(dayNumber("2027-06-01", "2027-07-10"), 40);

  const requests = retroFromAgreement({
    changeSetId: "cs-window",
    retroFrom: "2023-01-01",
    ratificationDate: "2027-06-01",
    eligiblePopulation: "terminated_on_application",
    applicationDays: 30,
    employees: [
      {
        personId: "early",
        employmentId: "e-early",
        ...early,
        periods: [{
          ...period(1, "1000.00", "4000.00"),
          personId: "early",
          periodStart: "2024-01-01",
          periodEnd: "2024-01-14",
          originalPayDate: "2024-01-19",
        }],
      },
      {
        personId: "late",
        employmentId: "e-late",
        ...late,
        periods: [period(1, "1000.00", "4000.00")],
      },
    ],
  });
  assert.deepEqual(requests.map((row) => row.personId), ["early"]);
  const paid = payRetro({ requests, approved: true, payDate: "2027-06-30", runId: "retro-2027", qualifiesForT1198: true });
  assert.equal(paid.lines[0]?.taxYear, 2027);
  assert.equal(paid.lines[0]?.t4Year, 2027);
  assert.equal(paid.letter?.amount, "3000.00");
});

test("ENT-029 retro into a period before go-live uses migrated history and CanDo pays the difference", () => {
  assert.equal(wasPaidSource("2026-05-14", "2026-07-01"), "migrated");
  assert.equal(wasPaidSource("2026-07-14", "2026-07-01"), "stored");
  const migrated = emptySnapshot([{ payCode: "REG", amount: "1000.00" }]);
  const requests = retroFromChangeSet({
    changeSetId: "cs-golive",
    effectiveDate: "2026-05-01",
    today: "2026-08-01",
    committed: true,
    touches: ["rate"],
    periods: [{
      ...period(1, "1000.00", "1100.00", "migrated"),
      periodStart: "2026-05-01",
      periodEnd: "2026-05-14",
      originalPayDate: "2026-05-22",
      was: migrated,
      should: snapshot("1100.00"),
    }],
  });
  assert.equal(requests[0]?.source, "migrated");
  assert.equal(earningsTotal(requests[0]?.differences ?? []), "100.00");
  const paid = payRetro({ requests, approved: true, payDate: "2026-08-14", runId: "cando", qualifiesForT1198: false });
  assert.equal(paid.lines[0]?.amount, "100.00");
  assert.equal(paid.lines[0]?.retroOf, "result-1");
  assert.throws(() => retroFromChangeSet({
    changeSetId: "cs-missing",
    effectiveDate: "2026-05-01",
    today: "2026-08-01",
    committed: true,
    touches: ["rate"],
    periods: [{
      ...period(1, "0.00", "100.00", "migrated"),
      periodStart: "2026-05-01",
      periodEnd: "2026-05-14",
      was: emptySnapshot(),
      should: snapshot("100.00"),
    }],
  }), /MIGRATED_HISTORY_MISSING/);
});
