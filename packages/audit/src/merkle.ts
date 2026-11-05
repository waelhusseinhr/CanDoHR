import { concat, sha256, ZERO_32 } from "./bytes.ts";
import { canonical } from "./canonical.ts";

/**
 * Fields covered by the leaf hash. IP address and user agent are left out so a
 * privacy redaction does not break an old proof (docs/10 §5, PLAT-012 AC3).
 */
export const AUDIT_FIELDS = [
  "tenant_id",
  "audit_id",
  "occurred_at",
  "actor_type",
  "actor_id",
  "on_behalf_of",
  "action",
  "subject_type",
  "subject_id",
  "change_set_id",
  "before",
  "after",
  "reason",
] as const;

export type AuditField = (typeof AUDIT_FIELDS)[number];

export type AuditMaterial = Record<AuditField, unknown>;

/** A row the hasher understands. Extra columns such as `ip` are ignored. */
export type AuditRow = Partial<AuditMaterial> & Record<string, unknown>;

function materialOf(row: AuditRow): AuditMaterial {
  const material = {} as AuditMaterial;
  for (const field of AUDIT_FIELDS) {
    const value = row[field];
    material[field] = value === undefined ? null : value;
  }
  return material;
}

/** SHA-256(0x00 || canonical(row)) over AUDIT_FIELDS. Missing fields hash as null. */
export function leafHash(row: AuditRow): Uint8Array {
  return sha256(concat([new Uint8Array([0x00]), canonical(materialOf(row))]));
}

function largestPow2Below(n: number): number {
  let k = 1;
  while (k * 2 < n) k *= 2;
  return k;
}

/** RFC 6962 Merkle tree hash. An empty list hashes as SHA-256 of no bytes. */
export function merkleRoot(leaves: readonly Uint8Array[]): Uint8Array {
  const n = leaves.length;
  if (n === 0) return sha256(new Uint8Array(0));
  if (n === 1) return leaves[0] ?? sha256(new Uint8Array(0));
  const k = largestPow2Below(n);
  return sha256(concat([new Uint8Array([0x01]), merkleRoot(leaves.slice(0, k)), merkleRoot(leaves.slice(k))]));
}

/** Audit path for one leaf. The last item is the sibling of the largest split (RFC 6962 §2.1.1). */
export function inclusionProof(index: number, leaves: readonly Uint8Array[]): Uint8Array[] {
  const n = leaves.length;
  if (n <= 1) return [];
  const k = largestPow2Below(n);
  if (index < k) return [...inclusionProof(index, leaves.slice(0, k)), merkleRoot(leaves.slice(k))];
  return [...inclusionProof(index - k, leaves.slice(k)), merkleRoot(leaves.slice(0, k))];
}

/** Recompute the root from a leaf and its audit path. */
export function verifyInclusion(
  index: number,
  size: number,
  leaf: Uint8Array,
  proof: readonly Uint8Array[],
  root: Uint8Array,
): boolean {
  const rec = (i: number, n: number, path: readonly Uint8Array[]): Uint8Array | null => {
    if (n === 1) return path.length === 0 ? leaf : null;
    if (path.length === 0) return null;
    const k = largestPow2Below(n);
    const sibling = path[path.length - 1];
    if (!sibling) return null;
    if (i < k) {
      const left = rec(i, k, path.slice(0, -1));
      return left === null ? null : sha256(concat([new Uint8Array([0x01]), left, sibling]));
    }
    const right = rec(i - k, n - k, path.slice(0, -1));
    return right === null ? null : sha256(concat([new Uint8Array([0x01]), sibling, right]));
  };
  const computed = rec(index, size, proof);
  return computed !== null && bytesEqual(computed, root);
}

export interface BatchHeader {
  tenant_id: string;
  batch_no: number;
  first_audit_id: number | null;
  last_audit_id: number | null;
  leaf_count: number;
  sealed_at: string;
}

/** SHA-256(0x02 || previous batch hash || root || canonical(header)). */
export function batchHash(prevBatchHash: Uint8Array, root: Uint8Array, header: BatchHeader): Uint8Array {
  if (prevBatchHash.length !== 32 || root.length !== 32) throw new Error("AUDIT_HASH_LENGTH");
  return sha256(concat([new Uint8Array([0x02]), prevBatchHash, root, canonical(header)]));
}

export function bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let diff = 0;
  // structural: missing numeric coalesces to zero for arithmetic
  for (let i = 0; i < left.length; i += 1) diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  return diff === 0;
}

export { ZERO_32 };
