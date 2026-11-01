import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { AgreementLibrary } from "../src/agreements.ts";
import { RulesError } from "../src/errors.ts";
import { EditionStore, sha256 } from "../src/editions.ts";
import { proposeGridFloor } from "../src/grid-floor.ts";
import { compareResolutions, resolve, type EmploymentStandardsEdition } from "../src/resolve.ts";
import { validateAgreementDocument } from "../src/schema.ts";
import { selectScopedRule } from "../src/scope.ts";
import { accrueSeniorityPoints } from "../src/seniority.ts";
import { caseRules, validate } from "../src/stacking.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");

test("every rules file loads and the employment-standards edition stays unverified in production", () => {
  const store = new EditionStore();
  const records = store.loadDirectory();
  assert.ok(records.length >= 20);
  assert.ok(records.every((record) => record.sha256.length === 64));
  const standards = records.find((record) => record.path === "employment-standards/ca-2026.json");
  assert.ok(standards);
  assert.equal(standards.status, "verify_at_load");
  const loaded = store.loadForCalculation(standards.sha256) as { id: string };
  assert.equal(loaded.id, "CA-EMPLOYMENT-STANDARDS-2026");
  assert.doesNotThrow(() => store.activate(standards.sha256, "sandbox"));
  assert.throws(
    () => store.activate(standards.sha256, "production"),
    (error: unknown) => error instanceof RulesError && error.code === "VERIFY_AT_LOAD" && error.status === 422,
  );
});

test("a calculation load refuses bytes that do not match the pinned hash", () => {
  const store = new EditionStore();
  const bytes = Buffer.from('{"id":"changed"}');
  store.remember(sha256(Buffer.from('{"id":"original"}')), bytes);
  assert.throws(
    () => store.loadForCalculation(sha256(Buffer.from('{"id":"original"}'))),
    (error: unknown) => error instanceof RulesError && error.code === "HASH_MISMATCH",
  );
});

test("the example agreement matches agreement.schema.json", () => {
  const example = JSON.parse(readFileSync(join(root, "rules/agreements/example-municipal-agreement.json"), "utf8"));
  assert.doesNotThrow(() => validateAgreementDocument(example));
});

test("LR-007 refuses a version that does not say how weekly overtime meets a holiday", () => {
  const example = JSON.parse(readFileSync(join(root, "rules/agreements/example-municipal-agreement.json"), "utf8")) as {
    versions: Array<{ version: number; rules: Record<string, unknown> }>;
  };
  const rules = caseRules(example.versions[0].rules, {
    rules_override: {
      pay_composition: { multiplier_conflicts: { default_resolution: null, default_cite: null } },
    },
  });
  const library = new AgreementLibrary();
  const saved = library.save({ id: "example:1", version: 1, rules });
  assert.deepEqual(library.loadByHash(saved.contentSha256), library.loadByHash(saved.contentSha256));
  assert.throws(
    () => library.verify(saved.id),
    (error: unknown) => {
      if (!(error instanceof RulesError)) return false;
      return (
        error.status === 422 &&
        error.problems.some((problem) => problem.code === "UNRESOLVED_INTERACTION" && problem.detail === "weekly+holiday")
      );
    },
  );
  assert.throws(() => library.activate(saved.id), (error: unknown) => error instanceof RulesError && error.status === 422);
});

test("LR-007 refuses a regular-rate premium that is flat on overtime", () => {
  const example = JSON.parse(readFileSync(join(root, "rules/agreements/example-municipal-agreement.json"), "utf8")) as {
    versions: Array<{ rules: Record<string, unknown> }>;
  };
  const rules = caseRules(example.versions[0].rules, {
    premium_override: { SHIFT_NIGHT: { in_regular_rate: true } },
  });
  const problems = validate(rules);
  assert.ok(
    problems.some(
      (problem) => problem.code === "INCONSISTENT_INTERACTION" && problem.detail.includes("SHIFT_NIGHT"),
    ),
  );
  const library = new AgreementLibrary();
  const saved = library.save({ id: "flat-regular", rules });
  assert.throws(() => library.activate(saved.id), (error: unknown) => error instanceof RulesError && error.status === 422);
});

test("a verified agreement version cannot be edited", () => {
  const library = new AgreementLibrary();
  const saved = library.save({ id: "empty", rules: {} });
  library.verify(saved.id);
  assert.throws(
    () => library.save({ id: "empty", rules: { overtime: {} } }),
    (error: unknown) => error instanceof RulesError && error.code === "IMMUTABLE",
  );
});

test("ON, BC and AB read overtime and minimum wage from the edition", () => {
  const store = new EditionStore();
  const records = store.loadDirectory();
  const standards = records.find((record) => record.path === "employment-standards/ca-2026.json");
  assert.ok(standards);
  const edition = store.loadForCalculation(standards.sha256) as EmploymentStandardsEdition;
  for (const jurisdiction of ["ON", "BC", "AB"] as const) {
    const file = edition.jurisdictions?.[jurisdiction];
    assert.ok(file?.overtime && file.minimum_wage);
    const result = resolve({
      jurisdiction,
      date: "2026-11-01",
      serviceYears: 5,
      edition,
      editionHash: standards.sha256,
      agreement: null,
    });
    assert.equal(result.minimumWage?.source, `es:${jurisdiction}`);
    assert.equal(result.minimumWage?.amount, String(file.minimum_wage?.general));
    assert.equal(result.agreement, null);
    if (typeof file.overtime.weekly_after === "number") {
      assert.ok(
        result.overtime.some(
          (tier) =>
            tier.basis === "weekly" &&
            tier.afterHours === String(file.overtime?.weekly_after) &&
            tier.source === `es:${jurisdiction}`,
        ),
      );
    }
    if (typeof file.overtime.daily_after === "number") {
      assert.ok(
        result.overtime.some(
          (tier) => tier.basis === "daily" && tier.afterHours === String(file.overtime?.daily_after),
        ),
      );
    }
  }
});

test("an agreement-covered employee keeps the greater right and names the source", () => {
  const store = new EditionStore();
  const standards = store.loadDirectory().find((record) => record.path === "employment-standards/ca-2026.json");
  assert.ok(standards);
  const edition = store.loadForCalculation(standards.sha256) as EmploymentStandardsEdition;
  const example = JSON.parse(readFileSync(join(root, "rules/agreements/example-municipal-agreement.json"), "utf8")) as {
    agreement: { id: string };
    versions: Array<{ version: number; rules: Record<string, unknown> }>;
  };
  const covered = resolve({
    jurisdiction: "ON",
    date: "2026-11-01",
    serviceYears: 5,
    edition,
    editionHash: standards.sha256,
    agreement: { id: example.agreement.id, version: example.versions[0].version, rules: example.versions[0].rules },
  });
  assert.equal(covered.agreement?.id, example.agreement.id);
  assert.ok(covered.overtime.some((tier) => tier.basis === "daily" && tier.afterHours === "7" && tier.source === "agreement:15"));
  assert.ok(covered.overtime.some((tier) => tier.basis === "weekly" && tier.afterHours === "35" && tier.source === "agreement:15"));
  assert.equal(covered.overtime.some((tier) => tier.basis === "weekly" && tier.afterHours === "44"), false);
  assert.equal(covered.vacation?.source, "agreement:21");
  assert.equal(covered.vacation?.days, "20");
  const statute = resolve({
    jurisdiction: "ON",
    date: "2026-11-01",
    serviceYears: 5,
    edition,
    editionHash: standards.sha256,
    agreement: {
      id: "THIN",
      version: 1,
      rules: {
        hours_of_work: { normal_daily_hours: 7, normal_weekly_hours: 35 },
        overtime: { thresholds: [{ basis: "daily", after_hours: 7, multiplier: 1.5 }], cite: { article: "15" } },
        vacation: { tiers: [{ service_years: 1, days: 10 }], cite: { article: "21" } },
      },
    },
  });
  assert.ok(statute.overtime.some((tier) => tier.basis === "weekly" && tier.source === "es:ON"));
  assert.ok(statute.overtime.some((tier) => tier.basis === "daily" && tier.source === "agreement:15"));
  assert.equal(statute.vacation?.source, "es:ON");
  const changes = compareResolutions(statute, covered);
  assert.ok(changes.some((change) => change.field === "vacation"));
});

test("ENT-022 awards 5 points per 7 hours and stops at the annual cap", () => {
  const year = accrueSeniorityPoints({ hours: "700", points: "5", perHours: "7", annualCap: "1825" });
  assert.equal(year.earned, "500");
  assert.equal(year.total, "500");
  assert.equal(year.capped, false);
  const cap = accrueSeniorityPoints({ hours: "3000", points: "5", perHours: "7", annualCap: "1825" });
  assert.equal(cap.total, "1825");
  assert.equal(cap.capped, true);
  const near = accrueSeniorityPoints({
    hours: "700",
    points: "5",
    perHours: "7",
    annualCap: "1825",
    already: "1800",
  });
  assert.equal(near.total, "1825");
  assert.equal(near.capped, true);
});

test("ENT-030 proposes the grid and the rate on the new minimum-wage date", () => {
  const proposal = proposeGridFloor({
    jurisdiction: "ON",
    nextWage: "18.00",
    effectiveFrom: "2027-10-01",
    steps: [
      { step: 1, rate: "17.20", margin: "0.50", linkedJurisdiction: "ON", article: "Schedule A" },
      { step: 2, rate: "30.00", margin: "0.50", linkedJurisdiction: "ON", article: "Schedule A" },
      { step: 1, rate: "16.00", margin: "0", linkedJurisdiction: "BC", article: "other" },
    ],
  });
  assert.equal(proposal.effectiveDate, "2027-10-01");
  assert.deepEqual(proposal.changes, [
    { step: 1, from: "17.20", to: "18.50", article: "Schedule A" },
  ]);
});

test("scoped rules take the most specific match and refuse a tie", () => {
  const rules = [
    { id: "all", rate: "home" },
    { id: "clerk", rate: "clerk", applies_to: { classifications: ["Clerk"] } },
    { id: "parks", rate: "parks", applies_to: { classifications: ["Clerk"], org_subtrees: ["parks"] } },
  ];
  const picked = selectScopedRule(rules, { classification: "Clerk", orgNode: "north", orgAncestors: ["parks"] }, "acting_pay");
  assert.equal(picked?.id, "parks");
  const tie = [
    { id: "a", applies_to: { classifications: ["Clerk"] } },
    { id: "b", applies_to: { classifications: ["Clerk"] } },
  ];
  assert.throws(
    () => selectScopedRule(tie, { classification: "Clerk" }, "acting_pay"),
    (error: unknown) => error instanceof RulesError && error.code === "UNRESOLVED_INTERACTION",
  );
  const letter = selectScopedRule(
    [
      { id: "grid", applies_to: { classifications: ["Clerk"], org_nodes: ["north"] } },
      { id: "letter", precedence: "prevails", applies_to: { classifications: ["Clerk"] } },
    ],
    { classification: "Clerk", orgNode: "north" },
    "rate",
  );
  assert.equal(letter?.id, "letter");
});
