import { fail } from "./errors.ts";

export function parseDate(iso: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!match) fail("DATE");
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) fail("DATE");
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

export function addMonths(iso: string, months: number): string {
  const date = parseDate(iso);
  const day = date.getUTCDate();
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() + months);
  const last = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
  date.setUTCDate(day > last ? last : day);
  return formatDate(date);
}

export function addYears(iso: string, years: number): string {
  const date = parseDate(iso);
  const month = date.getUTCMonth();
  const day = date.getUTCDate();
  const year = date.getUTCFullYear() + years;
  const last = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const clamped = day > last ? last : day;
  return formatDate(new Date(Date.UTC(year, month, clamped)));
}

/** `month` is 1-based. February is 2, so the UTC day 0 of the next month is the last day of February. */
export function lastDay(year: number, month: number): string {
  return formatDate(new Date(Date.UTC(year, month, 0)));
}

export function daysBetween(from: string, to: string): number {
  const start = parseDate(from).getTime();
  const end = parseDate(to).getTime();
  return Math.round((end - start) / (24 * 60 * 60 * 1000));
}
