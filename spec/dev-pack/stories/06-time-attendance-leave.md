# Stories · 06 Time, Attendance & Leave

Requirements: `requirements/06-time-attendance-leave.md`. Design: `docs/09`. The owner's decisions are in `docs/27-time-attendance-leave-decisions.md`, which wins where a story differs; its scenarios TIME-020 to TIME-047 (`docs/27` §13) are acceptance tests for these stories.

**TIME-001 — Overtime by jurisdiction and agreement.** AC: `docs/09` §6 tests 1 to 4 pass. Each pay code line records its rule source.

**TIME-002 — Rounding never underpays.** AC: punches are paid to the exact minute unless the organization turns rounding on (`time.punch_rounding_minutes`, at most 15). Rounding applies the same way up and down. A property test shows that over 10,000 random punch sets, rounded totals are not systematically lower than actual totals.

**TIME-003 — Meal breaks only when taken.** AC: an unpaid break is deducted only when the employee punches it or confirms it was taken (`break_confirmed`). Otherwise the hours stay paid and the shift is flagged for manager review (`unconfirmed_break`).

**TIME-004 — Timesheet approval and cut-off.** AC: employees confirm their timesheet each period, with reminders. Unapproved timesheets escalate to the next manager or delegate before cut-off. A timesheet still not approved at the cut-off is locked and paid as recorded, and the manager reviews it after. A second approval applies only where the organization's timesheet route says so (FB-037). Late corrections flow to the next run as adjustments, or to an off-cycle run if employment standards pay timing would be breached or the amount is above the organization's threshold (`docs/27` §6).

**TIME-005 — Correction after lock.** AC: `docs/09` §6 test 5.

**TIME-006 — Scheduling with rule checks.** As a scheduler, I want to see overtime exposure, rest-period breaches and credential gaps before publishing.
- AC1: Publishing a schedule with a rest-period breach under the agreement is refused until the caution `time.rest_or_hours_limit` is acknowledged with a reason; the warning shows the article reference.
- AC2: Overtime offers follow the agreement's distribution method (seniority, rotation, equalized hours), and each offer and response is logged. For non-union staff the manager chooses, with the fewest-extra-hours view.
- AC3: Changing a published shift inside its notice needs the caution `time.schedule_changed_late` and a reason, except a swap the manager approved (`docs/27` §9).

**TIME-007 — Leave balances as of any date.** AC: `docs/09` §6 test 6. The balance shown on a request includes accruals scheduled before the leave date. Each plan's year and tier steps follow the plan (`docs/27` §7.4).

**TIME-008 — Greater right for leave.** AC: given a test rule set where the agreement gives 5 paid bereavement days and the statute gives fewer, then the employee receives 5 paid days, and the record shows the agreement as the source. Given a test agreement that gives fewer days than the statute, the statute applies.

**TIME-009 — Protected absences excluded from attendance programs.** AC: the program is off until the organization turns it on. Statutory leaves, disability-related absences, workers' compensation, domestic violence leave and the other categories `docs/27` §8.4 lists are never counted toward attendance management stages; HR reviews before any disciplinary stage.

**TIME-010 — Holiday calendars by location.** AC: an employee in Nunavut gets Nunavut Day (9 July). An employee of a federally regulated employer gets the National Day for Truth and Reconciliation. Calendars come from `ref.holiday` by the location's jurisdiction and the employer's regulatory jurisdiction.

**TIME-011 — Long leave case.** AC: starting a parental leave creates the status change, ROE trigger, benefits continuation choice, seniority continuation and return-to-work task (`docs/09` §5).

**TIME-012 — Privacy of punches.** AC: geofencing is off until the organization turns it on and stores only a pass or fail result at punch time, never coordinates. CanDo offers no biometric punching and stores no biometric data (`docs/27` §3.3).

**TIME-013 — Overtime, holidays and premiums combined.** As a shift worker, I want night shifts that run into overtime or fall on holidays paid exactly as my agreement says.
- AC1: Under the example agreement, a 9-hour weekday night shift (22:00 to 07:00) at $30.85 pays 7 hours straight plus the night premium, and 2 hours at 1.5 plus the night premium at its flat rate (art. 16.02): $215.95 + $12.25 + $92.55 + $3.50 = $324.25.
- AC2: A 9-hour day shift on a holiday pays 7 hours at 1.5 and the 2 overtime hours at 2.0 (`sum_premiums`, art. 20.04): $323.93 + $123.40 = $447.33.
- AC3: When a premium in the same exclusive group as another is also met for some hours (for example evening and night), only the higher one is paid for those hours (art. 16.03).
- AC4: An hour paid as daily overtime does not count toward the weekly threshold when `daily_overtime_counts_toward_weekly` is false.
- AC5: Given a block that meets a combination the agreement leaves open, then the timesheet cannot be approved and the error names the combination and the agreement version.

**TIME-014 — Unapproved overtime is paid.** As an employee, I want every hour I work paid, even when my manager did not approve it in advance.
- AC1: Hours beyond the schedule without approval are flagged to the manager the same day and to the manager and HR before the payroll run, and paid in the run whatever happens.
- AC2: "Not authorized" needs a reason and keeps the hours paid; a correction of a wrong punch needs a reason and tells the employee, who can dispute it (`docs/27` §4.3).

**TIME-015 — Team availability before I ask.** As an employee, I want to see before submitting whether my team is short on the dates I want.
- AC1: The request screen shows green, amber, red or unknown for each day, with no names or counts; the confirmation repeats it.
- AC2: A statutory leave is never declined for staffing or a blackout period (`STATUTORY_LEAVE_NOT_REFUSABLE`), and every decline states its category and reason (`docs/27` §8.5).

**TIME-016 — Leave plans on their own years.** As an HR administrator, I want each leave plan to reset on its own date, so that an agreement's calendar-year vacation, a policy plan on the fiscal year and a sick plan that starts on a promotion can all apply to one person (`docs/27` §7.4).

**TIME-017 — Protected leave reasons.** As an employee on a sensitive leave, I want my manager to see only "protected leave" and my co-workers only "away" (`docs/27` §8.2). CanDo never asks me for a sick note (`docs/27` §8.1).
