# 09 · Time and leave engine

Module 06 owns scheduling, time capture, leave and accruals. Its engine turns raw time into pay codes that payroll values, and keeps leave balances right as of any date. Functional detail is in `requirements/06-time-attendance-leave.md`. The owner's decisions for this module are in `docs/27-time-attendance-leave-decisions.md` (migration 0013), which wins where this document differs.

## 1. From punches to pay codes

```
punches / timesheet lines
   → shifts (pair punches; round only where the organization turned rounding on, the same both ways;
             deduct a meal break only when it was punched or confirmed)
   → worked intervals per day (local time zone of the work location)
   → classify each minute: regular, daily OT tiers, weekly OT tiers, rest-day, holiday, premiums
   → flag exceptions for people to look at (unapproved overtime, unconfirmed breaks, missed punches,
             rest periods, hours limits), never removing paid hours
   → pay code lines: { date, assignmentId, payCode, hours, rateBasis, costAllocation, source }
```

How each group records time (punches, a timesheet, or exceptions only) comes from `timeleave.recording_method_for()` (`docs/27` §5.4). Rounding, breaks and the overtime flags follow `docs/27` §4; a rest-period or hours-limit flag stops approval until its caution is acknowledged (`docs/27` §5.1).

**Classification algorithm (per assignment, per work week):**

1. Load the resolved rule set for each day (`08` §3): ES thresholds plus agreement thresholds. A position HR marked exempt (`timeleave.overtime_exempt()`) gets no overtime tiers; every hour is still paid.
2. Daily pass: for each day, minutes beyond each daily threshold go to that tier, highest tier first (for example, BC: over 12 hours is double time; 8 to 12 hours is time and a half).
3. Weekly pass: minutes not already overtime count toward the weekly threshold in chronological order. Minutes past it become weekly overtime. Where an averaging arrangement covers the position (`timeleave.averaging_for()`), the threshold applies over its cycle (`docs/17` §7.4).
4. "Greater of" jurisdictions (Alberta: daily or weekly, whichever gives more overtime) compute both totals and keep the larger.
5. Rest-day, holiday and second-rest-day rules from the agreement apply on top.
6. Premiums: evaluate each premium's condition (time window, majority of shift, day of week). Premiums do not replace the base hour.
7. Compose: split the week into blocks with the same multiplier sources and premiums, and pass each block with the ES minimum multiplier to the pay composition evaluator (`08` §5). It returns the lines, the combined multiplier and the rule path. A block that meets a combination the agreement leaves open stops approval with `UNRESOLVED_INTERACTION`.
8. Banked time: if the employee elected time off in lieu and the rules allow it, convert overtime lines to bank accruals at the bank rate.

Overtime basis matters: NB and NL pay overtime at 1.5 × the **minimum wage**, not the regular rate (rule file `rate_basis`). Payroll values the line with the basis the time engine passed.

**Multiple assignments:** a person with two assignments under the same employer has hours aggregated for weekly thresholds where the statute requires it. Overtime is allocated to the assignment worked when the threshold was crossed, and its rate follows the jurisdiction's `overtime_rate_basis_multi_rate` rule (AGENTS rule 22; the earlier blended-rate wording is withdrawn).

## 2. Corrections after lock

A correction to a locked period creates a `time.corrected` change set. Payroll receives the difference as retro lines for the original work dates (`06` §6), in the next regular run, or off-cycle when the law's pay deadline or the organization's amount requires it (`docs/27` §6.3). The original timesheet is never edited in place. A timesheet not approved at the cut-off is locked and paid as recorded, and reviewed after (`docs/27` §6.2).

## 3. Leave accruals

Accrual is a function over time: `balance(asOf) = opening + Σ accruals(dates ≤ asOf) − Σ taken(dates ≤ asOf) ± adjustments`. Balances are computed from a ledger, never stored as a single mutable number.

| Method | Ledger entries |
| --- | --- |
| Front-loaded | One credit at the start of the plan year (prorated for mid-year starts and FTE) |
| Per pay period | Credit each pay date |
| Per hour paid or worked | Credit per approved hour (from pay code lines flagged `accrues_leave`) |
| Percentage of wages | Dollar credit at the vacation pay percentage of eligible earnings (from payroll) |
| Service tiers | Rate changes on the plan's tier date in the effective-dated rule; the ledger records the tier used |

Each plan (`timeleave.leave_plan`) states its own year and when its tiers step: calendar, fiscal, hire or service anniversary, or the date the person joined the plan through an event such as a promotion or a change of union (`timeleave.plan_cycle_start()`, `docs/27` §7.4). One person can hold plans on different years at once. Carry-over, negative limits and payout are the plan's (`docs/27` §7.1 to §7.3).

A change set that changes FTE, agreement or service date in the past triggers a recalculation of ledger entries from that date. The audit keeps the old entries in system time.

**Future balance:** the ledger projects accruals to a future date, so an employee can see what they will have on the first day of their vacation.

## 4. Statutory holidays

Holiday calendars per jurisdiction and year are generated from rules (fixed dates, nth weekday, observed-date rules) into `ref.holiday`, and each location points to its jurisdiction's calendar. Eligibility rules (days worked in the qualifying period, worked the day before and after) are evaluated per employee. The holiday pay formula, for example Ontario's (wages in the 4 weeks before ÷ 20), is computed by payroll from earnings history.

## 5. Long leaves

A leave case (pregnancy, parental, compassionate care, and others) creates: status change events, an ROE trigger on the interruption of earnings, benefits continuation choices (`docs/26` §6), top-up plan lines, seniority and service continuation per statute and agreement, and a return-to-work task. After `absence.disability_check_after_days` consecutive working days of absence, HR is prompted to check disability and accommodation (`docs/27` §8.3).

## 6. Acceptance tests

1. BC: 13 hours on one day = 8 regular, 4 at 1.5×, 1 at 2×.
2. Alberta: four 10-hour days in a week (40 hours) = 8 hours daily overtime (greater than 0 weekly).
3. Ontario non-union: five 9.5-hour days (47.5 hours) = 3.5 hours weekly overtime. Under the example agreement (7-hour day) = 12.5 hours daily overtime.
4. NB: overtime valued at 1.5 × minimum wage when the regular rate is higher.
5. Correction of a locked Tuesday from 8 to 10 hours creates retro lines dated Tuesday.
6. A vacation balance as of a future date includes the accruals scheduled before it.

The owner's scenarios TIME-020 to TIME-047 are in `docs/27` §13.
