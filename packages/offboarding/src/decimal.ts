import Decimal from "decimal.js";

/** 28-digit decimal, matching Python Decimal for the benefit and severance figures. */
export const D = Decimal.clone({ precision: 28, rounding: Decimal.ROUND_HALF_UP });

export type Dec = InstanceType<typeof D>;

export function dec(value: string): Dec {
  return new D(value);
}

export function money(value: string): string {
  return new D(value).toDecimalPlaces(2, Decimal.ROUND_HALF_UP).toFixed(2);
}

/** Python str(Decimal) for an FTE that was not forced to two places. */
export function pyStr(value: Dec): string {
  return value.toString();
}
