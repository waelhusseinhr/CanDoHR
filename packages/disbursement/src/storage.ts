import { createHash } from "node:crypto";
import { DisbursementError } from "./money.ts";

type Part = { partNumber: number; body: Uint8Array };
type Upload = { key: string; parts: Part[] };

/**
 * In-memory stand-in for an S3-style multipart upload.
 * The live site does not call Supabase Storage.
 */
export class ChunkStore {
  private uploads = new Map<string, Upload>();
  private objects = new Map<string, Uint8Array>();
  private sequence = 0;

  createMultipartUpload(key: string): { uploadId: string; key: string } {
    this.sequence += 1;
    const uploadId = `up-${this.sequence}`;
    this.uploads.set(uploadId, { key, parts: [] });
    return { uploadId, key };
  }

  uploadPart(uploadId: string, partNumber: number, body: Uint8Array): { etag: string } {
    const upload = this.uploads.get(uploadId);
    if (!upload) throw new DisbursementError("UPLOAD");
    if (partNumber < 1) throw new DisbursementError("UPLOAD");
    upload.parts = upload.parts.filter((part) => part.partNumber !== partNumber);
    upload.parts.push({ partNumber, body: body.slice() });
    return { etag: createHash("sha256").update(body).digest("hex") };
  }

  completeMultipartUpload(uploadId: string): { key: string; bytes: number } {
    const upload = this.uploads.get(uploadId);
    if (!upload) throw new DisbursementError("UPLOAD");
    const ordered = [...upload.parts].sort((left, right) => left.partNumber - right.partNumber);
    const total = ordered.reduce((count, part) => count + part.body.length, 0);
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const part of ordered) {
      bytes.set(part.body, offset);
      offset += part.body.length;
    }
    this.objects.set(upload.key, bytes);
    this.uploads.delete(uploadId);
    return { key: upload.key, bytes: total };
  }

  getObject(key: string): Uint8Array {
    const bytes = this.objects.get(key);
    if (!bytes) throw new DisbursementError("NOT_FOUND");
    return bytes;
  }
}

export function putChunked(store: ChunkStore, key: string, bytes: Uint8Array, chunkSize: number): { parts: number } {
  if (chunkSize < 1) throw new DisbursementError("UPLOAD");
  const upload = store.createMultipartUpload(key);
  let parts = 0;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    parts += 1;
    store.uploadPart(upload.uploadId, parts, bytes.slice(offset, offset + chunkSize));
  }
  if (parts === 0) {
    parts = 1;
    store.uploadPart(upload.uploadId, 1, new Uint8Array());
  }
  store.completeMultipartUpload(upload.uploadId);
  return { parts };
}
