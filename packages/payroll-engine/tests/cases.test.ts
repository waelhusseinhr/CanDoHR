import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { calculate, checkCase, resultSha256 } from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const cases = JSON.parse(readFileSync(join(root, "tests/payroll/cases.json"), "utf8")) as {
  cases: Array<Record<string, unknown>>;
};

for (const entry of cases.cases) {
  test(String(entry.id), () => {
    assert.deepEqual(checkCase(entry), []);
  });
}

test("resultSha256 is stable for the same pay", () => {
  const input = cases.cases[0].input as Record<string, unknown>;
  const first = calculate(input);
  const second = calculate(input);
  assert.equal(resultSha256(first), resultSha256(second));
  assert.equal(resultSha256(first).length, 64);
});

test("Quebec is refused", () => {
  assert.throws(
    () =>
      calculate({
        province: "QC",
        pay_date: "2026-03-13",
        P: 26,
        I: 1000,
        PM: 12,
        apply_cpp_exemption: true,
      }),
    /Quebec payroll is phase 2/,
  );
});
