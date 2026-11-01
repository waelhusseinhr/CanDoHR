# 26 · Benefits decisions

Oct 28, 2026 · @Wael

This document records the owner's review of Module 05 (Benefits Administration) and turns each decision into something the build can follow: a setting with its default, a database check, a rule the organization sets, a route it edits, or a screen behaviour. The review went round by round; the working record is `claude/review/05-benefits-decisions.md` in the project.

It covers spending accounts, carrier files, benefits advisors, the enrolment assistant, waiting periods, life event windows, late enrolment, open enrolment, variable-hour eligibility, dependents, opt-outs, people under two agreements or with two plans of one kind, benefits during statutory and other leaves, coverage when employment ends, benefits during notice outside Ontario, premium adjustments for past months, carrier invoices, public sector pension plans, automatic pension enrolment, union benefit trusts and retirees.

**Precedence.** On these topics this document wins over `requirements/05`, `stories/05-benefits.md`, `docs/17` §7.7 and `docs/20` §6 where it adds to them. `docs/22` still wins on values, defaults, languages and fallbacks. §14 lists every place that changes. The schema is `schema/0012_benefits_decisions.sql` (migration 0012, Step 1), checked by `tests/schema/schema_0012_smoke.sql`. Coverage rules when a position or employment ends start from `rules/benefits/benefit-change-rule-templates.json` and follow `reference/several_positions_reference.py`.

**The owner's rules for this module.**

1. Every decision is a default each organization can change at setup or later; only legal floors and safety rules are fixed. CanDo pre-fills its suggested numbers at setup, and the organization keeps or changes them (Q46). Where the owner gave no starting number, the setup wizard asks.
2. Plans, classes and rules are the organization's, taken from its plan contracts, agreements and policies. Where no rule says what to do (two agreements, two plans of one kind, a position ending with no rule), HR decides and records why; CanDo never picks.
3. The law's floors always apply: statutory leaves keep benefits as the law requires, and coverage never ends before a statutory notice floor.
4. CanDo keeps the records, prepares the files and reminds; carriers, administrators and plan administrators pay claims and run the plans. No medical information is stored (`requirements/05`).

---

## 1. Decisions at a glance

| # | Decision | Setting or rule | Section |
| --- | --- | --- | --- |
| R1.1 | Spending accounts are administered by a partner; CanDo holds allocations, balances, carry-forward and taxable amounts, and handles no claims | Integration | §3.1 |
| R1.2 | Carrier files: a generic enrolment and change file at launch; each carrier's own format built as anchor customers need it | Carrier file profiles | §3.2 |
| R1.3 | Benefits advisors get an included, read-only role the organization grants; individual data only if the organization allows it | Provider capabilities `benefits_plan_costs`, `benefits_individual_data` | §3.3 |
| R1.4 | The enrolment assistant comes later with the platform assistant, off until switched on; it answers from the plan booklet and never recommends | `benefits.ai_enrolment_assistant`: off | §3.4 |
| R2.1 | Waiting period: no CanDo number; the organization states it for each plan at setup | `benefits.plan.waiting_rule` (required) | §4.1 |
| R2.2 | Life event window: no CanDo number; the organization sets it at setup, and each plan can set its own | `benefits.life_event_window_days`: chosen at setup | §4.2 |
| R2.3 | Late enrolment follows each plan's rule; starting rule: evidence of insurability for life and disability, limited coverage for dental | `benefits.late_enrolment_starter` | §4.3 |
| R2.4 | No action in open enrolment: current elections roll over; a flex plan can name a default option | `benefits.open_enrolment_no_action`: keep current | §4.4 |
| R3.1 | A person under two agreements: HR chooses the governing agreement and records why | `benefits.governing_agreement`; FB-023 | §5.1 |
| R3.2 | Two plans of one kind: HR sets which pays first and records why; any order a plan contract sets is shown | `cob_decided_by`, `cob_reason`; FB-020 | §5.2 |
| R3.3 | Variable-hour eligibility: the organization's look-back and re-test per plan or class; CanDo re-tests and proposes, HR confirms | `benefits.plan.hours_test` | §4.7 |
| R3.4 | A position ends and no rule matches: HR decides, with the statutory floor shown | FB-021 | §7.3 |
| R4.1 | Statutory leave: the employee chooses how to pay their share (ahead, arrears on return, or through payroll); the organization can limit the choices or pay the share | `benefits.statutory_leave_contributions` | §6.1 |
| R4.2 | Other unpaid leaves: continue at the employee's cost, continue employer-paid for a period, or suspend; the organization sets one per leave type and class | `benefits.leave_rule`; `LEAVE_BENEFIT_RULE_MISSING` | §6.2 |
| R4.3 | When employment ends, the organization sets for each class when coverage ends: the termination date, month end, or the end of notice or severance; never before the law | Change rules with `employmentTypes` and `end_of_severance` | §7.1 |
| R4.4 | Benefits during notice outside Ontario: CanDo stops and cautions HR about common-law reasonable notice until counsel confirms each province; HR decides and records why | Caution `benefits.common_law_notice` | §7.2 |
| R5.1 | How far back premium adjustments go automatically: no CanDo number; the organization sets it at setup; older ones go to HR | `benefits.retro_adjust_months`: chosen at setup | §8.1 |
| R5.2 | Carrier invoices imported or entered, reconciled by employee, approved through the organization's route before accounts payable; self-billing per carrier | `carrier_invoice` route | §8.2 |
| R5.3 | Employee and HR told 60 days before a dependent child ages out; proof of full-time studies asked each year | `benefits.dependent_ageout_notice_days`: 60 | §4.5 |
| R5.4 | Opting out of health or dental where the plan allows, with proof of the other coverage; Quebec opt-outs respect RAMQ rules | `benefits.opt_out` | §4.6 |
| R6.1 | Pension plan files at launch for the BC Municipal Pension Plan, OMERS, HOOPP and LAPP; a generic contribution file for the rest | Pension file profiles | §9.1 |
| R6.2 | Someone who becomes eligible for a pension plan that is mandatory for them is enrolled automatically; the employee is told and HR confirms | `benefits.enrolment.source`: automatic | §9.2 |
| R6.3 | Union benefit trusts at launch through a generic file: rates from the agreement, hours-based remittances, member eligibility | Trust file profile | §9.3 |
| R6.4 | Retiree benefits in a later phase | — | §9.4 |

---

## 2. How the module is set up

### 2.1 Settings

| Setting | Decides | CanDo default | Set per |
| --- | --- | --- | --- |
| `benefits.life_event_window_days` | Days after a life event in which the employee can change elections, where the plan sets none | **None: chosen at setup** (at least 1) | Organization, employer |
| `benefits.retro_adjust_months` | How many months back premium adjustments are made automatically; older ones go to HR | **None: chosen at setup** (0 or more) | Organization, employer |
| `benefits.late_enrolment_starter` | The late-enrolment rule a new plan of each kind starts from | Life, AD&D, short- and long-term disability: evidence of insurability; dental: limited coverage; other kinds state their own | Organization, employer |
| `benefits.open_enrolment_no_action` | What happens when an employee does nothing in open enrolment | Current elections roll over | Organization, employer |
| `benefits.statutory_leave_contributions` | The ways an employee may pay their share during a statutory leave, and whether the employer pays it instead | Pay ahead, arrears on return, or through payroll; the employer does not pay it | Organization, employer |
| `benefits.dependent_ageout_notice_days` | Days before a dependent child ages out when the employee and HR are told | 60 | Organization, employer |
| `benefits.ai_enrolment_assistant` | The enrolment assistant | Off | Organization |

Pre-filled values follow the Q46 rule: the setup screen shows CanDo's suggestion and the organization keeps or changes it.

### 2.2 Chosen at setup

The owner left these to each organization. The setup wizard asks each one; until it is answered, the feature that needs it stops.

| What | How it is asked | Until answered |
| --- | --- | --- |
| `benefits.life_event_window_days` | One number for the organization or each employer; each plan can set its own | A life event on a plan with no window of its own stops with `SETTING_NOT_SET` (FB-003) |
| `benefits.retro_adjust_months` | One number for the organization or each employer | Adjustments for past months stop with `SETTING_NOT_SET` |
| Waiting period of each plan | A required field on the plan (§4.1) | The plan cannot be saved (`INPUT_REQUIRED`) |
| Late enrolment rule for plan kinds the starter does not list | A required field on the plan (§4.3) | The plan cannot be saved (`INPUT_REQUIRED`) |
| What happens to coverage during each kind of unpaid, non-statutory leave | The organization's leave rules (§6.2) | `LEAVE_BENEFIT_RULE_MISSING` for that leave |
| When coverage ends on termination, per class | The organization's change rules (§7.1) | HR decides each case (FB-021) |

### 2.3 Route

Carrier invoices use the organization's routes (`docs/23` §2.2). Starter route:

| Route | Steps | Decision |
| --- | --- | --- |
| Carrier invoice | Benefits review of the reconciliation (HR), then finance approval for payment | R5.2 |

No one approves an invoice they prepared (`SELF_APPROVAL`).

### 2.4 Caution

`benefits.common_law_notice` appears when HR decides what happens to coverage after an employer ends employment or a position with notice owed, in a province whose rule on benefits during notice is not confirmed (`COMMON_LAW_REVIEW` or `RULE_NOT_VERIFIED`). It says that a court can award the value of benefits for the whole reasonable notice period even where the statute does not require them, and that employment counsel should be consulted; a written reason is always needed (§7.2).

---

## 3. Scope and partners

### 3.1 Spending accounts (R1.1)

Health and wellness spending accounts are administered by a partner: a carrier or a third-party administrator receives and pays claims. CanDo holds each employee's allocation, balance, carry-forward and forfeiture, imports balances and paid claims totals from the administrator, and sends taxable wellness reimbursements to payroll as taxable benefits (BEN-008). CanDo stores no claim details and no receipts. A CanDo-branded administration service is not planned.

### 3.2 Carrier files (R1.2)

At launch, CanDo produces one generic enrolment and change file (full or changes only, CSV) with a golden file test, and imports acknowledgement and error files as tasks for the benefits administrator (BEN-006). A carrier's own format is built when an anchor customer needs it, from the carrier's specification and test file, with its own golden file. This closes `docs/16` Q6 for carriers.

A person with two plans of one kind is left out of the carrier file, with `COB_ORDER_NOT_SET` on the file's error list, until HR has set which plan pays first (§5.2).

### 3.3 Benefits advisors and brokers (R1.3)

Advisors and brokers work through the provider access grants of `docs/24` §4.5: the organization grants an advisor firm access for a period, and the firm's users act only while `platform.provider_can()` is true. Two capabilities are added:

| Capability | What the advisor sees |
| --- | --- |
| `benefits_plan_costs` | Plan design, enrolment counts by plan, option and class, premiums and costs, renewal reports |
| `benefits_individual_data` | Individual employees' benefits records, only when the organization grants it |

The role is read-only and included in the subscription (not a paid add-on). Everything an advisor views is recorded as theirs.

### 3.4 Enrolment assistant (R1.4)

The assistant comes with the platform assistant (Step 19, `docs/12`), not at launch, and is off until the organization switches it on (`benefits.ai_enrolment_assistant`). It answers enrolment questions only from the plan booklets the organization loaded, cites the booklet section, and never recommends an election (AGENTS rule 14). Decision support without AI (option comparison, per-pay cost, plain-language explanations, BEN-009) is at launch.

---

## 4. Eligibility and enrolment

### 4.1 Waiting periods (R2.1)

Every plan states its waiting period when it is set up; there is no CanDo starting number. `benefits.plan.waiting_rule` takes one of:

| Kind | Example |
| --- | --- |
| `none` | Covered from the hire date |
| `days`, `months` | 90 days or 3 months from hire |
| `first_of_month_after` | The first of the month after 3 months |
| `hours` | After 480 hours worked |

A plan without one is refused (`INPUT_REQUIRED`); an unknown kind or a missing number is `WAITING_RULE_INVALID`. A class with a different waiting period uses its own plan record (or the plan's class rules, where the plan contract sets them). Rehire waivers follow the plan contract.

### 4.2 Life event windows (R2.2)

A life event (marriage, birth, adoption, separation, loss of other coverage) opens a window for changing elections. The window is the plan's own (`benefits.plan.life_event_window_days`) or, where the plan sets none, the organization's (`benefits.life_event_window_days`), read with `benefits.life_event_window()`. The setup wizard asks the organization's number; until then a life event on a plan without its own window stops with `SETTING_NOT_SET`.

### 4.3 Late enrolment (R2.3)

Each plan states what happens when someone enrols after their window (`benefits.plan.late_enrolment`): evidence of insurability (`eoi`), limited coverage, the next open enrolment, or HR decides. A new plan starts from `benefits.late_enrolment_starter`: evidence of insurability for life, AD&D and disability, limited coverage for dental, as carriers usually require. A plan of another kind (health, for example) states its rule when it is set up (`INPUT_REQUIRED`). Evidence of insurability requests are tracked with the carrier as `requirements/05` describes.

### 4.4 Open enrolment (R2.4)

When an employee does nothing in open enrolment, current elections roll over (`benefits.open_enrolment_no_action`). A flex plan can name a default option for people who do nothing (`benefits.plan.open_enrolment_default_option`). Elections made by rollover carry `source = rollover` (§11).

### 4.5 Dependents (R5.3)

Dependents are kept under the employee's record (`benefits.dependent`), for plan administration only, and are deleted on schedule after coverage ends. Age limits and the student and disability rules come from the plan contract (`benefits.plan.dependent_rules`). The employee and HR are told `benefits.dependent_ageout_notice_days` days (60 pre-filled) before a child ages out (`benefits.ageout_notice_on()`), and proof of full-time studies is asked each year; the date the proof covers is kept (`student_proof_until`). A disabled dependent may have no age limit where the plan says so. No medical information is stored about a dependent's disability: only that the plan accepted it.

### 4.6 Opt-outs (R5.4)

An employee may opt out of health or dental where the plan permits, with proof of the other coverage (`benefits.opt_out` requires the proof document). In Quebec, an employee under 65 who has access to a group plan must join at least its prescription drug coverage unless they show they are covered by another private plan, and if they have several private plans they may choose among them; an opt-out never moves someone to the public plan when a private one is available (RAMQ). Opt-outs feed the T4 box 45 dental access code only through the plan's own rules.

### 4.7 Variable-hour eligibility (R3.3)

Where eligibility depends on hours, the plan (or class) states its test (`benefits.plan.hours_test`): the look-back period in weeks, the re-test schedule and the minimum average hours. All three are required when there is a test. CanDo re-tests on the schedule from time records across the person's positions under the plan's scope (`docs/20` §6.1), and proposes enrolments and coverage ends for HR to confirm; nothing changes until HR does.

---

## 5. Two agreements and two plans of one kind

### 5.1 The governing agreement (R3.1)

When a benefit-class or person-level rule must pick one of a person's two collective agreements, HR chooses for that person and records why (`benefits.governing_agreement`, with the period it covers). CanDo makes no automatic choice: `benefits.governing_agreement_for()` returns the only agreement when there is one, the HR choice when there are two or more, and otherwise stops with `GOVERNING_AGREEMENT_NOT_SET`, which gives HR a task. This replaces the "highest-FTE position" rule of `docs/17` §7.7 and decides FB-023 (closes `docs/16` Q13).

### 5.2 Coordination of benefits (R3.2)

When two plans of the same kind cover one person, HR sets which pays first for that person and records why (`cob_rank` with `cob_decided_by`, `cob_decided_at` and `cob_reason` on each enrolment). Any order a plan contract sets (a union trust plan's, for example) is shown beside the decision as information; CanDo never orders the plans itself. `benefits.cob_decisions_needed()` lists the people waiting for HR's order, and the carrier file leaves them out until HR decides (§3.2). This replaces the "higher-FTE position is primary" rule of `docs/20` §6.1 and decides FB-020 (closes `docs/16` Q37). The reference calculator returns `hr_decides` with the contract order (`cob_order`, cases COB-001 and COB-002).

---

## 6. Leaves

### 6.1 Statutory leaves (R4.1)

During a statutory leave (pregnancy, parental and the other job-protected leaves), benefits stay in force as the law requires. The employee chooses how to pay their share from the ways the organization offers (`benefits.statutory_leave_contributions`):

| Way | What happens |
| --- | --- |
| `prepay` | The employee pays ahead before the leave |
| `arrears_on_return` | The share builds as arrears and is recovered on return, under the deduction's shortfall rule (`docs/24` §6.3) |
| `payroll` | Taken from any pay still received during the leave (a top-up, for example) |
| `employer_pays` | Only where the organization pays the employee's share |

The choice is recorded on the leave (`benefits.leave_contribution_choice`); a way the organization does not offer is refused (`LEAVE_CONTRIBUTION_METHOD_NOT_ALLOWED`). The setting is read for the date the leave starts and the employer.

### 6.2 Other unpaid leaves (R4.2)

For unpaid leaves that are not statutory, all three options are available and the organization sets one for each leave type and class (`benefits.leave_rule`):

| Action | Meaning |
| --- | --- |
| `continue_employee_cost` | Coverage continues; the employee pays the full premium |
| `continue_employer_paid` | The employer keeps paying for a number of months (`employer_paid_months`), then the rule's next action applies |
| `suspend` | Coverage stops and restarts on return without a new waiting period, as the plan allows |

A rule applies to leave types, plan kinds, employment types, agreements and employers (`applies_to`; any other key is `BENEFITS_SCOPE_UNKNOWN`), and rules are tried in priority order. `benefits.leave_rule_for()` stops with `STATUTORY_LEAVE_FOLLOWS_LAW` for a statutory leave (§6.1 applies instead) and with `LEAVE_BENEFIT_RULE_MISSING` when no rule matches; CanDo never assumes one.

---

## 7. When employment ends

### 7.1 Coverage end by class (R4.3)

When employment ends, the organization sets for each class when coverage ends: on the termination date, at the end of that month, or at the end of the notice or severance period. These are change rules, the same rules that decide what happens when one position ends (`docs/20` §6.2), matching `employmentContinues: false`. Two additions make them work by class:

- a rule can match the ending position's employment type (`employmentTypes`), as well as agreement, jurisdiction, plan kind and end reason;
- a rule can continue coverage to `end_of_severance`: the termination date plus the weeks of severance the person receives. Without those weeks the proposal stops with `INPUT_REQUIRED`; CanDo never assumes a period.

The setup wizard asks the organization's choice for each class; `rules/benefits/benefit-change-rule-templates.json` holds optional examples. The statutory floor always applies on top: a rule's date is raised to the end of statutory notice where the province requires benefits to continue, and the database refuses an earlier date (`statutory_floor_respected`). Cases BEN-011 to BEN-013 show the three outcomes.

### 7.2 Benefits during notice outside Ontario (R4.4)

Ontario requires benefit contributions to continue during the statutory notice period. For every other province, until employment counsel confirms its rule (`docs/16` Q36 stays an item to verify), a proposal for an employer-initiated end with notice owed carries `COMMON_LAW_REVIEW` (British Columbia) or `RULE_NOT_VERIFIED` (the others). Such a decision stops for HR: the caution `benefits.common_law_notice` must be acknowledged and a reason written before it is decided, and the database refuses it otherwise (`CAUTION_NOT_ACKNOWLEDGED`, `INPUT_REQUIRED`). The warnings are read from before and after the change, so clearing them does not skip the caution.

### 7.3 No matching rule (R3.4)

When a position or employment ends and no change rule matches the enrolment, HR decides each case with the statutory floor shown (FB-021, confirmed). The decision needs a written reason (`case_by_case_needs_reason`).

---

## 8. Premiums and billing

### 8.1 Adjustments for past months (R5.1)

Late enrolments, life events and rate changes create premium adjustments (collect or refund) back to the coverage date. Adjustments reaching back no more than `benefits.retro_adjust_months` months (counted from the start of the current month) are made automatically; older ones go to HR to approve (`benefits.retro_needs_hr()`). There is no CanDo number: the setup wizard asks, and adjustments stop with `SETTING_NOT_SET` until it is answered.

### 8.2 Carrier invoices (R5.2)

Carrier invoices are imported or entered (`benefits.carrier_invoice`), reconciled to CanDo's enrolment and premiums by employee and plan, and the differences listed with their explanation. An invoice cannot be marked reconciled without its list of differences, and it is approved for accounts payable only through the organization's `carrier_invoice` route (`ROUTE_APPROVALS_MISSING`), never by the person who prepared it. Self-billing (the employer produces the bill) is available per carrier (`self_billed`). The monthly comparison of carrier-held enrolment with CanDo's (`requirements/05`) runs before reconciliation.

---

## 9. Pensions, union trusts and retirees

### 9.1 Public sector pension plans (R6.1)

At launch CanDo produces member data and contribution files for the four largest public sector plans its customers use: the BC Municipal Pension Plan, OMERS, HOOPP and LAPP, each built from the plan's own employer specification and tested against a golden file. Other pension plans get a generic contribution file until a customer needs their format. This closes `docs/16` Q6 for pension plans. Contribution rates below and above the YMPE, pensionable earnings and the pension adjustment follow BEN-007.

### 9.2 Automatic pension enrolment (R6.2)

Where membership in a pension plan is mandatory for someone (the plan's eligibility rule says who must join, for example full-time staff after the waiting period, or members of a bargaining unit), CanDo enrols them automatically on their eligibility date (`benefits.enrolment.source = automatic`). The employee is told, HR confirms the enrolment, and contributions start in the next pay. Optional membership is offered as an election.

### 9.3 Union benefit trusts (R6.3)

Multi-employer health, welfare and pension trusts are supported at launch through a generic file: contribution rates from the collective agreement, hours-based remittances and member eligibility. Each trust's own format is built when a customer needs it. A trust plan is a plan with `eligibility_scope = agreement` (`docs/20` §6.1).

### 9.4 Retirees (R6.4)

Retiree benefits administration comes in a later phase. Until then, a retirement end reason goes to HR (template rule R15), and conversion privileges are offered as the plan contract says.

---

## 10. Privacy and access

- Benefits data is restricted to benefits roles; managers see enrolment completion only.
- Dependents' data is visible to the employee and benefits roles, collected for plan administration only and deleted on schedule after coverage ends.
- Opt-out proof and invoices are restricted documents in Supabase Storage.
- Advisors see what the organization grants (§3.3), for the period it grants.
- No medical information, claim details or receipts are stored; disability claims hold status and dates only.
- Carriers and administrators receive only what the policy needs, under a data processing agreement.

---

## 11. Data model (migration 0012)

| Object | What it holds |
| --- | --- |
| Settings in §2.1 | 7 settings; the life event window and the retro months chosen at setup |
| `platform.workflow_route` subject type `carrier_invoice`; `check_approval_task()` | §2.3 |
| `benefits.plan.waiting_rule`, `late_enrolment`, `life_event_window_days`, `hours_test`, `open_enrolment_default_option`, `dependent_rules`; trigger `benefits.check_plan_setup()`; `benefits.life_event_window()` | §4 |
| `benefits.dependent`, `benefits.ageout_notice_on()` | §4.5 |
| `benefits.opt_out` | §4.6 |
| `benefits.enrolment.cob_decided_by`, `cob_decided_at`, `cob_reason` (constraint `enrolment_cob_decided`); `benefits.cob_decisions_needed()` | §5.2 |
| `benefits.governing_agreement`, `benefits.governing_agreement_for()` | §5.1 |
| `benefits.leave_contribution_choice` | §6.1 |
| `benefits.leave_rule`, `benefits.leave_rule_for()` | §6.2 |
| `benefits.change_rule` date rule `end_of_severance`; caution `benefits.common_law_notice` and trigger `benefits.check_change_decision_caution()` | §7 |
| `benefits.retro_needs_hr()`, `benefits.carrier_invoice` | §8 |
| `benefits.enrolment.source` | §4.4, §9.2 |
| Provider capabilities `benefits_plan_costs`, `benefits_individual_data` | §3.3 |
| Starter route `carrier_invoice` | §2.3 |

Every new tenant table has `tenant_id` with forced row-level security; text fields are registered as translatable (`docs/22` §4.3). Existing organizations get the starter route when 0012 runs, except one that keeps another language as required for its data (FB-035).

**Upgrading.** Plans that existed before 0012 state their waiting period (and late-enrolment rule, where the starter does not cover their kind) at their next change. Coordination orders set before 0012 are not rechecked (`enrolment_cob_decided` is added `NOT VALID`); HR records the decision and reason at the person's next change, and the carrier file lists anyone with an order but no recorded decision for HR to confirm. Change decisions already decided are not rechecked against the caution.

---

## 12. Validation, API and events

**Errors added by 0012:** `WAITING_RULE_INVALID`, `GOVERNING_AGREEMENT_NOT_SET`, `LEAVE_CONTRIBUTION_METHOD_NOT_ALLOWED`, `BENEFITS_SCOPE_UNKNOWN`, `STATUTORY_LEAVE_FOLLOWS_LAW`, `LEAVE_BENEFIT_RULE_MISSING`; in the application, `COB_ORDER_NOT_SET` on a carrier file. Existing ones used: `INPUT_REQUIRED`, `SETTING_NOT_SET`, `ROUTE_APPROVALS_MISSING`, `SELF_APPROVAL`, `CAUTION_NOT_ACKNOWLEDGED`, `RULE_NOT_VERIFIED`, `COMMON_LAW_REVIEW`, `JURISDICTION_RULE_MISSING`.

**Checks in the application (Steps 12, 15, 16 and 19), not the database:** waiting periods and windows applied to dates; evidence of insurability tracking; open enrolment rollover; variable-hour re-tests and their proposals; age-out notices and student proof requests; RAMQ opt-out rules; contribution collection during leaves; change rules by class, including the severance period; premium adjustment calculation; invoice reconciliation by employee; carrier, pension and trust files with golden tests; automatic pension enrolment and HR confirmation; advisor views by capability; the assistant.

**API** (added to `api/openapi.yaml` in Step 15): `GET/POST /benefits/plans` with the setup fields; `GET/POST /benefits/dependents`; `GET /benefits/cob-decisions-needed` and `POST /benefits/enrolments/{id}/cob-decision`; `GET/POST /benefits/governing-agreements`; `POST /leave-requests/{id}/benefit-contribution`; `GET/POST /benefits/leave-rules`; `GET/POST /benefits/opt-outs`; `GET/POST /benefits/carrier-invoices` with `submit`; `GET /benefits/files` and `POST /benefits/files/{profile}/generate`.

**Events** (added to `api/events.yaml`; identifiers only, AGENTS rule 9): `benefits.dependent.ageout_notice`, `benefits.cob.decision_needed`, `benefits.cob.decided`, `benefits.governing_agreement.needed`, `benefits.governing_agreement.chosen`, `benefits.leave_rule.missing`, `benefits.enrolment.automatic`, `benefits.retro_adjustment.needs_hr`, `benefits.carrier_invoice.approved`, `benefits.hours_test.proposal`.

---

## 13. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| BEN-020 | Wellness account claim paid by the administrator | Balance imported; taxable amount sent to payroll; no claim details stored | integration test | 15 |
| BEN-021 | Carrier with no file profile | Generic enrolment file with its golden file; acknowledgement errors become tasks | file test | 15 |
| BEN-022 | Advisor granted plan costs only, then individual data | Counts and costs only; individual records refused, then shown | smoke 1c; API test | 3, 15 |
| BEN-023 | Employee opens enrolment with the assistant off, then on | No assistant; answers cite the booklet and never recommend | assistant test | 19 |
| BEN-024 | Plan saved without a waiting period, or with "4 weeks" | `INPUT_REQUIRED`; `WAITING_RULE_INVALID`; "first of the month after 3" saved | smoke 2a, 2c | 1, 15 |
| BEN-025 | Life event before the organization chose a window; plan with 45 days; organization sets 31 | `SETTING_NOT_SET`; 45 for that plan; 31 for the others | smoke 2d | 15 |
| BEN-026 | New life plan; new health plan with no late-enrolment rule | Evidence of insurability; `INPUT_REQUIRED` | smoke 2b | 15 |
| BEN-027 | Employee does nothing in open enrolment; flex plan with a default option | Elections roll over; the flex default applies | engine test | 15 |
| BEN-028 | Casual employee averages 22 hours over 13 weeks against a 20-hour test | Enrolment proposed to HR; nothing changes until HR confirms | engine test | 11, 15 |
| BEN-029 | Person in a full-time and a part-time agreement | `GOVERNING_AGREEMENT_NOT_SET` until HR chooses with a reason | smoke 5a–d | 15 |
| BEN-030 | Person with an employer health plan and a union trust health plan | Listed for HR; left out of the carrier file; order set only with a reason; trust contract order shown | smoke 4a–c; COB-001, COB-002 | 15 |
| BEN-031 | Parental leave: arrears on return; employer pays where the organization does not | Recorded; `LEAVE_CONTRIBUTION_METHOD_NOT_ALLOWED`; accepted where an employer pays | smoke 6a | 11, 15 |
| BEN-032 | Unpaid personal leave for permanent and casual staff; no rule; a statutory leave | The organization's rule for each class; `LEAVE_BENEFIT_RULE_MISSING`; `STATUTORY_LEAVE_FOLLOWS_LAW` | smoke 6b–e | 11, 15 |
| BEN-033 | Termination of permanent staff with 12 weeks' severance in Ontario; casual staff; severance weeks unknown | Coverage to 7 June 2027; raised to the one-week floor; `INPUT_REQUIRED` | BEN-011 to BEN-013; smoke 7b | 16 |
| BEN-034 | Position eliminated in British Columbia with notice owed | Decision stops until HR acknowledges `benefits.common_law_notice` and writes a reason | smoke 7c; BEN-003 | 16 |
| BEN-035 | Rate change reaching back 5 months with 3 months set | HR approves the part older than 3 months; `SETTING_NOT_SET` before the organization chooses | smoke 8 | 15 |
| BEN-036 | Carrier invoice reconciled and approved | Refused without its differences; approved after HR and finance, never by the preparer | smoke 9a–c | 12, 15 |
| BEN-037 | Child turns 21 on 15 June 2027 | Employee and HR told on 16 April 2027; proof of studies asked | smoke 3 | 15 |
| BEN-038 | Dental opt-out without proof; Quebec employee opts out of drug coverage with no other private plan | Refused; refused (RAMQ) | smoke 7a; rule test | 15 |
| BEN-039 | Full-time hire reaches eligibility for a mandatory OMERS membership | Enrolled automatically on the date, employee told, HR confirms; contributions in the next pay; OMERS file | engine and file test | 9, 15 |
| BEN-040 | Union trust plan contributions for a month | Hours-based remittance from the agreement's rates in the generic trust file | file test | 12, 15 |

---

## 14. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/05` | Points here at the top; open questions closed; eligibility, coordination, leaves, termination, billing and pensions marked where they changed |
| `stories/05` | BEN-001, BEN-002, BEN-005 to BEN-009 follow this document; new stories BEN-041 to BEN-043 (coverage when employment ends, carrier invoices, two agreements and two plans); scenarios BEN-020 to BEN-040 in §13 |
| `docs/17` §7.7 and E3 | The governing agreement is chosen by HR (§5.1) |
| `docs/20` §6.1, §6.2, SP4, SP5 and MP-016 | Coordination of benefits is HR's decision (§5.2); change rules match employment type and can run to the end of severance (§7.1); the caution outside Ontario (§7.2) |
| `docs/15` Steps 15 and 16 | Read this document; build on migration 0012; pass BEN-020 to BEN-040 in the steps §13 names |
| `docs/16` | Q6, Q13 and Q37 decided; Q36 stays an item to verify, with the caution; the life event window and retro months chosen at setup; items to verify for this module |
| `docs/22` | Settings from 0012 are listed here, not in `docs/22` §2; FB-020, FB-021 and FB-023 decided |
| `AGENTS.md` | Reading order item 13; rule 50; Step 1 migration 0012 and its smoke test; Step 15 |
| `.cursor/rules/00-cando.mdc` | Rule 50 in short |
| `rules/benefits/benefit-change-rule-templates.json` | `employmentTypes` and `end_of_severance`; termination asked per class at setup |
| `reference/several_positions_reference.py`, `tests/assignments/several_positions_cases.json` | Coordination returns HR's decision with the contract order (COB-001, COB-002); change rules by employment type and to the end of severance (BEN-011 to BEN-013) |
| `tests/schema/schema_0006_smoke.sql` | Plans state their waiting period and late-enrolment rule; coordination orders carry HR's decision and reason; no rule relaxed |

Where a listed document still says otherwise, this document wins.

---

## 15. Open questions and items to verify

| Item | Until decided |
| --- | --- |
| Benefits during notice outside Ontario (Q36) | The caution in §7.2 for every province but Ontario; employment counsel review per province before Step 16 |
| Pension plan employer specifications (BC MPP, OMERS, HOOPP, LAPP) | Obtained from each plan with test files before Step 15; golden files per plan |
| Quebec RAMQ rules for opt-outs and the drug coverage minimum | Checked against RAMQ's guidance and the Act respecting prescription drug insurance before a Quebec customer's first enrolment |
| Carrier and trust file formats | Generic files at launch; each format from the carrier's or trust's specification per customer |

---

## Sources

- RAMQ, Information on private plans (joining an employer's plan, proof of other coverage, choosing among private plans): https://www.ramq.gouv.qc.ca/en/citizens/prescription-drug-insurance/information-private-plans
- Ontario Employment Standards Act, 2000, ss. 60–61 (benefit plan contributions during the notice period), as in `docs/20` §6.3
