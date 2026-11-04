import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { caseRules, validateAgreementDocument } from "@candohr/rules";
import { AnalyticsError } from "../src/errors.ts";
import { addDays, addYears } from "../src/dates.ts";
import {
  accommodationView,
  activateAgreement,
  applyEmploymentDecision,
  applyPattern,
  attendanceTotal,
  bcPayTransparency,
  biExport,
  buildReport,
  combinationQuestion,
  complianceCalendar,
  currentDefinition,
  deliverAccess,
  draftSalaryDisclosure,
  equityAggregate,
  explainPayLine,
  explainRisk,
  exportTenant,
  federalEquityReports,
  fileStatutoryReport,
  filingDue,
  funderView,
  grantSupport,
  grievanceAlert,
  importAgreement,
  logIncident,
  managerEquityView,
  metricAsOf,
  moveOutsideQuebec,
  openAccessRequest,
  openCombinations,
  openGrievance,
  payGapReport,
  proposeRules,
  publishDefinition,
  readAnalytics,
  recordCombinationAnswer,
  recordIncident,
  recordSelfId,
  renewAgreement,
  reorgGroupings,
  resolveScope,
  retentionRun,
  retroPreview,
  revokeSupport,
  sandboxCost,
  screen,
  setDedicatedDatabase,
  statutoryCatalogue,
  strikeSchedule,
  suppressGroups,
  transferPositions,
  verifyRule,
} from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");

function readJson(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(join(root, path), "utf8")) as Record<string, unknown>;
}

function settingDefault(sql: string, key: string): string {
  const pattern = new RegExp(
    `\\('${key}',\\s*'[^']+',\\s*'[^']+',\\s*(?:NULL|'(?:[^']|'')*'),\\s*(NULL|'(?:[^']|'')*')`,
  );
  const match = pattern.exec(sql);
  if (!match) throw new Error(key);
  const raw = match[1];
  if (raw === "NULL") throw new Error(key);
  return raw.slice(1, -1).replaceAll("''", "'");
}

function settingMin(sql: string, key: string): number {
  const pattern = new RegExp(`\\('${key}'[\\s\\S]{0,1200}?'decided',\\s*(\\d+),`);
  const match = pattern.exec(sql);
  if (!match) throw new Error(key);
  return Number(match[1]);
}

function codeOf(run: () => void): string {
  try {
    run();
  } catch (error) {
    if (error instanceof AnalyticsError) return error.code;
    throw error;
  }
  throw new Error("did not throw");
}

const catalogue = readJson("rules/compliance/statutory-reports.json") as {
  reports: Record<string, { form_status: string; cite: string; source_data: string; min_employees?: number; due?: { month: number; day: number | string }; first_year?: number }>;
};
const disclosure = readJson("rules/compensation/salary-disclosure.json") as {
  statutes: Record<string, { threshold: number | null; status: string; cite: string; basis: string }>;
};
const separation = readJson("rules/employment-standards/ca-2026-separation-additions.json") as {
  jurisdictions: { FED: { records_retention: { status: string; payroll_records_years: number | null } } };
};
const compensationSql = readFileSync(join(root, "schema/0011_compensation_decisions.sql"), "utf8");

test("ANA-001 metrics as of a date match the rows in force that day", () => {
  const result = metricAsOf({
    asOf: "2026-06-01",
    rows: [
      { id: "a", kind: "person", fte: "1.00", from: "2026-01-01", to: null },
      { id: "b", kind: "person", fte: "0.50", from: "2026-01-01", to: "2026-06-01" },
      { id: "c", kind: "person", fte: "1.00", from: "2026-01-01", to: "2026-05-01" },
      { id: "v", kind: "vacancy", fte: "1.00", from: "2026-01-01", to: null },
    ],
    turnover: { formula: "leavers/average", leavers: "2", averageHeadcount: "8" },
  });
  assert.equal(result.headcount, 2);
  assert.equal(result.fte, "1.50");
  assert.equal(result.vacancies, 1);
  assert.equal(result.turnover, "0.25");
  assert.equal(codeOf(() => metricAsOf({ asOf: "2026-06-01", rows: [], turnover: { formula: "other", leavers: "1", averageHeadcount: "1" } })), "INPUT_REQUIRED");
});

test("ANA-002 a changed metric definition is a new version and the previous version remains", () => {
  const first = publishDefinition([], { code: "turnover", formula: "leavers/average", inclusions: "voluntary", exclusions: "death" });
  assert.equal(first[0].version, 1);
  const second = publishDefinition(first, { code: "turnover", formula: "leavers/average", inclusions: "voluntary", exclusions: "death and transfer" });
  assert.equal(second.length, 2);
  assert.equal(second[0].version, 1);
  assert.equal(second[0].exclusions, "death");
  assert.equal(currentDefinition(second, "turnover").version, 2);
});

test("ANA-003 a report omits a denied field, masks a masked field, and a scheduled run uses the current permission set", () => {
  const fields = [
    { name: "name", value: "Ada", access: "allow" as const },
    { name: "pay", value: "10.00", access: "deny" as const },
    { name: "sin", value: "123", access: "mask" as const },
  ];
  const full = buildReport({ fields, readable: ["name", "pay", "sin"], lang: "en-CA" });
  assert.deepEqual(full.columns.map((column) => column.name), ["name", "sin"]);
  assert.equal(full.columns[1].value, screen["en-CA"].masked);
  assert.equal(full.columns.some((column) => column.value === "10.00"), false);
  const scheduled = buildReport({ fields, readable: ["name"], lang: "en-CA" });
  assert.deepEqual(scheduled.columns, [{ name: "name", value: "Ada" }]);
});

test("ANA-004 small groups are suppressed, and one suppressed cell also hides the smallest complement", () => {
  const hidden = suppressGroups(
    [
      { id: "a", count: 12 },
      { id: "b", count: 11 },
      { id: "c", count: 7 },
    ],
    10,
  );
  assert.deepEqual(hidden.shown, ["a"]);
  assert.deepEqual(hidden.suppressed, ["c", "b"]);
  const two = suppressGroups(
    [
      { id: "a", count: 12 },
      { id: "b", count: 4 },
      { id: "c", count: 3 },
    ],
    10,
  );
  assert.deepEqual(two.shown, ["a"]);
  assert.deepEqual(two.suppressed, ["b", "c"]);
  assert.notEqual(screen["en-CA"].suppressed, screen["fr-CA"].suppressed);
  assert.ok(screen["fr-CA"].suppressed.length > 0);
});

test("ANA-005 the catalogue lists the statutory reports, each with a source and a rule status", () => {
  const rows = statutoryCatalogue({ reports: catalogue.reports, statutes: disclosure.statutes });
  for (const code of ["BC_PAY_TRANSPARENCY", "FED_EMPLOYMENT_EQUITY", "EHT", "WCB_ANNUAL", "UNION_DUES_REMITTANCE", "ON_PSSDA"]) {
    const row = rows.find((item) => item.code === code);
    assert.ok(row);
    assert.ok(row.cite.length > 0);
    assert.ok(row.source.length > 0);
    assert.ok(row.status.length > 0);
  }
});

test("ANA-006 factors are shown and an employment decision waits for a person and a supplied review interval", () => {
  const explained = explainRisk({ factors: ["tenure", "overtime hours"] });
  assert.deepEqual(explained.factors, ["tenure", "overtime hours"]);
  assert.equal(explained.modelScore, null);
  assert.equal(codeOf(() => explainRisk({ factors: null })), "INPUT_REQUIRED");
  assert.equal(codeOf(() => applyEmploymentDecision({ humanReviewed: false, reviewEveryMonths: 3, lastTestOn: "2026-01-01", asOf: "2026-02-01" })), "INPUT_REQUIRED");
  assert.equal(codeOf(() => applyEmploymentDecision({ humanReviewed: true, reviewEveryMonths: null, lastTestOn: "2026-01-01", asOf: "2026-02-01" })), "SETTING_NOT_SET");
  assert.equal(codeOf(() => applyEmploymentDecision({ humanReviewed: true, reviewEveryMonths: 3, lastTestOn: null, asOf: "2026-02-01" })), "INPUT_REQUIRED");
  assert.deepEqual(applyEmploymentDecision({ humanReviewed: true, reviewEveryMonths: 3, lastTestOn: "2026-01-01", asOf: "2026-02-01" }), { decidedByPerson: true });
});

test("ANA-007 a BI export for another tenant is empty and masking matches the report", () => {
  const rows = [{ fields: [{ name: "sin", value: "123", access: "mask" as const }] }];
  assert.deepEqual(biExport({ recordTenant: "a", readerTenant: "b", rows, readable: ["sin"], lang: "en-CA" }), []);
  const own = biExport({ recordTenant: "a", readerTenant: "a", rows, readable: ["sin"], lang: "fr-CA" });
  assert.equal(own[0].columns[0].value, screen["fr-CA"].masked);
});

test("LR-001 an imported agreement stores the SHA-256, the registry reference, and the linked units and entities", () => {
  const bytes = new TextEncoder().encode("agreement");
  const stored = importAgreement({ bytes, registryRef: "reg-1", bargainingUnitIds: ["bu"], legalEntityIds: ["le"] });
  assert.equal(stored.sha256, createHash("sha256").update(bytes).digest("hex"));
  assert.equal(stored.sha256.length, 64);
  assert.deepEqual(stored.bargainingUnitIds, ["bu"]);
  assert.equal(codeOf(() => importAgreement({ bytes, registryRef: null, bargainingUnitIds: ["bu"], legalEntityIds: ["le"] })), "INPUT_REQUIRED");
});

test("LR-002 proposed rules carry the article, the quote, extracted_by ai, and verified false, and the example file validates", () => {
  const example = readJson("rules/agreements/example-municipal-agreement.json");
  assert.doesNotThrow(() => validateAgreementDocument(example));
  const proposed = proposeRules([{ id: "ot", article: "12.1", quote: "overtime after 8" }]);
  assert.equal(proposed[0].extracted_by, "ai");
  assert.equal(proposed[0].verified, false);
  assert.equal(proposed[0].article, "12.1");
});

test("LR-003 activation is refused while a rule is unverified, records the verifier, and needs two people", () => {
  const proposed = proposeRules([{ id: "ot", article: "12.1", quote: "overtime after 8" }]);
  const refused = codeOf(() => activateAgreement({ ruleRows: proposed, approverIds: ["hr", "lr"], agreementRules: null, answers: [] }));
  assert.equal(refused, "UNVERIFIED_RULES");
  try {
    activateAgreement({ ruleRows: proposed, approverIds: ["hr", "lr"], agreementRules: null, answers: [] });
    assert.fail("expected throw");
  } catch (error) {
    assert.ok(error instanceof AnalyticsError);
    assert.equal(error.status, 422);
  }
  const verified = verifyRule(proposed[0], "person-2", "12.1", "overtime after 8");
  assert.equal(verified.verifierId, "person-2");
  assert.equal(verified.clause, "12.1");
  assert.equal(verified.quote, "overtime after 8");
  assert.equal(codeOf(() => activateAgreement({ ruleRows: [verified], approverIds: ["hr"], agreementRules: null, answers: [] })), "INPUT_REQUIRED");
  assert.deepEqual(activateAgreement({ ruleRows: [verified], approverIds: ["hr", "lr"], agreementRules: null, answers: [] }), { activated: true });
});

test("LR-004 a renewal copies the previous version and only a changed rule loses verification", () => {
  const next = renewAgreement(
    [
      { id: "ot", verified: true, text: "after 8" },
      { id: "night", verified: true, text: "flat" },
    ],
    [{ id: "ot", text: "after 7" }],
  );
  assert.deepEqual(next.changed, ["ot"]);
  assert.equal(next.rules[0].verified, false);
  assert.equal(next.rules[1].verified, true);
  assert.equal(next.rules[1].text, "flat");
});

test("LR-005 retro_from previews requests and a total, and nothing is applied", () => {
  const none = retroPreview({ retroFrom: null, lines: [{ id: "r1", cost: "10.00" }] });
  assert.deepEqual(none.requestIds, []);
  assert.equal(none.applied, false);
  const preview = retroPreview({ retroFrom: "2026-01-01", lines: [{ id: "r1", cost: "10.00" }, { id: "r2", cost: "2.50" }] });
  assert.deepEqual(preview.requestIds, ["r1", "r2"]);
  assert.equal(preview.total, "12.50");
  assert.equal(preview.applied, false);
});

test("LR-006 a sandbox shows the old result, the new result, and the total difference", () => {
  const result = sandboxCost([
    { id: "a", before: "100.00", after: "103.00" },
    { id: "b", before: "50.00", after: "50.00" },
  ]);
  assert.equal(result.lines[0].delta, "3.00");
  assert.equal(result.lines[1].delta, "0.00");
  assert.equal(result.totalDelta, "3.00");
});

test("LR-007 open combinations, an inconsistent premium, and the specialist's answer", () => {
  const example = readJson("rules/agreements/example-municipal-agreement.json") as {
    versions: Array<{ rules: Record<string, unknown> }>;
  };
  const unresolved = caseRules(example.versions[0].rules, {
    rules_override: { pay_composition: { multiplier_conflicts: { default_resolution: null, default_cite: null } } },
  });
  const open = openCombinations(unresolved, "en-CA");
  const holiday = open.find((problem) => problem.detail === "weekly+holiday");
  assert.ok(holiday);
  assert.equal(holiday.code, "UNRESOLVED_INTERACTION");
  assert.equal(holiday.question, screen["en-CA"].weeklyHoliday);
  assert.equal(combinationQuestion("second_rest_day+holiday", "en-CA"), screen["en-CA"].restDayHoliday);
  assert.notEqual(screen["en-CA"].restDayHoliday, screen["fr-CA"].restDayHoliday);
  try {
    activateAgreement({ ruleRows: [{ verified: true }], approverIds: ["hr", "lr"], agreementRules: unresolved, answers: [] });
    assert.fail("expected throw");
  } catch (error) {
    assert.ok(error instanceof AnalyticsError);
    assert.equal(error.status, 422);
    assert.equal(error.code, "UNRESOLVED_INTERACTION");
  }
  const flat = caseRules(example.versions[0].rules, { premium_override: { SHIFT_NIGHT: { in_regular_rate: true } } });
  const inconsistent = openCombinations(flat, "en-CA");
  assert.ok(inconsistent.some((problem) => problem.code === "INCONSISTENT_INTERACTION" && problem.detail.includes("SHIFT_NIGHT")));
  assert.equal(
    codeOf(() => activateAgreement({ ruleRows: [{ verified: true }], approverIds: ["hr", "lr"], agreementRules: flat, answers: [] })),
    "INCONSISTENT_INTERACTION",
  );
  const answer = recordCombinationAnswer({ detail: "weekly+holiday", article: "12.4", by: "specialist-1" });
  assert.equal(answer.article, "12.4");
  assert.equal(answer.by, "specialist-1");
  const explained = explainPayLine({ articles: [answer.article], sources: ["weekly", "holiday"] });
  assert.ok(explained.text.includes("12.4"));
  const overlap = [
    { id: "a", applies_to: { locations: ["north"] } },
    { id: "b", applies_to: { locations: ["north"] } },
  ];
  assert.equal(codeOf(() => resolveScope(overlap, { location: "north" }, "overtime")), "AMBIGUOUS_SCOPE");
  const prevailing = resolveScope(
    [
      { id: "letter", applies_to: { locations: ["north"] }, precedence: "prevails" },
      { id: "other", applies_to: { locations: ["north"] } },
    ],
    { location: "north" },
    "overtime",
  );
  assert.equal(prevailing?.id, "letter");
});

test("LR-010 a grievance keeps the article, the agreement's deadline, and is hidden from a role that is not LR", () => {
  const grievance = openGrievance({
    article: "9.2",
    stepDays: 10,
    openedOn: "2026-03-01",
    meetings: ["2026-03-02"],
    outcome: null,
    documents: ["doc-1"],
  });
  assert.equal(grievance.deadline, "2026-03-11");
  assert.equal(grievance.article, "9.2");
  assert.deepEqual(grievanceAlert({ role: "manager", asOf: "2026-03-05", deadline: grievance.deadline, remindDays: 7 }), { visible: false, alert: false });
  assert.deepEqual(grievanceAlert({ role: "lr", asOf: "2026-03-05", deadline: grievance.deadline, remindDays: 7 }), { visible: true, alert: true });
});

test("LR-011 a strike schedule below the agreement's essential minimum is not allowed", () => {
  const blocked = strikeSchedule({ strike: true, scheduled: 2, required: 4 });
  assert.equal(blocked.allowed, false);
  assert.equal(blocked.shortfall, 2);
  assert.equal(blocked.payrollStopped, true);
  assert.deepEqual(strikeSchedule({ strike: false, scheduled: 1, required: 4 }), { allowed: true, shortfall: 0, payrollStopped: false });
});

test("pattern settlements are one inactive draft per agreement", () => {
  const drafts = applyPattern(["inside", "outside"]);
  assert.equal(drafts.length, 2);
  assert.equal(drafts[0].verified, false);
  assert.equal(drafts[0].activated, false);
  assert.equal(drafts[1].agreementId, "outside");
});

test("ENT-005 an open layoff keeps the grouping it started with", () => {
  const groupings = reorgGroupings([
    { id: "open", openLayoff: true, openBumping: false, openRecall: false, startedGrouping: "branch-a", nextGrouping: "branch-b" },
    { id: "next", openLayoff: false, openBumping: false, openRecall: false, startedGrouping: "branch-a", nextGrouping: "branch-b" },
  ]);
  assert.equal(groupings[0].grouping, "branch-a");
  assert.equal(groupings[1].grouping, "branch-b");
});

test("ENT-025 a labour board move is one change set once the grid and seniority terms are confirmed", () => {
  const ids = Array.from({ length: 40 }, (_, index) => `p${String(index)}`);
  assert.equal(codeOf(() => transferPositions({ positionIds: ids, gridConfirmed: false, seniorityTerms: "by hours", effectiveOn: "2026-04-01", grievanceIds: ["g1"] })), "INPUT_REQUIRED");
  const moved = transferPositions({ positionIds: ids, gridConfirmed: true, seniorityTerms: "by hours", effectiveOn: "2026-04-01", grievanceIds: ["g1"] });
  assert.equal(moved.changeSets, 1);
  assert.equal(moved.positionCount, 40);
  assert.equal(moved.duesFrom, "2026-04-01");
  assert.deepEqual(moved.grievanceIds, ["g1"]);
  assert.equal(moved.seniorityConverted, true);
});

test("ENT-032 a funder-report viewer sees only the named funding source", () => {
  const lines = funderView({
    source: "youth",
    lines: [
      { source: "youth", amount: "10.00" },
      { source: "roads", amount: "99.00" },
    ],
  });
  assert.deepEqual(lines, [{ source: "youth", amount: "10.00" }]);
});

test("PRIV-001 an access request uses the caller-supplied statutory days, redacts, and logs identifiers only", () => {
  assert.equal(codeOf(() => openAccessRequest({ receivedOn: "2026-01-01", dueDays: null, fields: [], lang: "en-CA" })), "JURISDICTION_RULE_MISSING");
  const opened = openAccessRequest({
    receivedOn: "2026-01-01",
    dueDays: 10,
    fields: [{ name: "note", value: "SIN-VALUE", redact: true }],
    lang: "en-CA",
  });
  assert.equal(opened.dueOn, addDays("2026-01-01", 10));
  assert.equal(opened.fields[0].value, screen["en-CA"].redacted);
  assert.equal(opened.fields[0].value.includes("SIN-VALUE"), false);
  const log = deliverAccess({ requestId: "req-1", fieldNames: ["note"] });
  assert.equal(JSON.stringify(log).includes("SIN-VALUE"), false);
});

test("PRIV-002 retention previews payroll records from the rule file and does not destroy while the entry is check-before-use", () => {
  const rule = separation.jurisdictions.FED.records_retention;
  assert.equal(rule.status, "verify_at_load");
  assert.equal(typeof rule.payroll_records_years, "number");
  const sunset = addYears("2019-12-31", rule.payroll_records_years ?? 0);
  const past = addDays(sunset, 1);
  const result = retentionRun({
    rule,
    asOf: past,
    records: [
      { id: "past", on: past, taxYearEnd: "2019-12-31", legalHold: false },
      { id: "sunset", on: sunset, taxYearEnd: "2019-12-31", legalHold: false },
      { id: "held", on: past, taxYearEnd: "2019-12-31", legalHold: true },
    ],
  });
  assert.deepEqual(result.destroy, []);
  assert.equal(result.blocked, "RULE_NOT_VERIFIED");
  assert.deepEqual(result.preview, ["past"]);
});

test("PRIV-003 a move of Quebec personal information waits for a privacy impact assessment, and an incident stores the case id and date", () => {
  assert.equal(codeOf(() => moveOutsideQuebec({ quebecResidents: true, piaRecorded: false })), "INPUT_REQUIRED");
  assert.deepEqual(moveOutsideQuebec({ quebecResidents: true, piaRecorded: true }), { allowed: true });
  assert.deepEqual(logIncident({ id: "inc-1", on: "2026-05-01" }), { id: "inc-1", on: "2026-05-01" });
});

test("PRIV-004 a dedicated database can grant and revoke support, and the tenant can export its rows", () => {
  let store = setDedicatedDatabase({ dedicated: false, supportGranted: false, rows: [{ id: "row-1" }] });
  assert.equal(store.dedicated, true);
  assert.deepEqual(exportTenant(store, true), []);
  store = grantSupport(store);
  assert.deepEqual(exportTenant(store, true), [{ id: "row-1" }]);
  store = revokeSupport(store);
  assert.deepEqual(exportTenant(store, true), []);
  assert.equal(JSON.stringify(exportTenant(store, false)), JSON.stringify([{ id: "row-1" }]));
});

test("EQ-001 self-identification needs a consent version, is marked encrypted, and a manager sees no person", () => {
  assert.equal(codeOf(() => recordSelfId({ consentVersion: null, categories: ["indigenous"] })), "INPUT_REQUIRED");
  const recorded = recordSelfId({ consentVersion: "2026-01", categories: ["indigenous"] });
  assert.equal(recorded.encrypted, true);
  const floor = Number(settingDefault(compensationSql, "privacy.min_group_size_self_id"));
  const aggregate = equityAggregate({ cells: [{ id: "indigenous", count: floor - 1 }, { id: "other", count: 20 }], minimum: floor });
  assert.equal(aggregate.shown.includes("indigenous"), false);
  assert.deepEqual(managerEquityView(), { people: [] });
});

test("EQ-002 a manager sees limitations and measures, and attendance leaves out accommodation absences", () => {
  const manager = accommodationView({ role: "manager", medical: "diagnosis", limitations: "no lifting", measures: "cart" });
  assert.equal("medical" in manager, false);
  assert.equal(manager.limitations, "no lifting");
  const hr = accommodationView({ role: "hr", medical: "diagnosis", limitations: "no lifting", measures: "cart" });
  assert.equal(hr.medical, "diagnosis");
  assert.equal(attendanceTotal([{ days: "2.00", accommodationRelated: true }, { days: "3.00", accommodationRelated: false }]), "3.00");
});

test("HS-001 an incident keeps the facts, a board deadline waits for a verified rule, and top-up needs the agreement rule", () => {
  const kept = recordIncident({
    facts: "slip in the hall",
    medical: "diagnosis",
    role: "manager",
    on: "2026-04-01",
    notifyDays: null,
    ruleStatus: "verify_at_load",
    lostTime: false,
    topUpRule: null,
    topUpAmount: null,
  });
  assert.equal(kept.facts, "slip in the hall");
  assert.equal(kept.medical, null);
  assert.equal(kept.deadline, null);
  assert.equal(kept.deadlineStatus, "RULE_NOT_VERIFIED");
  assert.equal(
    codeOf(() => recordIncident({ facts: "slip", medical: null, role: "hr", on: "2026-04-01", notifyDays: null, ruleStatus: null, lostTime: true, topUpRule: null, topUpAmount: null })),
    "INPUT_REQUIRED",
  );
  const topped = recordIncident({
    facts: "slip",
    medical: null,
    role: "hr",
    on: "2026-04-01",
    notifyDays: 3,
    ruleStatus: "verified",
    lostTime: true,
    topUpRule: "article-15",
    topUpAmount: "120.00",
  });
  assert.equal(topped.deadline, "2026-04-04");
  assert.equal(topped.topUpAmount, "120.00");
  assert.equal(topped.topUpRule, "article-15");
});

test("COMPL-001 one calendar carries the T4 and pay-transparency dates, the owner, and the organization's reminder", () => {
  const calendar = complianceCalendar({
    entityId: "city",
    year: 2027,
    asOf: "2027-02-20",
    remindDaysBefore: 10,
    ownerId: "finance-1",
    entries: [catalogue.reports.T4, catalogue.reports.BC_PAY_TRANSPARENCY, catalogue.reports.EHT].map((entry, index) => ({
      code: ["T4", "BC_PAY_TRANSPARENCY", "EHT"][index],
      due: entry.due,
      form_status: entry.form_status,
    })),
  });
  assert.equal(calendar.entityId, "city");
  const t4 = calendar.items.find((item) => item.code === "T4");
  const bc = calendar.items.find((item) => item.code === "BC_PAY_TRANSPARENCY");
  const eht = calendar.items.find((item) => item.code === "EHT");
  assert.equal(t4?.dueOn, "2027-02-28");
  assert.equal(t4?.ownerId, "finance-1");
  assert.equal(t4?.remind, true);
  assert.equal(bc?.dueOn, "2027-11-01");
  assert.equal(eht?.dueOn, null);
  assert.equal(eht?.blocked, "RULE_NOT_VERIFIED");
  assert.equal(codeOf(() => filingDue(catalogue.reports.EHT, 2027)), "RULE_NOT_VERIFIED");
  const leap = complianceCalendar({
    entityId: "city",
    year: 2028,
    asOf: "2028-01-01",
    remindDaysBefore: 10,
    ownerId: "finance-1",
    entries: [{ code: "T4", due: catalogue.reports.T4.due, form_status: catalogue.reports.T4.form_status }],
  });
  assert.equal(leap.items[0].dueOn, "2028-02-29");
});

test("COMP-030 a pay-gap group under the setting floor is hidden, and a lower floor is refused", () => {
  const floor = Number(settingDefault(compensationSql, "privacy.min_group_size_self_id"));
  const minimumFloor = settingMin(compensationSql, "privacy.min_group_size_self_id");
  const allowed = JSON.parse(settingDefault(compensationSql, "pay_gap.groups")) as string[];
  assert.equal(codeOf(() => payGapReport({ floor: minimumFloor - 2, minimumFloor, allowed, groups: [] })), "SETTING_BELOW_MINIMUM");
  const hidden = payGapReport({
    floor,
    minimumFloor,
    allowed,
    groups: [
      { id: "indigenous", category: "indigenous", count: floor - 3, consented: true },
      { id: "open", category: "gender", count: 20, consented: false },
    ],
  });
  assert.equal(hidden.every((group) => group.hidden), true);
  assert.equal(codeOf(() => payGapReport({ floor, minimumFloor, allowed, groups: [{ id: "x", category: "shoe", count: 20, consented: true }] })), "LIST_VALUE_UNKNOWN");
});

test("COMP-031 a BC employer at the file's count in October 2026 gets the 1 November draft, and a federal employer gets both federal drafts", () => {
  const report = catalogue.reports.BC_PAY_TRANSPARENCY;
  const produced = bcPayTransparency({ report, employeeCount: 60, asOf: "2026-10-15" });
  assert.equal(produced.produced, true);
  assert.equal(produced.dueOn, "2026-11-01");
  assert.equal(produced.filed, false);
  const below = bcPayTransparency({ report, employeeCount: (report.min_employees ?? 0) - 1, asOf: "2026-10-15" });
  assert.equal(below.produced, false);
  assert.equal(codeOf(() => fileStatutoryReport(report)), "RULE_NOT_VERIFIED");
  const federal = federalEquityReports({ reports: catalogue.reports, federallyRegulated: true });
  assert.deepEqual(federal.map((item) => item.code), ["FED_PAY_EQUITY", "FED_EMPLOYMENT_EQUITY"]);
  assert.equal(federal.every((item) => item.filed === false), true);
  assert.deepEqual(federalEquityReports({ reports: catalogue.reports, federallyRegulated: false }), []);
});

test("COMP-033 a salary disclosure list is drafted from the statute file and publication waits for HR, finance, and a verified statute", () => {
  const statute = disclosure.statutes.ON_PSSDA;
  const people = [
    { id: "at", paid: "100000.00" },
    { id: "under", paid: "99999.99" },
  ];
  const draft = draftSalaryDisclosure({ statute, people, publish: false });
  assert.deepEqual(draft.listed, ["at"]);
  assert.equal(draft.published, false);
  const route = {
    steps: [{ role: "hr" }, { role: "finance" }],
    approvals: [
      { role: "hr", approverId: "person-hr" },
      { role: "finance", approverId: "person-finance" },
    ],
  };
  assert.equal(
    codeOf(() => draftSalaryDisclosure({ statute, people, publish: true, preparerId: "preparer", route: { steps: route.steps, approvals: [] } })),
    "DISCLOSURE_NOT_APPROVED",
  );
  assert.equal(
    codeOf(() => draftSalaryDisclosure({ statute, people, publish: true, preparerId: "person-hr", route })),
    "SELF_APPROVAL",
  );
  assert.equal(
    codeOf(() => draftSalaryDisclosure({ statute, people, publish: true, preparerId: "preparer", route })),
    "RULE_NOT_VERIFIED",
  );
  const executives = disclosure.statutes.BC_PSEC_EXECUTIVE;
  const named = draftSalaryDisclosure({
    statute: executives,
    people: [
      { id: "exec", paid: "1.00", inPopulation: true },
      { id: "staff", paid: "200000.00", inPopulation: false },
    ],
    publish: false,
  });
  assert.deepEqual(named.listed, ["exec"]);
  assert.equal(codeOf(() => draftSalaryDisclosure({ statute: executives, people: [{ id: "x", paid: "1.00" }], publish: false })), "INPUT_REQUIRED");
});

test("analytics reads are empty for another tenant", () => {
  assert.deepEqual(readAnalytics("a", "b", [{ id: "1" }]), []);
  assert.deepEqual(readAnalytics("a", "a", [{ id: "1" }]), [{ id: "1" }]);
});
