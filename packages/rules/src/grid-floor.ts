import Decimal from "decimal.js";

export type GridFloorStep = {
  step: number;
  rate: string;
  margin: string;
  linkedJurisdiction: string;
  article?: string;
};

/**
 * When a new employment-standards edition lifts the minimum above a linked
 * grid step, propose the new rate on that edition's effective date.
 * The wage and the margin are passed in. They are not stored here.
 */
export function proposeGridFloor(input: {
  jurisdiction: string;
  nextWage: string;
  effectiveFrom: string;
  steps: GridFloorStep[];
}): { effectiveDate: string; changes: Array<{ step: number; from: string; to: string; article: string | null }> } {
  const changes = [];
  for (const step of input.steps) {
    if (step.linkedJurisdiction !== input.jurisdiction) continue;
    const floor = new Decimal(input.nextWage).plus(step.margin);
    if (floor.gt(step.rate)) {
      changes.push({
        step: step.step,
        from: new Decimal(step.rate).toDecimalPlaces(2, Decimal.ROUND_HALF_UP).toFixed(2),
        to: floor.toDecimalPlaces(2, Decimal.ROUND_HALF_UP).toFixed(2),
        article: step.article ?? null,
      });
    }
  }
  return { effectiveDate: input.effectiveFrom, changes };
}
