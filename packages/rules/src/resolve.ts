/**
 * Greater-right resolution. Every number comes from the edition or the agreement
 * passed in. This file does not contain a statutory amount.
 */
import Decimal from "decimal.js";
import { canonicalize } from "./canonical.ts";

type Tier = {
  basis: string;
  afterHours: string;
  multiplier: string;
  source: string;
};

type Vacation = {
  days: string | null;
  weeks: string | null;
  payPercent: string | null;
  source: string;
};

export type ResolveResult = {
  jurisdiction: string;
  esVersion: string;
  agreement: { id: string; version: number } | null;
  overtime: Tier[];
  minimumWage: { amount: string; source: string } | null;
  vacation: Vacation | null;
  noticeWeeks: { weeks: string; source: string } | null;
};

type MinWage = {
  general?: number;
  effective_from?: string;
  next?: { general?: number; effective_from?: string };
};

type EsJurisdiction = {
  minimum_wage?: MinWage;
  overtime?: Record<string, unknown>;
  vacation?: { tiers?: Array<Record<string, unknown>> };
  termination_notice?: { bands?: Array<Record<string, unknown>> };
};

export type EmploymentStandardsEdition = {
  id?: string;
  jurisdictions?: Record<string, EsJurisdiction>;
};

export type ResolveInput = {
  jurisdiction: string;
  date: string;
  serviceYears: number;
  edition: EmploymentStandardsEdition;
  editionHash: string;
  agreement?: {
    id: string;
    version: number;
    rules: Record<string, unknown>;
  } | null;
  individualVacationDays?: number | null;
};

function plain(value: number): string {
  return new Decimal(value.toString()).toSignificantDigits(28).toFixed();
}

function wageOn(wage: MinWage | undefined, date: string): number | null {
  if (!wage || typeof wage.general !== "number" || !wage.effective_from || date < wage.effective_from) return null;
  if (wage.next && typeof wage.next.general === "number" && wage.next.effective_from && date >= wage.next.effective_from) {
    return wage.next.general;
  }
  return wage.general;
}

function esTiers(overtime: Record<string, unknown> | undefined, source: string): Tier[] {
  if (!overtime || typeof overtime.multiplier !== "number") return [];
  const multiplier = plain(overtime.multiplier);
  const tiers: Tier[] = [];
  if (typeof overtime.daily_after === "number") {
    tiers.push({ basis: "daily", afterHours: plain(overtime.daily_after), multiplier, source });
  }
  if (typeof overtime.weekly_after === "number") {
    tiers.push({ basis: "weekly", afterHours: plain(overtime.weekly_after), multiplier, source });
  }
  if (typeof overtime.double_time_daily_after === "number" && typeof overtime.double_time_multiplier === "number") {
    tiers.push({
      basis: "daily",
      afterHours: plain(overtime.double_time_daily_after),
      multiplier: plain(overtime.double_time_multiplier),
      source,
    });
  }
  return tiers;
}

function agreementTiers(rules: Record<string, unknown>, source: string): Tier[] {
  const overtime = rules.overtime;
  if (typeof overtime !== "object" || overtime === null) return [];
  const thresholds = (overtime as { thresholds?: unknown }).thresholds;
  if (!Array.isArray(thresholds)) return [];
  return thresholds.flatMap((tier) => {
    if (typeof tier !== "object" || tier === null) return [];
    const row = tier as Record<string, unknown>;
    if (typeof row.basis !== "string" || typeof row.after_hours !== "number" || typeof row.multiplier !== "number") {
      return [];
    }
    return [{ basis: row.basis, afterHours: plain(row.after_hours), multiplier: plain(row.multiplier), source }];
  });
}

function article(rules: Record<string, unknown>, family: string): string {
  const block = rules[family];
  if (typeof block === "object" && block !== null) {
    const cite = (block as { cite?: { article?: string } }).cite;
    if (cite?.article) return cite.article;
  }
  return family;
}

/** Keep a later tier only when it pays a higher multiplier than an earlier one. */
function keepFavourable(tiers: Tier[]): Tier[] {
  const byBasis = new Map<string, Tier[]>();
  for (const tier of tiers) {
    const list = byBasis.get(tier.basis) ?? [];
    list.push(tier);
    byBasis.set(tier.basis, list);
  }
  const kept: Tier[] = [];
  for (const list of byBasis.values()) {
    const sorted = [...list].sort((left, right) => {
      const hours = new Decimal(left.afterHours).comparedTo(right.afterHours);
      if (hours !== 0) return hours;
      return new Decimal(right.multiplier).comparedTo(left.multiplier);
    });
    const chosen: Tier[] = [];
    for (const tier of sorted) {
      const covered = chosen.some(
        (earlier) =>
          new Decimal(earlier.afterHours).lte(tier.afterHours) &&
          new Decimal(earlier.multiplier).gte(tier.multiplier),
      );
      if (!covered) chosen.push(tier);
    }
    kept.push(...chosen);
  }
  return kept;
}

function daysPerWeek(rules: Record<string, unknown> | undefined): Decimal | null {
  if (!rules) return null;
  const hours = rules.hours_of_work;
  if (typeof hours !== "object" || hours === null) return null;
  const daily = (hours as { normal_daily_hours?: number }).normal_daily_hours;
  const weekly = (hours as { normal_weekly_hours?: number }).normal_weekly_hours;
  if (typeof daily !== "number" || typeof weekly !== "number" || daily === 0) return null;
  return new Decimal(weekly.toString()).div(daily.toString());
}

function bestTier<T extends { service_years?: number }>(tiers: T[], years: number): T | null {
  const eligible = tiers.filter((tier) => typeof tier.service_years === "number" && years >= tier.service_years);
  if (eligible.length === 0) return null;
  return eligible.reduce((best, tier) => ((tier.service_years ?? 0) > (best.service_years ?? 0) ? tier : best));
}

function vacationFor(input: ResolveInput, jurisdiction: EsJurisdiction): Vacation | null {
  const esTiers = jurisdiction.vacation?.tiers ?? [];
  const es = bestTier(esTiers, input.serviceYears);
  const rules = input.agreement?.rules;
  const agreementVacation =
    rules && typeof rules.vacation === "object" && rules.vacation !== null
      ? (rules.vacation as { tiers?: Array<Record<string, unknown>> })
      : null;
  const agreement = agreementVacation?.tiers ? bestTier(agreementVacation.tiers, input.serviceYears) : null;
  const perWeek = daysPerWeek(rules);
  let bestDays: Decimal | null = null;
  let bestWeeks: string | null = null;
  let bestPay: string | null = null;
  let source: string | null = null;

  if (es && typeof es.weeks === "number") {
    bestWeeks = plain(es.weeks);
    if (perWeek) bestDays = perWeek.mul(es.weeks.toString());
    if (typeof es.pay_percent === "number") bestPay = plain(es.pay_percent);
    source = `es:${input.jurisdiction}`;
  }
  if (agreement && typeof agreement.days === "number") {
    const days = new Decimal(agreement.days.toString());
    const better = bestDays === null || days.gt(bestDays);
    if (better) {
      bestDays = days;
      bestWeeks = null;
      bestPay = typeof agreement.pay_percent === "number" ? plain(agreement.pay_percent as number) : null;
      source = `agreement:${article(rules ?? {}, "vacation")}`;
    }
  }
  if (typeof input.individualVacationDays === "number") {
    const days = new Decimal(input.individualVacationDays.toString());
    if (bestDays === null || days.gt(bestDays)) {
      bestDays = days;
      bestWeeks = null;
      source = "individual";
    }
  }
  if (!source) return null;
  return {
    days: bestDays ? bestDays.toSignificantDigits(28).toFixed() : null,
    weeks: bestWeeks,
    payPercent: bestPay,
    source,
  };
}

function noticeFor(input: ResolveInput, jurisdiction: EsJurisdiction): { weeks: string; source: string } | null {
  const bands = jurisdiction.termination_notice?.bands ?? [];
  let esWeeks: number | null = null;
  for (const band of bands) {
    const weeks = band.weeks;
    if (typeof weeks !== "number") continue;
    const reached =
      (typeof band.from_years === "number" && input.serviceYears >= band.from_years) ||
      (typeof band.from_months === "number" && input.serviceYears * 12 >= band.from_months) ||
      (typeof band.from_days === "number" && input.serviceYears * 365 >= band.from_days) ||
      (typeof band.from_weeks === "number" && input.serviceYears * 52 >= band.from_weeks);
    if (reached && (esWeeks === null || weeks > esWeeks)) esWeeks = weeks;
  }
  let weeks = esWeeks;
  let source = esWeeks === null ? null : `es:${input.jurisdiction}`;
  const layoff = input.agreement?.rules.layoff_recall;
  if (typeof layoff === "object" && layoff !== null && typeof (layoff as { notice_weeks?: number }).notice_weeks === "number") {
    const agreementWeeks = (layoff as { notice_weeks: number }).notice_weeks;
    if (weeks === null || agreementWeeks > weeks) {
      weeks = agreementWeeks;
      source = `agreement:${article(input.agreement?.rules ?? {}, "layoff_recall")}`;
    }
  }
  if (weeks === null || source === null) return null;
  return { weeks: plain(weeks), source };
}

export function resolve(input: ResolveInput): ResolveResult {
  const jurisdiction = input.edition.jurisdictions?.[input.jurisdiction];
  if (!jurisdiction) {
    throw new Error(`UNKNOWN_JURISDICTION: ${input.jurisdiction}`);
  }
  const esSource = `es:${input.jurisdiction}`;
  const agreementSource = input.agreement ? `agreement:${article(input.agreement.rules, "overtime")}` : null;
  const tiers = [...esTiers(jurisdiction.overtime, esSource)];
  if (input.agreement && agreementSource) tiers.push(...agreementTiers(input.agreement.rules, agreementSource));
  const wage = wageOn(jurisdiction.minimum_wage, input.date);
  return {
    jurisdiction: input.jurisdiction,
    esVersion: `${input.edition.id ?? "es"}@${input.jurisdiction}#${input.editionHash.slice(0, 12)}`,
    agreement: input.agreement ? { id: input.agreement.id, version: input.agreement.version } : null,
    overtime: keepFavourable(tiers),
    minimumWage: wage === null ? null : { amount: plain(wage), source: esSource },
    vacation: vacationFor(input, jurisdiction),
    noticeWeeks: noticeFor(input, jurisdiction),
  };
}

export function compareResolutions(
  before: ResolveResult,
  after: ResolveResult,
): Array<{ field: string; before: string; after: string }> {
  const fields = ["overtime", "minimumWage", "vacation", "noticeWeeks"] as const;
  const changes: Array<{ field: string; before: string; after: string }> = [];
  for (const field of fields) {
    const left = canonicalize(before[field]);
    const right = canonicalize(after[field]);
    if (left !== right) changes.push({ field, before: left, after: right });
  }
  return changes;
}
