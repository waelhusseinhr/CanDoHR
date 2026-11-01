import { createHash } from "node:crypto";

/** B = ceil(subjects / 500), from 1 to 256 (docs/06 §9). */
export function bucketCountFor(subjectCount: number): number {
  if (!Number.isInteger(subjectCount) || subjectCount < 0) {
    throw new Error("SUBJECT_COUNT");
  }
  if (subjectCount === 0) return 1;
  return Math.min(256, Math.max(1, Math.ceil(subjectCount / 500)));
}

/** Stable bucket in 0 .. count-1. The same person always lands in the same bucket for a given count. */
export function bucketFor(payrollAccountId: string, personId: string, count: number): number {
  if (count < 1 || count > 256) throw new Error("BUCKET_COUNT");
  const digest = createHash("sha256").update(`${payrollAccountId}|${personId}`).digest();
  return digest.readUInt32BE(0) % count;
}

export interface SubjectRef {
  payrollAccountId: string;
  personId: string;
}

export function assignBuckets(subjects: readonly SubjectRef[], count = bucketCountFor(subjects.length)): Map<number, SubjectRef[]> {
  const groups = new Map<number, SubjectRef[]>();
  for (let bucket = 0; bucket < count; bucket += 1) groups.set(bucket, []);
  for (const subject of subjects) {
    const bucket = bucketFor(subject.payrollAccountId, subject.personId, count);
    groups.get(bucket)?.push(subject);
  }
  return groups;
}

export interface BucketMessage {
  payRunId: string;
  bucket: number;
}

/** One queue message per bucket, including empty buckets so a worker can mark them done. */
export function bucketMessages(payRunId: string, count: number): BucketMessage[] {
  return Array.from({ length: count }, (_unused, bucket) => ({ payRunId, bucket }));
}
