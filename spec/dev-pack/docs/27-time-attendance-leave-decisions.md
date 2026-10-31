# 27 · Time, attendance and leave decisions

Oct 28, 2026 · @Wael

This document records the owner's review of Module 06 (Time, Attendance & Leave) and turns each decision into something the build can follow: a setting with its default, a database check, a rule the organization sets, a route it edits, a caution, or a screen behaviour. The review went round by round; the working record is `claude/review/06-time-attendance-leave-decisions.md` in the project.

It covers scheduling, punching and time clocks, biometrics, the attendance program, rounding, meal breaks, unapproved overtime, location checks, rest periods and hours limits, averaging, overtime exemptions, how each group records time, timesheet approvals and the payroll cut-off, corrections, leave plans (carry-over, negative balances, payout, plan years), proof of leave, staffing and team availability, who sees why someone is away, long absences, schedule notice, shift offers and swaps.

**Precedence.** On these topics this document wins over `requirements/06`, `stories/06-time-attendance-leave.md` and `docs/09` where it adds to them. `docs/20` still governs approval by each manager's coverage and splitting requests, and `docs/22` still wins on values, defaults, languages and fallbacks. §14 lists every place that changes. The schema is `schema/0013_time_attendance_leave.sql` (migration 0013, Step 1), checked by `tests/schema/schema_0013_smoke.sql`. Overtime exemptions and schedule notice by jurisdiction are in `rules/employment-standards/ca-2026-time-additions.json`.

**The owner's rules for this module.**

1. Every decision is a default each organization can change at setup or later; only legal floors and safety rules are fixed. CanDo pre-fills its suggested numbers at setup, and the organization keeps or changes them (Q46).
2. Hours actually worked are always paid, and payroll never waits: flags, reviews and approvals happen around the pay, not in front of it.
3. The law and the agreement are the floor. Going past a rest-period, hours or notice rule needs a caution and a reason; a statutory leave is never refused for staffing.
4. Privacy first: no biometrics, no location coordinates, no proof of leave in CanDo, and sensitive leave reasons for HR only.

---

## 1. Decisions at a glance

| # | Decision | Setting or rule | Section |
| --- | --- | --- | --- |
| R1.1 | Full scheduling in CanDo: templates, rotations, rule checks, swaps, open shifts, auto-fill, demand-based staffing, shift bidding and self-scheduling | Step 11 scope | §9.4 |
| R1.2 | Punching by mobile app, web and kiosk, plus imports from any clock and one certified hardware partner at launch | `timeleave.punch.source` | §3.2 |
| R1.3 | No biometric punching at launch | — | §3.3 |
| R1.4 | The attendance program is at launch, off until the organization turns it on; protected absences never count; HR before any disciplinary stage | `attendance.program_enabled`: off | §8.4 |
| R2.1 | Punches paid to the exact minute; an organization can turn on rounding that goes both ways equally | `time.punch_rounding_minutes`: 0 | §4.1 |
| R2.2 | An unpaid meal break is deducted only when punched or confirmed | Punch kind `break_confirmed`; flag `unconfirmed_break` | §4.2 |
| R2.3 | Unapproved overtime: flagged the same day and again before payroll; paid whatever happens; "not authorized" is recorded with a reason | `time.unapproved_overtime_alerts` | §4.3 |
| R2.4 | Location on mobile punches optional, off by default, inside-or-outside only | `time.geofence`: off | §4.4 |
| R3.1 | A rest-period or hours-limit breach stops publishing and approval until a caution is acknowledged with a reason | Caution `time.rest_or_hours_limit` | §5.1 |
| R3.2 | Averaging agreements and permits recorded with their document, scope and end date, with reminders | `timeleave.averaging_arrangement`; `time.averaging_reminder_days` | §5.2 |
| R3.3 | HR marks a position exempt from overtime, picking the province's exemption with its legal basis | `timeleave.overtime_exemption` | §5.3 |
| R3.4 | How time is recorded is set per group: exceptions for salaried staff, punches for hourly staff, pre-filled | `time.recording_method_starter`; `timeleave.recording_rule` | §5.4 |
| R4.1 | Second approvals are conditions the organization adds to its timesheet route; none pre-filled | `timesheet` route; FB-037 | §6.1 |
| R4.2 | Timesheets not approved at the cut-off are paid as recorded and reviewed after | Lock without approval | §6.2 |
| R4.3 | Corrections after the cut-off go in the next run; off-cycle when the law's deadline requires it or above the organization's amount | `time.correction_off_cycle` | §6.3 |
| R4.4 | Employees confirm their own timesheet each period, with reminders; payroll does not wait | `time.employee_confirmation`: on | §6.4 |
| R5.1 | Carry-over set per plan; the law's minimum never lost and scheduled within the law's window | `carry_over` on each plan; `leave.expiry_warning_days` | §7.1 |
| R5.2 | Negative balances blocked unless the plan allows them, up to its limit | `negative_limit_hours` | §7.2 |
| R5.3 | Payout on termination set per plan: vacation and banked time as the law requires, sick and personal days not paid, pre-filled | `leave.termination_payout_starter` | §7.3 |
| R5.4 | Each plan has its own year (calendar, fiscal, anniversary, or the date the person joined the plan) and its own tier steps; one person holds plans on different years | `year_basis`, `tier_step_basis`, `timeleave.plan_entry` | §7.4 |
| R6.1 | CanDo never asks for sick notes or proof of leave | — | §8.1 |
| R6.2 | Staffing conflicts warn the manager, who decides; the employee sees a team availability bar before submitting; statutory leave never refused for staffing | `timeleave.team_availability()`; `STATUTORY_LEAVE_NOT_REFUSABLE` | §8.5 |
| R6.3 | Managers see the leave type, but sensitive leaves only as "protected leave"; co-workers see "away" | `leave.protected_categories` | §8.2 |
| R6.4 | HR prompted after 5 consecutive working days of absence to check disability and accommodation | `absence.disability_check_after_days`: 5 | §8.3 |
| R7.1 | Schedule notice from the agreement or the law, otherwise 14 days; a later change needs a caution and a reason | `scheduling.notice_days`: 14; caution `time.schedule_changed_late` | §9.1 |
| R7.2 | Non-union extra shifts: the manager chooses or posts them, CanDo shows who has had the fewest extra hours; unions follow their order | `timeleave.shift_offer` | §9.2 |
| R7.3 | Shift swaps agreed by the employees, checked by CanDo, approved by the manager | `timeleave.shift_swap` | §9.3 |

---

## 2. How the module is set up

### 2.1 Settings

| Setting | Decides | CanDo default | Set per |
| --- | --- | --- | --- |
| `time.punch_rounding_minutes` | Rounding of punches, the same both ways | 0 (exact minutes); at most 15 | Organization, employer |
| `time.geofence` | Location check on mobile punches (inside or outside only) | Off | Organization, employer |
| `time.unapproved_overtime_alerts` | Who is told about unapproved overtime, the same day and before payroll | Same day: the manager; before payroll: the manager and HR | Organization, employer |
| `time.recording_method_starter` | How a position records time when no rule covers it, by its pay basis | Hourly and daily pay: punches; salaries: exceptions only | Organization, employer |
| `time.employee_confirmation` | Employees confirm their timesheet each period | On | Organization, employer |
| `time.correction_off_cycle` | Amount above which a late correction is proposed for an off-cycle pay | None (only the law's pay deadline) | Organization, employer |
| `time.averaging_reminder_days` | Reminders before an averaging agreement or permit ends | 60 and 30 days | Organization, employer |
| `attendance.program_enabled` | The attendance management program | Off | Organization, employer |
| `absence.disability_check_after_days` | Consecutive working days of absence before HR is prompted | 5 | Organization, employer |
| `leave.expiry_warning_days` | Warnings before leave above the law's minimum expires, and before the law's window to schedule vacation closes | 60 and 30 days | Organization, employer |
| `leave.termination_payout_starter` | What a new plan pays out when employment ends, by leave category | Vacation: all; sick and personal: none; other categories state their own | Organization, employer |
| `leave.protected_categories` | Leave categories managers see only as "protected leave" | Domestic violence, medical, family and caregiver, disability, workers' compensation | Organization |
| `scheduling.notice_days` | Notice before a published shift where no agreement or law sets one | 14 days | Organization, employer |

Pre-filled values follow the Q46 rule: the setup screen shows CanDo's suggestion and the organization keeps or changes it. The reminder days (60 and 30) are CanDo's suggestion, as the owner asked for warnings without a number.

### 2.2 Set up by each organization

No setting in this module is left without a CanDo default. What each organization sets up, with no CanDo starting answer:

| What | Where | Until it is set |
| --- | --- | --- |
| Leave plans: accrual, tiers, year, tier steps, carry-over, negative limit | `timeleave.leave_plan` (§7) | A leave type with no plan for a position stops with `LEAVE_PLAN_MISSING` |
| Payout for leave categories the starter does not list | The plan's `termination_payout` | The plan cannot be saved (`INPUT_REQUIRED`) |
| Averaging agreements and permits | `timeleave.averaging_arrangement` (§5.2) | The law's weekly overtime rule applies |
| Overtime exemptions | `timeleave.overtime_exemption` (§5.3) | Overtime applies (the law until an exemption is recorded) |
| Staffing levels and blackout periods | `timeleave.staffing_level`, `timeleave.blackout_period` (§8.5) | The availability bar shows "unknown" |
| Attendance program stages | `timeleave.attendance_program` (§8.4) | No stages |

### 2.3 Route

Timesheets can use the organization's routes (`docs/23` §2.2) for a second approval, with two new route conditions: `minOvertimeHours` (overtime hours on the timesheet) and `otherCostCentre` (time charged outside the approver's area). No starter route is copied: a timesheet that matches no route needs only its manager's approval (FB-037). No one approves their own timesheet, at any step (`SELF_APPROVAL`).

### 2.4 Cautions

| Caution | When | Section |
| --- | --- | --- |
| `time.rest_or_hours_limit` | A schedule or timesheet breaks a rest period or a maximum-hours rule of the law or the agreement | §5.1 |
| `time.schedule_changed_late` | A published shift is changed inside its notice period | §9.1 |

Both always need a written reason.

---

## 3. Scope and devices

### 3.1 What CanDo builds

Scheduling, time capture, timesheets, leave and attendance are built in CanDo (Step 11), including the full scheduling scope in §9.4. Pay valuation stays in payroll (`docs/24`).

### 3.2 Punching and clocks (R1.2)

Employees punch on the mobile app, on the web, or on a shared kiosk tablet. Punches from any time clock are imported by file or API, and one certified time clock hardware partner is supported at launch; its choice is open (`docs/16` Q48). Other clock vendors' direct links are built per customer. Every punch records how it arrived (`source`: mobile, web, kiosk, clock, import, manual), and an edited punch keeps its original time, who edited it and why.

### 3.3 No biometrics (R1.3)

CanDo offers no fingerprint, face or other biometric punching at launch and stores no biometric data. The privacy assessment and Quebec registration steps in `requirements/06` are withdrawn until the owner decides otherwise.

---

## 4. Time capture

### 4.1 Rounding (R2.1)

Punches are paid to the exact minute (`time.punch_rounding_minutes` = 0). An organization can turn on rounding to the nearest number of minutes, up to 15, applied the same way up and down so it never systematically underpays (TIME-002).

### 4.2 Meal breaks (R2.2)

An unpaid meal break is deducted only when the employee punches it (`break_start`, `break_end`) or confirms they took it (`break_confirmed`). Otherwise the hours stay paid and the manager sees an `unconfirmed_break` flag (TIME-003).

### 4.3 Unapproved overtime (R2.3)

Hours worked beyond the schedule without approval are flagged (`unapproved_overtime` in `timeleave.time_exception`):

- on the same day, to the people `time.unapproved_overtime_alerts` names for `sameDay` (the manager);
- again before the payroll run, to those named for `beforePayroll` (the manager and HR).

Payroll never waits. With no action, the hours are paid. The manager can approve them, or mark them "not authorized": still paid, as the law requires, and recorded with a reason so the manager can follow up. If the time itself is wrong (a forgotten punch-out), the manager corrects the punch with a reason; the employee is told and can dispute it. A flag never removes paid hours.

### 4.4 Location (R2.4)

Location checks on mobile punches are off until the organization turns them on (`time.geofence`). When on, CanDo checks at punch time whether the punch is inside the work site and keeps only the result (`geo_ok`), never the coordinates (TIME-012).

---

## 5. Hours of work and overtime

### 5.1 Rest periods and hours limits (R3.1)

When the time engine finds that a schedule or timesheet breaks a rest period or a maximum-hours rule of the law or the agreement, it records a `rest_period` or `hours_limit` flag with the rule it comes from. The shift cannot be published and the timesheet cannot be approved while such a flag is open; it is cleared only by acknowledging the caution `time.rest_or_hours_limit` with a reason (an emergency, for example). The database enforces both.

### 5.2 Averaging (R3.2)

Each averaging agreement or permit is recorded (`timeleave.averaging_arrangement`) with:

- its kind: a written agreement with employees, a government permit, or a collective agreement;
- its document (required except for a collective agreement, which names the agreement instead);
- who it covers (positions, units, agreements, employers, as a scope);
- its cycle length in weeks and anchor date;
- its period, with an end date except for a collective agreement.

Overtime is counted over the cycle as `docs/17` §7.4 describes. HR is reminded `time.averaging_reminder_days` before one ends. A position covered by none follows the law's weekly rule; covered by two, it stops with `AVERAGING_CONFLICT` until HR ends one. The longest cycle the law allows is checked from the rules file at Step 7.

### 5.3 Overtime exemptions (R3.3)

HR marks a position exempt (`timeleave.overtime_exemption`) by picking one of the province's exemptions from `rules/employment-standards/ca-2026-time-additions.json` (for example `BC_MANAGER`, `ON_SUPERVISORY_MANAGERIAL`, `FED_MANAGER`), with its legal basis and a reason. A position has one exemption at a time. CanDo warns when the job does not seem to fit (for example a supervisor whose time records show mostly front-line work). An exempt employee is still paid for every hour worked, at the regular rate where the law says so. A province whose list is not yet loaded has no exemptions to pick (`JURISDICTION_RULE_MISSING`).

### 5.4 How each group records time (R3.4)

Each group records time by punches, a timesheet, or exceptions only (leave and overtime). The organization's rules (`timeleave.recording_rule`, by pay group, employment type, agreement, employer or unit) decide; where none covers a position, `time.recording_method_starter` decides by the basis of its base pay: punches for hourly and daily pay, exceptions for salaries. A position with no base pay stops with `INPUT_REQUIRED` (`timeleave.recording_method_for()`).

---

## 6. Timesheets and the payroll cut-off

### 6.1 Second approvals (R4.1)

The manager approves timesheets by coverage (`docs/20`). An organization can add second approvals as conditions on its own `timesheet` routes, for example HR above 8 overtime hours, or the other department's manager for time charged to its cost centre. None is pre-filled. When a timesheet's facts match a route, it is approved only once the route is complete (`ROUTE_APPROVALS_MISSING`); when they match none, the manager's approval is enough (FB-037).

### 6.2 The cut-off (R4.2)

Reminders and the escalation after `approvals.escalate_after_working_days` come first. A timesheet still not approved at the cut-off is locked and paid as recorded; the manager still reviews it afterwards (`reviewed_after_lock_by`), and any correction goes in the next run. Payroll never waits.

### 6.3 Corrections after the cut-off (R4.3)

A correction to a locked period is a change set paid as retro lines dated to the original work days (`docs/09` §2), in the next regular run. An off-cycle pay is proposed when waiting would miss the law's pay deadline, or when the amount is above `time.correction_off_cycle.aboveAmount`, which is empty unless the organization sets one.

### 6.4 Employee confirmation (R4.4)

Employees confirm their own timesheet each pay period, with reminders (`time.employee_confirmation`). The confirmation is recorded (`employee_confirmed_at`); payroll does not wait for it.

---

## 7. Leave plans and balances

Leave entitlements live in plans (`timeleave.leave_plan`), owned by an agreement or a policy, and the ledger is keyed by the plan's code (`docs/17` §7.5). Each plan states, for a leave type and a scope of positions: the accrual method and tiers, its year, when its tiers step, its carry-over, its negative limit and its payout. Plans are dated; the one with the lowest priority number that covers a position applies (`timeleave.leave_plan_for()`); two at the same priority stop with `LEAVE_PLAN_AMBIGUOUS`.

### 7.1 Carry-over (R5.1)

Each plan states its carry-over (`carry_over`): none, limited (`limitHours`, and `expiresMonths` if carried hours expire), or unlimited (`LEAVE_CARRYOVER_INVALID` otherwise). The rule applies only to hours above the law's minimum: statutory vacation is never lost, and must be scheduled within the law's window after the entitlement year. The employee and the manager are warned `leave.expiry_warning_days` before carried hours expire and before that window closes.

### 7.2 Negative balances (R5.2)

A plan allows a negative balance only if it states a limit (`negative_limit_hours`); otherwise a request beyond the balance (including accruals scheduled before the leave date) is refused (`LEAVE_BALANCE_INSUFFICIENT`). Recovering a negative balance when employment ends needs the employee's written authorization, as for any overpayment (`docs/21` §7.2).

### 7.3 Payout when employment ends (R5.3)

Each plan states what is paid out when employment ends (`termination_payout`): all of the unused balance, only the law's part, or none. A new plan starts from `leave.termination_payout_starter`: vacation all, sick and personal days none. A category the starter does not list states its rule when the plan is set up (`INPUT_REQUIRED`). A vacation plan can never pay out nothing (`LEAVE_PAYOUT_BELOW_LAW`). Banked time follows its own policy (`docs/24` §5.3).

### 7.4 Each plan's own year (R5.4)

One employee can hold several plans on different years at the same time. Each plan states:

| Field | Choices |
| --- | --- |
| `year_basis`, when entitlements reset | Calendar year; fiscal year (from a fiscal or leave-year calendar, `year_calendar_id`); hire anniversary; continuous service anniversary; or the anniversary of the date the person joined the plan |
| `tier_step_basis`, when service tiers step up | The start of the plan year; hire anniversary; service anniversary; or the plan entry date |

The date a person joined a plan is recorded with the event that brought them in (`timeleave.plan_entry`: hire, promotion, becoming exempt, a move of location or agreement), so a plan can restart from a promotion or a change of union. `timeleave.plan_cycle_start()` gives the start of the current year or tier cycle; a missing anchor (no plan entry, no calendar period) stops with `INPUT_REQUIRED`. When the law changes, the statutory minimums update on their effective date, as CanDo loads them centrally (Q7).

---

## 8. Leave requests and absences

Leave types are each organization's own, mapped to CanDo's fixed categories (`ref.leave_category`, 21 categories; `LIST_VALUE_UNKNOWN` otherwise). The category drives the payout starter, who sees the reason, and what the attendance program may count.

### 8.1 No proof of leave (R6.1)

CanDo never asks for sick notes or other proof of leave, and stores none. An employer that needs proof handles it outside CanDo. The leave type's "documentation that may be requested" in `requirements/06` is withdrawn.

### 8.2 Who sees why someone is away (R6.3)

Managers see the leave type (vacation, sick day). A leave type whose category is in `leave.protected_categories` (domestic violence, medical, family and caregiver, disability, workers' compensation) shows to managers only as "protected leave", and only HR sees the reason (`reason_restricted`). Domestic violence leave is always protected (`LEAVE_REASON_MUST_BE_PROTECTED`). Co-workers see only "away".

### 8.3 Long absences (R6.4)

After `absence.disability_check_after_days` (5) consecutive working days of absence, HR is prompted to check short-term disability (Module 05) and accommodation (Module 13). An absence HR knows is protected under human rights law is marked (`protected_reason`: disability, accommodation, workers' compensation, other).

### 8.4 The attendance program (R1.4)

The program is available at launch and off until the organization turns it on (`attendance.program_enabled`; `ATTENDANCE_PROGRAM_OFF`). The organization sets its stages (supportive or disciplinary, with their thresholds) per program and scope. The database refuses to count:

- a statutory leave;
- a leave whose reason is protected;
- a leave in a category never counted (medical, pregnancy, parental, family and caregiver, bereavement, domestic violence, Indigenous practices, civic, public health, disability, workers' compensation, union business);
- an absence HR marked as protected.

Any of these is `ATTENDANCE_PROTECTED_ABSENCE`. Accommodation must be considered before any stage after the first (`ACCOMMODATION_NOT_CONSIDERED`), and HR, not the manager who opened it, reviews a disciplinary stage before it is issued (`HR_REVIEW_REQUIRED`). Absence indices such as the Bradford factor stay hidden by default and are never used alone.

### 8.5 Staffing and the team availability bar (R6.2)

Each unit can record minimum staffing by day of the week (`timeleave.staffing_level`) and blackout periods (`timeleave.blackout_period`). When a request falls in a blackout period or would drop the team below its minimum, the manager is warned and decides. A declined request states its category (staffing, blackout, balance, other) and reason, and a statutory leave is never declined for staffing or a blackout period (`STATUTORY_LEAVE_NOT_REFUSABLE`, whether the decline comes through the approval part or the request).

Before submitting, the employee sees a team availability bar for the dates they pick (`timeleave.team_availability()`):

| Level | Meaning |
| --- | --- |
| Green | After this request, the team stays above its minimum |
| Amber | After this request, the team is exactly at its minimum |
| Red | A blackout period, or the team would drop below its minimum |
| Unknown | No minimum staffing recorded for that day |

Requested, approved and taken leave count as away. The bar shows only the level, never names or counts, and the confirmation message repeats it, so the employee can choose other dates first.

---

## 9. Scheduling

### 9.1 Notice and late changes (R7.1)

A shift's notice comes from the agreement or the law where one sets it (`schedule_notice` in the rules file; federally, 96 hours for a schedule and 24 hours for a change), otherwise from `scheduling.notice_days` (14). It is stored on the shift when it is published (`notice_hours`). Changing a published shift's times, break or person inside its notice needs the caution `time.schedule_changed_late` and a reason, and any premium the agreement requires is paid; a swap the manager approved is the exception (§9.3).

### 9.2 Extra shifts and overtime offers (R7.2)

For non-union staff, the manager chooses who gets an extra shift or overtime, or posts it to the open-shift board; CanDo shows who has had the fewest extra hours and checks overtime, rest and credentials first. Unionized staff follow their agreement's order (seniority, rotation or equal hours). Every offer and its answer is logged (`timeleave.shift_offer`), for equitable distribution reports and grievances (TIME-006).

### 9.3 Shift swaps (R7.3)

Two employees agree a swap; CanDo checks eligibility, credentials, overtime and rest (`checks`); the manager approves (`timeleave.shift_swap`). The database refuses approval before the colleague agrees, when a check failed (`SHIFT_SWAP_CHECKS_FAILED`), or by either employee (`SELF_APPROVAL`).

When a shift is published or moved to another person, CanDo also checks the credentials and training the position needs (`docs/29` §6, migration 0015): a licence the law requires stops it with no override; anything else needs the caution `learning.not_ready_for_work`.

### 9.4 Building schedules (R1.1)

At launch: templates and rotations (fixed, rotating, DuPont, platoon, compressed, split and on-call); a drag-and-drop editor with conflict checks across a person's positions; auto-fill that respects availability, qualifications, seniority and the rules above; demand-based staffing levels (for example residents per care aide); shift bidding (picks) by seniority for transit, fire and similar groups; self-scheduling within the unit's minimums for health care; open shifts; publication with notice; employee availability; and mobile notifications of changes.

---

## 10. Fallback decided in this review

| # | When | Then |
| --- | --- | --- |
| FB-037 | A timesheet's facts match none of the organization's timesheet routes | Only its manager's approval is needed; second approvals exist only where the organization adds a route (`timeleave.timesheet_route()`) |

---

## 11. Data model (migration 0013)

| Object | What it holds |
| --- | --- |
| Settings in §2.1 | 13 settings, all with CanDo defaults |
| `ref.leave_category`; `timeleave.leave_type.category` (foreign key); trigger `timeleave.check_leave_type_setup()` | §8 |
| `timeleave.leave_request.protected_reason` | §8.3, §8.4 |
| `timeleave.punch.source`, punch kind `break_confirmed` | §3.2, §4.2 |
| `timeleave.time_exception` and its trigger | §4.3, §5.1 |
| `timeleave.averaging_arrangement`, `timeleave.averaging_for()` | §5.2 |
| `timeleave.overtime_exemption`, `timeleave.overtime_exempt()` | §5.3 |
| `timeleave.recording_rule`, `timeleave.recording_method_for()` | §5.4 |
| `timeleave.timesheet` (`employee_confirmed_at`, `route_id`, `locked_at`, review after lock); route subject `timesheet` and conditions `minOvertimeHours`, `otherCostCentre`; `timeleave.timesheet_route()`; trigger `timeleave.check_timesheet()` | §6 |
| `timeleave.leave_plan`, `timeleave.leave_plan_for()`, `timeleave.plan_entry`, `timeleave.plan_cycle_start()` | §7 |
| `timeleave.leave_request_component.decline_category`, `decline_reason`; `core.check_part_decline()`; `core.roll_up_leave_request()` carries the decline | §8.5 |
| `timeleave.staffing_level`, `timeleave.blackout_period`, `timeleave.team_availability()` | §8.5 |
| `timeleave.attendance_program`, `timeleave.attendance_stage` | §8.4 |
| `timeleave.shift` (`published_at`, `published_by`, `notice_hours`); `timeleave.shift_offer`; `timeleave.shift_swap` | §9 |
| Cautions `time.rest_or_hours_limit`, `time.schedule_changed_late`; `check_approval_task()` with timesheets | §2 |

Every new tenant table has `tenant_id` with forced row-level security; text fields are registered as translatable (`docs/22` §4.3). No starter data is copied to existing organizations.

**Upgrading.** The leave category foreign key, the punch source and edit-reason checks and the approved-timesheet check are added `NOT VALID`: rows from before 0013 are not rechecked, and new rows must comply. Before going live on 0013, map every existing leave type to a category in `ref.leave_category` and validate `leave_type_category_fk`; set up leave plans for every leave type in use and fill the ledger's `plan_code`; record each existing averaging arrangement and overtime exemption.

---

## 12. Validation, API and events

**Errors added by 0013:** `LEAVE_REASON_MUST_BE_PROTECTED`, `AVERAGING_CONFLICT`, `LEAVE_CARRYOVER_INVALID`, `LEAVE_PAYOUT_BELOW_LAW`, `LEAVE_PLAN_MISSING`, `LEAVE_PLAN_AMBIGUOUS`, `STATUTORY_LEAVE_NOT_REFUSABLE`, `ATTENDANCE_PROGRAM_OFF`, `ATTENDANCE_PROTECTED_ABSENCE`, `ACCOMMODATION_NOT_CONSIDERED`, `HR_REVIEW_REQUIRED`, `SHIFT_SWAP_CHECKS_FAILED`; in the application, `LEAVE_BALANCE_INSUFFICIENT`. Existing ones used: `INPUT_REQUIRED`, `LIST_VALUE_UNKNOWN`, `SETTING_NOT_SET`, `CAUTION_NOT_ACKNOWLEDGED`, `ROUTE_APPROVALS_MISSING`, `SELF_APPROVAL`, `JURISDICTION_RULE_MISSING`, `RULE_NOT_VERIFIED`, `UNRESOLVED_INTERACTION`.

**Checks in the application (Step 11 unless noted), not the database:** rounding; break deduction only when punched or confirmed; detecting unapproved overtime, rest-period and hours-limit breaches with their rule source; the two overtime notices; averaging settlement and the law's longest cycle; the exemption fit warning; balances with future accruals and the negative limit; carry-over, expiry and warnings; the statutory vacation window; payout at termination (with Step 16); the long-absence prompt; attendance thresholds; auto-fill, bidding and self-scheduling; overtime offer order; swap checks; the notice from the agreement or the law; late-change premiums (with Step 9).

**API** (added to `api/openapi.yaml` in Step 11): `GET/POST /time/exceptions` with `approve`, `not-authorized`, `correct` and `acknowledge`; `GET/POST /time/averaging-arrangements`; `GET/POST /time/overtime-exemptions`; `GET/POST /time/recording-rules`; `POST /timesheets/{id}/confirm`, `approve`, `review-after-lock`; `GET/POST /leave/plans`; `GET /leave/plans/{id}/cycle?employment=&on=`; `GET/POST /leave/plan-entries`; `GET/POST /leave/staffing-levels`, `/leave/blackout-periods`; `GET /teams/{orgUnit}/availability?from=&to=` (levels only); `GET/POST /attendance/programs`, `/attendance/stages` with `issue`; `POST /shifts/{id}/publish`; `GET/POST /shifts/{id}/offers`; `GET/POST /shift-swaps` with `agree` and `approve`.

**Events** (added to `api/events.yaml`; identifiers only, AGENTS rule 9): `time.exception.flagged`, `time.exception.pre_payroll_notice`, `time.exception.decided`, `timesheet.confirmed`, `timesheet.locked_unapproved`, `averaging.expiring`, `leave.expiry_warning`, `leave.long_absence`, `attendance.stage_issued`, `shift.published`, `shift.changed_late`, `shift.offer_logged`, `shift.swap_approved`.

---

## 13. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| TIME-020 | Punches at 07:58 and 16:03 with rounding off; then with 5-minute rounding | Exact minutes; 08:00 and 16:05 | engine test | 11 |
| TIME-021 | No break punched, no confirmation | No deduction; `unconfirmed_break` flag | engine test; smoke 3a | 11 |
| TIME-022 | 1.5 hours beyond the schedule, nobody acts | Flag the same day and before payroll; paid in the run | smoke 3b; engine test | 11 |
| TIME-023 | Manager marks it not authorized | Refused without a reason; with one, still paid | smoke 3b–c | 11 |
| TIME-024 | Mobile punch with location on | Only inside or outside kept | API test | 11 |
| TIME-025 | Timesheet with an 8-hour rest breach | Approval refused until the caution is acknowledged with a reason | smoke 5b; smoke 3d | 11 |
| TIME-026 | Shift published with a rest breach | Refused until acknowledged | smoke 9c | 11 |
| TIME-027 | Written averaging agreement with no document or no end; two arrangements at once | Refused; `AVERAGING_CONFLICT` | smoke 4a–c | 11 |
| TIME-028 | HR marks a BC house manager exempt | Saved with `BC_MANAGER` and its basis; refused without a basis | smoke 4d–e | 11 |
| TIME-029 | Hourly care worker, salaried office worker, office unit on timesheets | Punches; exceptions; timesheet by the organization's rule; no base pay stops | smoke 4f–h | 11 |
| TIME-030 | Employee approves her own timesheet, or gives its second approval | `SELF_APPROVAL` | smoke 5a, 5e | 11 |
| TIME-031 | Organization adds HR above 8 overtime hours | Second approval only at 8 or more; manager alone below (FB-037) | smoke 5c–d | 11 |
| TIME-032 | Timesheet unapproved at the cut-off | Locked and paid as recorded; manager reviews after | smoke 5f | 9, 11 |
| TIME-033 | Missed 6 hours found after the cut-off, due in 2 days under the law | Off-cycle proposed; otherwise the next run | engine test | 9, 11 |
| TIME-034 | Employee does not confirm her timesheet | Reminders; payroll proceeds | API test | 11 |
| TIME-035 | Vacation plan with a limited carry-over and no limit; payout none | `LEAVE_CARRYOVER_INVALID`; `LEAVE_PAYOUT_BELOW_LAW` | smoke 6a–b | 11 |
| TIME-036 | New sick and vacation plans; union business plan with no payout | None and all from the starter; `INPUT_REQUIRED` | smoke 6c, 6e | 11 |
| TIME-037 | One employee with a calendar-year agreement plan, a fiscal-year policy plan and a promotion-year sick plan | Years start 1 January, 1 April and the promotion date; tiers on the service anniversary | smoke 6f–i | 11 |
| TIME-038 | Request beyond the balance on a plan with no negative limit; with a 16-hour limit | Refused; allowed to −16 | engine test | 11 |
| TIME-039 | Manager declines parental leave for staffing or a blackout | `STATUTORY_LEAVE_NOT_REFUSABLE` by either path | smoke 7a, 7c | 11 |
| TIME-040 | Vacation request in a week with two of three staff already away | Bar shows red with no names; manager warned and decides with a reason | smoke 7b, 7d–e | 11 |
| TIME-041 | Manager opens the team calendar with a domestic violence leave | Shows "protected leave"; HR sees the reason; co-workers see "away" | smoke 2b–c; API test | 11 |
| TIME-042 | Sixth consecutive working day of absence | HR prompted to check disability and accommodation | engine test | 11 |
| TIME-043 | Attendance stage counting a disability-related absence or a medical leave; stage 2 without accommodation; discipline without HR | Each refused; issued once corrected | smoke 8a–d | 11 |
| TIME-044 | Shift tomorrow moved 2 hours after publication | Refused until the caution is acknowledged; a shift in 60 days moves freely | smoke 9a–b | 11 |
| TIME-045 | Federal employer publishes a schedule 3 days ahead | 96-hour notice applies; employee may refuse; caution to change | rule test | 7, 11 |
| TIME-046 | Extra shift for non-union staff; for unionized staff | Manager picks with the fewest-hours view; agreement order; every offer logged | smoke 9f; engine test | 11 |
| TIME-047 | Swap approved before the colleague agrees, or by the colleague | Refused; manager approval applies it inside the notice | smoke 9d–e | 11 |

---

## 14. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/06` | Points here at the top; open questions closed; biometrics and proof of leave withdrawn; rounding, breaks, overtime, approvals, cut-off, leave plans, privacy, attendance and scheduling marked where they changed |
| `stories/06` | TIME-002, TIME-003, TIME-004, TIME-006, TIME-007, TIME-009 and TIME-012 follow this document; new stories TIME-014 to TIME-017; scenarios TIME-020 to TIME-047 in §13 |
| `docs/09` | Points here; §1 rounding, breaks, flags, exemptions and averaging, and the multi-rate overtime rule (blended-rate wording withdrawn, AGENTS rule 22); §2 the cut-off; §3 plan years; §5 the long-absence prompt |
| `docs/15` Step 11 | Read this document; build on migration 0013; pass TIME-020 to TIME-047 |
| `docs/16` | Q4 decided (full scheduling); new Q48 (time clock partner); items to verify for this module |
| `docs/22` | Settings from 0013 are listed here, not in `docs/22` §2; FB-037 |
| `AGENTS.md` | Reading order item 14; rule 51; Step 1 migration 0013 and its smoke test; Step 11 |
| `.cursor/rules/00-cando.mdc` | Rule 51 in short |
| `rules/employment-standards/ca-2026-time-additions.json` | New: overtime exemptions and schedule notice (federal, Ontario, British Columbia) |
| `tests/schema/schema_0003_smoke.sql`, `schema_0006_smoke.sql` | A declined leave states its category and reason; no rule relaxed |

Where a listed document still says otherwise, this document wins.

---

## 15. Open questions and items to verify

| Item | Until decided |
| --- | --- |
| Time clock hardware partner (Q48) | Imports from any clock by file or API |
| Overtime exemptions (`ca-2026-time-additions.json`) | Federal, Ontario and BC `secondary`; others not entered; checked against each statute before Step 11 |
| Schedule notice | Federal `secondary` (96 and 24 hours); Ontario and BC no general rule found, `verify_at_load`; others not entered |
| Longest averaging cycle by province | Checked from the employment standards file at Step 7 |
| Leave categories never counted by the attendance program | Reviewed with employment and human rights counsel before Step 11 |

---

## Sources

- ESDC, Labour Standards questions and answers (96 hours' notice of schedules, 24 hours' notice of shift changes, the right to refuse, emergencies): https://www.canada.ca/en/employment-social-development/corporate/portfolio/labour/programs/labour-standards/questions-answers.html
- BC Interpretation Guidelines, Employment Standards Regulation s. 34 (exclusions from Part 4, including managers): https://www2.gov.bc.ca/gov/content/employment-business/employment-standards-advice/employment-standards/forms-resources/igm/esr-part-7-section-34
- BC Interpretation Guidelines, Regulation s. 37.8 (high technology professionals): https://www2.gov.bc.ca/gov/content/employment-business/employment-standards-advice/employment-standards/forms-resources/igm/esr-part-7-section-37-8
- Overtime exemptions in Ontario (supervisory or managerial; information technology professionals): https://ullaw.ca/resource/overtime-exemptions-ontario
