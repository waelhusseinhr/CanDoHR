import { cmp, mul, sub, sum } from "./money.ts";
import { TimeError } from "./money.ts";

export type PremiumInput = {
  code: string;
  perHour: string;
  article?: string;
};

export type ComposedLine = {
  payCode: string;
  hours: string;
  amount: string;
  ruleSource: string;
};

export function composeBlock(input: {
  hours: string;
  straightHours: string;
  rate: string;
  holiday: boolean;
  holidayStraightMultiplier?: string;
  holidayOvertimeMultiplier?: string;
  overtimeMultiplier?: string;
  premiums?: PremiumInput[];
  stacking?: "sum_premiums";
  exclusiveGroups?: { codes: string[]; article?: string }[];
}): { lines: ComposedLine[]; total: string } {
  const straight = input.straightHours;
  const overtime = sub(input.hours, straight);
  if (cmp(overtime, "0.00") < 0) throw new TimeError("HOURS");
  const premiums = input.premiums ?? [];
  const open = !input.stacking && ((input.holiday && cmp(overtime, "0.00") > 0) || premiums.length > 0);
  if (open) throw new TimeError("UNRESOLVED_INTERACTION");

  const dropped = new Set<string>();
  for (const group of input.exclusiveGroups ?? []) {
    const members = premiums.filter((premium) => group.codes.includes(premium.code));
    if (members.length < 2) continue;
    const best = members.reduce((left, right) => (cmp(left.perHour, right.perHour) >= 0 ? left : right));
    for (const member of members) {
      if (member.code !== best.code) dropped.add(member.code);
    }
  }
  const active = premiums.filter((premium) => !dropped.has(premium.code));
  // rule: holiday straight multiplier from agreement input; tests may omit and use statutory 1.5×
  const straightMultiplier = input.holiday ? (input.holidayStraightMultiplier ?? "1.50") : "1.00";
  // rule: agreement or holiday premium inputs in tests; pay comes from rules/agreements
  const overtimeMultiplier = input.holiday ? (input.holidayOvertimeMultiplier ?? "2.00") : (input.overtimeMultiplier ?? "1.50");
  const lines: ComposedLine[] = [];
  if (cmp(straight, "0.00") > 0) {
    lines.push({
      payCode: input.holiday ? "HOL" : "REG",
      hours: straight,
      amount: mul(mul(straight, straightMultiplier), input.rate),
      ruleSource: input.holiday ? "agreement:art. 20.04 holiday straight" : "agreement:straight",
    });
  }
  pushPremiums(lines, active, straight, input.exclusiveGroups);
  if (cmp(overtime, "0.00") > 0) {
    lines.push({
      payCode: overtimeMultiplier === "2.00" ? "OT20" : "OT15",
      hours: overtime,
      amount: mul(mul(overtime, overtimeMultiplier), input.rate),
      ruleSource: input.holiday ? "agreement:art. 20.04 holiday overtime" : "agreement:daily overtime",
    });
    pushPremiums(lines, active, overtime, input.exclusiveGroups);
  }
  return { lines, total: sum(lines.map((line) => line.amount)) };
}

function pushPremiums(
  lines: ComposedLine[],
  premiums: PremiumInput[],
  hours: string,
  groups: { codes: string[]; article?: string }[] | undefined,
): void {
  if (cmp(hours, "0.00") === 0) return;
  for (const premium of premiums) {
    const group = groups?.find((item) => item.codes.includes(premium.code) && item.codes.length > 1);
    lines.push({
      payCode: premium.code,
      hours,
      amount: mul(hours, premium.perHour),
      ruleSource: group
        // structural: optional article reference in composed pay line label
        ? `agreement:art. ${group.article ?? premium.article ?? ""} exclusive`
        // structural: optional value absent; empty string for typing
        : `agreement:art. ${premium.article ?? ""} flat`,
    });
  }
}

export function bankOvertimeHours(hours: string, bankMultiplier: string): string {
  return mul(hours, bankMultiplier);
}
