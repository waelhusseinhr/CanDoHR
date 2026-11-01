import Decimal from "decimal.js";

function plain(value: Decimal): string {
  return value.toSignificantDigits(28).toFixed();
}

/**
 * Points accrual from an agreement rule. The points, the hours, and the cap
 * are the agreement's numbers, not constants in this function.
 */
export function accrueSeniorityPoints(input: {
  hours: string;
  points: string;
  perHours: string;
  annualCap: string;
  already?: string;
}): { earned: string; total: string; capped: boolean } {
  const earned = new Decimal(input.hours).div(input.perHours).mul(input.points);
  const cap = new Decimal(input.annualCap);
  const raw = new Decimal(input.already ?? "0").plus(earned);
  const capped = raw.gt(cap);
  return { earned: plain(earned), total: plain(capped ? cap : raw), capped };
}
