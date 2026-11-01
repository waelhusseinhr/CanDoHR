import { cmp, hours, TimeError } from "./money.ts";

const SOURCES = ["mobile", "web", "kiosk", "clock", "import", "manual"] as const;

export function roundClock(value: string, roundingMinutes: number): string {
  if (!Number.isInteger(roundingMinutes) || roundingMinutes < 0 || roundingMinutes > 15) {
    throw new TimeError("ROUNDING_MINUTES");
  }
  const match = /^(\d{2}):(\d{2})$/.exec(value);
  if (!match) throw new TimeError("TIME");
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 47 || minute > 59) throw new TimeError("TIME");
  if (roundingMinutes === 0) return value;
  const total = hour * 60 + minute;
  const rounded = Math.round(total / roundingMinutes) * roundingMinutes;
  const nextHour = Math.floor(rounded / 60);
  const nextMinute = rounded % 60;
  return `${String(nextHour).padStart(2, "0")}:${String(nextMinute).padStart(2, "0")}`;
}

export function clockToMinutes(value: string): number {
  const match = /^(\d{2}):(\d{2})$/.exec(value);
  if (!match) throw new TimeError("TIME");
  return Number(match[1]) * 60 + Number(match[2]);
}

export function workedShift(input: {
  punches: { at: string; kind: "in" | "out" | "break_start" | "break_end" }[];
  roundingMinutes: number;
  unpaidBreakHours: string;
  breakConfirmed: boolean;
}): { start: string; end: string; paidHours: string; flags: string[] } {
  const startPunch = input.punches.find((punch) => punch.kind === "in");
  const endPunch = input.punches.find((punch) => punch.kind === "out");
  if (!startPunch || !endPunch) throw new TimeError("INPUT_REQUIRED");
  const start = roundClock(startPunch.at, input.roundingMinutes);
  const end = roundClock(endPunch.at, input.roundingMinutes);
  const span = clockToMinutes(end) - clockToMinutes(start);
  if (span < 0) throw new TimeError("TIME");
  let paidMinutes = span;
  const breakStart = input.punches.find((punch) => punch.kind === "break_start");
  const breakEnd = input.punches.find((punch) => punch.kind === "break_end");
  const punched = Boolean(breakStart && breakEnd);
  const flags: string[] = [];
  if (punched && breakStart && breakEnd) {
    paidMinutes -= clockToMinutes(roundClock(breakEnd.at, input.roundingMinutes)) - clockToMinutes(roundClock(breakStart.at, input.roundingMinutes));
  } else if (input.breakConfirmed) {
    paidMinutes -= Math.round(Number(input.unpaidBreakHours) * 60);
  } else if (cmp(hours(input.unpaidBreakHours), "0.00") > 0) {
    flags.push("unconfirmed_break");
  }
  return {
    start,
    end,
    paidHours: hours(String(paidMinutes / 60)),
    flags,
  };
}

export function capturePunch(input: {
  source: "mobile" | "web" | "kiosk" | "clock" | "import" | "manual" | "biometric";
  geofence: boolean;
  inside?: boolean;
  coordinates?: { lat: string; lng: string };
}): { source: string; geoOk?: boolean } {
  if (input.source === "biometric") throw new TimeError("NO_BIOMETRICS");
  if (!SOURCES.includes(input.source)) throw new TimeError("INPUT_REQUIRED");
  const result: { source: string; geoOk?: boolean } = { source: input.source };
  if (input.geofence) {
    if (input.inside === undefined) throw new TimeError("INPUT_REQUIRED");
    result.geoOk = input.inside;
  }
  return result;
}

export function unapprovedOvertime(extraHours: string): {
  paidHours: string;
  flags: ["unapproved_overtime"];
  notices: { when: "sameDay" | "beforePayroll"; to: string[] }[];
} {
  return {
    paidHours: hours(extraHours),
    flags: ["unapproved_overtime"],
    notices: [
      { when: "sameDay", to: ["manager"] },
      { when: "beforePayroll", to: ["manager", "hr"] },
    ],
  };
}

export function markNotAuthorized(reason?: string): { paid: true; reason: string } {
  if (!reason || reason.trim() === "") throw new TimeError("INPUT_REQUIRED");
  return { paid: true, reason };
}

export function correctPunch(reason?: string): { paid: true; employeeNotified: true; canDispute: true; reason: string } {
  if (!reason || reason.trim() === "") throw new TimeError("INPUT_REQUIRED");
  return { paid: true, employeeNotified: true, canDispute: true, reason };
}
