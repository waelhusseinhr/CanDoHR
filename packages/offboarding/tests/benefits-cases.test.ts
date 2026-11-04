import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { runBenefitCase, type BenefitResult } from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const cases = JSON.parse(readFileSync(join(root, "tests/assignments/several_positions_cases.json"), "utf8")).cases as {
  id: string;
  kind: string;
  input: {
    enrolment: Parameters<typeof runBenefitCase>[0]["enrolment"];
    ending: Parameters<typeof runBenefitCase>[0]["ending"];
    rules: Parameters<typeof runBenefitCase>[0]["rules"];
    jurisdictionRules: Parameters<typeof runBenefitCase>[0]["jurisdictionRules"];
  };
  expected: BenefitResult | { error: string };
}[];

function subset(expected: unknown, actual: unknown, path: string): string[] {
  if (expected !== null && typeof expected === "object" && !Array.isArray(expected)) {
    if (actual === null || typeof actual !== "object" || Array.isArray(actual)) {
      return [`${path}: expected object`];
    }
    const errs: string[] = [];
    const exp = expected as Record<string, unknown>;
    const act = actual as Record<string, unknown>;
    for (const key of Object.keys(exp)) {
      errs.push(...subset(exp[key], act[key], `${path}.${key}`));
    }
    return errs;
  }
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual) || actual.length !== expected.length) return [`${path}: list length`];
    const errs: string[] = [];
    let index = 0;
    while (index < expected.length) {
      errs.push(...subset(expected[index], actual[index], `${path}[${index}]`));
      index += 1;
    }
    return errs;
  }
  if (expected !== actual) return [`${path}: expected ${JSON.stringify(expected)} got ${JSON.stringify(actual)}`];
  return [];
}

test("BEN-033 benefit outcomes match BEN-001 through BEN-013", () => {
  const benefits = cases.filter((item) => item.kind === "benefits");
  assert.ok(benefits.some((item) => item.id === "BEN-011"));
  assert.ok(benefits.some((item) => item.id === "BEN-012"));
  assert.ok(benefits.some((item) => item.id === "BEN-013"));
  for (const item of benefits) {
    const actual = runBenefitCase(item.input);
    const errs = subset(item.expected, actual, item.id);
    assert.deepEqual(errs, [], errs.join("\n"));
  }
});
