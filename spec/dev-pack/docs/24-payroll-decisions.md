# 24 · Payroll decisions

Oct 27, 2026 · @Wael

This document records the owner's review of Module 03 (Payroll) and turns each decision into something the build can follow: a setting with its default, a database check, a rule the organization sets per group of employees, a starter copy the organization edits, or a screen behaviour. The review went round by round; the working record is `claude/review/03-payroll-decisions.md` in the project.

It covers who moves the money and files with governments, pay run approval and failed checks, pay dates, the parallel run before going live, outside payroll providers, vacation pay, proration, banked overtime, the starter earnings codes, garnishments and other deductions, shortfalls and arrears, money an employee owes, pay statements and slips, former employees' access, banks, the ROE, cost coding and funding, one-time payments for people in several positions, accounting journals, premium combinations and the statutory tables.

**Precedence.** On these topics this document wins over `requirements/03`, `stories/03-payroll.md`, `docs/06` and `docs/17` §8 to §10 where it adds to them, and over `docs/20` §4.3 on one-time payments. `docs/22` still wins on values, defaults, languages and fallbacks. §14 lists every place that changes. The schema is `schema/0010_payroll_decisions.sql` (migration 0010, Step 1), checked by `tests/schema/schema_0010_smoke.sql`. New values from the law are in `rules/employment-standards/ca-2026-payroll-additions.json`; the starter earnings, benefit and deduction codes are in `rules/payroll/starter-pay-codes.json`.

**The owner's rules for this module.**

1. CanDo calculates, prepares and reminds; the employer moves the money, pays the remittances and uploads the filings (§3). No pay money passes through CanDo.
2. Payroll rules are the organization's, and they must be able to treat each group of employees differently inside one organization and to mix methods (for example casual staff paid vacation pay on each cheque, everyone else accruing it). The law's minimums always apply.
3. Routes, approvals and cautions work as in Module 02 (`docs/23` §2): starter copies the organization edits, a recorded acknowledgement when a user goes past a caution on purpose, and no one approves their own work.
4. No guessing: where a rule, an agreement or a setting is missing, CanDo stops and asks the person who owns it.

---

## 1. Decisions at a glance

| # | Decision | Setting or rule | Section |
| --- | --- | --- | --- |
| R1.1 | CanDo builds the direct-deposit file; the employer sends it from its own bank | Bank file under dual control | §3.1 |
| R1.2 | The employer pays CRA and the other remittances; CanDo calculates amounts and due dates, prepares the forms and reminds before penalty dates | `remittances.reminder_days`: 7, 3 and 1 days before, pre-filled at setup | §3.2 |
| R1.3 | CanDo builds validated T4, T4A and ROE files; the employer uploads them to CRA and ROE Web | Files | §3.3 |
| R1.4 | At a mid-year move to CanDo, the old system's year-to-date amounts are imported and CanDo issues one T4 per employee for the whole year | Go-live YTD (`docs/17` §10) | §3.4 |
| R2.1 | A pay run is approved through the organization's route before the bank file is released; the preparer can never approve | `pay_run` route; `SELF_APPROVAL` | §4.1 |
| R2.2 | Failed pre-run checks: the organization chooses; by default only the affected employees are held, with a reason, and paid off-cycle once fixed | `payroll.failed_check_handling`: hold affected | §4.2 |
| R2.3 | A pay date on a weekend or bank holiday moves to the previous banking day | Pay calendar | §4.3 |
| R2.4 | An outside payroll provider can work for several client organizations from one login, with each client's approval of what it can do; everything it does is recorded as its own | `platform.provider_access_grant` | §4.5 |
| R3.1 | Vacation pay: accrue and pay when taken, or pay on each cheque, chosen per group of employees; the law's minimum always applies; a caution where the law needs the employee's agreement | `payroll.vacation_pay_rule`; caution `payroll.vacation_pay_each_cheque` | §5.1 |
| R3.2 | Proration of salaried pay follows the law and the organization's choice, per pay group | `payroll.default_proration_method`: chosen at setup | §5.2 |
| R3.3 | Banked overtime at year-end follows the organization's policy and approvals, and can be a mix (pay some, carry some) within the law | `timeleave.banked_time_policy`; `banked_time_payout` route | §5.3 |
| R3.4 | Each organization starts from CanDo's starter catalogue of earnings codes and renames, adds or retires codes | `rules/payroll/starter-pay-codes.json` | §5.4 |
| R4.1 | Garnishments and support orders: payroll enters the order with its document; CanDo works out the deduction and the protected amount; payroll confirms the first deduction | `GARNISHMENT_NOT_CONFIRMED` | §6.1 |
| R4.2 | Employees start or stop voluntary deductions in self-service, with the approval the organization sets | `voluntary_deduction` route | §6.2 |
| R4.3 | When a pay cannot cover every deduction: the law's order, then the organization's; the shortfall becomes arrears recovered as each deduction says, never below the protected minimum | `pay_code.arrears_recovery` | §6.3 |
| R4.4 | Money owed (advance, equipment, unearned training) is taken only with the employee's written authorization and within the law's limits | `payroll.recovery_authorization` | §6.4 |
| R5.1 | Pay statements and slips follow CRA's rule: self-service for current employees, paper on request; former employees and people on extended leave electronically only with consent; email only with consent | `payroll.delivery_method()`; FB-036 | §7.1 |
| R5.2 | Former employees keep a limited login to their own pay statements, slips and ROE for a period the organization sets | `self_service.former_employee_access`: the T4 due date plus 12 months, pre-filled at setup | §7.2 |
| R5.3 | Direct-deposit files for all major banks at launch | Bank profiles | §7.3 |
| R5.4 | CanDo prepares the ROE; HR reviews the reason code and comments; the employer uploads it to ROE Web | `ROE_NOT_REVIEWED` | §7.4 |
| R6.1 | A pay line with no cost coding takes the assignment's, the position's, then the unit's; otherwise suspense and a finance task; pay is not delayed | FB-011 decided | §8.1 |
| R6.2 | Pay over a grant's cap or not eligible moves to the fallback fund by default, with alerts at 90, 60 and 30 days; each source can be set differently | FB-012 decided; `funding.default_cap_behaviour`, `funding.default_alert_days` | §8.1 |
| R6.3 | Retro or a correction reaching a closed grant goes where finance set that grant up to send it, on a funder adjustment report | FB-013 decided; `funding.default_post_close_policy` | §8.1 |
| R6.4 | Payroll reaches the accounting system through journal files in that system's import format; direct connections later | Journal export | §8.3 |
| R7.1 | Two premiums the agreement does not combine: CanDo stops that pay line and asks labour relations to complete the rule; the employee is handled as set for failed checks | FB-010 decided; `UNRESOLVED_INTERACTION` | §5.5 |
| R7.2 | A one-time payment for someone in several positions must name its position | FB-026 decided; `payroll.one_time_allocation`: assignment | §8.2 |
| R7.3 | A parallel run is required before going live: at least one pay period alongside the old system, every difference explained | `payroll.parallel_run_periods`: 1, never fewer | §4.4 |
| R7.4 | CanDo loads and tests the CRA tables (January and July) and other statutory changes centrally; organizations cannot change statutory tables | Rule editions | §9 |

R5.1 was corrected on 27 Oct 2026. The first wording said CRA requires consent from everyone; CRA's page says a secure portal needs no consent for current employees. The owner chose to follow CRA's rule.

---

## 2. How the module is set up

### 2.1 Who does what

| Task | CanDo | The employer |
| --- | --- | --- |
| Net pay | Calculates, builds the direct-deposit file for the employer's bank | Approves the run through its route, releases the file under dual control, sends it from its own bank account |
| Source deductions and other remittances (CRA, workers' compensation, employer health tax, unions, pension plans, support and garnishment payees) | Calculates amounts and due dates, prepares the forms and vouchers, reminds payroll before each due date | Pays them |
| T4, T4A, other slips and ROEs | Builds and validates the files; prepares the ROE from pay data | Reviews (HR for the ROE), uploads to CRA and ROE Web |
| Statutory tables (CRA, provinces) | Loads, tests and activates each edition centrally for every organization | Nothing to load; sees which edition paid each result |
| Pay rules (vacation pay, banked time, proration, deductions, codes) | Starter copies and checks against the law | Sets them per group of employees and changes them over time |

### 2.2 Settings

| Setting | Decides | CanDo default | Set per |
| --- | --- | --- | --- |
| `payroll.failed_check_handling` | When pre-run checks fail for some employees: hold only those employees (they are paid off-cycle once fixed), or stop the whole run | Hold affected employees | Organization, employer |
| `payroll.parallel_run_periods` | Pay periods run alongside the old system, every difference explained and accepted, before a payroll account's first live run | 1 (never fewer than 1) | Organization, employer |
| `remittances.reminder_days` | Days before a remittance's due date when payroll is reminded | 7, 3 and 1, pre-filled at setup | Organization, employer |
| `self_service.former_employee_access` | How long a former employee keeps a login to their own pay statements, slips and ROE: until the T4 for their last year is due, plus this many months | 12 months, pre-filled at setup | Organization, employer |
| `payroll.default_proration_method` | How salaried pay is prorated for a partial period: calendar days, working days or scheduled hours | **None: chosen at setup for each pay group** | Organization, employer |
| `payroll.one_time_allocation` | A one-time payment for someone in several positions names its position (`assignment`), or unnamed payments are shared by earnings (`earnings_share`) | Names its position | Organization, employer |
| `funding.default_cap_behaviour` | What happens to pay over a funding source's cap or not eligible for it (each source can say otherwise) | Spill to the fallback source (decided, R6.2) | Organization |
| `funding.default_alert_days` | Days before a source runs out or ends when finance is alerted | 90, 60 and 30 (decided, R6.2) | Organization |
| `funding.default_post_close_policy` | Where retro or a correction goes when it reaches a closed source | The fallback source (decided, R6.3) | Organization |

Pre-filled numbers follow the owner's rule from Module 02 (Q46): the setup screen shows CanDo's suggestion, and the organization keeps it or changes it. The three `funding` settings were created in migration 0008 (`docs/22` §2) and are marked decided by 0010.

### 2.3 Chosen at setup

`payroll.default_proration_method` has no CanDo default because the owner left it to the law and each organization (R3.2). The setup wizard asks it for each pay group, showing what the law allows where it says anything; a pay group cannot be created without it (`SETTING_NOT_SET`, `docs/22` FB-003).

### 2.4 Routes and cautions

Three new kinds of subject use the organization's routes (`docs/23` §2.2): `pay_run`, `voluntary_deduction` and `banked_time_payout`. Starter routes:

| Route | Steps | Decision |
| --- | --- | --- |
| Pay run approval | Finance approves (setup asks whether HR approves instead, or adds a step); never the person who prepared the run | R2.1 |
| Voluntary deduction | Payroll approves; the organization can make it HR, or remove the step for no approval | R4.2 |
| Banked time payout | The requester's manager, then payroll | R3.3 |

No one approves their own pay run, voluntary deduction or payout request (`SELF_APPROVAL`). For a pay run the requester is the person who created it.

New caution: `payroll.vacation_pay_each_cheque`, shown when a vacation pay rule pays on each cheque (§5.1). It states the law (`shows_law`); a reason is needed only if the organization asks (`cautions.reason_required`).

---

## 3. Money, remittances and filings

### 3.1 The bank file (R1.1)

CanDo builds the direct-deposit file for the employer's own bank from an approved run (`docs/06` §9: only approved runs, under dual control, with control totals). The employer uploads or sends it through its bank. CanDo never holds or moves pay money, so there is no trust account, no funding step and no CanDo bank in between. Accounts in the file are only those `payroll.bank_account_usable()` allows (`docs/21` §9.1). Automatic delivery by SFTP is still open (`docs/16` Q21).

### 3.2 Remittances (R1.2)

For each payroll account CanDo works out what is owed and when: CRA source deductions by remitter type (T4001), workers' compensation, employer health tax, union dues, pension contributions, and payments to courts and agencies for support orders and garnishments. It prepares the remittance forms and vouchers and shows a remittance calendar. Payroll is reminded on each of the days in `remittances.reminder_days` before a due date (7, 3 and 1 days before, pre-filled); the reminder names the payee, the amount and the due date, and stops once payroll records the payment. CanDo does not pay anyone.

### 3.3 Filings (R1.3)

CanDo builds T4, T4A and other slip files in CRA's XML format, validated against the schema downloaded for the year (AGENTS rule 12), and the ROE file for ROE Web (§7.4). The employer uploads them. CanDo records who downloaded each file and when, and the confirmation number the employer enters.

### 3.4 Moving to CanDo mid-year (R1.4)

When an organization moves to CanDo during a year, the old system's year-to-date amounts are imported by person, payroll account, province and code (`docs/17` §10). CanDo then issues one T4 per employee for the whole year, combining the imported amounts with its own; the old system issues none for that year. This closes `docs/16` Q11 and `docs/17` E1.

---

## 4. Pay runs

### 4.1 Approval through the organization's route (R2.1)

A pay run moves through `draft → inputs_locked → calculated → reviewed → approved → finalized → paid` (`docs/06` §2). It becomes `approved` only when it names its route and its final approver and the route is complete (`platform.route_complete()`; `ROUTE_APPROVALS_MISSING`). The person who created the run can approve no step of it (`SELF_APPROVAL`). Simulations need no approval. The bank file is then released under dual control as before.

### 4.2 Failed pre-run checks (R2.2)

The pre-run checks are those in `requirements/03` (missing bank details, no rate, rate below minimum wage, negative net, terminated with active pay, an undefined premium combination and the others). A missing TD1 is not a failure: it has its own fallback (FB-028).

With `payroll.failed_check_handling` = `hold_affected` (the default), payroll holds each affected employee from the run with the failed check and a reason (`payroll.pay_run_hold`); everyone else is paid on time. Once the problem is fixed, the held employee is paid in an off-cycle run, and the hold records which run paid them. With `stop_run`, the run cannot be approved while any hold is open (`PAY_RUN_HAS_FAILED_CHECKS`).

A check that guards the law (below minimum wage, pay below a protected minimum) is fixed, never overridden.

### 4.3 Pay dates on weekends and holidays (R2.3)

A pay date that falls on a Saturday, a Sunday or a bank holiday moves to the previous banking day, so no one is paid late (`docs/06` §1). Bank holidays come from the holiday calendars in the rules repository. Moving the date earlier can move a pay into an earlier tax year (a 1 January pay date paid on 31 December): the edition and the tax year follow the actual pay date (AGENTS rule 6), and the calendar screen shows the change before the year's calendar is approved.

### 4.4 The parallel run before going live (R7.3)

Before a payroll account's first live pay run, payroll runs at least `payroll.parallel_run_periods` pay periods in CanDo as simulations alongside the old system (1 by default, never fewer). The old system's totals are imported by person and code, every difference is explained, and finance or the payroll lead accepts the parallel run (`payroll.parallel_run`: accepted only with its differences, by a named person). Until enough parallel runs are accepted, the first live run cannot be finalized (`PARALLEL_RUN_REQUIRED`). Later runs are not affected. `requirements/03` asked two cycles; that is now the organization's choice through the setting.

### 4.5 Outside payroll providers (R2.4)

An accounting firm or a CanDo partner that runs payroll for several organizations has its own organization in CanDo and one login per person. A client gives a provider access through `platform.provider_access_grant`: which provider user, which capabilities (`ref.provider_capability`: prepare runs, approve runs, build files, see or change employee pay records, run reports) and for how long. Only a user of the client organization approves a grant (`PROVIDER_GRANT_NOT_CLIENT`), and the provider user must belong to the provider's organization (`PROVIDER_USER_UNKNOWN`). The provider can act for the client only while an approved grant covers that capability and date (`platform.provider_can()`); the client can revoke it at any time. Everything the provider does is recorded as the provider user's, with the provider's organization, in the client's audit trail.

A provider sees one client at a time. Switching clients starts a new request context with that client's `app.tenant_id`; the identity Worker checks the grant before it issues the context.

---

## 5. Earnings

### 5.1 Vacation pay per group of employees (R3.1)

Each organization sets vacation pay rules (`payroll.vacation_pay_rule`):

- **method:** accrue the vacation pay and pay it when vacation is taken (`accrue_pay_when_taken`), or pay it on each cheque (`pay_each_cheque`);
- **rate:** the law's minimum for the employee's service in their jurisdiction (`law_minimum`, read from the employment standards edition), or a higher fixed percentage;
- **who it covers:** `applies_to` with pay groups, employment types (the organization's types, by category), collective agreements, employers and org units; `{}` covers everyone;
- **priority:** the first active rule whose scope matches the position applies.

So an organization can pay casual and on-call staff on each cheque and let everyone else accrue at 6%, as in the review. A position no rule covers stops with `VACATION_PAY_RULE_MISSING`; CanDo never assumes a method. An unknown scope key is refused (`PAYROLL_SCOPE_UNKNOWN`). A fixed percentage below the law's minimum for an employee is paid at the minimum (AGENTS rule 42 applies the same way to agreements).

Paying on each cheque needs the employee's written agreement in some provinces (Ontario ESA s. 36(3); British Columbia ESA s. 58, in writing or by collective agreement). When a rule pays on each cheque, CanDo shows the caution `payroll.vacation_pay_each_cheque`, so payroll checks the law for those employees and gets their agreement where it is needed (`vacation_pay_each_cheque` in the rules file). The employee still takes their vacation time.

### 5.2 Proration (R3.2)

Each pay group states how salaried pay is prorated for a partial period: calendar days, working days or scheduled hours (`payroll.pay_group.proration_method`, filled from `payroll.default_proration_method`, which the organization chooses at setup). The engine applies it as `docs/06` §3 says. Where the law sets a method for a case (for example final pay), the law's method applies.

### 5.3 Banked overtime (R3.3)

Each organization sets banked time policies (`timeleave.banked_time_policy`) with the same scopes and priority as vacation pay rules:

| Year-end action | What happens to unused hours |
| --- | --- |
| `pay_out` | All are paid out |
| `carry_over` | All are carried to the next year |
| `carry_then_pay` | Up to `carry_limit_hours` are carried; the rest are paid out |

A policy also says whether employees can ask for a payout during the year (`employee_payout_requests`); a request goes through the `banked_time_payout` route (`BANKED_PAYOUT_NOT_ALLOWED` where the policy does not allow it). A position no policy covers stops with `BANKED_TIME_POLICY_MISSING`. Payouts are taxed with the bonus method (`docs/06` §4).

The law's limits come first: where a jurisdiction requires banked hours to be taken or paid within a period, or paid on request or at termination (Ontario ESA s. 22(7); British Columbia ESA s. 42, values `banked_time` in the rules file), CanDo pays them as the law requires whatever the policy says.

### 5.4 Starter earnings codes (R3.4)

`rules/payroll/starter-pay-codes.json` holds 27 starter codes (the cash award and taxable gift codes were added by `docs/31` §6.1) (regular pay, overtime, statutory holiday pay, vacation pay, banked time payout, bonus, retro, allowances, taxable benefits, union dues, pension, charity, garnishment and others) with their kind and their tax, CPP, EI and vacation flags. The flags are statutory facts: every entry is `verify_at_load` until checked against CRA's T4001 and the year's chart of types of remuneration, and the Step 9 loader copies only verified entries. Slip boxes and other information codes are set at that check. Each organization renames, adds or retires codes; a change to a statutory flag needs payroll's review and is recorded.

### 5.5 Premiums the agreement does not combine (R7.1)

When an agreement does not say how two premiums or pay sources combine, CanDo stops that pay line with `UNRESOLVED_INTERACTION` and gives labour relations a task to complete the agreement's rule (`docs/08` §5; FB-010 decided). It never picks a combination. The employee is then handled as the organization set for failed checks (§4.2): held by default and paid off-cycle once the rule is complete.

---

## 6. Deductions

### 6.1 Garnishments and support orders (R4.1)

Payroll enters each order (`payroll.garnishment_order`) with its kind (family support, CRA requirement to pay, federal garnishment, provincial garnishment, other), the law it is made under, the issuer, its reference, its terms and the order itself as a document. CanDo works out each deduction and the amount that stays protected from the law (`garnishment_protection` in the rules file), and the priority between several orders. Payroll checks and confirms the first deduction of each order before it is taken (`GARNISHMENT_NOT_CONFIRMED`); the order is then active until it is satisfied, suspended or withdrawn. Remittance to the court or agency is a remittance (§3.2).

Protected amounts are in the rules file for Ontario (Wages Act s. 7) and British Columbia (Court Order Enforcement Act s. 3), both `verify_at_load`. An order under a law with no verified value cannot be confirmed (`RULE_NOT_VERIFIED`, `JURISDICTION_RULE_MISSING`), and payroll gets a task; each province where an organization has employees is verified before Step 9 (§15).

### 6.2 Voluntary deductions in self-service (R4.2)

Employees start, change or stop voluntary deductions (charity, parking, social club, purchase plans) in self-service (`payroll.voluntary_deduction`), with an amount per pay, an optional goal amount and dates. Only a deduction code can be used (`PAY_CODE_NOT_DEDUCTION`). The request follows the organization's `voluntary_deduction` route; a route with no steps means no approval is needed. The employee cannot approve their own (`SELF_APPROVAL`).

### 6.3 When a pay cannot cover every deduction (R4.3)

The law's order comes first: statutory deductions, then support orders, then other garnishments (`docs/06` §7). The organization orders the rest. Each deduction code says what happens to a shortfall (`payroll.pay_code.arrears_recovery`, required for every deduction):

| Value | The shortfall is |
| --- | --- |
| `next_pay` | Taken in full from the next pay |
| `spread` | Spread over `arrears_spread_periods` pays |
| `hr_decides` | Left for HR to decide, with a task |
| `not_recovered` | Not recovered (for example a missed charity gift) |

Arrears are kept in `payroll.deduction_arrears`; writing one off needs the person and a reason. No deduction or arrears recovery takes pay below the protected minimum.

### 6.4 Money an employee owes (R4.4)

An advance, equipment not returned or unearned training is recovered from pay, including the final pay, only with the employee's written authorization (`payroll.recovery_authorization`: what it is for, the amount, an optional limit per pay, the signed document) and within the law's limits. A recovery item without one is refused (`RECOVERY_NOT_AUTHORIZED`), and recoveries cannot go above the total or the per-pay limit authorized (`RECOVERY_ABOVE_AUTHORIZED`). Without an authorization, HR follows up outside payroll. Overpayments keep their own flow (`docs/21` §7.2).

---

## 7. Pay statements, slips, banks and the ROE

### 7.1 Delivery (R5.1)

CanDo follows CRA's rule for slips (`nationwide.tax_slip_delivery` in the rules file) and uses it for pay statements too:

| Person when the document is issued | Delivery |
| --- | --- |
| A current employee | In CanDo self-service, where they can view and print it; no consent needed. On paper if they ask, or if HR records that they cannot reasonably reach self-service |
| A former employee, or one on leave or laid off | Electronically only if they consented; otherwise on paper, mailed to their last known address |
| Anyone, by email | Only with their consent to email |

CanDo treats a position on leave or laid off as extended leave, so those people get paper unless they consent; consenting is one step in self-service. A choice (`payroll.delivery_choice`: electronic consent, email consent or paper request) is made per kind of document (pay statement or tax slip), on the self-service screen or a paper form, and can be withdrawn. A paper request always wins. `payroll.delivery_method()` returns `portal` or `print` for a person, a kind of document and a moment, and `payroll.may_email()` says whether an email copy may be sent. When no choice was made, FB-036 applies.

Provinces have their own rules for pay statements (Ontario ESA s. 12; British Columbia ESA s. 27: electronic statements where the employee can view them privately and print them), in the rules file as `pay_statement_electronic`, `verify_at_load`. Notifications carry no pay data, only a link into CanDo (`docs/16` Q20).

### 7.2 Former employees' access (R5.2)

When a person's last employment ends, their login is kept with `platform.app_user.former_employee_until`. Until that date they can sign in to see only their own pay statements, slips and ROE. The date is the T4 due date for the year of their last day (the last day of February of the next year) plus `self_service.former_employee_access` months (12 pre-filled): someone who left on 15 November 2026 keeps access until 28 February 2028. After that, they ask the employer for copies.

### 7.3 Banks (R5.3)

Direct-deposit files are built for all major banks at launch: RBC, TD, Scotiabank, BMO, CIBC, National Bank, Desjardins and the main credit unions. Each has its own CPA 005 or ISO 20022 variant, tested against a golden file from the bank (PAY-031). This closes `docs/16` Q2; which credit unions count as main is confirmed with the anchor customers (§15).

### 7.4 The ROE (R5.4)

When a termination or a leave interrupts earnings, CanDo prepares the ROE from payroll data: insurable hours and earnings by pay period, the reason code mapped from the separation or leave reason, and the due date. HR reviews the reason code and comments before the file is built (`payroll.roe.reviewed_by`, `reviewed_at`; `ROE_NOT_REVIEWED`), then the employer uploads it to ROE Web.

---

## 8. Several positions, funding and accounting

### 8.1 Cost coding and funding (R6.1 to R6.3)

The precedence in `docs/17` §8.2 stays and is now decided: a pay line with no cost coding takes the assignment's, then the position's, then the org unit's; if none has any, it goes to the suspense account and finance gets a task. Pay is never delayed for cost coding (FB-011).

Pay over a funding source's cap, or not eligible for it, moves to the fallback fund by default, with alerts to finance at 90, 60 and 30 days (`funding.default_cap_behaviour`, `funding.default_alert_days`; FB-012). Each source can be set differently. Retro or a correction that reaches a closed source goes where finance set that source up to send it (successor, fallback or suspense; `funding.default_post_close_policy`, FB-013), listed on the funder adjustment report. This closes `docs/16` Q12 and `docs/17` E2.

### 8.2 One-time payments for people in several positions (R7.2)

A one-time payment for someone in several positions names the position it belongs to; it cannot be saved until someone picks one (`payroll.one_time_allocation` = `assignment`; FB-026). An organization can choose `earnings_share` instead, which shares unnamed payments by each position's earnings in the period (`docs/20` §4.3).

### 8.3 Accounting journals (R6.4)

Payroll reaches the organization's accounting system through journal files in that system's import format (QuickBooks, Sage, Xero, Microsoft Dynamics, NetSuite and others through a mapping), with work and posting periods on every line (AGENTS rule 21) and control totals. Direct connections to accounting systems come later. This closes `docs/16` Q14 and `docs/17` E4.

---

## 9. Statutory tables (R7.4)

CanDo loads, tests and activates the CRA tables (the January and July T4127 editions) and every other statutory change centrally, once for every organization, through rule editions (`docs/06` §8). CanDo's payroll rules lead owns the update. Organizations cannot change statutory tables; they see which edition paid each result. This closes `docs/16` Q7 for CRA and the provinces; Revenu Québec certification stays phase 2.

---

## 10. Fallbacks decided in this review

| ID | When | CanDo does |
| --- | --- | --- |
| FB-010 | Two premiums or pay sources meet and the agreement says nothing about how they combine | Stops that line with `UNRESOLVED_INTERACTION`; labour relations completes the agreement version; the employee is held by default (R7.1) |
| FB-011 | A cost has no cost coding | The assignment's, the position's, then the unit's coding; otherwise suspense with a finance task; pay not delayed (R6.1) |
| FB-012 | Pay is over a funding source's cap or not eligible for it | The fallback fund by default, with alerts at 90, 60 and 30 days; each source can say otherwise (R6.2) |
| FB-013 | Retro or a correction reaches a closed funding source | Where the source's post-close policy sends it, on the funder adjustment report (R6.3) |
| FB-026 | A one-time payment names no position | Refused until it names one; an organization can choose to share by earnings (R7.2) |
| FB-036 (new) | A pay statement or slip is issued and the person made no delivery choice | Self-service for a current employee; paper for a former employee or one on leave or laid off; never email (R5.1) |

The register is `rules/register/values-and-fallbacks.json`; `docs/22` §5 lists every fallback.

---

## 11. Data model (migration 0010)

| Object | What it holds |
| --- | --- |
| Settings in §2.2 | Four new; `payroll.default_proration_method` pending (chosen at setup); `payroll.one_time_allocation` and the three `funding` settings decided |
| `platform.workflow_route` subject types `pay_run`, `voluntary_deduction`, `banked_time_payout`; `check_approval_task()` | §2.4 |
| `payroll.pay_run.route_id`, `payroll.pay_run_hold`, `payroll.parallel_run`, trigger `payroll.check_pay_run()` | §4.1, §4.2, §4.4 |
| `payroll.vacation_pay_rule`, `payroll.check_scope_keys()`, `payroll.assignment_scope_facts()`, `payroll.scope_matches()`, `payroll.vacation_pay_rule_for()`; caution `payroll.vacation_pay_each_cheque` | §5.1 |
| `timeleave.banked_time_policy`, `timeleave.banked_time_policy_for()`, `timeleave.banked_time_payout_request` | §5.3 |
| `payroll.pay_code.arrears_recovery`, `arrears_spread_periods`; `payroll.deduction_arrears` | §6.3 |
| `payroll.voluntary_deduction`, `payroll.garnishment_order`, `payroll.recovery_authorization`, `payroll.one_time_item.recovery_authorization_id` | §6.1, §6.2, §6.4 |
| `payroll.delivery_choice`, `payroll.delivery_method()`, `payroll.may_email()` | §7.1 |
| `platform.app_user.former_employee_until`, `payroll.former_employee_access_until()` | §7.2 |
| `payroll.roe.reviewed_by`, `reviewed_at` | §7.4 |
| `ref.provider_capability`, `platform.provider_access_grant`, `platform.provider_can()` | §4.5 |
| Starter routes `pay_run`, `voluntary_deduction`, `banked_time_payout`; `core.seed_tenant()` copies them | §2.4 |

Every new tenant table has `tenant_id` with forced row-level security; text fields are registered as translatable (`docs/22` §4.3). Existing organizations get the starter routes when 0010 runs, except one that keeps another language as required for its data (FB-035): the migration names it, and HR adds the routes with their texts. Rows that existed before 0010 are not rechecked; the new checks apply from their next change. Pay codes of kind `deduction` need `arrears_recovery` on their next change, so the Step 9 loader sets it for every existing deduction.

---

## 12. Validation, API and events

**Errors added by 0010:** `PAY_RUN_HAS_FAILED_CHECKS`, `PARALLEL_RUN_REQUIRED`, `PAYROLL_SCOPE_UNKNOWN`, `VACATION_PAY_RULE_MISSING`, `BANKED_TIME_POLICY_MISSING`, `BANKED_PAYOUT_NOT_ALLOWED`, `PAY_CODE_NOT_DEDUCTION`, `GARNISHMENT_NOT_CONFIRMED`, `RECOVERY_NOT_AUTHORIZED`, `RECOVERY_ABOVE_AUTHORIZED`, `ROE_NOT_REVIEWED`, `PROVIDER_CAPABILITY_UNKNOWN`, `PROVIDER_GRANT_NOT_CLIENT`, `PROVIDER_USER_UNKNOWN`. Existing ones used: `INPUT_REQUIRED`, `ROUTE_APPROVALS_MISSING`, `SELF_APPROVAL`, `SETTING_NOT_SET`, `UNRESOLVED_INTERACTION`, `RULE_NOT_VERIFIED`, `JURISDICTION_RULE_MISSING`, `CAUTION_NOT_ACKNOWLEDGED`.

**Checks in the application (Steps 9 to 13), not the database:** pre-run checks and holds; moving pay dates to the previous banking day; the vacation pay caution and the employee's agreement where the law needs it; the law's minimum vacation rate; banked time limits from the law; the order of deductions and the protected minimum; garnishment and protected amounts from the rules file; remittance amounts, due dates and reminders; delivery choices on the self-service screen; former employees' limited login; bank file variants; journal file formats; the mid-year YTD import and one T4 for the year.

**API** (added to `api/openapi.yaml` in Steps 9 to 13): `POST /payroll/runs/{id}/holds` and `release`; `POST /payroll/runs/{id}/submit` (into its route); `GET/POST /payroll/parallel-runs` with `accept`; `GET/POST /payroll/vacation-pay-rules`; `GET/POST /time/banked-time-policies`; `POST /time/banked-time-payout-requests`; `GET/POST /payroll/voluntary-deductions` (self-service) with `stop`; `GET/POST /payroll/garnishment-orders` with `confirm-first-deduction`; `GET/POST /payroll/recovery-authorizations`; `GET/PUT /me/delivery-choices`; `POST /payroll/roes/{id}/review`; `GET/POST /provider-access-grants` with `approve` and `revoke` (client side, through the identity Worker); `GET /payroll/remittances` (calendar); `GET /payroll/journals/{runId}?format=`.

**Events** (added to `api/events.yaml`; identifiers only, AGENTS rule 9): `pay_run.submitted`, `pay_run.approved`, `pay_run.employee_held`, `pay_run.hold_released`, `parallel_run.accepted`, `remittance.reminder_due`, `garnishment.first_deduction_confirmed`, `voluntary_deduction.approved`, `banked_time.payout_approved`, `roe.reviewed`, `provider_grant.approved`, `provider_grant.revoked`, `delivery_choice.changed`.

---

## 13. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| PAY-060 | Pay run approved without naming its approver, with the route incomplete, or by the person who prepared it | `INPUT_REQUIRED`; `ROUTE_APPROVALS_MISSING`; `SELF_APPROVAL`; approved once finance approves | smoke 2a–c | 1, 9 |
| PAY-061 | One employee has no bank account at review | Held with the failed check and a reason; everyone else paid on time; paid off-cycle once fixed, the hold naming that run | smoke 3a; engine test | 9 |
| PAY-062 | The employer chose to stop the run, and a hold is open | `PAY_RUN_HAS_FAILED_CHECKS`; approved once every hold is released | smoke 3a | 9 |
| PAY-063 | Pay date on Saturday 26 December 2026, or on a bank holiday | Moved to the previous banking day; a move into the previous year is shown before the calendar is approved | unit test | 9 |
| PAY-064 | First live run with no accepted parallel run; a parallel run accepted without its differences | `PARALLEL_RUN_REQUIRED`; refused; after one accepted parallel run the first run finalizes, and later runs need nothing more | smoke 4a–b | 9, 20 |
| PAY-065 | Provider asks to prepare, build files and report for a client | Unknown capability refused; nothing allowed before the client approves; the provider cannot approve its own access; only the approved capabilities and period afterwards; actions recorded as the provider's | smoke 12a–d | 3, 9 |
| PAY-066 | Casual staff paid vacation pay on each cheque, everyone else accruing 6% | The casual position gets the casual rule, the permanent one 6%; the caution is shown when the casual rule is saved | smoke 5c; UI test | 9 |
| PAY-067 | Vacation pay needed before any rule exists; a rule with an unknown scope | `VACATION_PAY_RULE_MISSING`; `PAYROLL_SCOPE_UNKNOWN` | smoke 5a–b | 9 |
| PAY-068 | Pay group created before the organization chose its proration method | `SETTING_NOT_SET`; created once chosen | smoke 1e | 9 |
| PAY-069 | Banked time: casual staff paid out at year-end with requests allowed; others carry 40 hours and the rest is paid | Policies chosen per position; a request where the policy does not allow it refused; approved only through the route | smoke 6a–c | 11 |
| PAY-070 | Loading the starter codes with one entry still `verify_at_load` | Only verified entries copied; the rest listed for payroll | loader test | 9 |
| PAY-071 | Evening and weekend premiums meet in an agreement that does not combine them | That line stops with `UNRESOLVED_INTERACTION`; labour relations gets a task; the employee is held by default | stacking test; engine test | 7, 9 |
| PAY-072 | Support order entered and set active before payroll confirmed the first deduction | `GARNISHMENT_NOT_CONFIRMED`; active once confirmed | smoke 7d | 9 |
| PAY-073 | Employee starts a $10 charity deduction in self-service | An earnings code refused (`PAY_CODE_NOT_DEDUCTION`); the employee cannot approve it; approved by payroll through the route | smoke 7b–c | 9, 12 |
| PAY-074 | Deduction code without a shortfall rule; arrears written off without a reason | Both refused | smoke 7a, 7e | 9 |
| PAY-075 | Net pay too small for tax, a support order, parking and charity | Tax, then the support order, then the organization's order; parking's shortfall spread over 3 pays, charity's not recovered; never below the protected minimum | engine test | 9 |
| PAY-076 | $150 advance recovery without an authorization; a third $50 after two $150 against a $300 authorization | `RECOVERY_NOT_AUTHORIZED`; `RECOVERY_ABOVE_AUTHORIZED` | smoke 8a–b | 9, 16 |
| PAY-077 | T4 for a current employee; that employee asks for paper statements; T4 for someone who left in October, before and after their consent | Self-service; print, and no email without consent; print, then self-service | smoke 9a–c | 12, 13 |
| PAY-078 | Employee leaves 15 November 2026 | Access until 28 February 2028; until 28 February 2029 where the employer set 24 months | smoke 10 | 3, 13 |
| PAY-079 | ROE file built before HR reviewed it | `ROE_NOT_REVIEWED`; built once HR reviews | smoke 11 | 13 |
| PAY-080 | One-time payment saved without its position for someone in several positions | Refused until a position is named | smoke 1f | 9 |
| PAY-081 | Organization moves to CanDo on 1 July with imported YTD | One T4 per employee for the year combining both systems; CPP and EI maximums count the imported amounts | engine test | 9, 13 |
| PAY-082 | CRA remittance due 15 December for a regular remitter | Payroll reminded on 8, 12 and 14 December; no more reminders once the payment is recorded | job test | 12 |
| PAY-083 | Journal for a run with work in two fiscal periods, exported for Xero | One file in Xero's import format with work and posting periods on each line, totals matching the run | golden file | 12 |
| PAY-084 | Pay line with no cost coding anywhere | Suspense account and a finance task; pay not delayed | engine test | 12 |
| PAY-085 | Grant reaches its cap mid-period | The excess moves to the fallback fund; finance alerted at 90, 60 and 30 days before the grant runs out | engine test | 12 |
| PAY-086 | An organization tries to change a statutory table | Refused; the edition in force is shown with its source | API test | 9 |

---

## 14. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/03` | Points here at the top: CanDo calculates and prepares, the employer pays, remits and files (§2.1); the parallel run standard is the organization's setting (§4.4); slips and statements follow CRA's rule (§7.1); recoveries need written authorization (§6.4); the ROE is reviewed by HR (§7.4) |
| `stories/03` | PAY-010 approval through the route (§4.1); PAY-030 shortfall rule per deduction (§6.3); PAY-042 HR review of the ROE (§7.4); PAY-051 failed checks hold employees or stop the run (§4.2). New PAY-060 to PAY-086 in §13 |
| `docs/06` | §2 approval through the organization's route; §9 holds and the parallel run; §1 pay dates as decided |
| `docs/15` Steps 3, 9, 11, 12 and 13 | Read this document; build on migration 0010; pass PAY-060 to PAY-086, each in the step §13 names |
| `docs/16` | Q2, Q7, Q11, Q12 and Q14 decided; `payroll.default_proration_method` chosen at setup; items to verify for this module |
| `docs/17` §16 | E1, E2 and E4 decided |
| `docs/20` §4.3 | A one-time payment names its position by default (§8.2) |
| `docs/22` | FB-010 to FB-013 and FB-026 decided; FB-036 added; settings from 0010 are listed here, not in `docs/22` §2 |
| `AGENTS.md` | Reading order item 11; rule 48; Step 1 migration 0010 and its smoke test; Steps 9 to 13 |
| `.cursor/rules/00-cando.mdc` | Rule 48 in short |
| `rules/employment-standards` | `ca-2026-payroll-additions.json` merged into the edition in Step 7 |
| `tests/schema/schema_0006_smoke.sql`, `schema_0007_smoke.sql` | Fixtures state the proration method and the one-time allocation they test; no rule relaxed |

Where a listed document still says otherwise, this document wins.

---

## 15. Open questions and items to verify

| Item | Until decided |
| --- | --- |
| Starter codes' tax, CPP, EI and vacation flags and slip boxes (`rules/payroll/starter-pay-codes.json`) | All `verify_at_load`; checked against T4001 and the chart of types of remuneration before Step 9 |
| Garnishment protection, banked time limits, vacation pay on each cheque and electronic pay statements per jurisdiction | Ontario and British Columbia entered, `verify_at_load`; other jurisdictions entered and verified before Step 9 for each province where the anchor customers have employees |
| CRA's slip delivery rule (`nationwide.tax_slip_delivery`) | From CRA's page, checked 27 Oct 2026, `secondary`; re-check each year before slips are issued |
| Whether a short leave counts as extended leave for slip delivery | CanDo treats any position on leave or laid off as extended leave (paper unless the person consents), which is always allowed |
| Which credit unions are main for bank files at launch | Confirmed with the anchor customers before Step 12 |

---

## Sources

- Canada Revenue Agency, Distribute the slips (secure portal without consent, the exceptions, email with consent, paper copies, due date): https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/payroll/file-information-returns-slip-summaries/distribute-slips.html
- Canada Revenue Agency, Electronic distribution of T4 slips (Budget 2017 measure): https://www.canada.ca/en/revenue-agency/programs/about-canada-revenue-agency-cra/federal-government-budgets/budget-2017-building-a-strong-middle-class/electronic-distribution-t4-slips.html
- Canada Revenue Agency, T4001 Employers' Guide: Payroll Deductions and Remittances (remitter types and due dates; types of remuneration)
- Ontario, Employment Standards Act, 2000, ss. 12, 22(7) and 36(3); Wages Act, s. 7
- British Columbia, Employment Standards Act, ss. 27, 42 and 58; Court Order Enforcement Act, s. 3
