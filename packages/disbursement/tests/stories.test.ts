import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  BANK_PROFILES,
  ChunkStore,
  DisbursementError,
  accrualTrueUp,
  deliveryFor,
  exportJournal,
  fundBurden,
  fundEarnings,
  funderPeriodOn,
  fundingEndAlerts,
  intercompanyRecovery,
  journalForRun,
  periodEndAccrual,
  postLine,
  putChunked,
  releaseBankFile,
  remittanceReminders,
  resolveCoding,
  sum,
  sourceDeductionRemittance,
  territorialPayrollTax,
  type BankProfile,
  type DirectDeposit,
} from "../src/index.ts";

const PAYMENTS: DirectDeposit[] = [
  { name: "Ada", amount: "1500.00", institution: "000312345", account: "123456789012" },
  { name: "Bo", amount: "250.50", institution: "000498765", account: "000011112222" },
];

const FILE_DATE = "2026-11-02";
const PAY_DATE = "2026-11-15";
const RUN_TOTAL = "1750.50";

function released(profile: BankProfile) {
  return releaseBankFile({
    profile,
    fileDate: FILE_DATE,
    payDate: PAY_DATE,
    payments: PAYMENTS,
    runTotal: RUN_TOTAL,
    approved: true,
    releasers: ["payroll", "finance"],
  });
}

function throwsCode(run: () => void): string {
  try {
    run();
  } catch (error) {
    if (error instanceof DisbursementError) return error.code;
    throw error;
  }
  throw new Error("did not throw");
}

function golden(name: string): Buffer {
  return readFileSync(new URL(`./golden/${name}`, import.meta.url));
}

const MARCH_APRIL = {
  start: "2027-03-25",
  end: "2027-04-07",
  amount: "1400.00",
  account: "6000",
  description: "Payroll",
  yearEndMonth: 3,
  mappingVersions: [{ version: "MV-2027", effectiveFrom: "2026-04-01" }],
};

test("PAY-031 releases an approved run under dual control for every bank profile", () => {
  assert.equal(BANK_PROFILES.length, 8);
  const checksums = new Set<string>();
  for (const profile of BANK_PROFILES) {
    const file = released(profile);
    const expected = golden(profile.format === "pain001" ? `${profile.id}.pain001.xml` : `${profile.id}.cpa005`);
    assert.equal(Buffer.compare(Buffer.from(file.bytes), expected), 0);
    assert.equal(file.checksum, createHash("sha256").update(file.bytes).digest("hex"));
    assert.equal(file.controlTotal, RUN_TOTAL);
    assert.equal(file.sftp, false);
    assert.equal(file.format, profile.format);
    checksums.add(file.checksum);
    const store = new ChunkStore();
    const stored = putChunked(store, profile.id, file.bytes, 100);
    assert.ok(stored.parts > 1);
    assert.equal(Buffer.compare(Buffer.from(store.getObject(profile.id)), Buffer.from(file.bytes)), 0);
  }
  assert.equal(checksums.size, BANK_PROFILES.length);

  const rbc = released(BANK_PROFILES[0]!);
  const text = new TextDecoder().decode(rbc.bytes);
  assert.equal(text.includes("\n"), false);
  assert.equal(rbc.bytes.length % 1464, 0);
  assert.equal(rbc.bytes.length / 1464, 3);
  assert.equal(text.startsWith("A"), true);
  assert.ok(text.includes("026306"));
  assert.ok(text.includes("026319"));
  assert.ok(text.includes("RBC0000001"));

  const scotia = new TextDecoder().decode(released(BANK_PROFILES.find((profile) => profile.id === "scotiabank")!).bytes);
  assert.match(scotia, /<NbOfTxs>2<\/NbOfTxs>/);
  assert.match(scotia, /<CtrlSum>1750\.50<\/CtrlSum>/);
  assert.match(scotia, /<PmtMtd>TRF<\/PmtMtd>/);
  assert.ok(scotia.endsWith("\n"));

  assert.equal(
    throwsCode(() =>
      releaseBankFile({
        profile: BANK_PROFILES[0]!,
        fileDate: FILE_DATE,
        payDate: PAY_DATE,
        payments: PAYMENTS,
        runTotal: RUN_TOTAL,
        approved: false,
        releasers: ["payroll", "finance"],
      }),
    ),
    "RUN_NOT_APPROVED",
  );
  assert.equal(
    throwsCode(() =>
      releaseBankFile({
        profile: BANK_PROFILES[0]!,
        fileDate: FILE_DATE,
        payDate: PAY_DATE,
        payments: PAYMENTS,
        runTotal: RUN_TOTAL,
        approved: true,
        releasers: ["payroll"],
      }),
    ),
    "DUAL_CONTROL",
  );
  assert.equal(
    throwsCode(() =>
      releaseBankFile({
        profile: BANK_PROFILES[0]!,
        fileDate: FILE_DATE,
        payDate: PAY_DATE,
        payments: PAYMENTS,
        runTotal: RUN_TOTAL,
        approved: true,
        releasers: ["payroll", "payroll"],
      }),
    ),
    "DUAL_CONTROL",
  );
  assert.equal(
    throwsCode(() =>
      releaseBankFile({
        profile: BANK_PROFILES[0]!,
        fileDate: FILE_DATE,
        payDate: PAY_DATE,
        payments: PAYMENTS,
        runTotal: "10.00",
        approved: true,
        releasers: ["payroll", "finance"],
      }),
    ),
    "CONTROL_TOTAL_MISMATCH",
  );

  const many = Array.from({ length: 7 }, (_, index) => ({
    name: `Person ${index + 1}`,
    amount: "1.00",
    institution: "000312345",
    account: "123456789012",
  }));
  const wide = releaseBankFile({
    profile: BANK_PROFILES[0]!,
    fileDate: FILE_DATE,
    payDate: PAY_DATE,
    payments: many,
    runTotal: "7.00",
    approved: true,
    releasers: ["payroll", "finance"],
  });
  assert.equal(wide.bytes.length / 1464, 4);
  assert.equal(wide.controlTotal, "7.00");
});

test("PAY-032 remittance due dates by remitter type", () => {
  const early = sourceDeductionRemittance({ remitterType: "accelerated_1", payDate: "2026-11-02", amount: "100.00" });
  const late = sourceDeductionRemittance({ remitterType: "accelerated_1", payDate: "2026-11-30", amount: "80.00" });
  assert.equal(early.dueDate, "2026-11-25");
  assert.equal(late.dueDate, "2026-12-10");
  assert.equal(early.payee, "CRA");
  assert.equal(
    sourceDeductionRemittance({ remitterType: "accelerated_1", payDate: "2026-11-16", amount: "1.00" }).dueDate,
    "2026-12-10",
  );
  assert.equal(sourceDeductionRemittance({ remitterType: "quarterly", payDate: "2026-11-02", amount: "1.00" }).dueDate, "2027-01-15");
  assert.equal(sourceDeductionRemittance({ remitterType: "regular", payDate: "2026-11-20", amount: "1.00" }).dueDate, "2026-12-15");
  assert.equal(
    sourceDeductionRemittance({ remitterType: "accelerated_2", payDate: "2026-11-07", amount: "1.00" }).dueDate,
    "2026-11-11",
  );
  assert.equal(
    sourceDeductionRemittance({
      remitterType: "accelerated_2",
      payDate: "2026-11-07",
      amount: "1.00",
      holidays: ["2026-11-09"],
    }).dueDate,
    "2026-11-12",
  );
  const summed = sourceDeductionRemittance({
    remitterType: "regular",
    payDate: "2026-11-20",
    parts: { employeeCpp: "10.00", employerCpp: "10.00", employeeEi: "5.00", employerEi: "7.00", tax: "20.00" },
  });
  assert.equal(summed.amount, "52.00");
  assert.equal(summed.payee, "CRA");
});

test("PAY-033 territorial payroll tax for Nunavut and the Northwest Territories", () => {
  const nunavut = territorialPayrollTax({ province: "NU", gross: "1000.00", rate: "0.02" });
  assert.deepEqual(nunavut, { code: "NU_PAYROLL_TAX", amount: "20.00", onT4: false, t4Boxes: [] });
  const northwest = territorialPayrollTax({ province: "NT", gross: "1000.00", rate: "0.02" });
  assert.equal(northwest.code, "NT_PAYROLL_TAX");
  assert.equal(northwest.amount, "20.00");
  assert.equal(northwest.onT4, false);
  assert.deepEqual(northwest.t4Boxes, []);
  assert.deepEqual(territorialPayrollTax({ province: "ON", gross: "1000.00", rate: "0.02" }), {
    code: null,
    amount: "0.00",
    onT4: false,
    t4Boxes: [],
  });
  assert.equal(throwsCode(() => territorialPayrollTax({ province: "NU", gross: 1000 as unknown as string, rate: "0.02" })), "MONEY");
});

test("PAY-077 delivery follows the person's status and choice", () => {
  assert.deepEqual(deliveryFor({ status: "current", kind: "tax_slip", choice: null }), { method: "portal", mayEmail: false });
  assert.deepEqual(deliveryFor({ status: "current", kind: "pay_statement", choice: "paper" }), { method: "print", mayEmail: false });
  assert.deepEqual(deliveryFor({ status: "former", kind: "tax_slip", choice: null }), { method: "print", mayEmail: false });
  assert.deepEqual(deliveryFor({ status: "former", kind: "tax_slip", choice: "electronic" }), { method: "portal", mayEmail: false });
  assert.deepEqual(deliveryFor({ status: "leave", kind: "pay_statement", choice: null }), { method: "print", mayEmail: false });
  assert.deepEqual(deliveryFor({ status: "laid_off", kind: "pay_statement", choice: null }), { method: "print", mayEmail: false });
  assert.deepEqual(deliveryFor({ status: "laid_off", kind: "pay_statement", choice: "electronic" }), { method: "portal", mayEmail: false });
  assert.deepEqual(deliveryFor({ status: "current", kind: "pay_statement", choice: "email" }), { method: "portal", mayEmail: true });
  assert.deepEqual(deliveryFor({ status: "former", kind: "tax_slip", choice: "paper" }), { method: "print", mayEmail: false });
});

test("PAY-082 remittance reminders stop once the payment is recorded", () => {
  const open = {
    payee: "CRA",
    amount: "640.00",
    dueDate: "2026-12-15",
    reminderDays: [7, 3, 1],
    paid: false,
  };
  assert.deepEqual(
    remittanceReminders(open).map((reminder) => reminder.on),
    ["2026-12-08", "2026-12-12", "2026-12-14"],
  );
  for (const reminder of remittanceReminders(open)) {
    assert.equal(reminder.payee, "CRA");
    assert.equal(reminder.amount, "640.00");
    assert.equal(reminder.dueDate, "2026-12-15");
  }
  assert.deepEqual(remittanceReminders({ ...open, paid: true }), []);
});

test("PAY-083 journal file for Xero and the other ledgers", () => {
  const journal = journalForRun(MARCH_APRIL);
  const xero = exportJournal("xero", journal.lines);
  assert.equal(xero.csv, golden("xero.csv").toString("utf8"));
  assert.equal(xero.controlTotal, "1400.00");
  assert.equal(journal.controlTotal, "1400.00");
  assert.deepEqual(
    journal.lines.map((line) => [line.workPeriod, line.postingPeriod, line.mappingVersion, line.amount]),
    [
      ["FY2027-P12", "FY2027-P12", "MV-2027", "700.00"],
      ["FY2028-P01", "FY2028-P01", "MV-2027", "700.00"],
    ],
  );
  for (const system of ["quickbooks", "sage", "dynamics", "netsuite", "generic"] as const) {
    const file = exportJournal(system, journal.lines);
    const [header, ...rows] = file.csv.trimEnd().split("\n");
    assert.match(header!, /WorkPeriod|work_period/);
    assert.match(header!, /PostingPeriod|posting_period/);
    assert.match(header!, /MappingVersion|mapping_version/);
    const columns = header!.split(",");
    const amountIndex = columns.findIndex((column) => /amount/i.test(column));
    const total = sum(rows.map((row) => row.split(",")[amountIndex] ?? "0.00"));
    assert.equal(total, file.controlTotal);
    assert.equal(file.controlTotal, "1400.00");
    assert.ok(file.csv.includes("FY2027-P12"));
    assert.ok(file.csv.includes("MV-2027"));
  }
});

test("PAY-084 a line with no cost coding goes to suspense", () => {
  const none = resolveCoding({ suspenseAccount: "SUSPENSE" });
  assert.equal(none.account, "SUSPENSE");
  assert.equal(none.financeTask, true);
  assert.equal(none.payDelayed, false);
  assert.equal(none.from, "suspense");
  const assignment = resolveCoding({
    assignment: { account: "4100", sourceId: "assign" },
    position: { account: "4200", sourceId: "position" },
    suspenseAccount: "SUSPENSE",
  });
  assert.equal(assignment.from, "assignment");
  assert.equal(assignment.account, "4100");
  assert.equal(assignment.financeTask, false);
  const position = resolveCoding({
    position: { account: "4200", sourceId: "position" },
    orgUnit: { account: "4300" },
    suspenseAccount: "SUSPENSE",
  });
  assert.equal(position.from, "position");
  assert.equal(position.sourceId, "position");
  const explicit = resolveCoding({
    explicit: { account: "4000", sourceId: "grant" },
    assignment: { account: "4100" },
    suspenseAccount: "SUSPENSE",
  });
  assert.equal(explicit.from, "explicit");
  const unit = resolveCoding({ orgUnit: { account: "4300", sourceId: "unit" }, suspenseAccount: "SUSPENSE" });
  assert.equal(unit.from, "org_unit");
});

test("PAY-085 a grant cap sends the excess to the fallback", () => {
  const source = {
    id: "A1",
    endsOn: "2027-03-31",
    remainingCap: "600.00",
    capBehaviour: "spill_fallback" as const,
    eligibleCategories: ["salary"],
    allowsBurden: true,
    fallbackId: "OPERATING",
  };
  assert.deepEqual(fundEarnings({ amount: "1000.00", workDate: "2027-03-15", category: "salary", source }).lines, [
    { id: "A1", amount: "600.00" },
    { id: "OPERATING", amount: "400.00" },
  ]);
  assert.deepEqual(fundingEndAlerts("2027-03-31", [90, 60, 30]), [
    { on: "2026-12-31", daysBefore: 90 },
    { on: "2027-01-30", daysBefore: 60 },
    { on: "2027-03-01", daysBefore: 30 },
  ]);
  assert.equal(
    throwsCode(() =>
      fundEarnings({
        amount: "1000.00",
        workDate: "2027-03-15",
        category: "salary",
        source: { ...source, capBehaviour: "hard_stop" },
      }),
    ),
    "FUNDING_CAP",
  );
  assert.deepEqual(fundEarnings({ amount: "1000.00", workDate: "2027-03-15", category: "training", source }).lines, [
    { id: "OPERATING", amount: "1000.00" },
  ]);
});

test("docs/06 section 10 test 4 splits a period across two fiscal years", () => {
  const journal = journalForRun(MARCH_APRIL);
  assert.deepEqual(journal.budgets, [
    { fiscalYear: "FY2027", amount: "700.00" },
    { fiscalYear: "FY2028", amount: "700.00" },
  ]);
  assert.deepEqual(
    journal.lines.map((line) => line.fiscalYear),
    ["FY2027", "FY2028"],
  );
  assert.deepEqual(
    journal.lines.map((line) => line.workPeriod),
    ["FY2027-P12", "FY2028-P01"],
  );
});

test("ENT-012 a grant that ended sends April earnings to the operating fund", () => {
  const ended = fundEarnings({
    amount: "800.00",
    workDate: "2027-04-06",
    category: "salary",
    source: {
      id: "A1",
      endsOn: "2027-03-31",
      remainingCap: "5000.00",
      capBehaviour: "spill_fallback",
      eligibleCategories: ["salary"],
      allowsBurden: true,
      fallbackId: "OPERATING",
    },
  });
  assert.deepEqual(ended.lines, [{ id: "OPERATING", amount: "800.00" }]);
  assert.deepEqual(fundingEndAlerts("2027-03-31", [90, 60, 30]).map((alert) => alert.on), [
    "2026-12-31",
    "2027-01-30",
    "2027-03-01",
  ]);
  const calendar = funderPeriodOn(
    [
      { id: "A1-2027", start: "2026-04-01", end: "2027-03-31", status: "closed" },
      { id: "OP-2028", start: "2027-04-01", end: "2028-03-31", status: "open" },
    ],
    "2027-04-06",
  );
  assert.equal(calendar.id, "OP-2028");
  assert.equal(calendar.status, "open");
});

test("ENT-013 a salary cap mid-period sends the excess to the fallback", () => {
  const earnings = fundEarnings({
    amount: "1000.00",
    workDate: "2027-02-15",
    category: "salary",
    source: {
      id: "A1",
      endsOn: "2027-03-31",
      remainingCap: "600.00",
      capBehaviour: "spill_fallback",
      eligibleCategories: ["salary"],
      allowsBurden: true,
      fallbackId: "OPERATING",
    },
  }).lines;
  assert.deepEqual(earnings, [
    { id: "A1", amount: "600.00" },
    { id: "OPERATING", amount: "400.00" },
  ]);
  assert.deepEqual(fundBurden({ burden: "150.00", earnings, allowsBurden: true, fallbackId: "OPERATING" }), [
    { id: "A1", amount: "90.00" },
    { id: "OPERATING", amount: "60.00" },
  ]);
  assert.deepEqual(fundBurden({ burden: "150.00", earnings, allowsBurden: false, fallbackId: "OPERATING" }), [
    { id: "OPERATING", amount: "150.00" },
  ]);
  const distributed = sum(fundBurden({ burden: "150.00", earnings, allowsBurden: true, fallbackId: "OPERATING" }).map((line) => line.amount));
  assert.equal(distributed, "150.00");
});

test("ENT-026 period-end accrual reverses and revalues liabilities", () => {
  const run = periodEndAccrual({
    periodEnd: "2027-03-31",
    nextPeriodStart: "2027-04-01",
    unpaidDays: 4,
    dailyAmount: "100.00",
    expenseAccount: "6000",
    liabilityAccount: "2400",
    workPeriod: "FY2027-P12",
    accrualPostingPeriod: "FY2027-P12",
    reversalPostingPeriod: "FY2028-P01",
    mappingVersion: "MV-2027",
    previousLiability: "50.00",
    currentLiability: "80.00",
  });
  assert.equal(run.accrual.amount, "400.00");
  assert.equal(run.accrual.journalDate, "2027-03-31");
  assert.equal(run.reversal.amount, "-400.00");
  assert.equal(run.reversal.on, "2027-04-01");
  assert.equal(run.reversal.postingPeriod, "FY2028-P01");
  assert.equal(run.revaluation.change, "30.00");
  assert.equal(run.revaluation.line?.account, "2400");
  assert.equal(accrualTrueUp("400.00", "400.00"), "0.00");
  assert.equal(accrualTrueUp("500.00", "400.00"), "100.00");
});

test("ENT-027 a closed fiscal period posts to the first open period", () => {
  const line = postLine({
    workDate: "2027-03-20",
    amount: "250.00",
    account: "6000",
    description: "Correction",
    yearEndMonth: 3,
    closed: ["FY2027-P12"],
    mappingVersions: [
      { version: "MV-2026", effectiveFrom: "2026-04-01" },
      { version: "MV-2027", effectiveFrom: "2027-01-01" },
      { version: "MV-LATER", effectiveFrom: "2027-06-01" },
    ],
  });
  assert.equal(line.workPeriod, "FY2027-P12");
  assert.equal(line.postingPeriod, "FY2028-P01");
  assert.equal(line.mappingVersion, "MV-2027");
  assert.equal(throwsCode(() => postLine({ ...lineInput(), closed: ["*"] })), "PERIOD_CLOSED");
});

function lineInput() {
  return {
    workDate: "2027-03-20",
    amount: "250.00",
    account: "6000",
    description: "Correction",
    yearEndMonth: 3,
    mappingVersions: [{ version: "MV-2027", effectiveFrom: "2026-04-01" }],
  };
}

test("intercompany recovery journals follow cost, cost plus, or a fixed fee", () => {
  const shared = {
    payingEntity: "CITY",
    receivingEntity: "BOARD",
    account: "1500",
    workPeriod: "FY2027-P12",
    postingPeriod: "FY2027-P12",
    mappingVersion: "MV-2027",
  };
  const cost = intercompanyRecovery({ ...shared, basis: "cost", cost: "1000.00" });
  assert.equal(cost.amount, "1000.00");
  assert.deepEqual(
    cost.lines.map((line) => [line.entity, line.side, line.amount]),
    [
      ["BOARD", "debit", "1000.00"],
      ["CITY", "credit", "1000.00"],
    ],
  );
  assert.equal(intercompanyRecovery({ ...shared, basis: "cost_plus", cost: "1000.00", markupRate: "0.10" }).amount, "1100.00");
  assert.equal(intercompanyRecovery({ ...shared, basis: "fixed", cost: "1000.00", fixedFee: "500.00" }).amount, "500.00");
});
