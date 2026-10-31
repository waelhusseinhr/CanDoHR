# 22 · Values, defaults and fallbacks

Oct 25, 2026 · @Wael

This document answers one question for the whole pack: where may a value live? It comes from the owner's review on 25 Oct 2026, which asked that nothing in CanDo be hard-coded, that no fallback ever happen silently, and that any doubt about a fallback go to the owner as a question.

It covers:

- the three rules every document, migration and line of code follows (§1);
- the settings migration 0008 adds, so that every value an organization might want different is a setting (§2);
- defaults: which come from settings, which columns have none, and the few that stay (§3);
- organization lists: each organization's own values, mapped to fixed categories (§3.4);
- languages as data: any language for an organization's data, screens in English and French at launch (§4);
- the register of every fallback, with who decided it (§5);
- legal values moved out of prose and code into the rules files (§6);
- the reference calculators, which no longer carry values of their own (§7);
- countries and postal codes (§8);
- the automatic check that keeps all of this true (§9);
- changes to other documents (§10) and the open question (§11).

**Precedence.** On these topics this document wins over every other document in the pack, including `docs/21`. The schema is `schema/0008_values_and_languages.sql` (migration 0008, Step 1), checked by `tests/schema/schema_0008_smoke.sql`. The register is `rules/register/values-and-fallbacks.json`, checked by `tests/hardcoding/check_values.py`.

---

## 1. The rules

### 1.1 Values are data (AGENTS rule 43)

A value an organization could want different is never written in code, in a database check or in a document as a fixed number. It lives in one of four places:

| Kind of value | Where it lives | Example |
| --- | --- | --- |
| A choice or number an organization can change | A setting in `platform.setting_definition`, read with `platform.setting()` for a date (and an employer where allowed) | Longest support access grant: `support.max_grant_days`, 7 days, never more than 7 |
| A list the organization names and orders itself | The organization's list in `core.list_value`, each value mapped to a fixed category | Employment types: "Regular full-time" in the category `permanent` |
| A value set by law, a regulator or a published standard | A rules file in `rules/`, with its source and status | Ontario Health Premium bands; EI employer multiplier |
| Something that has no business meaning | Code or the database, classified in the register (§9) | The first status of a draft; a list's sort order; "no adjustment" |

A **safety limit** is a setting with a ceiling: the organization can make it stricter, never looser (support access at most 7 days; locked settings in `docs/21` §2.2).

A number in a requirement or story is the default of a named setting or a value from a cited rule, never a constant. Each module review turns the numbers in its documents into settings or rule values; §10.2 lists the ones already found for modules not yet reviewed.

### 1.2 No silent fallbacks (AGENTS rule 44)

A fallback is what CanDo does when the value it needs is missing. CanDo uses only the fallbacks in the register (§5). Everything else stops with a named error that tells the user what is missing, for example `SETTING_NOT_SET`, `LIST_VALUE_UNKNOWN`, `RULE_NOT_VERIFIED`, `JURISDICTION_RULE_MISSING`, `TRANSLATION_MISSING`, `UNRESOLVED_INTERACTION`.

For anyone building CanDo, person or AI agent:

1. Never invent a fallback: no "use 0", "use the first one", "use English", "use the default profile" unless the register says so.
2. When a case is not covered, stop. Write the question in `docs/16`, with what you would propose, and ask the owner how the fallback should work. Continue only with work that does not depend on the answer.
3. A new fallback enters the register with its source and status (`decided`, `spec`, `proposed` or `pending`) in the same pull request as the code, and the code names it (`# fallback: FB-NNN`).
4. A `proposed` or `pending` fallback is confirmed in the owner's review of that module before go-live.

### 1.3 Languages are data (AGENTS rule 45)

Two things are kept apart. **Screens** (menus, buttons, messages, help) are each user's own choice: a switch at the top of every screen, EN or FR at launch, whatever the organization uses. **The organization's own words** (job titles, unit names, its lists, its letters) show exactly as the organization typed them, in the language it chose at setup, tagged with that language when it differs from the screen. No code assumes English or French. §4 has the detail.

---

## 2. Settings added in migration 0008

### 2.1 How the catalogue now works

- Every setting has a **decision status**: `decided` (chosen by the owner in a module review), `spec_default` (written in the specifications; confirmed in that module's review) or `pending` (no CanDo default: each organization chooses at setup, and `platform.setting()` raises `SETTING_NOT_SET` until it does).
- A number can have a **minimum and maximum**; a JSON setting lists its **required keys**. Organization values and CanDo's own defaults pass the same checks (`SETTING_BELOW_MINIMUM`, `SETTING_ABOVE_MAXIMUM`, `SETTING_KEYS_MISSING`, `SETTING_VALUE_TYPE`, `SETTING_VALUE_NOT_ALLOWED`).
- `platform.setting()` raises `SETTING_UNKNOWN` for a key that does not exist; it never returns nothing.
- Functions that read a setting never carry the value as a fallback of their own. `platform.required_approvals()` now reads every number from `retro.backdate_approval`, which gained `olderHrApprovals` (2: the two HR approvals of R5.1).

### 2.2 The new settings

Each default is the value an earlier migration or specification already used, so nothing changes for an organization until it changes the setting. Settings with status "spec" are confirmed in their module's review. Settings added or decided by later migrations are described in their module's document: Module 02 (migration 0009) in `docs/23` §2.3, Module 03 (migration 0010) in `docs/24` §2.2, Module 04 (migration 0011) in `docs/25` §2.1, Module 05 (migration 0012) in `docs/26` §2.1, Module 06 (migration 0013) in `docs/27` §2.1, Module 08 (migration 0015) in `docs/29` §2.1, Module 09 (migration 0016) in `docs/30` §2.1, Module 10 (migration 0017) in `docs/31` §2.1, Module 07 (migration 0014) in `docs/28` §2.1, which also records the owner's decision on `reviews.overall_method` (each position by itself) and `reviews.min_section_days` (90 days worked).

| Setting | What it decides | Default | Limits or choices | Set per | Status | Source |
| --- | --- | --- | --- | --- | --- | --- |
| `approvals.coverage_capabilities` | What a manager's approval coverage includes when the coverage record does not list it. | leave, time, overtime | – | organization | spec | docs/20 §2 |
| `approvals.multi_manager_mode` | Default routing for a position with several managers: each approves the days and hours they cover, all must approve, or any one decides. A position can set its own (core.approval_policy). | by_coverage | by_coverage, all, any | organization, employer | spec | docs/20 §2 |
| `approvals.multi_manager_overlap` | When several managers cover the same minutes: all of them approve, or any one decides. | all | all, any | organization, employer | spec | docs/20 §2 |
| `approvals.override_reason_min_length` | Shortest written reason accepted for a position control override, in characters. | 10 | at least 1 | organization | spec | docs/21 §5.2; 0007 §6 |
| `approvals.uncovered_time` | Minutes that no manager's coverage includes go to the line manager, or to HR. | line | line, hr | organization, employer | spec | docs/20 §2 |
| `benefits.default_eligibility_scope` | Eligibility scope of a new benefit plan when not stated. | employer | employer, agreement, assignment | organization | spec | docs/20 §6.1; 0006 |
| `codes.default_code_case` | Letter case of codes in a new code scheme. | as_entered | as_entered, upper | organization | spec | docs/18 §3; 0004 |
| `codes.default_inherit` | Whether codes in a new scheme pass down from job to position to incumbent. | down | none, down | organization | spec | docs/18 §4; 0004 |
| `codes.default_ordering` | Sort order of a new code scheme's values. | natural_code | natural_code, alpha_code, alpha_title, custom_rank, hierarchy | organization | spec | docs/18 §3; 0004 |
| `codes.default_rule_severity` | Severity of a new code scheme rule. | warning | warning, block | organization | spec | docs/18 §5; 0004 |
| `codes.default_structure` | Structure of a new code scheme. | flat | flat, hierarchical | organization | spec | docs/18 §3; 0004 |
| `codes.default_uniqueness` | Whether a value of a new code scheme may be held by only one target at a time. | none | none, unique | organization | spec | docs/18 §3; 0004 |
| `codes.default_values_mode` | Whether a new code scheme takes values from its list, free text, or both. | list | list, free, list_or_free | organization | spec | docs/18 §3; 0004 |
| `codes.default_values_per_target` | How many values of a new code scheme a target can hold at once. | one | one, many | organization | spec | docs/18 §3; 0004 |
| `comp.merit_rating_source` | Rating a merit increase reads for a person in several positions: the section of the position being increased, or the overall rating. | section | section, overall | organization | spec | docs/20 §5.5 |
| `job_evaluation.default_method` | Method of a new job evaluation plan. | point_factor | point_factor, classification, ranking, market_slotting | organization | spec | docs/19 §5; 0005 |
| `job_evaluation.default_purposes` | Purposes of a new job evaluation plan. | grading | – | organization | spec | docs/19 §5; 0005 |
| `job_evaluation.evidence_combine` | How several competency targets combine into one evidence level for a factor. | max | max, min | organization | spec | docs/19 §5; 0005 |
| `market.default_ageing` | How a new market definition ages survey data to a common date. | method none, annualRate 0 | – | organization | spec | docs/19 §7.3; 0005 |
| `market.default_min_sources` | Fewest usable sources before a job is priced. | 1 | at least 1 | organization | spec | docs/19 §7; 0005 |
| `market.default_minimum` | Fewest organizations (and, if set, incumbents) behind a survey value before a new market definition uses it. | nOrgs 4 | – | organization | spec | docs/19 §7.2; 0005 |
| `market.default_statistic` | Market statistic a new market definition targets. | p50 | mean, p10, p25, p50, p75, p90 | organization | spec | docs/19 §7; 0005 |
| `market.default_statistics` | Statistics a new market definition reports. | p25, p50, p75 | – | organization | spec | docs/19 §7; 0005 |
| `market.line_outlier_pct` | A benchmark job more than this per cent above or below the market line is flagged as an outlier for review; it is never removed automatically. | 15 | at least 0; at most 100 | organization | spec | docs/19 §7.6 |
| `pay.default_structure_basis` | Basis of a new pay structure or salary range when none is given. | annual | annual, hourly | organization | spec | docs/19 §7.7; 0005 |
| `pay.structure_rounding` | Unit that grade minimums, midpoints and maximums are rounded to. | 100 | at least 1 | organization | spec | docs/19 §7.7; 0005 |
| `surveys.default_weightings` | Weightings a new survey edition publishes when none are given. | organization | – | organization | spec | docs/19 §6; 0005 |
| `surveys.duties_match_threshold` | Share of duties (per cent) a job must share with a survey job to count as a match. | 70 | at least 0; at most 100 | organization | spec | docs/19 §6; 0005 |
| `competencies.default_criticality` | Criticality of a new competency target when none is given. | important | critical, important, useful | organization | spec | docs/19 §4; 0005 |
| `competencies.gap_sources` | Assessment sources counted when CanDo works out a competency gap. Self-assessments are shown beside the gap and never counted. | calibrated, assessment, manager, peer_360, evidence | – | organization | spec | docs/19 §4; docs/20 §5.4 |
| `finance.fiscal_year_start_month` | First month of the fiscal year of a new legal entity version when not stated. | 1 | at least 1; at most 12 | organization, employer | spec | cando_schema.sql (0001) |
| `funding.default_accounting_basis` | Accounting basis of a new funding source. | accrual | accrual, cash | organization | spec | docs/17 §8.5 |
| `funding.default_alert_days` | Days before a new funding source ends that alerts go to the position owner and finance. | 90, 60, 30 | – | organization | decided | docs/17 §8.6; docs/16 Q12; docs/24 §8.1 (R6.2) |
| `funding.default_cap_behaviour` | What a new funding source does when a cost is over its cap or not eligible for it. | spill_fallback | hard_stop, spill_next_line, spill_fallback, warn_only | organization | decided | docs/17 §8.3; docs/16 Q12; docs/24 §8.1 (R6.2) |
| `funding.default_post_close_policy` | Where retro and corrections go when a new funding source is closed. | fallback | successor, fallback, suspense | organization | decided | docs/17 §8.7; docs/24 §8.1 (R6.3) |
| `gl.default_apply_by` | Which date selects a new GL mapping version. | work_date | work_date, posting_date | organization | spec | docs/17 §9 |
| `money.currency` | Currency of new money records (pay structures, survey editions) when none is given. | CAD | – | organization, employer | spec | cando_schema.sql; 0005 |
| `languages.starter` | Language a new organization types its own words in (its main language): English unless it chooses French at setup. An organization with a work location in Quebec has French (docs/22 §4.2). | English, main language | – | organization | decided | Owner, 25 Oct 2026 (docs/16 Q44); requirements/00; docs/22 §4 |
| `lists.end_reason_applies_to` | What a new end reason can end when not stated. | both | assignment, employment, both | organization | spec | docs/20 §6; 0006 |
| `locations.default_country` | Country of a new work location when none is given. Postal codes are checked against the country's format in ref.country. | CA | – | organization, employer | spec | cando_schema.sql (0001); docs/22 §6 |
| `pay_items.default_cost_target` | Where a new pay item is costed when not stated. | assignment | assignment, explicit | organization | spec | docs/20 §4; 0006 |
| `people.default_person_type` | Person type of a new person record when the transaction does not name one. Must be a code on the organization's person type list. | employee | – | organization | spec | cando_schema.sql (0001); docs/22 §3 |
| `support.max_grant_days` | Longest support access grant, in days. CanDo's security ceiling is 7; an organization can set fewer. | 7 | at least 1; at most 7 | organization | spec | docs/21 §9.3 (R7.3); 0007 §15 |
| `tenant.default_data_isolation` | Database arrangement of a new organization. A First Nation chooses at setup between the shared platform with OCAP® controls and its own database. | shared | shared, dedicated | organization | decided | docs/21 §9.3 (R7.3) |
| `tenant.default_modules` | Modules a new organization starts with. | core | – | organization | spec | cando_schema.sql (0001) |
| `tenant.default_residency` | Data region of a new organization (ref.data_region). | CA | – | organization | spec | docs/02; cando_schema.sql (0001) |
| `positions.max_assignment_fte` | Highest FTE a single assignment may have. | 1.5 | at least 0.01 | organization, employer | spec | cando_schema.sql (0001) |
| `requirements.default_verification` | How a new work requirement is verified when not stated. | document | self_declared, document, credential_record, background_check, assessment, none | organization | spec | docs/18 §6; 0004 |
| `reviews.overall_rounding_step` | Step the overall rating is rounded to, for example 0.5 on a half-point scale. | 1 | at least 0.01 | organization | spec | docs/20 §5.3 |

---

## 3. Defaults and lists

### 3.1 Defaults that come from settings

A column listed in `platform.column_default` has no `DEFAULT` in its table. When an insert leaves it empty, the trigger `a00_fill_from_settings` fills it from the organization's setting (for the employer, where the setting allows), or from the organization's main language or locale. Any other empty value fails its `NOT NULL` or check.

| Column | Filled from |
| --- | --- |
| `benefits.plan.eligibility_scope` | `benefits.default_eligibility_scope` |
| `comp.cycle.eligibility` | `cycles.eligibility_starter` |
| `comp.cycle.guideline_method` | `cycles.guideline_method` |
| `comp.cycle.letter_release` | `cycles.letter_release` |
| `comp.cycle.merit_rating_source` | `comp.merit_rating_source` |
| `comp.incentive_plan.proration` | `incentives.proration` |
| `comp.je_evidence_link.combine` | `job_evaluation.evidence_combine` |
| `comp.je_plan.method` | `job_evaluation.default_method` |
| `comp.je_plan.purposes` | `job_evaluation.default_purposes` |
| `comp.market_definition.ageing` | `market.default_ageing` |
| `comp.market_definition.min_sources` | `market.default_min_sources` |
| `comp.market_definition.minimum` | `market.default_minimum` |
| `comp.market_definition.statistic` | `market.default_statistic` |
| `comp.market_definition.statistics` | `market.default_statistics` |
| `comp.pay_structure.basis` | `pay.default_structure_basis` |
| `comp.pay_structure.currency` | `money.currency` |
| `comp.pay_structure_version.rounding` | `pay.structure_rounding` |
| `comp.salary_range.basis` | `pay.default_structure_basis` |
| `comp.survey.duties_match_threshold` | `surveys.duties_match_threshold` |
| `comp.survey_edition.currency` | `money.currency` |
| `comp.survey_edition.weightings` | `surveys.default_weightings` |
| `core.approval_coverage.capabilities` | `approvals.coverage_capabilities` |
| `core.approval_policy.mode` | `approvals.multi_manager_mode` |
| `core.approval_policy.overlap` | `approvals.multi_manager_overlap` |
| `core.approval_policy.uncovered` | `approvals.uncovered_time` |
| `core.assignment_pay_item.cost_target` | `pay_items.default_cost_target` |
| `core.code_scheme.code_case` | `codes.default_code_case` |
| `core.code_scheme.inherit` | `codes.default_inherit` |
| `core.code_scheme.ordering` | `codes.default_ordering` |
| `core.code_scheme.structure` | `codes.default_structure` |
| `core.code_scheme.uniqueness` | `codes.default_uniqueness` |
| `core.code_scheme.values_mode` | `codes.default_values_mode` |
| `core.code_scheme.values_per_target` | `codes.default_values_per_target` |
| `core.code_scheme_rule.severity` | `codes.default_rule_severity` |
| `core.end_reason.applies_to` | `lists.end_reason_applies_to` |
| `core.legal_entity_version.fiscal_year_start_month` | `finance.fiscal_year_start_month` |
| `core.location_version.country_code` | `locations.default_country` |
| `core.person.person_type` | `people.default_person_type` |
| `core.person_version.preferred_language` | the organization's main language |
| `core.work_requirement.verification` | `requirements.default_verification` |
| `finance.funding_source.accounting_basis` | `funding.default_accounting_basis` |
| `finance.funding_source.alert_days` | `funding.default_alert_days` |
| `finance.funding_source.cap_behaviour` | `funding.default_cap_behaviour` |
| `finance.funding_source.post_close_policy` | `funding.default_post_close_policy` |
| `finance.gl_mapping_version.apply_by` | `gl.default_apply_by` |
| `payroll.one_time_item.allocation` | `payroll.one_time_allocation` |
| `payroll.pay_group.proration_method` | `payroll.default_proration_method` |
| `platform.app_user.locale` | the organization's main locale |
| `platform.tenant.data_isolation` | `tenant.default_data_isolation` |
| `platform.tenant.modules_enabled` | `tenant.default_modules` |
| `platform.tenant.residency` | `tenant.default_residency` |
| `recruit.posting.audience` | `recruit.posting_audience` |
| `recruit.posting.lang` | the organization's main language |
| `recruit.posting.missing_requirement` | `recruit.missing_requirement` |
| `recruit.posting.pay_basis` | `recruit.posting_pay_basis` |
| `recruit.posting.pay_shown` | `recruit.posting_pay_shown` |
| `recruit.posting.seniority_applies` | `recruit.apply_agreement_seniority` |
| `talent.competency_target.criticality` | `competencies.default_criticality` |
| `talent.learning_assignment.language` | the organization's main language |
| `talent.review.min_section_days` | `reviews.min_section_days` |
| `talent.review.overall_method` | `reviews.overall_method` |
| `talent.review_cycle.calibration` | `performance.calibration` |
| `talent.review_cycle.feedback_360_use` | `performance.feedback_360_use` |
| `talent.review_cycle.new_hire_no_rating_months` | `performance.new_hire_no_rating_months` |
| `talent.review_cycle.weights` | `performance.weights_starter` |
| `talent.talent_review.uses_nine_box` | `succession.nine_box_enabled` |
| `talent.training_rule.early_window_days` | `learning.refresher_early_window_days` |
| `talent.training_rule.events` | `learning.assignment_events` |

### 3.2 Columns with no default at all

These columns have a legal or pay effect where neither value is the safe one, so whoever creates the row states the value: a leave type's paid percentage, job protection, ROE effect and whether its reason is restricted; a shift's unpaid break; whether a requisition is for an existing vacancy and whether it uses AI screening; whether a benefit-change rule or decision offers conversion; whether a pay code accrues leave; a pay result's territorial payroll tax; whether a survey licence restricts derived results; whether an employer is a First Nation government; the overtime rate basis of a time line (written by the time engine from the rule); the EI employer rate (§6.3). Setup screens and templates can propose a value; the database never assumes one.

### 3.3 Defaults that stay

A default stays only when it is one of these, and the register gives each one its class:

| Class | What it means | How many | Examples |
| --- | --- | --- | --- |
| technical | Internal shape: what a row points to, where it came from, how it is stored or shown. No business meaning. | 26 | `benefits.practice_market.masked`, `comp.je_plan_version.source`, `comp.market_pricing_run.stale`, `comp.survey_pseudonym.pseudonym` |
| initial state | The first state of a workflow record (draft, pending, active). The workflow moves it on. | 39 | `benefits.change_decision.status`, `comp.decision.out_of_guideline`, `comp.je_plan.status`, `comp.je_plan_version.status` |
| counter | A count or running total that starts at zero. | 7 | `core.employee_number_counter.last_value`, `core.probation.extended_by`, `payroll.deduction_arrears.recovered`, `payroll.overpayment.recovered_amount` |
| display order | Where an item sorts on screen until the organization reorders it. | 6 | `comp.je_factor.display_order`, `comp.total_rewards_component.display_order`, `core.code_scheme.display_order`, `core.work_requirement.display_order` |
| law until exemption | The law applies until an exemption or a claim is recorded: tax, CPP, EI and overtime apply; TD1 amounts are nothing claimed. It errs on the side of compliance and the employee. | 18 | `core.job_version.overtime_eligible`, `core.location_version.on_reserve`, `payroll.pay_code.cpp_pensionable`, `payroll.pay_code.ei_insurable` |
| safety | The most protective value for security or privacy (MFA on, restricted cases, the assistant off until approved). It can be loosened only where a setting allows. | 5 | `compliance.case_file.restricted`, `core.code_scheme.override_needs_reason`, `platform.app_user.mfa_required`, `platform.tenant.assistant_enabled` |
| neutral choice | The neutral value of an option with no legal or pay effect (a display flag, a feature not switched on, no adjustment). The organization sets it on the record. | 24 | `benefits.practice.enabled`, `comp.market_composite.is_benchmark`, `comp.market_definition.adjust_pct`, `comp.market_definition.is_default` |
| decided | Chosen by the product owner in a module review (cited). | 1 | `platform.tenant.ocap_controls` |

Columns filled with the time, a new id or an empty list are technical and are not listed in the register.

### 3.4 Organization lists mapped to categories

Lists that an organization would want to name and order itself are no longer fixed checks. Each organization has its own values in `core.list_value`, each mapped to a fixed **category** that CanDo's logic, reports and the law read. A new organization starts with the starter values in `ref.list_starter` and changes them at setup.

| List | Used on | Fixed categories | Starter values |
| --- | --- | --- | --- |
| Case types (`case_kind`) | compliance cases | grievance, accommodation, return_to_work, investigation, privacy_request, wcb_claim, pay_equity, other, complaint, discipline | Grievance; Accommodation; Return to work; Investigation; Privacy request; Workers' compensation claim; Pay equity; Other; Complaint (human rights, employment standards, harassment); Warning letter or discipline |
| Pay decision types (`comp_decision_kind`) | pay decisions | merit, promotion, market_adjustment, equity_adjustment, retention, counter_offer, bonus, lump_sum, other, demotion, acting, catch_up | Merit increase; Promotion; Market adjustment; Equity adjustment; Retention increase; Bonus; Lump sum; Demotion or reclassification down; Acting pay; Catch-up to range minimum |
| Employment types (`employment_type`) | positions, assignments, employments | permanent, term, casual, auxiliary, seasonal, student | Permanent; Term; Auxiliary; Seasonal; Casual; Student |
| Language requirements of positions (`language_requirement`) | positions | one_language, two_languages, several_languages, other | English (one_language); French (one_language); English and French, level B (two_languages); English and French, level C (two_languages); Other |
| Person types (`person_type`) | people | employee, elected_official, board_appointee, volunteer, contractor, student, candidate_converted | Employee; Elected official; Board appointee; Volunteer; Contractor; Student; Former candidate |
| Posting channels (`posting_channel`) | posting channels (docs/23 §4.1) | partner_job_board, career_page, google, indeed_free, professional_body, other | Job boards through CanDo's posting partner; Our career page; Google for Jobs; Indeed free listing; Professional and regulatory bodies; Other |
| Values recognition is tied to (`recognition_value`) | recognition (docs/31 §5.1); no starter values, the organization enters its own | value |  |
| Requisition types (`requisition_type`) | requisitions | replacement, additional_headcount, new_position | Replacement; Additional headcount; New position |
| Review types (`review_kind`) | reviews | probation, annual, mid_year, pip, other | Probation review; Annual review; Mid-year review; Performance improvement plan |
| Successor readiness levels (`succession_readiness`) | successors (docs/30 §6.1) | ready_now, near_term, long_term | Ready now; Ready in 1 to 2 years (near_term); Ready in 3 years or more (long_term) |

Rules for every list:

- A value is never deleted (`LIST_VALUE_RETIRE_INSTEAD`); it is retired. A retired value stays valid on existing records; screens and imports offer only active values.
- A value's category never changes (`LIST_CATEGORY_IMMUTABLE`); add a new value instead.
- A record that uses a value not on the organization's list is refused (`LIST_VALUE_UNKNOWN`).
- Logic reads only the category. An employment's status, for example, is worked out from the categories of its positions' employment types, in the order of `employment.status_precedence`; a category the precedence does not list stops with `EMPLOYMENT_STATUS_UNRESOLVED` (FB-027).

### 3.5 Fixed lists that stay

| Class | What it means | How many | Examples |
| --- | --- | --- | --- |
| system status | A state CanDo's own workflow moves a record through. Code depends on every value; screens show each organization's wording through translations, never new values. | 152 | `benefits.carrier_invoice.status`, `benefits.change_decision.outcome`, `benefits.change_decision.proposed_outcome`, `benefits.change_decision.status` |
| engine method | A way CanDo calculates, routes, matches or stores an entry. Each value has code behind it; the organization chooses among them (through a setting, a list category or the record itself) and a new value needs new code. | 128 | `benefits.change_rule.action`, `benefits.leave_contribution_choice.method`, `benefits.leave_rule.action`, `benefits.leave_rule.then_action` |
| published vocabulary | Values defined by law, a government body or a published standard (CRA, Service Canada, Statistics Canada, Payments Canada, the statute). They change only when the publication changes. | 27 | `comp.lti_grant.instrument`, `core.code_mapping.relation`, `core.legal_entity_version.regulatory_jurisdiction`, `core.location_version.northern_zone` |
| taxonomy | Fixed categories that CanDo's logic, reports or the law read. Organizations keep their own names and values in their own records (or in core.list_value) and map them to these categories. | 75 | `benefits.dependent.relationship`, `benefits.opt_out.plan_kind`, `benefits.plan.kind`, `comp.incentive_plan.kind` |
| technical | Internal shape: what a row points to, where it came from, how it is stored or shown. No business meaning. | 62 | `benefits.enrolment.source`, `benefits.practice.source`, `benefits.practice.value_type`, `benefits.practice_own_value.source` |

The register lists every one with its values. Adding a value to one of these needs code, so it is a change to the product, not to an organization.

---

## 4. Languages

### 4.1 What is decided

Option (a) of the review: the database is ready for any language now; screens are in English and French at launch; other languages are added as data.

- `ref.language` holds the languages CanDo can keep data in (BCP 47 codes), each with its English and French names, its own name, its writing direction and whether CanDo has screens in it. It starts with English and French (screens available), Inuktut and Inuinnaqtun, Cree, Ojibwe, Mi'kmaq, Mohawk, Dene, Blackfoot, Arabic, Persian, Urdu, Spanish, Punjabi, Chinese, Tagalog and Ukrainian. Adding a language is a new row, never a code change.
- `ref.locale` holds the formats (dates, numbers) for each language in Canada.
- The fixed type `ref.lang` (English or French only) is gone. Every language column is text referring to `ref.language`.

### 4.2 Screens and the organization's own words

Decided with the owner on 25 Oct 2026:

| What | Rule |
| --- | --- |
| Screens | Each user picks EN or FR at the top of the screen, at any time (`platform.app_user.locale`). It has nothing to do with the organization's own language |
| The organization's own words | At setup the organization picks the language it types its words in: English or French (its main language, `languages.starter`, English unless it chooses French). Words show as typed, for every user. Nobody has to type anything twice |
| A word not in the screen's language | Shown as typed, with a small tag (EN or FR) so the user knows it is in the other language on purpose (FB-016) |
| Letters, emails and documents | Sent in the language the employee picked when the template exists in it; otherwise in the language it exists in (FB-033) |
| Quebec | An organization with a work location in Quebec keeps its words in French: French is its main or a required language (`FRENCH_REQUIRED_FOR_QUEBEC`, a legal floor under the Charter of the French Language). An English version for such an organization is CanDo's paid service |
| Translation | Only through CanDo's translation service, sold by CanDo on the organization's request and charged by use (§4.6). No do-it-yourself translation button |

`platform.tenant_language` records the languages an organization's words are kept in: its main language, and any other language some or all of its texts have (required: every required text has it; optional: some do, for example after the translation service). A language becomes required only when every text already has it: `platform.missing_translations()` lists what is missing, and switching the language to required is refused until the list is empty (`TRANSLATIONS_INCOMPLETE`). A language that is required for Quebec cannot be removed or made optional while the organization has a Quebec work location.

The database stays ready for any language (§4.1); only English and French have screens at launch.

### 4.3 Where texts are kept

- English and French texts stay in their columns (`name_en`, `name_fr`, `title_en`, `title_fr`).
- Every other language goes in `platform.translation`, keyed by table, row and field. Text in a language that has a column is refused there (`TRANSLATION_HAS_COLUMN`), and so is text in a language that is not one of the organization's languages (`LANGUAGE_NOT_ENABLED`).
- `platform.translatable_field` registers every English/French text field of every tenant table. English columns are no longer `NOT NULL`: a required field needs text in the main language and in every required language, checked at commit by the trigger `zz_required_text` (`REQUIRED_TEXT_MISSING`), so a row and its translations can be written in one transaction.
- A new version of a record carries all its texts, including its rows in `platform.translation`; the change-set writer copies them like every other column.
- Every text is read through `platform.text_for()` with the user's screen language. It returns the text, the language it is in, and whether it is in another language than the one asked; the screen then shows the tag (FB-016).

### 4.4 Screens

Each user picks the screen language; the organization does not limit it. A user cannot be given a locale whose language has no screens (`INTERFACE_LANGUAGE_NOT_AVAILABLE`); no screen language is substituted (FB-031). Every user-facing string goes in the resource files of every screen language (`en-CA` and `fr-CA` at launch).

### 4.5 Existing organizations

Migration 0008 keeps each existing organization's languages. Before 0008 every text had English, so English is the main language where the organization had it. French becomes required where every text already has French; otherwise it is kept as optional, and French-screen users see the English text marked, until the texts are complete (FB-017). Migration notices list each organization concerned. An existing organization with a Quebec work location completes its French texts and makes French required (AGENTS.md Step 1).

### 4.6 CanDo's translation service

- Translation of an organization's words into the other language is a paid service. The organization asks CanDo; CanDo quotes and runs it. It is not a button in the organization's screens.
- The service may use AI to translate, including job descriptions. AI only translates: it never writes or rewrites a job description (`docs/21` §6.3).
- Price and checking (Q45, decided 25 Oct 2026): charged by the number of words translated, at a rate that covers the AI cost plus CanDo's margin, quoted and approved by the organization before each job; letters and contracts approved by the organization's HR before they are used, everything else shown when delivered.
- Each job is recorded for the organization (words, languages, price, who asked, who approved), so it can be invoiced and audited. The record is built with the documents module (Step 12).

---

## 5. Fallback register

Status: `decided` (the owner decided it, cited), `spec` (in the specifications, confirmed in that module's review), `proposed` (added here; to confirm), `pending` (an open question in `docs/16`; until it is answered, the behaviour shown is used only where the cited question says so).

| ID | When | CanDo does | Status | Source |
| --- | --- | --- | --- | --- |
| FB-001 | An organization has not set a setting | CanDo's registered default for that setting (platform.setting_definition.default_value), shown on the setup screen as the default | decided | Principle, 25 Oct 2026 (claude/review/01); docs/22 §2 |
| FB-002 | A legal entity has no value of its own for a setting that can be set per employer | The organization's value, then FB-001 | decided | docs/21 §1 |
| FB-003 | A setting has no CanDo default (decision_status pending) and the organization has not chosen | No fallback: SETTING_NOT_SET; setup cannot finish until the organization chooses | decided | AGENTS rule 44 |
| FB-004 | An insert leaves empty a column whose default is registered in platform.column_default | The organization's setting for it (or its main language or locale); any other empty value fails its constraint | decided | docs/22 §3 |
| FB-005 | A manager position is vacant and has no acting manager | Approvals go to the next filled position up the line, and HR is alerted to name an acting manager | decided | R2.1, docs/21 §4.1 |
| FB-006 | Time in a request falls in minutes no manager's approval coverage includes | The line manager, or HR, as the policy's 'uncovered' says (setting approvals.uncovered_time) | spec | docs/20 §2 |
| FB-007 | An approver would approve their own request | The part goes to the approver's own approver; never self-approved (locked setting approvals.no_self_approval) | decided | docs/21 §7.4 |
| FB-008 | A rule value is marked verify_at_load, or is null (not yet researched) | No value is assumed: in production the rule set cannot be activated, and a calculation that needs it stops or warns with RULE_NOT_VERIFIED for HR | decided | rules/employment-standards activation_rule; AGENTS rule 44 |
| FB-009 | No rule edition covers the date | Stop: no calculation without a loaded edition | decided | AGENTS rule 15 |
| FB-010 | Two pay sources or premiums meet and the agreement says nothing about how they combine | Stop with UNRESOLVED_INTERACTION; labour relations completes the agreement version (first_in_order also needs the agreement's evaluation_order) | decided | docs/17 §11; Owner, 27 Oct 2026 (Module 03 review, R7.1) |
| FB-011 | A cost has no explicit distribution | The assignment's, then the position's, then the org unit's distribution, then the suspense account with a task for finance | decided | docs/17 §8.2; Owner, 27 Oct 2026 (Module 03 review, R6.1) |
| FB-012 | A cost is over a funding source's cap or not eligible for it | As the funding source's cap_behaviour says; new sources start from funding.default_cap_behaviour: move the excess to the fallback fund, with alerts at 90, 60 and 30 days | decided | docs/17 §8.3; Owner, 27 Oct 2026 (Module 03 review, R6.2; closes Q12) |
| FB-013 | Retro or a correction reaches a funding source that has closed | The successor source, the fallback source or suspense, as the source's post_close_policy says | decided | docs/17 §8.7; Owner, 27 Oct 2026 (Module 03 review, R6.3) |
| FB-014 | Migration 0008 meets relationship types created before it | They keep the purpose 0007 gave them (mentor: none; hrbp: hr_services; any other: supervision) until the organization reviews them at setup | proposed | schema 0008 §8.3 |
| FB-015 | A competency gap is worked out for a position | The latest assessment from the same position, else the latest from any position, from the sources in competencies.gap_sources; self-assessments are shown and never counted | spec | docs/20 §5.4 |
| FB-016 | A text has no version in the user's screen language | The text as the organization typed it (its main language), with a small tag showing its language (EN or FR). A language the organization keeps as required with no text is a data error (TRANSLATION_MISSING). Other versions come only from the organization or from CanDo's paid translation service | decided | Owner, 25 Oct 2026 (docs/16 Q44) |
| FB-017 | Migration 0008 meets an organization that had French switched on but has texts without French | French is kept as an optional language; a French-screen user sees the English text marked EN until French texts are added | proposed | schema 0008 §9; docs/16 Q44 |
| FB-018 | A published code (NOC) has no title in the language asked | The published language's title, marked with its language (for example EN), until the French NOC is loaded | spec | docs/18 C1; docs/16 Q22 |
| FB-019 | A title is needed for a purpose (posting, funder) that the position has no title for | The working title, then the job's title; the result says which one it is (origin) | decided | R4.4, docs/21 §6.4 |
| FB-020 | A person in several positions is covered by two plans of one kind | HR decides which plan pays first for that person and records why; CanDo shows any order a plan contract sets (for example a union trust plan's) beside the decision, and never orders the plans itself | decided | docs/20 §6.1; docs/16 Q37; Owner, 28 Oct 2026 (Module 05 review, R3.2; closes Q37) |
| FB-021 | A position ends and no benefit-change rule matches the enrolment | HR decides (hr_decides), with the statutory floor shown | decided | docs/20 §6; Owner, 28 Oct 2026 (Module 05 review, R3.4) |
| FB-022 | An employer ends a position with notice owed and the jurisdiction's benefits-during-notice rule is not loaded | Stop with JURISDICTION_RULE_MISSING; a rule marked verify_at_load gives RULE_NOT_VERIFIED to HR | decided | AGENTS rule 44; docs/16 Q36 |
| FB-023 | A person is covered by two agreements and a benefit-class or person-level rule must pick one | HR chooses the governing agreement for that person and records why; CanDo makes no automatic choice (GOVERNING_AGREEMENT_NOT_SET until HR decides) | decided | docs/17 §7.7; docs/16 Q13; Owner, 28 Oct 2026 (Module 05 review, R3.1; closes Q13) |
| FB-024 | A payroll profile has no Indian Act s. 87 exemption recorded | Tax, CPP and EI apply (s87_status not_applicable) until HR records the exemption with its basis. Pre-boarding asks every new hire whether they claim it; a yes gives HR a task due before the first pay | decided | Indian Act s. 87; requirements/03; Owner, 25 Oct 2026 (Module 02 review, F2) |
| FB-025 | A leave or time request names no positions | It covers every position the person holds that is active in the period | spec | docs/20 §3 |
| FB-026 | A one-time payment names no position | Refused until it names a position (payroll.one_time_allocation = assignment); an organization can choose to share unnamed payments by earnings instead | decided | docs/20 §4.3; Owner, 27 Oct 2026 (Module 03 review, R7.2) |
| FB-027 | An employment's status is worked out on a date | The first category in employment.status_precedence held by a position that has not ended; no position on the date gives no status; a category missing from the precedence stops with EMPLOYMENT_STATUS_UNRESOLVED | decided | R1.1, docs/21 §3.1 |
| FB-028 | An employee has no federal or provincial TD1 on file | Claim code 1: the basic personal amount, as CRA requires; HR is reminded to collect the form | decided | CRA TD1 instructions; T4127; Owner, 25 Oct 2026 (Module 02 review, F1) |
| FB-029 | An approval part stays undecided | After approvals.escalate_after_working_days working days it also goes to the approver's own manager | decided | Q34, docs/21 §7.5 |
| FB-030 | An agreement gives less than the law on a standard the law does not let it replace | CanDo pays the law's minimum whatever is approved | decided | R6.1, docs/21 §8.1 |
| FB-031 | A user's language has no screens yet | No substitution: the user is given a locale whose language has screens (INTERFACE_LANGUAGE_NOT_AVAILABLE otherwise); data, documents and notices follow the organization's data languages (FB-016) | decided | docs/22 §4 |
| FB-032 | A new organization is created | It starts with the starter lists (ref.list_starter) and English as the language it types its words in, unless it chooses French at setup (languages.starter); an organization with a Quebec work location keeps its words in French | decided | Owner, 25 Oct 2026 (docs/16 Q44); docs/22 §3-4 |
| FB-033 | A letter, email or document template has no version in the language the employee picked | It is sent in the language the template exists in; for an employee working in Quebec the French version must exist (FRENCH_REQUIRED_FOR_QUEBEC) | decided | Owner, 25 Oct 2026 (docs/16 Q44) |
| FB-034 | A probation counted on the calendar reaches its end date and no one has recorded a decision | The probation is passed on its end date and HR is told; the reminders before the end (probation.end_reminders_days) are there so this rarely happens | decided | Owner, 25 Oct 2026 (Module 02 review, R7.2) |
| FB-035 | Migration 0009 meets an organization that keeps a language other than those of the starter texts as required for its data | Its starter routes, onboarding plans, posting channels and case kinds are not copied, and the migration says so; HR adds them with their texts or copies them once the texts can be completed | proposed | docs/23 §10 |
| FB-036 | A pay statement or tax slip is issued and the person has made no delivery choice | A current employee gets it in CanDo self-service (no consent needed under CRA's rule); a former employee, or one on leave or laid off, gets it on paper unless they consented to electronic delivery; it is never emailed without email consent. A paper request always wins. Choices are per kind of document and can be withdrawn | decided | Owner, 27 Oct 2026 (Module 03 review, R5.1, corrected the same day to follow CRA's rule) |
| FB-037 | A timesheet's facts match none of the organization's timesheet routes | Only its manager's approval is needed (no second approval); second approvals exist only where the organization adds a route | decided | Owner, 28 Oct 2026 (Module 06 review, R4.1) |
| FB-038 | Migration 0014 meets reviews written before it | They are marked rated and keep their ratings and overall method; the 90-day rule and the reasons apply when a rating is next changed | decided | Owner, 28 Oct 2026 (Module 07 review, confirmed after the write-up) |
| FB-039 | Migration 0016 meets plans made before it | They are marked org_chart plans, the only feature that made plans before 0016; position plans and workforce plans start with 0016 | decided | Owner, 29 Oct 2026 (Module 09 review, confirmed after the write-up) |

---

## 6. Legal values moved into the rules files

### 6.1 Ontario Health Premium

The bands in both 2026 statutory editions (`rules/statutory/ca-2026-01-01.json` and `ca-2026-07-01.json`, `provinces.ON.health_premium_V2`) now carry their numbers (`over`, `upto`, `base`, `rate`, `cap`) next to the formula in words. The payroll reference reads them; it held them in code before. All 77 payroll cases give the same results.

### 6.2 Separation, final pay and records

`rules/employment-standards/ca-2026-separation-additions.json` holds the values the module specifications stated only in prose: final pay deadlines (Ontario, British Columbia), statutory severance (Ontario, federal), and records retention (CRA payroll records, six years from the end of the tax year). Every other jurisdiction has the same keys set to null with "Not yet researched". Every entry is `verify_at_load`; it is merged into the employment standards edition in Step 7 with the core HR additions. The same file gives Ontario's holiday pay formula and pay transparency rules as fields (45 days to tell interviewed applicants the outcome; posting records kept 3 years).

### 6.3 EI employer rate

`core.payroll_account.ei_employer_rate` no longer defaults to 1.4. Payroll uses `ei.employer_multiplier` from the rule edition of the pay date; an account stores a rate only when CRA has assigned it a reduced rate, with CRA's reference (`ei_reduced_rate_ref`). Accounts that stored another rate before 0008 keep it until their reference is recorded.

### 6.4 Overtime rate basis

`timeleave.time_line.rate_basis` has no default: the time engine writes it from `overtime.rate_basis` in the employment standards file or from the agreement.

### 6.5 Public wage statistics

Each public wage edition says which statistic each published column is (`ref.public_wage_edition.statistic_columns`, for Job Bank `{"p10": "low", "p50": "median", "p90": "high"}`, docs/19 §6.5). Market pricing reads only this; a published edition must state it.

### 6.6 Benefit practice comparison

What makes a yes/no practice "common in the market" is a value in `rules/total-rewards/benefit-practices.json` (`comparison.boolean_common_at_pct`, 50), and each value type's tolerance is required (`TOLERANCE_NOT_SET` otherwise).

---

## 7. Reference calculators

The five reference calculators are the specifications the TypeScript ports must match. None of them keeps a value of its own any more:

| Calculator | What changed |
| --- | --- |
| Payroll | The Ontario Health Premium comes from the rules. `PM` (months of CPP) and `apply_cpp_exemption` are required inputs; `PR` is required when the bonus method runs; `I_recent` when a run has no periodic pay. Amounts not reported are none, as T4127 defines them; no TD1 on file is claim code 1 (FB-028). |
| Premium stacking | No built-in evaluation order: `first_in_order` without the agreement's `evaluation_order` stops with `UNRESOLVED_INTERACTION` (new case and validation case). |
| Position similarity | No built-in profile: the scorer needs a complete profile (`PROFILE_INCOMPLETE` otherwise). Every starter profile in `rules/classifications/schemes.json` is now complete; before, all but one relied on the scorer's hidden default. |
| Market pricing | No built-in statistic mapping, minimum, ageing, statistics list, outlier threshold or rounding: the definition, edition or plan states them (`DEFINITION_INCOMPLETE`, `EDITION_INCOMPLETE`). The outlier threshold is the setting `market.line_outlier_pct`. |
| Several positions | The request's capability, each assignment's schedule and approval policy, each shift's break, the review's rounding step and minimum days, notice owed, benefit eligibility and conversion offers are required inputs. A missing benefits-during-notice rule stops with `JURISDICTION_RULE_MISSING` when it is needed (new case BEN-010). |

The test cases were changed only by stating their inputs explicitly (the values the calculators used to assume). No expected value changed.

---

## 8. Countries and postal codes

- `ref.country` holds each country's name, whether it has postal codes, their format and whether addresses use Canadian province codes. It starts with Canada and the United States.
- A work location has a country (`core.location_version.country_code`, filled from `locations.default_country`); its postal code is checked against that country's format (`POSTAL_CODE_FORMAT`). Province and holiday jurisdiction are required for a Canadian location and refused for another country (`PROVINCE_REQUIRED`, `PROVINCE_NOT_APPLICABLE`).
- Payroll, employment standards and holiday calendars run for Canadian locations. A location in another country stops a pay run with `LOCATION_OUTSIDE_CANADA` until a payroll for that country exists.
- Data regions are `ref.data_region` (Canada, European Union), not a fixed check.

---

## 9. The automatic check

`tests/hardcoding/check_values.py` runs in CI after the migrations, like the smoke tests:

```
python3 tests/hardcoding/check_values.py --db "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
```

It fails when:

- code (`reference/`, `workers/`, `apps/`, `packages/`) has a literal default, a literal parameter default or a constant without a marker: `# rule:` (the law's or the method's own definition, cited), `# structural:` (no business meaning) or `# fallback: FB-NNN` (a registered fallback); `//` in TypeScript and JavaScript;
- a marker names a fallback the register does not have;
- the database has a fixed value list, a column default or a function parameter default that is not in the register with the same values, or the register names one that no longer exists;
- a column whose default comes from a setting still has a table default;
- an API contract (`api/*.yaml`) has a `default:` that is not in the register: a business value there is written "When not given, the organization's setting …" or made required, never a literal;
- a setting is not described in `docs/21` §1 or §2.2 of this document, or a pending setting has no question in `docs/16`;
- a fallback has no source or status, or is missing from §5.

When it fails, the fix is never to add a marker to silence it. Decide what the value is: a setting, an organization list, a rule value, or something structural; then register it with its class and source, in the same pull request.

---

## 10. Changes to other documents

### 10.1 Changed with this document

| Document | Change |
| --- | --- |
| `AGENTS.md` | Reading order item 9; rules 10, 43, 44 and 45; Step 1 instructions for migration 0008; the commands for the 0008 smoke test and the check |
| `.cursor/rules/00-cando.mdc` | Rules 43 to 45 in short |
| `docs/13` | §1 and §3: screens in English and French at launch; data in the organization's languages (§4 here) |
| `docs/16` | Q44 decided; Q45 (translation service) added |
| `docs/21` | Points here for strict settings, organization lists and languages; R4.3 and §6.3: AI may translate job descriptions through CanDo's service, never write them |
| `requirements/00` | The languages decision closed |
| `api/openapi.yaml`, `openapi-codes.yaml`, `openapi-total-rewards.yaml`, `openapi-several-positions.yaml` | `lang` is any of the organization's languages (BCP 47) and required; a survey file states its locale; business defaults (approval routing, coverage, cost target, survey threshold, currency, minimum sources, NOC version, similarity profile) became "the organization's setting" or required fields |
| Rules files | §6 |
| Reference calculators and test cases | §7 |
| Smoke tests 0003 to 0007 | Fixtures brought up to the 0008 rules (organizations created first, relationship types with their purpose, explicit language, rate basis, leave and benefit flags); no rule relaxed |

### 10.2 Numbers to turn into settings in later module reviews

These numbers appear in documents for modules not yet reviewed. Until their review, each is the default of the setting named here, created in that module's migration; none is written in code.

| Where | Number | Setting to create |
| --- | --- | --- |
| `docs/10` §1 | Sessions: 8 hours absolute, 30 minutes idle for privileged roles | `security.session_max_hours` (8), `security.privileged_idle_minutes` (30), each with CanDo's ceiling |
| `stories/07-to-10-talent` PERF-003; `stories/12` ANA-004 | Smallest group shown in aggregate: 10 | `privacy.min_group_size_self_id` (10): created in migration 0011 for pay gap analysis, never lower than 10 (`docs/25` §8.2) |
| `requirements/10` | Smallest group for survey results: 5, never below 3 | Reviewed: `engagement.min_group_size` (5, minimum 3) is in `docs/31` §2.1 for results by unit and other breakdowns; self-identified groups keep `privacy.min_group_size_self_id` (10) (`docs/31` §3.3) |
| `stories/07-to-10-talent` LRN-002 | Credential expiry alerts at 90, 60 and 30 days | Reviewed: `learning.credential_alert_days` is in `docs/29` §2.1 (employee 90, 60 and 30 days; manager and HR 30 days and on the expiry date) |
| `requirements/10` | Service milestones every 5 years | Reviewed: `recognition.milestone_years` ([5, 10, 15, … 50]) is in `docs/31` §2.1 |
| `requirements/02` | Ontario applicant outcome within 45 days; records kept 3 years | Rule values (§6.2), not settings. Reviewed: the Module 02 settings are in `docs/23` §2.3 |
| `requirements/11`, `stories/11` | Final pay deadlines, severance, notice | Rule values (§6.2), not settings |
| `requirements/04` | Spreads, catch-up months, promotion increase, cycle rules | Reviewed: the Module 04 settings are in `docs/25` §2.1 |
| `requirements/08`, `stories/07-to-10-talent` LRN stories | Reminders, refresher windows, deadlines after a change in the law, request approvals, records retention | Reviewed: the Module 08 settings are in `docs/29` §2.1; the training the law requires is a rule value (`rules/learning`) |
| `requirements/09`, `stories/07-to-10-talent` SUCC stories | Critical role weights, plan review cycles, the smallest group for bias prompts, thin turnover history | Reviewed: the Module 09 settings are in `docs/30` §2.1; bias prompts use `privacy.min_group_size_self_id` (10) |
| `requirements/07`, `stories/07-to-10-talent` PERF stories | Rating points, weights, minimum days, 360° rater counts, check-in rhythm, plan length | Reviewed: the Module 07 settings are in `docs/28` §2.1 |
| `requirements/06` | Rounding, meal breaks, carry-over warnings, schedule notice, the long-absence prompt | Reviewed: the Module 06 settings are in `docs/27` §2.1; overtime exemptions and schedule notice are rule values (`ca-2026-time-additions.json`) |
| `requirements/05` | Life event windows ("often 31 days"), waiting periods, how far back premium adjustments go, dependent age-out notice | Reviewed: the Module 05 settings are in `docs/26` §2.1; the window and retro months are chosen at setup, waiting periods are required on each plan |
| `requirements/03` | Remittance reminders, the parallel run's length, former employees' access | Reviewed: the Module 03 settings are in `docs/24` §2.2; garnishment protection, banked time limits and slip delivery are rule values (`ca-2026-payroll-additions.json`) |

---

## 11. Decided after this document was written

| # | Question | Decision (25 Oct 2026) |
| --- | --- | --- |
| Q44 | Languages: screens and the organization's own words | Screens: each user picks EN or FR at the top. Words: shown as typed, in the language the organization chose at setup, tagged EN or FR when they differ from the screen. Quebec: French. Translation only through CanDo's paid service (§4.2, §4.6) |
| — | Fallbacks marked `spec` or `proposed` (§5) | Brought to the owner in each module's review, starting with Module 02 |
| FB-028 | No TD1 on file at the first payroll (Module 02 review) | Tax on the basic personal amount only, as CRA requires, and HR is reminded to collect the form |
| FB-024 | No s. 87 exemption recorded (Module 02 review) | Normal deductions until HR records it with its basis; pre-boarding asks every new hire, and a yes gives HR a task before the first pay |
| FB-034 | A probation's end date passes with no decision (Module 02 review) | Passed on the end date, and HR is told (`docs/23` §7.2) |
| FB-010 | Premiums the agreement does not combine (Module 03 review) | The line stops with `UNRESOLVED_INTERACTION` and labour relations completes the rule; the employee is held by default (`docs/24` §5.5) |
| FB-011 | A cost with no cost coding (Module 03 review) | The assignment's, the position's, then the unit's coding, otherwise suspense with a finance task; pay is not delayed |
| FB-012 | Pay over a funding source's cap or not eligible (Module 03 review) | The fallback fund, with alerts at 90, 60 and 30 days; each source can say otherwise (closes Q12) |
| FB-013 | Retro reaching a closed funding source (Module 03 review) | Where the source's post-close policy sends it, on the funder adjustment report |
| FB-026 | A one-time payment with no position (Module 03 review) | Refused until it names one; an organization can choose to share by earnings (`docs/24` §8.2) |
| FB-036 | A pay statement or slip with no delivery choice (Module 03 review, new) | CRA's rule: self-service for current employees, paper for former employees and people on leave or laid off unless they consent, never email without consent (`docs/24` §7.1) |
| FB-020 | Two plans of one kind cover a person (Module 05 review) | HR sets which pays first and records why; any order a plan contract sets is shown beside it; CanDo never orders the plans (`docs/26` §5.2, closes Q37) |
| FB-021 | A position ends and no benefit-change rule matches (Module 05 review) | HR decides, with the statutory floor shown (`docs/26` §7.3) |
| FB-037 | A timesheet matching none of the organization's timesheet routes (Module 06 review, new) | Only its manager's approval; second approvals exist only where the organization adds a route (`docs/27` §6.1) |
| Q35 | The overall review rating for people in several positions (Module 07 review) | Each position stands by itself, rated from 90 days worked; no combined rating unless the organization chooses FTE × days or the primary manager (`docs/28` §6) |
| FB-038 | Reviews written before migration 0014 (Module 07 review, new) | Marked rated; they keep their ratings and overall method, and the new rules apply at the next change of a rating (`docs/28` §10) |
| FB-039 | Plans made before migration 0016 (Module 09 review, new) | Marked org chart plans, the only feature that made plans before it; position and workforce plans start with 0016 (`docs/30` §11) |
| FB-023 | A person under two agreements and a rule must pick one (Module 05 review) | HR chooses the governing agreement and records why; `GOVERNING_AGREEMENT_NOT_SET` until then (`docs/26` §5.1, closes Q13) |

| # | Open question | Proposed until decided |
| --- | --- | --- |
| Q45 | ~~How CanDo's translation service is priced and checked (§4.6)~~ **Decided (25 Oct 2026)** | Per word translated (AI cost plus margin), quoted and approved before each job; letters and contracts approved by the organization's HR before use; other words shown when delivered |
