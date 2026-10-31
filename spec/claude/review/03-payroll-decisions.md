# 03 Payroll · Review decisions

Review started 27 Oct 2026 with Wael. Decisions are logged here round by round; the developer pack is updated when the review is complete.

**Status: applied 27 Oct 2026.** The decisions are in `dev-pack/docs/24-payroll-decisions.md`, migration `dev-pack/schema/0010_payroll_decisions.sql` and its smoke test, the register (FB-010 to FB-013 and FB-026 decided, FB-036 added), `rules/employment-standards/ca-2026-payroll-additions.json`, `rules/payroll/starter-pay-codes.json`, and the updates listed in docs/24 §14. Numbers CanDo pre-fills at setup, each organization's to change (the Q46 principle): remittance reminders 7, 3 and 1 days before the due date; former employees' access until the T4 due date plus 12 months; a parallel run of 1 pay period (never fewer).

Rounds: 1 scope and who moves the money · 2 pay runs and approvals · 3 earnings, vacation and holiday pay · 4 deductions and garnishments · 5 pay statements, banking and year-end · 6 people in several positions, funding and accounting · 7 special cases (s. 87, Quebec, sector features).

The principle from Modules 01 and 02 applies: every decision is a default each organization can change at setup or later, except legal floors and safety rules; routes and rules are the organization's, with reminders, cautions and recorded acknowledgements.

Already decided elsewhere and not asked again: Quebec payroll in phase 2 (Revenu Québec certification), with export to a certified provider until then; back-dated changes and overpayments (`docs/21` §7.1, §7.2); bank account changes (`docs/21` §9.1); overtime across several rates by the jurisdiction's rule (`docs/17` §7.2); TD1 and s. 87 fallbacks (FB-028, FB-024).

## Round 1 · Scope and who moves the money

| # | Decision |
| --- | --- |
| 1 | **CanDo builds the direct-deposit file; the employer sends it from its own bank.** No pay money passes through CanDo. |
| 2 | **The employer pays CRA source deductions and the other remittances (WCB, employer health tax, union, pension); CanDo calculates the amounts and due dates, prepares the forms and reminds before penalty dates.** |
| 3 | **CanDo builds validated T4, T4A and ROE files; the employer uploads them to CRA and ROE Web.** |
| 4 | **When an organization moves to CanDo mid-year, CanDo imports the old system's year-to-date amounts and issues one T4 per employee for the whole year** (closes docs/16 Q11). |

## Round 2 · Pay runs and approvals

| # | Decision |
| --- | --- |
| 1 | **A pay run is approved through the organization's own route** before the bank file is released. Starter route: payroll prepares, HR or finance approves; the preparer can never approve. |
| 2 | **When pre-run checks find a problem for some employees, the organization chooses what happens.** By default only the affected employees are held, with a reason, and everyone else is paid on time; the held people go into an off-cycle run once fixed. The organization can choose to stop the whole run instead. |
| 3 | **A pay date that falls on a weekend or bank holiday moves to the previous banking day,** so no one is paid late. |
| 4 | **An outside payroll provider (an accounting firm or a CanDo partner) can run payroll for several client organizations from one login, with each client's approval** of the access and what it can do; everything the provider does is recorded as theirs. |

## Round 3 · Earnings, vacation and holiday pay

Wael's guidance for this round: payroll rules must be flexible enough to treat each group of employees differently inside one organization, and to mix methods; the law's minimums always apply.

| # | Decision |
| --- | --- |
| 1 | **Vacation pay: both methods are available, and the employer chooses per group of employees.** For example, on-call and casual employees paid vacation pay on each cheque, others accruing it and being paid when they take vacation. The law's minimum percentage always applies; where the law needs the employee's agreement to pay it on each cheque, CanDo shows a caution. |
| 2 | **Proration of salaried pay for a partial period follows the law and the organization's choice,** set per pay group (working days, calendar days or scheduled hours). |
| 3 | **Unused banked overtime at year-end follows the organization's policy and approvals, and can be a mix:** for example pay out some hours and carry some forward, within the law's limits. |
| 4 | **Each organization starts from CanDo's starter catalogue of earnings codes** (with the correct tax, CPP, EI and slip settings) and renames, adds or retires codes. |

## Round 4 · Deductions and garnishments

| # | Decision |
| --- | --- |
| 1 | **Garnishments and family support orders: payroll enters each order with its document; CanDo works out the deduction and the protected amount from the law; payroll confirms the first deduction of each order.** |
| 2 | **Employees start or stop voluntary deductions (charity, parking, social club) in self-service, with the approval the organization sets** (none, payroll or HR). |
| 3 | **When a pay cannot cover every deduction, the law's order comes first (taxes, support orders, garnishments), then the organization's order; the shortfall becomes arrears recovered as the organization sets for each deduction,** never below the protected minimum. |
| 4 | **Money an employee owes when leaving (advance, equipment, unearned training) is taken from the final pay only with the employee's written authorization and within the law's limits,** as for overpayments (Module 01); otherwise HR follows up. |

## Round 5 · Pay statements, banking and year-end

| # | Decision |
| --- | --- |
| 1 | **Pay statements and T4 slips follow CRA's rule:** current employees get them in CanDo self-service without needing to consent, and on paper if they ask; former employees and people on extended leave get them electronically only if they consented, otherwise on paper; email only with consent. *(Corrected 27 Oct 2026: the first wording said CRA requires consent from everyone, which was my error. Wael chose to follow CRA's rule.)* |
| 2 | **Former employees keep a limited self-service login to their own pay statements, slips and ROE,** for a period the organization sets (for example until the next T4 plus one year). |
| 3 | **Direct-deposit files for all major banks at launch:** the big six banks, Desjardins and the main credit unions. |
| 4 | **CanDo prepares the ROE from payroll data when a termination or leave needs one; HR reviews the reason code and comments, then uploads the file to ROE Web.** |

## Round 6 · People in several positions, funding and accounting

| # | Decision |
| --- | --- |
| 1 | **A pay line with no cost coding takes the assignment's, then the position's, then the unit's coding; if none has any, it goes to a suspense account and finance gets a task. Pay is not delayed** (FB-011 confirmed). |
| 2 | **Pay over a grant's cap, or not eligible for it, moves to the fallback fund by default, with alerts to finance at 90, 60 and 30 days;** each funding source can be set differently (FB-012 confirmed; closes docs/16 Q12). |
| 3 | **Retro or a correction that reaches a closed grant goes where finance set that grant up to send it** (successor grant, fallback fund or suspense), listed on a funder adjustment report (FB-013 confirmed). |
| 4 | **Payroll reaches the organization's accounting system through journal files in that system's import format;** direct connections come later (closes docs/16 Q14). |

## Round 7 · Special cases

| # | Decision |
| --- | --- |
| 1 | **When a collective agreement does not say how two premiums combine, CanDo stops that pay line and asks labour relations to complete the agreement's rule;** no guessing (FB-010 confirmed). The employee is handled as the organization set for failed checks (held by default, Round 2). |
| 2 | **A one-time payment for someone in several positions must name its position;** it cannot be saved until someone picks it (FB-026 decided: refuse until named). |
| 3 | **A parallel run is required before an organization goes live on CanDo payroll:** at least one pay period alongside the old system, with every difference explained. |
| 4 | **CanDo loads and tests the CRA tables (January and July) and other statutory changes centrally, once for every organization;** organizations cannot change statutory tables (closes docs/16 Q7). |
