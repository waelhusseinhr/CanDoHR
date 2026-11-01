import assert from "node:assert/strict";
import test from "node:test";
import pg from "pg";
import { claimRetroRequest, linesSha256 } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

async function payrollReady(client: pg.Client): Promise<boolean> {
  const found = await client.query<{ ready: string }>("SELECT to_regclass('payroll.retro_request')::text AS ready");
  return found.rows[0]?.ready === "payroll.retro_request";
}

test("docs/06 section 10 test 15 a tampered result line raises a mismatch and the stored row is left as it is", { skip: !databaseUrl, timeout: 20_000 }, async () => {
  const client = new pg.Client({ connectionString: databaseUrl });
  await client.connect();
  await client.query("SET statement_timeout = '5s'");
  const tenant = crypto.randomUUID();
  const legal = crypto.randomUUID();
  const account = crypto.randomUUID();
  const person = crypto.randomUUID();
  const employment = crypto.randomUUID();
  const run = crypto.randomUUID();
  const result = crypto.randomUUID();
  const createdBy = crypto.randomUUID();
  const storedSha = linesSha256([{ payCode: "REG", amount: "100.00" }]);
  let inserted = false;
  try {
    if (!(await payrollReady(client))) return;
    await client.query("BEGIN");
    await client.query("INSERT INTO platform.tenant (tenant_id, name) VALUES ($1, 'Retro replay')", [tenant]);
    await client.query("SELECT set_config('app.tenant_id', $1, true)", [tenant]);
    await client.query("INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES ($1, $2)", [tenant, legal]);
    await client.query(
      `INSERT INTO core.legal_entity_version (tenant_id, legal_entity_id, valid_period, change_set_id, legal_name, business_number, regulatory_jurisdiction, first_nation_government)
       VALUES ($1, $2, '[2020-01-01,)', gen_random_uuid(), 'Retro Co', '123456789', 'provincial', false)`,
      [tenant, legal],
    );
    await client.query(
      `INSERT INTO core.payroll_account (tenant_id, payroll_account_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid)
       VALUES ($1, $2, $3, 'RP0001', 'regular', '[2026-01-01,)')`,
      [tenant, account, legal],
    );
    await client.query("INSERT INTO core.person (tenant_id, person_id) VALUES ($1, $2)", [tenant, person]);
    await client.query(
      "INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id, employee_number) VALUES ($1, $2, $3, $4, 'E1')",
      [tenant, employment, person, legal],
    );
    await client.query(
      `INSERT INTO payroll.pay_run (tenant_id, pay_run_id, number, run_type, legal_entity_id, population, pay_date, status, created_by)
       VALUES ($1, $2, 1, 'regular', $3, '{"mode":"employees"}', '2026-04-24', 'finalized', $4)`,
      [tenant, run, legal, createdBy],
    );
    await client.query(
      `INSERT INTO payroll.pay_result (
         tenant_id, pay_result_id, pay_run_id, employment_id, person_id, payroll_account_id, bucket, pay_date, tax_year,
         province, periods_per_year, tax_method, gross, taxable_periodic, taxable_non_periodic, pensionable, insurable,
         cpp, cpp2, ei, income_tax_federal, income_tax_provincial, territorial_payroll_tax, net, employer_cpp, employer_cpp2, employer_ei,
         input_snapshot_sha256, result_sha256, trace, status
       ) VALUES (
         $1, $2, $3, $4, $5, $6, 0, '2026-04-24', 2026,
         'ON', 26, 'periodic', 100, 100, 0, 100, 100,
         0, 0, 0, 0, 0, 0, 100, 0, 0, 0,
         'inputs', $7, '[]', 'finalized'
       )`,
      [tenant, result, run, employment, person, account, storedSha],
    );
    await client.query(
      `INSERT INTO payroll.pay_result_line (tenant_id, pay_result_id, pay_code, amount, source)
       VALUES ($1, $2, 'REG', 100.00, 'salary')`,
      [tenant, result],
    );
    await client.query("COMMIT");
    inserted = true;

    const before = await client.query<{ amount: string; result_sha256: string }>(
      `SELECT line.amount::text AS amount, result.result_sha256
       FROM payroll.pay_result_line AS line
       JOIN payroll.pay_result AS result ON result.pay_result_id = line.pay_result_id
       WHERE line.pay_result_id = $1`,
      [result],
    );
    assert.equal(linesSha256([{ payCode: "REG", amount: before.rows[0]?.amount ?? "" }]), before.rows[0]?.result_sha256);

    await client.query("UPDATE payroll.pay_result_line SET amount = 150.00 WHERE pay_result_id = $1", [result]);
    const after = await client.query<{ amount: string; result_sha256: string }>(
      `SELECT line.amount::text AS amount, result.result_sha256
       FROM payroll.pay_result_line AS line
       JOIN payroll.pay_result AS result ON result.pay_result_id = line.pay_result_id
       WHERE line.pay_result_id = $1`,
      [result],
    );
    const replaySha = linesSha256([{ payCode: "REG", amount: after.rows[0]?.amount ?? "" }]);
    assert.notEqual(replaySha, after.rows[0]?.result_sha256);
    assert.equal(after.rows[0]?.result_sha256, storedSha);
    assert.equal(Number(after.rows[0]?.amount), 150);
  } finally {
    let cleanupError: unknown;
    try {
      await client.query("ROLLBACK").catch(() => undefined);
      if (inserted) {
        await client.query("DELETE FROM payroll.pay_result_line WHERE pay_result_id = $1", [result]);
        await client.query("DELETE FROM payroll.pay_result WHERE pay_result_id = $1", [result]);
        await client.query("DELETE FROM payroll.pay_run WHERE pay_run_id = $1", [run]);
        await client.query("DELETE FROM core.employment WHERE employment_id = $1", [employment]);
        await client.query("DELETE FROM core.person WHERE person_id = $1", [person]);
        await client.query("DELETE FROM core.payroll_account WHERE payroll_account_id = $1", [account]);
        await client.query("DELETE FROM core.legal_entity_version WHERE legal_entity_id = $1", [legal]);
        await client.query("DELETE FROM core.legal_entity WHERE legal_entity_id = $1", [legal]);
      }
    } catch (error) {
      cleanupError = error;
    }
    await client.end().catch(() => undefined);
    if (cleanupError) throw cleanupError;
  }
});

test("a redelivered retro batch message does not calculate the request twice", { skip: !databaseUrl, timeout: 20_000 }, async () => {
  const client = new pg.Client({ connectionString: databaseUrl });
  const other = new pg.Client({ connectionString: databaseUrl });
  await client.connect();
  await other.connect();
  await client.query("SET statement_timeout = '5s'");
  await other.query("SET statement_timeout = '5s'");
  const tenant = crypto.randomUUID();
  const legal = crypto.randomUUID();
  const account = crypto.randomUUID();
  const person = crypto.randomUUID();
  const employment = crypto.randomUUID();
  const run = crypto.randomUUID();
  const result = crypto.randomUUID();
  const request = crypto.randomUUID();
  const createdBy = crypto.randomUUID();
  let inserted = false;
  try {
    if (!(await payrollReady(client))) return;
    await client.query("BEGIN");
    await client.query("INSERT INTO platform.tenant (tenant_id, name) VALUES ($1, 'Retro claim')", [tenant]);
    await client.query("SELECT set_config('app.tenant_id', $1, true)", [tenant]);
    await client.query("INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES ($1, $2)", [tenant, legal]);
    await client.query(
      `INSERT INTO core.legal_entity_version (tenant_id, legal_entity_id, valid_period, change_set_id, legal_name, business_number, regulatory_jurisdiction, first_nation_government)
       VALUES ($1, $2, '[2020-01-01,)', gen_random_uuid(), 'Retro Co', '123456789', 'provincial', false)`,
      [tenant, legal],
    );
    await client.query(
      `INSERT INTO core.payroll_account (tenant_id, payroll_account_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid)
       VALUES ($1, $2, $3, 'RP0001', 'regular', '[2026-01-01,)')`,
      [tenant, account, legal],
    );
    await client.query("INSERT INTO core.person (tenant_id, person_id) VALUES ($1, $2)", [tenant, person]);
    await client.query(
      "INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id, employee_number) VALUES ($1, $2, $3, $4, 'E1')",
      [tenant, employment, person, legal],
    );
    await client.query(
      `INSERT INTO payroll.pay_run (tenant_id, pay_run_id, number, run_type, legal_entity_id, population, pay_date, status, created_by)
       VALUES ($1, $2, 1, 'regular', $3, '{"mode":"employees"}', '2026-04-24', 'finalized', $4)`,
      [tenant, run, legal, createdBy],
    );
    await client.query(
      `INSERT INTO payroll.pay_result (
         tenant_id, pay_result_id, pay_run_id, employment_id, person_id, payroll_account_id, bucket, pay_date, tax_year,
         province, periods_per_year, tax_method, gross, taxable_periodic, taxable_non_periodic, pensionable, insurable,
         cpp, cpp2, ei, income_tax_federal, income_tax_provincial, territorial_payroll_tax, net, employer_cpp, employer_cpp2, employer_ei,
         input_snapshot_sha256, result_sha256, trace, status
       ) VALUES (
         $1, $2, $3, $4, $5, $6, 0, '2026-04-24', 2026,
         'ON', 26, 'periodic', 100, 100, 0, 100, 100,
         0, 0, 0, 0, 0, 0, 100, 0, 0, 0,
         'inputs', 'sha', '[]', 'finalized'
       )`,
      [tenant, result, run, employment, person, account],
    );
    await client.query(
      `INSERT INTO payroll.retro_request (tenant_id, retro_request_id, employment_id, trigger_change_set_id, original_result_id, status, difference)
       VALUES ($1, $2, $3, $4, $5, 'queued', '{"REG":"10.00"}')`,
      [tenant, request, employment, crypto.randomUUID(), result],
    );
    await client.query("COMMIT");
    inserted = true;

    const first = await claimRetroRequest(client, { tenantId: tenant, retroRequestId: request });
    assert.equal(first.outcome, "claimed");
    const again = await claimRetroRequest(client, { tenantId: tenant, retroRequestId: request });
    assert.equal(again.outcome, "already_done");
    const stored = await client.query<{ status: string; difference: { REG: string } }>(
      "SELECT status, difference FROM payroll.retro_request WHERE retro_request_id = $1",
      [request],
    );
    assert.equal(stored.rows[0]?.status, "calculated");
    assert.equal(stored.rows[0]?.difference.REG, "10.00");

    await client.query("UPDATE payroll.retro_request SET status = 'queued' WHERE retro_request_id = $1", [request]);
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.tenant_id', $1, true)", [tenant]);
    const held = await claimRetroRequest(client, { tenantId: tenant, retroRequestId: request });
    assert.equal(held.outcome, "claimed");
    await other.query("BEGIN");
    await other.query("SELECT set_config('app.tenant_id', $1, true)", [tenant]);
    const skipped = await claimRetroRequest(other, { tenantId: tenant, retroRequestId: request });
    assert.equal(skipped.outcome, "busy");
    await other.query("ROLLBACK");
    await client.query("ROLLBACK");
  } finally {
    let cleanupError: unknown;
    try {
      await client.query("ROLLBACK").catch(() => undefined);
      await other.query("ROLLBACK").catch(() => undefined);
      if (inserted) {
        await client.query("DELETE FROM payroll.retro_request WHERE retro_request_id = $1", [request]);
        await client.query("DELETE FROM payroll.pay_result WHERE pay_result_id = $1", [result]);
        await client.query("DELETE FROM payroll.pay_run WHERE pay_run_id = $1", [run]);
        await client.query("DELETE FROM core.employment WHERE employment_id = $1", [employment]);
        await client.query("DELETE FROM core.person WHERE person_id = $1", [person]);
        await client.query("DELETE FROM core.payroll_account WHERE payroll_account_id = $1", [account]);
        await client.query("DELETE FROM core.legal_entity_version WHERE legal_entity_id = $1", [legal]);
        await client.query("DELETE FROM core.legal_entity WHERE legal_entity_id = $1", [legal]);
      }
    } catch (error) {
      cleanupError = error;
    }
    await client.end().catch(() => undefined);
    await other.end().catch(() => undefined);
    if (cleanupError) throw cleanupError;
  }
});
