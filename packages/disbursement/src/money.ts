import Decimal from "decimal.js";

export class DisbursementError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = "DisbursementError";
    this.code = code;
  }
}

export function money(value: string): string {
  if (typeof value !== "string" || value.trim() === "" || Number.isNaN(Number(value))) {
    throw new DisbursementError("MONEY");
  }
  return new Decimal(value).toDecimalPlaces(2).toFixed(2);
}

export function add(left: string, right: string): string {
  return new Decimal(money(left)).plus(money(right)).toDecimalPlaces(2).toFixed(2);
}

export function sub(left: string, right: string): string {
  return new Decimal(money(left)).minus(money(right)).toDecimalPlaces(2).toFixed(2);
}

export function mul(left: string, right: string): string {
  return new Decimal(left).times(right).toDecimalPlaces(2).toFixed(2);
}

export function cmp(left: string, right: string): number {
  return new Decimal(left).comparedTo(right);
}

export function sum(values: string[]): string {
  return values.reduce((total, value) => add(total, value), "0.00");
}

export function allocateByShare(total: string, parts: { id: string; weight: string }[]): { id: string; amount: string }[] {
  const weightSum = parts.reduce((totalWeight, part) => totalWeight.plus(part.weight), new Decimal(0));
  if (weightSum.isZero()) throw new DisbursementError("INPUT_REQUIRED");
  const totalCents = new Decimal(money(total)).times(100);
  const raw = parts.map((part, index) => {
    const exact = totalCents.times(part.weight).div(weightSum);
    const floor = exact.floor();
    return { id: part.id, index, floor, frac: exact.minus(floor) };
  });
  let remainder = totalCents.minus(raw.reduce((totalFloor, part) => totalFloor.plus(part.floor), new Decimal(0)));
  const order = [...raw].sort((left, right) => right.frac.comparedTo(left.frac) || left.index - right.index);
  const extra = new Map<string, Decimal>();
  for (const part of order) {
    if (remainder.lte(0)) break;
    extra.set(part.id, new Decimal(1));
    remainder = remainder.minus(1);
  }
  return raw.map((part) => ({
    id: part.id,
    // structural: missing numeric coalesces to zero for arithmetic
    amount: part.floor.plus(extra.get(part.id) ?? 0).div(100).toFixed(2),
  }));
}

export function addDays(iso: string, days: number): string {
  const date = new Date(`${iso}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) throw new DisbursementError("DATE");
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export function eachDate(start: string, end: string): string[] {
  const dates: string[] = [];
  let cursor = start;
  while (cursor <= end) {
    dates.push(cursor);
    cursor = addDays(cursor, 1);
  }
  return dates;
}
