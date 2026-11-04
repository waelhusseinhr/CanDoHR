import { createHash } from "node:crypto";
import { assignBuckets, bucketCountFor, type SubjectRef } from "@candohr/pay-runs";

/** docs/02: 50,000 employees, 100 buckets. This fingerprint is bucket assignment, not a tax calculation. */
export const SUBJECT_COUNT = 50000;

export function syntheticSubjects(count: number): SubjectRef[] {
  if (!Number.isInteger(count) || count < 1) throw new Error("SUBJECT_COUNT");
  const subjects: SubjectRef[] = [];
  let index = 0;
  while (index < count) {
    subjects.push({
      payrollAccountId: "demo-payroll-account",
      personId: `person-${String(index).padStart(6, "0")}`,
    });
    index += 1;
  }
  return subjects;
}

/**
 * Split buckets across in-process partitions, then hash the sorted person fingerprints.
 * The same subjects produce the same hash for every partition count.
 * This does not call the payroll engine and does not use a Cloudflare Queue.
 */
export function assignmentResultSha256(subjects: readonly SubjectRef[], consumerCount: number): string {
  if (!Number.isInteger(consumerCount) || consumerCount < 1) throw new Error("CONSUMER_COUNT");
  const bucketCount = bucketCountFor(subjects.length);
  const groups = assignBuckets(subjects, bucketCount);
  const lines: string[] = [];
  let consumer = 0;
  while (consumer < consumerCount) {
    for (const [bucket, members] of groups) {
      if (bucket % consumerCount !== consumer) continue;
      const ordered = [...members].sort((left, right) => left.personId.localeCompare(right.personId));
      for (const member of ordered) {
        const fingerprint = createHash("sha256").update(`${member.personId}|${String(bucket)}`).digest("hex");
        lines.push(`${member.personId}|${fingerprint}`);
      }
    }
    consumer += 1;
  }
  lines.sort();
  return createHash("sha256").update(lines.join("\n")).digest("hex");
}

export function sameResultAcrossConsumers(subjects: readonly SubjectRef[], counts: readonly number[]): {
  buckets: number;
  hashes: string[];
  identical: boolean;
} {
  const buckets = bucketCountFor(subjects.length);
  const hashes: string[] = [];
  for (const count of counts) hashes.push(assignmentResultSha256(subjects, count));
  const first = hashes[0];
  let identical = typeof first === "string";
  for (const hash of hashes) {
    if (hash !== first) identical = false;
  }
  return { buckets, hashes, identical };
}
