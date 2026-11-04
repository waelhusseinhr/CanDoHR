import { addMonths, shiftDays } from "./dates.ts";
import { RecruitError } from "./errors.ts";
import { noticeThresholdDate, type StandardsBundle } from "./standards.ts";
import { cautionCleared, type Acknowledgement, type Caution } from "./routes.ts";

export type Probation = {
  id: string;
  measure: "calendar_months" | "calendar_days" | "hours" | "shifts";
  requiredAmount: number;
  extendedBy: number;
  startedOn: string;
  status: "in_progress" | "extended" | "passed" | "failed";
  kind: string;
};

export type CheckPoint = { from: "start" | "end"; days: number };

export function calendarEnd(probation: Probation): string {
  if (probation.measure !== "calendar_months" && probation.measure !== "calendar_days") throw new RecruitError("PROBATION_MEASURE_COUNTED");
  const total = probation.requiredAmount + probation.extendedBy;
  if (!Number.isInteger(total)) throw new RecruitError("PROBATION_AMOUNT_NOT_WHOLE");
  if (probation.measure === "calendar_months") return shiftDays(addMonths(probation.startedOn, total), -1);
  return shiftDays(probation.startedOn, total - 1);
}

export function checkInDates(probation: Probation, points: CheckPoint[]): { dueOn: string; basis: CheckPoint }[] {
  const ends = calendarEnd(probation);
  return points.map((point) => ({
    dueOn: point.from === "start" ? shiftDays(probation.startedOn, point.days) : shiftDays(ends, -point.days),
    basis: point,
  }));
}

export function remindersDue(endsOn: string, asOf: string, days: number[]): { daysLeft: number } | null {
  const daysLeft = daysBetween(asOf, endsOn);
  if (!days.includes(daysLeft)) return null;
  return { daysLeft };
}

function daysBetween(earlier: string, later: string): number {
  const start = Date.parse(`${earlier}T00:00:00Z`);
  const end = Date.parse(`${later}T00:00:00Z`);
  return Math.round((end - start) / 86_400_000);
}

export function leaveCaution(input: {
  endsOn: string;
  reminderDays: number[];
  leaveFrom: string;
  leaveTo: string;
  holidays: { date: string; name: string; statutory: boolean }[];
  holidayCalendarPresent: boolean;
}): { cautionCode: "probation.leave_near_end"; endsOn: string; holidays: { date: string; name: string }[] } | null {
  if (!input.holidayCalendarPresent) throw new RecruitError("HOLIDAY_CALENDAR_MISSING");
  const first = Math.max(...input.reminderDays);
  const windowFrom = shiftDays(input.endsOn, -first);
  const overlaps = input.leaveTo >= windowFrom && input.leaveFrom <= input.endsOn;
  if (!overlaps) return null;
  const holidays = input.holidays.filter((holiday) => holiday.statutory && holiday.date >= windowFrom && holiday.date <= input.endsOn);
  return { cautionCode: "probation.leave_near_end", endsOn: input.endsOn, holidays };
}

export function closeLapsed(probation: Probation, asOf: string): { status: "passed"; endedOn: string; hrTold: true; fallback: "FB-034"; event: "probation.lapsed_passed" } | null {
  if (probation.status !== "in_progress" && probation.status !== "extended") return null;
  const ends = calendarEnd(probation);
  if (ends >= asOf) return null;
  return { status: "passed", endedOn: ends, hrTold: true, fallback: "FB-034", event: "probation.lapsed_passed" };
}

export function confirmationLetter(usesLetter: boolean): { send: boolean } {
  return { send: usesLetter };
}

export type Extension = {
  amount: number;
  reason: string;
  notifiedOn?: string;
  approved: boolean;
  agreementMaximum?: number;
  organizationMaximum?: { amount: number; measure: string } | null;
  caution?: Acknowledgement;
  cautionDef?: Caution;
};

export function applyExtension(bundle: StandardsBundle, probation: Probation, extension: Extension, jurisdiction: string): Probation {
  if (probation.status !== "in_progress" && probation.status !== "extended") throw new RecruitError("PROBATION_NOT_OPEN");
  if (!extension.approved) throw new RecruitError("EXTENSION_NOT_APPROVED");
  if (!extension.notifiedOn) throw new RecruitError("EXTENSION_NOT_COMMUNICATED");
  if (extension.reason.trim() === "") throw new RecruitError("INPUT_REQUIRED");
  const ends = probation.measure === "calendar_months" || probation.measure === "calendar_days" ? calendarEnd(probation) : undefined;
  if (ends && extension.notifiedOn > ends) throw new RecruitError("EXTENSION_AFTER_END");
  const total = probation.extendedBy + extension.amount;
  const cap = extension.organizationMaximum ?? (extension.agreementMaximum === undefined ? null : { amount: extension.agreementMaximum, measure: probation.measure });
  if (cap && cap.measure !== probation.measure) throw new RecruitError("EXTENSION_MEASURE_DIFFERS");
  if (cap && total > cap.amount) throw new RecruitError("EXTENSION_ABOVE_MAXIMUM");
  const next = { ...probation, extendedBy: total, status: "extended" as const };
  if (ends) {
    const newEnd = calendarEnd(next);
    const threshold = noticeThresholdDate(bundle, jurisdiction, probation.startedOn);
    const definition = extension.cautionDef;
    if (newEnd > threshold && (!definition || !cautionCleared(definition, extension.caution))) {
      throw new RecruitError("CAUTION_NOT_ACKNOWLEDGED");
    }
  }
  return next;
}

export type Matter = { source: "case" | "closed_case" | "leave"; refId: string; category: string; respondentPersonId?: string };

export function openMatters(input: {
  cases: { id: string; category: string; openedOn: string; closedOn?: string; roles: string[]; respondentPersonId?: string }[];
  leaves: { id: string; status: string; until: string }[];
  asOf: string;
  lookbackMonths: number;
}): Matter[] {
  const threshold = addMonths(input.asOf, -input.lookbackMonths);
  const cases = input.cases.filter((row) => {
    if (row.openedOn > input.asOf) return false;
    if (!row.roles.some((role) => role === "subject" || role === "complainant")) return false;
    if (!row.closedOn || row.closedOn > input.asOf) return true;
    return row.closedOn > threshold;
  }).map((row) => ({
    source: !row.closedOn || row.closedOn > input.asOf ? "case" as const : "closed_case" as const,
    refId: row.id,
    category: row.category,
    respondentPersonId: row.respondentPersonId,
  }));
  const leaves = input.leaves.filter((leave) => ["requested", "approved", "taken"].includes(leave.status) && leave.until >= input.asOf)
    .map((leave) => ({ source: "leave" as const, refId: leave.id, category: "leave" }));
  return [...cases, ...leaves];
}

export function mattersForViewer(matters: Matter[], viewerPersonId: string, viewerIsHr: boolean): { detail: Matter[] } | { message: "HR review required" } | { detail: [] } {
  if (viewerIsHr) return { detail: matters };
  if (matters.some((matter) => matter.respondentPersonId === viewerPersonId)) return { message: "HR review required" };
  return { detail: [] };
}

export function approveEnding(matters: Matter[], hrAcknowledged: boolean): void {
  if (matters.length > 0 && !hrAcknowledged) throw new RecruitError("OPEN_CASES_NOT_REVIEWED");
}
