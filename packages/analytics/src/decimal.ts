import Decimal from "decimal.js";

export const D = Decimal.clone({ precision: 28, rounding: Decimal.ROUND_HALF_UP });

export function money(value: string): string {
  return new D(value).toDecimalPlaces(2, D.ROUND_HALF_UP).toFixed(2);
}

export function fixed(value: InstanceType<typeof D>, places: number): string {
  return value.toDecimalPlaces(places, D.ROUND_HALF_UP).toFixed(places);
}
