import assert from "node:assert/strict";
import test from "node:test";
import pg from "pg";
import { claimBucket, finishBucket } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

async function payrollReady(client: pg.Client): Promise<boolean> {
  const found = await client.query<{ ready: string }>("SELECT to_regclass('payroll.pay_run_partition')::text AS ready");
  return found.rows[0]?.ready === "payroll.pay_run_partition";
}

test("a redelivered bucket message writes nothing twice", { skip: !databaseUrl }, async () => {
  const client = new pg.Client({ connectionString: databaseUrl });
  const other = new pg.Client({ connectionString: databaseUrl });
  await client.connect();
  await other.connect();
  const tenant = crypto.randomUUID();
  const legal = crypto.randomUUID();
  const account = crypto.randomUUID();
  const person = crypto.randomUUID();
  const run = crypto.randomUUID();
  const createdBy = crypto.randomUUID();
  let inserted = false;
  try {
    if (!(await payrollReady(client))) return;
    await client.query("BEGIN");
    await client.query("INSERT INTO platform.tenant (tenant_id, name) VALUES ($1, 'Pay run test')", [tenant]);
    await client.query("SELECT set_config('app.tenant_id', $1, true)", [tenant]);
    await client.query("INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES ($1, $2)", [tenant, legal]);
    await client.query(
      `INSERT INTO core.legal_entity_version (tenant_id, legal_entity_id, valid_period, change_set_id, legal_name, business_number, regulatory_jurisdiction, first_nation_government)
       VALUES ($1, $2, '[2020-01-01,)', gen_random_uuid(), 'Pay Co', '123456789', 'provincial', false)`,
      [tenant, legal],
    );
    await client.query(
      `INSERT INTO core.payroll_account (tenant_id, payroll_account_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid)
       VALUES ($1, $2, $3, 'RP0001', 'regular', '[2026-01-01,)')`,
      [tenant, account, legal],
    );
    await client.query("INSERT INTO core.person (tenant_id, person_id) VALUES ($1, $2)", [tenant, person]);
    await client.query(
      `INSERT INTO payroll.pay_run (tenant_id, pay_run_id, number, run_type, legal_entity_id, population, pay_date, status, created_by)
       VALUES ($1, $2, 1, 'regular', $3, '{"mode":"employees"}', '2026-11-13', 'inputs_locked', $4)`,
      [tenant, run, legal, createdBy],
    );
    await client.query(
      `INSERT INTO payroll.pay_run_partition (tenant_id, pay_run_id, bucket, subject_count, status)
       VALUES ($1, $2, 0, 1, 'pending')`,
      [tenant, run],
    );
    await client.query("COMMIT");
    inserted = true;

    const first = await claimBucket(client, { tenantId: tenant, payRunId: run, bucket: 0, workerId: "worker-a" });
    assert.equal(first.outcome, "claimed");
    if (first.outcome === "claimed") assert.equal(first.attempts, 1);
    await finishBucket(client, { tenantId: tenant, payRunId: run, bucket: 0, checksum: "abc" });
    const again = await claimBucket(client, { tenantId: tenant, payRunId: run, bucket: 0, workerId: "worker-b" });
    assert.equal(again.outcome, "already_done");
    const stored = await client.query<{ attempts: number; status: string; results_checksum: string; results: number }>(
      `SELECT partition.attempts, partition.status, partition.results_checksum,
              (SELECT count(*)::int FROM payroll.pay_result WHERE pay_run_id = partition.pay_run_id) AS results
       FROM payroll.pay_run_partition AS partition
       WHERE partition.pay_run_id = $1 AND partition.bucket = 0`,
      [run],
    );
    assert.equal(stored.rows[0]?.attempts, 1);
    assert.equal(stored.rows[0]?.status, "calculated");
    assert.equal(stored.rows[0]?.results_checksum, "abc");
    assert.equal(stored.rows[0]?.results, 0);

    await client.query(
      "UPDATE payroll.pay_run_partition SET status = 'pending', worker_id = NULL, finished_at = NULL WHERE pay_run_id = $1",
      [run],
    );
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.tenant_id', $1, true)", [tenant]);
    const held = await claimBucket(client, { tenantId: tenant, payRunId: run, bucket: 0, workerId: "worker-a" });
    assert.equal(held.outcome, "claimed");
    if (held.outcome === "claimed") assert.equal(held.attempts, 2);
    await other.query("BEGIN");
    await other.query("SELECT set_config('app.tenant_id', $1, true)", [tenant]);
    const skipped = await claimBucket(other, { tenantId: tenant, payRunId: run, bucket: 0, workerId: "worker-b" });
    assert.equal(skipped.outcome, "busy");
    await other.query("ROLLBACK");
    await client.query("ROLLBACK");
  } finally {
    if (inserted) {
      await client.query("DELETE FROM payroll.pay_run_partition WHERE pay_run_id = $1", [run]);
      await client.query("DELETE FROM payroll.pay_run WHERE pay_run_id = $1", [run]);
      await client.query("DELETE FROM core.person WHERE person_id = $1", [person]);
      await client.query("DELETE FROM core.payroll_account WHERE payroll_account_id = $1", [account]);
      await client.query("DELETE FROM core.legal_entity_version WHERE legal_entity_id = $1", [legal]);
      await client.query("DELETE FROM core.legal_entity WHERE legal_entity_id = $1", [legal]);
      await client.query("DELETE FROM platform.tenant WHERE tenant_id = $1", [tenant]);
    }
    await client.end();
    await other.end();
  }
});
