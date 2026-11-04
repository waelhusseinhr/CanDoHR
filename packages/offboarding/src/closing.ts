import { addDays } from "./dates.ts";
import { D, money } from "./decimal.ts";
import { fail } from "./errors.ts";
import { fill, screen, type ScreenLang } from "./text.ts";

export type PayItem = {
  code: string;
  amount: string;
  workStart: string;
  workEnd: string;
  kind: string;
  rrspDirectTransfer?: boolean;
};

export function finalPayItems(input: {
  items: readonly PayItem[];
  recovery: { amount: string; authorization: string | null } | null;
  protectedMinimum: string;
  gross: string;
}): PayItem[] {
  const items = input.items.map((item) => ({
    code: item.code,
    amount: money(item.amount),
    workStart: item.workStart,
    workEnd: item.workEnd,
    kind: item.kind,
    rrspDirectTransfer: item.rrspDirectTransfer === true,
  }));
  if (input.recovery === null) return items;
  if (input.recovery.authorization === null || input.recovery.authorization.trim() === "") fail("INPUT_REQUIRED");
  const amount = new D(input.recovery.amount);
  const authorization = new D(input.recovery.authorization);
  if (amount.gt(authorization)) fail("RECOVERY_EXCEEDS_AUTHORIZATION");
  const net = new D(input.gross).minus(amount);
  if (net.lt(new D(input.protectedMinimum))) fail("RECOVERY_BELOW_PROTECTED_MINIMUM");
  items.push({
    code: "recovery",
    amount: money(input.recovery.amount),
    workStart: "",
    workEnd: "",
    kind: "recovery",
    rrspDirectTransfer: false,
  });
  return items;
}

export type GroupRule = {
  status: string;
  cite?: string;
  thresholds: { count: number; within_weeks: number } | null;
};

export function groupTerminations(input: {
  rule: GroupRule;
  establishmentId: string;
  endings: readonly { establishmentId: string; date: string }[];
  asOf: string;
  proposed: number;
  apply: boolean;
}): {
  count: number | null;
  threshold: number | null;
  windowStart: string | null;
  warn: boolean;
  ministryForm: { "en-CA": string; "fr-CA": string } | null;
  status: string;
  cite: string;
  blocked: boolean;
} {
  const cite = input.rule.cite === undefined ? "" : input.rule.cite;
  if (input.rule.thresholds === null || input.rule.thresholds === undefined) {
    if (input.apply) fail("RULE_NOT_VERIFIED");
    return {
      count: null,
      threshold: null,
      windowStart: null,
      warn: false,
      ministryForm: null,
      status: input.rule.status,
      cite,
      blocked: true,
    };
  }
  if (input.apply && input.rule.status === "verify_at_load") fail("RULE_NOT_VERIFIED");
  const windowStart = addDays(input.asOf, -input.rule.thresholds.within_weeks * 7);
  let count = 0;
  for (const ending of input.endings) {
    if (ending.establishmentId === input.establishmentId && ending.date >= windowStart && ending.date <= input.asOf) {
      count += 1;
    }
  }
  const warn = count + input.proposed >= input.rule.thresholds.count;
  const ministryForm = warn
    ? { "en-CA": screen["en-CA"].groupNotice, "fr-CA": screen["fr-CA"].groupNotice }
    : null;
  return {
    count,
    threshold: input.rule.thresholds.count,
    windowStart,
    warn,
    ministryForm,
    status: input.rule.status,
    cite,
    blocked: input.rule.status === "verify_at_load",
  };
}

export type LayoffRule = {
  status: string;
  cite?: string;
  max_weeks: number | null;
  within_weeks?: number | null;
};

export function recordLayoff(input: {
  rule: LayoffRule;
  startDate: string;
  expectedRecallDate: string;
  asOf: string;
  alertLeadDays: number;
  separationReason: string;
  reasonMap: Readonly<Record<string, string>>;
  apply: boolean;
}): {
  expectedRecallDate: string;
  deemedOn: string | null;
  alert: boolean;
  deemedReached: boolean;
  roeReasonCode: string | null;
  status: string;
  cite: string;
  blocked: boolean;
} {
  const cite = input.rule.cite === undefined ? "" : input.rule.cite;
  const reasonCode = input.reasonMap[input.separationReason];
  if (reasonCode === undefined || reasonCode.trim() === "") fail("REASON_UNMAPPED");
  if (input.expectedRecallDate.trim() === "") fail("INPUT_REQUIRED");
  if (input.rule.max_weeks === null || input.rule.max_weeks === undefined) {
    if (input.apply) fail("RULE_NOT_VERIFIED");
    return {
      expectedRecallDate: input.expectedRecallDate,
      deemedOn: null,
      alert: false,
      deemedReached: false,
      roeReasonCode: reasonCode,
      status: input.rule.status,
      cite,
      blocked: true,
    };
  }
  if (input.apply && input.rule.status === "verify_at_load") fail("RULE_NOT_VERIFIED");
  const deemedOn = addDays(input.startDate, input.rule.max_weeks * 7);
  const alertFrom = addDays(deemedOn, -input.alertLeadDays);
  const deemedReached = input.asOf >= deemedOn;
  const alert = input.asOf >= alertFrom && input.asOf < deemedOn;
  return {
    expectedRecallDate: input.expectedRecallDate,
    deemedOn,
    alert,
    deemedReached,
    roeReasonCode: reasonCode,
    status: input.rule.status,
    cite,
    blocked: input.rule.status === "verify_at_load",
  };
}

export type BumpPosition = {
  positionId: string;
  incumbentSeniority: string | null;
  requiredQualifications: readonly string[];
  grouping: string;
};

export function bumpingOptions(input: {
  employeeSeniority: string;
  qualifications: readonly string[];
  grouping: string;
  positions: readonly BumpPosition[];
}): { positionId: string; vacant: boolean; incumbentSeniority: string | null }[] {
  const seniority = new D(input.employeeSeniority);
  const matched: { positionId: string; vacant: boolean; incumbentSeniority: string | null }[] = [];
  for (const position of input.positions) {
    if (position.grouping !== input.grouping) continue;
    let qualified = true;
    for (const required of position.requiredQualifications) {
      if (!input.qualifications.includes(required)) qualified = false;
    }
    if (!qualified) continue;
    if (position.incumbentSeniority === null) {
      matched.push({ positionId: position.positionId, vacant: true, incumbentSeniority: null });
      continue;
    }
    if (seniority.gt(new D(position.incumbentSeniority))) {
      matched.push({
        positionId: position.positionId,
        vacant: false,
        incumbentSeniority: position.incumbentSeniority,
      });
    }
  }
  matched.sort((left, right) => {
    if (left.vacant !== right.vacant) return left.vacant ? -1 : 1;
    if (left.incumbentSeniority === null || right.incumbentSeniority === null) return 0;
    const leftSeniority = new D(left.incumbentSeniority);
    const rightSeniority = new D(right.incumbentSeniority);
    if (leftSeniority.lt(rightSeniority)) return -1;
    if (leftSeniority.gt(rightSeniority)) return 1;
    return 0;
  });
  return matched;
}

export function recordBump(input: {
  positionId: string;
  offerDate: string;
  response: "accepted" | "declined" | "pending";
  recallDays: number;
}): { positionId: string; offerDate: string; response: string; recallExpiry: string } {
  if (!Number.isInteger(input.recallDays) || input.recallDays < 0) fail("DATE");
  return {
    positionId: input.positionId,
    offerDate: input.offerDate,
    response: input.response,
    recallExpiry: addDays(input.offerDate, input.recallDays),
  };
}

/** structural: PLAT-013 AC2 platform timing bound, not an organization setting. */
const ACCESS_BOUND_MS = 5 * 60 * 1000;

function instant(value: string): number {
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) fail("DATE");
  return parsed;
}

export function scheduleAccessRemoval(input: {
  dismissal: boolean;
  removeAt: string;
  now: string;
  equipment: readonly { id: string }[];
}): {
  removeAt: string;
  removed: boolean;
  late: boolean;
  assetTasks: { equipmentId: string; "en-CA": string; "fr-CA": string }[];
} {
  const assetTasks = input.equipment.map((item) => ({
    equipmentId: item.id,
    "en-CA": fill(screen["en-CA"].assetTask, { id: item.id }),
    "fr-CA": fill(screen["fr-CA"].assetTask, { id: item.id }),
  }));
  if (input.dismissal) {
    return { removeAt: input.now, removed: true, late: false, assetTasks };
  }
  const removeAt = instant(input.removeAt);
  const now = instant(input.now);
  const removed = now >= removeAt;
  const late = removed && now - removeAt > ACCESS_BOUND_MS;
  return { removeAt: input.removeAt, removed, late, assetTasks };
}

export function deathPayments(input: {
  slipTreatment: "T4" | "estate" | null;
  screenLanguage: ScreenLang;
}): { payee: "estate"; slipTreatment: "T4" | "estate"; benefitsClaim: true; template: string } {
  if (input.slipTreatment === null) fail("INPUT_REQUIRED");
  return {
    payee: "estate",
    slipTreatment: input.slipTreatment,
    benefitsClaim: true,
    template: screen[input.screenLanguage].bereavement,
  };
}

export function terminationDocument(input: {
  kind: "letter" | "release" | "reference";
  screenLanguage: ScreenLang;
  quebecWorkLocation: boolean;
  terminationDate: string;
}): { language: ScreenLang; text: string } {
  if (input.quebecWorkLocation && input.screenLanguage !== "fr-CA") fail("FRENCH_REQUIRED_FOR_QUEBEC");
  return {
    language: input.screenLanguage,
    text: fill(screen[input.screenLanguage][input.kind], { date: input.terminationDate }),
  };
}
