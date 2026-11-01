import { RulesError } from "./errors.ts";

export type AppliesTo = {
  classifications?: string[];
  position_groups?: string[];
  org_nodes?: string[];
  org_subtrees?: string[];
  locations?: string[];
  schedule_types?: string[];
  employment_types?: string[];
  statuses?: string[];
  hour_bands?: Array<{ min?: number; max?: number }>;
  age_bands?: Array<{ min?: number; max?: number }>;
};

export type ScopedRule = {
  applies_to?: AppliesTo;
  precedence?: string;
};

export type ScopeContext = {
  classification?: string;
  positionGroup?: string;
  orgNode?: string;
  orgAncestors?: string[];
  location?: string;
  scheduleType?: string;
  employmentType?: string;
  status?: string;
  hours?: number;
  age?: number;
};

function includes(allowed: string[] | undefined, value: string | undefined, score: { n: number }): boolean {
  if (!allowed || allowed.length === 0) return true;
  score.n += 1;
  return value != null && allowed.includes(value);
}

function bandOk(bands: Array<{ min?: number; max?: number }> | undefined, value: number | undefined, score: { n: number }): boolean {
  if (!bands || bands.length === 0) return true;
  score.n += 1;
  if (value == null) return false;
  return bands.some((band) => (band.min == null || value >= band.min) && (band.max == null || value <= band.max));
}

function specificity(rule: ScopedRule, ctx: ScopeContext): number | null {
  const scope = rule.applies_to;
  if (!scope) return 0;
  const score = { n: 0 };
  if (!includes(scope.classifications, ctx.classification, score)) return null;
  if (!includes(scope.position_groups, ctx.positionGroup, score)) return null;
  if (!includes(scope.org_nodes, ctx.orgNode, score)) return null;
  if (!includes(scope.locations, ctx.location, score)) return null;
  if (!includes(scope.schedule_types, ctx.scheduleType, score)) return null;
  if (!includes(scope.employment_types, ctx.employmentType, score)) return null;
  if (!includes(scope.statuses, ctx.status, score)) return null;
  if (scope.org_subtrees && scope.org_subtrees.length > 0) {
    score.n += 1;
    const ancestors = new Set([ctx.orgNode, ...(ctx.orgAncestors ?? [])].filter((item): item is string => Boolean(item)));
    if (!scope.org_subtrees.some((node) => ancestors.has(node))) return null;
  }
  if (!bandOk(scope.hour_bands, ctx.hours, score)) return null;
  if (!bandOk(scope.age_bands, ctx.age, score)) return null;
  return score.n;
}

const overlapFamilies = new Set(["acting_pay", "status_conversion", "seniority"]);

/** The most specific matching scope wins. A tie without precedence is refused. */
export function selectScopedRule<T extends ScopedRule>(rules: T[], ctx: ScopeContext, family: string): T | null {
  const matched = rules
    .map((rule) => ({ rule, score: specificity(rule, ctx) }))
    .filter((item): item is { rule: T; score: number } => item.score !== null);
  if (matched.length === 0) return null;
  const prevailing = matched.filter((item) => item.rule.precedence === "prevails");
  const pool = prevailing.length > 0 ? prevailing : matched;
  const best = Math.max(...pool.map((item) => item.score));
  const winners = pool.filter((item) => item.score === best);
  if (winners.length > 1) {
    const code = overlapFamilies.has(family) ? "UNRESOLVED_INTERACTION" : "AMBIGUOUS_SCOPE";
    throw new RulesError(code, `${family} has overlapping scopes and no precedence`, 422);
  }
  return winners[0].rule;
}
