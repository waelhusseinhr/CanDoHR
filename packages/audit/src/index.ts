export { canonical } from "./canonical.ts";
export { fromHex, sha256, toHex, ZERO_32 } from "./bytes.ts";
export {
  AUDIT_FIELDS,
  batchHash,
  bytesEqual,
  inclusionProof,
  leafHash,
  merkleRoot,
  verifyInclusion,
  type AuditRow,
  type BatchHeader,
} from "./merkle.ts";
export {
  anchorBody,
  proofFor,
  sealTick,
  verifyLog,
  type AnchorStore,
  type Proof,
  type SealClock,
  type SealResult,
  type SealedBatch,
  type Signer,
  type VerifyFailure,
} from "./seal.ts";
