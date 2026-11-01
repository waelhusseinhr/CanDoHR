# 25 · Compensation decisions

Oct 28, 2026 · @Wael

This document records the owner's review of Module 04 (Compensation Management) and turns each decision into something the build can follow: a setting with its default, a database check, a route the organization edits, or a screen behaviour. The review went round by round; the working record is `claude/review/04-compensation-decisions.md` in the project.

It covers the compensation philosophy, survey imports and what managers see, long-term incentives, range spreads, structure approval, pay below the minimum and above the maximum, location pay, promotions, demotions and acting pay, increase cycles, guideline exceptions and letters, incentive payouts, clawbacks and proration, commissions, what employees see about pay, pay gap groups, compliance reports, total rewards statements, public salary disclosure, the sample job evaluation plan, bargaining costing and the competency model.

**Precedence.** On these topics this document wins over `requirements/04`, `stories/04-compensation.md` and `docs/19` where it adds to them. `docs/22` still wins on values, defaults, languages and fallbacks. §14 lists every place that changes. The schema is `schema/0011_compensation_decisions.sql` (migration 0011, Step 1), checked by `tests/schema/schema_0011_smoke.sql`. Disclosure statutes are in `rules/compensation/salary-disclosure.json`.

**The owner's rules for this module.**

1. Every decision is a default each organization can change at setup or later; only legal floors and safety rules are fixed. CanDo pre-fills its suggested numbers at setup, and the organization keeps or changes them (Q46).
2. People decide pay, through the organization's own routes; no one approves their own recommendation, payout or structure (`SELF_APPROVAL`).
3. Collective agreements keep their own pay rules; the rules here are for non-union pay unless they say otherwise.
4. The job, the market and the person stay separate (`docs/19` §2.1, AGENTS rule 34), and survey data stays within its licence (AGENTS rule 35).

---

## 1. Decisions at a glance

| # | Decision | Setting or rule | Section |
| --- | --- | --- | --- |
| R1.1 | The philosophy is pre-filled ("match the market median") and the organization edits it; an executive approves it before a market-based structure is approved | `comp.philosophy_starter`; `PHILOSOPHY_NOT_APPROVED` | §3 |
| R1.2 | Survey imports: generic CSV and Excel profiles at launch; a publisher template only when a customer sends a sample file and the publisher allows it | Import profiles | §8.3 |
| R1.3 | Managers do not see market ratios until the organization switches it on, and never where a licence restricts derived results | `comp.manager_sees_market_ratio`: off | §8.1 |
| R1.4 | Long-term incentives: basic tracking at launch (grants, vesting, taxable benefit to payroll); no valuations | `comp.lti_grant` | §7.4 |
| R2.1 | Range spreads pre-filled by track: support 30%, professional 40%, management 50%, executive 60% | `comp.range_spread_by_track` | §4.1 |
| R2.2 | A structure version is approved through the organization's route; starter: HR, finance, executive | `pay_structure_version` route | §4.2 |
| R2.3 | Pay below the minimum: flagged with a catch-up plan within a period the organization sets (12 months pre-filled), in cycle budgets | `comp.below_minimum_catch_up_months`: 12 | §4.3 |
| R2.4 | Location pay: ranges per location group, or a premium for the person; each structure says which | `comp.pay_structure.location_method` | §4.4 |
| R3.1 | Pay above the maximum: no CanDo rule; the manager proposes and the route approves | `comp.above_maximum_handling`: manager proposes | §5.1 |
| R3.2 | A promotion pays at least the new minimum and at least a percentage the organization sets (5% pre-filled) | `comp.promotion_min_increase_pct`: 5; `PROMOTION_BELOW_RULE` | §5.2 |
| R3.3 | A demotion keeps the person's pay, red-circled; reducing it needs a caution with a reason | `comp.demotion_pay`: keep; caution `comp.pay_reduced_on_demotion` | §5.3 |
| R3.4 | Non-union acting pay: no CanDo rule; the setup wizard asks | `comp.acting_pay_method`, `comp.acting_pay_percent`: chosen at setup | §5.4 |
| R4.1 | Cycle eligibility starts from pre-filled rules each cycle can change | `cycles.eligibility_starter` | §6.1 |
| R4.2 | Merit guidelines start from a matrix of rating and position in range; range position only where there are no ratings | `cycles.guideline_method`: matrix | §6.2 |
| R4.3 | A recommendation outside the guideline needs a reason and HR's approval | `cycles.out_of_guideline`: reason and HR | §6.3 |
| R4.4 | Cycle letters from the organization's templates; HR reviews and releases them | `cycles.letter_release`: HR review | §6.4 |
| R5.1 | Bonus and incentive payouts approved through the organization's route; starter: manager, HR, finance | `incentive_payout` route | §7.1 |
| R5.2 | A clawback is recovered only as the signed bonus agreement allows, within the law | `CLAWBACK_NOT_SIGNED`; `docs/24` §6.4 | §7.3 |
| R5.3 | Bonuses prorated by eligible days in the plan year; each plan can change it | `incentives.proration`: eligible days | §7.2 |
| R5.4 | Commissions at launch are basic: rates, tiers, caps, results by file, statements, payout | Commission plans | §7.5 |
| R6.1 | Employees see a moderate level of pay information by default | `transparency.employee_view` | §8.1 |
| R6.2 | Pay gap analysis covers gender and the voluntary self-identification groups, with consent, hidden below 10 people | `pay_gap.groups`; `privacy.min_group_size_self_id`: 10, never lower | §8.2 |
| R6.3 | Both the BC pay transparency report and the federal reports at launch | Reports | §8.3 |
| R6.4 | Total rewards statements on request | `total_rewards.statement_mode`: on request | §8.4 |
| R7.1 | Public salary disclosure lists drafted by CanDo, reviewed by HR and finance, approved through the route before publication | `salary_disclosure` route; `DISCLOSURE_NOT_APPROVED` | §10.1 |
| R7.2 | The sample job evaluation plan stays a sample until a pay equity adviser reviews it | `docs/19` §5.3 | §10.2 |
| R7.3 | Bargaining proposals costed at launch; only a ratified agreement version changes pay | `comp.bargaining_scenario` | §10.3 |
| R7.4 | The competency model's indicators and the starting targets by career level accepted as written | UCM 1.0 published starter | §9 |

---

## 2. How the module is set up

### 2.1 Settings

| Setting | Decides | CanDo default | Set per |
| --- | --- | --- | --- |
| `comp.philosophy_starter` | What setup pre-fills as the philosophy's target position | Match the market median (P50) | Organization, employer |
| `comp.manager_sees_market_ratio` | Managers see their team's market ratios | Off | Organization, employer |
| `comp.range_spread_by_track` | Range spread the structure builder starts from, by career track | Support 30%, professional 40%, management 50%, executive 60% | Organization, employer |
| `comp.below_minimum_catch_up_months` | Months to bring someone below the minimum up to it | 12 | Organization, employer |
| `comp.above_maximum_handling` | Increases above the maximum: manager proposes, lump sum, or frozen | Manager proposes | Organization, employer |
| `comp.promotion_min_increase_pct` | Smallest promotion increase, on top of reaching the new minimum | 5% | Organization, employer |
| `comp.demotion_pay` | Pay on a demotion: kept and red-circled, phased down, or reduced to the new maximum | Kept, red-circled | Organization, employer |
| `comp.acting_pay_method` | How acting pay is set | **None: chosen at setup** | Organization, employer |
| `comp.acting_pay_percent` | The percentage for acting pay, where the method uses one | **None: chosen at setup** | Organization, employer |
| `cycles.eligibility_starter` | Eligibility a new cycle starts from | Negotiated increases excluded; hired in the last 3 months excluded; unpaid leave on return | Organization |
| `cycles.guideline_method` | How a new cycle's guidelines work | Rating × range position matrix | Organization |
| `cycles.out_of_guideline` | Recommendations outside the guideline | A reason and HR's approval | Organization, employer |
| `cycles.letter_release` | How cycle letters reach employees | HR reviews and releases | Organization |
| `incentives.proration` | How a new incentive plan prorates awards | By eligible days | Organization, employer |
| `transparency.employee_view` | What employees and managers see about pay | Philosophy summary; market position not shown; own range; quartile; managers see their team's ranges | Organization, employer |
| `pay_gap.groups` | Groups in pay gap analysis | Gender, Indigenous, racialized, disability | Organization |
| `privacy.min_group_size_self_id` | Smallest group shown in results that use self-identification data | 10 (never lower) | Organization |
| `total_rewards.statement_mode` | When total rewards statements are produced | On request | Organization, employer |

Pre-filled numbers follow the Q46 rule: the setup screen shows CanDo's suggestion and the organization keeps or changes it. `privacy.min_group_size_self_id` was named in `docs/22` §10.2 and is created here because pay gap analysis needs it; the organization can raise it, never lower it.

### 2.2 Chosen at setup

`comp.acting_pay_method` and `comp.acting_pay_percent` have no CanDo default because the owner left acting pay to each organization (R3.4). The setup wizard asks the method (a percentage above current pay, the acting job's range minimum, the higher of the two, or the acting job's first step above current pay) and, where the method uses one, the percentage. Until then, acting pay for non-union staff stops with `SETTING_NOT_SET` (FB-003). Collective agreements keep their own acting rules.

### 2.3 Routes

Five new kinds of subject use the organization's routes (`docs/23` §2.2). Starter routes:

| Route | Steps | Decision |
| --- | --- | --- |
| Compensation philosophy | An executive | R1.1 |
| Pay structure approval | HR, then finance, then an executive | R2.2 |
| Pay decision (promotion, demotion, off-cycle, cycle recommendation) | The approving manager, then HR | R3, R4.3 |
| Incentive payout | The manager, then HR, then finance | R5.1 |
| Salary disclosure list | HR review, then finance review and approval | R7.1 |

No one approves their own philosophy, structure version, pay decision, payout or disclosure list (`SELF_APPROVAL`). For a structure version or a philosophy the requester is the person who submitted it.

### 2.4 Caution

`comp.pay_reduced_on_demotion` appears when a demotion or a downward reclassification reduces pay. It states that reducing pay without agreement can be constructive dismissal and that the organization's rule is to keep pay; a written reason is always needed.

---

## 3. The compensation philosophy (R1.1)

Each organization records its philosophy in `comp.philosophy`: the target position against the market overall and by job group (for example lead at P75 for executives), the pay mix, the role of performance, seniority and skills, and notes in the organization's languages. Setup pre-fills the target from `comp.philosophy_starter` (match the median); the organization edits it.

The philosophy goes through the organization's `comp_philosophy` route (an executive in the starter copy). An approved philosophy covers dates and cannot overlap another approved one. A structure version built from a pricing run (a market-based structure) cannot be approved unless an approved philosophy covers its start date (`PHILOSOPHY_NOT_APPROVED`). Structures loaded without market pricing, such as union grids or an existing validated structure, do not need one.

---

## 4. Structures

### 4.1 Range spreads (R2.1)

The structure builder starts each grade's spread from `comp.range_spread_by_track` by the career track of the grade's jobs (`docs/19` §3.1): support 30%, professional 40%, management 50%, executive 60%. A grade with jobs from several tracks starts from the highest track. The analyst can change any grade's spread before approval. Minimum and maximum follow `docs/19` §7.7.

### 4.2 Approval (R2.2)

A structure version becomes `approved` only when it names who submitted it and its route, and the route is complete (`INPUT_REQUIRED`, `ROUTE_APPROVALS_MISSING`), plus the philosophy check in §3. The rest of `docs/19` §7.7 stays: approved versions cannot overlap, and approval writes the salary ranges, recomputes compa-ratios and flags open requisitions.

### 4.3 Below the minimum (R2.3)

When someone's pay is below their range minimum (a "green circle"), CanDo opens a catch-up plan (`comp.range_catch_up`) with the gap and a target date `comp.below_minimum_catch_up_months` after it was flagged (12 pre-filled; 6 where the employer sets 6). The plan's remaining gap is included in cycle budgets and modelling. A plan is closed as met when pay reaches the minimum (a `catch_up` pay decision can name it), or cancelled with a written reason.

### 4.4 Location pay (R2.4)

Each structure says how location pay works (`comp.pay_structure.location_method`):

| Method | How it works |
| --- | --- |
| `none` | One range for everyone |
| `location_ranges` | Each grade has a range per location group (for example south and north); every grade names its group (`LOCATION_GROUP_MISMATCH`) |
| `location_premium` | One range; a location premium is paid to the person as a pay item on the position (`docs/20` §4.2), for example for a northern or remote location |

---

## 5. Pay administration

### 5.1 Above the maximum (R3.1)

Pay above the range maximum (a "red circle") is flagged in reports and on the manager's worksheet. With `comp.above_maximum_handling` = `manager_proposes` (the default) there is no CanDo rule: the manager proposes a lump sum, a base increase or nothing, and the organization's route approves. An organization can choose `lump_sum` or `freeze` instead, and the worksheet then follows that rule.

### 5.2 Promotions (R3.2)

A promotion states the current rate, the new rate and the new range minimum. It pays at least the new minimum and at least `comp.promotion_min_increase_pct` more than the current rate (5% pre-filled); otherwise `PROMOTION_BELOW_RULE`. A promotion from $60,000 into a range starting at $61,000 must pay at least $63,000.

### 5.3 Demotions and reclassification down (R3.3)

With `comp.demotion_pay` = `keep_red_circle` (the default), a non-union demotion keeps the person's pay, red-circled: no base increases until the range catches up. If anyone reduces pay anyway, the pay decision cannot be approved until the caution `comp.pay_reduced_on_demotion` is acknowledged with a reason (`CAUTION_NOT_ACKNOWLEDGED`). Collective agreements keep their own pay protection rules.

### 5.4 Acting pay (R3.4)

Chosen at setup (§2.2). The acting pay decision (category `acting`) records the acting period; pay returns to the substantive rate when it ends (`docs/17` §4.6).

### 5.5 Pay decision kinds

Pay decisions use the organization's list `comp_decision_kind` (`docs/22` §3.4). The review adds three categories with starter values: `demotion`, `acting` and `catch_up`. Logic reads the category, never the organization's code.

---

## 6. Increase cycles

### 6.1 Eligibility (R4.1)

A new cycle starts from `cycles.eligibility_starter`: union groups on negotiated increases are excluded (they get their increases through mass changes, `requirements/04`); people hired within the last 3 months are excluded; people on unpaid leave get their increase when they return. Each cycle can change its own copy (`comp.cycle.eligibility`). Statutory leaves are treated as the law requires: no one loses an increase because of a protected leave.

### 6.2 Guidelines (R4.2)

A new cycle starts with `cycles.guideline_method` = `matrix`: increase guidelines by performance rating and position in range, with percentages set each cycle against the budget. An organization without ratings (or a cycle without them) uses range position only. Across-the-board and manager-discretion cycles are also available (`comp.cycle.guideline_method`).

### 6.3 Recommendations outside the guideline (R4.3)

A recommendation outside the guideline is marked `out_of_guideline` and needs a written reason (`CYCLE_EXCEPTION_REASON_REQUIRED`). With `cycles.out_of_guideline` = `reason_and_hr` (the default), it is approved only when HR has approved it, even if the organization's route has no HR step (`HR_APPROVAL_REQUIRED`). An employer can choose `reason_and_route` (the route only) or `blocked` (`OUT_OF_GUIDELINE_BLOCKED`).

### 6.4 Letters (R4.4)

Cycle letters are generated from the organization's templates in the employee's language. With `cycles.letter_release` = `hr_review` (the default), HR reviews and releases them to self-service; the release is recorded on the decision (`letter_released_by`, `letter_released_at`). The other choices are `automatic` (on the effective date) and `manager_delivers` (PDFs for managers, then self-service).

---

## 7. Variable pay

### 7.1 Payout approval (R5.1)

Each award (`comp.incentive_award`) names its plan and the position it is for, and is approved through the organization's `incentive_payout` route before it goes to payroll as a one-time item (`ROUTE_APPROVALS_MISSING`). The starter route is the manager, HR, then finance. Plans (`comp.incentive_plan`) keep their kind, plan year, rules and clawback terms.

### 7.2 Proration (R5.3)

A new plan starts with `incentives.proration` = `eligible_days`: an award is prorated by the days in the plan year the person was eligible (hire, transfer, unpaid leave). Statutory leaves are treated as the law requires. A plan can choose `employed_on_payout` or `plan_decides`.

### 7.3 Clawbacks (R5.2)

A signing or retention bonus with a clawback names the employee's signed bonus agreement, recorded as a payroll recovery authorization of kind `bonus_clawback` (`CLAWBACK_NOT_SIGNED` otherwise). If the person leaves before the clawback date, the amount is recovered from the final pay only within that authorization and the law's limits (`docs/24` §6.4); anything else is followed up by HR.

### 7.4 Long-term incentives (R1.4)

At launch CanDo tracks long-term incentive grants (`comp.lti_grant`: instrument, grant date, units, exercise price, vesting schedule, the grant document) on plans of kind `long_term` (`LTI_PLAN_REQUIRED`). When a taxable benefit arises (for example on exercise of an option or settlement of a unit), payroll gets the amount as a taxable benefit item. CanDo does not value grants.

### 7.5 Commissions (R5.4)

At launch: commission plans with rates, tiers and caps; results imported by file; statements; payout to payroll as one-time items through the payout route. Draws, recoverable advances and direct connections to sales systems come later.

---

## 8. Transparency, pay gaps, reports and statements

### 8.1 What people see (R6.1, R1.3)

`transparency.employee_view` starts at a moderate level:

| Item | Default | Choices |
| --- | --- | --- |
| Philosophy | Summary | Not shown, summary, full |
| Market position | Not shown | Not shown, general statement, by job group |
| Ranges | Own range | Own, own job family, all |
| Position in range | Quartile | Not shown, quartile, compa-ratio |
| Managers see ranges | Their team's | Their team's, all |

Managers see their team's market ratios only when `comp.manager_sees_market_ratio` is on, and never from a pricing run that uses a survey marked `derived_results_restricted` (`docs/19` §12). This closes `docs/16` Q32.

### 8.2 Pay gap analysis (R6.2)

Pay gap analysis in cycles, structure modelling and pay equity reviews covers the groups in `pay_gap.groups` (gender, Indigenous, racialized, disability). It uses voluntary self-identification only, for people who consented to that use (`docs/21` §9.2), and hides any group smaller than `privacy.min_group_size_self_id` (10, never lower).

### 8.3 Compliance reports and survey imports (R6.3, R1.2)

Both reports are built at launch: the BC pay transparency report (employers with 50 or more employees, due each 1 November from 2026) and the federal reports (pay equity and employment equity) for federally regulated employers. Ontario and Quebec pay equity follow. Survey imports use the generic profiles (`rules/total-rewards/survey-import-profiles.json`); a publisher's template is added when a customer sends a sample file and the publisher allows it. This closes `docs/16` Q31.

### 8.4 Total rewards statements (R6.4)

With `total_rewards.statement_mode` = `on_request` (the default), HR or the employee produces a statement when they ask, using the valuations in `docs/19` §9 and the components the organization shows. The other choices are once a year, or once a year plus an up-to-date view in self-service.

---

## 9. The competency model (R7.4)

The owner accepted the Unified Competency Model as written, including the proposed level-by-level indicators for the four functional competencies, and the starting competency targets by career level (`docs/19` §3.1). `rules/competencies/unified-competency-model.json` is now version `1.0`, status `published_starter`, with every competency's `indicators_status` `as_provided` or `reviewed`. The Step 15 loader publishes it as CanDo's starting framework; each organization copies and edits it. The career level defaults stay hints for suggestions and warnings, never blocking. This closes `docs/16` Q27. French definitions and indicators are still needed before a French-speaking organization uses the framework (Q28).

---

## 10. Public sector and special cases

### 10.1 Public salary disclosure (R7.1)

For an employer subject to a disclosure statute, CanDo drafts the list from amounts paid in the period, by the statute's definitions, from `rules/compensation/salary-disclosure.json`:

| Statute | Who | Threshold |
| --- | --- | --- |
| `ON_PSSDA` | Ontario public sector employers | $100,000 salary paid |
| `BC_FIA_REMUNERATION` | BC public bodies under the Financial Information Act | $75,000 remuneration |
| `BC_PSEC_EXECUTIVE` | BC public sector employers' executives | All executives |
| `BC_SOCIETIES_ACT` | BC societies (directors, and employees and contractors at or above the threshold) | $75,000 remuneration |
| `FN_FNFTA` | First Nations under the First Nations Financial Transparency Act (chief and councillors) | All |

Every entry is `verify_at_load`. The list (`compliance.salary_disclosure`) is reviewed by HR and finance and approved through the organization's route before it is published (`DISCLOSURE_NOT_APPROVED`); the publication date is recorded.

### 10.2 The sample job evaluation plan (R7.2)

The sample gender-neutral plan stays a sample until a pay equity adviser reviews it. Each organization records its own gender-neutral review before using a plan for pay equity, as `docs/19` §5.3 requires. This decides `docs/16` Q29 for now.

### 10.3 Costing bargaining proposals (R7.3)

Labour relations and compensation cost proposals in `comp.bargaining_scenario`: the agreement, the term, the proposals by year (general increases, step changes, premiums, retro) and the results from live pay, benefits and schedule data, with the data date. A scenario can be shared with labour relations. Nothing in a scenario changes pay: a scenario marked ratified names the agreement version that carries the ratified terms, and pay changes only through that version (`docs/21` §8).

---

## 11. Data model (migration 0011)

| Object | What it holds |
| --- | --- |
| Settings in §2.1 | 18 settings; acting pay chosen at setup |
| `platform.workflow_route` subject types `comp_philosophy`, `pay_structure_version`, `comp_decision`, `incentive_payout`, `salary_disclosure`; `check_approval_task()` | §2.3 |
| `comp.philosophy`, `comp.philosophy_approved_on()` | §3 |
| `comp.pay_structure_version.submitted_by`, `route_id`; trigger `comp.check_structure_approval()` | §4.2 |
| `comp.pay_structure.location_method`, `comp.pay_grade.location_group` | §4.4 |
| `comp.range_catch_up` | §4.3 |
| `comp.decision` (requester, route, rates, guideline, exception, reason, catch-up, letter release); `comp.decision_category()`; trigger `comp.check_decision()`; decision categories `demotion`, `acting`, `catch_up` | §5, §6.3, §6.4 |
| `comp.cycle.eligibility`, `guideline_method`, `letter_release`, filled from settings | §6 |
| `comp.incentive_plan`, `comp.incentive_award`, `comp.lti_grant`; recovery authorization kind `bonus_clawback` | §7 |
| `compliance.salary_disclosure` | §10.1 |
| `comp.bargaining_scenario` | §10.3 |
| Caution `comp.pay_reduced_on_demotion`; starter routes; starter decision kinds | §2 |

Every new tenant table has `tenant_id` with forced row-level security; text fields are registered as translatable (`docs/22` §4.3). Existing organizations get the starter routes and decision kinds when 0011 runs, except one that keeps another language as required for its data (FB-035). Rows that existed before 0011 are not rechecked; the new checks apply from their next change (a cycle from before 0011 states its eligibility, guideline method and letter release when it next changes).

---

## 12. Validation, API and events

**Errors added by 0011:** `PHILOSOPHY_NOT_APPROVED`, `LOCATION_GROUP_MISMATCH`, `PROMOTION_BELOW_RULE`, `CYCLE_EXCEPTION_REASON_REQUIRED`, `OUT_OF_GUIDELINE_BLOCKED`, `HR_APPROVAL_REQUIRED`, `CLAWBACK_NOT_SIGNED`, `LTI_PLAN_REQUIRED`, `DISCLOSURE_NOT_APPROVED`. Existing ones used: `INPUT_REQUIRED`, `ROUTE_APPROVALS_MISSING`, `SELF_APPROVAL`, `SETTING_NOT_SET`, `SETTING_BELOW_MINIMUM`, `CAUTION_NOT_ACKNOWLEDGED`, `STRUCTURE_VERSION_IMMUTABLE`.

**Checks in the application (Step 15, Step 18), not the database:** spreads by track in the builder; red circles and the above-maximum rule on the worksheet; acting pay by the chosen method; cycle eligibility from each cycle's rules; the guideline matrix and range position; letters from templates; proration by eligible days; commission calculation from imported results; what employees and managers see; pay gap groups with consent and the minimum group size; report formats; drafting disclosure lists from the statute's definitions; bargaining cost models.

**API** (added to `api/openapi.yaml` in Step 15): `GET/POST /comp/philosophies` with `submit`; `POST /comp/structure-versions/{id}/submit`; `GET /comp/catch-up-plans`; pay decisions with `submit`, `approve` and the exception reason; cycles with eligibility and letters (`POST /comp/cycles/{id}/letters/release`); `GET/POST /comp/incentive-plans`, `/comp/incentive-awards` with `submit`; `GET/POST /comp/lti-grants`; `GET/POST /compliance/salary-disclosures` with `submit` and `publish`; `GET/POST /comp/bargaining-scenarios` with `share`; `GET /me/total-rewards-statement`.

**Events** (added to `api/events.yaml`; identifiers only, AGENTS rule 9): `comp_philosophy.approved`, `pay_structure.version.submitted`, `range_catch_up.opened`, `range_catch_up.closed`, `comp_decision.approved`, `comp_decision.exception_flagged`, `cycle.letters_released`, `incentive_award.approved`, `lti_grant.vested`, `salary_disclosure.published`, `bargaining_scenario.shared`.

---

## 13. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| COMP-010 | Market-based structure submitted before the philosophy is approved | `PHILOSOPHY_NOT_APPROVED`; approved once an executive approves the philosophy | smoke 2c–d | 1, 15 |
| COMP-011 | Structure approved without its route, or without the executive step; analyst approves own philosophy | `INPUT_REQUIRED`; `ROUTE_APPROVALS_MISSING`; `SELF_APPROVAL` | smoke 2a–d | 1, 15 |
| COMP-012 | Customer imports a survey with no publisher template | Generic profile with dry run; a template is added only with a sample file and the publisher's permission | import test | 15 |
| COMP-013 | Manager opens the team view with market ratios off, then on, with a restricted survey in the run | Hidden; shown; hidden for the restricted run | API test | 15 |
| COMP-014 | Builder creates grades for support, professional, management and executive jobs | Spreads start at 30%, 40%, 50% and 60% | unit test | 15 |
| COMP-015 | Structure with ranges per location group | Every grade names its group; two groups for one grade code | smoke 3 | 1, 15 |
| COMP-016 | Employee $1,500 below the minimum on 1 January 2027 | Catch-up target 1 January 2028; 1 July 2027 where the employer sets 6 months; cancelled only with a reason | smoke 4a–c | 15 |
| COMP-017 | Employee above the maximum in a merit cycle | Flagged; manager proposes; route approves | UI test | 15 |
| COMP-018 | Promotion from $60,000 into a range starting at $61,000 | $62,000 refused; $63,000 accepted | smoke 5a | 15 |
| COMP-019 | Demotion that cuts pay from $70,000 to $66,000 | Not approved until the caution is acknowledged with a reason | smoke 5f | 15 |
| COMP-020 | Acting pay before the organization chose a method | `SETTING_NOT_SET` | smoke 1b | 15 |
| COMP-021 | New 2027 merit cycle | Matrix guidelines, HR-reviewed letters, hires in the last 3 months excluded | smoke 6 | 15 |
| COMP-022 | 6% recommendation against a 3% guideline | Refused without a reason; needs HR even when the route has no HR step; refused where the employer blocks exceptions | smoke 5c–e | 15 |
| COMP-023 | Cycle letters generated | Released to self-service only after HR reviews them | UI test | 15 |
| COMP-024 | Retention bonus payout | Approved after the manager, HR and finance | smoke 7c | 15 |
| COMP-025 | Retention bonus with a 12-month clawback | Refused without the signed agreement; recovery within it only | smoke 7b; `docs/24` PAY-076 | 15, 16 |
| COMP-026 | Annual bonus for someone hired on 1 July | Prorated by eligible days; protected leave counted as the law requires | engine test | 15 |
| COMP-027 | Commission results imported for a quarter | Rates, tiers and caps applied; statement; payout through the route | engine test | 15 |
| COMP-028 | Phantom unit grant on a retention plan; then on a long-term plan | `LTI_PLAN_REQUIRED`; recorded with its vesting | smoke 7d | 15 |
| COMP-029 | Employee opens their pay page with the defaults | Philosophy summary, own range and quartile; no market position | API test | 15 |
| COMP-030 | Pay gap report with a group of 7 Indigenous employees; an organization tries a minimum of 8 | Group hidden; `SETTING_BELOW_MINIMUM` | smoke 1b; report test | 15, 18 |
| COMP-031 | BC employer with 60 employees in October 2026 | BC pay transparency report produced for 1 November; federal reports for a federal employer | report test | 18 |
| COMP-032 | Employee asks for a total rewards statement | Produced on request with the organization's components | API test | 15 |
| COMP-033 | BC public body publishes its remuneration list | Refused until HR and finance approve through the route | smoke 8 | 18 |
| COMP-034 | Union proposal of 3% a year for three years | Costed and shared; marking it ratified needs the agreement version | smoke 9 | 7, 15 |
| COMP-035 | Load the Unified Competency Model | Published as the starting framework 1.0; TR-001 passes because every functional competency is reviewed | loader test | 15 |

---

## 14. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/04` | Points here at the top; open questions closed; philosophy, structures, pay administration, cycles, variable pay, transparency and disclosure marked where they changed |
| `stories/04` | COMP-004 cycles from settings and exceptions with HR (§6); new COMP-010 to COMP-035 in §13 |
| `docs/19` | §4.2 and §19 T1: UCM 1.0 accepted; §19 T3, T5, T6 decided |
| `docs/15` Steps 15 and 18 | Read this document; build on migration 0011; pass COMP-010 to COMP-035 in the steps §13 names |
| `docs/16` | Q27, Q29, Q31 and Q32 decided; acting pay chosen at setup; items to verify for this module |
| `docs/22` | Settings from 0011 are listed here, not in `docs/22` §2; `privacy.min_group_size_self_id` created |
| `AGENTS.md` | Reading order item 12; rule 49; Step 1 migration 0011 and its smoke test; Step 15 |
| `.cursor/rules/00-cando.mdc` | Rule 49 in short |
| `rules/competencies/unified-competency-model.json` | Version 1.0, published starter, functional indicators reviewed |
| `rules/compensation/salary-disclosure.json` | New |
| `tests/schema/schema_0005_smoke.sql` | The structure fixture names who submitted it, its route and its approvals, and the tenant has an approved philosophy; no rule relaxed |

Where a listed document still says otherwise, this document wins.

---

## 15. Open questions and items to verify

| Item | Until decided |
| --- | --- |
| Salary disclosure statutes (`rules/compensation/salary-disclosure.json`) | All `verify_at_load`; checked against each statute before Step 18 |
| BC pay transparency report and federal report formats | Built from the regulations and government guidance before Step 18 |
| Pay equity adviser review of the sample plan (Q29) | Sample only |
| French definitions and indicators for UCM (Q28) | Required before a French-speaking organization uses it |

---

## Sources

- BC Ministry of Finance, Pay Transparency Report (1 June 2026): reporting extends to employers with 50 or more employees in November 2026: https://news.gov.bc.ca/releases/2026FIN0022-000633
- Fasken, New pay transparency reporting deadline approaching for BC employers (October 2026): https://www.fasken.com/en/knowledge/2026/10/new-pay-transparency-reporting-deadline-approaching-for-bc-employers
- UBCM, Amendment to SOFI reporting legislation (the $75,000 threshold): https://www.ubcm.ca/node/109792
- BC government, Executive compensation disclosures: https://www2.gov.bc.ca/gov/content/governments/services-for-government/public-sector-management/compensation/executive-compensation-disclosures
- Canadian Council of Christian Charities, Remuneration disclosure obligations of B.C.'s new Societies Act: https://www.cccc.org/news_blogs/legal/2016/01/remuneration-disclosure-obligations-of-b-c-s-new-societies-act/
- Public Sector Salary Disclosure Act, 1996 (Ontario); First Nations Financial Transparency Act (Canada)
