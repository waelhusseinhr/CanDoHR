import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { RulesError } from "../src/errors.ts";
import { caseRules, compose, validate, type Problem } from "../src/stacking.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const cases = JSON.parse(readFileSync(join(root, "tests/agreements/stacking_cases.json"), "utf8")) as {
  cases: Array<Record<string, unknown>>;
  validation_cases: Array<Record<string, unknown>>;
};
const example = JSON.parse(readFileSync(join(root, "rules/agreements/example-municipal-agreement.json"), "utf8")) as {
  versions: Array<{ rules: Record<string, unknown> }>;
};
const baseRules = example.versions[0].rules;

function pairKey(problem: Problem): string {
  return `${problem.code}\t${problem.detail}`;
}

for (const entry of cases.cases) {
  test(`stacking ${String(entry.id)}`, () => {
    const rules = caseRules(baseRules, entry);
    const expected = entry.expected as Record<string, unknown>;
    try {
      const got = compose(entry.block as Record<string, unknown>, rules);
      assert.equal("error" in expected, false, `expected ${String(expected.error)}, got total ${got.total}`);
      assert.equal(got.total, expected.total);
      assert.equal(got.multiplier, expected.multiplier);
      if (Array.isArray(expected.lines)) {
        const lines = got.lines.map((line) => [line.code ?? "time", line.amount]);
        assert.deepEqual(lines, expected.lines);
      }
    } catch (error) {
      if (error instanceof RulesError) {
        assert.equal(error.code, expected.error);
        return;
      }
      throw error;
    }
  });
}

for (const entry of cases.validation_cases) {
  test(`validate ${String(entry.id)}`, () => {
    const rules = caseRules(baseRules, entry);
    const got = validate(rules).map(pairKey).sort();
    const expected = (entry.expected_problems as string[][]).map((pair) => `${pair[0]}\t${pair[1]}`).sort();
    assert.deepEqual(got, expected);
  });
}
