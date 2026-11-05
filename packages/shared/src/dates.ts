import { CanDoError } from "./errors.ts";

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

/**
 * A valid-time range. `start` is included. `end` is excluded.
 * `end === null` means the range is still open.
 */
export interface DateRange {
  start: string;
  end: string | null;
}

/** Returns the same `YYYY-MM-DD` string, or throws ISO_DATE when it is not a real calendar day. */
export function parseIsoDate(value: string): string {
  if (typeof value !== "string") {
    throw new CanDoError("ISO_DATE");
  }
  const match = ISO_DATE.exec(value);
  if (!match) {
    throw new CanDoError("ISO_DATE");
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const utc = new Date(Date.UTC(year, month - 1, day));
  if (utc.getUTCFullYear() !== year || utc.getUTCMonth() !== month - 1 || utc.getUTCDate() !== day) {
    throw new CanDoError("ISO_DATE");
  }
  return value;
}

/** Adds calendar days. Uses UTC so a daylight-saving change cannot skip or repeat a date. */
export function addDays(isoDate: string, days: number): string {
  if (!Number.isInteger(days)) {
    throw new CanDoError("ISO_DATE");
  }
  const parsed = parseIsoDate(isoDate);
  const [year, month, day] = parsed.split("-").map(Number);
  // structural: missing numeric coalesces to zero for arithmetic
  const utc = new Date(Date.UTC(year ?? 0, (month ?? 1) - 1, (day ?? 1) + days));
  const y = utc.getUTCFullYear().toString().padStart(4, "0");
  const m = (utc.getUTCMonth() + 1).toString().padStart(2, "0");
  const d = utc.getUTCDate().toString().padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/** Negative when `a` is before `b`, zero when they are the same day, positive when `a` is after `b`. */
export function compareIsoDate(a: string, b: string): number {
  const left = parseIsoDate(a);
  const right = parseIsoDate(b);
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

/**
 * The calendar date of an instant in a legal entity's time zone (docs/03 §1).
 * `timeZone` is an IANA name such as "America/Toronto".
 */
export function isoDateInTimeZone(instant: Date | string, timeZone: string): string {
  const date = typeof instant === "string" ? new Date(instant) : instant;
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
    throw new CanDoError("ISO_DATE");
  }
  if (typeof timeZone !== "string" || timeZone.length === 0) {
    throw new CanDoError("TIME_ZONE_UNKNOWN");
  }
  let formatter: Intl.DateTimeFormat;
  try {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  } catch (error) {
    if (error instanceof RangeError) {
      throw new CanDoError("TIME_ZONE_UNKNOWN");
    }
    throw error;
  }
  const resolved = formatter.resolvedOptions().timeZone;
  if (resolved !== timeZone && !sameTimeZone(resolved, timeZone)) {
    throw new CanDoError("TIME_ZONE_UNKNOWN");
  }
  const parts = formatter.formatToParts(date);
  const year = parts.find((part) => part.type === "year")?.value;
  const month = parts.find((part) => part.type === "month")?.value;
  const day = parts.find((part) => part.type === "day")?.value;
  if (!year || !month || !day) {
    throw new CanDoError("TIME_ZONE_UNKNOWN");
  }
  return parseIsoDate(`${year}-${month}-${day}`);
}

function sameTimeZone(resolved: string, requested: string): boolean {
  try {
    const sample = new Date("2026-07-01T12:00:00.000Z");
    const left = new Intl.DateTimeFormat("en-US", { timeZone: resolved, timeZoneName: "longOffset" }).format(sample);
    const right = new Intl.DateTimeFormat("en-US", { timeZone: requested, timeZoneName: "longOffset" }).format(sample);
    return left === right;
  } catch {
    return false;
  }
}

/** True when `day` is inside the half-open range. */
export function rangeContains(range: DateRange, day: string): boolean {
  const date = parseIsoDate(day);
  if (compareIsoDate(range.start, date) > 0) return false;
  if (range.end === null) return true;
  return compareIsoDate(date, range.end) < 0;
}

/** True when the two half-open ranges share a day. Touching at an endpoint does not count. */
export function rangesOverlap(a: DateRange, b: DateRange): boolean {
  const aReachesB = a.end === null || compareIsoDate(b.start, a.end) < 0;
  const bReachesA = b.end === null || compareIsoDate(a.start, b.end) < 0;
  return aReachesB && bReachesA;
}
