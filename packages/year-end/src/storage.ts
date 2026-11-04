import { ChunkStore, putChunked } from "@candohr/disbursement";

/** In-memory stand-in for the chunked storage upload. The live site does not call Supabase Storage. */
export function storeReturn(store: ChunkStore, key: string, xml: string, chunkSize = 100): { parts: number; bytes: Uint8Array } {
  const bytes = new TextEncoder().encode(xml);
  const stored = putChunked(store, key, bytes, chunkSize);
  return { parts: stored.parts, bytes: store.getObject(key) };
}
