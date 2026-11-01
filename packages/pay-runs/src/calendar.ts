/** Pay dates move to the previous banking day (docs/24 §4.3, PAY-063). */

const WEEKEND = new Set([0, 6]);

function observed(month: number, day: number, year: number): string[] {
  const date = new Date(Date.UTC(year, month - 1, day));
  const weekday = date.getUTCDay();
  const iso = date.toISOString().slice(0, 10);
  if (weekday === 0) {
    const monday = new Date(date);
    monday.setUTCDate(date.getUTCDate() + 1);
    return [iso, monday.toISOString().slice(0, 10)];
  }
  if (weekday === 6) {
    const friday = new Date(date);
    friday.setUTCDate(date.getUTCDate() - 1);
    return [iso, friday.toISOString().slice(0, 10)];
  }
  return [iso];
}

function nthMonday(year: number, month: number, n: number): string {
  const first = new Date(Date.UTC(year, month - 1, 1));
  const offset = (8 - first.getUTCDay()) % 7;
  const day = 1 + offset + (n - 1) * 7;
  return new Date(Date.UTC(year, month - 1, day)).toISOString().slice(0, 10);
}

/** Federal bank holidays for the year, including the weekend day and the observed weekday. */
export function bankHolidays(year: number): Set<string> {
  const days = [
    ...observed(1, 1, year),
    ...observed(7, 1, year),
    ...observed(9, 30, year),
    ...observed(11, 11, year),
    ...observed(12, 25, year),
    ...observed(12, 26, year),
    mondayBeforeMay25(year),
    nthMonday(year, 9, 1),
    nthMonday(year, 10, 2),
  ];
  const goodFriday = goodFridayIso(year);
  return new Set([...days, goodFriday].filter((day) => day.length > 0));
}

function mondayBeforeMay25(year: number): string {
  const date = new Date(Date.UTC(year, 4, 24));
  const back = (date.getUTCDay() + 6) % 7;
  date.setUTCDate(24 - back);
  return date.toISOString().slice(0, 10);
}

function goodFridayIso(year: number): string {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  const easter = new Date(Date.UTC(year, month - 1, day));
  easter.setUTCDate(easter.getUTCDate() - 2);
  return easter.toISOString().slice(0, 10);
}

function shift(iso: string, days: number): string {
  const date = new Date(`${iso}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export function isBankingDay(iso: string, holidays: Set<string>): boolean {
  const date = new Date(`${iso}T00:00:00Z`);
  return !WEEKEND.has(date.getUTCDay()) && !holidays.has(iso);
}

export interface PayDatePlan {
  requested: string;
  payDate: string;
  moved: boolean;
  crossesPriorYear: boolean;
}

/** Walk back to the previous banking day. A move into the prior year is flagged before the calendar is approved. */
export function planPayDate(requested: string): PayDatePlan {
  const year = Number(requested.slice(0, 4));
  const holidays = new Set<string>([...bankHolidays(year), ...bankHolidays(year - 1), ...bankHolidays(year + 1)]);
  let payDate = requested;
  while (!isBankingDay(payDate, holidays)) payDate = shift(payDate, -1);
  return {
    requested,
    payDate,
    moved: payDate !== requested,
    crossesPriorYear: Number(payDate.slice(0, 4)) < year,
  };
}
