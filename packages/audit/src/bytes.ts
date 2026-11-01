import { createHash } from "node:crypto";

/** SHA-256 digest. The audit reference uses the same function for every hash. */
export function sha256(data: Uint8Array): Uint8Array {
  return new Uint8Array(createHash("sha256").update(data).digest());
}

export function concat(parts: readonly Uint8Array[]): Uint8Array {
  const length = parts.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

export function toHex(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("hex");
}

export function fromHex(hex: string): Uint8Array {
  if (hex.length % 2 !== 0 || /[^0-9a-f]/i.test(hex)) {
    throw new Error("AUDIT_HEX");
  }
  return new Uint8Array(Buffer.from(hex, "hex"));
}

/** Thirty-two zero bytes. The first batch of a tenant uses this as the previous batch hash. */
export const ZERO_32 = new Uint8Array(32);
