import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { ChunkStore } from "@candohr/disbursement";
import {
  assignmentEndRoes,
  buildRoeFile,
  buildT4ASubmission,
  buildT4Submission,
  combineYearSlip,
  formerEmployeeAccessUntil,
  importGoLive,
  pierReport,
  prepareRoe,
  slipDelivery,
  storeReturn,
  trackRoeDeadlines,
  YearEndError,
  type Transmitter,
} from "../src/index.ts";

const craZip = fileURLToPath(new URL("../../../vendor/cra/xmlschm1-26-3.zip", import.meta.url));
const roeSchema = fileURLToPath(new URL("../../../vendor/roe/PayrollExtractXmlV2.xsd", import.meta.url));

const transmitter: Transmitter = {
  businessNumber: "123456789RP0001",
  language: "E",
  country: "CAN",
  contactName: "Payroll Desk",
  areaCode: "613",
  phone: "555-0100",
  email: "payroll@example.com",
  name: "CanDo HR",
  submissionId: "CANDO001",
};

function throwsCode(run: () => void): string {
  try {
    run();
  } catch (error) {
    if (error instanceof YearEndError) return error.code;
    throw error;
  }
  throw new Error("did not throw");
}

function validateCra(xml: string, entry: "T619_T4.xsd" | "T619_T4A.xsd"): void {
  const dir = mkdtempSync(path.join(tmpdir(), "cra-"));
  try {
    execFileSync("unzip", ["-qo", craZip, "-d", dir]);
    const schemaDir = path.join(dir, "SchemasEFV-Published - 202601");
    writeFileSync(path.join(schemaDir, "return.xml"), xml);
    execFileSync("xmllint", ["--noout", "--schema", entry, "return.xml"], { cwd: schemaDir });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function validateRoe(xml: string): void {
  const dir = mkdtempSync(path.join(tmpdir(), "roe-"));
  try {
    const xmlPath = path.join(dir, "roe.xml");
    writeFileSync(xmlPath, xml);
    execFileSync("xmllint", ["--noout", "--schema", roeSchema, xmlPath]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const adaSlip = {
  surname: "Lovelace",
  givenName: "Ada",
  sin: "123456789",
  payrollAccount: "123456789RP0001",
  province: "ON",
  employmentIncome: "45000.00",
  cpp: "2400.00",
  ei: "700.00",
  tax: "8000.00",
  pensionable: "45000.00",
  insurable: "45000.00",
};

test("PAY-040 T4 and T4A XML validate against the downloaded CRA schemas", () => {
  const original = buildT4Submission({
    transmitter,
    taxYear: "2026",
    employerName: "City of CanDo",
    report: "O",
    slips: [adaSlip],
  });
  validateCra(original, "T619_T4.xsd");
  assert.match(original, /<T4>/);
  assert.doesNotMatch(original, /<T4A>/);
  assert.doesNotMatch(original, /<[^/>]+><\/[^>]+>/);
  assert.equal(original.includes("<rpt_tcd>O</rpt_tcd>"), true);

  const amended = buildT4Submission({
    transmitter,
    taxYear: "2026",
    employerName: "City of CanDo",
    report: "A",
    amendmentNote: "Corrected CPP",
    slips: [{ ...adaSlip, cpp: "2500.00" }],
  });
  validateCra(amended, "T619_T4.xsd");
  assert.equal(amended.includes("<rpt_tcd>A</rpt_tcd>"), true);
  assert.equal(amended.includes("Corrected CPP"), true);

  const t4a = buildT4ASubmission({
    transmitter: { ...transmitter, submissionId: "CANDO002" },
    taxYear: "2026",
    payerName: "City of CanDo",
    report: "O",
    slips: [
      {
        surname: "Lovelace",
        givenName: "Ada",
        sin: "123456789",
        recipientBn: "987654321RC0001",
        payrollAccount: "123456789RP0001",
        otherIncome: "800.00",
        tax: "120.00",
      },
    ],
  });
  validateCra(t4a, "T619_T4A.xsd");
  assert.match(t4a, /<T4A>/);
  assert.doesNotMatch(t4a, /<T4Slip>/);

  const store = new ChunkStore();
  const stored = storeReturn(store, "t4-2026", original, 100);
  assert.ok(stored.parts > 1);
  assert.equal(Buffer.compare(Buffer.from(stored.bytes), Buffer.from(original)), 0);
});

test("PAY-041 a PIER difference is listed before filing", () => {
  const report = pierReport([
    { personId: "ada", cppDeducted: "100.00", cppCalculated: "90.00", eiDeducted: "20.00", eiCalculated: "20.00" },
    { personId: "bo", cppDeducted: "50.00", cppCalculated: "50.00", eiDeducted: "10.00", eiCalculated: "12.00" },
    { personId: "cy", cppDeducted: "0.00", cppCalculated: "0.00", eiDeducted: "0.00", eiCalculated: "0.00" },
  ]);
  assert.deepEqual(report, [
    { personId: "ada", kind: "cpp", deducted: "100.00", calculated: "90.00" },
    { personId: "bo", kind: "ei", deducted: "10.00", calculated: "12.00" },
  ]);
});

test("PAY-042 and PAY-079 an ROE is drafted with its deadline and built only after HR reviews it", () => {
  const draft = prepareRoe({
    payrollAccount: "123456789RP0001",
    payPeriodType: "B",
    sin: "123456789",
    firstName: "Ada",
    lastName: "Lovelace",
    addressLine1: "1 Main Street",
    addressLine2: "Ottawa ON",
    postalCode: "K1A0A6",
    firstDay: "2026-01-05",
    lastDayPaid: "2026-11-15",
    finalPayPeriodEnd: "2026-11-15",
    insurableHours: "80",
    periods: [
      { number: 1, amount: "1500.00" },
      { number: 2, amount: "1500.00" },
    ],
    separationReason: "quit",
    reasonMap: { quit: "E", layoff: "A" },
    contactFirstName: "Pat",
    contactLastName: "Kim",
    contactArea: "613",
    contactPhone: "5550100",
    deadlineDays: 5,
  });
  assert.equal(draft.reasonCode, "E");
  assert.equal(draft.dueDate, "2026-11-20");
  assert.equal(throwsCode(() => buildRoeFile(draft, null)), "ROE_NOT_REVIEWED");
  const xml = buildRoeFile(draft, { reviewedBy: "hr-1", reviewedAt: "2026-11-16" });
  validateRoe(xml);
  assert.equal(xml.includes("<CD>E</CD>"), true);
  assert.equal(xml.includes('nbr="2"'), true);
  const tracked = trackRoeDeadlines(
    [
      { id: "ada", dueDate: draft.dueDate, filed: false },
      { id: "bo", dueDate: "2026-11-01", filed: false },
      { id: "cy", dueDate: "2026-11-20", filed: true },
    ],
    "2026-11-18",
  );
  assert.deepEqual(tracked, [
    { id: "ada", status: "due" },
    { id: "bo", status: "overdue" },
    { id: "cy", status: "filed" },
  ]);
  const store = new ChunkStore();
  const stored = storeReturn(store, "roe-ada", xml, 80);
  assert.ok(stored.parts > 1);
  assert.equal(new TextDecoder().decode(stored.bytes), xml);
});

test("PAY-077 slips follow the person's status and delivery choice", () => {
  assert.deepEqual(slipDelivery({ status: "current", kind: "tax_slip", choice: null }), { method: "portal", mayEmail: false });
  assert.deepEqual(slipDelivery({ status: "current", kind: "pay_statement", choice: "paper" }), { method: "print", mayEmail: false });
  assert.deepEqual(slipDelivery({ status: "former", kind: "tax_slip", choice: null }), { method: "print", mayEmail: false });
  assert.deepEqual(slipDelivery({ status: "former", kind: "tax_slip", choice: "electronic" }), { method: "portal", mayEmail: false });
});

test("PAY-078 leaving on 15 November 2026 keeps access until 28 February 2028", () => {
  assert.equal(formerEmployeeAccessUntil("2026-11-15", 12), "2028-02-28");
  assert.equal(formerEmployeeAccessUntil("2026-11-15", 24), "2029-02-28");
});

test("PAY-081 one T4 for the year counts imported CPP and EI toward the maximums", () => {
  const combined = combineYearSlip({
    personId: "ada",
    payrollAccountId: "123456789RP0001",
    province: "ON",
    imported: {
      employmentIncome: "20000.00",
      cpp: "3900.00",
      ei: "300.00",
      tax: "3000.00",
      pensionable: "20000.00",
      insurable: "20000.00",
    },
    cando: {
      employmentIncome: "25000.00",
      cpp: "50.00",
      ei: "400.00",
      tax: "5000.00",
      pensionable: "25000.00",
      insurable: "25000.00",
    },
    cppMaximum: "4000.00",
    eiMaximum: "1000.00",
  });
  assert.equal(combined.slipCount, 1);
  assert.equal(combined.amounts.employmentIncome, "45000.00");
  assert.equal(combined.amounts.cpp, "3950.00");
  assert.equal(combined.cppRoom, "50.00");
  assert.equal(combined.eiRoom, "300.00");
  const xml = buildT4Submission({
    transmitter,
    taxYear: "2026",
    employerName: "City of CanDo",
    report: "O",
    slips: [
      {
        surname: "Lovelace",
        givenName: "Ada",
        sin: "123456789",
        payrollAccount: combined.payrollAccountId,
        province: combined.province,
        employmentIncome: combined.amounts.employmentIncome,
        cpp: combined.amounts.cpp,
        ei: combined.amounts.ei,
        tax: combined.amounts.tax,
        pensionable: combined.amounts.pensionable,
        insurable: combined.amounts.insurable,
      },
    ],
  });
  assert.equal((xml.match(/<T4Slip>/g) ?? []).length, 1);
  assert.equal(xml.includes("<empt_incamt>45000.00</empt_incamt>"), true);
  assert.equal(xml.includes("<cpp_cntrb_amt>3950.00</cpp_cntrb_amt>"), true);
  validateCra(xml, "T619_T4.xsd");
});

test("ENT-016 earnings that continue on the same account do not produce an ROE", () => {
  const result = assignmentEndRoes({
    interruptionDays: 7,
    ended: {
      assignmentId: "A1",
      personId: "jordan",
      payrollAccountId: "city",
      leavePlanId: "IO",
      positionId: "P1",
      nextEarningsDate: "2027-03-31",
      endDate: "2027-03-31",
    },
    remaining: [
      {
        assignmentId: "A2",
        personId: "jordan",
        payrollAccountId: "city",
        leavePlanId: "IU",
        positionId: "P2",
        nextEarningsDate: "2027-04-06",
      },
    ],
    positionHolders: [{ positionId: "P2", assignmentId: "A2" }],
  });
  assert.deepEqual(result.roes, []);
  assert.equal(result.leaveSettles, true);
  assert.equal(result.benefitsReevaluated, true);
  assert.equal(result.positionVacated, true);
});

test("ENT-017 the library account gets an ROE and the city account does not", () => {
  const result = assignmentEndRoes({
    interruptionDays: 7,
    ended: {
      assignmentId: "A3",
      personId: "jordan",
      payrollAccountId: "library",
      leavePlanId: "LIB",
      positionId: "L1",
      nextEarningsDate: "2027-03-31",
      endDate: "2027-03-31",
    },
    remaining: [
      {
        assignmentId: "city-job",
        personId: "jordan",
        payrollAccountId: "city",
        leavePlanId: "CITY",
        positionId: "C1",
        nextEarningsDate: "2027-04-01",
      },
    ],
    positionHolders: [{ positionId: "C1", assignmentId: "city-job" }],
  });
  assert.deepEqual(result.roes, [{ personId: "jordan", payrollAccountId: "library" }]);
  assert.equal(result.roes.some((roe) => roe.payrollAccountId === "city"), false);
});

test("ENT-028 covered days are left out and opening amounts reconcile to the cent", () => {
  const loaded = importGoLive({
    cutover: "2026-07-01",
    workDays: ["2026-06-28", "2026-06-29", "2026-06-30", "2026-07-01"],
    lines: [
      { kind: "ytd", personId: "ada", payrollAccountId: "city", code: "CPP", amount: "10.00", sourceTotal: "10.00" },
      { kind: "period_history", personId: "ada", payrollAccountId: "city", code: "insurable", amount: "5.50", sourceTotal: "5.50" },
      { kind: "opening_liability", personId: "ada", payrollAccountId: "city", code: "vacation", amount: "100.00", sourceTotal: "100.00" },
      { kind: "balance", personId: "ada", payrollAccountId: "city", code: "sick", amount: "8.00", sourceTotal: "8.00" },
      { kind: "funding_spent", personId: "ada", payrollAccountId: "city", code: "A1", amount: "20.00", sourceTotal: "20.00" },
    ],
  });
  assert.deepEqual(loaded.excludedDays, ["2026-06-28", "2026-06-29", "2026-06-30"]);
  assert.deepEqual(loaded.payableDays, ["2026-07-01"]);
  assert.equal(loaded.reconciliation.every((line) => line.status === "reconciled"), true);
  assert.equal(loaded.changeSet?.source, "import");
  assert.equal(loaded.changeSet?.lines.length, 5);
  const refused = importGoLive({
    cutover: "2026-07-01",
    workDays: ["2026-06-30", "2026-07-01"],
    lines: [{ kind: "ytd", personId: "ada", payrollAccountId: "city", code: "CPP", amount: "10.00", sourceTotal: "10.01" }],
  });
  assert.equal(refused.changeSet, null);
  assert.equal(refused.reconciliation[0]?.difference, "-0.01");
  assert.equal(refused.reconciliation[0]?.status, "difference");
});
