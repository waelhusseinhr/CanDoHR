import { sealTick, type AnchorStore, type SealedBatch, type Signer } from "@candohr/audit";
import { customerDigest, type SealBatch, type TenantAnchorStore } from "@candohr/changesets";

interface Env {
  // The sealer's Hyperdrive binding is added when that configuration exists.
  // Create it with caching disabled. This cron does not run a query until then.
}

/**
 * Hourly audit seal (docs/10 §5). With no database binding the tick reports that it skipped.
 * The seal itself is tested in @candohr/audit.
 */
export default {
  async scheduled(controller: { cron?: string }, _env: Env): Promise<void> {
    if (controller.cron === "15 12 * * *") {
      runDailyDigest({ batches: null, tenantId: "", now: new Date().toISOString() });
    }
  },
  async fetch(): Promise<Response> {
    return Response.json({
      ok: true,
      service: "candohr-jobs",
      step: 4,
      seal: "waiting-for-hyperdrive",
      digest: "waiting-for-hyperdrive",
    });
  },
};

/**
 * Daily customer copy of the latest audit seal (PLAT-016).
 * With no batches yet, the job reports that it is waiting for the database.
 */
export function runDailyDigest(input: {
  batches: readonly SealBatch[] | null;
  tenantId: string;
  now: string;
  dedicated?: boolean;
  anchor?: TenantAnchorStore;
}) {
  if (!input.batches) return { skipped: true as const, reason: "waiting-for-hyperdrive" };
  return {
    skipped: false as const,
    ...customerDigest({
      batches: input.batches,
      tenantId: input.tenantId,
      now: input.now,
      dedicated: input.dedicated,
      anchor: input.anchor,
    }),
  };
}

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
