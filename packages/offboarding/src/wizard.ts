import { draftRoe, type RoeDraft } from "./accounts.ts";
import {
  decideBenefitEnd,
  runBenefitCase,
  type BenefitResult,
  type ChangeRule,
  type Ending,
  type Enrolment,
  type JurisdictionRule,
} from "./benefits.ts";
import { finalPayItems, scheduleAccessRemoval, deathPayments, type PayItem } from "./closing.ts";
import { parseDate } from "./dates.ts";
import { money } from "./decimal.ts";
import { fail } from "./errors.ts";
import { finalPayDeadline, owed, statutoryNotice, statutorySeverance, type DeadlineRule, type NoticeRule, type Service, type SeveranceRule } from "./standards.ts";
import type { ScreenLang } from "./text.ts";

export type WizardAssignment = {
  assignmentId: string;
  personId: string;
  employmentId: string;
  payrollAccountId: string;
  leavePlanId: string;
  positionId: string;
};

export type SeparationInput = {
  personId: string;
  employmentId: string;
  reason: string;
  initiatedBy: "employer" | "employee";
  noticeDate: string;
  lastDayWorked: string;
  terminationDate: string;
  quebecWorkLocation: boolean;
  service: Service;
  serviceYears: string;
  serviceMonths: number;
  employerPayroll: string;
  qualifyingGroupTermination: boolean;
  vacationOwing: string;
  nextRegularPayDay: string;
  assignments: WizardAssignment[];
  positionHolders: readonly { positionId: string; assignmentId: string }[];
  futureChangeSetIds: readonly string[];
  notice: NoticeRule;
  severance: SeveranceRule;
  deadline: DeadlineRule;
  benefits: {
    enrolment: Enrolment;
    ending: Ending;
    rules: ChangeRule[];
    jurisdictionRules: Record<string, JurisdictionRule>;
    acknowledgement: { caution: string; reason: string } | null;
  } | null;
  finalItems: readonly PayItem[];
  recovery: { amount: string; authorization: string | null } | null;
  protectedMinimum: string;
  gross: string;
  roe: {
    reasonMap: Readonly<Record<string, string>>;
    deadlineDays: number;
    finalPayPeriodEnd: string;
    periods: readonly { number: number; amount: string; hours: string }[];
    vacation: { block: string; amount: string };
    severance: { block: string; amount: string };
    amended: boolean;
  };
  access: {
    dismissal: boolean;
    removeAt: string;
    now: string;
    equipment: readonly { id: string }[];
  };
  slipTreatment: "T4" | "estate" | null;
  screenLanguage: ScreenLang;
};

function requireText(value: string): void {
  if (value.trim() === "") fail("INPUT_REQUIRED");
}

function checkDates(input: SeparationInput): void {
  parseDate(input.noticeDate);
  parseDate(input.lastDayWorked);
  parseDate(input.terminationDate);
  requireText(input.personId);
  requireText(input.employmentId);
  requireText(input.reason);
  if (input.assignments.length === 0) fail("INPUT_REQUIRED");
}

export type SeparationPreview = {
  reason: string;
  initiatedBy: "employer" | "employee";
  noticeDate: string;
  lastDayWorked: string;
  terminationDate: string;
  notice: ReturnType<typeof statutoryNotice>;
  severance: ReturnType<typeof statutorySeverance>;
  vacationOwing: string;
  benefits: (BenefitResult | { error: string })[];
  finalPay: ReturnType<typeof finalPayDeadline>;
  blocked: boolean;
};

export function previewSeparation(input: SeparationInput): SeparationPreview {
  checkDates(input);
  const notice = statutoryNotice(input.notice, input.service, false);
  const severance = statutorySeverance({
    rule: input.severance,
    serviceYears: input.serviceYears,
    serviceMonths: input.serviceMonths,
    employerPayroll: input.employerPayroll,
    qualifyingGroupTermination: input.qualifyingGroupTermination,
    apply: false,
  });
  const finalPay = finalPayDeadline({
    rule: input.deadline,
    initiatedBy: input.initiatedBy,
    endDate: input.terminationDate,
    nextRegularPayDay: input.nextRegularPayDay,
    apply: false,
  });
  const benefits: (BenefitResult | { error: string })[] = [];
  if (input.benefits !== null) {
    benefits.push(
      runBenefitCase({
        enrolment: input.benefits.enrolment,
        ending: input.benefits.ending,
        rules: input.benefits.rules,
        jurisdictionRules: input.benefits.jurisdictionRules,
      }),
    );
  }
  return {
    reason: input.reason,
    initiatedBy: input.initiatedBy,
    noticeDate: input.noticeDate,
    lastDayWorked: input.lastDayWorked,
    terminationDate: input.terminationDate,
    notice,
    severance,
    vacationOwing: owed(input.vacationOwing),
    benefits,
    finalPay,
    blocked: notice.blocked || severance.blocked || finalPay.blocked,
  };
}

export type TerminationChangeSet = {
  id: string;
  kind: "employment.terminate";
  effectiveDate: string;
  reason: string;
  initiatedBy: "employer" | "employee";
  noticeDate: string;
  lastDayWorked: string;
  terminationDate: string;
  operations: { op: string; [key: string]: string }[];
  events: ["payroll", "benefits", "idp", "offboarding_tasks"];
  noticeWeeks: number;
  severanceWeeks: string | null;
  vacationOwing: string;
  finalPayDeadline: string | null;
  offCycleFinal: boolean;
  benefits: BenefitResult[];
  roes: RoeDraft[];
  finalItems: PayItem[];
  access: ReturnType<typeof scheduleAccessRemoval>;
  positionsVacated: string[];
  cancelChangeSetIds: string[];
  death: ReturnType<typeof deathPayments> | null;
};

export function commitSeparation(input: SeparationInput): TerminationChangeSet {
  checkDates(input);
  const notice = statutoryNotice(input.notice, input.service, true);
  const severance = statutorySeverance({
    rule: input.severance,
    serviceYears: input.serviceYears,
    serviceMonths: input.serviceMonths,
    employerPayroll: input.employerPayroll,
    qualifyingGroupTermination: input.qualifyingGroupTermination,
    apply: true,
  });
  const finalPay = finalPayDeadline({
    rule: input.deadline,
    initiatedBy: input.initiatedBy,
    endDate: input.terminationDate,
    nextRegularPayDay: input.nextRegularPayDay,
    apply: true,
  });
  const benefits: BenefitResult[] = [];
  if (input.benefits !== null) {
    const looked = runBenefitCase({
      enrolment: input.benefits.enrolment,
      ending: input.benefits.ending,
      rules: input.benefits.rules,
      jurisdictionRules: input.benefits.jurisdictionRules,
    });
    if ("error" in looked) fail(looked.error);
    benefits.push(
      decideBenefitEnd(
        input.benefits.enrolment,
        input.benefits.ending,
        input.benefits.rules,
        input.benefits.jurisdictionRules,
        input.benefits.acknowledgement,
      ),
    );
  }
  let death: ReturnType<typeof deathPayments> | null = null;
  if (input.reason === "death") death = deathPayments({ slipTreatment: input.slipTreatment, screenLanguage: input.screenLanguage });
  const items = finalPayItems({
    items: input.finalItems,
    recovery: input.recovery,
    protectedMinimum: input.protectedMinimum,
    gross: input.gross,
  });
  const endingIds = new Set(input.assignments.map((assignment) => assignment.assignmentId));
  const positionsVacated: string[] = [];
  const operations: { op: string; [key: string]: string }[] = [
    { op: "end_employment", employmentId: input.employmentId, endDate: input.terminationDate },
  ];
  for (const assignment of input.assignments) {
    operations.push({ op: "end_assignment", assignmentId: assignment.assignmentId, endDate: input.terminationDate });
    const stillHeld = input.positionHolders.some(
      (holder) => holder.positionId === assignment.positionId && !endingIds.has(holder.assignmentId),
    );
    if (!stillHeld && !positionsVacated.includes(assignment.positionId)) {
      positionsVacated.push(assignment.positionId);
      operations.push({ op: "vacate_position", positionId: assignment.positionId });
    }
  }
  const cancelChangeSetIds = input.futureChangeSetIds.slice();
  for (const changeSetId of cancelChangeSetIds) {
    operations.push({ op: "cancel_change_set", changeSetId });
  }
  if (finalPay.offCycle && finalPay.deadline !== null) {
    operations.push({ op: "schedule_off_cycle", runKind: "final", payDate: finalPay.deadline });
  }
  const accounts: string[] = [];
  for (const assignment of input.assignments) {
    if (!accounts.includes(assignment.payrollAccountId)) accounts.push(assignment.payrollAccountId);
  }
  const roes = accounts.map((payrollAccountId) =>
    draftRoe({
      payrollAccountId,
      separationReason: input.reason,
      reasonMap: input.roe.reasonMap,
      periods: input.roe.periods,
      vacation: input.roe.vacation,
      severance: input.roe.severance,
      deadlineDays: input.roe.deadlineDays,
      finalPayPeriodEnd: input.roe.finalPayPeriodEnd,
      amended: input.roe.amended,
    }),
  );
  const access = scheduleAccessRemoval(input.access);
  return {
    id: `employment.terminate:${input.employmentId}:${input.terminationDate}`,
    kind: "employment.terminate",
    effectiveDate: input.terminationDate,
    reason: input.reason,
    initiatedBy: input.initiatedBy,
    noticeDate: input.noticeDate,
    lastDayWorked: input.lastDayWorked,
    terminationDate: input.terminationDate,
    operations,
    events: ["payroll", "benefits", "idp", "offboarding_tasks"],
    noticeWeeks: notice.weeks,
    severanceWeeks: severance.weeks,
    vacationOwing: money(input.vacationOwing),
    finalPayDeadline: finalPay.deadline,
    offCycleFinal: finalPay.offCycle,
    benefits,
    roes,
    finalItems: items,
    access,
    positionsVacated,
    cancelChangeSetIds,
    death,
  };
}
