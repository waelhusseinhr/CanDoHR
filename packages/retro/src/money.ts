import Decimal from "decimal.js";

/** Money is a decimal string. A JavaScript number is rejected. */
export function cents(value: string): string {
  if (typeof value !== "string" || value.trim() === "" || Number.isNaN(Number(value))) {
    throw new RetroError("MONEY");
  }
  return new Decimal(value).toDecimalPlaces(2).toFixed(2);
}

export function add(left: string, right: string): string {
  return new Decimal(cents(left)).plus(cents(right)).toDecimalPlaces(2).toFixed(2);
}

export function sub(left: string, right: string): string {
  return new Decimal(cents(left)).minus(cents(right)).toDecimalPlaces(2).toFixed(2);
}

export function isZero(value: string): boolean {
  return new Decimal(cents(value)).isZero();
}

export function isNegative(value: string): boolean {
  return new Decimal(cents(value)).isNegative();
}

export function compare(left: string, right: string): number {
  return new Decimal(cents(left)).comparedTo(cents(right));
}

export class RetroError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = "RetroError";
    this.code = code;
  }
}
