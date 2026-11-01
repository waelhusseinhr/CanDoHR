import assert from "node:assert/strict";
import { test } from "node:test";
import { generateKeyPairSync, sign, verify } from "node:crypto";
import { toHex } from "../src/bytes.ts";
import { leafHash, type AuditRow } from "../src/merkle.ts";
import { anchorBody, proofFor, sealTick, verifyLog, type SealedBatch, type Signer } from "../src/seal.ts";

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

function memoryAnchor() {
  const objects = new Map<string, { versionId: string; body: Uint8Array }>();
  let failTimes = 0;
  return {
    failNext(times: number) {
      failTimes = times;
    },
    putImmutable(key: string, body: Uint8Array) {
      if (failTimes > 0) {
        failTimes -= 1;
        throw new Error("ANCHOR_UNAVAILABLE");
      }
      if (objects.has(key)) throw new Error("OBJECT_LOCK");
      const versionId = `v-${objects.size + 1}`;
      objects.set(key, { versionId, body });
      return { versionId };
    },
    get(key: string, versionId: string) {
      const found = objects.get(key);
      if (!found || found.versionId !== versionId) return null;
      return found.body;
    },
  };
}

function row(id: number, after: string): AuditRow & { audit_id: number } {
  return {
    tenant_id: "11111111-1111-1111-1111-111111111111",
    audit_id: id,
    occurred_at: "2026-10-18T14:01:00.000000Z",
    actor_type: "user",
    actor_id: "user:hr-admin",
    on_behalf_of: null,
    action: "change_set.commit",
    subject_type: "change_set",
    subject_id: `cs-${id}`,
    change_set_id: `cs-${id}`,
    before: null,
    after: { content_sha256: after },
    reason: "REORG",
    ip: "203.0.113.7",
  };
}

test("an hourly tick seals visible rows, and a quiet day still gets one empty batch", () => {
  const signer = devSigner();
  const anchor = memoryAnchor();
  const first = sealTick({
    tenantId: "11111111-1111-1111-1111-111111111111",
    rows: [row(1, "aa"), row(2, "bb")],
    batches: [],
    clock: { sealedAt: "2026-10-18T15:00:00.000000Z", nowMs: Date.parse("2026-10-18T15:00:00.000Z") },
    signer,
    anchor,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
  assert.equal(first.batches.length, 1);
  assert.equal(first.batches[0]?.leafCount, 2);
  assert.equal(first.batches[0]?.auditIds.join(","), "1,2");
  assert.ok(first.batches[0]?.anchorUri?.endsWith("/1.json"));
  assert.equal(first.alert, null);

  const quiet = sealTick({
    tenantId: "11111111-1111-1111-1111-111111111111",
    rows: [
      { ...row(1, "aa"), batchNo: 1 },
      { ...row(2, "bb"), batchNo: 1 },
    ],
    batches: first.batches,
    clock: { sealedAt: "2026-10-19T15:00:00.000000Z", nowMs: Date.parse("2026-10-19T15:00:00.000Z") },
    signer,
    anchor,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
  const empty = quiet.batches.find((batch) => batch.batchNo === 2);
  assert.ok(empty);
  assert.equal(empty.leafCount, 0);
  assert.equal(empty.firstAuditId, null);
  assert.equal(verifyLog({
    rowsByBatch: [
      { batch: quiet.batches[0] as SealedBatch, rows: [row(1, "aa"), row(2, "bb")].map((item) => ({ ...item, leaf_hash: toHex(leafHash(item)) })) },
      { batch: empty, rows: [] },
    ],
    signer,
    anchor,
  }).ok, true);
});

test("a row still inside an open transaction is not in this batch", () => {
  const signer = devSigner();
  const anchor = memoryAnchor();
  const visible = [row(1, "aa")];
  const result = sealTick({
    tenantId: "11111111-1111-1111-1111-111111111111",
    rows: visible,
    batches: [],
    clock: { sealedAt: "2026-10-18T15:00:00.000000Z", nowMs: Date.parse("2026-10-18T15:00:00.000Z") },
    signer,
    anchor,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
  assert.deepEqual(result.assigned.map((item) => item.auditId), [1]);
  assert.equal(result.batches[0]?.auditIds.includes(2), false);
});

test("a failed anchor is retried in order and alerts after three hours", () => {
  const signer = devSigner();
  const anchor = memoryAnchor();
  anchor.failNext(1);
  const clock = { sealedAt: "2026-10-18T15:00:00.000000Z", nowMs: Date.parse("2026-10-18T15:00:00.000Z") };
  const first = sealTick({
    tenantId: "11111111-1111-1111-1111-111111111111",
    rows: [row(1, "aa")],
    batches: [],
    clock,
    signer,
    anchor,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
  assert.equal(first.batches[0]?.anchorUri, null);
  assert.equal(first.alert, null);

  const late = sealTick({
    tenantId: "11111111-1111-1111-1111-111111111111",
    rows: [{ ...row(1, "aa"), batchNo: 1 }],
    batches: first.batches,
    clock: { sealedAt: "2026-10-18T18:00:00.000000Z", nowMs: Date.parse("2026-10-18T18:00:00.000Z") },
    signer,
    anchor,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
  assert.equal(late.batches[0]?.anchorUri?.endsWith("/1.json"), true);
  assert.equal(late.alert, null);

  const stuck = memoryAnchor();
  stuck.failNext(5);
  const waiting = sealTick({
    tenantId: "11111111-1111-1111-1111-111111111111",
    rows: [row(1, "aa")],
    batches: [],
    clock: { sealedAt: "2026-10-18T15:00:00.000000Z", nowMs: Date.parse("2026-10-18T15:00:00.000Z") },
    signer,
    anchor: stuck,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
  const alerted = sealTick({
    tenantId: "11111111-1111-1111-1111-111111111111",
    rows: [{ ...row(1, "aa"), batchNo: 1 }],
    batches: waiting.batches,
    clock: { sealedAt: "2026-10-18T18:30:00.000000Z", nowMs: Date.parse("2026-10-18T18:30:00.000Z") },
    signer,
    anchor: stuck,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
  assert.equal(alerted.alert, "ANCHOR_LATE");
  assert.equal(alerted.batches[0]?.anchorUri, null);
});

test("the anchor object cannot be replaced, and a changed row fails only its own batch", () => {
  const signer = devSigner();
  const anchor = memoryAnchor();
  const sealed = sealTick({
    tenantId: "11111111-1111-1111-1111-111111111111",
    rows: [row(1, "aa"), row(2, "bb")],
    batches: [],
    clock: { sealedAt: "2026-10-18T15:00:00.000000Z", nowMs: Date.parse("2026-10-18T15:00:00.000Z") },
    signer,
    anchor,
    anchorUriPrefix: "s3://candohr-anchors/",
  });
  const batch = sealed.batches[0];
  assert.ok(batch);
  assert.throws(() => anchor.putImmutable("11111111-1111-1111-1111-111111111111/1.json", anchorBody(batch)));
  const body = new TextDecoder().decode(anchorBody(batch));
  assert.equal(body.includes("home_address"), false);
  assert.equal(body.includes("\"aa\""), false);

  const honest = [row(1, "aa"), row(2, "bb")].map((item) => ({ ...item, leaf_hash: toHex(leafHash(item)) }));
  const tampered = honest.map((item, index) => (index === 0 ? { ...item, after: { content_sha256: "ff" } } : item));
  const report = verifyLog({ rowsByBatch: [{ batch, rows: tampered }], signer, anchor });
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) => failure.auditId === 1 && failure.reason === "LEAF"));

  const proof = proofFor(row(2, "bb"), batch, [row(1, "aa"), row(2, "bb")]);
  assert.equal(proof.signingKeyId, "dev-audit-signer");
  assert.equal(proof.batchHash, batch.batchHash);
  assert.ok(proof.auditPath.length > 0);
});
