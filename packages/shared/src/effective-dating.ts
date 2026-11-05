import { compareIsoDate, parseIsoDate, rangeContains } from "./dates.ts";
import { CanDoError } from "./errors.ts";

/** A business value on a version row. Money is a two-decimal string, never a JavaScript number. */
export type AttributeValue = string | boolean | null;
export type AttributeMap = Record<string, AttributeValue>;

/**
 * What to do with a future row that already set one of the same fields.
 * keep — leave the future row as it is.
 * replace — overwrite those fields on the future row.
 * merge — copy the new values only onto fields the future row did not set itself.
 */
export type ConflictResolution = "keep" | "replace" | "merge";

/**
 * One version of an entity. Valid time is a half-open calendar range.
 * System time is half-open too: the row is visible at `knownAt` when
 * `recordedAt <= knownAt` and (`supersededAt` is null or `knownAt < supersededAt`).
 */
export interface VersionRow {
  versionId: string;
  entityId: string;
  validStart: string;
  validEnd: string | null;
  recordedAt: string;
  supersededAt: string | null;
  changeSetId: string;
  attributes: AttributeMap;
  /** Fields this version itself set. Copied fields are not listed, so a later edit can tell a real conflict from a copy. */
  explicitKeys: readonly string[];
}

export interface WriteVersionInput {
  entityId: string;
  kind: "change" | "correction";
  effectiveDate: string;
  knownAt: string;
  changeSetId: string;
  patch: AttributeMap;
  /** Defaults to every key in `patch`. */
  explicitKeys?: readonly string[];
  /**
   * Defaults to `keep`. A change never overwrites a future row unless this says replace or merge (docs/03 §4).
   */
  conflictResolution?: ConflictResolution;
}

export interface VersionConflict {
  versionId: string;
  validStart: string;
  key: string;
  futureValue: AttributeValue;
  incomingValue: AttributeValue;
}

export interface WriteVersionResult {
  versions: VersionRow[];
  opened: VersionRow[];
  closedVersionIds: string[];
  conflicts: VersionConflict[];
}

/**
 * The row that was believed at `knownAt` to be true on `asOf`.
 * `versions` is the history of one entity. Returns null when nothing covers that day.
 */
export function readAsOf(
  versions: readonly VersionRow[],
  entityId: string,
  asOf: string,
  knownAt: string,
): VersionRow | null {
  const day = parseIsoDate(asOf);
  const at = timestampMs(knownAt);
  const matches = versions.filter((row) => {
    if (row.entityId !== entityId) return false;
    if (!rangeContains({ start: row.validStart, end: row.validEnd }, day)) return false;
    const recorded = timestampMs(row.recordedAt);
    const superseded = row.supersededAt === null ? null : timestampMs(row.supersededAt);
    return recorded <= at && (superseded === null || at < superseded);
  });
  if (matches.length > 1) {
    throw new CanDoError("MULTIPLE_VERSIONS");
  }
  return matches[0] ?? null;
}

/**
 * A change splits valid time at the effective date and copies fields it does not set.
 * It stops at the next future version. A correction replaces the covering row in system
 * time and keeps the same valid dates. Future rows that set the same field to a different
 * value are reported and are not changed unless `conflictResolution` says so.
 * A correction never rewrites other slices.
 */
export function writeVersion(versions: readonly VersionRow[], input: WriteVersionInput): WriteVersionResult {
  const patchKeys = Object.keys(input.patch);
  if (patchKeys.length === 0) {
    throw new CanDoError("PATCH_EMPTY");
  }
  const effectiveDate = parseIsoDate(input.effectiveDate);
  const knownAt = normalizeTimestamp(input.knownAt);
  const knownAtMs = timestampMs(knownAt);
  const explicitKeys = [...(input.explicitKeys ?? patchKeys)];
  for (const key of explicitKeys) {
    if (!Object.prototype.hasOwnProperty.call(input.patch, key)) {
      throw new CanDoError("EXPLICIT_KEY_NOT_IN_PATCH");
    }
  }
  // structural: in-memory merge strategy for tests, not platform.setting()
  const resolution = input.conflictResolution ?? "keep";
  if (resolution !== "keep" && resolution !== "replace" && resolution !== "merge") {
    throw new CanDoError("CONFLICT_RESOLUTION");
  }
  if (input.kind !== "change" && input.kind !== "correction") {
    throw new CanDoError("VERSION_KIND");
  }
  if (!input.changeSetId) {
    throw new CanDoError("CHANGE_SET_ID");
  }
  if (!input.entityId) {
    throw new CanDoError("ENTITY_ID");
  }

  const current = versions.filter((row) => row.entityId === input.entityId && row.supersededAt === null);
  const containing = current.find((row) => rangeContains({ start: row.validStart, end: row.validEnd }, effectiveDate));
  if (!containing) {
    throw new CanDoError("EFFECTIVE_DATE_NOT_COVERED");
  }
  assertKnownAfter(containing, knownAtMs);

  const future = current
    .filter((row) => compareIsoDate(row.validStart, effectiveDate) > 0)
    .sort((a, b) => compareIsoDate(a.validStart, b.validStart));

  const conflicts: VersionConflict[] = [];
  for (const row of future) {
    for (const key of explicitKeys) {
      if (!row.explicitKeys.includes(key)) continue;
      const futureValue = valueAt(row.attributes, key);
      const incomingValue = valueAt(input.patch, key);
      if (futureValue !== incomingValue) {
        conflicts.push({
          versionId: row.versionId,
          validStart: row.validStart,
          key,
          futureValue,
          incomingValue,
        });
      }
    }
  }

  const closed = new Set<string>();
  const opened: VersionRow[] = [];

  if (input.kind === "correction") {
    closed.add(containing.versionId);
    opened.push(openRow(input, containing.validStart, containing.validEnd, knownAt, applyPatch(containing.attributes, input.patch, explicitKeys), unique([...containing.explicitKeys, ...explicitKeys])));
  } else {
    closed.add(containing.versionId);
    if (compareIsoDate(containing.validStart, effectiveDate) < 0) {
      opened.push(
        openRow(input, containing.validStart, effectiveDate, knownAt, cloneAttributes(containing.attributes), [...containing.explicitKeys]),
      );
    }
    opened.push(
      openRow(
        input,
        effectiveDate,
        containing.validEnd,
        knownAt,
        applyPatch(containing.attributes, input.patch, explicitKeys),
        [...explicitKeys],
      ),
    );

    for (const row of future) {
      assertKnownAfter(row, knownAtMs);
      const keysToApply = explicitKeys.filter((key) => {
        if (valueAt(input.patch, key) === valueAt(row.attributes, key)) return false;
        if (resolution === "keep") return false;
        if (resolution === "replace") return true;
        return !row.explicitKeys.includes(key);
      });
      if (keysToApply.length === 0) continue;
      closed.add(row.versionId);
      const nextExplicit = resolution === "replace" ? unique([...row.explicitKeys, ...keysToApply]) : [...row.explicitKeys];
      opened.push(openRow(input, row.validStart, row.validEnd, knownAt, applyPatch(row.attributes, input.patch, keysToApply), nextExplicit));
    }
  }

  const nextVersions = versions.map((row) =>
    closed.has(row.versionId)
      ? {
          ...row,
          attributes: cloneAttributes(row.attributes),
          explicitKeys: [...row.explicitKeys],
          supersededAt: knownAt,
        }
      : row,
  );

  return {
    versions: [...nextVersions, ...opened],
    opened,
    closedVersionIds: [...closed],
    conflicts,
  };
}

function openRow(
  input: WriteVersionInput,
  validStart: string,
  validEnd: string | null,
  knownAt: string,
  attributes: AttributeMap,
  explicitKeys: readonly string[],
): VersionRow {
  return {
    versionId: crypto.randomUUID(),
    entityId: input.entityId,
    validStart,
    validEnd,
    recordedAt: knownAt,
    supersededAt: null,
    changeSetId: input.changeSetId,
    attributes,
    explicitKeys: [...explicitKeys],
  };
}

function applyPatch(base: AttributeMap, patch: AttributeMap, keys: readonly string[]): AttributeMap {
  const next = cloneAttributes(base);
  for (const key of keys) {
    next[key] = valueAt(patch, key);
  }
  return next;
}

function cloneAttributes(attributes: AttributeMap): AttributeMap {
  return { ...attributes };
}

function valueAt(attributes: AttributeMap, key: string): AttributeValue {
  if (!Object.prototype.hasOwnProperty.call(attributes, key)) return null;
  return attributes[key] ?? null;
}

function unique(keys: readonly string[]): string[] {
  return [...new Set(keys)];
}

function assertKnownAfter(row: VersionRow, knownAtMs: number): void {
  if (timestampMs(row.recordedAt) >= knownAtMs) {
    throw new CanDoError("KNOWN_AT_BEFORE_RECORD");
  }
}

function normalizeTimestamp(value: string): string {
  return new Date(timestampMs(value)).toISOString();
}

function timestampMs(value: string): number {
  if (typeof value !== "string") {
    throw new CanDoError("KNOWN_AT");
  }
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) {
    throw new CanDoError("KNOWN_AT");
  }
  return ms;
}
