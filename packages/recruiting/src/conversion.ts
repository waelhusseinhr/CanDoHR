import { cmp, mul, sum } from "@candohr/disbursement";
import { addMonths, shiftDays } from "./dates.ts";
import { RecruitError } from "./errors.ts";
import { cautionCleared, type Acknowledgement, type Caution, type WorkflowRoute } from "./routes.ts";

export type ConversionRule = {
  id: string;
  fromTypes: string[];
  toType: string;
  windowMonths: number;
  measuredOverWeeks: number;
  averageHoursMin: string;
  sameGrouping: boolean;
  countsLeaves: string[];
  createsPosition: boolean;
  precedence?: number;
};

export type ServiceWeek = {
  weekStart: string;
  groupingId: string;
  scheduledHours: string;
  leaveHours: string;
  leaveKind: string | null;
};

export function evaluateConversion(rules: ConversionRule[], weeks: ServiceWeek[], asOf: string, employmentType: string, serviceStart: string): {
  proposed: boolean;
  leaveCounted: boolean;
  createsPosition: boolean;
  ruleId?: string;
  toType?: string;
} {
  if (rules.length === 0) throw new RecruitError("CONVERSION_THRESHOLDS_OFF");
  const applicable = rules.filter((rule) => rule.fromTypes.includes(employmentType));
  if (applicable.length > 1 && applicable.some((rule) => rule.precedence === undefined)) throw new RecruitError("UNRESOLVED_INTERACTION");
  const rule = [...applicable].sort((left, right) => precedenceOf(left) - precedenceOf(right))[0];
  if (!rule) return { proposed: false, leaveCounted: false, createsPosition: false };
  if (asOf < addMonths(serviceStart, rule.windowMonths)) return { proposed: false, leaveCounted: false, createsPosition: false };
  const ordered = [...weeks].sort((left, right) => left.weekStart.localeCompare(right.weekStart));
  if (ordered.length < rule.measuredOverWeeks) return { proposed: false, leaveCounted: false, createsPosition: false };
  let index = 1;
  while (index < ordered.length) {
    if (ordered[index].weekStart !== shiftDays(ordered[index - 1].weekStart, 7)) {
      return { proposed: false, leaveCounted: false, createsPosition: false };
    }
    index += 1;
  }
  if (rule.sameGrouping && new Set(ordered.map((week) => week.groupingId)).size > 1) {
    return { proposed: false, leaveCounted: false, createsPosition: false };
  }
  let leaveCounted = false;
  let windowIndex = 0;
  while (windowIndex <= ordered.length - rule.measuredOverWeeks) {
    const window = ordered.slice(windowIndex, windowIndex + rule.measuredOverWeeks);
    const hours = window.map((week) => {
      const counts = week.leaveKind !== null && rule.countsLeaves.includes(week.leaveKind);
      if (counts && cmp(week.leaveHours, "0.00") > 0) leaveCounted = true;
      return counts ? sum([week.scheduledHours, week.leaveHours]) : week.scheduledHours;
    });
    const minimum = mul(rule.averageHoursMin, String(rule.measuredOverWeeks));
    if (cmp(sum(hours), minimum) < 0) return { proposed: false, leaveCounted, createsPosition: false };
    windowIndex += 1;
  }
  return { proposed: true, leaveCounted, createsPosition: rule.createsPosition, ruleId: rule.id, toType: rule.toType };
}

function precedenceOf(rule: ConversionRule): number {
  if (rule.precedence === undefined) return 0;
  return rule.precedence;
}

export function approveConversion(proposed: { createsPosition: boolean; toType?: string }, positionId: string): {
  changeSet: { source: "conversion"; operations: { type: string; positionId?: string; toType?: string }[] };
} {
  const operations: { type: string; positionId?: string; toType?: string }[] = [];
  if (proposed.createsPosition) operations.push({ type: "position.create", positionId });
  operations.push({ type: "status_conversion", toType: proposed.toType });
  return { changeSet: { source: "conversion", operations } };
}

export function requestConversion(startedBy: "manager_request" | "threshold" | "agreement", route: WorkflowRoute | undefined, requestedBy?: string): { startedBy: string; routeId?: string } {
  if (startedBy === "manager_request" && !requestedBy) throw new RecruitError("INPUT_REQUIRED");
  if (!route) throw new RecruitError("ROUTE_NOT_FOUND");
  return { startedBy, routeId: route.id };
}

export function declineAgreementConversion(caution: Caution | undefined, acknowledgement: Acknowledgement | undefined): void {
  if (acknowledgement && acknowledgement.reason.trim() === "") throw new RecruitError("CAUTION_REASON_REQUIRED");
  if (!caution || !cautionCleared(caution, acknowledgement)) throw new RecruitError("CAUTION_NOT_ACKNOWLEDGED");
}

export function flagAgreementConversion(clause: string): { startedBy: "agreement"; ruleSource: string; event: "status_conversion.flagged" } {
  return { startedBy: "agreement", ruleSource: clause, event: "status_conversion.flagged" };
}
