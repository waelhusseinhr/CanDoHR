import { fail } from "./errors.ts";
import { D, fixed } from "./decimal.ts";

export type HeadcountRow = {
  id: string;
  kind: "person" | "vacancy";
  fte: string;
  from: string;
  to: string | null;
};

export type TurnoverInput = {
  formula: string;
  leavers: string;
  averageHeadcount: string;
};

function covers(row: HeadcountRow, asOf: string): boolean {
  if (row.from > asOf) return false;
  if (row.to !== null && row.to < asOf) return false;
  return true;
}

/** Headcount, FTE, vacancies and turnover from effective-dated rows. Turnover uses the definition's formula. */
export function metricAsOf(input: { asOf: string; rows: readonly HeadcountRow[]; turnover: TurnoverInput | null }): {
  headcount: number;
  fte: string;
  vacancies: number;
  turnover: string | null;
} {
  let headcount = 0;
  let vacancies = 0;
  let fte = new D(0);
  for (const row of input.rows) {
    if (!covers(row, input.asOf)) continue;
    if (row.kind === "vacancy") {
      vacancies += 1;
      continue;
    }
    headcount += 1;
    fte = fte.plus(row.fte);
  }
  return {
    headcount,
    fte: fixed(fte, 2),
    vacancies,
    turnover: input.turnover === null ? null : turnoverRate(input.turnover),
  };
}

function turnoverRate(turnover: TurnoverInput): string {
  if (turnover.formula !== "leavers/average") fail("INPUT_REQUIRED", turnover.formula);
  const average = new D(turnover.averageHeadcount);
  if (average.isZero()) fail("INPUT_REQUIRED");
  return fixed(new D(turnover.leavers).div(average), 2);
}

export type MetricDefinition = {
  code: string;
  version: number;
  formula: string;
  inclusions: string;
  exclusions: string;
};

/** A change of formula, inclusions or exclusions is a new version. The previous version stays. */
export function publishDefinition(
  history: readonly MetricDefinition[],
  next: { code: string; formula: string; inclusions: string; exclusions: string },
): MetricDefinition[] {
  const same = history.filter((item) => item.code === next.code);
  let version = 1;
  let current: MetricDefinition | null = null;
  for (const item of same) {
    if (current === null || item.version > current.version) current = item;
  }
  if (current !== null) {
    version = current.version + 1;
    if (current.formula === next.formula && current.inclusions === next.inclusions && current.exclusions === next.exclusions) {
      return history.slice();
    }
  }
  return [...history, { ...next, version }];
}

export function currentDefinition(history: readonly MetricDefinition[], code: string): MetricDefinition {
  let found: MetricDefinition | null = null;
  for (const item of history) {
    if (item.code === code && (found === null || item.version > found.version)) found = item;
  }
  if (found === null) fail("INPUT_REQUIRED");
  return found;
}
