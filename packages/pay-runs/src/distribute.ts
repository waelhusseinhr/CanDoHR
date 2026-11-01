import Decimal from "decimal.js";

Decimal.set({ precision: 28 });

export interface Weight {
  key: string;
  weight: string;
}

export interface Share {
  key: string;
  amount: string;
}

/** Split a money amount by weight. The shares add up to the total exactly (ENT-015). */
export function distributeLargestRemainder(total: string, weights: readonly Weight[]): Share[] {
  if (weights.length === 0) throw new Error("DISTRIBUTION_EMPTY");
  const cents = new Decimal(total).times(100);
  if (!cents.isInteger() || cents.isNegative()) throw new Error("DISTRIBUTION_AMOUNT");
  const sum = weights.reduce((acc, item) => acc.plus(item.weight), new Decimal(0));
  if (sum.lte(0)) throw new Error("DISTRIBUTION_WEIGHT");
  const raw = weights.map((item) => ({
    key: item.key,
    exact: cents.times(item.weight).div(sum),
  }));
  const floors = raw.map((item) => item.exact.floor());
  let left = cents.minus(floors.reduce((acc, item) => acc.plus(item), new Decimal(0)));
  const order = raw
    .map((item, index) => ({ index, fraction: item.exact.minus(item.exact.floor()), key: item.key }))
    .sort((a, b) => b.fraction.comparedTo(a.fraction) || a.key.localeCompare(b.key));
  const awarded = floors.map((item) => item);
  let cursor = 0;
  while (left.gt(0)) {
    const pick = order[cursor % order.length];
    if (!pick) break;
    awarded[pick.index] = awarded[pick.index]!.plus(1);
    left = left.minus(1);
    cursor += 1;
  }
  return weights.map((item, index) => ({
    key: item.key,
    amount: awarded[index]!.div(100).toFixed(2),
  }));
}
