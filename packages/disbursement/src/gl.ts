import Decimal from "decimal.js";
import { addDays, allocateByShare, cmp, DisbursementError, eachDate, money, mul, sub, sum } from "./money.ts";

export type PeriodStatus = "open" | "closed";

export type FiscalPeriod = {
  id: string;
  fiscalYear: string;
  number: number;
  start: string;
  end: string;
  status: PeriodStatus;
};

export type MappingVersion = { version: string; effectiveFrom: string };

export type JournalLine = {
  journalDate: string;
  account: string;
  description: string;
  amount: string;
  workPeriod: string;
  postingPeriod: string;
  mappingVersion: string;
  fiscalYear: string;
};

export type JournalSystem = "xero" | "quickbooks" | "sage" | "dynamics" | "netsuite" | "generic";

export type FunderPeriod = { id: string; start: string; end: string; status: PeriodStatus };

const HEADERS: Record<JournalSystem, readonly string[]> = {
  xero: ["JournalDate", "AccountCode", "Description", "NetAmount", "WorkPeriod", "PostingPeriod", "MappingVersion"],
  quickbooks: ["Date", "Account", "Memo", "Amount", "WorkPeriod", "PostingPeriod", "MappingVersion"],
  sage: ["JournalDate", "AccountNumber", "Reference", "Amount", "WorkPeriod", "PostingPeriod", "MappingVersion"],
  dynamics: ["PostingDate", "Account", "Description", "Amount", "WorkPeriod", "PostingPeriod", "MappingVersion"],
  netsuite: ["TranDate", "Account", "Memo", "Amount", "WorkPeriod", "PostingPeriod", "MappingVersion"],
  generic: ["date", "account", "description", "amount", "work_period", "posting_period", "mapping_version"],
};

function closed(id: string, list: readonly string[]): boolean {
  return list.includes("*") || list.includes(id);
}

export function fiscalPeriod(date: string, yearEndMonth: number, closedPeriods: readonly string[] = []): FiscalPeriod {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (!match || yearEndMonth < 1 || yearEndMonth > 12) throw new DisbursementError("DATE");
  const year = Number(match[1]);
  const month = Number(match[2]);
  const endYear = month > yearEndMonth ? year + 1 : year;
  const number = month > yearEndMonth ? month - yearEndMonth : month + (12 - yearEndMonth);
  const id = `FY${endYear}-P${String(number).padStart(2, "0")}`;
  const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return {
    id,
    fiscalYear: `FY${endYear}`,
    number,
    start: `${date.slice(0, 8)}01`,
    end: `${date.slice(0, 8)}${String(last).padStart(2, "0")}`,
    status: closed(id, closedPeriods) ? "closed" : "open",
  };
}

export function postingPeriod(work: FiscalPeriod, yearEndMonth: number, closedPeriods: readonly string[]): FiscalPeriod {
  if (work.status === "open") return work;
  let cursor = addDays(work.end, 1);
  // structural: loop index or iteration bound, not a business default
  for (let step = 0; step < 36; step += 1) {
    const period = fiscalPeriod(cursor, yearEndMonth, closedPeriods);
    if (period.status === "open") return period;
    cursor = addDays(period.end, 1);
  }
  throw new DisbursementError("PERIOD_CLOSED");
}

export function mappingInForce(versions: readonly MappingVersion[], workDate: string): string {
  const chosen = versions
    .filter((version) => version.effectiveFrom <= workDate)
    .sort((left, right) => left.effectiveFrom.localeCompare(right.effectiveFrom))
    .at(-1);
  if (!chosen) throw new DisbursementError("MAPPING");
  return chosen.version;
}

export function funderPeriodOn(periods: readonly FunderPeriod[], date: string): FunderPeriod {
  const found = periods.find((period) => period.start <= date && date <= period.end);
  if (!found) throw new DisbursementError("PERIOD");
  return found;
}

export function postLine(input: {
  workDate: string;
  amount: string;
  account: string;
  description: string;
  yearEndMonth: number;
  closed?: readonly string[];
  mappingVersions: readonly MappingVersion[];
}): JournalLine {
  if (input.description.includes(",")) throw new DisbursementError("FIELD");
  const closedPeriods = input.closed ?? [];
  const work = fiscalPeriod(input.workDate, input.yearEndMonth, closedPeriods);
  const posting = postingPeriod(work, input.yearEndMonth, closedPeriods);
  return {
    journalDate: input.workDate,
    account: input.account,
    description: input.description,
    amount: money(input.amount),
    workPeriod: work.id,
    postingPeriod: posting.id,
    mappingVersion: mappingInForce(input.mappingVersions, input.workDate),
    fiscalYear: work.fiscalYear,
  };
}

export function journalForRun(input: {
  start: string;
  end: string;
  amount: string;
  account: string;
  description: string;
  yearEndMonth: number;
  closed?: readonly string[];
  mappingVersions: readonly MappingVersion[];
}): { lines: JournalLine[]; controlTotal: string; budgets: { fiscalYear: string; amount: string }[] } {
  const dates = eachDate(input.start, input.end);
  const shares = allocateByShare(
    input.amount,
    dates.map((date) => ({ id: date, weight: "1" })),
  );
  const groups = new Map<string, { first: string; amounts: string[]; sample: string }>();
  for (const share of shares) {
    const period = fiscalPeriod(share.id, input.yearEndMonth, input.closed ?? []);
    // structural: nullish coalescing for optional input in tests or adapters
    const group = groups.get(period.id) ?? { first: share.id, amounts: [], sample: share.id };
    group.amounts.push(share.amount);
    groups.set(period.id, group);
  }
  const lines = [...groups.values()].map((group) =>
    postLine({
      workDate: group.first,
      amount: sum(group.amounts),
      account: input.account,
      description: input.description,
      yearEndMonth: input.yearEndMonth,
      closed: input.closed,
      mappingVersions: input.mappingVersions,
    }),
  );
  const controlTotal = sum(lines.map((line) => line.amount));
  if (controlTotal !== money(input.amount)) throw new DisbursementError("CONTROL_TOTAL_MISMATCH");
  const budgets = new Map<string, string[]>();
  for (const line of lines) {
    budgets.set(line.fiscalYear, [...(budgets.get(line.fiscalYear) ?? []), line.amount]);
  }
  return {
    lines,
    controlTotal,
    budgets: [...budgets.entries()].map(([fiscalYear, amounts]) => ({ fiscalYear, amount: sum(amounts) })),
  };
}

export function exportJournal(system: JournalSystem, lines: readonly JournalLine[]): { csv: string; controlTotal: string } {
  const rows = lines.map((line) => {
    if (line.description.includes(",")) throw new DisbursementError("FIELD");
    return [line.journalDate, line.account, line.description, line.amount, line.workPeriod, line.postingPeriod, line.mappingVersion].join(",");
  });
  return {
    csv: `${HEADERS[system].join(",")}\n${rows.join("\n")}${rows.length ? "\n" : ""}`,
    controlTotal: sum(lines.map((line) => line.amount)),
  };
}

/** Pure period-end accrual. This does not start a Cloudflare Workflow. */
export function periodEndAccrual(input: {
  periodEnd: string;
  nextPeriodStart: string;
  unpaidDays: number;
  dailyAmount: string;
  expenseAccount: string;
  liabilityAccount: string;
  workPeriod: string;
  accrualPostingPeriod: string;
  reversalPostingPeriod: string;
  mappingVersion: string;
  previousLiability: string;
  currentLiability: string;
}): {
  accrual: JournalLine;
  reversal: JournalLine & { on: string };
  revaluation: { change: string; line: JournalLine | null };
} {
  const amount = mul(money(input.dailyAmount), String(input.unpaidDays));
  const fiscalYear = input.workPeriod.slice(0, 6);
  const accrual: JournalLine = {
    journalDate: input.periodEnd,
    account: input.expenseAccount,
    description: "Period-end accrual",
    amount,
    workPeriod: input.workPeriod,
    postingPeriod: input.accrualPostingPeriod,
    mappingVersion: input.mappingVersion,
    fiscalYear,
  };
  const reversal: JournalLine & { on: string } = {
    ...accrual,
    journalDate: input.nextPeriodStart,
    on: input.nextPeriodStart,
    postingPeriod: input.reversalPostingPeriod,
    amount: sub("0.00", amount),
    description: "Accrual reversal",
  };
  const change = sub(money(input.currentLiability), money(input.previousLiability));
  const line =
    change === "0.00"
      ? null
      : {
          journalDate: input.periodEnd,
          account: input.liabilityAccount,
          description: "Liability revaluation",
          amount: change,
          workPeriod: input.workPeriod,
          postingPeriod: input.accrualPostingPeriod,
          mappingVersion: input.mappingVersion,
          fiscalYear,
        };
  return { accrual, reversal, revaluation: { change, line } };
}

export function accrualTrueUp(paid: string, accrued: string): string {
  return sub(money(paid), money(accrued));
}

export type RecoveryLine = {
  entity: string;
  side: "debit" | "credit";
  amount: string;
  account: string;
  workPeriod: string;
  postingPeriod: string;
  mappingVersion: string;
};

export function intercompanyRecovery(input: {
  basis: "cost" | "cost_plus" | "fixed";
  cost: string;
  markupRate?: string;
  fixedFee?: string;
  payingEntity: string;
  receivingEntity: string;
  account: string;
  workPeriod: string;
  postingPeriod: string;
  mappingVersion: string;
}): { amount: string; lines: RecoveryLine[] } {
  let amount: string;
  if (input.basis === "cost") amount = money(input.cost);
  else if (input.basis === "cost_plus") {
    if (typeof input.markupRate !== "string" || input.markupRate.trim() === "") throw new DisbursementError("INPUT_REQUIRED");
    amount = new Decimal(money(input.cost)).times(new Decimal(input.markupRate).plus(1)).toDecimalPlaces(2).toFixed(2);
  } else if (input.fixedFee === undefined) throw new DisbursementError("INPUT_REQUIRED");
  else amount = money(input.fixedFee);
  if (cmp(amount, "0.00") < 0) throw new DisbursementError("AMOUNT");
  const shared = {
    account: input.account,
    workPeriod: input.workPeriod,
    postingPeriod: input.postingPeriod,
    mappingVersion: input.mappingVersion,
    amount,
  };
  return {
    amount,
    lines: [
      { ...shared, entity: input.receivingEntity, side: "debit" },
      { ...shared, entity: input.payingEntity, side: "credit" },
    ],
  };
}
