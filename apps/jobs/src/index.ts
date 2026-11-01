import { sealTick, type AnchorStore, type SealedBatch, type Signer } from "@candohr/audit";

interface Env {
  // The sealer's Hyperdrive binding is added when that configuration exists.
  // Create it with caching disabled. This cron does not run a query until then.
}

/**
 * Hourly audit seal (docs/10 §5). With no database binding the tick reports that it skipped.
 * The seal itself is tested in @candohr/audit.
 */
export default {
  async scheduled(_controller: unknown, _env: Env): Promise<void> {
    return;
  },
  async fetch(): Promise<Response> {
    return Response.json({ ok: true, service: "candohr-jobs", step: 3, seal: "waiting-for-hyperdrive" });
  },
};

/** Called by tests and, later, by the scheduled handler once the sealer database is bound. */
export function runSeal(input: {
  tenantId: string;
  rows: readonly { audit_id: number; batchNo?: number | null; [key: string]: unknown }[];
  batches: readonly SealedBatch[];
  sealedAt: string;
  nowMs: number;
  signer: Signer;
  anchor: AnchorStore;
}) {
  return sealTick({
    tenantId: input.tenantId,
    rows: input.rows,
    batches: input.batches,
    clock: { sealedAt: input.sealedAt, nowMs: input.nowMs },
    signer: input.signer,
    anchor: input.anchor,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
}
