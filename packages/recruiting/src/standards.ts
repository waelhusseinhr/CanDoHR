import { money } from "@candohr/disbursement";
import { addMonths, shiftDays } from "./dates.ts";
import { RecruitError } from "./errors.ts";

export type RuleRecord = Record<string, unknown>;

export type StandardsBundle = {
  edition: {
    jurisdictions?: Record<string, Record<string, RuleRecord>>;
    nationwide?: Record<string, RuleRecord>;
  };
  recruitment?: {
    jurisdictions?: Record<string, Record<string, RuleRecord>>;
    nationwide?: Record<string, RuleRecord>;
  };
  separation?: {
    structured_fields?: Record<string, Record<string, RuleRecord>>;
  };
};

function isRecord(value: unknown): value is RuleRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function piece(source: Record<string, unknown> | undefined, jurisdiction: string | null, key: string): RuleRecord | undefined {
  if (!source) return undefined;
  const scope = jurisdiction ? source[jurisdiction] : source;
  if (!isRecord(scope)) return undefined;
  const row = jurisdiction ? scope[key] : scope[key];
  return isRecord(row) ? row : undefined;
}

/** A rule still marked verify_at_load is not applied. */
export function employmentStandard(bundle: StandardsBundle, jurisdiction: string | null, key: string): RuleRecord {
  const fromEdition = jurisdiction
    ? piece(bundle.edition.jurisdictions, jurisdiction, key)
    : piece(bundle.edition.nationwide, null, key);
  const fromRecruitment = jurisdiction
    ? piece(bundle.recruitment?.jurisdictions, jurisdiction, key)
    : piece(bundle.recruitment?.nationwide, null, key);
  const structured = jurisdiction ? piece(bundle.separation?.structured_fields, jurisdiction, key) : undefined;
  const base = fromEdition ?? fromRecruitment;
  if (!base && !structured) throw new RecruitError("JURISDICTION_RULE_MISSING");
  if (base?.status === "verify_at_load" || structured?.status === "verify_at_load" || fromRecruitment?.status === "verify_at_load" && !fromEdition) {
    throw new RecruitError("RULE_NOT_VERIFIED");
  }
  if (fromEdition?.status === "verify_at_load") throw new RecruitError("RULE_NOT_VERIFIED");
  return { ...(base ?? {}), ...(structured ?? {}) };
}

export function ruleInt(record: RuleRecord, field: string): number {
  const raw = record[field];
  if (typeof raw !== "number" || !Number.isInteger(raw)) throw new RecruitError("JURISDICTION_RULE_MISSING");
  return raw;
}

export function ruleMoney(record: RuleRecord, field: string): string {
  const raw = record[field];
  if (typeof raw === "number" && Number.isFinite(raw)) return money(raw.toFixed(2));
  if (typeof raw === "string") return money(raw);
  throw new RecruitError("JURISDICTION_RULE_MISSING");
}

export function noticeThresholdDate(bundle: StandardsBundle, jurisdiction: string, startedOn: string): string {
  const rule = employmentStandard(bundle, jurisdiction, "termination_notice");
  const bands = rule.bands;
  if (!Array.isArray(bands) || !isRecord(bands[0])) throw new RecruitError("JURISDICTION_RULE_MISSING");
  const band = bands[0];
  let reached: string | undefined;
  if (typeof band.from_months === "number") reached = addMonths(startedOn, band.from_months);
  else if (typeof band.from_weeks === "number") reached = shiftDays(startedOn, band.from_weeks * 7);
  else if (typeof band.from_days === "number") reached = shiftDays(startedOn, band.from_days);
  else if (typeof band.from_years === "number") reached = addMonths(startedOn, band.from_years * 12);
  if (!reached) throw new RecruitError("JURISDICTION_RULE_MISSING");
  return shiftDays(reached, -1);
}
