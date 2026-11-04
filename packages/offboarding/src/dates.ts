import { fail } from "./errors.ts";

export function parseDate(iso: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!match) fail("DATE");
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    fail("DATE");
  }
  return date;
}

export function formatDate(date: Date): string {
  const year = String(date.getUTCFullYear());
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function addDays(iso: string, days: number): string {
  const date = parseDate(iso);
  date.setUTCDate(date.getUTCDate() + days);
  return formatDate(date);
}

/** Same as Python datetime.timedelta(weeks=n): n times 7 days. */
export function addWeeks(iso: string, weeks: number): string {
  return addDays(iso, weeks * 7);
}

/** Hours added to midnight UTC on the date. 48 hours after 15 March is 17 March. */
export function addHours(iso: string, hours: number): string {
  const date = parseDate(iso);
  date.setUTCHours(date.getUTCHours() + hours);
  return formatDate(date);
}

/** Python _last_of_month: day 28, plus 4 days, back to the last day of the month. */
export function lastOfMonth(iso: string): string {
  const date = parseDate(iso);
  const day28 = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 28));
  const shifted = new Date(day28.getTime() + 4 * 24 * 60 * 60 * 1000);
  const firstNext = new Date(Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), 1));
  const last = new Date(firstNext.getTime() - 24 * 60 * 60 * 1000);
  return formatDate(last);
}
