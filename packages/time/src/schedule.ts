import { cmp, TimeError } from "./money.ts";

export function scheduleConflicts(shifts: { id: string; personId: string; assignmentId: string; start: string; end: string }[]): {
  shiftIds: [string, string];
  assignmentIds: [string, string];
}[] {
  const conflicts: { shiftIds: [string, string]; assignmentIds: [string, string] }[] = [];
  for (let left = 0; left < shifts.length; left += 1) {
    for (let right = left + 1; right < shifts.length; right += 1) {
      const a = shifts[left];
      const b = shifts[right];
      if (a.personId === b.personId && a.start < b.end && b.start < a.end) {
        conflicts.push({ shiftIds: [a.id, b.id], assignmentIds: [a.assignmentId, b.assignmentId] });
      }
    }
  }
  return conflicts;
}

export function publishShift(input: {
  restBreach?: { article: string };
  cautionReason?: string;
  credential?: "ok" | "law_required" | "not_ready";
  learningReason?: string;
}): { published: true; caution?: "time.rest_or_hours_limit" | "learning.not_ready_for_work"; article?: string } {
  if (input.credential === "law_required") throw new TimeError("CREDENTIAL_REQUIRED");
  if (input.credential === "not_ready" && (!input.learningReason || input.learningReason.trim() === "")) {
    throw new TimeError("CAUTION_NOT_ACKNOWLEDGED");
  }
  if (input.restBreach && (!input.cautionReason || input.cautionReason.trim() === "")) {
    throw new TimeError("CAUTION_NOT_ACKNOWLEDGED");
  }
  if (input.restBreach) {
    return { published: true, caution: "time.rest_or_hours_limit", article: input.restBreach.article };
  }
  if (input.credential === "not_ready") return { published: true, caution: "learning.not_ready_for_work" };
  return { published: true };
}

export function noticeHours(input: { regulatory?: "federal" | "other"; kind: "schedule" | "change"; agreementHours?: string }): string {
  if (input.regulatory === "federal" && input.kind === "schedule") return "96.00";
  if (input.regulatory === "federal" && input.kind === "change") return "24.00";
  return input.agreementHours ?? "336.00";
}

export function assessScheduleNotice(input: {
  regulatory: "federal" | "other";
  kind: "schedule" | "change";
  hoursAhead: string;
  agreementHours?: string;
}): { noticeHours: string; employeeMayRefuse: boolean; needsCaution: boolean } {
  const notice = noticeHours(input);
  const inside = cmp(input.hoursAhead, notice) < 0;
  return {
    noticeHours: notice,
    employeeMayRefuse: input.regulatory === "federal" && input.kind === "schedule" && inside,
    needsCaution: inside,
  };
}

export function changePublishedShift(input: {
  hoursUntilStart: string;
  noticeHours: string;
  cautionReason?: string;
  approvedSwap?: boolean;
}): { applied: true; caution?: "time.schedule_changed_late" } {
  const inside = cmp(input.hoursUntilStart, input.noticeHours) < 0;
  if (inside && !input.approvedSwap && (!input.cautionReason || input.cautionReason.trim() === "")) {
    throw new TimeError("CAUTION_NOT_ACKNOWLEDGED");
  }
  if (inside && !input.approvedSwap) return { applied: true, caution: "time.schedule_changed_late" };
  return { applied: true };
}

export type OfferCandidate = { id: string; extraHours: string; seniorityDate: string; rotationIndex: number };

export function offerExtraShift(input: {
  union: boolean;
  method?: "seniority" | "rotation" | "equal_hours";
  candidates: OfferCandidate[];
  managerChoice?: string;
}): { offeredTo: string; order: string[]; log: { personId: string; response: "offered" }[] } {
  if (input.candidates.length === 0) throw new TimeError("INPUT_REQUIRED");
  if (!input.union) {
    const order = [...input.candidates].sort((left, right) => cmp(left.extraHours, right.extraHours) || left.id.localeCompare(right.id)).map((person) => person.id);
    if (!input.managerChoice) throw new TimeError("INPUT_REQUIRED");
    return { offeredTo: input.managerChoice, order, log: [{ personId: input.managerChoice, response: "offered" }] };
  }
  if (!input.method) throw new TimeError("INPUT_REQUIRED");
  const ordered = [...input.candidates].sort((left, right) => {
    if (input.method === "seniority") return left.seniorityDate.localeCompare(right.seniorityDate);
    if (input.method === "rotation") return left.rotationIndex - right.rotationIndex;
    return cmp(left.extraHours, right.extraHours);
  });
  const offeredTo = ordered[0].id;
  return {
    offeredTo,
    order: ordered.map((person) => person.id),
    log: ordered.map((person) => ({ personId: person.id, response: "offered" as const })),
  };
}

export function approveShiftSwap(input: {
  colleagueAgreed: boolean;
  checksPassed: boolean;
  approverId: string;
  employeeIds: string[];
  insideNotice: boolean;
}): { applied: true; withinNotice: boolean } {
  if (!input.colleagueAgreed) throw new TimeError("SHIFT_SWAP_NOT_AGREED");
  if (!input.checksPassed) throw new TimeError("SHIFT_SWAP_CHECKS_FAILED");
  if (input.employeeIds.includes(input.approverId)) throw new TimeError("SELF_APPROVAL");
  return { applied: true, withinNotice: input.insideNotice };
}

export type RotationKind = "fixed" | "rotating" | "dupont" | "platoon" | "compressed" | "split" | "on_call";

const ROTATIONS: Record<RotationKind, number[]> = {
  fixed: [1, 1, 1, 1, 1, 0, 0],
  rotating: [1, 1, 1, 0, 0, 1, 1],
  dupont: [1, 1, 1, 1, 0, 0, 0],
  platoon: [1, 1, 0, 0],
  compressed: [1, 1, 1, 0, 0, 0, 0],
  split: [1, 0, 1, 0, 1, 0, 0],
  on_call: [1, 1, 1, 1, 1, 1, 1],
};

export function buildRotation(kind: RotationKind, days: number): number[] {
  const pattern = ROTATIONS[kind];
  return Array.from({ length: days }, (_, index) => pattern[index % pattern.length]);
}

export function applyTemplate(template: { name: string; shifts: { day: number; start: string; end: string }[] }, weekStart: string): { name: string; date: string; start: string; end: string }[] {
  return template.shifts.map((shift) => ({
    name: template.name,
    date: addDays(weekStart, shift.day),
    start: shift.start,
    end: shift.end,
  }));
}

export function autoFill(input: {
  openShifts: { id: string; start: string; end: string; requiredQualification: string }[];
  people: { id: string; qualifications: string[]; seniority: string; unavailable: string[]; extraHours: string }[];
}): { shiftId: string; personId: string }[] {
  const assigned: { shiftId: string; personId: string; start: string; end: string }[] = [];
  const ranked = [...input.people].sort((left, right) => left.seniority.localeCompare(right.seniority) || cmp(left.extraHours, right.extraHours));
  for (const shift of input.openShifts) {
    const person = ranked.find((candidate) => {
      if (!candidate.qualifications.includes(shift.requiredQualification)) return false;
      if (candidate.unavailable.includes(shift.start.slice(0, 10))) return false;
      return !assigned.some((item) => item.personId === candidate.id && item.start < shift.end && shift.start < item.end);
    });
    if (person) assigned.push({ shiftId: shift.id, personId: person.id, start: shift.start, end: shift.end });
  }
  return assigned.map((item) => ({ shiftId: item.shiftId, personId: item.personId }));
}

export function aidesRequired(residents: number, residentsPerAide: number): number {
  if (residentsPerAide <= 0) throw new TimeError("INPUT_REQUIRED");
  return Math.ceil(residents / residentsPerAide);
}

export function awardBids(input: { shifts: string[]; people: { id: string; seniority: string; picks: string[] }[] }): { shiftId: string; personId: string }[] {
  const remaining = new Set(input.shifts);
  const awards: { shiftId: string; personId: string }[] = [];
  const people = [...input.people].sort((left, right) => left.seniority.localeCompare(right.seniority));
  for (const person of people) {
    const pick = person.picks.find((shift) => remaining.has(shift));
    if (!pick) continue;
    remaining.delete(pick);
    awards.push({ shiftId: pick, personId: person.id });
  }
  return awards;
}

export function acceptSelfSchedule(days: { date: string; minimum: number; onDuty: number; requestingOff: boolean }[]): { accepted: boolean } {
  return { accepted: days.every((day) => !day.requestingOff || day.onDuty - 1 >= day.minimum) };
}

export function postOpenShift(shiftId: string): { shiftId: string; status: "open" } {
  return { shiftId, status: "open" };
}

function addDays(isoDate: string, days: number): string {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}
