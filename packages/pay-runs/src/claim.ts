/** Claim one calculation bucket with FOR UPDATE SKIP LOCKED (docs/06 §9). */

export interface Sql {
  query<T = Record<string, unknown>>(text: string, values?: readonly unknown[]): Promise<{ rows: T[]; rowCount: number | null }>;
}

export type ClaimOutcome =
  | { outcome: "busy" }
  | { outcome: "already_done"; bucket: number }
  | { outcome: "claimed"; bucket: number; attempts: number };

const CLAIM = `
WITH next AS (
  SELECT pay_run_id, bucket
  FROM payroll.pay_run_partition
  WHERE tenant_id = $1::uuid
    AND pay_run_id = $2::uuid
    AND bucket = $3
    AND status IN ('pending', 'failed', 'calculating')
  FOR UPDATE SKIP LOCKED
)
UPDATE payroll.pay_run_partition AS partition
SET status = 'calculating',
    worker_id = $4,
    attempts = partition.attempts + 1,
    started_at = COALESCE(partition.started_at, now())
FROM next
WHERE partition.pay_run_id = next.pay_run_id
  AND partition.bucket = next.bucket
RETURNING partition.bucket, partition.attempts, partition.status
`;

const LOOK = `
SELECT status
FROM payroll.pay_run_partition
WHERE tenant_id = $1::uuid AND pay_run_id = $2::uuid AND bucket = $3
`;

/**
 * Claim this bucket, or report that another worker holds it, or that it is already finished.
 * A redelivered message for a finished bucket does not claim and does not write.
 */
export async function claimBucket(sql: Sql, input: { tenantId: string; payRunId: string; bucket: number; workerId: string }): Promise<ClaimOutcome> {
  const claimed = await sql.query<{ bucket: number; attempts: number }>(CLAIM, [
    input.tenantId,
    input.payRunId,
    input.bucket,
    input.workerId,
  ]);
  const row = claimed.rows[0];
  if (row) return { outcome: "claimed", bucket: row.bucket, attempts: row.attempts };
  const existing = await sql.query<{ status: string }>(LOOK, [input.tenantId, input.payRunId, input.bucket]);
  const status = existing.rows[0]?.status;
  if (status === "calculated" || status === "finalized") return { outcome: "already_done", bucket: input.bucket };
  return { outcome: "busy" };
}

export async function finishBucket(sql: Sql, input: { tenantId: string; payRunId: string; bucket: number; checksum: string }): Promise<void> {
  await sql.query(
    `UPDATE payroll.pay_run_partition
     SET status = 'calculated', finished_at = now(), results_checksum = $4
     WHERE tenant_id = $1::uuid AND pay_run_id = $2::uuid AND bucket = $3 AND status = 'calculating'`,
    [input.tenantId, input.payRunId, input.bucket, input.checksum],
  );
}
