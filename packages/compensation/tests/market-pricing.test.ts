import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { D, roundToUnit } from "../src/decimal.ts";
import { payMetrics, runCaseSafe, type Files } from "../src/market-pricing.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");

function load(path: string): unknown {
  return JSON.parse(readFileSync(join(root, path), "utf8"));
}

const files: Files = {
  plan: load("rules/job-evaluation/sample-point-factor-plan.json") as Files["plan"],
  practices: load("rules/total-rewards/benefit-practices.json") as Files["practices"],
};

function subset(expected: unknown, actual: unknown, path: string, errs: string[]): void {
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual) || actual.length !== expected.length) {
      errs.push(`${path}: expected list of ${expected.length}`);
      return;
    }
    let n = 0;
    while (n < expected.length) {
      subset(expected[n], actual[n], `${path}[${n}]`, errs);
      n += 1;
    }
    return;
  }
  if (expected !== null && typeof expected === "object") {
    if (actual === null || typeof actual !== "object" || Array.isArray(actual)) {
      errs.push(`${path}: expected object`);
      return;
    }
    const got = actual as Record<string, unknown>;
    for (const [key, val] of Object.entries(expected as Record<string, unknown>)) {
      subset(val, got[key], `${path}.${key}`, errs);
    }
    return;
  }
  if (expected !== actual) errs.push(`${path}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

const doc = load("tests/compensation/market_pricing_cases.json") as { cases: { id: string; title: string; expected: unknown; kind: string; input: unknown }[] };

test("market pricing cases match the Python reference", () => {
  const failed: string[] = [];
  for (const c of doc.cases) {
    const errs: string[] = [];
    subset(c.expected, runCaseSafe(c as unknown as Record<string, unknown>, files), c.id, errs);
    if (errs.length > 0) failed.push(`${c.id}\n${errs.join("\n")}`);
  }
  assert.equal(failed.length, 0, failed.join("\n\n"));
});

test("reference selftest: rounding, quartiles, incomplete definition", () => {
  assert.equal(roundToUnit(new D("64949.99"), new D(100)).toString(), "64900");
  assert.equal(roundToUnit(new D("64950"), new D(100)).toString(), "65000");
  assert.deepEqual(payMetrics(60000, { minimum: 50000, midpoint: 60000, maximum: 70000 }), {
    compaRatio: "1.000",
    penetration: "0.500",
    quartile: "Q3",
  });
  const safe = runCaseSafe(
    {
      kind: "price",
      input: { job: { jobId: "X" }, definition: { statistic: "p50", sources: [] }, editions: {}, asOf: "2026-01-01" },
    },
    files,
  );
  assert.equal(safe.error, "DEFINITION_INCOMPLETE");
});
