import { putChunked, type ChunkStore } from "@candohr/disbursement";

/** Candidate files are split in memory. The live site does not upload them. */
export function storeCandidateDocument(store: ChunkStore, documentId: string, bytes: Uint8Array, chunkSize: number): { parts: number; bytes: number } {
  const stored = putChunked(store, documentId, bytes, chunkSize);
  const body = store.getObject(documentId);
  return { parts: stored.parts, bytes: body.length };
}
