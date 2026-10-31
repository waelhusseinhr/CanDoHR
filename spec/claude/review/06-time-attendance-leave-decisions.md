# 06 Time, Attendance & Leave · Review decisions

Review started 28 Oct 2026 with Wael. Decisions are logged here round by round; the developer pack is updated when the review is complete.

**Status: applied 28 Oct 2026.** The decisions are in `dev-pack/docs/27-time-attendance-leave-decisions.md`, migration `dev-pack/schema/0013_time_attendance_leave.sql` and its smoke test, the register (FB-037 new), `rules/employment-standards/ca-2026-time-additions.json` (overtime exemptions and schedule notice for federal, Ontario and BC), and the updates listed in docs/27 §14. Pre-filled, each organization's to change (the Q46 principle): exact minutes (rounding off); location checks off; unapproved overtime told to the manager the same day and to the manager and HR before payroll; salaried staff record exceptions and hourly staff punch; employees confirm their time; reminders 60 and 30 days before an averaging arrangement ends and before leave expires (CanDo's suggestion, as no number was given); vacation paid out on termination, sick and personal days not; sensitive leave categories protected; HR prompted after 5 working days of absence; schedule notice 14 days; the attendance program off. Set up by each organization with no CanDo starting answer: leave plans (year, tiers, carry-over, negative limit), averaging arrangements, overtime exemptions, staffing levels and blackouts, attendance stages. Open: the time clock hardware partner (docs/16 Q48). Interpretations: a timesheet matching no second-approval route needs only its manager (FB-037); leave plan years can start from a recorded plan entry (promotion, becoming exempt, a move of location or union); statutory leave is never declined for staffing or a blackout, whichever path the decline takes.

Planned rounds: 1 scope and devices · 2 time capture · 3 hours of work and overtime · 4 timesheets and the payroll cut-off · 5 leave plans and balances · 6 leave requests, holidays and absences · 7 scheduling and union rules.

The principle from Modules 01 to 05 applies: every decision is a default each organization can change at setup or later, except legal floors and safety rules; routes and rules are the organization's, with reminders, cautions and recorded acknowledgements; CanDo pre-fills its suggested numbers at setup and the organization can change them (Q46).

Already decided elsewhere and not asked again: approval by each manager's coverage, requests split to the minute and partial approval (`docs/20` §2–§3); escalation after 3 working days (`docs/21` §7.5); banked time policies and payouts per group (`docs/24` §5.3); vacation pay per group (`docs/24` §5.1); proration per pay group (`docs/24` §5.2); overtime for people with several rates follows the jurisdiction (AGENTS rule 22); premium combinations an agreement leaves open stop for labour relations (`docs/24` §5.5); statutory holiday pay at employer level (`docs/17` §7.6); statutory tables and employment standards loaded centrally by CanDo (Q7, which closes the rule-refresh question in `requirements/06`); the leave caution near the end of probation (`docs/23` §7); benefits during leaves (`docs/26` §6).

## Round 1 · Scope and devices

| # | Decision |
| --- | --- |
| 1 | **Full scheduling in-house:** templates, rotations, rule checks, swaps and open shifts, plus auto-fill, demand-based staffing, shift bidding (picks) and self-scheduling (closes docs/16 Q4). |
| 2 | **Punching by mobile app, web and shared kiosk, plus file or API import from any clock, and one certified time clock hardware partner at launch;** other clock vendors' direct links built per customer. The partner is still to be chosen. |
| 3 | **No biometric punching at launch.** |
| 4 | **The attendance management program is at launch, off until the organization turns it on;** protected absences are never counted and HR reviews before any disciplinary stage. |

## Round 2 · Time capture

| # | Decision |
| --- | --- |
| 1 | **Punches are paid to the exact minute;** an organization can turn on rounding that goes both ways equally (for example to the nearest 5 minutes). |
| 2 | **An unpaid meal break is deducted only when the employee punches it or confirms they took it;** otherwise the manager sees a flag. |
| 3 | **Hours worked beyond the schedule without approval are flagged to the manager on the same day, and again to the manager and HR before the payroll run; payroll never waits.** With no action, the hours are paid. "Not approved" means worked but not authorized: still paid, as the law requires, and recorded so the manager can follow up. If the time itself is wrong (a forgotten punch-out), the manager corrects it with a reason, and the employee is told and can dispute it. (Wael's own approach, with the refinement confirmed.) |
| 4 | **Location on mobile punches is optional, off until the organization turns it on, and keeps only "inside or outside the site" at punch time, never the coordinates** (CanDo's suggestion, confirmed). |

## Round 3 · Hours of work and overtime

| # | Decision |
| --- | --- |
| 1 | **A schedule or timesheet that breaks a rest-period or maximum-hours rule from the law or the agreement stops:** it is published or approved only after someone acknowledges the caution and gives a reason (an emergency, for example). |
| 2 | **Averaging agreements and permits are recorded with their document, who they cover and their end date;** overtime counts over the averaging period, and reminders go out before one expires. |
| 3 | **HR marks a position exempt from overtime and picks the exemption from the province's list in the rules file;** CanDo warns when the job does not seem to fit. |
| 4 | **How time is recorded is set per group, pre-filled as exceptions only for salaried staff (leave and overtime) and punches for hourly staff;** each group can change it. |

## Round 4 · Timesheets and the payroll cut-off

| # | Decision |
| --- | --- |
| 1 | **Second approvals are conditions the organization can add to its own timesheet route (large overtime, another department's cost centre); none is pre-filled.** |
| 2 | **A timesheet still not approved at the cut-off, after the reminders and the escalation, is paid as recorded;** the manager still reviews it, and any correction goes in the next run. Payroll never waits. |
| 3 | **A correction made after the cut-off is paid in the next regular run;** an off-cycle pay is proposed when waiting would miss the law's pay deadline, or when the amount is above a threshold the organization may set. |
| 4 | **Employees confirm their own timesheet each pay period, with reminders;** payroll does not wait for them. |

## Round 5 · Leave plans and balances

| # | Decision |
| --- | --- |
| 1 | **Each plan sets its own carry-over limit and expiry for days above the law's minimum, with warnings;** the law's minimum is never lost and must be scheduled within the law's window, with reminders. |
| 2 | **A negative balance is blocked unless the plan allows it, up to the plan's limit;** recovering it when employment ends needs the employee's written authorization, as for overpayments. |
| 3 | **What is paid out when employment ends is set per plan, pre-filled as: vacation and banked time as the law requires; sick and personal days not paid;** each plan or agreement can change it. |
| 4 | **Each leave plan has its own year, and one employee can hold plans on different years at the same time.** A plan's year can follow the calendar, the fiscal year, the hire or service anniversary, or the date the person joined the plan through an event (a promotion, becoming exempt, a move to another location or union). A plan can also step its service tiers on a different date from its year (for example, tiers on the anniversary, balances on the calendar year). When the law changes, the statutory minimums update on their effective date, as CanDo loads them centrally. (Wael's own answer.) |

## Round 6 · Leave requests, holidays and absences

| # | Decision |
| --- | --- |
| 1 | **CanDo never asks for sick notes or other proof of leave, and stores none;** an employer that needs proof handles it outside CanDo. |
| 2 | **A request in a blackout period or one that would drop a team below minimum staffing warns the manager, who decides;** a statutory leave is never refused for staffing. **Before submitting, the employee sees a team availability bar for the dates (green to red, by how many are already away against the minimum), with no names,** and the confirmation repeats the heads-up, so they can pick other dates first. (Wael's addition.) |
| 3 | **Managers see the leave type, but sensitive leaves (domestic violence, medical, family) show only "protected leave", with the reason for HR only; co-workers see "away"** (Wael chose this option when he revisited the question). |
| 4 | **HR is prompted to check short-term disability and accommodation after 5 consecutive working days of absence (pre-filled, editable)** (Wael chose this option when he revisited the question). |

## Round 7 · Scheduling and union rules

| # | Decision |
| --- | --- |
| 1 | **Schedule notice comes from the agreement or the law where one exists; otherwise from the organization's setting, pre-filled at 14 days.** A change after publication needs a caution and a reason, and any premium the agreement requires. |
| 2 | **Non-union extra shifts and overtime: the manager chooses or posts to the open-shift board; CanDo shows who has had the fewest extra hours, and checks overtime, rest and credentials.** Unionized staff follow their agreement's order (seniority, rotation or equal hours), with every offer and response logged. |
| 3 | **Shift swaps: the employees agree, CanDo checks eligibility, credentials, overtime and rest, and the manager approves.** |
