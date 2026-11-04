import { addDays, lastOfMonth } from "./dates.ts";
import { D, pyStr } from "./decimal.ts";
import { fail, OffboardingError } from "./errors.ts";

/** Port of reference/several_positions_reference.py benefit_outcome. Do not change the result shape. */

export type RemainingAssignment = {
  assignmentId: string;
  fte: string | number;
  agreementId?: string;
  benefitEligible: boolean;
};

export type Enrolment = {
  planId: string;
  kind: string;
  scope: string;
  minFte: string | number;
  agreementId?: string;
};

export type Ending = {
  assignmentId?: string;
  endDate: string;
  reasonCategory: string;
  employerInitiated: boolean;
  jurisdiction: string;
  employmentType?: string;
  noticeOwedWeeks: number;
  severanceWeeks?: number | null;
  remaining?: RemainingAssignment[];
};

export type RuleMatch = {
  planKinds?: string[];
  planIds?: string[];
  scopes?: string[];
  endReasonCategories?: string[];
  jurisdictions?: string[];
  agreementIds?: string[];
  employmentTypes?: string[];
  employerInitiated?: boolean;
  employmentContinues?: boolean;
};

export type ChangeRule = {
  id: string;
  priority: number;
  name?: string;
  action: string;
  until?: { kind: string; n?: number; date?: string };
  offerConversion?: boolean;
  match?: RuleMatch;
};

export type JurisdictionRule = { rule: string };

export type BenefitResult = {
  planId: string;
  fteAfter: string;
  eligibleAfter: boolean;
  outcome: string;
  reasons: string[];
  warnings: string[];
  coverageUntil?: string;
  floorUntil?: string | null;
  ruleId?: string | null;
  offerConversion?: boolean;
};

function inList(match: RuleMatch, key: keyof RuleMatch, value: string | undefined): boolean {
  if (!(key in match)) return true;
  const allowed = match[key];
  if (!Array.isArray(allowed)) return false;
  if (value === undefined) return false;
  return allowed.includes(value);
}

function matches(rule: ChangeRule, enrolment: Enrolment, ending: Ending, continues: boolean): boolean {
  const match = rule.match === undefined ? {} : rule.match;
  if (!inList(match, "planKinds", enrolment.kind)) return false;
  if (!inList(match, "planIds", enrolment.planId)) return false;
  if (!inList(match, "scopes", enrolment.scope)) return false;
  if (!inList(match, "endReasonCategories", ending.reasonCategory)) return false;
  if (!inList(match, "jurisdictions", ending.jurisdiction)) return false;
  if (!inList(match, "agreementIds", enrolment.agreementId)) return false;
  if (!inList(match, "employmentTypes", ending.employmentType)) return false;
  if ("employerInitiated" in match && match.employerInitiated !== ending.employerInitiated) return false;
  if ("employmentContinues" in match && match.employmentContinues !== continues) return false;
  return true;
}

function untilDate(rule: ChangeRule, end: string, noticeWeeks: number, severanceWeeks: number | null): string {
  if (rule.action === "end_on_date") return end;
  const until = rule.until;
  if (until === undefined) fail("INPUT_REQUIRED");
  if (until.kind === "end_of_month") return lastOfMonth(end);
  if (until.kind === "end_of_next_month") return lastOfMonth(addDays(lastOfMonth(end), 1));
  if (until.kind === "days") {
    if (until.n === undefined) fail("INPUT_REQUIRED");
    return addDays(end, until.n);
  }
  if (until.kind === "weeks") {
    if (until.n === undefined) fail("INPUT_REQUIRED");
    return addDays(end, until.n * 7);
  }
  if (until.kind === "end_of_notice") return addDays(end, noticeWeeks * 7);
  if (until.kind === "end_of_severance") {
    if (severanceWeeks === null) {
      fail("INPUT_REQUIRED", "the rule continues coverage to the end of severance; give the weeks of severance");
    }
    return addDays(end, Math.trunc(severanceWeeks) * 7);
  }
  if (until.kind === "date") {
    if (until.date === undefined) fail("INPUT_REQUIRED");
    return until.date;
  }
  fail("INPUT_REQUIRED", `unknown until kind ${until.kind}`);
}

export function benefitOutcome(
  enrolment: Enrolment,
  ending: Ending,
  rules: ChangeRule[],
  jurisdictionRules: Record<string, JurisdictionRule>,
): BenefitResult {
  const end = ending.endDate;
  const original = ending.remaining === undefined ? [] : ending.remaining;
  const continues = original.length > 0;
  let remaining = original.filter((row) => row.benefitEligible);
  if (enrolment.scope === "agreement") {
    remaining = remaining.filter((row) => row.agreementId === enrolment.agreementId);
  }
  let fte = new D(0);
  for (const row of remaining) {
    fte = fte.plus(new D(String(row.fte)));
  }
  const eligibleAfter = fte.gte(new D(String(enrolment.minFte)));
  const base = { planId: enrolment.planId, fteAfter: pyStr(fte), eligibleAfter };
  if (eligibleAfter) {
    return { ...base, outcome: "no_change", reasons: ["STILL_ELIGIBLE"], warnings: [] };
  }
  if (ending.noticeOwedWeeks === undefined || ending.noticeOwedWeeks === null) fail("INPUT_REQUIRED");
  const weeks = Math.trunc(ending.noticeOwedWeeks);
  let floor: string | null = null;
  let jur: JurisdictionRule | null = null;
  const warnings: string[] = [];
  if (ending.employerInitiated && weeks > 0) {
    const found = jurisdictionRules[ending.jurisdiction];
    if (found === undefined) {
      fail("JURISDICTION_RULE_MISSING", `no benefits-during-notice rule for ${ending.jurisdiction}`);
    }
    jur = found;
    if (jur.rule === "continue_required") floor = addDays(end, weeks * 7);
    else if (jur.rule === "verify_at_load") warnings.push("RULE_NOT_VERIFIED");
  }
  const sorted = rules.slice().sort((left, right) => {
    if (left.priority !== right.priority) return left.priority - right.priority;
    if (left.id < right.id) return -1;
    if (left.id > right.id) return 1;
    return 0;
  });
  let rule: ChangeRule | null = null;
  for (const candidate of sorted) {
    if (matches(candidate, enrolment, ending, continues)) {
      rule = candidate;
      break;
    }
  }
  if (rule === null || rule.action === "hr_decides") {
    return {
      ...base,
      outcome: "hr_decides",
      ruleId: rule === null ? null : rule.id,
      floorUntil: floor,
      reasons: [rule === null ? "NO_MATCHING_RULE" : "RULE_REQUIRES_HR"],
      warnings,
    };
  }
  const severanceWeeks = !("severanceWeeks" in ending) || ending.severanceWeeks === undefined || ending.severanceWeeks === null
    ? null
    : ending.severanceWeeks;
  let until = untilDate(rule, end, weeks, severanceWeeks);
  const reasons = [`RULE:${rule.id}`];
  if (floor !== null && floor > until) {
    until = floor;
    reasons.push("STATUTORY_FLOOR");
  }
  if (jur !== null && jur.rule === "not_explicit" && until < addDays(end, weeks * 7)) {
    warnings.push("COMMON_LAW_REVIEW");
  }
  if (rule.offerConversion === undefined) fail("INPUT_REQUIRED");
  return {
    ...base,
    outcome: until === end ? "end_on_date" : "continue_until",
    coverageUntil: until,
    floorUntil: floor,
    ruleId: rule.id,
    offerConversion: rule.offerConversion,
    reasons,
    warnings,
  };
}

export function runBenefitCase(input: {
  enrolment: Enrolment;
  ending: Ending;
  rules: ChangeRule[];
  jurisdictionRules: Record<string, JurisdictionRule>;
}): BenefitResult | { error: string } {
  try {
    return benefitOutcome(input.enrolment, input.ending, input.rules, input.jurisdictionRules);
  } catch (error) {
    if (error instanceof OffboardingError) return { error: error.code };
    const message = error instanceof Error ? error.message : String(error);
    const head = message.split(":")[0];
    return { error: head === undefined ? message : head };
  }
}

const COMMON_LAW_CAUTION = "benefits.common_law_notice";

/**
 * Outside Ontario the oracle warning stops the decision until HR acknowledges
 * benefits.common_law_notice and writes a reason. Ontario continue_required has no warning.
 */
export function decideBenefitEnd(
  enrolment: Enrolment,
  ending: Ending,
  rules: ChangeRule[],
  jurisdictionRules: Record<string, JurisdictionRule>,
  acknowledgement: { caution: string; reason: string } | null,
): BenefitResult {
  const result = benefitOutcome(enrolment, ending, rules, jurisdictionRules);
  const needsCaution = result.warnings.includes("COMMON_LAW_REVIEW") || result.warnings.includes("RULE_NOT_VERIFIED");
  if (!needsCaution) return result;
  if (acknowledgement === null || acknowledgement.caution !== COMMON_LAW_CAUTION) fail("CAUTION_NOT_ACKNOWLEDGED");
  if (acknowledgement.reason.trim() === "") fail("INPUT_REQUIRED");
  return result;
}
