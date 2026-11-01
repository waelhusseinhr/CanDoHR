/**
 * Pay composition, ported from reference/premium_stacking_reference.py.
 * Amounts use decimal.js. Each line is rounded half up to the cent once.
 * Missing combinations stay missing: this module does not guess.
 */
import Decimal from "decimal.js";
import { RulesError } from "./errors.ts";

Decimal.set({ precision: 28 });

const SOURCES = ["daily", "weekly", "consecutive_days", "rest_day", "second_rest_day", "holiday"] as const;
const LINE_ORDER = ["holiday", "second_rest_day", "rest_day", "daily", "consecutive_days", "weekly"];
const ONE = new Decimal(1);

export type Problem = { code: string; detail: string };

type Obj = Record<string, unknown>;

function isObj(value: unknown): value is Obj {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function D(value: unknown): Decimal {
  if (value instanceof Decimal) return value;
  if (typeof value === "number") return new Decimal(value.toString());
  return new Decimal(String(value));
}

function money(value: Decimal): string {
  return value.toDecimalPlaces(2, Decimal.ROUND_HALF_UP).toFixed(2);
}

function fmt(value: Decimal): string {
  return value.toSignificantDigits(28).toFixed();
}

function art(obj: unknown): string | null {
  if (!isObj(obj)) return null;
  const cite = obj.cite;
  if (!isObj(cite)) return null;
  return typeof cite.article === "string" ? cite.article : null;
}

function asObj(value: unknown): Obj {
  return isObj(value) ? value : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function holidayMultiplier(rules: Obj): { multiplier: Decimal | null; cite: string | null } {
  const ot = asObj(rules.overtime);
  const fromThr = asArray(ot.thresholds).filter((tier) => isObj(tier) && tier.basis === "holiday");
  const fromHol = asObj(rules.holidays).worked_multiplier;
  if (fromThr.length > 0 && fromHol !== undefined && fromThr.some((tier) => !D((tier as Obj).multiplier).eq(D(fromHol)))) {
    throw new RulesError(
      "AMBIGUOUS_HOLIDAY_MULTIPLIER",
      "overtime.thresholds[holiday] and holidays.worked_multiplier disagree",
    );
  }
  if (fromThr.length > 0) {
    return { multiplier: D((fromThr[0] as Obj).multiplier), cite: art(ot) };
  }
  if (fromHol !== undefined && fromHol !== null) {
    return { multiplier: D(fromHol), cite: art(rules.holidays) };
  }
  return { multiplier: null, cite: null };
}

export function definedSources(rules: Obj): string[] {
  const bases = new Set<string>();
  for (const tier of asArray(asObj(rules.overtime).thresholds)) {
    if (isObj(tier) && typeof tier.basis === "string") bases.add(tier.basis);
  }
  if (holidayMultiplier(rules).multiplier !== null) bases.add("holiday");
  return SOURCES.filter((source) => bases.has(source));
}

function sourceMultiplier(rules: Obj, src: Obj): { multiplier: Decimal; why: string } {
  const basis = String(src.basis);
  if (!SOURCES.includes(basis as (typeof SOURCES)[number])) {
    throw new RulesError("UNKNOWN_SOURCE", basis);
  }
  if (basis === "holiday") {
    const found = holidayMultiplier(rules);
    if (found.multiplier === null) {
      throw new RulesError("UNKNOWN_SOURCE", "holiday: the agreement defines no holiday multiplier");
    }
    return {
      multiplier: found.multiplier,
      why: `holiday ×${fmt(found.multiplier)}` + (found.cite ? ` (art. ${found.cite})` : ""),
    };
  }
  const ot = asObj(rules.overtime);
  let tiers = asArray(ot.thresholds).filter((tier) => isObj(tier) && tier.basis === basis) as Obj[];
  if (tiers.length === 0) {
    throw new RulesError("UNKNOWN_SOURCE", `${basis}: no such threshold in the agreement`);
  }
  if ("after_hours" in src) {
    tiers = tiers.filter((tier) => D(tier.after_hours).eq(D(src.after_hours)));
    if (tiers.length === 0) {
      throw new RulesError("UNKNOWN_SOURCE", `${basis} after ${String(src.after_hours)} h: no such tier`);
    }
  } else if (tiers.length > 1) {
    throw new RulesError("AMBIGUOUS_TIER", `${basis} has ${tiers.length} tiers; the block must give after_hours`);
  }
  const tier = tiers[0];
  const cite = art(ot);
  const why =
    `overtime ${basis} after ${fmt(D(tier.after_hours))} h ×${fmt(D(tier.multiplier))}` +
    (cite ? ` (art. ${cite})` : "");
  return { multiplier: D(tier.multiplier), why };
}

function premiumByCode(rules: Obj, code: string): Obj {
  for (const premium of asArray(rules.premiums)) {
    if (isObj(premium) && premium.code === code) return premium;
  }
  throw new RulesError("UNKNOWN_PREMIUM", code);
}

function hourlyRate(premium: Obj, base: Decimal): Decimal {
  const amount = asObj(premium.amount);
  if ("per_hour" in amount) return D(amount.per_hour);
  if ("percent_of_rate" in amount) return base.mul(D(amount.percent_of_rate)).div(100);
  throw new RulesError(
    "NOT_AN_HOURLY_PREMIUM",
    `${String(premium.code)} is paid per shift or by its own formula, not per hour`,
  );
}

function isHourly(premium: Obj): boolean {
  const amount = asObj(premium.amount);
  return "per_hour" in amount || "percent_of_rate" in amount;
}

function resolveMethod(method: string, multipliers: Map<string, Decimal>, order: string[] | null): Decimal {
  const values = [...multipliers.values()];
  if (method === "greater_of") return values.reduce((best, value) => (value.gt(best) ? value : best));
  if (method === "sum_premiums") {
    return values.reduce((total, value) => total.plus(value.minus(ONE)), ONE);
  }
  if (method === "multiply") return values.reduce((total, value) => total.mul(value), ONE);
  if (method === "first_in_order") {
    if (order === null) {
      throw new RulesError("UNRESOLVED_INTERACTION", "first_in_order needs pay_composition.evaluation_order");
    }
    for (const source of order) {
      const found = multipliers.get(source);
      if (found) return found;
    }
    throw new RulesError(
      "UNRESOLVED_INTERACTION",
      `first_in_order: none of ${[...multipliers.keys()].sort()} is in evaluation_order`,
    );
  }
  throw new RulesError("UNKNOWN_RESOLUTION", method);
}

function findConflictRule(comp: Obj, bases: Set<string>): { index: number; rule: Obj } | null {
  const rules = asArray(asObj(comp.multiplier_conflicts).rules);
  for (let index = 0; index < rules.length; index += 1) {
    const rule = rules[index];
    if (!isObj(rule) || !Array.isArray(rule.when)) continue;
    if (rule.when.length === bases.size && rule.when.every((source) => bases.has(String(source)))) {
      return { index, rule };
    }
  }
  return null;
}

export type ComposeResult = {
  multiplier: string;
  regular_rate: string;
  lines: Obj[];
  total: string;
  rule_path: Obj[];
};

export function compose(block: Obj, rules: Obj): ComposeResult {
  let comp = rules.pay_composition;
  const sources = asArray(block.sources);
  const premiumCodes = asArray(block.premiums);
  if (comp == null && (sources.length > 0 || premiumCodes.length > 1)) {
    throw new RulesError("UNRESOLVED_INTERACTION", "the agreement version has no pay_composition");
  }
  const composition = asObj(comp);
  const order = Array.isArray(composition.evaluation_order) ? (composition.evaluation_order as string[]) : null;
  const shown = order && order.length > 0 ? order : LINE_ORDER;
  const hours = D(block.hours);
  const base = D(block.base_rate);
  const path: Obj[] = [];
  const multipliers = new Map<string, Decimal>();

  for (const source of sources) {
    if (!isObj(source)) continue;
    const basis = String(source.basis);
    if (multipliers.has(basis)) throw new RulesError("DUPLICATE_SOURCE", basis);
    const found = sourceMultiplier(rules, source);
    multipliers.set(basis, found.multiplier);
    path.push({ step: "source", rule: found.why });
  }

  let mult: Decimal;
  if (multipliers.size === 0) {
    mult = ONE;
  } else if (multipliers.size === 1) {
    mult = multipliers.values().next().value as Decimal;
  } else {
    const bases = new Set(multipliers.keys());
    const found = findConflictRule(composition, bases);
    const conflicts = asObj(composition.multiplier_conflicts);
    let cap: unknown;
    let where: string;
    let cite: string | null;
    let resolution: string;
    if (found) {
      resolution = String(found.rule.resolution);
      mult = resolveMethod(resolution, multipliers, order);
      cap = found.rule.multiplier_cap;
      where = `pay_composition.multiplier_conflicts.rules[${found.index}]`;
      cite = art(found.rule);
    } else if (conflicts.default_resolution) {
      resolution = String(conflicts.default_resolution);
      mult = resolveMethod(resolution, multipliers, order);
      cap = conflicts.default_cap;
      where = "pay_composition.multiplier_conflicts.default_resolution";
      cite = isObj(conflicts.default_cite) && typeof conflicts.default_cite.article === "string"
        ? conflicts.default_cite.article
        : null;
    } else {
      const label = shown.filter((source) => bases.has(source)).join("+");
      throw new RulesError("UNRESOLVED_INTERACTION", `no rule for ${label} and no default_resolution`);
    }
    path.push({
      step: "combine",
      rule: `${where}: ${resolution} → ×${fmt(mult)}` + (cite ? ` (art. ${cite})` : ""),
    });
    if (cap != null && mult.gt(D(cap))) {
      mult = D(cap);
      path.push({ step: "cap", rule: `multiplier_cap ×${fmt(mult)}` });
    }
  }

  const floor = block.statutory_minimum_multiplier;
  if (floor != null && mult.lt(D(floor))) {
    mult = D(floor);
    path.push({ step: "statute_floor", rule: `employment standards minimum ×${fmt(mult)}` });
  }

  const listed = asArray(rules.premiums).filter(isObj).map((premium) => String(premium.code));
  let prem = premiumCodes.map((code) => {
    const premium = premiumByCode(rules, String(code));
    return { code: String(code), premium, rate: hourlyRate(premium, base) };
  });
  prem.sort((a, b) => listed.indexOf(a.code) - listed.indexOf(b.code));
  const dropped = new Set<string>();
  for (const group of asArray(composition.exclusive_groups)) {
    if (!isObj(group) || !Array.isArray(group.codes)) continue;
    const codes = group.codes.map(String);
    const inside = prem.filter((item) => codes.includes(item.code));
    if (inside.length > 1) {
      const keep = [...inside].sort((a, b) => {
        const byRate = b.rate.comparedTo(a.rate);
        if (byRate !== 0) return byRate;
        return codes.indexOf(a.code) - codes.indexOf(b.code);
      })[0];
      for (const item of inside) {
        if (item.code === keep.code) continue;
        dropped.add(item.code);
        const cite = art(group);
        path.push({
          step: "stacking",
          rule: `${item.code} not paid: exclusive group with ${keep.code}` + (cite ? ` (art. ${cite})` : ""),
        });
      }
    }
  }
  prem = prem.filter((item) => !dropped.has(item.code));
  if (prem.length > 1 && composition.premium_stacking === "highest_only") {
    const keep = [...prem].sort((a, b) => {
      const byRate = b.rate.comparedTo(a.rate);
      if (byRate !== 0) return byRate;
      return listed.indexOf(a.code) - listed.indexOf(b.code);
    })[0];
    for (const item of prem) {
      if (item.code === keep.code) continue;
      path.push({ step: "stacking", rule: `${item.code} not paid: premium_stacking highest_only` });
    }
    prem = [keep];
  } else if (prem.length > 1 && !("premium_stacking" in composition)) {
    throw new RulesError("UNRESOLVED_INTERACTION", "several premiums apply and premium_stacking is not set");
  }

  let regular = base;
  for (const item of prem) {
    if (item.premium.in_regular_rate) {
      regular = regular.plus(item.rate);
      const cite = art(item.premium);
      path.push({
        step: "regular_rate",
        rule: `${item.code} +${fmt(item.rate)} included in the regular rate` + (cite ? ` (art. ${cite})` : ""),
      });
    }
  }

  const lines: Obj[] = [
    {
      kind: "time",
      sources: shown.filter((source) => multipliers.has(source)),
      hours: fmt(hours),
      rate: fmt(regular),
      multiplier: fmt(mult),
      amount: money(hours.mul(regular).mul(mult)),
    },
  ];

  const governing = multipliers.has("holiday") ? "holiday_interaction" : "overtime_interaction";
  for (const item of prem) {
    if (item.premium.in_regular_rate) continue;
    let factor: Decimal;
    if (mult.eq(ONE)) {
      factor = ONE;
    } else {
      const how = item.premium[governing];
      if (how == null) throw new RulesError("MISSING_INTERACTION", `${item.code}.${governing} is not set`);
      const factors: Record<string, Decimal> = { multiplied: mult, flat: ONE, excluded: new Decimal(0) };
      factor = factors[String(how)];
      const cite = art(item.premium);
      path.push({
        step: "premium",
        rule: `${item.code}.${governing} = ${String(how)}` + (cite ? ` (art. ${cite})` : ""),
      });
    }
    if (factor.eq(0)) continue;
    lines.push({
      kind: "premium",
      code: item.code,
      hours: fmt(hours),
      rate: fmt(item.rate),
      multiplier: fmt(factor),
      amount: money(hours.mul(item.rate).mul(factor)),
    });
  }

  const total = lines.reduce((sum, line) => sum.plus(D(line.amount)), new Decimal(0));
  return {
    multiplier: fmt(mult),
    regular_rate: fmt(regular),
    lines,
    total: money(total),
    rule_path: path,
  };
}

function combinations(items: string[], size: number): string[][] {
  const out: string[][] = [];
  const pick = (start: number, acc: string[]): void => {
    if (acc.length === size) {
      out.push([...acc]);
      return;
    }
    for (let index = start; index < items.length; index += 1) {
      acc.push(items[index]);
      pick(index + 1, acc);
      acc.pop();
    }
  };
  pick(0, []);
  return out;
}

function pairKey(left: string, right: string): string {
  return [left, right].sort().join("|");
}

function exclusivePairs(rules: Obj): Set<string> {
  const pairs = new Set<string>([pairKey("rest_day", "second_rest_day")]);
  const counting = asObj(asObj(rules.pay_composition).hours_counting);
  if (counting.daily_overtime_counts_toward_weekly === false) pairs.add(pairKey("daily", "weekly"));
  return pairs;
}

function possibleCombinations(rules: Obj): string[][] {
  const sources = definedSources(rules);
  const exclusive = exclusivePairs(rules);
  const out: string[][] = [];
  for (let size = 2; size <= sources.length; size += 1) {
    for (const combo of combinations(sources, size)) {
      const blocked = combinations(combo, 2).some((pair) => exclusive.has(pairKey(pair[0], pair[1])));
      if (!blocked) out.push(combo);
    }
  }
  return out;
}

export function validate(rules: Obj): Problem[] {
  const problems: Problem[] = [];
  let sources: string[];
  try {
    sources = definedSources(rules);
  } catch (error) {
    if (error instanceof RulesError) return [{ code: error.code, detail: error.detail }];
    throw error;
  }
  const comp = rules.pay_composition;
  const hourly = asArray(rules.premiums).filter((premium) => isObj(premium) && isHourly(premium)) as Obj[];
  if (comp == null) {
    if (sources.length > 0 || hourly.length > 1) {
      problems.push({ code: "UNRESOLVED_INTERACTION", detail: "pay_composition is missing" });
    }
    return problems;
  }
  const composition = asObj(comp);
  for (const premium of hourly) {
    for (const key of ["in_regular_rate", "overtime_interaction", "holiday_interaction"]) {
      if (!(key in premium)) problems.push({ code: "MISSING_INTERACTION", detail: `${String(premium.code)}.${key}` });
    }
    if (
      premium.in_regular_rate &&
      (premium.overtime_interaction !== "multiplied" || premium.holiday_interaction !== "multiplied")
    ) {
      problems.push({
        code: "INCONSISTENT_INTERACTION",
        detail: `${String(premium.code)} is in the regular rate, so it is always multiplied`,
      });
    }
  }
  const codes = new Set(asArray(rules.premiums).filter(isObj).map((premium) => String(premium.code)));
  for (const group of asArray(composition.exclusive_groups)) {
    if (!isObj(group) || !Array.isArray(group.codes)) continue;
    for (const code of group.codes) {
      if (!codes.has(String(code))) {
        problems.push({ code: "UNKNOWN_PREMIUM", detail: `exclusive group names ${String(code)}` });
      }
    }
  }
  const conflicts = asObj(composition.multiplier_conflicts);
  const seen = new Set<string>();
  const order = Array.isArray(composition.evaluation_order) ? composition.evaluation_order.map(String) : [];
  const conflictRules = asArray(conflicts.rules);
  for (let index = 0; index < conflictRules.length; index += 1) {
    const rule = conflictRules[index];
    if (!isObj(rule) || !Array.isArray(rule.when)) continue;
    const key = [...rule.when.map(String)].sort().join("|");
    if (seen.has(key)) {
      problems.push({ code: "DUPLICATE_CONFLICT_RULE", detail: `rules[${index}] ${[...rule.when.map(String)].sort()}` });
    }
    seen.add(key);
    for (const source of rule.when) {
      if (!sources.includes(String(source))) {
        problems.push({
          code: "UNKNOWN_SOURCE",
          detail: `rules[${index}] names ${String(source)}, which this version does not define`,
        });
      }
    }
    if (rule.resolution === "first_in_order" && !rule.when.every((source) => order.includes(String(source)))) {
      problems.push({
        code: "UNRESOLVED_INTERACTION",
        detail: `rules[${index}] first_in_order without an order for all its sources`,
      });
    }
  }
  if (conflicts.default_resolution === "first_in_order" && !sources.every((source) => order.includes(source))) {
    problems.push({
      code: "UNRESOLVED_INTERACTION",
      detail: "default first_in_order without an order for every source",
    });
  }
  if (!conflicts.default_resolution) {
    for (const combo of possibleCombinations(rules)) {
      const key = [...combo].sort().join("|");
      if (!seen.has(key)) problems.push({ code: "UNRESOLVED_INTERACTION", detail: combo.join("+") });
    }
  }
  return problems;
}

export function deepMerge(base: unknown, over: unknown): unknown {
  const out = structuredClone(base) as Obj;
  if (!isObj(over)) return out;
  for (const [key, value] of Object.entries(over)) {
    if (value === null) {
      delete out[key];
    } else if (isObj(value) && isObj(out[key])) {
      out[key] = deepMerge(out[key], value);
    } else {
      out[key] = structuredClone(value);
    }
  }
  return out;
}

export function caseRules(baseRules: Obj, testCase: Obj): Obj {
  const rules = deepMerge(baseRules, testCase.rules_override ?? {}) as Obj;
  const overrides = asObj(testCase.premium_override);
  if (Object.keys(overrides).length > 0) {
    rules.premiums = asArray(rules.premiums).map((premium) => {
      if (!isObj(premium)) return premium;
      const over = overrides[String(premium.code)];
      return over ? (deepMerge(premium, over) as Obj) : premium;
    });
  }
  for (const extra of asArray(testCase.premium_add)) {
    rules.premiums = [...asArray(rules.premiums), extra];
  }
  return rules;
}
