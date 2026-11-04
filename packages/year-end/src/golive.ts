import { add, money, sub } from "@candohr/disbursement";
import { YearEndError } from "./errors.ts";

export type OpeningKind = "ytd" | "period_history" | "balance" | "opening_liability" | "funding_spent";

export type OpeningLine = {
  kind: OpeningKind;
  personId: string;
  payrollAccountId: string;
  code: string;
  amount: string;
  sourceTotal: string;
};

export type ReconciliationLine = {
  kind: OpeningKind;
  personId: string;
  payrollAccountId: string;
  code: string;
  imported: string;
  sourceTotal: string;
  difference: string;
  status: "reconciled" | "difference";
};

export function coveredDays(workDays: readonly string[], cutover: string): { excludedDays: string[]; payableDays: string[] } {
  const excludedDays: string[] = [];
  const payableDays: string[] = [];
  for (const day of [...workDays].sort()) {
    if (day < cutover) excludedDays.push(day);
    else payableDays.push(day);
  }
  return { excludedDays, payableDays };
}

/** Loads opening amounts through one change set with source import, after each line matches the legacy total to the cent. */
export function importGoLive(input: { cutover: string; workDays: readonly string[]; lines: readonly OpeningLine[] }): {
  excludedDays: string[];
  payableDays: string[];
  reconciliation: ReconciliationLine[];
  changeSet: { source: "import"; lines: { kind: OpeningKind; personId: string; payrollAccountId: string; code: string; amount: string }[] } | null;
} {
  if (input.lines.length === 0) throw new YearEndError("INPUT_REQUIRED");
  const days = coveredDays(input.workDays, input.cutover);
  const reconciliation = input.lines.map((line) => {
    const imported = money(line.amount);
    const sourceTotal = money(line.sourceTotal);
    const difference = sub(imported, sourceTotal);
    return {
      kind: line.kind,
      personId: line.personId,
      payrollAccountId: line.payrollAccountId,
      code: line.code,
      imported,
      sourceTotal,
      difference,
      status: difference === "0.00" ? ("reconciled" as const) : ("difference" as const),
    };
  });
  if (reconciliation.some((line) => line.status === "difference")) {
    return { ...days, reconciliation, changeSet: null };
  }
  return {
    ...days,
    reconciliation,
    changeSet: {
      source: "import",
      lines: reconciliation.map((line) => ({
        kind: line.kind,
        personId: line.personId,
        payrollAccountId: line.payrollAccountId,
        code: line.code,
        amount: line.imported,
      })),
    },
  };
}

export function reconciledTotal(lines: readonly { amount: string }[]): string {
  return lines.reduce((total, line) => add(total, line.amount), "0.00");
}
