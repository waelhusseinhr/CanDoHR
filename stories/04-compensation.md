# Stories · 04 Compensation Management

Requirements: `requirements/04-compensation.md`. Design: `docs/19`, and the owner's Module 04 review in `docs/25`, which wins where these stories differ. Its scenarios COMP-010 to COMP-035 are listed at the end.

**COMP-001 — Salary ranges by grade.** As a compensation analyst, I want effective-dated ranges per grade, so that offers and increases stay within policy.
- AC1: Ranges have min ≤ mid ≤ max (database check). A new range version takes effect on its date, and compa-ratios recalculate as of any date.

**COMP-002 — Agreement grids are the source for union jobs.** AC: for assignments covered by an agreement, rates come from the agreement version's wage grid. Manual rates are blocked unless the agreement allows them, with a reason.

**COMP-003 — Step progression job.** As a payroll administrator, I want grid steps to advance automatically when hours or months are reached.
- AC1: Given progression `every: 1820 hours_paid`, when an employee's paid hours since the last step reach 1,820, then a `compensation.set_rate` change set is drafted, effective the next pay period start, for HR confirmation.

**COMP-004 — Merit cycle.** As a manager, I want a worksheet with guidelines and budget, so that I can propose increases fairly.
- AC1: The worksheet shows each employee's current rate, compa-ratio, performance rating (from Module 07) and guideline, with a running budget total. The cycle starts from the organization's eligibility rules and guideline method (`docs/25` §6.1, §6.2).
- AC2: A recommendation outside the guideline needs a written reason and HR's approval, as the organization set (`docs/25` §6.3).
- AC3: Approved decisions load as rate change sets on the cycle's effective date. If that date is in the past, retro requests are created. Letters are released to self-service after HR reviews them (`docs/25` §6.4).

**COMP-005 — Market pricing.** AC: benchmark jobs are matched to survey jobs with match quality. Market percentiles are aged to a common date with the configured aging factor, and the method is stored.

**COMP-006 — Pay equity analysis.** As a compliance officer, I want job-class comparisons by gender predominance, so that Ontario, Quebec and federal pay equity obligations are met.
- AC1: Job classes have evaluation scores and predominance. The report compares female-predominant classes to male comparators by value band and flags gaps.

**COMP-007 — Pay transparency reporting.** AC: BC pay transparency reports (by employer size and year) are produced from payroll data with the required metrics, suppressing groups under the minimum size. Federal pay equity and employment equity reports are built at launch too (`docs/25` §8.3).

**COMP-008 — Total rewards statement.** AC: a statement per employee in English or French shows pay, employer CPP, EI and pension contributions, benefits costs and time off value, from actual payroll data. It is produced on request by default; the organization can choose once a year or once a year plus self-service (`docs/25` §8.4).

**COMP-009 — Public salary disclosure.** AC: for tenants subject to a disclosure statute (for example Ontario's list for $100,000 and over), the report lists name, position, salary paid and taxable benefits per the statute's definitions for the calendar year. HR and finance review it and the organization's route approves it before it is published (`docs/25` §10.1).

## Decisions from the owner's review

The scenarios below come from `docs/25` §13, which gives the expected result, the check and the build step for each.

| ID | Story |
| --- | --- |
| COMP-010, COMP-011 | The philosophy approved by an executive before a market-based structure; structures approved through the organization's route |
| COMP-012, COMP-013 | Generic survey imports; market ratios hidden from managers until switched on |
| COMP-014, COMP-015 | Spreads pre-filled by track; ranges per location group |
| COMP-016, COMP-017 | Catch-up plans below the minimum; above the maximum, the manager proposes |
| COMP-018 to COMP-020 | Promotions at least the new minimum and 5%; demotion pay cuts need the caution; acting pay chosen at setup |
| COMP-021 to COMP-023 | Cycles from the organization's settings; exceptions with a reason and HR; letters released by HR |
| COMP-024 to COMP-028 | Payouts through the route; clawbacks from the signed agreement; proration by eligible days; basic commissions; long-term grants |
| COMP-029 to COMP-032 | What employees see; pay gap groups never below 10; BC and federal reports; statements on request |
| COMP-033, COMP-034 | Disclosure lists approved before publication; bargaining costed in scenarios |
| COMP-035 | The competency model published as CanDo's starting framework |
