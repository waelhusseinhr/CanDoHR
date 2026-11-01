import { fromHex, toHex, ZERO_32 } from "./bytes.ts";
import {
  batchHash,
  bytesEqual,
  inclusionProof,
  leafHash,
  merkleRoot,
  verifyInclusion,
  type AuditRow,
  type BatchHeader,
} from "./merkle.ts";

export interface Signer {
  readonly keyId: string;
  sign(batchHashBytes: Uint8Array): Uint8Array;
  verify(batchHashBytes: Uint8Array, signature: Uint8Array): boolean;
}

export interface AnchorStore {
  /** Write-once. A second put of the same key must fail (Object Lock compliance). */
  putImmutable(key: string, body: Uint8Array): { versionId: string };
  get(key: string, versionId: string): Uint8Array | null;
}

export interface SealedBatch {
  tenantId: string;
  batchNo: number;
  firstAuditId: number | null;
  lastAuditId: number | null;
  leafCount: number;
  sealedAt: string;
  merkleRoot: string;
  prevBatchHash: string;
  batchHash: string;
  signature: string;
  signingKeyId: string;
  anchorUri: string | null;
  anchorVersionId: string | null;
  anchoredAt: string | null;
  /** Audit ids assigned to this batch, in order. Empty when the batch is the daily empty seal. */
  auditIds: number[];
}

export interface SealClock {
  /** ISO-8601 UTC with microseconds and Z, the form the reference hashes. */
  sealedAt: string;
  /** Milliseconds since epoch, used only for the three-hour anchor alert. */
  nowMs: number;
}

export interface SealResult {
  batches: SealedBatch[];
  /** Rows whose batch assignment changed on this tick. */
  assigned: { auditId: number; batchNo: number; leafHash: string }[];
  /** Set when a sealed batch has waited more than three hours for its anchor. */
  alert: string | null;
}

const THREE_HOURS_MS = 3 * 60 * 60 * 1000;

function headerOf(batch: SealedBatch): BatchHeader {
  return {
    tenant_id: batch.tenantId,
    batch_no: batch.batchNo,
    first_audit_id: batch.firstAuditId,
    last_audit_id: batch.lastAuditId,
    leaf_count: batch.leafCount,
    sealed_at: batch.sealedAt,
  };
}

function anchorKey(tenantId: string, batchNo: number): string {
  return `${tenantId}/${batchNo}.json`;
}

/** Hashes and the signature only. Personal data stays in the database. */
export function anchorBody(batch: SealedBatch): Uint8Array {
  const json = JSON.stringify({
    batch_hash: batch.batchHash,
    batch_no: batch.batchNo,
    merkle_root: batch.merkleRoot,
    sealed_at: batch.sealedAt,
    signature: batch.signature,
    signing_key_id: batch.signingKeyId,
    tenant_id: batch.tenantId,
  });
  return new TextEncoder().encode(json);
}

function dayOf(iso: string): string {
  return iso.slice(0, 10);
}

/**
 * One hourly tick for one tenant.
 * Unsealed rows that the caller can see (committed) become the next batch.
 * A quiet day still gets one empty batch. Anchors are written in batch order.
 */
export function sealTick(input: {
  tenantId: string;
  rows: readonly (AuditRow & { audit_id: number; batchNo?: number | null })[];
  batches: readonly SealedBatch[];
  clock: SealClock;
  signer: Signer;
  anchor: AnchorStore;
  anchorUriPrefix: string;
}): SealResult {
  const batches = input.batches.map((batch) => ({ ...batch }));
  const assigned: SealResult["assigned"] = [];
  const ordered = [...batches].sort((a, b) => a.batchNo - b.batchNo);
  const last = ordered[ordered.length - 1];
  const unsealed = input.rows
    .filter((row) => row.batchNo == null)
    .sort((a, b) => Number(a.audit_id) - Number(b.audit_id));
  const sealedToday = ordered.some((batch) => dayOf(batch.sealedAt) === dayOf(input.clock.sealedAt));

  if (unsealed.length > 0 || !sealedToday) {
    const leaves = unsealed.map((row) => leafHash(row));
    const root = merkleRoot(leaves);
    const prev = last ? fromHex(last.batchHash) : ZERO_32;
    const batchNo = last ? last.batchNo + 1 : 1;
    const header: BatchHeader = {
      tenant_id: input.tenantId,
      batch_no: batchNo,
      first_audit_id: unsealed[0] ? Number(unsealed[0].audit_id) : null,
      last_audit_id: unsealed.length ? Number(unsealed[unsealed.length - 1]?.audit_id) : null,
      leaf_count: unsealed.length,
      sealed_at: input.clock.sealedAt,
    };
    const hash = batchHash(prev, root, header);
    const signature = input.signer.sign(hash);
    const batch: SealedBatch = {
      tenantId: input.tenantId,
      batchNo,
      firstAuditId: header.first_audit_id,
      lastAuditId: header.last_audit_id,
      leafCount: unsealed.length,
      sealedAt: input.clock.sealedAt,
      merkleRoot: toHex(root),
      prevBatchHash: toHex(prev),
      batchHash: toHex(hash),
      signature: toHex(signature),
      signingKeyId: input.signer.keyId,
      anchorUri: null,
      anchorVersionId: null,
      anchoredAt: null,
      auditIds: unsealed.map((row) => Number(row.audit_id)),
    };
    batches.push(batch);
    for (const row of unsealed) {
      assigned.push({ auditId: Number(row.audit_id), batchNo, leafHash: toHex(leafHash(row)) });
    }
  }

  let alert: string | null = null;
  const pending = batches.filter((batch) => batch.anchorUri === null).sort((a, b) => a.batchNo - b.batchNo);
  for (const batch of pending) {
    try {
      const key = anchorKey(batch.tenantId, batch.batchNo);
      const put = input.anchor.putImmutable(key, anchorBody(batch));
      batch.anchorUri = `${input.anchorUriPrefix}${key}`;
      batch.anchorVersionId = put.versionId;
      batch.anchoredAt = input.clock.sealedAt;
    } catch {
      const sealedMs = Date.parse(batch.sealedAt);
      if (Number.isFinite(sealedMs) && input.clock.nowMs - sealedMs >= THREE_HOURS_MS) {
        alert = "ANCHOR_LATE";
      }
      break;
    }
  }

  return { batches, assigned, alert };
}

export interface Proof {
  auditId: number;
  leafHash: string;
  batch: BatchHeader;
  auditPath: string[];
  batchHash: string;
  signature: string;
  signingKeyId: string;
}

export function proofFor(row: AuditRow & { audit_id: number }, batch: SealedBatch, rowsInBatch: readonly AuditRow[]): Proof {
  const leaves = rowsInBatch.map((item) => leafHash(item));
  const index = rowsInBatch.findIndex((item) => Number(item.audit_id) === Number(row.audit_id));
  if (index < 0) throw new Error("AUDIT_NOT_IN_BATCH");
  const leaf = leaves[index];
  if (!leaf) throw new Error("AUDIT_NOT_IN_BATCH");
  return {
    auditId: Number(row.audit_id),
    leafHash: toHex(leaf),
    batch: headerOf(batch),
    auditPath: inclusionProof(index, leaves).map((part) => toHex(part)),
    batchHash: batch.batchHash,
    signature: batch.signature,
    signingKeyId: batch.signingKeyId,
  };
}

export interface VerifyFailure {
  batchNo: number;
  auditId: number | null;
  reason: string;
}

/** Recompute roots, the chain, signatures and anchored copies. Other batches stay valid when one fails. */
export function verifyLog(input: {
  rowsByBatch: readonly { batch: SealedBatch; rows: readonly AuditRow[] }[];
  signer: Signer;
  anchor: AnchorStore;
}): { ok: boolean; failures: VerifyFailure[] } {
  const failures: VerifyFailure[] = [];
  const ordered = [...input.rowsByBatch].sort((a, b) => a.batch.batchNo - b.batch.batchNo);
  let expectedPrev = toHex(ZERO_32);
  for (const { batch, rows } of ordered) {
    if (batch.prevBatchHash !== expectedPrev) {
      failures.push({ batchNo: batch.batchNo, auditId: null, reason: "CHAIN" });
    }
    const sorted = [...rows].sort((a, b) => Number(a.audit_id) - Number(b.audit_id));
    const ids = sorted.map((row) => Number(row.audit_id));
    if (batch.leafCount !== ids.length) {
      failures.push({ batchNo: batch.batchNo, auditId: null, reason: "LEAF_COUNT" });
    }
    if (ids.length > 0) {
      for (let i = 1; i < ids.length; i += 1) {
        const prev = ids[i - 1] ?? 0;
        const current = ids[i] ?? 0;
        if (current !== prev + 1) {
          failures.push({ batchNo: batch.batchNo, auditId: current, reason: "AUDIT_ID_GAP" });
        }
      }
    }
    const leaves: Uint8Array[] = [];
    for (const row of sorted) {
      const hash = leafHash(row);
      const stored = typeof row.leaf_hash === "string" ? row.leaf_hash : null;
      if (stored && stored !== toHex(hash)) {
        failures.push({ batchNo: batch.batchNo, auditId: Number(row.audit_id), reason: "LEAF" });
      }
      leaves.push(hash);
    }
    const root = merkleRoot(leaves);
    if (toHex(root) !== batch.merkleRoot) {
      failures.push({ batchNo: batch.batchNo, auditId: null, reason: "ROOT" });
    }
    const hash = batchHash(fromHex(batch.prevBatchHash), root, headerOf(batch));
    if (!bytesEqual(hash, fromHex(batch.batchHash))) {
      failures.push({ batchNo: batch.batchNo, auditId: null, reason: "BATCH_HASH" });
    }
    if (!input.signer.verify(fromHex(batch.batchHash), fromHex(batch.signature))) {
      failures.push({ batchNo: batch.batchNo, auditId: null, reason: "SIGNATURE" });
    }
    if (batch.anchorVersionId && batch.anchorUri) {
      const key = anchorKey(batch.tenantId, batch.batchNo);
      const stored = input.anchor.get(key, batch.anchorVersionId);
      const expect = anchorBody(batch);
      if (!stored || !bytesEqual(stored, expect)) {
        failures.push({ batchNo: batch.batchNo, auditId: null, reason: "ANCHOR" });
      }
    }
    const proofIndex = 0;
    const first = leaves[proofIndex];
    if (first && leaves.length > 0) {
      const path = inclusionProof(proofIndex, leaves);
      if (!verifyInclusion(proofIndex, leaves.length, first, path, root)) {
        failures.push({ batchNo: batch.batchNo, auditId: ids[0] ?? null, reason: "INCLUSION" });
      }
    }
    expectedPrev = batch.batchHash;
  }
  return { ok: failures.length === 0, failures };
}
