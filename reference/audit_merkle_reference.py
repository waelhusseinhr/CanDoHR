#!/usr/bin/env python3
"""
CanDo HRIS - reference implementation of audit integrity (docs/10 §5).

Defines, exactly, the bytes the production TypeScript code must produce:

  canonical(row)      canonical JSON of an audit row (sorted keys, no spaces, UTF-8,
                      timestamps as ISO-8601 UTC with microseconds and 'Z')
  leaf_hash(row)      SHA-256(0x00 || canonical(row))                       (RFC 6962 leaf)
  merkle_root(leaves) RFC 6962 Merkle Tree Hash over the leaf hashes in audit_id order:
                        MTH([])      = SHA-256(b"")
                        MTH([h])     = h                (h is already a leaf hash)
                        MTH(D[0:n])  = SHA-256(0x01 || MTH(D[0:k]) || MTH(D[k:n])),
                                       k = largest power of two < n
  batch_hash(...)     SHA-256(0x02 || prev_batch_hash || merkle_root || canonical(batch header))
                      chains the hourly batches of one tenant
  inclusion_proof / verify_inclusion   audit path for one row (RFC 6962 §2.1.1)

Usage:
  python3 audit_merkle_reference.py --selftest      # checks tests/audit/merkle_vectors.json
  python3 audit_merkle_reference.py --make-vectors  # regenerates the vectors (review the diff!)
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

VECTORS = Path(__file__).resolve().parent.parent / "tests" / "audit" / "merkle_vectors.json"
ZERO32 = bytes(32)


def sha256(b: bytes) -> bytes:
    return hashlib.sha256(b).digest()


def canonical(obj: dict) -> bytes:
    """Canonical JSON: keys sorted, separators without spaces, UTF-8, no NaN.
    Callers must already format timestamps as 'YYYY-MM-DDTHH:MM:SS.ffffffZ' and money as strings."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")


# structural: audit leaf field names are fixed by docs/10 §5
AUDIT_FIELDS = ("tenant_id", "audit_id", "occurred_at", "actor_type", "actor_id", "on_behalf_of", "action",
                "subject_type", "subject_id", "change_set_id", "before", "after", "reason")


def leaf_hash(row: dict) -> bytes:
    """Only the listed fields are hashed (ip and user_agent are excluded so they can be redacted later
    under privacy rules without breaking proofs). Missing fields hash as null."""
    material = {k: row.get(k) for k in AUDIT_FIELDS}
    return sha256(b"\x00" + canonical(material))


def _largest_pow2_below(n: int) -> int:
    k = 1
    while k * 2 < n:
        k *= 2
    return k


def merkle_root(leaves: list[bytes]) -> bytes:
    n = len(leaves)
    if n == 0:
        return sha256(b"")
    if n == 1:
        return leaves[0]
    k = _largest_pow2_below(n)
    return sha256(b"\x01" + merkle_root(leaves[:k]) + merkle_root(leaves[k:]))


def inclusion_proof(index: int, leaves: list[bytes]) -> list[bytes]:
    n = len(leaves)
    if n <= 1:
        return []
    k = _largest_pow2_below(n)
    if index < k:
        return inclusion_proof(index, leaves[:k]) + [merkle_root(leaves[k:])]
    return inclusion_proof(index - k, leaves[k:]) + [merkle_root(leaves[:k])]


def verify_inclusion(index: int, n: int, leaf: bytes, proof: list[bytes], root: bytes) -> bool:
    """Recompute the root from a leaf and its audit path (RFC 6962 style, recursive split)."""
    def rec(i: int, size: int, path: list[bytes]) -> bytes | None:
        if size == 1:
            return leaf if not path else None
        if not path:
            return None
        k = _largest_pow2_below(size)
        sibling = path[-1]
        if i < k:
            left = rec(i, k, path[:-1])
            return None if left is None else sha256(b"\x01" + left + sibling)
        right = rec(i - k, size - k, path[:-1])
        return None if right is None else sha256(b"\x01" + sibling + right)
    return rec(index, n, proof) == root


def batch_hash(prev_batch_hash: bytes, root: bytes, header: dict) -> bytes:
    """header = {tenant_id, batch_no, first_audit_id, last_audit_id, leaf_count, sealed_at}"""
    return sha256(b"\x02" + prev_batch_hash + root + canonical(header))


def _sample_rows(n: int) -> list[dict]:
    rows = []
    for i in range(1, n + 1):
        rows.append({
            "tenant_id": "11111111-1111-1111-1111-111111111111",
            "audit_id": 1000 + i,
            "occurred_at": f"2026-10-18T14:{i:02d}:00.000000Z",
            "actor_type": "user",
            "actor_id": "user:hr-admin",
            "on_behalf_of": None,
            "action": "change_set.commit",
            "subject_type": "change_set",
            "subject_id": f"cs-{i:04d}",
            "change_set_id": f"cs-{i:04d}",
            "before": None,
            "after": {"content_sha256": sha256(f"cs-{i}".encode()).hex()},
            "reason": "REORG",
            "ip": "203.0.113.7",
        })
    return rows


def make_vectors() -> dict:
    out = {"description": "Audit integrity test vectors produced by reference/audit_merkle_reference.py. "
                          "The production code must reproduce every hash byte for byte.",
           "cases": []}
    prev = ZERO32
    for batch_no, n in enumerate([0, 1, 2, 3, 5, 8, 13], start=1):
        rows = _sample_rows(n)
        leaves = [leaf_hash(r) for r in rows]
        root = merkle_root(leaves)
        header = {"tenant_id": "11111111-1111-1111-1111-111111111111", "batch_no": batch_no,
                  "first_audit_id": rows[0]["audit_id"] if rows else None,
                  "last_audit_id": rows[-1]["audit_id"] if rows else None,
                  "leaf_count": n, "sealed_at": "2026-10-18T15:00:00.000000Z"}
        bh = batch_hash(prev, root, header)
        proofs = [{"index": i, "path": [p.hex() for p in inclusion_proof(i, leaves)]} for i in range(n)]
        out["cases"].append({"batch_no": batch_no, "rows": rows, "leaf_hashes": [l.hex() for l in leaves],
                             "merkle_root": root.hex(), "prev_batch_hash": prev.hex(), "header": header,
                             "batch_hash": bh.hex(), "proofs": proofs})
        prev = bh
    # Tamper case: deleting row 3 of the 5-row batch must change the root
    rows = _sample_rows(5)
    tampered = [leaf_hash(r) for r in rows if r["audit_id"] != 1003]
    out["tamper_check"] = {"description": "5-row batch with audit_id 1003 deleted; root must differ from batch_no 5",
                           "merkle_root_after_delete": merkle_root(tampered).hex()}
    return out


def selftest() -> int:
    v = json.loads(VECTORS.read_text())
    fails = 0
    prev = ZERO32
    for c in v["cases"]:
        leaves = [leaf_hash(r) for r in c["rows"]]
        ok = [l.hex() for l in leaves] == c["leaf_hashes"]
        root = merkle_root(leaves)
        ok &= root.hex() == c["merkle_root"]
        ok &= c["prev_batch_hash"] == prev.hex()
        bh = batch_hash(prev, root, c["header"])
        ok &= bh.hex() == c["batch_hash"]
        for p in c["proofs"]:
            ok &= verify_inclusion(p["index"], len(leaves), leaves[p["index"]],
                                   [bytes.fromhex(x) for x in p["path"]], root)
        # a wrong leaf must not verify
        if leaves:
            ok &= not verify_inclusion(0, len(leaves), sha256(b"forged"),
                                       [bytes.fromhex(x) for x in c["proofs"][0]["path"]], root)
        prev = bh
        print(("PASS" if ok else "FAIL"), f"batch {c['batch_no']} ({len(leaves)} rows)")
        fails += 0 if ok else 1
    five = next(c for c in v["cases"] if c["header"]["leaf_count"] == 5)
    t_ok = v["tamper_check"]["merkle_root_after_delete"] != five["merkle_root"]
    print(("PASS" if t_ok else "FAIL"), "deleting a row changes the root")
    fails += 0 if t_ok else 1
    print(f"{'all passed' if not fails else str(fails) + ' failed'}")
    return 1 if fails else 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--make-vectors":
        VECTORS.parent.mkdir(parents=True, exist_ok=True)
        VECTORS.write_text(json.dumps(make_vectors(), indent=2))
        print("written", VECTORS)
        sys.exit(0)
    sys.exit(selftest())
