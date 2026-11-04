import Decimal from "decimal.js";

/** Arithmetic matches reference/market_pricing_reference.py: 34 digits, half-up only where that file rounds. */
export const D = Decimal.clone({ precision: 34, rounding: Decimal.ROUND_HALF_UP });

export type Dec = InstanceType<typeof D>;

export const ZERO = new D(0);
export const ONE = new D(1);
export const HUNDRED = new D(100);
export const TWELVE = new D(12);

function digits(places: string): number {
  if (places === "1") return 0;
  if (places === "0.1") return 1;
  if (places === "0.01") return 2;
  if (places === "0.001") return 3;
  if (places === "0.0001") return 4;
  if (places === "0.000001") return 6;
  if (places === "0.0000000001") return 10;
  throw new Error(`unknown places ${places}`);
}

export function q(x: Dec, places: string): Dec {
  return x.toDecimalPlaces(digits(places), Decimal.ROUND_HALF_UP);
}

export function qstr(x: Dec, places: string): string {
  return q(x, places).toFixed(digits(places));
}

export function dec(v: unknown): Dec {
  return new D(String(v));
}

export function moneyStr(x: Dec): string {
  return qstr(x, "0.01");
}

/** Python str(Decimal) for a value that was not quantized to a fixed exponent. */
export function pyStr(x: Dec): string {
  return x.toString();
}

export function roundToUnit(x: Dec, unit: Dec): Dec {
  return q(x.div(unit), "1").mul(unit);
}
