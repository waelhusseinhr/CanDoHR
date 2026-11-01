/**
 * Daily customer audit digest (PLAT-016).
 * The hourly sealer still owns the batch hash. This job copies the latest hash,
 * batch number, and signature to the customer, and writes the same copy to a
 * dedicated tenant's own store when they have one. It does not call AWS from here.
 */

export interface SealBatch {
  tenantId: string;
  batchNo: number;
  batchHash: string;
  prevBatchHash: string;
  signature: string;
  sealedAt: string;
}

export interface DigestRecord {
  tenantId: string;
  batchNo: number;
  batchHash: string;
  signature: string;
  sentAt: string;
}

export interface TenantAnchorStore {
  put(tenantId: string, body: DigestRecord): void;
  get(tenantId: string): DigestRecord | null;
}

export class MemoryAnchorStore implements TenantAnchorStore {
  private readonly rows = new Map<string, DigestRecord>();
  put(tenantId: string, body: DigestRecord): void {
    this.rows.set(tenantId, { ...body });
  }
  get(tenantId: string): DigestRecord | null {
    const row = this.rows.get(tenantId);
    return row ? { ...row } : null;
  }
}

export function customerDigest(input: {
  batches: readonly SealBatch[];
  tenantId: string;
  now: string;
  /** OCAP or dedicated tenant: also write the digest with that tenant's own key material. */
  dedicated?: boolean;
  anchor?: TenantAnchorStore;
}): { digest: DigestRecord; anchorWritten: boolean } {
  const mine = input.batches
    .filter((batch) => batch.tenantId === input.tenantId)
    .sort((a, b) => a.batchNo - b.batchNo);
  const last = mine[mine.length - 1];
  if (!last) {
    throw new Error("NO_BATCH");
  }
  const digest: DigestRecord = {
    tenantId: input.tenantId,
    batchNo: last.batchNo,
    batchHash: last.batchHash,
    signature: last.signature,
    sentAt: input.now,
  };
  const anchorWritten = Boolean(input.dedicated && input.anchor);
  if (input.dedicated && input.anchor) input.anchor.put(input.tenantId, digest);
  return { digest, anchorWritten };
}

/** A digest kept from an earlier day is still in today's chain when each batch points at the one before it. */
export function digestStillInChain(kept: { batchHash: string }, batches: readonly SealBatch[]): boolean {
  const ordered = [...batches].sort((a, b) => a.batchNo - b.batchNo);
  if (!ordered.some((batch) => batch.batchHash === kept.batchHash)) return false;
  for (let index = 1; index < ordered.length; index += 1) {
    const prev = ordered[index - 1];
    const row = ordered[index];
    if (!prev || !row || row.prevBatchHash !== prev.batchHash) return false;
  }
  return true;
}
