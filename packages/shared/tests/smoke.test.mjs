import assert from "node:assert/strict";
import test from "node:test";
import { CANDOHR_BUILD_PLAN_STEP } from "../src/index.ts";

test("workspace is wired", () => {
  assert.equal(CANDOHR_BUILD_PLAN_STEP, 0);
});
