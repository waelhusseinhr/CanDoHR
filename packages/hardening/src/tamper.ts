import { generateKeyPairSync, sign, verify } from "node:crypto";
import {
  leafHash,
  sealTick,
  toHex,
  verifyLog,
  type AnchorStore,
  type AuditRow,
  type SealedBatch,
  type Signer,
  type VerifyFailure,
} from "@candohr/audit";

const TENANT = "11111111-1111-1111-1111-111111111111";

export interface NamedFailure {
  batchNo: number;
  auditId: number | null;
  reason: string;
}

export interface TamperDrill {
  /** The sealed log verifies before any change. */
  clean: boolean;
  /**
   * verifyLog sorts by audit_id, so shuffling the array is not a tamper.
   * A reorder that moves a row onto another audit id is named below.
   */
  arrayReorderStillVerifies: boolean;
  edit: NamedFailure;
  delete: NamedFailure;
  reorder: NamedFailure;
  otherBatchCleanAfterEdit: boolean;
  /** This drill uses an in-memory anchor. It is not a copy of a staging database. */
  stagingCopy: false;
}

type DrillRow = AuditRow & { audit_id: number; leaf_hash: string };

function devSigner(): Signer {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    keyId: "dev-audit-signer",
    sign(bytes) {
      return new Uint8Array(sign(null, Buffer.from(bytes), privateKey));
    },
    verify(bytes, signature) {
      return verify(null, Buffer.from(bytes), publicKey, Buffer.from(signature));
    },
  };
}

function memoryAnchor(): AnchorStore {
  const objects = new Map<string, { versionId: string; body: Uint8Array }>();
  return {
    putImmutable(key, body) {
      if (objects.has(key)) throw new Error("OBJECT_LOCK");
      const versionId = `v-${String(objects.size + 1)}`;
      objects.set(key, { versionId, body });
      return { versionId };
    },
    get(key, versionId) {
      const found = objects.get(key);
      if (!found || found.versionId !== versionId) return null;
      return found.body;
    },
  };
}

function baseRow(id: number, content: string): AuditRow & { audit_id: number } {
  return {
    tenant_id: TENANT,
    audit_id: id,
    occurred_at: "2026-10-18T14:01:00.000000Z",
    actor_type: "user",
    actor_id: "user:drill",
    on_behalf_of: null,
    action: "change_set.commit",
    subject_type: "change_set",
    subject_id: `cs-${String(id)}`,
    change_set_id: `cs-${String(id)}`,
    before: null,
    after: { content_sha256: content },
    reason: "DRILL",
  };
}

function stamped(id: number, content: string): DrillRow {
  const row = baseRow(id, content);
  return { ...row, leaf_hash: toHex(leafHash(row)) };
}

function clock(day: string): { sealedAt: string; nowMs: number } {
  return {
    sealedAt: `${day}T15:00:00.000000Z`,
    nowMs: Date.parse(`${day}T15:00:00.000Z`),
  };
}

function named(failures: readonly VerifyFailure[], reason: string): NamedFailure {
  for (const failure of failures) {
    if (failure.reason === reason) {
      return { batchNo: failure.batchNo, auditId: failure.auditId, reason: failure.reason };
    }
  }
  throw new Error("TAMPER_NOT_NAMED");
}

function batchRows(batch: SealedBatch, rows: readonly DrillRow[]): DrillRow[] {
  const wanted = new Set(batch.auditIds);
  return rows.filter((row) => wanted.has(row.audit_id));
}

/** Seal two batches, then edit, delete, and move a row onto another audit id. */
export function tamperDrill(): TamperDrill {
  const signer = devSigner();
  const anchor = memoryAnchor();
  const firstRows = [stamped(1, "aa"), stamped(2, "bb"), stamped(3, "cc")];
  const first = sealTick({
    tenantId: TENANT,
    rows: firstRows,
    batches: [],
    clock: clock("2026-10-18"),
    signer,
    anchor,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
  const secondRows = [stamped(4, "dd"), stamped(5, "ee")];
  const second = sealTick({
    tenantId: TENANT,
    rows: [...firstRows.map((row) => ({ ...row, batchNo: 1 })), ...secondRows],
    batches: first.batches,
    clock: clock("2026-10-19"),
    signer,
    anchor,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
  const batchOne = second.batches.find((batch) => batch.batchNo === 1);
  const batchTwo = second.batches.find((batch) => batch.batchNo === 2);
  if (!batchOne || !batchTwo) throw new Error("TAMPER_SEAL");
  const rowsOne = batchRows(batchOne, firstRows);
  const rowsTwo = batchRows(batchTwo, secondRows);
  const clean = verifyLog({
    rowsByBatch: [
      { batch: batchOne, rows: rowsOne },
      { batch: batchTwo, rows: rowsTwo },
    ],
    signer,
    anchor,
  });

  const shuffled = [rowsOne[2], rowsOne[0], rowsOne[1]].filter((row): row is DrillRow => row !== undefined);
  const arrayReorder = verifyLog({
    rowsByBatch: [
      { batch: batchOne, rows: shuffled },
      { batch: batchTwo, rows: rowsTwo },
    ],
    signer,
    anchor,
  });

  const edited = rowsOne.map((row) =>
    row.audit_id === 2 ? { ...row, after: { content_sha256: "edited" } } : row,
  );
  const editResult = verifyLog({
    rowsByBatch: [
      { batch: batchOne, rows: edited },
      { batch: batchTwo, rows: rowsTwo },
    ],
    signer,
    anchor,
  });

  const deleted = rowsOne.filter((row) => row.audit_id !== 2);
  const deleteResult = verifyLog({
    rowsByBatch: [{ batch: batchOne, rows: deleted }],
    signer,
    anchor,
  });

  const reordered = rowsOne.map((row) => (row.audit_id === 3 ? { ...row, audit_id: 9 } : row));
  const reorderResult = verifyLog({
    rowsByBatch: [{ batch: batchOne, rows: reordered }],
    signer,
    anchor,
  });

  return {
    clean: clean.ok,
    arrayReorderStillVerifies: arrayReorder.ok,
    edit: named(editResult.failures, "LEAF"),
    delete: named(deleteResult.failures, "LEAF_COUNT"),
    reorder: named(reorderResult.failures, "AUDIT_ID_GAP"),
    otherBatchCleanAfterEdit: editResult.failures.every((failure) => failure.batchNo !== batchTwo.batchNo),
    stagingCopy: false,
  };
}
