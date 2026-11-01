# 05 Benefits Administration · Review decisions

Review started 28 Oct 2026 with Wael. Decisions are logged here round by round; the developer pack is updated when the review is complete.

**Status: applied 28 Oct 2026.** The decisions are in `dev-pack/docs/26-benefits-decisions.md`, migration `dev-pack/schema/0012_benefits_decisions.sql` and its smoke test, the register (FB-020, FB-021 and FB-023 decided), `rules/benefits/benefit-change-rule-templates.json`, the several-positions reference and cases (coordination decided by HR; change rules by employment type and to the end of severance), and the updates listed in docs/26 §14. Pre-filled, each organization's to change (the Q46 principle): dependents' age-out notice 60 days; late enrolment starting from evidence of insurability for life and disability and limited coverage for dental; elections roll over. Chosen at setup with no CanDo default: the life event window, how far back premium adjustments go, each plan's waiting period, what happens to coverage during each unpaid non-statutory leave, and when coverage ends on termination for each class. Interpretations: coordination shows a plan contract's order beside HR's decision but never applies it by itself; coverage on termination uses the existing benefit-change rules, which now also match employment type and can run to the end of severance; statutory leaves always follow the law and only the contribution method is chosen; outside Ontario the decision waits for a caution and a reason.

Planned rounds: 1 scope and partners · 2 eligibility and enrolment · 3 people in several positions and two agreements · 4 leaves, disability and termination · 5 premiums, billing and taxable benefits · 6 pensions, retirement and retirees.

The principle from Modules 01 to 04 applies: every decision is a default each organization can change at setup or later, except legal floors and safety rules; routes and rules are the organization's, with reminders, cautions and recorded acknowledgements; CanDo pre-fills its suggested numbers at setup and the organization can change them (Q46).

Already decided elsewhere and not asked again: benefit changes when one position ends come from the organization's rules or HR, never below the statutory floor (`docs/20` §6.2, AGENTS rule 38); plan eligibility by employer, agreement or position (`docs/20` §6.1); benefits and practice benchmarking (`docs/19` §8, `docs/25`); no medical information stored (`requirements/05`); each deduction states its shortfall rule, and a premium shortfall never cancels coverage by itself (`docs/24` §6.3); Quebec payroll in phase 2.

## Round 1 · Scope and partners

| # | Decision |
| --- | --- |
| 1 | **Spending accounts are administered by a partner** (a carrier or third-party administrator pays claims); CanDo holds allocations, balances, carry-forward and taxable amounts, and does no claims handling. |
| 2 | **Carrier files: a generic enrolment and change file at launch, then each carrier's own format built as anchor customers need it** (closes docs/16 Q6 for carriers). |
| 3 | **Benefits advisors and brokers get an included, read-only role the organization grants:** plan design, enrolment counts and costs; individual employee data only if the organization allows it. |
| 4 | **The AI enrolment assistant comes later, with the platform assistant, and stays off until the organization switches it on;** it answers only from the plan booklet and never recommends an election. |

## Round 2 · Eligibility and enrolment

| # | Decision |
| --- | --- |
| 1 | **The waiting period has no CanDo starting number: the organization sets it for each plan (or class) at setup** — none, days, months, first of the month after, or hours worked. |
| 2 | **The life event window has no CanDo starting number: the organization sets it at setup,** and each plan can set its own. |
| 3 | **Late enrolment follows each plan's rule;** the starting rule is evidence of insurability for life and disability and limited coverage for dental, as carriers usually require. |
| 4 | **When an employee does nothing in open enrolment, current elections roll over;** for a flex plan the organization can set a default option instead. |

## Round 3 · People in several positions and two agreements

| # | Decision |
| --- | --- |
| 1 | **When a benefit rule must pick one of two collective agreements for a person, HR decides each time and records why;** CanDo makes no automatic choice (FB-023 decided; closes docs/16 Q13). |
| 2 | **When two plans of the same kind cover one person, HR sets which pays first for that person and records why;** CanDo shows any order a plan contract sets (for example a union trust plan's) beside the decision (FB-020 decided; closes docs/16 Q37). |
| 3 | **Variable-hour eligibility uses the look-back period and re-test schedule the organization sets per plan or class;** CanDo re-tests and proposes changes for HR to confirm. |
| 4 | **When a position ends and no benefit-change rule matches, HR decides, with the statutory floor shown** (FB-021 confirmed). |

## Round 4 · Leaves, disability and termination

| # | Decision |
| --- | --- |
| 1 | **During a statutory leave, the employee chooses how to pay their share:** ahead, as arrears on return, or through payroll while they still get pay (a top-up). Each organization can customize this (limit the choices, or pay the employee's share itself). Benefits stay in force as the law requires. |
| 2 | **Unpaid leaves that are not statutory: all three options are available** — continue at the employee's cost, continue employer-paid for a period, or suspend and restart on return — and the organization sets one for each leave type and class at setup. |
| 3 | **On termination, the organization sets when coverage ends for each class at setup:** the termination date, the end of that month, or the end of the notice or severance period; never earlier than the law requires. |
| 4 | **Benefits during statutory notice outside Ontario: until employment counsel confirms each province, CanDo stops the decision and shows HR a caution about common-law reasonable notice;** HR decides and records why (keeps the current design; docs/16 Q36 stays an item to verify). |

## Round 5 · Premiums, billing and dependents

| # | Decision |
| --- | --- |
| 1 | **How far back premium adjustments go automatically (late enrolments, life events, rate changes) has no CanDo starting number: the organization sets it at setup;** anything older goes to HR to approve. |
| 2 | **Carrier invoices are imported or entered, reconciled to enrolment by employee, differences listed, and approved through the organization's route before they go to accounts payable;** self-billing is available per carrier. |
| 3 | **The employee and HR are told 60 days before a dependent child ages out (pre-filled, editable),** and proof of full-time studies is asked each year. |
| 4 | **Opting out of health or dental is allowed where the plan permits, with proof of the other coverage;** Quebec opt-outs respect RAMQ rules. |

## Round 6 · Pensions, union trusts and retirees

| # | Decision |
| --- | --- |
| 1 | **Public sector pension plan files for the big four at launch: the BC Municipal Pension Plan, OMERS, HOOPP and LAPP;** other plans as customers need them, with a generic contribution file meanwhile (closes docs/16 Q6 for pension plans). |
| 2 | **Someone who becomes eligible for a pension plan that is mandatory for them is enrolled automatically on the eligibility date;** the employee is told, HR confirms, and contributions start in the next pay. |
| 3 | **Union benefit trusts at launch through a generic file:** contribution rates from the agreement, hours-based remittances and member eligibility; each trust's own format built per customer. |
| 4 | **Retiree benefits come in a later phase.** |
