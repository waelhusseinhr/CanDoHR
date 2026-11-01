import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { calculate, type PayResult } from "../src/index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const provinces = ["AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "SK", "YT"];

function random(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 4294967296;
  };
}

function money(draw: () => number, max: number): number {
  return Math.floor(draw() * max * 100) / 100;
}

test("random non-Quebec pays match the Python reference to the cent", () => {
  const draw = random(20261101);
  const dir = mkdtempSync(join(tmpdir(), "cando-pay-"));
  for (const province of provinces) {
    for (let sample = 0; sample < 2; sample += 1) {
      const periodic = money(draw, 4000);
      const bonus = sample === 0 ? 0 : money(draw, 5000);
      const input: Record<string, unknown> = {
        province,
        pay_date: sample === 0 ? "2026-03-13" : "2026-08-14",
        P: 26,
        I: periodic,
        B: bonus,
        B1: money(draw, 2000),
        PM: 12,
        apply_cpp_exemption: true,
        D_cpp_ytd: money(draw, 1000),
        D1_ei_ytd: money(draw, 400),
        PIYTD: money(draw, 20000),
      };
      if (bonus > 0) {
        input.PR = 10;
        if (periodic === 0) input.I_recent = 1500;
      }
      const file = join(dir, `${province}-${sample}.json`);
      writeFileSync(file, JSON.stringify(input));
      const python = spawnSync("python3", [join(root, "reference/payroll_reference.py"), file], { encoding: "utf8" });
      assert.equal(python.status, 0, python.stderr);
      const expected = JSON.parse(python.stdout) as PayResult;
      const got = calculate(input);
      for (const field of ["cpp_employee", "cpp2_employee", "ei_employee", "income_tax", "income_tax_regular", "net_pay"] as const) {
        assert.equal(got[field], expected[field], `${province} sample ${sample} ${field}`);
      }
    }
  }
});
