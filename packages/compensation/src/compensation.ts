import { addCalendarMonths, compareDates } from "./dates.ts";
import { HUNDRED, ONE, dec, moneyStr, qstr } from "./decimal.ts";
import { fail } from "./errors.ts";
import { payMetrics } from "./market-pricing.ts";
import { fill, screen, type ScreenLang } from "./text.ts";

export type Step = { role: string; approverId: string; approved: boolean };

export type ChangeDraft = {
  kind: string;
  status: "draft";
  effective: string;
  rate: string;
  retro: boolean;
  confirm: "hr";
};

function present(value: unknown): boolean {
  return value !== undefined && value !== null && value !== "";
}

export function approveSteps(submitterId: string, steps: Step[]): void {
  if (steps.length === 0) fail("ROUTE_APPROVALS_MISSING");
  for (const step of steps) {
    if (!step.approved) fail("ROUTE_APPROVALS_MISSING");
    if (step.approverId === submitterId) fail("SELF_APPROVAL");
  }
}

export function rangeVersion(input: {
  versions: { effective: string; minimum: string; midpoint: string; maximum: string }[];
  asOf: string;
  rate: string;
}): { minimum: string; midpoint: string; maximum: string; compaRatio: string; quartile: string } {
  let chosen: (typeof input.versions)[number] | undefined;
  for (const version of input.versions) {
    if (compareDates(version.effective, input.asOf) <= 0) {
      if (chosen === undefined || compareDates(version.effective, chosen.effective) > 0) chosen = version;
    }
  }
  if (chosen === undefined) fail("INPUT_REQUIRED", "range");
  const min = dec(chosen.minimum);
  const mid = dec(chosen.midpoint);
  const max = dec(chosen.maximum);
  if (min.gt(mid) || mid.gt(max)) fail("RANGE_ORDER");
  const metrics = payMetrics(input.rate, chosen);
  return {
    minimum: chosen.minimum,
    midpoint: chosen.midpoint,
    maximum: chosen.maximum,
    compaRatio: String(metrics.compaRatio),
    quartile: String(metrics.quartile),
  };
}

export function manualGridRate(input: {
  gridRate: string;
  proposed: string;
  agreementAllowsManual: boolean;
  reason?: string;
}): { rate: string; source: "grid" | "manual" } {
  if (input.proposed === input.gridRate) return { rate: input.gridRate, source: "grid" };
  if (!input.agreementAllowsManual) fail("MANUAL_RATE_BLOCKED");
  if (!present(input.reason)) fail("INPUT_REQUIRED", "reason");
  return { rate: input.proposed, source: "manual" };
}

export function progressionDraft(input: {
  hoursPaid: string;
  hoursStep: string;
  nextRate: string;
  nextPeriodStart: string;
}): { reached: boolean; changeSet: ChangeDraft | null } {
  if (!present(input.hoursStep)) fail("INPUT_REQUIRED", "hoursStep");
  const reached = dec(input.hoursPaid).gte(dec(input.hoursStep));
  if (!reached) return { reached: false, changeSet: null };
  return {
    reached: true,
    changeSet: {
      kind: "compensation.set_rate",
      status: "draft",
      effective: input.nextPeriodStart,
      rate: input.nextRate,
      retro: false,
      confirm: "hr",
    },
  };
}

export function openCycle(input: {
  year: string;
  eligibility: string;
  guidelineMethod: string;
  letterRelease: string;
  excludeHiredWithinMonths: string;
}): { year: string; eligibility: string; guidelineMethod: string; letterRelease: string; excludeHiredWithinMonths: string } {
  if (!present(input.eligibility) || !present(input.guidelineMethod) || !present(input.letterRelease)) {
    fail("SETTING_NOT_SET", "cycle");
  }
  if (!present(input.excludeHiredWithinMonths)) fail("SETTING_NOT_SET", "cycles.eligibility");
  return input;
}

export function hireInCycle(input: { hiredOn: string; cycleStart: string; excludeHiredWithinMonths: string }): { eligible: boolean } {
  const limit = addCalendarMonths(input.cycleStart, -Number(input.excludeHiredWithinMonths));
  return { eligible: compareDates(input.hiredOn, limit) < 0 };
}

export function meritWorksheet(input: {
  rate: string;
  range: { minimum: string; midpoint: string; maximum: string };
  rating: string;
  guidelinePct: string;
  spent: string;
  budget: string;
}): { rate: string; compaRatio: string; rating: string; guidelinePct: string; remaining: string } {
  const metrics = payMetrics(input.rate, input.range);
  return {
    rate: input.rate,
    compaRatio: String(metrics.compaRatio),
    rating: input.rating,
    guidelinePct: input.guidelinePct,
    remaining: moneyStr(dec(input.budget).minus(dec(input.spent))),
  };
}

export function meritRecommendation(input: {
  guidelinePct: string;
  proposedPct: string;
  reason?: string;
  hrApproved: boolean;
  policy: string;
}): { accepted: boolean; outOfGuideline: boolean } {
  if (!present(input.policy)) fail("SETTING_NOT_SET", "cycles.out_of_guideline");
  const outside = !dec(input.proposedPct).eq(dec(input.guidelinePct)) && dec(input.proposedPct).gt(dec(input.guidelinePct));
  if (!outside) return { accepted: true, outOfGuideline: false };
  if (input.policy === "blocked") fail("OUT_OF_GUIDELINE_BLOCKED");
  if (!present(input.reason)) fail("CYCLE_EXCEPTION_REASON_REQUIRED");
  if (input.policy === "reason_and_hr" && !input.hrApproved) fail("HR_APPROVAL_REQUIRED");
  return { accepted: true, outOfGuideline: true };
}

export function releaseLetters(input: { hrReviewed: boolean }): { channel: "self_service" } {
  if (!input.hrReviewed) fail("HR_APPROVAL_REQUIRED");
  return { channel: "self_service" };
}

export function approveRate(input: { effective: string; asOf: string; rate: string; submitterId: string; steps: Step[] }): ChangeDraft {
  approveSteps(input.submitterId, input.steps);
  return {
    kind: "compensation.set_rate",
    status: "draft",
    effective: input.effective,
    rate: input.rate,
    retro: compareDates(input.effective, input.asOf) < 0,
    confirm: "hr",
  };
}

export function payEquityFlags(input: {
  classes: { id: string; band: string; predominance: string; rate: string; basis: string }[];
  materialGapPct: string;
}): { flags: { femaleClassId: string; maleClassId: string; gapPct: string; basis: string }[] } {
  if (!present(input.materialGapPct)) fail("INPUT_REQUIRED", "materialGapPct");
  const flags: { femaleClassId: string; maleClassId: string; gapPct: string; basis: string }[] = [];
  for (const female of input.classes) {
    if (female.predominance !== "female") continue;
    for (const male of input.classes) {
      if (male.predominance !== "male" || male.band !== female.band) continue;
      const gap = dec(male.rate).minus(dec(female.rate)).div(dec(male.rate)).mul(HUNDRED);
      if (gap.gt(dec(input.materialGapPct))) {
        flags.push({ femaleClassId: female.id, maleClassId: male.id, gapPct: qstr(gap, "0.01"), basis: female.basis });
      }
    }
  }
  return { flags };
}

export function totalRewardsStatement(input: {
  cadence: string;
  requested: boolean;
  lang: ScreenLang;
  figures: { pay: string; cpp: string; ei: string; pension: string; benefits: string; timeOff: string };
}): { text: string } {
  if (!present(input.cadence)) fail("SETTING_NOT_SET", "statements.cadence");
  if (input.cadence === "on_request" && !input.requested) fail("STATEMENT_NOT_REQUESTED");
  const copy = screen[input.lang];
  if (copy === undefined) fail("INTERFACE_LANGUAGE_NOT_AVAILABLE");
  return { text: fill(copy.statement, input.figures) };
}

export type Statute = { code: string; status: string; threshold: number | null };

export function draftDisclosure(input: {
  statute: Statute;
  people: { id: string; paid: string; position: string }[];
  publish: boolean;
  hrApproved: boolean;
  financeApproved: boolean;
  preparerId: string;
  approverId: string;
}): { listed: { id: string; position: string }[]; published: boolean } {
  if (input.statute.threshold === null) fail("INPUT_REQUIRED", "threshold");
  const floor = dec(input.statute.threshold);
  const listed = input.people.filter((p) => dec(p.paid).gte(floor)).map((p) => ({ id: p.id, position: p.position }));
  if (!input.publish) return { listed, published: false };
  if (input.statute.status === "verify_at_load") fail("RULE_NOT_VERIFIED");
  if (input.approverId === input.preparerId) fail("SELF_APPROVAL");
  if (!input.hrApproved || !input.financeApproved) fail("DISCLOSURE_NOT_APPROVED");
  return { listed, published: true };
}

export function approvePhilosophy(input: { submitterId: string; approverId: string; executive: boolean }): { approved: boolean } {
  if (input.approverId === input.submitterId) fail("SELF_APPROVAL");
  if (!input.executive) fail("ROUTE_APPROVALS_MISSING");
  return { approved: true };
}

export function approveStructure(input: {
  marketBased: boolean;
  philosophyCoversStart: boolean;
  routeFound: boolean;
  routeHasExecutive: boolean;
  submitterId: string;
  approverId: string;
}): { approved: boolean } {
  if (!input.routeFound) fail("INPUT_REQUIRED", "route");
  if (!input.routeHasExecutive) fail("ROUTE_APPROVALS_MISSING");
  if (input.approverId === input.submitterId) fail("SELF_APPROVAL");
  if (input.marketBased && !input.philosophyCoversStart) fail("PHILOSOPHY_NOT_APPROVED");
  return { approved: true };
}

export function prepareSurveyImport(input: {
  profiles: { code: string }[];
  chosenCode?: string;
  publisherTemplate?: { code: string; sampleFile: boolean; permission: boolean } | null;
}): { profileCode: string; dryRun: true } {
  if (input.publisherTemplate) {
    if (!input.publisherTemplate.sampleFile || !input.publisherTemplate.permission) fail("INPUT_REQUIRED", "template");
    return { profileCode: input.publisherTemplate.code, dryRun: true };
  }
  if (!present(input.chosenCode)) fail("INPUT_REQUIRED", "profile");
  let found = false;
  for (const profile of input.profiles) if (profile.code === input.chosenCode) found = true;
  if (!found) fail("INPUT_REQUIRED", "profile");
  return { profileCode: String(input.chosenCode), dryRun: true };
}

export function managerPayView(input: { ratiosEnabled: boolean; restrictedSurveyInRun: boolean; marketRatio: string }): { marketRatio: string | null } {
  if (!input.ratiosEnabled || input.restrictedSurveyInRun) return { marketRatio: null };
  return { marketRatio: input.marketRatio };
}

const TRACK_RANK: Record<string, number> = { support: 1, professional: 2, management: 3, executive: 4 };

export function gradeSpread(input: { tracks: string[]; byTrack: Record<string, string>; analystOverride?: string }): string {
  if (present(input.analystOverride)) return String(input.analystOverride);
  let best: string | undefined;
  let rank = 0;
  for (const track of input.tracks) {
    if (!present(input.byTrack[track])) fail("SETTING_NOT_SET", "comp.range_spread_by_track");
    const next = TRACK_RANK[track];
    if (next === undefined) fail("INPUT_REQUIRED", track);
    if (best === undefined || next > rank) {
      rank = next;
      best = input.byTrack[track];
    }
  }
  if (best === undefined) fail("INPUT_REQUIRED", "tracks");
  return best;
}

export function locationRanges(rows: { grade: string; locationGroup: string; minimum: string; maximum: string }[]): typeof rows {
  for (const row of rows) {
    if (!present(row.locationGroup)) fail("LOCATION_GROUP_MISMATCH");
  }
  return rows;
}

export function catchUpPlan(input: { belowOn: string; months: string | null; cancelReason?: string; cancel: boolean }): { target: string | null; cancelled: boolean } {
  if (input.months === null || input.months === undefined || input.months === "") fail("SETTING_NOT_SET", "comp.catch_up_months");
  if (input.cancel) {
    if (!present(input.cancelReason)) fail("INPUT_REQUIRED", "reason");
    return { target: null, cancelled: true };
  }
  return { target: addCalendarMonths(input.belowOn, Number(input.months)), cancelled: false };
}

export function aboveMaximum(input: {
  rate: string;
  maximum: string;
  proposal?: string;
  approved: boolean;
  effective: string;
}): { flagged: boolean; cutApplied: false; changeSet: ChangeDraft | null } {
  const flagged = dec(input.rate).gt(dec(input.maximum));
  if (!flagged || !present(input.proposal) || !input.approved) {
    return { flagged, cutApplied: false, changeSet: null };
  }
  return {
    flagged,
    cutApplied: false,
    changeSet: {
      kind: "compensation.set_rate",
      status: "draft",
      effective: input.effective,
      rate: String(input.proposal),
      retro: false,
      confirm: "hr",
    },
  };
}

export function promotionRate(input: { current: string; proposed: string; newMinimum: string; minIncreasePct: string | null }): { rate: string } {
  if (input.minIncreasePct === null || input.minIncreasePct === undefined || input.minIncreasePct === "") {
    fail("SETTING_NOT_SET", "comp.promotion_min_increase_pct");
  }
  const floor = dec(input.current).mul(ONE.plus(dec(input.minIncreasePct).div(HUNDRED)));
  const least = dec(input.newMinimum).gt(floor) ? dec(input.newMinimum) : floor;
  if (dec(input.proposed).lt(least)) fail("PROMOTION_BELOW_RULE");
  return { rate: input.proposed };
}

export function demotionPay(input: { current: string; proposed: string; cautionAcknowledged: boolean; reason?: string }): { rate: string } {
  if (dec(input.proposed).lt(dec(input.current))) {
    if (!input.cautionAcknowledged) fail("CAUTION_NOT_ACKNOWLEDGED", "comp.pay_reduced_on_demotion");
    if (!present(input.reason)) fail("CAUTION_REASON_REQUIRED");
  }
  return { rate: input.proposed };
}

export function actingPay(input: {
  method: string | null;
  percent: string | null;
  current: string;
  rangeMinimum: string;
  stepsAbove: string[];
}): { rate: string } {
  if (!present(input.method)) fail("SETTING_NOT_SET", "comp.acting_pay_method");
  if (input.method === "percent_above_current") {
    if (!present(input.percent)) fail("SETTING_NOT_SET", "comp.acting_pay_percent");
    return { rate: moneyStr(dec(input.current).mul(ONE.plus(dec(input.percent).div(HUNDRED)))) };
  }
  if (input.method === "range_minimum") return { rate: input.rangeMinimum };
  if (input.method === "higher_of_both") {
    if (!present(input.percent)) fail("SETTING_NOT_SET", "comp.acting_pay_percent");
    const percentRate = dec(input.current).mul(ONE.plus(dec(input.percent).div(HUNDRED)));
    const min = dec(input.rangeMinimum);
    return { rate: moneyStr(percentRate.gt(min) ? percentRate : min) };
  }
  if (input.method === "first_step_above") {
    for (const step of input.stepsAbove) {
      if (dec(step).gt(dec(input.current))) return { rate: step };
    }
    fail("INPUT_REQUIRED", "step");
  }
  fail("INPUT_REQUIRED", "comp.acting_pay_method");
}

export function approvePayout(input: { submitterId: string; steps: Step[] }): { approved: boolean } {
  approveSteps(input.submitterId, input.steps);
  return { approved: true };
}

export function clawback(input: { signed: boolean; authorized: string; requested: string }): { recovery: string } {
  if (!input.signed) fail("CLAWBACK_NOT_SIGNED");
  if (dec(input.requested).gt(dec(input.authorized))) fail("CLAWBACK_NOT_SIGNED");
  return { recovery: input.requested };
}

export function prorateIncentive(input: { amount: string; eligibleDays: string; periodDays: string; countRule: string }): { payout: string; countRule: string } {
  if (!present(input.countRule)) fail("INPUT_REQUIRED", "countRule");
  const payout = moneyStr(dec(input.amount).mul(dec(input.eligibleDays)).div(dec(input.periodDays)));
  return { payout, countRule: input.countRule };
}

export function commissionPayout(input: {
  sales: string;
  tiers: { upTo: string | null; ratePct: string }[];
  cap: string | null;
  submitterId: string;
  steps: Step[];
}): { commission: string; approved: boolean } {
  if (input.tiers.length === 0) fail("INPUT_REQUIRED", "tiers");
  let left = dec(input.sales);
  let previous = dec(0);
  let amount = dec(0);
  for (const tier of input.tiers) {
    const top = tier.upTo === null ? null : dec(tier.upTo);
    const width = top === null ? left : top.minus(previous);
    const slice = left.lt(width) ? left : width;
    if (slice.gt(0)) amount = amount.plus(slice.mul(dec(tier.ratePct)).div(HUNDRED));
    left = left.minus(slice);
    if (top !== null) previous = top;
    if (left.lte(0)) break;
  }
  if (input.cap !== null && amount.gt(dec(input.cap))) amount = dec(input.cap);
  approveSteps(input.submitterId, input.steps);
  return { commission: moneyStr(amount), approved: true };
}

export function recordGrant(input: { planKind: string; units: string; vesting: string }): { units: string; vesting: string } {
  if (input.planKind !== "long_term") fail("LTI_PLAN_REQUIRED");
  if (!present(input.vesting)) fail("INPUT_REQUIRED", "vesting");
  return { units: input.units, vesting: input.vesting };
}

export function employeePayPage(input: {
  showPhilosophy: boolean | null;
  showOwnRange: boolean | null;
  showQuartile: boolean | null;
  showMarket: boolean | null;
  philosophy: string;
  rate: string;
  range: { minimum: string; midpoint: string; maximum: string };
  marketRate: string;
}): { philosophy: string | null; range: { minimum: string; maximum: string } | null; quartile: string | null; marketRatio: string | null } {
  if (input.showPhilosophy === null || input.showOwnRange === null || input.showQuartile === null || input.showMarket === null) {
    fail("SETTING_NOT_SET", "comp.employee_pay_view");
  }
  const metrics = payMetrics(input.rate, input.range, input.marketRate);
  return {
    philosophy: input.showPhilosophy ? input.philosophy : null,
    range: input.showOwnRange ? { minimum: input.range.minimum, maximum: input.range.maximum } : null,
    quartile: input.showQuartile ? String(metrics.quartile) : null,
    marketRatio: input.showMarket ? String(metrics.marketRatio) : null,
  };
}

export function payGap(input: {
  floor: string | null;
  minimumFloor: string;
  groups: { id: string; consented: boolean; count: number }[];
}): { shown: string[]; hidden: string[] } {
  if (!present(input.floor)) fail("SETTING_NOT_SET", "privacy.min_group_size_self_id");
  if (dec(input.floor).lt(dec(input.minimumFloor))) fail("SETTING_BELOW_MINIMUM");
  const shown: string[] = [];
  const hidden: string[] = [];
  for (const group of input.groups) {
    if (!group.consented || group.count < Number(input.floor)) hidden.push(group.id);
    else shown.push(group.id);
  }
  return { shown, hidden };
}

export function bargainScenario(input: {
  basePayroll: string;
  annualPct: string;
  years: number;
  agreementVersionId?: string;
  ratify: boolean;
}): { yearPayroll: string[]; changesPay: false } {
  const yearPayroll: string[] = [];
  let payroll = dec(input.basePayroll);
  const factor = ONE.plus(dec(input.annualPct).div(HUNDRED));
  let n = 0;
  while (n < input.years) {
    payroll = payroll.mul(factor);
    yearPayroll.push(moneyStr(payroll));
    n += 1;
  }
  if (input.ratify && !present(input.agreementVersionId)) fail("INPUT_REQUIRED", "agreementVersion");
  return { yearPayroll, changesPay: false };
}

export function positionGrade(input: { jobGrade: string; positionGrade: string }): { flag: string | null } {
  if (input.jobGrade !== input.positionGrade) return { flag: "POSITION_GRADE_DIFFERS" };
  return { flag: null };
}

export function postingRange(rows: { grade: string; minimum: string; maximum: string }[], grade: string): { minimum: string; maximum: string } {
  for (const row of rows) {
    if (row.grade === grade) return { minimum: row.minimum, maximum: row.maximum };
  }
  fail("INPUT_REQUIRED", "grade");
}
