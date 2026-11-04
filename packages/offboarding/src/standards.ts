import { addDays, addHours } from "./dates.ts";
import { D, money } from "./decimal.ts";
import { fail } from "./errors.ts";

export type NoticeBand = {
  from_days?: number;
  from_weeks?: number;
  from_months?: number;
  from_years?: number;
  weeks: number;
};

export type NoticeRule = {
  bands?: NoticeBand[];
  status: string;
  cite?: string;
};

export type Service = { years: number; months: number; days?: number };

/**
 * Mixed band units are ranked in days so the highest threshold the service meets can be chosen.
 * structural: a year is 365 days, a month is 30, a week is 7. This only orders the bands.
 * The weeks returned are the matched band's own weeks.
 */
function thresholdDays(band: NoticeBand): number {
  if (band.from_days !== undefined) return band.from_days;
  if (band.from_weeks !== undefined) return band.from_weeks * 7;
  if (band.from_months !== undefined) return band.from_months * 30;
  if (band.from_years !== undefined) return band.from_years * 365;
  fail("RULE_NOT_VERIFIED", "notice band has no threshold");
}

function serviceDays(service: Service): number {
  const extra = service.days === undefined ? 0 : service.days;
  return service.years * 365 + service.months * 30 + extra;
}

export type NoticeResult = {
  weeks: number;
  matched: NoticeBand | null;
  status: string;
  cite: string;
  blocked: boolean;
};

export function statutoryNotice(rule: NoticeRule, service: Service, apply: boolean): NoticeResult {
  const cite = rule.cite === undefined ? "" : rule.cite;
  const bands = rule.bands === undefined ? [] : rule.bands;
  if (bands.length === 0) {
    if (apply) fail("RULE_NOT_VERIFIED");
    return { weeks: 0, matched: null, status: rule.status, cite, blocked: true };
  }
  const have = serviceDays(service);
  let best: NoticeBand | null = null;
  let bestDays = -1;
  for (const band of bands) {
    const need = thresholdDays(band);
    if (have >= need && need >= bestDays) {
      best = band;
      bestDays = need;
    }
  }
  const weeks = best === null ? 0 : best.weeks;
  if (apply && rule.status === "verify_at_load") fail("RULE_NOT_VERIFIED");
  return { weeks, matched: best, status: rule.status, cite, blocked: rule.status === "verify_at_load" };
}

export type SeveranceGate = {
  employer_ontario_payroll_at_least?: number;
  qualifying_group_termination?: boolean;
};

export type SeveranceRule = {
  status: string;
  exists: boolean | null;
  cite?: string;
  weeks_per_year_of_service?: number;
  prorated_for_part_years?: boolean;
  max_weeks?: number;
  min_service_years?: number;
  applies_when_any?: SeveranceGate[];
  rule?: string;
  days_wages_per_year_of_service?: number;
  minimum_days_wages?: number;
  min_service_months?: number;
};

export type SeveranceResult = {
  applies: boolean;
  weeks: string | null;
  days: string | null;
  status: string;
  cite: string;
  blocked: boolean;
};

function none(rule: SeveranceRule, cite: string, blocked: boolean): SeveranceResult {
  return { applies: false, weeks: null, days: null, status: rule.status, cite, blocked };
}

export function statutorySeverance(input: {
  rule: SeveranceRule;
  serviceYears: string;
  serviceMonths: number;
  employerPayroll: string;
  qualifyingGroupTermination: boolean;
  apply: boolean;
}): SeveranceResult {
  const rule = input.rule;
  const cite = rule.cite === undefined ? "" : rule.cite;
  if (rule.exists === null || rule.exists === undefined) {
    if (input.apply) fail("RULE_NOT_VERIFIED");
    return none(rule, cite, true);
  }
  if (!rule.exists) {
    if (input.apply && rule.status === "verify_at_load") fail("RULE_NOT_VERIFIED");
    return none(rule, cite, rule.status === "verify_at_load");
  }
  const years = new D(input.serviceYears);
  let result: SeveranceResult;
  if (rule.rule === "greater_of") {
    if (
      rule.days_wages_per_year_of_service === undefined ||
      rule.minimum_days_wages === undefined ||
      rule.min_service_months === undefined
    ) {
      fail("INPUT_REQUIRED");
    }
    if (input.serviceMonths < rule.min_service_months) {
      result = none(rule, cite, false);
    } else {
      const fromService = years.mul(new D(String(rule.days_wages_per_year_of_service)));
      const minimum = new D(String(rule.minimum_days_wages));
      const days = fromService.gt(minimum) ? fromService : minimum;
      result = {
        applies: true,
        weeks: null,
        days: days.toDecimalPlaces(2, D.ROUND_HALF_UP).toFixed(2),
        status: rule.status,
        cite,
        blocked: false,
      };
    }
  } else {
    if (
      rule.weeks_per_year_of_service === undefined ||
      rule.max_weeks === undefined ||
      rule.min_service_years === undefined ||
      rule.applies_when_any === undefined
    ) {
      fail("INPUT_REQUIRED");
    }
    if (years.lt(new D(String(rule.min_service_years)))) {
      result = none(rule, cite, false);
    } else {
      const payroll = new D(input.employerPayroll);
      let allowed = false;
      for (const gate of rule.applies_when_any) {
        if (gate.employer_ontario_payroll_at_least !== undefined) {
          const floor = new D(String(gate.employer_ontario_payroll_at_least));
          if (payroll.gte(floor)) allowed = true;
        }
        if (gate.qualifying_group_termination === true && input.qualifyingGroupTermination) allowed = true;
      }
      if (!allowed) {
        result = none(rule, cite, false);
      } else {
        const perYear = new D(String(rule.weeks_per_year_of_service));
        const earned = rule.prorated_for_part_years === false ? years.floor().mul(perYear) : years.mul(perYear);
        const cap = new D(String(rule.max_weeks));
        const weeks = earned.gt(cap) ? cap : earned;
        result = {
          applies: true,
          weeks: weeks.toDecimalPlaces(2, D.ROUND_HALF_UP).toFixed(2),
          days: null,
          status: rule.status,
          cite,
          blocked: false,
        };
      }
    }
  }
  if (input.apply && rule.status === "verify_at_load") fail("RULE_NOT_VERIFIED");
  return { ...result, blocked: rule.status === "verify_at_load", status: rule.status, cite };
}

export type DeadlineSide = {
  rule: string;
  days_after_end?: number;
  hours_after_end?: number;
  or?: string;
};

export type DeadlineRule = {
  status: string;
  cite?: string;
  employer_ends: DeadlineSide | null;
  employee_quits: DeadlineSide | null;
};

export type DeadlineResult = {
  deadline: string | null;
  offCycle: boolean;
  status: string;
  cite: string;
  blocked: boolean;
};

export function finalPayDeadline(input: {
  rule: DeadlineRule;
  initiatedBy: "employer" | "employee";
  endDate: string;
  nextRegularPayDay: string;
  apply: boolean;
}): DeadlineResult {
  const rule = input.rule;
  const cite = rule.cite === undefined ? "" : rule.cite;
  const side = input.initiatedBy === "employer" ? rule.employer_ends : rule.employee_quits;
  if (side === null) {
    if (input.apply) fail("RULE_NOT_VERIFIED");
    return { deadline: null, offCycle: false, status: rule.status, cite, blocked: true };
  }
  if (input.nextRegularPayDay.trim() === "") fail("INPUT_REQUIRED");
  let deadline: string;
  let offCycle = false;
  if (side.rule === "later_of") {
    if (side.days_after_end === undefined) fail("INPUT_REQUIRED");
    const byDays = addDays(input.endDate, side.days_after_end);
    deadline = byDays > input.nextRegularPayDay ? byDays : input.nextRegularPayDay;
  } else if (side.rule === "within_hours") {
    if (side.hours_after_end === undefined) fail("INPUT_REQUIRED");
    deadline = addHours(input.endDate, side.hours_after_end);
    offCycle = input.nextRegularPayDay > deadline;
  } else if (side.rule === "within_days") {
    if (side.days_after_end === undefined) fail("INPUT_REQUIRED");
    deadline = addDays(input.endDate, side.days_after_end);
    offCycle = input.nextRegularPayDay > deadline;
  } else {
    fail("RULE_NOT_VERIFIED");
  }
  if (input.apply && rule.status === "verify_at_load") fail("RULE_NOT_VERIFIED");
  return { deadline, offCycle, status: rule.status, cite, blocked: rule.status === "verify_at_load" };
}

export function owed(amount: string): string {
  return money(amount);
}
