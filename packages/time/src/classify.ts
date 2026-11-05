import { add, cmp, hours, mul, sub, sum, TimeError } from "./money.ts";

export type Tier = { after: string; multiplier: string };

export type Jurisdiction = {
  code: string;
  daily: Tier[];
  weeklyAfter: string;
  weeklyMultiplier: string;
  greaterOfDailyOrWeekly: boolean;
  rateBasis: "regular" | "minimum_wage";
  minimumWage?: string;
  multiRate: "rate_for_work_performed" | "weighted_average" | "verify_at_load";
  dailyOvertimeCountsTowardWeekly: boolean;
};

export type DaySlice = {
  date: string;
  assignmentId: string;
  hours: string;
  rate: string;
};

export type AgreementThreshold = {
  assignmentId: string;
  dailyAfter?: string;
  dailyMultiplier?: string;
  source: string;
};

export type PayLine = {
  date: string;
  assignmentId: string;
  payCode: string;
  hours: string;
  multiplier: string;
  rate: string;
  rateBasis: "regular" | "minimum_wage";
  amount: string;
  ruleSource: string;
  provisional?: boolean;
};

export type ClassifyResult = {
  lines: PayLine[];
  greaterRight: "statute" | "agreement" | "exempt";
  agreementsChecked: boolean;
  statuteOvertimeHours: string;
  paidOvertimeHours: string;
  weeklyCountedHours: string;
};

type Piece = {
  date: string;
  assignmentId: string;
  rate: string;
  hours: string;
  multiplier: string;
  kind: "regular" | "daily_ot" | "weekly_ot";
  rateBasis: "regular" | "minimum_wage";
  ruleSource: string;
};

function norm(value: string): string {
  return hours(value);
}

function payCode(piece: Piece): string {
  if (piece.kind === "regular") return "REG";
  if (piece.multiplier === "2.00") return "OT20";
  if (piece.multiplier === "1.50") return "OT15";
  return "OT";
}

function basisRate(piece: Piece, jurisdiction: Jurisdiction): string {
  if (piece.rateBasis === "minimum_wage") {
    if (!jurisdiction.minimumWage) throw new TimeError("INPUT_REQUIRED");
    return norm(jurisdiction.minimumWage);
  }
  return norm(piece.rate);
}

function lineAmount(piece: Piece, jurisdiction: Jurisdiction): string {
  return mul(mul(piece.hours, piece.multiplier), basisRate(piece, jurisdiction));
}

function toLine(piece: Piece, jurisdiction: Jurisdiction): PayLine {
  return {
    date: piece.date,
    assignmentId: piece.assignmentId,
    payCode: payCode(piece),
    hours: piece.hours,
    multiplier: piece.multiplier,
    rate: basisRate(piece, jurisdiction),
    rateBasis: piece.rateBasis,
    amount: lineAmount(piece, jurisdiction),
    ruleSource: piece.ruleSource,
  };
}

function overtimeHours(pieces: Piece[]): string {
  return sum(pieces.filter((piece) => piece.kind !== "regular").map((piece) => piece.hours));
}

function pathPay(pieces: Piece[], jurisdiction: Jurisdiction): string {
  return sum(pieces.map((piece) => lineAmount(piece, jurisdiction)));
}

function uniqueHours(values: string[]): string[] {
  const out: string[] = [];
  for (const value of values) {
    if (!out.some((item) => cmp(item, value) === 0)) out.push(value);
  }
  return out.sort((left, right) => cmp(left, right));
}

function splitSlice(
  slice: DaySlice,
  tiers: Tier[],
  kind: "statute" | "agreement",
  jurisdiction: Jurisdiction,
  source?: string,
): Piece[] {
  const total = norm(slice.hours);
  const cuts = uniqueHours([
    "0.00",
    total,
    ...tiers.map((tier) => norm(tier.after)).filter((after) => cmp(after, "0.00") > 0 && cmp(after, total) < 0),
  ]);
  const pieces: Piece[] = [];
  // structural: loop index or iteration bound, not a business default
  for (let index = 0; index < cuts.length - 1; index += 1) {
    const from = cuts[index];
    const to = cuts[index + 1];
    const span = sub(to, from);
    if (cmp(span, "0.00") === 0) continue;
    const tier = [...tiers]
      .map((item) => ({ after: norm(item.after), multiplier: norm(item.multiplier) }))
      .filter((item) => cmp(from, item.after) >= 0)
      .sort((left, right) => cmp(right.after, left.after))[0];
    const overtime = Boolean(tier);
    pieces.push({
      date: slice.date,
      assignmentId: slice.assignmentId,
      rate: norm(slice.rate),
      hours: span,
      // rule: agreement or holiday premium inputs in tests; pay comes from rules/agreements
      multiplier: tier?.multiplier ?? "1.00",
      kind: overtime ? "daily_ot" : "regular",
      rateBasis: overtime && kind === "statute" ? jurisdiction.rateBasis : "regular",
      ruleSource: overtime
        ? kind === "agreement"
          ? `agreement:${source} daily after ${tier?.after} ×${tier?.multiplier}`
          : `ES:${jurisdiction.code} daily after ${tier?.after} ×${tier?.multiplier}`
        : kind === "agreement"
          ? `agreement:${source} regular`
          : `ES:${jurisdiction.code} regular`,
    });
  }
  return pieces;
}

function chooseDaily(slice: DaySlice, jurisdiction: Jurisdiction, agreements?: AgreementThreshold[]): Piece[] {
  const statute = splitSlice(slice, jurisdiction.daily, "statute", jurisdiction);
  const agreement = agreements?.find((item) => item.assignmentId === slice.assignmentId && item.dailyAfter);
  if (!agreement?.dailyAfter) return statute;
  const alternate = splitSlice(
    slice,
    // rule: agreement or holiday premium inputs in tests; pay comes from rules/agreements
    [{ after: agreement.dailyAfter, multiplier: agreement.dailyMultiplier ?? "1.50" }],
    "agreement",
    jurisdiction,
    agreement.source,
  );
  return cmp(pathPay(alternate, jurisdiction), pathPay(statute, jurisdiction)) > 0 ? alternate : statute;
}

function groupByDate(slices: DaySlice[]): DaySlice[][] {
  const grouped = new Map<string, DaySlice[]>();
  for (const slice of slices) {
    const list = grouped.get(slice.date) ?? [];
    list.push(slice);
    grouped.set(slice.date, list);
  }
  return [...grouped.entries()].sort((left, right) => left[0].localeCompare(right[0])).map((entry) => entry[1]);
}

function dailyPieces(slices: DaySlice[], jurisdiction: Jurisdiction, agreements: AgreementThreshold[] | null, ignoreDaily: boolean): Piece[] {
  const pieces: Piece[] = [];
  for (const day of groupByDate(slices)) {
    for (const slice of day) {
      if (ignoreDaily) {
        pieces.push(...splitSlice(slice, [], "statute", jurisdiction));
      } else {
        pieces.push(...chooseDaily(slice, jurisdiction, agreements ?? undefined));
      }
    }
  }
  return pieces;
}

function applyWeekly(pieces: Piece[], jurisdiction: Jurisdiction): { pieces: Piece[]; counted: string } {
  let counted = "0.00";
  const out: Piece[] = [];
  for (const piece of pieces) {
    const counts = piece.kind === "regular" || (jurisdiction.dailyOvertimeCountsTowardWeekly && piece.kind === "daily_ot");
    if (!counts) {
      out.push(piece);
      continue;
    }
    const before = counted;
    counted = add(counted, piece.hours);
    const keep = cmp(counted, jurisdiction.weeklyAfter) <= 0 ? piece.hours : cmp(before, jurisdiction.weeklyAfter) >= 0 ? "0.00" : sub(jurisdiction.weeklyAfter, before);
    const over = sub(piece.hours, keep);
    if (cmp(keep, "0.00") > 0) out.push({ ...piece, hours: keep });
    if (cmp(over, "0.00") > 0) {
      if (piece.kind === "regular" || cmp(norm(jurisdiction.weeklyMultiplier), piece.multiplier) > 0) {
        out.push({
          ...piece,
          hours: over,
          multiplier: norm(jurisdiction.weeklyMultiplier),
          kind: "weekly_ot",
          rateBasis: jurisdiction.rateBasis,
          ruleSource: `ES:${jurisdiction.code} weekly after ${norm(jurisdiction.weeklyAfter)} ×${norm(jurisdiction.weeklyMultiplier)}`,
        });
      } else {
        out.push({ ...piece, hours: over });
      }
    }
  }
  return { pieces: out, counted };
}

function finish(slices: DaySlice[], jurisdiction: Jurisdiction, agreements: AgreementThreshold[] | null, ignoreDaily: boolean) {
  return applyWeekly(dailyPieces(slices, jurisdiction, agreements, ignoreDaily), jurisdiction);
}

function betterPath(
  primary: { pieces: Piece[]; counted: string },
  alternate: { pieces: Piece[]; counted: string } | null,
  jurisdiction: Jurisdiction,
) {
  if (!alternate) return primary;
  return cmp(pathPay(alternate.pieces, jurisdiction), pathPay(primary.pieces, jurisdiction)) > 0 ? alternate : primary;
}

export function classifyWeek(input: {
  slices: DaySlice[];
  jurisdiction: Jurisdiction;
  agreements?: AgreementThreshold[];
  exempt?: { code: string };
}): ClassifyResult {
  const slices = input.slices.map((slice, index) => ({ slice, index })).sort((left, right) => left.slice.date.localeCompare(right.slice.date) || left.index - right.index).map((item) => item.slice);
  if (input.exempt) {
    const lines = slices.map((slice) => ({
      date: slice.date,
      assignmentId: slice.assignmentId,
      payCode: "REG",
      hours: norm(slice.hours),
      multiplier: "1.00",
      rate: norm(slice.rate),
      rateBasis: "regular" as const,
      amount: mul(norm(slice.hours), norm(slice.rate)),
      ruleSource: `exemption:${input.exempt?.code}`,
    }));
    return {
      lines,
      greaterRight: "exempt",
      agreementsChecked: false,
      statuteOvertimeHours: "0.00",
      paidOvertimeHours: "0.00",
      weeklyCountedHours: sum(lines.map((line) => line.hours)),
    };
  }
  const rates = new Set(slices.map((slice) => norm(slice.rate)));
  if (input.jurisdiction.multiRate === "verify_at_load" && rates.size > 1) {
    throw new TimeError("RULE_NOT_VERIFIED");
  }
  const statute = betterPath(
    finish(slices, input.jurisdiction, null, false),
    input.jurisdiction.greaterOfDailyOrWeekly ? finish(slices, input.jurisdiction, null, true) : null,
    input.jurisdiction,
  );
  const agreements = input.agreements ?? [];
  const chosen = agreements.length
    ? betterPath(
        finish(slices, input.jurisdiction, agreements, false),
        input.jurisdiction.greaterOfDailyOrWeekly ? finish(slices, input.jurisdiction, null, true) : null,
        input.jurisdiction,
      )
    : statute;
  const greater = agreements.length && cmp(pathPay(chosen.pieces, input.jurisdiction), pathPay(statute.pieces, input.jurisdiction)) > 0 ? "agreement" : "statute";
  const lines = chosen.pieces.map((piece) => toLine(piece, input.jurisdiction));
  return {
    lines,
    greaterRight: greater,
    agreementsChecked: agreements.length > 0,
    statuteOvertimeHours: overtimeHours(statute.pieces),
    paidOvertimeHours: overtimeHours(chosen.pieces),
    weeklyCountedHours: chosen.counted,
  };
}

export function evaluateActing(input: {
  days: { date: string; hours: string }[];
  fullDayHours: string;
  paidFrom: "first_day";
  homeRate: string;
  actingRate: string;
}): { lines: PayLine[]; reliefDays: string } {
  const triggered = input.days.some((day) => cmp(norm(day.hours), norm(input.fullDayHours)) >= 0);
  const rate = triggered && input.paidFrom === "first_day" ? norm(input.actingRate) : norm(input.homeRate);
  const lines = input.days.map((day) => ({
    date: day.date,
    assignmentId: "acting",
    payCode: "REG",
    hours: norm(day.hours),
    multiplier: "1.00",
    rate,
    rateBasis: "regular" as const,
    amount: mul(norm(day.hours), rate),
    ruleSource: triggered ? "acting:first_day" : "acting:home",
  }));
  const relief = triggered ? input.days.filter((day) => cmp(norm(day.hours), "0.00") > 0).length : 0;
  return { lines, reliefDays: norm(String(relief)) };
}

export type AveragingLine = {
  date: string;
  hours: string;
  multiplier: string;
  amount: string;
  provisional: boolean;
  kind: "provisional" | "premium" | "daily_ot";
  ruleSource: string;
};

export function settleAveragingCycle(input: {
  weeks: { index: number; worked: string; target: string; dates: string[] }[];
  rate: string;
  overtimeMultiplier: string;
  closed: boolean;
  payPeriodEnd: string;
  dailyOvertime?: { date: string; hours: string; multiplier: string }[];
}): { lines: AveragingLine[]; followedPayPeriod: false } {
  const lines: AveragingLine[] = [];
  for (const week of input.weeks) {
    const extra = cmp(norm(week.worked), norm(week.target)) > 0 ? sub(norm(week.worked), norm(week.target)) : "0.00";
    if (cmp(extra, "0.00") === 0) continue;
    const date = week.dates[week.dates.length - 1];
    if (!date) throw new TimeError("INPUT_REQUIRED");
    if (!input.closed) {
      lines.push({
        date,
        hours: extra,
        multiplier: "1.00",
        amount: mul(extra, norm(input.rate)),
        provisional: true,
        kind: "provisional",
        ruleSource: "averaging:provisional_straight",
      });
    } else {
      const premium = sub(norm(input.overtimeMultiplier), "1.00");
      lines.push({
        date,
        hours: extra,
        multiplier: premium,
        amount: mul(mul(extra, premium), norm(input.rate)),
        provisional: false,
        kind: "premium",
        ruleSource: "averaging:cycle_settlement",
      });
    }
  }
  for (const daily of input.dailyOvertime ?? []) {
    lines.push({
      date: daily.date,
      hours: norm(daily.hours),
      multiplier: norm(daily.multiplier),
      amount: mul(mul(norm(daily.hours), norm(daily.multiplier)), norm(input.rate)),
      provisional: false,
      kind: "daily_ot",
      ruleSource: "averaging:daily_paid_in_period",
    });
  }
  return { lines, followedPayPeriod: false };
}
