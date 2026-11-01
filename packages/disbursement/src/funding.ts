import { addDays, allocateByShare, cmp, DisbursementError, money, sub } from "./money.ts";

export type Coding = { sourceId?: string; account?: string } | null | undefined;
export type CapBehaviour = "hard_stop" | "spill_fallback" | "spill_next_line" | "warn_only";

export type FundingSource = {
  id: string;
  endsOn: string;
  remainingCap: string;
  capBehaviour: CapBehaviour;
  eligibleCategories: readonly string[];
  allowsBurden: boolean;
  fallbackId: string;
  nextId?: string;
};

export type FundLine = { id: string; amount: string };

export function resolveCoding(input: {
  explicit?: Coding;
  assignment?: Coding;
  position?: Coding;
  orgUnit?: Coding;
  suspenseAccount: string;
}): {
  from: "explicit" | "assignment" | "position" | "org_unit" | "suspense";
  sourceId?: string;
  account: string;
  financeTask: boolean;
  payDelayed: false;
} {
  const order = [
    ["explicit", input.explicit],
    ["assignment", input.assignment],
    ["position", input.position],
    ["org_unit", input.orgUnit],
  ] as const;
  for (const [from, coding] of order) {
    if (coding && (coding.sourceId || coding.account)) {
      return {
        from,
        sourceId: coding.sourceId,
        account: coding.account ?? input.suspenseAccount,
        financeTask: false,
        payDelayed: false,
      };
    }
  }
  return { from: "suspense", account: input.suspenseAccount, financeTask: true, payDelayed: false };
}

export function fundEarnings(input: {
  amount: string;
  workDate: string;
  category: string;
  source: FundingSource;
}): { lines: FundLine[]; warning: string | null } {
  const amount = money(input.amount);
  const ended = input.workDate > input.source.endsOn;
  const eligible = input.source.eligibleCategories.includes(input.category);
  if (ended || !eligible) return { lines: [{ id: input.source.fallbackId, amount }], warning: null };
  const cap = money(input.source.remainingCap);
  if (cmp(amount, cap) <= 0) return { lines: [{ id: input.source.id, amount }], warning: null };
  if (input.source.capBehaviour === "hard_stop") throw new DisbursementError("FUNDING_CAP");
  if (input.source.capBehaviour === "warn_only") {
    return { lines: [{ id: input.source.id, amount }], warning: "CAP" };
  }
  const excessId = input.source.capBehaviour === "spill_next_line" && input.source.nextId ? input.source.nextId : input.source.fallbackId;
  const lines: FundLine[] = [];
  if (cmp(cap, "0.00") > 0) lines.push({ id: input.source.id, amount: cap });
  const excess = sub(amount, cap);
  if (cmp(excess, "0.00") > 0) lines.push({ id: excessId, amount: excess });
  return { lines, warning: null };
}

export function fundBurden(input: {
  burden: string;
  earnings: readonly FundLine[];
  allowsBurden: boolean;
  fallbackId: string;
}): FundLine[] {
  const burden = money(input.burden);
  if (!input.allowsBurden) return [{ id: input.fallbackId, amount: burden }];
  return allocateByShare(
    burden,
    input.earnings.map((line) => ({ id: line.id, weight: line.amount })),
  ).filter((line) => cmp(line.amount, "0.00") > 0);
}

export function fundingEndAlerts(endsOn: string, daysBefore: readonly number[]): { on: string; daysBefore: number }[] {
  return [...daysBefore]
    .sort((left, right) => right - left)
    .map((days) => ({ on: addDays(endsOn, -days), daysBefore: days }));
}
