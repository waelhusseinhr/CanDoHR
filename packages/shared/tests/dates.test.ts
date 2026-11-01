import assert from "node:assert/strict";
import test from "node:test";
import { CanDoError, addDays, compareIsoDate, isoDateInTimeZone, parseIsoDate, rangeContains, rangesOverlap } from "../src/index.ts";

test("calendar dates stay on the legal entity's calendar", () => {
  assert.equal(parseIsoDate("2026-11-01"), "2026-11-01");
  assert.equal(addDays("2026-11-01", -1), "2026-10-31");
  assert.equal(addDays("2024-02-28", 1), "2024-02-29");
  assert.equal(compareIsoDate("2026-11-01", "2026-11-02"), -1);
  assert.equal(isoDateInTimeZone("2026-11-01T03:30:00.000Z", "America/Toronto"), "2026-10-31");
  assert.equal(isoDateInTimeZone("2026-07-01T03:30:00.000Z", "America/Toronto"), "2026-06-30");
  assert.equal(isoDateInTimeZone("2026-07-01T04:00:00.000Z", "America/Toronto"), "2026-07-01");
  assert.throws(() => parseIsoDate("2026-02-31"), (error: CanDoError) => error.code === "ISO_DATE");
  assert.throws(() => isoDateInTimeZone("2026-07-01T00:00:00.000Z", "Not/AZone"), (error: CanDoError) => error.code === "TIME_ZONE_UNKNOWN");
});

test("valid-time ranges are half-open", () => {
  const november = { start: "2026-11-01", end: "2027-01-01" };
  const january = { start: "2027-01-01", end: null };
  assert.equal(rangeContains(november, "2026-11-01"), true);
  assert.equal(rangeContains(november, "2027-01-01"), false);
  assert.equal(rangeContains(january, "2027-01-01"), true);
  assert.equal(rangesOverlap(november, january), false);
  assert.equal(rangesOverlap({ start: "2026-04-01", end: null }, november), true);
});
