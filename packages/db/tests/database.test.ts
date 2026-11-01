import assert from "node:assert/strict";
import test from "node:test";
import fc from "fast-check";
import { sql, type Kysely, type Transaction } from "kysely";
import {
  addDays,
  compareIsoDate,
  readAsOf,
  writeVersion,
  type VersionRow,
  type WriteVersionInput,
  type WriteVersionResult,
} from "@candohr/shared";
import { createDb, withTenant, type Database } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
const userId = "00000000-0000-4000-8000-0000000000aa";
const skip = !databaseUrl;

test("two tenants sharing one pooled connection cannot see each other", { skip }, async () => {
  const db = createDb(databaseUrl ?? "", { max: 1 });
  try {
    await ensureStep2(db);
    const tenantA = crypto.randomUUID();
    const tenantB = crypto.randomUUID();
    await withTenant(db, { tenantId: tenantA, userId, roles: ["hr_admin"] }, async (trx) => {
      await asApp(trx);
      await sql`insert into step2.tenant_note (tenant_id, note) values (${tenantA}::uuid, 'secret-a')`.execute(trx);
    });
    await withTenant(db, { tenantId: tenantB, userId, roles: ["comp_admin", "survey_data:SVY_T"] }, async (trx) => {
      await asApp(trx);
      await sql`insert into step2.tenant_note (tenant_id, note) values (${tenantB}::uuid, 'note-b')`.execute(trx);
      const notes = await sql<{ note: string }>`select note from step2.tenant_note order by note`.execute(trx);
      assert.deepEqual(
        notes.rows.map((row) => row.note),
        ["note-b"],
      );
      const settings = await sql<{ tenant_id: string; user_id: string; roles: string }>`
        select current_setting('app.tenant_id', true) as tenant_id,
               current_setting('app.user_id', true) as user_id,
               current_setting('app.roles', true) as roles
      `.execute(trx);
      assert.equal(settings.rows[0]?.tenant_id, tenantB);
      assert.equal(settings.rows[0]?.user_id, userId);
      assert.equal(settings.rows[0]?.roles, "comp_admin,survey_data:SVY_T");
    });
    const leftover = await sql<{ tenant_id: string }>`select current_setting('app.tenant_id', true) as tenant_id`.execute(db);
    assert.equal(leftover.rows[0]?.tenant_id, "");

    const tenantC = crypto.randomUUID();
    await assert.rejects(
      withTenant(db, { tenantId: tenantC, userId, roles: ["hr_admin"] }, async (trx) => {
        await asApp(trx);
        await sql`insert into step2.tenant_note (tenant_id, note) values (${tenantC}::uuid, 'gone')`.execute(trx);
        throw new Error("rollback");
      }),
      (error: Error) => error.message === "rollback",
    );
    await withTenant(db, { tenantId: tenantC, userId, roles: ["hr_admin"] }, async (trx) => {
      await asApp(trx);
      const notes = await sql<{ note: string }>`select note from step2.tenant_note`.execute(trx);
      assert.equal(notes.rows.length, 0);
    });
  } finally {
    await db.destroy();
  }
});

test("version changes and corrections stay one row per day in Postgres", { skip }, async () => {
  const db = createDb(databaseUrl ?? "", { max: 4 });
  try {
    await ensureStep2(db);
    const operation = fc.record({
      kind: fc.constantFrom("change" as const, "correction" as const),
      dayOffset: fc.integer({ min: 0, max: 120 }),
      key: fc.constantFrom("a" as const, "b" as const),
      value: fc.integer({ min: 0, max: 12 }).map(String),
      resolution: fc.constantFrom("keep" as const, "replace" as const, "merge" as const),
    });
    await fc.assert(
      fc.asyncProperty(fc.uuid(), fc.array(operation, { minLength: 1, maxLength: 8 }), async (entityId, operations) => {
        const tenantId = crypto.randomUUID();
        const start = "2020-01-01";
        let versions: VersionRow[] = [
          {
            versionId: crypto.randomUUID(),
            entityId,
            validStart: start,
            validEnd: null,
            recordedAt: "2020-01-01T00:00:00.000Z",
            supersededAt: null,
            changeSetId: crypto.randomUUID(),
            attributes: { a: "0", b: "0" },
            explicitKeys: ["a", "b"],
          },
        ];
        await withTenant(db, { tenantId, userId, roles: ["hr_admin"] }, async (trx) => {
          await asApp(trx);
          await insertRows(trx, tenantId, versions);
        });
        for (let index = 0; index < operations.length; index += 1) {
          const operationRow = operations[index];
          if (!operationRow) continue;
          const knownAt = new Date(Date.parse("2024-01-01T00:00:00.000Z") + (index + 1) * 60_000).toISOString();
          const input: WriteVersionInput = {
            entityId,
            kind: operationRow.kind,
            effectiveDate: addDays(start, operationRow.dayOffset),
            knownAt,
            changeSetId: crypto.randomUUID(),
            patch: { [operationRow.key]: operationRow.value },
            explicitKeys: [operationRow.key],
            conflictResolution: operationRow.resolution,
          };
          const result = writeVersion(versions, input);
          await withTenant(db, { tenantId, userId, roles: ["hr_admin"] }, async (trx) => {
            await asApp(trx);
            await persist(trx, tenantId, result, knownAt);
            const stored = await loadRows(trx, tenantId, entityId);
            assert.deepEqual(currentShape(stored), currentShape(result.versions));
            const day = addDays(start, operationRow.dayOffset);
            const fromDb = readAsOf(stored, entityId, day, knownAt);
            assert.equal(fromDb?.attributes[operationRow.key], operationRow.value);
          });
          versions = result.versions;
        }
        assertPartition(versions, entityId, "2024-01-02T00:00:00.000Z", start);
      }),
      { numRuns: 20 },
    );
  } finally {
    await db.destroy();
  }
});

async function ensureStep2(db: Kysely<Database>): Promise<void> {
  const existing = await sql<{ role_exists: boolean }>`
    select exists (select 1 from pg_roles where rolname = 'step2_app') as role_exists
  `.execute(db);
  if (!existing.rows[0]?.role_exists) {
    await sql`create role step2_app login password 'step2-app-local' nosuperuser nobypassrls`.execute(db);
  }
  await sql`alter role step2_app nosuperuser nobypassrls`.execute(db);
  await sql`grant step2_app to current_user`.execute(db);
  await sql`create schema if not exists extensions`.execute(db);
  await sql`create extension if not exists btree_gist with schema extensions`.execute(db);
  await db.transaction().execute(async (trx) => {
    await sql`set local search_path to step2, public, extensions`.execute(trx);
    await sql`drop schema if exists step2 cascade`.execute(trx);
    await sql`create schema step2`.execute(trx);
    await sql`
      create table step2.tenant_note (
        tenant_id uuid not null,
        note text not null
      )
    `.execute(trx);
    await sql`
      create table step2.version (
        version_id text primary key,
        tenant_id uuid not null,
        entity_name text not null,
        entity_id uuid not null,
        valid_start date not null,
        valid_end date,
        recorded_at timestamptz not null,
        superseded_at timestamptz,
        change_set_id uuid not null,
        attributes jsonb not null,
        explicit_keys text[] not null,
        exclude using gist (
          tenant_id with =,
          entity_name with =,
          entity_id with =,
          daterange(valid_start, coalesce(valid_end, 'infinity'::date), '[)') with &&
        ) where (superseded_at is null)
      )
    `.execute(trx);
    await sql`alter table step2.tenant_note enable row level security`.execute(trx);
    await sql`alter table step2.tenant_note force row level security`.execute(trx);
    await sql`alter table step2.version enable row level security`.execute(trx);
    await sql`alter table step2.version force row level security`.execute(trx);
    await sql`
      create policy tenant_note_isolation on step2.tenant_note
        using (tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid)
        with check (tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid)
    `.execute(trx);
    await sql`
      create policy version_isolation on step2.version
        using (tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid)
        with check (tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid)
    `.execute(trx);
    await sql`grant usage on schema step2 to step2_app`.execute(trx);
    await sql`grant select, insert, update on step2.tenant_note to step2_app`.execute(trx);
    await sql`grant select, insert, update on step2.version to step2_app`.execute(trx);
  });
}

async function asApp(trx: Transaction<Database>): Promise<void> {
  await sql`set local role step2_app`.execute(trx);
}

async function insertRows(trx: Transaction<Database>, tenantId: string, rows: readonly VersionRow[]): Promise<void> {
  for (const row of rows) {
    await insertRow(trx, tenantId, row);
  }
}

async function persist(trx: Transaction<Database>, tenantId: string, result: WriteVersionResult, knownAt: string): Promise<void> {
  for (const versionId of result.closedVersionIds) {
    await sql`
      update step2.version
      set superseded_at = ${knownAt}::timestamptz
      where version_id = ${versionId}
    `.execute(trx);
  }
  await insertRows(trx, tenantId, result.opened);
}

async function insertRow(trx: Transaction<Database>, tenantId: string, row: VersionRow): Promise<void> {
  await sql`
    insert into step2.version (
      version_id, tenant_id, entity_name, entity_id, valid_start, valid_end,
      recorded_at, superseded_at, change_set_id, attributes, explicit_keys
    ) values (
      ${row.versionId},
      ${tenantId}::uuid,
      'demo',
      ${row.entityId}::uuid,
      ${row.validStart}::date,
      ${row.validEnd}::date,
      ${row.recordedAt}::timestamptz,
      ${row.supersededAt}::timestamptz,
      ${row.changeSetId}::uuid,
      ${JSON.stringify(row.attributes)}::jsonb,
      ${textArray(row.explicitKeys)}::text[]
    )
  `.execute(trx);
}

async function loadRows(trx: Transaction<Database>, tenantId: string, entityId: string): Promise<VersionRow[]> {
  const result = await sql<{
    version_id: string;
    entity_id: string;
    valid_start: string;
    valid_end: string | null;
    recorded_at: string;
    superseded_at: string | null;
    change_set_id: string;
    attributes: VersionRow["attributes"];
    explicit_keys: string[];
  }>`
    select version_id, entity_id, valid_start::text, valid_end::text,
           recorded_at::text, superseded_at::text,
           change_set_id::text, attributes, explicit_keys
    from step2.version
    where tenant_id = ${tenantId}::uuid and entity_id = ${entityId}::uuid
  `.execute(trx);
  return result.rows.map((row) => ({
    versionId: row.version_id,
    entityId: row.entity_id,
    validStart: row.valid_start,
    validEnd: row.valid_end,
    recordedAt: row.recorded_at,
    supersededAt: row.superseded_at,
    changeSetId: row.change_set_id,
    attributes: row.attributes,
    explicitKeys: row.explicit_keys,
  }));
}

function textArray(keys: readonly string[]): string {
  return `{${keys.map((key) => `"${key}"`).join(",")}}`;
}

function currentShape(rows: readonly VersionRow[]): unknown[] {
  return rows
    .filter((row) => row.supersededAt === null)
    .map((row) => ({
      validStart: row.validStart,
      validEnd: row.validEnd,
      attributes: row.attributes,
      explicitKeys: [...row.explicitKeys].sort(),
    }))
    .sort((a, b) => compareIsoDate(a.validStart, b.validStart));
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
  assert.equal(visible[0]?.validStart, start);
  assert.equal(visible[visible.length - 1]?.validEnd, null);
  for (let index = 0; index < visible.length - 1; index += 1) {
    assert.equal(visible[index]?.validEnd, visible[index + 1]?.validStart);
  }
}
