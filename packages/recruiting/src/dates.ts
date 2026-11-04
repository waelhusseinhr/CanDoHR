import { addDays } from "@candohr/disbursement";
import { RecruitError } from "./errors.ts";

export function addMonths(iso: string, months: number): string {
  const [year, month, day] = iso.split("-").map(Number);
  if (!year || !month || !day) throw new RecruitError("DATE");
  const index = year * 12 + (month - 1) + months;
  const nextYear = Math.floor(index / 12);
  const nextMonth = index - nextYear * 12;
  const last = new Date(Date.UTC(nextYear, nextMonth + 1, 0)).getUTCDate();
  return new Date(Date.UTC(nextYear, nextMonth, Math.min(day, last))).toISOString().slice(0, 10);
}

export function daysBetween(earlier: string, later: string): number {
  const start = Date.parse(`${earlier}T00:00:00Z`);
  const end = Date.parse(`${later}T00:00:00Z`);
  if (Number.isNaN(start) || Number.isNaN(end)) throw new RecruitError("DATE");
  return Math.round((end - start) / 86_400_000);
}

export function shiftDays(iso: string, days: number): string {
  return addDays(iso, days);
}
