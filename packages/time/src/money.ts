import Decimal from "decimal.js";

export class TimeError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = "TimeError";
    this.code = code;
  }
}

export function hours(value: string): string {
  if (typeof value !== "string" || value.trim() === "") throw new TimeError("HOURS");
  return new Decimal(value).toDecimalPlaces(2).toFixed(2);
}

export function money(value: string): string {
  if (typeof value !== "string" || value.trim() === "") throw new TimeError("MONEY");
  return new Decimal(value).toDecimalPlaces(2).toFixed(2);
}

export function add(left: string, right: string): string {
  return new Decimal(left).plus(right).toDecimalPlaces(2).toFixed(2);
}

export function sub(left: string, right: string): string {
  return new Decimal(left).minus(right).toDecimalPlaces(2).toFixed(2);
}

export function mul(left: string, right: string): string {
  return new Decimal(left).times(right).toDecimalPlaces(2).toFixed(2);
}

export function div(left: string, right: string): string {
  return new Decimal(left).div(right).toDecimalPlaces(2).toFixed(2);
}

export function cmp(left: string, right: string): number {
  return new Decimal(left).comparedTo(right);
}

export function sum(values: string[]): string {
  return values.reduce((total, value) => add(total, value), "0.00");
}

export function max(left: string, right: string): string {
  return cmp(left, right) >= 0 ? left : right;
}
