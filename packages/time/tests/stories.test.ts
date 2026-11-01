import assert from "node:assert/strict";
import test from "node:test";
import {
  acceptSelfSchedule,
  aidesRequired,
  applyTemplate,
  approveShiftSwap,
  approveTimesheet,
  assertLeaveProtection,
  assessScheduleNotice,
  autoFill,
  awardBids,
  buildRotation,
  capturePunch,
  carryOverHours,
  changePublishedShift,
  classifyWeek,
  clockToMinutes,
  composeBlock,
  correctLockedPeriod,
  correctPunch,
  declineLeave,
  employeeConfirmation,
  employerHolidayPay,
  escalateTimesheet,
  evaluateActing,
  greaterLeaveDays,
  holidaysFor,
  issueAttendanceStage,
  leaveBalance,
  leavePlanFor,
  leaveVisibility,
  lockUnapprovedTimesheet,
  longAbsencePrompt,
  markNotAuthorized,
  noticeHours,
  offerExtraShift,
  openLongLeave,
  planCycleStart,
  postOpenShift,
  publishShift,
  recordAveraging,
  recordExemption,
  recordSickNote,
  recordingMethodFor,
  requestAgainstBalance,
  requestBankedPayout,
  reviewAfterLock,
  roundClock,
  scheduleConflicts,
  settleAveragingCycle,
  settleBankedTime,
  splitLeaveRequest,
  statutoryVacationTopUp,
  teamAvailability,
  terminationPayout,
  tierStepDate,
  TimeError,
  unapprovedOvertime,
  validateCarryOver,
  workedShift,
  type DaySlice,
  type Jurisdiction,
} from "../src/index.ts";

function throwsCode(run: () => unknown, code: string): void {
  assert.throws(run, (error: unknown) => {
    assert.ok(error instanceof TimeError);
    assert.equal(error.code, code);
    return true;
  });
}

function jurisdiction(overrides: Partial<Jurisdiction> & Pick<Jurisdiction, "code" | "daily" | "weeklyAfter">): Jurisdiction {
  return {
    weeklyMultiplier: "1.50",
    greaterOfDailyOrWeekly: false,
    rateBasis: "regular",
    multiRate: "rate_for_work_performed",
    dailyOvertimeCountsTowardWeekly: false,
    ...overrides,
  };
}

function day(date: string, hours: string, rate = "30.00", assignmentId = "A"): DaySlice {
  return { date, assignmentId, hours, rate };
}

test("TIME-001 overtime by jurisdiction and agreement, with a rule source on every line", () => {
  const bc = classifyWeek({
    slices: [day("2026-06-02", "13.00")],
    jurisdiction: jurisdiction({
      code: "BC",
      daily: [
        { after: "8.00", multiplier: "1.50" },
        { after: "12.00", multiplier: "2.00" },
      ],
      weeklyAfter: "40.00",
    }),
  });
  assert.equal(bc.lines.find((line) => line.payCode === "REG")?.hours, "8.00");
  assert.equal(bc.lines.find((line) => line.payCode === "OT15")?.hours, "4.00");
  assert.equal(bc.lines.find((line) => line.payCode === "OT20")?.hours, "1.00");
  assert.ok(bc.lines.every((line) => line.ruleSource.includes("ES:BC")));

  const alberta = classifyWeek({
    slices: ["2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04"].map((date) => day(date, "10.00")),
    jurisdiction: jurisdiction({
      code: "AB",
      daily: [{ after: "8.00", multiplier: "1.50" }],
      weeklyAfter: "44.00",
      greaterOfDailyOrWeekly: true,
    }),
  });
  assert.equal(alberta.paidOvertimeHours, "8.00");
  assert.equal(alberta.lines.filter((line) => line.payCode === "OT15").reduce((sum, line) => sum + Number(line.hours), 0).toFixed(2), "8.00");

  const ontario = classifyWeek({
    slices: ["2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04", "2026-06-05"].map((date) => day(date, "9.50")),
    jurisdiction: jurisdiction({ code: "ON", daily: [], weeklyAfter: "44.00" }),
  });
  assert.equal(ontario.paidOvertimeHours, "3.50");
  assert.ok(ontario.lines.some((line) => line.ruleSource.includes("weekly")));

  const agreed = classifyWeek({
    slices: ["2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04", "2026-06-05"].map((date) => day(date, "9.50")),
    jurisdiction: jurisdiction({ code: "ON", daily: [], weeklyAfter: "44.00" }),
    agreements: [{ assignmentId: "A", dailyAfter: "7.00", dailyMultiplier: "1.50", source: "7-hour day" }],
  });
  assert.equal(agreed.statuteOvertimeHours, "3.50");
  assert.equal(agreed.paidOvertimeHours, "12.50");
  assert.equal(agreed.greaterRight, "agreement");
  assert.ok(agreed.lines.every((line) => line.ruleSource.includes("agreement:")));

  const nb = classifyWeek({
    slices: ["2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04", "2026-06-05"].map((date) => day(date, "10.00", "30.00")),
    jurisdiction: jurisdiction({
      code: "NB",
      daily: [],
      weeklyAfter: "44.00",
      rateBasis: "minimum_wage",
      minimumWage: "15.00",
    }),
  });
  const nbOvertime = nb.lines.filter((line) => line.payCode === "OT15");
  assert.equal(nbOvertime.reduce((sum, line) => sum + Number(line.hours), 0).toFixed(2), "6.00");
  assert.ok(nbOvertime.every((line) => line.rateBasis === "minimum_wage" && line.rate === "15.00"));
  assert.equal(nbOvertime.reduce((sum, line) => sum + Number(line.amount), 0).toFixed(2), "135.00");
  assert.ok(nb.lines.filter((line) => line.payCode === "REG").every((line) => line.rate === "30.00"));
  assert.ok(nb.lines.every((line) => line.ruleSource.length > 0));
});

test("TIME-002 rounding is the same up and down and is not systematically low", () => {
  assert.equal(roundClock("08:02", 5), "08:00");
  assert.equal(roundClock("08:03", 5), "08:05");
  throwsCode(() => roundClock("08:00", 16), "ROUNDING_MINUTES");
  let delta = 0;
  let seed = 20260601;
  const next = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 4294967296;
  };
  for (let index = 0; index < 10000; index += 1) {
    const interval = [5, 6, 10, 15][index % 4];
    const start = Math.floor(next() * (12 * 60));
    const duration = 60 + Math.floor(next() * 480);
    const end = start + duration;
    const roundedStart = clockToMinutes(roundClock(toClock(start), interval));
    const roundedEnd = clockToMinutes(roundClock(toClock(end), interval));
    delta += roundedEnd - roundedStart - duration;
  }
  assert.ok(delta / 10000 >= -0.05);
});

test("TIME-003 and TIME-021 a meal break is deducted only when punched or confirmed", () => {
  const open = workedShift({
    punches: [
      { at: "08:00", kind: "in" },
      { at: "16:00", kind: "out" },
    ],
    roundingMinutes: 0,
    unpaidBreakHours: "0.50",
    breakConfirmed: false,
  });
  assert.equal(open.paidHours, "8.00");
  assert.deepEqual(open.flags, ["unconfirmed_break"]);

  const confirmed = workedShift({
    punches: [
      { at: "08:00", kind: "in" },
      { at: "16:00", kind: "out" },
    ],
    roundingMinutes: 0,
    unpaidBreakHours: "0.50",
    breakConfirmed: true,
  });
  assert.equal(confirmed.paidHours, "7.50");
  assert.deepEqual(confirmed.flags, []);

  const punched = workedShift({
    punches: [
      { at: "08:00", kind: "in" },
      { at: "12:00", kind: "break_start" },
      { at: "12:30", kind: "break_end" },
      { at: "16:00", kind: "out" },
    ],
    roundingMinutes: 0,
    unpaidBreakHours: "0.50",
    breakConfirmed: false,
  });
  assert.equal(punched.paidHours, "7.50");
  assert.deepEqual(punched.flags, []);
});

test("TIME-004 employees confirm, unapproved sheets escalate, and the cut-off does not stop pay", () => {
  const waiting = employeeConfirmation(false);
  assert.equal(waiting.reminders, true);
  assert.equal(waiting.payrollProceeds, true);
  const escalated = escalateTimesheet({
    approved: false,
    workingDaysWaiting: 3,
    escalateAfter: 2,
    beforeCutoff: true,
    nextManagerId: "manager-2",
  });
  assert.equal(escalated.escalateTo, "manager-2");
  const locked = lockUnapprovedTimesheet();
  assert.equal(locked.locked, true);
  assert.equal(locked.paidAsRecorded, true);
  assert.equal(reviewAfterLock("manager-1").reviewedAfterLockBy, "manager-1");
});

test("TIME-005 a locked Tuesday corrected from 8 to 10 hours is a retro line dated Tuesday", () => {
  const correction = correctLockedPeriod({
    date: "2026-06-02",
    fromHours: "8.00",
    toHours: "10.00",
    rate: "30.00",
    lawDeadlineInDays: 14,
    nextRegularInDays: 7,
  });
  assert.equal(correction.originalEdited, false);
  assert.equal(correction.run, "next_regular");
  assert.deepEqual(correction.retroLines, [
    { date: "2026-06-02", hours: "2.00", amount: "60.00", ruleSource: "time.corrected" },
  ]);
});

test("TIME-006 schedules show conflicts, rest cautions, offers, and the launch scheduling tools", () => {
  const conflicts = scheduleConflicts([
    { id: "s1", personId: "jordan", assignmentId: "A1", start: "2026-06-02T08:00", end: "2026-06-02T16:00" },
    { id: "s2", personId: "jordan", assignmentId: "A2", start: "2026-06-02T15:00", end: "2026-06-02T20:00" },
  ]);
  assert.deepEqual(conflicts[0].assignmentIds, ["A1", "A2"]);
  throwsCode(() => publishShift({ restBreach: { article: "art. 12" } }), "CAUTION_NOT_ACKNOWLEDGED");
  const published = publishShift({ restBreach: { article: "art. 12" }, cautionReason: "emergency coverage" });
  assert.equal(published.caution, "time.rest_or_hours_limit");
  assert.equal(published.article, "art. 12");
  throwsCode(() => publishShift({ credential: "law_required", cautionReason: "short" }), "CREDENTIAL_REQUIRED");
  assert.deepEqual(buildRotation("dupont", 7), [1, 1, 1, 1, 0, 0, 0]);
  assert.equal(buildRotation("on_call", 3).every((day) => day === 1), true);
  const filled = autoFill({
    openShifts: [{ id: "open-1", start: "2026-06-03T08:00", end: "2026-06-03T16:00", requiredQualification: "care" }],
    people: [
      { id: "new", qualifications: ["care"], seniority: "2024-01-01", unavailable: [], extraHours: "0.00" },
      { id: "senior", qualifications: ["care"], seniority: "2010-01-01", unavailable: [], extraHours: "4.00" },
    ],
  });
  assert.equal(filled[0].personId, "senior");
  assert.equal(aidesRequired(10, 4), 3);
  assert.deepEqual(awardBids({
    shifts: ["day", "night"],
    people: [
      { id: "junior", seniority: "2020-01-01", picks: ["day"] },
      { id: "senior", seniority: "2010-01-01", picks: ["day", "night"] },
    ],
  })[0], { shiftId: "day", personId: "senior" });
  assert.equal(acceptSelfSchedule([{ date: "2026-06-04", minimum: 2, onDuty: 2, requestingOff: true }]).accepted, false);
  assert.equal(postOpenShift("open-9").status, "open");
  assert.equal(applyTemplate({ name: "days", shifts: [{ day: 1, start: "08:00", end: "16:00" }] }, "2026-06-01")[0].date, "2026-06-02");
  assert.equal(noticeHours({ kind: "schedule" }), "336.00");
});

test("TIME-007 a balance on a future date includes accruals scheduled before it", () => {
  const entries = [
    { date: "2026-01-01", hours: "40.00", kind: "opening" as const },
    { date: "2026-06-01", hours: "8.00", kind: "accrual" as const },
    { date: "2026-07-01", hours: "4.00", kind: "taken" as const },
    { date: "2026-08-01", hours: "8.00", kind: "accrual" as const },
  ];
  assert.equal(leaveBalance(entries, "2026-05-01"), "40.00");
  assert.equal(leaveBalance(entries, "2026-07-15"), "44.00");
  assert.equal(leaveBalance(entries, "2026-08-01"), "52.00");
});

test("TIME-008 the greater leave right is the agreement or the statute", () => {
  const richer = greaterLeaveDays({ agreementDays: "5", statuteDays: "3", agreementSource: "agreement", statuteSource: "statute" });
  assert.equal(richer.days, "5.00");
  assert.equal(richer.source, "agreement");
  const floor = greaterLeaveDays({ agreementDays: "2", statuteDays: "3", agreementSource: "agreement", statuteSource: "statute" });
  assert.equal(floor.days, "3.00");
  assert.equal(floor.source, "statute");
});

test("TIME-009 protected absences never count, and HR reviews discipline", () => {
  throwsCode(() => issueAttendanceStage({
    programEnabled: false,
    stage: 1,
    disciplinary: false,
    accommodationConsidered: false,
    hrReviewed: false,
    openedBy: "manager",
  }), "ATTENDANCE_PROGRAM_OFF");
  for (const category of ["disability", "medical", "domestic_violence", "workers_compensation"]) {
    throwsCode(() => issueAttendanceStage({
      programEnabled: true,
      category,
      stage: 1,
      disciplinary: false,
      accommodationConsidered: true,
      hrReviewed: true,
      openedBy: "manager",
      reviewerId: "hr",
    }), "ATTENDANCE_PROTECTED_ABSENCE");
  }
  throwsCode(() => issueAttendanceStage({
    programEnabled: true,
    statutory: true,
    category: "unexcused",
    stage: 1,
    disciplinary: false,
    accommodationConsidered: true,
    hrReviewed: true,
    openedBy: "manager",
    reviewerId: "hr",
  }), "ATTENDANCE_PROTECTED_ABSENCE");
});

test("TIME-010 holiday calendars follow the location and a federal employer", () => {
  const calendar = [
    { name: "Nunavut Day", monthDay: "07-09", jurisdiction: "NU" },
    { name: "National Day for Truth and Reconciliation", monthDay: "09-30", jurisdiction: "FED" },
  ];
  assert.deepEqual(holidaysFor({ year: 2026, locationJurisdiction: "NU", regulatory: "provincial", calendar }), [
    { name: "Nunavut Day", date: "2026-07-09", jurisdiction: "NU" },
  ]);
  assert.deepEqual(holidaysFor({ year: 2026, locationJurisdiction: "ON", regulatory: "federal", calendar }), [
    { name: "National Day for Truth and Reconciliation", date: "2026-09-30", jurisdiction: "FED" },
  ]);
  assert.equal(holidaysFor({ year: 2026, locationJurisdiction: "NU", regulatory: "federal", calendar }).length, 2);
});

test("TIME-011 starting parental leave opens the long-leave case", () => {
  const leave = openLongLeave("parental");
  assert.equal(leave.statusChange, true);
  assert.equal(leave.roeTrigger, true);
  assert.equal(leave.benefitsContinuationChoice, true);
  assert.equal(leave.seniorityContinuation, true);
  assert.equal(leave.returnToWorkTask, true);
});

test("TIME-012 geofencing stores only inside or outside, and biometrics are refused", () => {
  const off = capturePunch({ source: "mobile", geofence: false, coordinates: { lat: "45", lng: "-75" } });
  assert.equal("geoOk" in off, false);
  assert.equal("coordinates" in off, false);
  throwsCode(() => capturePunch({ source: "biometric", geofence: false }), "NO_BIOMETRICS");
});

test("TIME-013 premiums, holidays, exclusive groups, the weekly flag, and an open combination", () => {
  const night = composeBlock({
    hours: "9.00",
    straightHours: "7.00",
    rate: "30.85",
    holiday: false,
    overtimeMultiplier: "1.50",
    premiums: [{ code: "NIGHT", perHour: "1.75", article: "16.02" }],
    stacking: "sum_premiums",
  });
  assert.equal(night.lines.find((line) => line.payCode === "REG")?.amount, "215.95");
  assert.equal(night.lines.filter((line) => line.payCode === "NIGHT").map((line) => line.amount).join("+"), "12.25+3.50");
  assert.equal(night.lines.find((line) => line.payCode === "OT15")?.amount, "92.55");
  assert.equal(night.total, "324.25");

  const holiday = composeBlock({
    hours: "9.00",
    straightHours: "7.00",
    rate: "30.85",
    holiday: true,
    stacking: "sum_premiums",
  });
  assert.equal(holiday.lines[0].amount, "323.93");
  assert.equal(holiday.lines[1].amount, "123.40");
  assert.equal(holiday.total, "447.33");

  const exclusive = composeBlock({
    hours: "2.00",
    straightHours: "2.00",
    rate: "30.85",
    holiday: false,
    premiums: [
      { code: "EVENING", perHour: "2.00", article: "16.03" },
      { code: "NIGHT", perHour: "1.75", article: "16.03" },
    ],
    stacking: "sum_premiums",
    exclusiveGroups: [{ codes: ["EVENING", "NIGHT"], article: "16.03" }],
  });
  assert.equal(exclusive.lines.find((line) => line.payCode === "EVENING")?.amount, "4.00");
  assert.equal(exclusive.lines.some((line) => line.payCode === "NIGHT"), false);
  assert.ok(exclusive.lines.some((line) => line.ruleSource.includes("exclusive")));

  const base = {
    slices: [...Array(4).fill(0).map((_, index) => day(`2026-06-0${index + 1}`, "12.00")), day("2026-06-05", "8.00")],
    agreements: [],
  };
  const excluded = classifyWeek({
    ...base,
    jurisdiction: jurisdiction({
      code: "RULE",
      daily: [{ after: "8.00", multiplier: "1.50" }],
      weeklyAfter: "40.00",
      dailyOvertimeCountsTowardWeekly: false,
    }),
  });
  const included = classifyWeek({
    ...base,
    jurisdiction: jurisdiction({
      code: "RULE",
      daily: [{ after: "8.00", multiplier: "1.50" }],
      weeklyAfter: "40.00",
      dailyOvertimeCountsTowardWeekly: true,
    }),
  });
  assert.equal(excluded.weeklyCountedHours, "40.00");
  assert.equal(excluded.lines.filter((line) => line.ruleSource.includes("weekly")).reduce((sum, line) => sum + Number(line.hours), 0), 0);
  assert.equal(included.weeklyCountedHours, "56.00");
  assert.equal(included.lines.filter((line) => line.ruleSource.includes("weekly")).reduce((sum, line) => sum + Number(line.hours), 0).toFixed(2), "12.00");

  throwsCode(() => composeBlock({
    hours: "9.00",
    straightHours: "7.00",
    rate: "30.85",
    holiday: true,
  }), "UNRESOLVED_INTERACTION");
  throwsCode(() => approveTimesheet({
    employeeId: "employee",
    approverId: "manager",
    overtimeHours: "2.00",
    unresolvedInteraction: true,
  }), "UNRESOLVED_INTERACTION");
});

test("TIME-014 and TIME-022 unapproved overtime is flagged and still paid", () => {
  const flagged = unapprovedOvertime("1.50");
  assert.equal(flagged.paidHours, "1.50");
  assert.deepEqual(flagged.flags, ["unapproved_overtime"]);
  assert.deepEqual(flagged.notices[0], { when: "sameDay", to: ["manager"] });
  assert.deepEqual(flagged.notices[1], { when: "beforePayroll", to: ["manager", "hr"] });
});

test("TIME-015 and TIME-040 the team bar is a level only, and a decline needs a reason", () => {
  assert.deepEqual(Object.keys(teamAvailability({ minimum: 2, away: 0, teamSize: 5, blackout: false })), ["level"]);
  assert.equal(teamAvailability({ minimum: 2, away: 0, teamSize: 5, blackout: false }).level, "green");
  assert.equal(teamAvailability({ minimum: 2, away: 1, teamSize: 4, blackout: false }).level, "amber");
  const red = teamAvailability({ minimum: 1, away: 2, teamSize: 3, blackout: false });
  assert.equal(red.level, "red");
  assert.equal(JSON.stringify(red).includes("name"), false);
  assert.equal(teamAvailability({ away: 0, teamSize: 3, blackout: false }).level, "unknown");
  throwsCode(() => declineLeave({ statutory: false, category: "staffing" }), "INPUT_REQUIRED");
  assert.equal(declineLeave({ statutory: false, category: "staffing", reason: "coverage" }).declined, true);
});

test("TIME-016 and TIME-037 each plan keeps its own year and tier date", () => {
  assert.equal(planCycleStart({ yearBasis: "calendar", on: "2026-08-01" }), "2026-01-01");
  assert.equal(planCycleStart({ yearBasis: "fiscal", on: "2026-08-01", fiscalMonthDay: "04-01" }), "2026-04-01");
  assert.equal(planCycleStart({ yearBasis: "plan_entry", on: "2026-08-01", planEntryDate: "2024-05-20" }), "2026-05-20");
  assert.equal(planCycleStart({ yearBasis: "plan_entry", on: "2024-05-20", planEntryDate: "2024-05-20" }), "2024-05-20");
  assert.equal(tierStepDate({ basis: "service", on: "2026-08-01", serviceDate: "2019-11-02" }), "2025-11-02");
  throwsCode(() => planCycleStart({ yearBasis: "plan_entry", on: "2026-08-01" }), "INPUT_REQUIRED");
  throwsCode(() => leavePlanFor([
    { code: "IO", priority: 1 },
    { code: "PT", priority: 1 },
  ]), "LEAVE_PLAN_AMBIGUOUS");
  assert.equal(leavePlanFor([{ code: "IO", priority: 1 }, { code: "PT", priority: 2 }]).code, "IO");
});

test("TIME-017 protected leave hides the reason, and a sick note is never stored", () => {
  const manager = leaveVisibility({
    category: "domestic_violence",
    leaveType: "domestic violence",
    reason: "private detail",
    audience: "manager",
  });
  assert.equal(manager.label, "protected leave");
  assert.equal(manager.reason, undefined);
  assert.equal(leaveVisibility({
    category: "domestic_violence",
    leaveType: "domestic violence",
    reason: "private detail",
    audience: "hr",
  }).reason, "private detail");
  assert.equal(leaveVisibility({
    category: "vacation",
    leaveType: "vacation",
    reason: "trip",
    audience: "coworker",
  }).label, "away");
  assert.equal(leaveVisibility({
    category: "domestic_violence",
    leaveType: "domestic violence",
    reason: "private detail",
    audience: "manager",
    protectedCategories: [],
  }).label, "protected leave");
  throwsCode(() => assertLeaveProtection({ category: "domestic_violence", protected: false }), "LEAVE_REASON_MUST_BE_PROTECTED");
  throwsCode(() => recordSickNote(), "SICK_NOTE_NOT_ALLOWED");
  const ordinary = leaveVisibility({ category: "vacation", leaveType: "vacation", reason: "trip", audience: "manager" });
  assert.equal(ordinary.label, "vacation");
});

test("TIME-020 punches at 07:58 and 16:03 stay exact, then round to 08:00 and 16:05", () => {
  assert.equal(roundClock("07:58", 0), "07:58");
  assert.equal(roundClock("16:03", 0), "16:03");
  assert.equal(roundClock("07:58", 5), "08:00");
  assert.equal(roundClock("16:03", 5), "16:05");
});

test("TIME-023 not authorized needs a reason and stays paid", () => {
  throwsCode(() => markNotAuthorized(), "INPUT_REQUIRED");
  assert.equal(markNotAuthorized("not approved in advance").paid, true);
  throwsCode(() => correctPunch(), "INPUT_REQUIRED");
  const corrected = correctPunch("missed punch-out");
  assert.equal(corrected.employeeNotified, true);
  assert.equal(corrected.canDispute, true);
  assert.equal(corrected.paid, true);
});

test("TIME-024 a mobile punch with location on keeps only inside or outside", () => {
  const punch = capturePunch({ source: "mobile", geofence: true, inside: true, coordinates: { lat: "45.4", lng: "-75.7" } });
  assert.deepEqual(punch, { source: "mobile", geoOk: true });
});

test("TIME-025 and TIME-026 a rest breach blocks approval and publishing until the caution has a reason", () => {
  throwsCode(() => approveTimesheet({
    employeeId: "employee",
    approverId: "manager",
    overtimeHours: "0.00",
    restOrHoursBreach: true,
  }), "CAUTION_NOT_ACKNOWLEDGED");
  assert.equal(approveTimesheet({
    employeeId: "employee",
    approverId: "manager",
    overtimeHours: "0.00",
    restOrHoursBreach: true,
    cautionReason: "call-in",
  }).approved, true);
  throwsCode(() => publishShift({ restBreach: { article: "art. 12" } }), "CAUTION_NOT_ACKNOWLEDGED");
  assert.equal(publishShift({ restBreach: { article: "art. 12" }, cautionReason: "storm" }).published, true);
});

test("TIME-027 an averaging arrangement needs its document and end, and two at once conflict", () => {
  throwsCode(() => recordAveraging({ positionId: "p", kind: "written_agreement" }), "INPUT_REQUIRED");
  throwsCode(() => recordAveraging({ positionId: "p", kind: "written_agreement", documentId: "doc" }), "INPUT_REQUIRED");
  assert.equal(recordAveraging({
    positionId: "p",
    kind: "collective_agreement",
    agreementName: "IO",
  }).endDate, undefined);
  throwsCode(() => recordAveraging({
    positionId: "p",
    kind: "collective_agreement",
    agreementName: "IO",
    alreadyCovered: true,
  }), "AVERAGING_CONFLICT");
});

test("TIME-028 a BC house manager exemption needs its legal basis", () => {
  const catalogue = { BC: ["BC_MANAGER"], ON: ["ON_SUPERVISORY_MANAGERIAL"], FED: ["FED_MANAGER"] };
  const saved = recordExemption({ jurisdiction: "BC", code: "BC_MANAGER", legalBasis: "ESA s.34", reason: "house manager", catalogue });
  assert.equal(saved.code, "BC_MANAGER");
  assert.equal(saved.legalBasis, "ESA s.34");
  throwsCode(() => recordExemption({ jurisdiction: "BC", code: "BC_MANAGER", catalogue }), "INPUT_REQUIRED");
  throwsCode(() => recordExemption({ jurisdiction: "ZZ", code: "BC_MANAGER", legalBasis: "x", reason: "y", catalogue }), "JURISDICTION_RULE_MISSING");
  const exempt = classifyWeek({
    slices: [day("2026-06-01", "50.00", "20.00")],
    jurisdiction: jurisdiction({ code: "BC", daily: [{ after: "8.00", multiplier: "1.50" }], weeklyAfter: "40.00" }),
    exempt: { code: "BC_MANAGER" },
  });
  assert.equal(exempt.paidOvertimeHours, "0.00");
  assert.equal(exempt.lines[0].amount, "1000.00");
  assert.equal(exempt.lines[0].ruleSource, "exemption:BC_MANAGER");
});

test("TIME-029 the organization's recording rule wins, and no base pay stops", () => {
  assert.equal(recordingMethodFor({ payBasis: "hourly" }), "punches");
  assert.equal(recordingMethodFor({ payBasis: "salary" }), "exceptions");
  assert.equal(recordingMethodFor({ payBasis: "salary", orgRule: "timesheet" }), "timesheet");
  throwsCode(() => recordingMethodFor({}), "INPUT_REQUIRED");
});

test("TIME-030 nobody approves their own timesheet", () => {
  throwsCode(() => approveTimesheet({ employeeId: "employee", approverId: "employee", overtimeHours: "1.00" }), "SELF_APPROVAL");
  throwsCode(() => approveTimesheet({
    employeeId: "employee",
    approverId: "manager",
    overtimeHours: "8.00",
    route: { minOvertimeHours: "8.00", secondApproverId: "employee", secondApproved: true },
  }), "SELF_APPROVAL");
});

test("TIME-031 a second approval applies only where the route says so", () => {
  throwsCode(() => approveTimesheet({
    employeeId: "employee",
    approverId: "manager",
    overtimeHours: "8.00",
    route: { minOvertimeHours: "8.00", secondApproverId: "hr" },
  }), "ROUTE_APPROVALS_MISSING");
  assert.equal(approveTimesheet({
    employeeId: "employee",
    approverId: "manager",
    overtimeHours: "7.50",
    route: { minOvertimeHours: "8.00", secondApproverId: "hr" },
  }).approved, true);
  assert.equal(approveTimesheet({
    employeeId: "employee",
    approverId: "manager",
    overtimeHours: "10.00",
  }).approved, true);
});

test("TIME-032 an unapproved timesheet at the cut-off is locked and paid as recorded", () => {
  const locked = lockUnapprovedTimesheet();
  assert.equal(locked.paidAsRecorded, true);
  assert.equal(locked.reviewedAfterLockBy, null);
  assert.equal(reviewAfterLock("manager").reviewedAfterLockBy, "manager");
});

test("TIME-033 six missed hours due in two days are proposed off-cycle", () => {
  const urgent = correctLockedPeriod({
    date: "2026-06-03",
    fromHours: "0.00",
    toHours: "6.00",
    rate: "20.00",
    lawDeadlineInDays: 2,
    nextRegularInDays: 7,
  });
  assert.equal(urgent.run, "off_cycle");
  assert.equal(urgent.retroLines[0].hours, "6.00");
  const ordinary = correctLockedPeriod({
    date: "2026-06-03",
    fromHours: "0.00",
    toHours: "6.00",
    rate: "200.00",
    lawDeadlineInDays: 14,
    nextRegularInDays: 7,
    aboveAmount: "",
  });
  assert.equal(ordinary.run, "next_regular");
});

test("TIME-034 payroll proceeds when the employee has not confirmed", () => {
  const pending = employeeConfirmation(false);
  assert.equal(pending.reminders, true);
  assert.equal(pending.payrollProceeds, true);
  assert.equal(pending.employeeConfirmedAt, null);
});

test("TIME-035 carry-over must be a known kind, and vacation cannot pay out nothing", () => {
  throwsCode(() => validateCarryOver("sometimes"), "LEAVE_CARRYOVER_INVALID");
  throwsCode(() => carryOverHours({ balance: "40.00", statutoryHours: "20.00", mode: "limited" }), "LEAVE_CARRYOVER_INVALID");
  throwsCode(() => terminationPayout({ category: "vacation", payout: "none" }), "LEAVE_PAYOUT_BELOW_LAW");
  assert.equal(carryOverHours({ balance: "80.00", statutoryHours: "40.00", mode: "none" }), "40.00");
  assert.equal(carryOverHours({ balance: "80.00", statutoryHours: "40.00", mode: "limited", limitHours: "10.00" }), "50.00");
});

test("TIME-036 new plans take the starter payout, and an unlisted category must say its own", () => {
  assert.equal(terminationPayout({ category: "sick" }), "none");
  assert.equal(terminationPayout({ category: "vacation" }), "all");
  throwsCode(() => terminationPayout({ category: "union_business" }), "INPUT_REQUIRED");
});

test("TIME-038 a request past the balance is refused unless the plan allows a negative limit", () => {
  throwsCode(() => requestAgainstBalance({ available: "8.00", requested: "10.00" }), "LEAVE_BALANCE_INSUFFICIENT");
  assert.equal(requestAgainstBalance({ available: "0.00", requested: "16.00", negativeLimitHours: "16.00" }).balanceAfter, "-16.00");
  throwsCode(() => requestAgainstBalance({ available: "0.00", requested: "17.00", negativeLimitHours: "16.00" }), "LEAVE_BALANCE_INSUFFICIENT");
});

test("TIME-039 parental leave is never declined for staffing or a blackout", () => {
  throwsCode(() => declineLeave({ statutory: true, category: "staffing", reason: "short" }), "STATUTORY_LEAVE_NOT_REFUSABLE");
  throwsCode(() => declineLeave({ statutory: true, category: "blackout", reason: "peak" }), "STATUTORY_LEAVE_NOT_REFUSABLE");
});

test("TIME-041 a manager sees protected leave, HR sees the reason, and co-workers see away", () => {
  assert.equal(leaveVisibility({
    category: "domestic_violence",
    leaveType: "domestic violence",
    reason: "not for the manager",
    audience: "manager",
  }).label, "protected leave");
  assert.equal(leaveVisibility({
    category: "domestic_violence",
    leaveType: "domestic violence",
    reason: "not for the manager",
    audience: "hr",
  }).reason, "not for the manager");
  assert.equal(leaveVisibility({
    category: "domestic_violence",
    leaveType: "domestic violence",
    reason: "not for the manager",
    audience: "coworker",
  }).label, "away");
});

test("TIME-042 the sixth consecutive working day prompts HR", () => {
  assert.equal(longAbsencePrompt(5).promptHr, false);
  assert.equal(longAbsencePrompt(6).promptHr, true);
});

test("TIME-043 attendance refuses protected time, a later stage without accommodation, and discipline without HR", () => {
  throwsCode(() => issueAttendanceStage({
    programEnabled: true,
    protectedReason: true,
    category: "unexcused",
    stage: 1,
    disciplinary: false,
    accommodationConsidered: true,
    hrReviewed: true,
    openedBy: "manager",
    reviewerId: "hr",
  }), "ATTENDANCE_PROTECTED_ABSENCE");
  throwsCode(() => issueAttendanceStage({
    programEnabled: true,
    category: "unexcused",
    stage: 2,
    disciplinary: true,
    accommodationConsidered: false,
    hrReviewed: true,
    openedBy: "manager",
    reviewerId: "hr",
  }), "ACCOMMODATION_NOT_CONSIDERED");
  throwsCode(() => issueAttendanceStage({
    programEnabled: true,
    category: "unexcused",
    stage: 1,
    disciplinary: true,
    accommodationConsidered: true,
    hrReviewed: false,
    openedBy: "manager",
  }), "HR_REVIEW_REQUIRED");
  assert.equal(issueAttendanceStage({
    programEnabled: true,
    category: "unexcused",
    stage: 2,
    disciplinary: true,
    accommodationConsidered: true,
    hrReviewed: true,
    openedBy: "manager",
    reviewerId: "hr",
  }).issued, true);
});

test("TIME-044 a shift tomorrow needs the late-change caution, and a shift in 60 days moves freely", () => {
  throwsCode(() => changePublishedShift({ hoursUntilStart: "24.00", noticeHours: "336.00" }), "CAUTION_NOT_ACKNOWLEDGED");
  assert.equal(changePublishedShift({ hoursUntilStart: "24.00", noticeHours: "336.00", cautionReason: "coverage" }).caution, "time.schedule_changed_late");
  const later = changePublishedShift({ hoursUntilStart: "1440.00", noticeHours: "336.00" });
  assert.equal(later.applied, true);
  assert.equal(later.caution, undefined);
});

test("TIME-045 a federal schedule published three days ahead may be refused", () => {
  const notice = assessScheduleNotice({ regulatory: "federal", kind: "schedule", hoursAhead: "72.00" });
  assert.equal(notice.noticeHours, "96.00");
  assert.equal(notice.employeeMayRefuse, true);
  assert.equal(notice.needsCaution, true);
});

test("TIME-046 extra shifts show fewest hours for non-union staff and the agreement order for union staff", () => {
  const people = [
    { id: "ada", extraHours: "10.00", seniorityDate: "2012-01-01", rotationIndex: 2 },
    { id: "bo", extraHours: "2.00", seniorityDate: "2018-01-01", rotationIndex: 0 },
    { id: "cy", extraHours: "5.00", seniorityDate: "2010-01-01", rotationIndex: 1 },
  ];
  const nonUnion = offerExtraShift({ union: false, candidates: people, managerChoice: "cy" });
  assert.deepEqual(nonUnion.order, ["bo", "cy", "ada"]);
  assert.equal(nonUnion.log[0].personId, "cy");
  const union = offerExtraShift({ union: true, method: "seniority", candidates: people });
  assert.equal(union.offeredTo, "cy");
  assert.equal(union.log.length, people.length);
  assert.equal(offerExtraShift({ union: true, method: "equal_hours", candidates: people }).offeredTo, "bo");
});

test("TIME-047 a swap waits for the colleague and cannot be approved by either employee", () => {
  throwsCode(() => approveShiftSwap({
    colleagueAgreed: false,
    checksPassed: true,
    approverId: "manager",
    employeeIds: ["a", "b"],
    insideNotice: true,
  }), "SHIFT_SWAP_NOT_AGREED");
  throwsCode(() => approveShiftSwap({
    colleagueAgreed: true,
    checksPassed: false,
    approverId: "manager",
    employeeIds: ["a", "b"],
    insideNotice: false,
  }), "SHIFT_SWAP_CHECKS_FAILED");
  throwsCode(() => approveShiftSwap({
    colleagueAgreed: true,
    checksPassed: true,
    approverId: "b",
    employeeIds: ["a", "b"],
    insideNotice: true,
  }), "SELF_APPROVAL");
  const approved = approveShiftSwap({
    colleagueAgreed: true,
    checksPassed: true,
    approverId: "manager",
    employeeIds: ["a", "b"],
    insideNotice: true,
  });
  assert.equal(approved.applied, true);
  assert.equal(approved.withinNotice, true);
});

test("ENT-006 a leave across two assignments splits, and one decline is partial", () => {
  const request = splitLeaveRequest({
    assignments: [
      { id: "A1", approverId: "manager-a" },
      { id: "A2", approverId: "manager-b" },
    ],
    decisions: [
      { assignmentId: "A1", declined: false },
      { assignmentId: "A2", declined: true },
    ],
  });
  assert.equal(request.components.length, 2);
  assert.deepEqual(request.components.map((component) => component.approverId), ["manager-a", "manager-b"]);
  assert.equal(request.status, "partially_approved");
});

test("ENT-008 statutory overtime across one employer lands on the assignment that crossed 44", () => {
  const week = classifyWeek({
    slices: [
      day("2026-06-01", "10.00", "40.00", "A1"),
      day("2026-06-02", "10.00", "40.00", "A1"),
      day("2026-06-03", "10.00", "40.00", "A1"),
      day("2026-06-04", "8.00", "20.00", "A2"),
      day("2026-06-05", "8.00", "20.00", "A2"),
    ],
    jurisdiction: jurisdiction({ code: "ON", daily: [], weeklyAfter: "44.00" }),
    agreements: [
      { assignmentId: "A1", dailyAfter: "12.00", source: "IO" },
      { assignmentId: "A2", dailyAfter: "12.00", source: "PT" },
    ],
  });
  assert.equal(week.agreementsChecked, true);
  assert.equal(week.greaterRight, "statute");
  assert.equal(week.paidOvertimeHours, "2.00");
  const overtime = week.lines.filter((line) => line.payCode === "OT15");
  assert.equal(overtime.length, 1);
  assert.equal(overtime[0].assignmentId, "A2");
  assert.equal(overtime[0].hours, "2.00");
  assert.equal(overtime[0].rate, "20.00");
  assert.equal(overtime[0].amount, "60.00");
  assert.ok(overtime[0].ruleSource.includes("ES:ON"));
});

test("ENT-009 an unverified multi-rate rule stops the timesheet", () => {
  throwsCode(() => classifyWeek({
    slices: [
      day("2026-06-01", "30.00", "40.00", "A1"),
      day("2026-06-04", "16.00", "20.00", "A2"),
    ],
    jurisdiction: jurisdiction({ code: "ON", daily: [], weeklyAfter: "44.00", multiRate: "verify_at_load" }),
  }), "RULE_NOT_VERIFIED");
  throwsCode(() => approveTimesheet({
    employeeId: "jordan",
    approverId: "manager",
    overtimeHours: "2.00",
    multiRateUnverified: true,
  }), "RULE_NOT_VERIFIED");
});

test("ENT-010 acting pay starts from day one once one full day is worked", () => {
  const acting = evaluateActing({
    days: [
      { date: "2026-06-01", hours: "8.00" },
      { date: "2026-06-02", hours: "8.00" },
      { date: "2026-06-03", hours: "8.00" },
    ],
    fullDayHours: "7.50",
    paidFrom: "first_day",
    homeRate: "30.00",
    actingRate: "36.00",
  });
  assert.ok(acting.lines.every((line) => line.rate === "36.00"));
  assert.equal(acting.reliefDays, "3.00");
  const short = evaluateActing({
    days: [{ date: "2026-06-01", hours: "4.00" }],
    fullDayHours: "7.50",
    paidFrom: "first_day",
    homeRate: "30.00",
    actingRate: "36.00",
  });
  assert.equal(short.lines[0].rate, "30.00");
  assert.equal(short.reliefDays, "0.00");
});

test("ENT-019 two vacation plans are checked against the statutory minimum on the total", () => {
  const short = statutoryVacationTopUp({
    plans: [
      { code: "IO", hours: "30.00", primary: true },
      { code: "PT", hours: "10.00" },
    ],
    statutoryMinimumHours: "48.00",
  });
  assert.equal(short.total, "40.00");
  assert.equal(short.topUpHours, "8.00");
  assert.equal(short.planCode, "IO");
  assert.equal(statutoryVacationTopUp({
    plans: [
      { code: "IO", hours: "40.00", primary: true },
      { code: "PT", hours: "10.00" },
    ],
    statutoryMinimumHours: "48.00",
  }).topUpHours, "0.00");
});

test("ENT-020 holiday pay is the greater employer right, allocated by wages", () => {
  const city = employerHolidayPay({
    divisor: "20",
    assignments: [
      { id: "A1", wages: "800.00", agreementHoliday: "40.00", cashInLieu: "0.00" },
      { id: "A2", wages: "200.00", agreementHoliday: "18.00", cashInLieu: "12.00" },
    ],
  });
  assert.equal(city.statutory, "50.00");
  assert.equal(city.agreement, "70.00");
  assert.equal(city.greater, "agreement");
  assert.equal(city.paid, "70.00");
  assert.deepEqual(city.allocation, [
    { id: "A1", amount: "56.00" },
    { id: "A2", amount: "14.00" },
  ]);
  const split = employerHolidayPay({
    divisor: "20",
    assignments: [
      { id: "a", wages: "1.00", agreementHoliday: "10.00", cashInLieu: "0.00" },
      { id: "b", wages: "1.00", agreementHoliday: "0.00", cashInLieu: "0.00" },
      { id: "c", wages: "1.00", agreementHoliday: "0.00", cashInLieu: "0.00" },
    ],
  });
  assert.equal(split.allocation.map((line) => line.amount).join(","), "3.34,3.33,3.33");
  assert.equal(split.allocation.reduce((total, line) => total + Number(line.amount), 0).toFixed(2), split.paid);
});

test("ENT-023 averaging extra hours stay provisional until the cycle closes on the original days", () => {
  const weeks = [
    { index: 1, worked: "44.00", target: "40.00", dates: ["2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04", "2026-06-05"] },
    { index: 2, worked: "40.00", target: "40.00", dates: ["2026-06-08", "2026-06-09", "2026-06-10", "2026-06-11", "2026-06-12"] },
    { index: 3, worked: "40.00", target: "40.00", dates: ["2026-06-15", "2026-06-16", "2026-06-17", "2026-06-18", "2026-06-19"] },
  ];
  const open = settleAveragingCycle({
    weeks,
    rate: "20.00",
    overtimeMultiplier: "1.50",
    closed: false,
    payPeriodEnd: "2026-06-13",
    dailyOvertime: [{ date: "2026-06-02", hours: "1.00", multiplier: "1.50" }],
  });
  assert.equal(open.followedPayPeriod, false);
  const provisional = open.lines.find((line) => line.kind === "provisional");
  assert.equal(provisional?.hours, "4.00");
  assert.equal(provisional?.multiplier, "1.00");
  assert.equal(provisional?.date, "2026-06-05");
  assert.equal(provisional?.provisional, true);
  assert.notEqual(provisional?.date, "2026-06-13");
  assert.equal(open.lines.find((line) => line.kind === "daily_ot")?.provisional, false);

  const closed = settleAveragingCycle({
    weeks,
    rate: "20.00",
    overtimeMultiplier: "1.50",
    closed: true,
    payPeriodEnd: "2026-06-13",
  });
  const premium = closed.lines[0];
  assert.equal(premium.kind, "premium");
  assert.equal(premium.date, "2026-06-05");
  assert.equal(premium.hours, "4.00");
  assert.equal(premium.multiplier, "0.50");
  assert.equal(premium.amount, "40.00");
  assert.equal(premium.provisional, false);
});

test("PAY-069 banked time can mix carry-over and payout, and a payout uses the route", () => {
  assert.deepEqual(settleBankedTime({
    unusedHours: "16.00",
    policy: { action: "carry_then_pay", carryLimitHours: "10.00" },
  }), { carried: "10.00", paid: "6.00" });
  assert.deepEqual(settleBankedTime({
    unusedHours: "16.00",
    policy: { action: "carry_over" },
    lawCapHours: "8.00",
  }), { carried: "8.00", paid: "8.00" });
  throwsCode(() => settleBankedTime({ unusedHours: "4.00" }), "BANKED_TIME_POLICY_MISSING");
  throwsCode(() => requestBankedPayout({
    policy: { employeePayoutRequests: false },
    hours: "4.00",
    balance: "8.00",
    requesterId: "employee",
    approverId: "payroll",
    routeComplete: true,
  }), "BANKED_PAYOUT_NOT_ALLOWED");
  throwsCode(() => requestBankedPayout({
    policy: { employeePayoutRequests: true },
    hours: "4.00",
    balance: "8.00",
    requesterId: "employee",
    approverId: "employee",
    routeComplete: true,
  }), "SELF_APPROVAL");
  throwsCode(() => requestBankedPayout({
    policy: { employeePayoutRequests: true },
    hours: "4.00",
    balance: "8.00",
    requesterId: "employee",
    approverId: "payroll",
    routeComplete: false,
  }), "ROUTE_APPROVALS_MISSING");
  assert.equal(requestBankedPayout({
    policy: { employeePayoutRequests: true },
    hours: "4.00",
    balance: "8.00",
    requesterId: "employee",
    approverId: "payroll",
    routeComplete: true,
  }).paidHours, "4.00");
});

function toClock(minutes: number): string {
  const hour = Math.floor(minutes / 60);
  const minute = minutes % 60;
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}
