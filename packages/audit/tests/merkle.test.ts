import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { fromHex, toHex } from "../src/bytes.ts";
import { batchHash, inclusionProof, leafHash, merkleRoot, verifyInclusion, type AuditRow } from "../src/merkle.ts";

interface VectorCase {
  batch_no: number;
  rows: AuditRow[];
  leaf_hashes: string[];
  merkle_root: string;
  prev_batch_hash: string;
  header: {
    tenant_id: string;
    batch_no: number;
    first_audit_id: number | null;
    last_audit_id: number | null;
    leaf_count: number;
    sealed_at: string;
  };
  batch_hash: string;
  proofs: { index: number; path: string[] }[];
}

const vectors = JSON.parse(
  readFileSync(new URL("../../../tests/audit/merkle_vectors.json", import.meta.url), "utf8"),
) as {
  cases: VectorCase[];
  tamper_check: { merkle_root_after_delete: string };
};

test("leaf hashes, roots, batch hashes and proofs match the reference vectors", () => {
  for (const item of vectors.cases) {
    const leaves = item.rows.map((row) => leafHash(row));
    assert.deepEqual(
      leaves.map((leaf) => toHex(leaf)),
      item.leaf_hashes,
      `batch ${item.batch_no} leaves`,
    );
    assert.equal(toHex(merkleRoot(leaves)), item.merkle_root, `batch ${item.batch_no} root`);
    assert.equal(
      toHex(batchHash(fromHex(item.prev_batch_hash), merkleRoot(leaves), item.header)),
      item.batch_hash,
      `batch ${item.batch_no} hash`,
    );
    for (const proof of item.proofs) {
      const path = inclusionProof(proof.index, leaves);
      assert.deepEqual(
        path.map((part) => toHex(part)),
        proof.path,
        `batch ${item.batch_no} proof ${proof.index}`,
      );
      const leaf = leaves[proof.index];
      assert.ok(leaf);
      assert.equal(verifyInclusion(proof.index, leaves.length, leaf, path, merkleRoot(leaves)), true);
    }
  }
});

test("changing the IP address does not change the leaf hash", () => {
  const row = vectors.cases.find((item) => item.rows.length > 0)?.rows[0];
  assert.ok(row);
  const original = toHex(leafHash(row));
  const redacted = toHex(leafHash({ ...row, ip: null, user_agent: "removed" }));
  assert.equal(redacted, original);
});

test("deleting a row changes the root", () => {
  const five = vectors.cases.find((item) => item.header.leaf_count === 5);
  assert.ok(five);
  const remaining = five.rows.filter((row) => row.audit_id !== 1003).map((row) => leafHash(row));
  assert.equal(toHex(merkleRoot(remaining)), vectors.tamper_check.merkle_root_after_delete);
  assert.notEqual(vectors.tamper_check.merkle_root_after_delete, five.merkle_root);
});
