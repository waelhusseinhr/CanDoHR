import assert from "node:assert/strict";
import test from "node:test";
import fc from "fast-check";
import {
  CanDoError,
  Money,
  addDays,
  compareIsoDate,
  rangeContains,
  rangesOverlap,
  readAsOf,
  writeVersion,
  type VersionRow,
  type WriteVersionInput,
} from "../src/index.ts";

const START = "2020-01-01";

test("a transfer stops at the next future version and does not overwrite it", () => {
  const entityId = "person-ana";
  let versions = [seed(entityId, { salary: money("72000"), manager: "Ana" }, ["salary", "manager"])];

  const raised = writeVersion(versions, {
    entityId,
    kind: "change",
    effectiveDate: "2027-01-01",
    knownAt: "2026-10-01T00:00:00.000Z",
    changeSetId: "00000000-0000-4000-8000-000000000010",
    patch: { salary: money("80000") },
    explicitKeys: ["salary"],
  });
  versions = raised.versions;
  assert.equal(raised.conflicts.length, 0);

  const transferred = writeVersion(versions, {
    entityId,
    kind: "change",
    effectiveDate: "2026-11-01",
    knownAt: "2026-10-02T00:00:00.000Z",
    changeSetId: "00000000-0000-4000-8000-000000000011",
    patch: { manager: "Ben" },
    explicitKeys: ["manager"],
    conflictResolution: "keep",
  });
  versions = transferred.versions;
  assert.equal(transferred.conflicts.length, 0);

  const november = readAsOf(versions, entityId, "2026-11-15", "2026-10-02T00:00:00.000Z");
  const january = readAsOf(versions, entityId, "2027-01-15", "2026-10-02T00:00:00.000Z");
  assert.equal(november?.attributes.manager, "Ben");
  assert.equal(november?.attributes.salary, money("72000"));
  assert.equal(november?.validEnd, "2027-01-01");
  assert.equal(january?.attributes.manager, "Ana");
  assert.equal(january?.attributes.salary, money("80000"));
});

test("an explicit future value is kept, replaced, or merged", () => {
  const entityId = "person-ana";
  const base = writeVersion([seed(entityId, { salary: money("72000"), manager: "Ana" }, ["salary", "manager"])], {
    entityId,
    kind: "change",
    effectiveDate: "2027-01-01",
    knownAt: "2026-09-01T00:00:00.000Z",
    changeSetId: "00000000-0000-4000-8000-000000000020",
    patch: { salary: money("80000"), manager: "Cara" },
    explicitKeys: ["salary", "manager"],
  }).versions;

  const input = {
    entityId,
    kind: "change" as const,
    effectiveDate: "2026-11-01",
    knownAt: "2026-10-02T00:00:00.000Z",
    changeSetId: "00000000-0000-4000-8000-000000000021",
    patch: { manager: "Ben" },
    explicitKeys: ["manager"],
  };

  const kept = writeVersion(base, { ...input, conflictResolution: "keep" });
  assert.equal(kept.conflicts.length, 1);
  assert.equal(kept.conflicts[0]?.key, "manager");
  assert.equal(readAsOf(kept.versions, entityId, "2027-01-15", input.knownAt)?.attributes.manager, "Cara");

  const replaced = writeVersion(base, { ...input, conflictResolution: "replace" });
  assert.equal(readAsOf(replaced.versions, entityId, "2027-01-15", input.knownAt)?.attributes.manager, "Ben");
  assert.equal(readAsOf(replaced.versions, entityId, "2027-01-15", input.knownAt)?.attributes.salary, money("80000"));

  const merged = writeVersion(base, { ...input, conflictResolution: "merge" });
  assert.equal(merged.conflicts.length, 1);
  assert.equal(readAsOf(merged.versions, entityId, "2027-01-15", input.knownAt)?.attributes.manager, "Cara");
});

test("merge copies a change onto future rows that did not set that field", () => {
  const entityId = "person-ana";
  const raised = writeVersion([seed(entityId, { salary: money("72000"), manager: "Ana" }, ["salary", "manager"])], {
    entityId,
    kind: "change",
    effectiveDate: "2027-01-01",
    knownAt: "2026-09-01T00:00:00.000Z",
    changeSetId: "00000000-0000-4000-8000-000000000030",
    patch: { salary: money("80000") },
    explicitKeys: ["salary"],
  });
  const merged = writeVersion(raised.versions, {
    entityId,
    kind: "change",
    effectiveDate: "2026-11-01",
    knownAt: "2026-10-02T00:00:00.000Z",
    changeSetId: "00000000-0000-4000-8000-000000000031",
    patch: { manager: "Ben" },
    explicitKeys: ["manager"],
    conflictResolution: "merge",
  });
  const january = readAsOf(merged.versions, entityId, "2027-01-15", "2026-10-02T00:00:00.000Z");
  assert.equal(merged.conflicts.length, 0);
  assert.equal(january?.attributes.manager, "Ben");
  assert.equal(january?.attributes.salary, money("80000"));
  assert.ok(january?.explicitKeys.includes("salary"));
  assert.equal(january?.explicitKeys.includes("manager"), false);
});

test("a correction supersedes the row and keeps the same valid dates", () => {
  const entityId = "person-ana";
  const wrong = seed(entityId, { salary: money("27000") }, ["salary"], "2026-04-01", "2026-03-20T10:02:00.000Z");
  const knownAt = "2026-03-21T15:00:00.000Z";
  const corrected = writeVersion([wrong], {
    entityId,
    kind: "correction",
    effectiveDate: "2026-04-01",
    knownAt,
    changeSetId: "00000000-0000-4000-8000-000000000040",
    patch: { salary: money("72000") },
  });
  assert.equal(corrected.opened.length, 1);
  assert.equal(corrected.opened[0]?.validStart, "2026-04-01");
  assert.equal(corrected.opened[0]?.validEnd, null);
  assert.equal(readAsOf(corrected.versions, entityId, "2026-06-01", "2026-03-20T12:00:00.000Z")?.attributes.salary, money("27000"));
  assert.equal(readAsOf(corrected.versions, entityId, "2026-06-01", knownAt)?.attributes.salary, money("72000"));
  assert.equal(readAsOf(corrected.versions, entityId, "2026-06-01", "2026-03-21T14:59:00.000Z")?.attributes.salary, money("27000"));
});

test("writeVersion rejects an empty patch and a date the entity does not cover", () => {
  const entityId = "person-ana";
  const versions = [seed(entityId, { salary: money("72000") }, ["salary"])];
  assert.throws(
    () =>
      writeVersion(versions, {
        entityId,
        kind: "change",
        effectiveDate: "2026-11-01",
        knownAt: "2026-10-01T00:00:00.000Z",
        changeSetId: "00000000-0000-4000-8000-000000000050",
        patch: {},
      }),
    (error: CanDoError) => error.code === "PATCH_EMPTY",
  );
  assert.throws(
    () =>
      writeVersion(versions, {
        entityId,
        kind: "change",
        effectiveDate: "2026-03-01",
        knownAt: "2026-10-01T00:00:00.000Z",
        changeSetId: "00000000-0000-4000-8000-000000000051",
        patch: { salary: money("1") },
      }),
    (error: CanDoError) => error.code === "EFFECTIVE_DATE_NOT_COVERED",
  );
});

test("random changes and corrections keep exactly one current row per day", () => {
  const operation = fc.record({
    kind: fc.constantFrom("change" as const, "correction" as const),
    dayOffset: fc.integer({ min: 0, max: 400 }),
    key: fc.constantFrom("a" as const, "b" as const),
    value: fc.integer({ min: 0, max: 30 }).map(String),
    resolution: fc.constantFrom("keep" as const, "replace" as const, "merge" as const),
  });

  fc.assert(
    fc.property(fc.uuid(), fc.array(operation, { minLength: 1, maxLength: 25 }), (entityId, operations) => {
      let versions = [seed(entityId, { a: "0", b: "0" }, ["a", "b"], START, "2020-01-01T00:00:00.000Z")];
      const snapshots: { versions: VersionRow[]; knownAt: string }[] = [
        { versions, knownAt: "2020-01-01T00:00:00.000Z" },
      ];
      operations.forEach((operation, index) => {
        const knownAt = new Date(Date.parse("2024-01-01T00:00:00.000Z") + (index + 1) * 60_000).toISOString();
        const input: WriteVersionInput = {
          entityId,
          kind: operation.kind,
          effectiveDate: addDays(START, operation.dayOffset),
          knownAt,
          changeSetId: crypto.randomUUID(),
          patch: { [operation.key]: operation.value },
          explicitKeys: [operation.key],
          conflictResolution: operation.resolution,
        };
        const result = writeVersion(versions, input);
        versions = result.versions;
        snapshots.push({ versions, knownAt });
      });
      for (const snapshot of snapshots) {
        assertPartition(snapshot.versions, entityId, snapshot.knownAt, START);
      }
    }),
    { numRuns: 200 },
  );
});

function money(amount: string): string {
  return Money.parse(amount).toString();
}

function seed(
  entityId: string,
  attributes: VersionRow["attributes"],
  explicitKeys: string[],
  validStart = "2026-04-01",
  recordedAt = "2026-04-01T00:00:00.000Z",
): VersionRow {
  return {
    versionId: "seed",
    entityId,
    validStart,
    validEnd: null,
    recordedAt,
    supersededAt: null,
    changeSetId: "00000000-0000-4000-8000-000000000001",
    attributes,
    explicitKeys,
  };
}

function assertPartition(versions: readonly VersionRow[], entityId: string, knownAt: string, start: string): void {
  const at = Date.parse(knownAt);
  const visible = versions
    .filter((row) => {
      if (row.entityId !== entityId) return false;
      const recorded = Date.parse(row.recordedAt);
      const superseded = row.supersededAt === null ? null : Date.parse(row.supersededAt);
      return recorded <= at && (superseded === null || at < superseded);
    })
    .sort((a, b) => compareIsoDate(a.validStart, b.validStart));
  assert.ok(visible.length > 0);
  assert.equal(visible[0]?.validStart, start);
  assert.equal(visible[visible.length - 1]?.validEnd, null);
  for (let i = 0; i < visible.length; i += 1) {
    const row = visible[i];
    if (!row) continue;
    assert.notEqual(row.validStart, row.validEnd);
    const next = visible[i + 1];
    if (next) {
      assert.equal(row.validEnd, next.validStart);
      assert.equal(rangesOverlap({ start: row.validStart, end: row.validEnd }, { start: next.validStart, end: next.validEnd }), false);
    }
  }
  for (let offset = 0; offset <= 400; offset += 1) {
    const day = addDays(start, offset);
    const found = readAsOf(versions, entityId, day, knownAt);
    assert.ok(found, day);
    assert.equal(rangeContains({ start: found.validStart, end: found.validEnd }, day), true);
  }
}
