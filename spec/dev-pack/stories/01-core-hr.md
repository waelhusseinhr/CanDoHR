# Stories · 01 Core HR & Position Management

Requirements: `requirements/01-core-hr-position-management.md`. Design: `docs/03`, `docs/04`, `docs/05`.

## Records

**CORE-001 — Hire into a position.** As an HR administrator, I want to hire a person into a vacant position, so that payroll, benefits and onboarding start without re-keying.
- AC1: Given a vacant position with FTE 1.0, when I commit `employment.hire` with an assignment at FTE 1.0, then the position shows filled from the start date, and the events `employment.hired` and `position.changed` are emitted.
- AC2: Given the work location is in Manitoba, then the payroll profile's derived tax province is MB and a TD1MB task is created for the employee.
- AC3: Given the rate is below the location's minimum wage, then validation fails with `BELOW_MINIMUM_WAGE`, citing the rule source.

**CORE-002 — One person, several assignments.** As an HR administrator, I want to give someone a second concurrent assignment, so that part-time and casual work in two departments is tracked correctly.
- AC1: Given an employee with a primary assignment, when I add a casual assignment in another unit, then both appear on the profile, each with its own manager, agreement and pay rate, and exactly one is primary.
- AC2: Payroll aggregates both assignments for statutory maximums (verified in PAY stories).

**CORE-003 — Rehire.** As an HR administrator, I want a returning employee to reuse their person record, so that history and service bridging work.
- AC1: Given a terminated employment, when I rehire, then a new employment or reactivated employment is created on the same person, and bridging rules from the agreement determine `continuous_service_date`.

**CORE-004 — Sensitive data.** As a payroll administrator, I want SIN and date of birth encrypted and masked, so that privacy is protected.
- AC1: SIN is stored only in `person_sensitive.sin_enc`. API responses show `*** *** 123` unless revealed with a reason.
- AC2: SIN validation uses the Luhn check digit and rejects invalid numbers.

## Positions and organization

**CORE-010 — Create a position under budget control.** As an HRBP, I want new positions to pass budget approval, so that headcount is controlled.
- AC1: Given a new position whose annual cost (midpoint plus burden) exceeds the unit's remaining budget, then validation warns `OVER_BUDGET` and routes to Finance approval.

**CORE-011 — Prevent over-filling.** As an HR administrator, I want the system to block a second full-time holder in a 1.0 FTE position, unless an overlap is approved.
- AC1: Given a filled 1.0 position, when I assign another 1.0 holder, then error `OVER_FTE`, unless the assignment type is `overlap` with an end date and approval.

**CORE-012 — Vacancy on departure.** As a manager, I want a vacancy created automatically when someone leaves, so that I can backfill quickly.
- AC1: Given a termination effective 15 Nov, then from 15 Nov the position is vacant, `position.vacated` is emitted, and a backfill task (backfill, modify or eliminate) is created for the manager.

**CORE-013 — Move a department.** As an HR administrator, I want to move a department and everything below it in one action, so that reorganizations are quick.
- AC1: Given a unit with 3,000 people, when I commit `org_unit.move`, then one operation is written, and each employee's derived reporting chain changes from the effective date without 3,000 assignment rows being written.

**CORE-014 — Light mode to position mode.** As a small employer, I want to start without positions and switch later.
- AC1: Given a light-mode tenant, when I enable position mode, then a position is created per assignment with the same reporting lines, and the org chart looks the same before and after.

## Org chart (see docs/04 for the full acceptance tests)

**CORE-020 — Drag a position under a new manager.** AC: docs/04 §8 test 1.
**CORE-021 — Edit manager on the profile updates the chart.** AC: docs/04 §8 test 2.
**CORE-022 — Cross-province move with retro.** AC: docs/04 §8 test 3.
**CORE-023 — Plans.** AC: docs/04 §8 test 5.
**CORE-024 — Keyboard move.** AC: docs/04 §8 test 6.
**CORE-025 — Time travel.** As an HR administrator, I want to see the chart as of any date. AC: given approved future changes, the chart as of their date shows them, and today's chart shows "upcoming" badges.

## Agreements and seniority

**CORE-030 — Link units to agreements.** As a labour relations specialist, I want each bargaining unit linked to its agreement version, so that every module applies the right terms.
- AC1: Given a job whose default bargaining unit is INSIDE, when an assignment is created, then the agreement defaults to the INSIDE unit's agreement, and an exclusion needs a reason.

**CORE-031 — Seniority list.** As a labour relations specialist, I want seniority lists generated from the ledger with tie-breakers, so that postings and layoffs follow the agreement.
- AC1: Given two employees with the same seniority date, then the order follows the agreement's tie-breakers (hire date, then lot).
- AC2: The published list records its posting date and the challenge-period end date.

## Self-service

**CORE-040 — Employee updates address.** As an employee, I want to update my address, so that my records and slips are right.
- AC1: Given I move to another province, then the system asks whether my work location also changed; my tax province does not change unless my work location changes or HR overrides it with a reason.

**CORE-041 — Legal name change needs evidence.** AC: a legal name change requires an uploaded document and HR approval; preferred name changes take effect immediately.
