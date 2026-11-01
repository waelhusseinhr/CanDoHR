/**
 * Canonical JSON as `reference/audit_merkle_reference.py` defines it:
 * keys sorted, no spaces, UTF-8, timestamps already formatted by the caller.
 * Matches Python `json.dumps(..., sort_keys=True, separators=(",", ":"), ensure_ascii=False)`.
 */
export function canonical(value: unknown): Uint8Array {
  return new TextEncoder().encode(canonicalString(value));
}

function canonicalString(value: unknown): string {
  if (value === null) return "null";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("CANONICAL_NUMBER");
    if (Number.isInteger(value)) return String(value);
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalString(item)).join(",")}]`;
  }
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    const keys = Object.keys(record).sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalString(record[key])}`).join(",")}}`;
  }
  throw new Error("CANONICAL_TYPE");
}
