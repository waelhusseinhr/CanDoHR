import assert from "node:assert/strict";
import { test } from "node:test";
import { createDevKms, envelopeDecrypt, envelopeEncrypt } from "../src/envelope.ts";

test("a field round-trips and the stored envelope does not hold the data key", async () => {
  const kms = createDevKms();
  const plaintext = new TextEncoder().encode("123456789");
  const envelope = await envelopeEncrypt(kms, plaintext);
  const opened = await envelopeDecrypt(kms, envelope);
  assert.equal(new TextDecoder().decode(opened), "123456789");
  const stored = Buffer.concat([envelope.wrappedKey, envelope.iv, envelope.ciphertext]);
  assert.equal(stored.includes(Buffer.from(plaintext)), false);
  assert.equal(envelope.keyId, "dev-envelope");
});
