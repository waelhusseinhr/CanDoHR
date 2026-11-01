/** Claim one queued retro request. A second delivery for a finished request writes nothing. */

export interface Sql {
  query<T = Record<string, unknown>>(text: string, values?: readonly unknown[]): Promise<{ rows: T[]; rowCount: number | null }>;
}

export type RetroClaim =
  | { outcome: "claimed"; retroRequestId: string }
  | { outcome: "already_done"; retroRequestId: string }
  | { outcome: "busy" };

const CLAIM = `
WITH next AS MATERIALIZED (
  SELECT retro_request_id
  FROM payroll.retro_request
  WHERE tenant_id = $1::uuid
    AND retro_request_id = $2::uuid
    AND status = 'queued'
  FOR UPDATE SKIP LOCKED
)
UPDATE payroll.retro_request AS request
SET status = 'calculated'
FROM next
WHERE request.retro_request_id = next.retro_request_id
RETURNING request.retro_request_id
`;

const LOOK = `
SELECT status
FROM payroll.retro_request
WHERE tenant_id = $1::uuid AND retro_request_id = $2::uuid
`;

export async function claimRetroRequest(
  sql: Sql,
  input: { tenantId: string; retroRequestId: string },
): Promise<RetroClaim> {
  const claimed = await sql.query<{ retro_request_id: string }>(CLAIM, [input.tenantId, input.retroRequestId]);
  const row = claimed.rows[0];
  if (row) return { outcome: "claimed", retroRequestId: row.retro_request_id };
  const existing = await sql.query<{ status: string }>(LOOK, [input.tenantId, input.retroRequestId]);
  const status = existing.rows[0]?.status;
  if (status && status !== "queued") return { outcome: "already_done", retroRequestId: input.retroRequestId };
  return { outcome: "busy" };
}
