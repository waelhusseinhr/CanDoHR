import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { AssistantError } from "../src/errors.ts";
import {
  TOOLS,
  anomalyChecks,
  assistantPanel,
  compareNet,
  dataQuality,
  draftFromTemplate,
  draftJobDescription,
  enrolmentAnswer,
  explainPay,
  forecast,
  postingAiDisclosure,
  preRunChecks,
  previewConsequences,
  proposeAgreementRule,
  rankCodesFromDuties,
  reminders,
  runTool,
  screen,
  searchDocuments,
  smartDefaults,
  titleSearch,
  writingHelp,
  type ToolName,
} from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");

function settingDefault(sql: string, key: string): string {
  const pattern = new RegExp(`\\('${key}',\\s*'[^']+',\\s*'[^']+',\\s*(?:NULL|'(?:[^']|'')*'),\\s*(NULL|'(?:[^']|'')*')`);
  const match = pattern.exec(sql);
  if (!match) throw new Error(key);
  const raw = match[1];
  if (raw === "NULL") throw new Error(key);
  return raw.slice(1, -1).replaceAll("''", "'");
}

function codeOf(run: () => void): string {
  try {
    run();
  } catch (error) {
    if (error instanceof AssistantError) return error.code;
    throw error;
  }
  throw new Error("did not throw");
}

const benefitsSql = readFileSync(join(root, "schema/0012_benefits_decisions.sql"), "utf8");
const performanceSql = readFileSync(join(root, "schema/0014_performance_decisions.sql"), "utf8");
const valuesSql = readFileSync(join(root, "schema/0008_values_and_languages.sql"), "utf8");
const schemaSql = readFileSync(join(root, "schema/cando_schema.sql"), "utf8");
const residency = JSON.parse(settingDefault(valuesSql, "tenant.default_residency")) as string;
const enrolmentDefault = settingDefault(benefitsSql, "benefits.ai_enrolment_assistant");
const writingDefault = settingDefault(performanceSql, "performance.ai_writing_help");

test("docs/12 §5.1 a manager cannot read an employee outside their subtree", () => {
  const calls: { tool: string; token: string }[] = [];
  const turn = runTool({
    panelEnabled: true,
    token: "user-token",
    tool: "get_record",
    args: { recordId: "outside", salary: "88888.88" },
    lang: "en-CA",
    api: {
      call(tool, _args, token) {
        calls.push({ tool, token });
        return { access: "denied" };
      },
    },
  });
  assert.equal(turn.answer, screen["en-CA"].cannotAccess);
  assert.equal(turn.committed, false);
  assert.equal(turn.modelCalled, false);
  assert.equal(calls[0].token, "user-token");
  assert.equal(JSON.stringify(turn.log).includes("88888.88"), false);
  assert.deepEqual(turn.log, { tool: "get_record", recordIds: ["outside"] });
  assert.notEqual(screen["en-CA"].cannotAccess, screen["fr-CA"].cannotAccess);
});

test("docs/12 §5.2 a raise is a draft change set and nothing is committed", () => {
  const stored = { rate: "100.00" };
  const turn = runTool({
    panelEnabled: true,
    token: "user-token",
    tool: "draft_change_set",
    args: { recordId: "ana", request: "10%" },
    lang: "en-CA",
    api: {
      call() {
        return {
          access: "ok",
          body: { id: "cs-1", status: "draft", operations: [{ entity: "rate", field: "amount", before: stored.rate, after: "110.00" }] },
        };
      },
    },
  });
  assert.equal(stored.rate, "100.00");
  assert.equal(turn.committed, false);
  assert.equal(turn.answer, screen["en-CA"].draft);
  assert.equal(turn.modelCalled, false);
  const cited = turn.cited as { status: string };
  assert.equal(cited.status, "draft");
});

test("docs/12 §5.3 an explanation uses only the numbers on the stored trace", () => {
  const trace: [string, string][] = [
    ["federal_tax", "243.16"],
    ["annual_taxable", "64462.00"],
  ];
  const direct = explainPay(trace);
  for (const value of trace.map((entry) => entry[1])) assert.ok(direct.text.includes(value));
  const turn = runTool({
    panelEnabled: true,
    token: "user-token",
    tool: "explain_pay_result",
    args: { recordId: "self" },
    lang: "en-CA",
    api: {
      call() {
        return { access: "ok", body: { trace } };
      },
    },
  });
  for (const value of trace.map((entry) => entry[1])) assert.ok(turn.answer.includes(value));
  assert.deepEqual(turn.cited, ["243.16", "64462.00"]);
});

test("docs/12 §5.4 an agreement question with no verified clause says it is not covered", () => {
  const turn = runTool({
    panelEnabled: true,
    token: "user-token",
    tool: "resolve_rules",
    args: { topic: "grandparent" },
    lang: "en-CA",
    api: {
      call() {
        return {
          access: "ok",
          body: {
            clauses: [
              { article: "15.02", topic: "grandparent", quote: "three days", verified: false },
              { article: "12.1", topic: "overtime", quote: "after 8", verified: true },
            ],
          },
        };
      },
    },
  });
  assert.equal(turn.answer, screen["en-CA"].notCovered);
  assert.equal(turn.cited, null);
  assert.equal(turn.answer.includes("three days"), false);
});

test("docs/12 §5.5 without a compliant endpoint the assistant stays off and the helpers still run", () => {
  assert.equal(schemaSql.includes("assistant_enabled boolean NOT NULL DEFAULT false"), true);
  assert.equal(residency, "CA");
  assert.deepEqual(assistantPanel({ assistantEnabled: false, residency, endpoints: [{ region: residency, trainsOnCustomerData: false }] }), { enabled: false });
  assert.deepEqual(assistantPanel({ assistantEnabled: true, residency, endpoints: [{ region: "EU", trainsOnCustomerData: false }] }), { enabled: false });
  assert.deepEqual(assistantPanel({ assistantEnabled: true, residency, endpoints: [{ region: residency, trainsOnCustomerData: true }] }), { enabled: false });
  assert.deepEqual(assistantPanel({ assistantEnabled: true, residency, endpoints: [{ region: residency, trainsOnCustomerData: false }] }), { enabled: true });
  assert.equal(codeOf(() => runTool({
    panelEnabled: false,
    token: "user-token",
    tool: "get_record",
    args: {},
    lang: "en-CA",
    api: { call: () => ({ access: "ok", body: {} }) },
  })), "ASSISTANT_OFF");
  assert.ok(explainPay([["net", "10.00"]]).text.includes("10.00"));
});

test("deterministic helpers preview consequences, compare net pay, and check a pay run", () => {
  const preview = previewConsequences({
    id: "cs-2",
    operations: [{ entity: "assignment", field: "unit", before: "roads", after: "buildings" }],
  });
  assert.equal(preview.committed, false);
  assert.equal(preview.consequences[0].after, "buildings");
  const compared = compareNet({ previous: "100.00", current: "58.80", reasons: ["CPP maximum was reset"] });
  assert.equal(compared.direction, "lower");
  assert.equal(compared.delta, "-41.20");
  assert.ok(compared.text.includes("41.20"));
  assert.equal(codeOf(() => compareNet({ previous: "10.00", current: "9.00", reasons: [] })), "INPUT_REQUIRED");
  const findings = preRunChecks({
    largePayment: "5000.00",
    people: [
      { id: "a", td1OnFile: false, rate: "15.00", minimumWage: "17.20", net: "-1.00", active: false, hasPay: true, bankChanged: true, payment: "5000.00" },
    ],
  });
  assert.deepEqual(findings.map((finding) => finding.code), ["MISSING_TD1", "BELOW_MINIMUM_WAGE", "NEGATIVE_NET", "INACTIVE_WITH_PAY", "BANK_CHANGE_LARGE_PAYMENT"]);
  assert.equal(codeOf(() => preRunChecks({
    largePayment: "1.00",
    people: [{ id: "b", td1OnFile: true, rate: "20.00", minimumWage: null, net: "1.00", active: true, hasPay: true, bankChanged: false, payment: null }],
  })), "JURISDICTION_RULE_MISSING");
});

test("anomaly rules, reminders, data quality, and smart defaults use the caller's settings", () => {
  const anomalies = anomalyChecks({
    varianceThreshold: "0.50",
    periods: [{ id: "p", previous: "100.00", current: "200.00" }],
    peerLimit: "80.00",
    peers: [{ id: "high", amount: "90.00" }],
    accounts: [
      { personId: "a", accountHash: "h1" },
      { personId: "b", accountHash: "h1" },
    ],
  });
  assert.deepEqual(anomalies.find((item) => item.code === "PERIOD_VARIANCE")?.ids, ["p"]);
  assert.deepEqual(anomalies.find((item) => item.code === "PEER_OUTLIER")?.ids, ["high"]);
  assert.deepEqual(anomalies.find((item) => item.code === "DUPLICATE_BANK")?.ids, ["a", "b"]);
  assert.equal(codeOf(() => anomalyChecks({ varianceThreshold: null, periods: [{ id: "p", previous: "1.00", current: "2.00" }], peerLimit: null, peers: [], accounts: [] })), "SETTING_NOT_SET");
  const due = reminders({
    asOf: "2026-03-01",
    withinDays: 7,
    items: [
      { id: "permit", kind: "permit", dueOn: "2026-03-05" },
      { id: "later", kind: "probation", dueOn: "2026-04-01" },
    ],
  });
  assert.deepEqual(due.map((item) => item.id), ["permit"]);
  assert.equal(codeOf(() => reminders({ asOf: "2026-03-01", withinDays: null, items: [] })), "SETTING_NOT_SET");
  const quality = dataQuality({
    asOf: "2026-06-01",
    staleDays: 30,
    fields: [
      { unitId: "works", field: "address", missing: true, updatedOn: null, fixForm: "address" },
      { unitId: "works", field: "phone", missing: false, updatedOn: "2026-01-01", fixForm: "phone" },
    ],
  });
  assert.deepEqual(quality.map((item) => item.reason), ["missing", "stale"]);
  assert.equal(quality[0].fixForm, "address");
  const defaults = smartDefaults({ nextPeriodStart: "2026-03-15", locationProvince: "MB", agreementId: "inside" });
  assert.deepEqual(defaults, { effectiveDate: "2026-03-15", taxProvince: "MB", agreementId: "inside" });
  assert.equal(codeOf(() => smartDefaults({ nextPeriodStart: "2026-03-15", locationProvince: null, agreementId: "inside" })), "INPUT_REQUIRED");
});

test("HR-021 a job description comes from the template and the assistant has no tool for it", () => {
  assert.equal(TOOLS.includes("search_people"), true);
  assert.equal((TOOLS as readonly string[]).some((tool) => tool.includes("job")), false);
  const draft = draftJobDescription({
    lead: "Leads a crew on the road.",
    duties: ["Sets the daily work."],
    requirements: ["A licence the law requires."],
  });
  assert.equal(draft.draft, true);
  assert.equal(draft.source, "template");
  assert.ok(draft.text.includes("Leads a crew on the road."));
  assert.equal(codeOf(() => rankCodesFromDuties()), "FEATURE_OFF");
  assert.deepEqual(titleSearch({ query: "crew", titles: [{ code: "70010", title: "Crew lead" }] }), [{ code: "70010", title: "Crew lead" }]);
});

test("BEN-023 the enrolment assistant stays off until switched on, cites the booklet, and never recommends", () => {
  assert.equal(enrolmentDefault, "false");
  const off = enrolmentAnswer({ enabled: false, booklet: [{ section: "4", text: "dental waiting period" }], topic: "dental", asksForRecommendation: false, lang: "en-CA" });
  assert.equal(off.enabled, false);
  assert.equal(off.text, null);
  const cited = enrolmentAnswer({ enabled: true, booklet: [{ section: "4", text: "dental waiting period" }], topic: "dental", asksForRecommendation: false, lang: "en-CA" });
  assert.equal(cited.section, "4");
  assert.equal(cited.recommends, false);
  assert.equal(cited.text, "dental waiting period");
  const refused = enrolmentAnswer({ enabled: true, booklet: [{ section: "4", text: "dental waiting period" }], topic: "dental", asksForRecommendation: true, lang: "fr-CA" });
  assert.equal(refused.recommends, false);
  assert.equal(refused.text, screen["fr-CA"].noRecommendation);
  assert.equal(refused.section, null);
});

test("performance writing help stays off, and when on it does not rate or recommend an ending", () => {
  assert.equal(writingDefault, "false");
  assert.equal(codeOf(() => writingHelp({ enabled: false, text: "meets the goal", blockedWords: [], asksForRating: false, asksToEndEmployment: false, lang: "en-CA" })), "FEATURE_OFF");
  assert.equal(codeOf(() => writingHelp({ enabled: true, text: "meets the goal", blockedWords: [], asksForRating: true, asksToEndEmployment: false, lang: "en-CA" })), "INPUT_REQUIRED");
  const help = writingHelp({ enabled: true, text: "meets the goal", blockedWords: ["meets"], asksForRating: false, asksToEndEmployment: false, lang: "en-CA" });
  assert.equal(help.ai, true);
  assert.equal(help.editable, true);
  assert.equal(help.visibleToEmployee, true);
  assert.deepEqual(help.flags, ["meets"]);
  assert.equal(help.text, "meets the goal");
});

test("document search drops records the user cannot read before it ranks them", () => {
  const found = searchDocuments({
    query: "bereavement",
    documents: [
      { id: "secret", text: "bereavement SECRET-PAY", permitted: false },
      { id: "policy", text: "bereavement leave", permitted: true },
    ],
  });
  assert.deepEqual(found.map((document) => document.id), ["policy"]);
  assert.equal(JSON.stringify(found).includes("SECRET-PAY"), false);
});

test("a forecast is labelled as an estimate, a template fills its slots, and a proposed rule stays unverified", () => {
  const estimate = forecast({ inputs: [{ name: "overtime", amount: "10.00" }, { name: "retro", amount: "2.50" }] });
  assert.equal(estimate.estimate, true);
  assert.equal(estimate.total, "12.50");
  assert.equal(estimate.inputs[0].amount, "10.00");
  const letter = draftFromTemplate({ template: "Hello {name}", slots: { name: "Ana" } });
  assert.equal(letter.draft, true);
  assert.equal(letter.text, "Hello Ana");
  const rule = proposeAgreementRule({ article: "15.02", quote: "three days" });
  assert.equal(rule.verified, false);
  assert.equal(rule.extracted_by, "ai");
  assert.equal(codeOf(() => postingAiDisclosure({ disclosureRequired: true, usesAiScreening: true, disclosed: false })), "INPUT_REQUIRED");
  assert.deepEqual(postingAiDisclosure({ disclosureRequired: false, usesAiScreening: true, disclosed: false }), { ok: true });
  assert.equal(codeOf(() => runTool({
    panelEnabled: true,
    token: null,
    tool: "search_people" satisfies ToolName,
    args: {},
    lang: "en-CA",
    api: { call: () => ({ access: "ok", body: {} }) },
  })), "INPUT_REQUIRED");
});
