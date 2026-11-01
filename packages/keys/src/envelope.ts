import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

export interface Kms {
  readonly keyId: string;
  /** Returns a data key and the same key wrapped so only KMS can unwrap it. */
  generateDataKey(): Promise<{ plaintext: Uint8Array; wrapped: Uint8Array }>;
  unwrapDataKey(wrapped: Uint8Array): Promise<Uint8Array>;
}

export interface Envelope {
  keyId: string;
  wrappedKey: Uint8Array;
  iv: Uint8Array;
  ciphertext: Uint8Array;
}

function aesEncrypt(keyBytes: Uint8Array, plaintext: Uint8Array): { iv: Uint8Array; ciphertext: Uint8Array } {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", Buffer.from(keyBytes), iv);
  const body = Buffer.concat([cipher.update(Buffer.from(plaintext)), cipher.final()]);
  const ciphertext = Buffer.concat([body, cipher.getAuthTag()]);
  return { iv: new Uint8Array(iv), ciphertext: new Uint8Array(ciphertext) };
}

function aesDecrypt(keyBytes: Uint8Array, iv: Uint8Array, ciphertext: Uint8Array): Uint8Array {
  const tag = ciphertext.slice(ciphertext.length - 16);
  const body = ciphertext.slice(0, ciphertext.length - 16);
  const decipher = createDecipheriv("aes-256-gcm", Buffer.from(keyBytes), Buffer.from(iv));
  decipher.setAuthTag(Buffer.from(tag));
  return new Uint8Array(Buffer.concat([decipher.update(Buffer.from(body)), decipher.final()]));
}

/**
 * Dev stand-in for AWS KMS. The master key stays in this object.
 * Production replaces it with KMS GenerateDataKey; the private key never leaves KMS.
 */
export function createDevKms(keyId = "dev-envelope"): Kms {
  const master = randomBytes(32);
  return {
    keyId,
    async generateDataKey() {
      const plaintext = randomBytes(32);
      const wrapped = aesEncrypt(master, plaintext);
      const packed = new Uint8Array(wrapped.iv.length + wrapped.ciphertext.length);
      packed.set(wrapped.iv, 0);
      packed.set(wrapped.ciphertext, wrapped.iv.length);
      return { plaintext: new Uint8Array(plaintext), wrapped: packed };
    },
    async unwrapDataKey(wrapped) {
      const iv = wrapped.slice(0, 12);
      const ciphertext = wrapped.slice(12);
      return aesDecrypt(master, iv, ciphertext);
    },
  };
}

/** Encrypts a field (SIN, bank account, health note) with a fresh data key. */
export async function envelopeEncrypt(kms: Kms, plaintext: Uint8Array): Promise<Envelope> {
  const generated = await kms.generateDataKey();
  const { iv, ciphertext } = aesEncrypt(generated.plaintext, plaintext);
  generated.plaintext.fill(0);
  return { keyId: kms.keyId, wrappedKey: generated.wrapped, iv, ciphertext };
}

export async function envelopeDecrypt(kms: Kms, envelope: Envelope): Promise<Uint8Array> {
  const dataKey = await kms.unwrapDataKey(envelope.wrappedKey);
  try {
    return aesDecrypt(dataKey, envelope.iv, envelope.ciphertext);
  } finally {
    dataKey.fill(0);
  }
}
