import { CanDoError } from "@candohr/shared";

const OWN_DOCUMENTS = new Set(["pay_statement", "tax_slip", "roe"]);

function pad(value: number): string {
  return String(value).padStart(2, "0");
}

function isoDate(year: number, month: number, day: number): string {
  return `${year}-${pad(month)}-${pad(day)}`;
}

function lastDayOfMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** Adds calendar months the way Postgres does: a short month clamps the day. */
export function addMonths(iso: string, months: number): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!match) throw new CanDoError("ISO_DATE");
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const index = year * 12 + (month - 1) + months;
  const nextYear = Math.floor(index / 12);
  const nextMonth = (index % 12) + 1;
  const nextDay = Math.min(day, lastDayOfMonth(nextYear, nextMonth));
  return isoDate(nextYear, nextMonth, nextDay);
}

/**
 * T4 due date for the year of the last day (last day of the following February)
 * plus the organization's months. 15 November 2026 with 12 months is 28 February 2028.
 * Matches payroll.former_employee_access_until.
 */
export function formerEmployeeUntil(lastDay: string, monthsAfterNextT4: number): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(lastDay);
  if (!match || !Number.isInteger(monthsAfterNextT4) || monthsAfterNextT4 < 0) throw new CanDoError("ISO_DATE");
  const year = Number(match[1]);
  const february = lastDayOfMonth(year + 1, 2);
  const t4Due = isoDate(year + 1, 2, february);
  return addMonths(t4Due, monthsAfterNextT4);
}

export type FormerAccess = "full" | "own_documents" | "denied";

/** Until former_employee_until, the person sees only their own pay statements, slips and ROE. */
export function formerEmployeeAccess(input: {
  formerEmployeeUntil: string | null;
  today: string;
  documentKind: string | null;
  ownRecord: boolean;
}): FormerAccess {
  if (input.formerEmployeeUntil === null) return "full";
  if (input.today > input.formerEmployeeUntil) return "denied";
  if (!input.ownRecord) return "denied";
  if (input.documentKind !== null && OWN_DOCUMENTS.has(input.documentKind)) return "own_documents";
  return "denied";
}
