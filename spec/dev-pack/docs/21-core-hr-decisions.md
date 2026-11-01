# 21 · Core HR decisions and organization settings

Oct 25, 2026 · @Wael

This document records the decisions from the owner's review of Module 01 (Core HR & Position Management) and turns each one into a rule the build can follow: a setting with its default, a database check, a validation rule or a screen behaviour. The review was done round by round; the working record is `claude/review/01-core-hr-decisions.md` in the project.

It covers:

- organization settings, and the short list of legal floors and safety rules no setting can change;
- the employee record: employment type per position, probation per bargaining unit, gender, rehire eligibility and the employee number;
- organization structure: routing past vacant manager positions, unit heads, what employees see on the org chart, and reporting across employers;
- positions: positions for everyone, automatic positions for small organizations, budget overrides and where the pay grade lives;
- jobs: NOC as a recommendation, optional starter catalogues, job descriptions without AI and several titles per position;
- changes and approvals: back-dated changes, overpayments, "communicated" changes and the changes that always need HR;
- collective agreements: how an agreement is compared with employment standards law, and who sets agreements up;
- self-service, security and privacy: bank account changes, self-identification categories and OCAP® for First Nation customers.

**Precedence.** On these topics this document wins over `requirements/01` to `13` and over `docs/03`, `04`, `06`, `08`, `10`, `12`, `13`, `17`, `18`, `19` and `20`. §13 lists every place that changes. The schema is `schema/0007_core_hr_decisions.sql` (migration 0007, Step 1), checked by `tests/schema/schema_0007_smoke.sql`. New employment standards keys are in `rules/employment-standards/ca-2026-core-hr-additions.json`.

**The rule behind everything here: every decision is a default that each organization can change, except legal floors and safety rules.** CanDo is sold to many different employers. Code that hard-codes a decision this document lists as a setting is a bug. Code that lets an organization change a locked setting is also a bug.

---

## 1. Decisions at a glance

| # | Decision | Setting and default | Section |
| --- | --- | --- | --- |
| R1.1 | Employment type lives on each position; the employment's status is worked out from its positions | `employment.status_precedence`: permanent, term, auxiliary, seasonal, casual, student | §3.1 |
| R1.2 | Probation per bargaining unit, one employer probation for non-union work, and a trial period when moving inside a unit | `probation.non_union`: 3 calendar months, extendable; `probation.trial_period_non_union`: off | §3.2 |
| R1.3 | Gender is voluntary self-identification only; there is no gender field in the record | None (data model) | §3.3 |
| R1.4 | Rehire eligibility is kept by HR with a reason category and a review date; recruiters see only "check with HR" | `rehire.review_max_months`: 24 | §3.4 |
| R1.5 | One employee number per person, for life | `employee_number.format`: no prefix, 6 digits | §3.5 |
| R1.6 | Service bridging on rehire: the rule proposes, HR confirms | `rehire.service_bridging`: propose, HR confirms | §3.6 |
| R2.1 | Vacant manager position with no acting manager: route to the next filled position up and alert HR | `approvals.vacant_manager`: next filled up, alert HR | §4.1 |
| R2.2 | Each org unit names its head position, with dates | `org.unit_without_head`: warn | §4.2 |
| R2.3 | What employees see on the org chart is set per organization | `org_chart.employee_view`: filled positions as of today only | §4.3 |
| R2.4 | Reporting across employers only under a recorded shared-services arrangement | `reporting.cross_employer`: **locked** | §4.4 |
| R3.1 | Positions for everyone; light mode removed; small organizations get positions created at hire | `positions.management`: managed | §5.1 |
| R3.2 | Over budget or over complement: allowed with finance approval and a written reason | `positions.over_budget`, `positions.over_complement`: finance approval | §5.2 |
| R3.3 | The pay grade comes from the job only; bargaining unit stays on the position | None (data model) | §5.3 |
| R4.1 | NOC recommended, not required | `codes.warn_when_missing`: NOC on jobs | §6.1 |
| R4.2 | Starter job catalogues optional; any coding scheme | Setup choice | §6.2 |
| R4.3 | Job description drafts from NOC duties and the job's requirements; no AI writes job descriptions (AI may only translate them, through CanDo's paid translation service) | Product rule, not a setting | §6.3 |
| R4.4 | A position can have several titles, each with its purpose | None (data model) | §6.4 |
| R5.1 | Back-dated changes into paid periods: HR and payroll approve; over one month back, two HR approvals; retro is then automatic and complete | `retro.backdate_approval`: 1 HR + payroll; 2 HR over 1 month | §7.1 |
| R5.1 | Overpayments are never deducted automatically | `payroll.overpayment_recovery`: employee authorization | §7.2 |
| R5.2 | An employee sees an approved change once it is marked "communicated" | `self_service.show_changes`: when communicated | §7.3 |
| R5.3 | Terminations, demotions and leave- or accommodation-linked changes always need HR | `approvals.hr_required`: **locked** | §7.4 |
| R5.x | `any` decisions are final; undecided approvals escalate after 3 working days; change reasons are each organization's list | `approvals.escalate_after_working_days`: 3 | §7.5 |
| R6.1 | Where agreement and law differ, the agreement applies where the law allows; below-law parts need HR and payroll approval | `agreements.below_law_dual_approval`: **locked**; comparison per agreement: per hour | §8.1 |
| R6.2 | CanDo or a partner sets up agreements; the customer's HR can amend them | `agreements.customer_can_amend`: on | §8.2 |
| R6.x | Seniority by date, hours or points from launch | None | §8.3 |
| R7.1 | Bank account changes: second factor, notices, hold, and HR approval after a live video or phone check with photo ID | `bank_change.hold_hours`: 72; `bank_change.hr_live_verification`: on | §9.1 |
| R7.2 | Self-identification: a library of categories each organization switches on, edits or adds to | None (data model) | §9.2 |
| R7.3 | OCAP®: each First Nation chooses the shared platform with OCAP® controls or its own database, priced accordingly | `platform.tenant.data_isolation`; `support.access_requires_approval`: on | §9.3 |
| R7.x | Installable web app; Entra ID and Okta at launch; full history for every record | None | §9.4 |

---

## 2. Organization settings

### 2.1 How settings work

`platform.setting_definition` is CanDo's catalogue of settings: each has a key, an area, a value type, its allowed values where it has a list, CanDo's default, the scopes it can be set at (the whole organization, or one legal entity) and the decision it comes from. The catalogue is global reference data, seeded by migration 0007 and extended by later migrations.

`platform.tenant_setting` holds an organization's own values. Each value is effective-dated and bi-temporal like every other business row (`docs/03`), written through a change set (`setting.set`, §11), and its history is kept. The database refuses a value of the wrong type (`SETTING_VALUE_TYPE`), a value outside the allowed list (`SETTING_VALUE_NOT_ALLOWED`) and a scope the setting does not allow (`SETTING_SCOPE_NOT_ALLOWED`).

`platform.setting(tenant, key, as_of, legal_entity)` returns the value in force: the legal entity's value, then the organization's, then CanDo's default. Every module reads settings only through this function (or its API equivalent) with a date. A setting is never copied into code, a constant or an environment variable.

Examples of per-employer values: a city that wants hard stops on its council-approved complement while its library board keeps finance approvals, or a different non-union probation for one entity.

Migration 0008 makes the catalogue strict and extends it (`docs/22` §2): every setting has a decision status, numbers can have limits, JSON settings list their required keys, `platform.setting()` raises `SETTING_UNKNOWN` or `SETTING_NOT_SET` instead of returning nothing, and about fifty more values that earlier migrations held as column defaults or checks are now settings. Lists that each organization names itself (employment types, person types and six others) are organization lists mapped to fixed categories (`docs/22` §3.4), and languages are data (`docs/22` §4). On those topics `docs/22` wins over this document.

### 2.2 Locked settings: legal floors and safety rules

A locked setting always returns CanDo's default, and the database refuses an organization's value for it (`SETTING_LOCKED`). The locked list:

| Setting | Why it is locked |
| --- | --- |
| `approvals.no_self_approval` | Nobody approves their own request or change, from any of their positions (also enforced by `SELF_APPROVAL` checks) |
| `approvals.hr_required` | Terminations, demotions and changes linked to a leave or accommodation carry the highest legal risk |
| `reporting.cross_employer` | Personal data crosses employers only under a recorded arrangement (privacy law) |
| `agreements.below_law_dual_approval` | Paying less than a statute allows, where an agreement may replace it, needs two accountable people |

Statutory minimums, privacy and security limits and the audit trail are not settings at all. They come from `rules/`, the schema and AGENTS rules 1 to 38, and nothing in an organization's configuration can lower them.

### 2.3 Settings at setup

The setup wizard (Step 5) asks the questions that shape an organization's start, and writes the answers as settings with the setup date:

- how positions are managed (`positions.management`, §5.1);
- whether to start from a CanDo sector job catalogue, the organization's own file, or nothing (§6.2);
- which code schemes it uses, and whether NOC is required (§6.1);
- what employees see on the org chart (§4.3);
- for a First Nation government, whether its data is on the shared platform with OCAP® controls or in its own database (§9.3).

Everything else starts from CanDo's defaults and can be changed later in Admin → Settings, which shows each setting with its default, the organization's value, who changed it, when and why. Locked settings are shown with the reason they are locked.

---

## 3. The employee record

### 3.1 Employment type on each position

`core.assignment_version.employment_type` holds permanent, term, casual, auxiliary, seasonal or student for each position the person holds. Every new assignment version must carry it (validation `EMPLOYMENT_TYPE_REQUIRED`); the data migration copies it from `core.employment_version.employment_type`, which becomes read-only.

The employment's own status is worked out, never stored: `core.employment_status_type(employment, as_of)` returns the first type in the organization's `employment.status_precedence` list that any of the employment's positions holds on that date, ignoring positions that have ended. With the default order, a person who is permanent in one position and casual in another is a permanent employee. A position suspended for an acting assignment still counts, so acting never costs anyone their permanent status.

Rules that need "is this a permanent employee?" (benefits waiting periods, notice, headcount reports) read the worked-out status. Rules that are about one job (seniority in a unit, casual conversion, dues) read the position's own type.

### 3.2 Probation

`core.probation` holds three kinds of probation, each effective-dated with its history:

| Kind | Started by | Length from | Example |
| --- | --- | --- | --- |
| `agreement` | The first position in a bargaining unit | The agreement's probation rule | 624 paid hours in the part-time unit |
| `employer` | The first non-union position with the employer | `probation.non_union` (default 3 calendar months, extendable) | An excluded coordinator |
| `trial` | A move to another position inside the same unit, where the agreement provides one; or a non-union move when `probation.trial_period_non_union` is on | The agreement or the setting | A promotion with a 60-day trial and a right to return |

A person can be on several probations at once, one per unit (and one employer probation). The database allows only one open probation per employment and unit (smoke check 5b). Each probation names its measure (calendar days or months, hours paid, hours worked, days or shifts worked), and a counted measure names its counter in `core.counter_ledger` (`docs/17` §13), so leaves and part-time hours extend it exactly as the agreement says.

Outcomes are passed, extended (with the extension), failed, waived, returned (a trial that ends with a return to the former position) and ended. Failing, waiving, returning and extending need a written reason. The agreement's rule decides what failing means: for a trial period, usually a return to the former position, which the outcome proposes as a change set.

Check-ins, reminders before the end, leave near the end, extensions (told to the employee before the end date), a probation whose end date passes with no decision (passed, and HR told), the HR review of open cases before a probation is failed, and the confirmation letter were decided in the Module 02 review: `docs/23` §7.

### 3.3 Gender

The employee record has no gender or sex field. Gender identity is collected only through voluntary self-identification (§9.2), with consent, in its own encrypted store, and is reported only in aggregate with small-group suppression.

Pay equity still needs the gender predominance of each job class (Ontario, Quebec and federal pay equity statutes). In CanDo, predominance is set by HR for each job class, with its basis recorded: the statute's tests such as historical incumbency and gender stereotypes of the work, the comparison with the sector, and any aggregate self-identification counts as supporting evidence. A predominance without a recorded basis cannot be used in a pay equity plan. The calculation and plans stay in Module 13 and `docs/19` §5.6.

If a benefits carrier or pension plan later requires a sex field in its file, that will be a field on the carrier enrolment in Module 05, collected only for that plan with its purpose stated, never a field on the person.

### 3.4 Rehire eligibility

`core.rehire_eligibility` replaces the yes/no flag `employment_version.rehire_eligible`, which becomes read-only.

| Status | Meaning | Needs |
| --- | --- | --- |
| `eligible` | Nothing to check | No reason |
| `check_with_hr` | Recruiters must speak to HR before an offer | A reason category and a review date |
| `not_eligible` | HR has decided against rehire for now | A reason category and a review date |

Reason categories are each organization's own list (`core.rehire_reason`), mapped to a fixed set: conduct, performance, job abandonment, policy breach, misrepresentation, safety, contract terms, other. There is deliberately no category for health, leave, accommodation, a complaint, a family matter or any other protected ground, because a rehire ban on those grounds is discriminatory. The note field is restricted to HR and must never name a protected ground; the screen says so.

The review date is required and can be at most `rehire.review_max_months` ahead (default 24). On the review date HR gets a task to renew, change or lift the status. Until HR acts, the status stays as it is.

Recruiters, hiring managers and the recruitment module see only `core.rehire_signal()`: "check with HR" or nothing. They never see the status, the reason or the note.

### 3.5 One employee number per person

The employee number belongs to the person (`core.person.employee_number`), is given once and never changes or gets reused (`EMPLOYEE_NUMBER_IMMUTABLE`). It is generated from the organization's format (`employee_number.format`) by `core.next_employee_number()`, skipping any number already in use, when the person's first employment is created.

`core.employment.employee_number` becomes a legacy, employer-specific number. When the data migration loads a person whose employment already has a number, that number becomes the person's number if the person has none yet. Numbers from other employers or other systems (a library board's own numbers, an old payroll system's IDs) are kept as codes in a code scheme with `purpose = identifier` on the person or the assignment (`docs/18` §3), so they can still be searched and exported.

Exports to banks, carriers and government files use the number each receiver expects: the person's number by default, or the code from a named scheme where a receiver needs the employer-specific one (`docs/11`).

### 3.6 Service on rehire

When a person is rehired, the agreement or policy rule that covers the new position proposes which prior service counts for seniority, vacation, benefits and notice, and why (`rule_source`). HR confirms or changes the proposal in the rehire change set, with a reason for any change (`rehire.service_bridging = propose_hr_confirms`). An organization can let the rule apply on its own (`apply_rule`), in which case the proposal is applied and recorded the same way.

### 3.7 People in several positions

Nothing in the review changes `docs/17` §4 or `docs/20`. `requirements/01` now restates them: assignment types, which position governs which domain, ending one position while others continue, and positions with two managers.

---

## 4. Organization structure and reporting lines

Tenant-defined levels, several hierarchies and typed relationships with an authority matrix (`docs/17` §3 and §5) replace the fixed level table and the solid and dotted lines in `requirements/01`.

### 4.1 A vacant manager position

When a request's approver is the holder of a position that is vacant on the date, and no acting manager or delegate is named, the routing service sends it to the nearest filled position above (`core.next_filled_position_up()`), and HR gets a task to name an acting manager (`approvals.vacant_manager`). A position counts as filled when someone holds it actively, on leave, or in an acting assignment. The routing records `routed_by = vacant_manager` so the approver can see why it reached them. This applies to every capability: leave, time, overtime, expenses, availability and change sets.

### 4.2 Unit heads

Each org unit names its head position (`org_unit_version.head_position_id`, now a foreign key to `core.position`), with dates like every other unit attribute. The head is used by approval chains that go "to the head of the unit", by the `first_excluded_head` grouping (`docs/17` §3.4) and by reports.

`core.org_units_without_head(as_of)` lists management units that have no head, or whose head position is not active, on a date. With `org.unit_without_head = warn` (default) the reorganization preview and the data quality dashboard show them; with `block`, a change set that leaves a unit without a head is refused (`UNIT_HEAD_REQUIRED`).

### 4.3 What employees see on the org chart

By default employees see filled positions as of today, with directory fields only (`org_chart.employee_view`). Vacant positions, change badges ("Leaving 13 Nov", "Moving", "Starting") and future dates are shown to managers for their own area and to HR (`org_chart.manager_view`). An organization can show more to everyone, for example vacancies to encourage internal applications. Badges about a person always follow §7.3: a badge appears only once the change has been communicated to that person, whoever views the chart. Confidential positions stay hidden as in `docs/04` §6.

### 4.4 Reporting across employers

A position can report to a position of another employer of record, and a typed relationship can link two employers' staff, only while a shared-services arrangement between the two employers is recorded (`core.shared_services_arrangement`). The arrangement names the serving employer, the served employer, its purposes (supervision, HR services, payroll services), its privacy basis and its agreement document. The database refuses a cross-employer line or relationship without one (`CROSS_EMPLOYER_NO_ARRANGEMENT`); an HR business partner needs `hr_services`, every other relationship except mentoring needs `supervision`.

Under an arrangement, a manager from the serving employer sees the served employer's staff through the work field class only (job, schedule, time, leave dates), never personal, pay, restricted or self-identification fields, unless the arrangement's purposes and the role grant both cover more. When an arrangement ends, the cascade proposes ending or moving the reporting lines that depend on it, with a task for HR from 30 days before.

This is a locked setting: the requirement for an arrangement is a privacy limit.

---

## 5. Positions and position control

### 5.1 Positions for everyone

Light mode is removed. Every assignment fills a position (validation `POSITION_REQUIRED`), and the line manager always comes from the position tree; `assignment_version.manager_assignment_id` is no longer used (`DIRECT_MANAGER_NOT_USED`). Acting managers and delegates are typed relationships. `platform.tenant.org_mode` can only be `position`, and migration 0007 refuses to run while a light-mode tenant exists.

How positions come into being is a setting, `positions.management`, per organization or legal entity:

| Value | What happens | Position control |
| --- | --- | --- |
| `managed` (default) | HR creates and approves positions; requisitions and hires fill them | On: FTE, budget, complement and funding checks |
| `automatic` | At hire, HR picks the manager; CanDo creates the position under the manager's position, from the job chosen, with `core.position.origin = auto_at_hire` | Off |

A small organization on `automatic` never has to think about positions; the org chart, approvals and costing still work because the positions exist. When it switches to `managed`, the automatic positions are already there: a review list shows every position with `origin = auto_at_hire` and no `reviewed_at`, so HR can merge, rename, budget or approve them, and position control starts from the switch date.

Any tenant that used light mode before 0007 is converted by the data migration in Step 1: one position per assignment, under the manager's position, with `origin = data_migration`.

### 5.2 Over budget or over the approved complement

When a hire, transfer, FTE change or new position fails a position control check, the change set is not refused outright. By default (`positions.over_budget` and `positions.over_complement` set to `finance_approval`) it gets a finance approval step and a `core.position_control_override` row with the check that failed, the amount or FTE over, and a written reason of at least ten characters. Finance approves or rejects, never the requester (`SELF_APPROVAL`). Every override is listed in the position control report.

An organization whose complement is approved by council or a board can set `over_complement` (or `over_budget`) to `hard_stop`, for the whole organization or one legal entity; the change set is then refused until the budget or complement is changed through its own approval (`docs/17` §3.5).

### 5.3 The pay grade comes from the job

A position has no grade of its own. Its grade is its job's grade, so job evaluation, pay equity and salary ranges all work from one source. A position that needs a different grade needs a different job: create a new job (or move the position to an existing one) through a change set.

Position-specific evaluations (`docs/19` §5.4) remain possible as evidence. If one lands in a different grade band from the job's grade, CanDo raises `POSITION_GRADE_DIFFERS` and proposes a new job for that position; it never sets a grade on the position.

The bargaining unit stays on the position, defaulting from the job, because the same job can sit in two units (a city's and its parks board's, for example).

---

## 6. Jobs, codes and requirements

### 6.1 NOC is recommended, not required

The NOC template in `rules/classifications/schemes.json` no longer makes NOC required on jobs: `required_on` defaults to empty. Instead `codes.warn_when_missing` (default: NOC on jobs) shows a warning on a job without a NOC code, and every feature that uses NOC says the job is not coded rather than failing quietly:

- requirement proposals (`docs/18` §6.3) are not offered;
- the similarity score leaves out the occupation component and shows `NO_OCCUPATION_CODE`;
- employment equity occupational groups and public wage data are not available for that job, and reports list the job under "not coded".

An organization can make NOC, or any other scheme, required (`core.code_scheme.required_on`), or switch the warning off.

### 6.2 Starter job catalogues and other coding schemes

At setup an organization chooses to start from a CanDo sector catalogue (non-profit, First Nation government, municipal; more as they are built), to load its own file, or to start empty. A sector catalogue is copied into the organization's own jobs, with NOC codes, job families and proposed requirements, and is then the organization's to edit; later updates to CanDo's catalogue are offered, never applied. Required requirements still need the organization's own rationale.

NOC is not a must: an organization can classify jobs with its own scheme, a funder's or another country's (`docs/18` §3), and use NOC only where a government program requires it. CanDo keeps NOC current, including NOC 2026 (`docs/18` §8).

### 6.3 Job descriptions: drafted from NOC, never by AI

This is a product rule from the owner, not a setting: CanDo does not use AI to draft or rewrite job descriptions, now or later, because each organization's descriptions are its own. The one exception (owner, 25 Oct 2026): CanDo's paid translation service may use AI to translate a job description into the other language; it never changes what it says (`docs/22` §4.6).

A job description draft is assembled from the job's NOC unit group (lead statement and main duties, with the matching sub-group) and the job's active requirements, in a fixed template, and is clearly marked as a draft. HR edits it freely, writes its own, or uploads one. The inclusive-language check stays, as a rule-based check with word lists, never a model. The assistant (`docs/12`) has no job description tool, and its coding suggestions (`docs/18` §2.6) never write description text.

### 6.4 Several titles per position

A position keeps its job's title as its official title for pay, pay equity, job evaluation, reports and government forms. It can also carry, in `core.position_title`, effective-dated titles for other purposes:

| Purpose | Example | Rule |
| --- | --- | --- |
| `working` | Youth Program Coordinator, North | One at a time; shown on the org chart, directory and profile |
| `funder` | Youth Program Supervisor (the title a provincial grant requires) | One per funder at a time; names the funding source |
| `posting` | Title used in job postings | One at a time |
| `legacy` | Title from the previous system | For search and history |
| `other` | A ministry contract's title | Needs a label saying what it is for |

`core.position_title_for(position, purpose, as_of, funding_source, lang)` returns the title for a purpose, falling back to the working title and then the job's title. Every screen, posting, export and report states which title it uses; funder reports (`docs/17` §8.11) use that funder's title. `position_version.title_override_en/_fr` become read-only and are migrated into working titles.

---

## 7. Changes and approvals

### 7.1 Back-dated changes

When a change set's effective date falls in a pay period that is already finalized (`reaches_finalized_pay`, set by validation), it needs, by default:

- one HR approval and one payroll approval;
- two HR approvals from different people, plus payroll, when the effective date is more than one month before the request (`secondHrApprovalOlderThan`).

Approvers see the retro estimate before approving (`docs/03` §4). Approvals count only from people other than the requester. The database refuses to approve, schedule or commit a change set without them (`APPROVALS_MISSING`), including a change set inserted already approved. Imports at go-live (`source = import`) follow their own sign-off (`docs/17` §10).

Once approved, retro is calculated automatically however far back it goes (`docs/06` §6, `docs/17` §11.6): everything that depends on the changed value is recalculated by the payroll rules for each affected period, including overtime and premiums on the new rate, income tax, CPP, CPP2, EI, pension contributions and pension adjustments, salary-based benefits and their taxable benefits, vacation pay, costing and the GL. Retro that comes from a ratified agreement follows the agreement's own activation (§8), not this approval route.

### 7.2 Overpayments are never deducted automatically

When retro or a correction produces a negative difference, payroll does not deduct it. The retro request ends as `overpayment_held` and a `payroll.overpayment` row records the gross and net amounts. Recovery needs, by default (`payroll.overpayment_recovery = employee_authorization`):

- the employee's written authorization as a document, with its date;
- a repayment schedule.

Only then can recovery items be created (`OVERPAYMENT_NOT_AUTHORIZED` otherwise). HR can also waive the overpayment, with a reason, or record a dispute.

An organization can choose `jurisdiction_rule_allows`; recovery without the employee's authorization is then possible only where the jurisdiction's `overpayment_recovery` rule (or the collective agreement, or a court order) is verified to allow it, citing the rule (`OVERPAYMENT_NEEDS_AUTHORIZATION` otherwise). Every jurisdiction is `verify_at_load` except Ontario, where the statute requires a written authorization for a specific amount or formula (`rules/employment-standards/ca-2026-core-hr-additions.json`).

### 7.3 "Communicated" changes

An employee sees an approved change about them on their own profile (and in badges about them on the org chart) only once HR or the manager marks it communicated: `change_set.communicated_at`, `communicated_by` and the method (in person, video, phone, letter, email, other). The change can be marked communicated only after approval. Changes the employee asked for themselves are always visible to them.

`platform.employee_sees_change()` applies the setting `self_service.show_changes`: when communicated (default), when approved, or from the effective date. The manager's and HR's views are unaffected. The communication date is kept for the record, for example when the notice period of a termination is disputed.

### 7.4 Changes that always need HR

Whatever an organization's workflow, these need an approval with the HR capability (`approval_task.capability = hr`) from someone other than the requester:

- terminations (reason category or change set kind `termination`);
- demotions;
- any change linked to a leave request or to an accommodation or return-to-work case (`linked_leave_request_id`, `linked_case_id`).

"HR" means whoever holds a role with the HR approval capability; in a small organization that may be the executive director. The list is the locked setting `approvals.hr_required`, enforced by the database.

### 7.5 Other approval defaults

- **`any` decisions are final.** When either of two managers can decide, the first decision stands; the employee resubmits if needed (closes `docs/16` Q33 and `docs/20` SP1).
- **Escalation.** An approval part or task not decided within `approvals.escalate_after_working_days` (default 3) also goes to the approver's own manager (closes Q34 and SP2).
- **Change reasons** are each organization's own list (`core.change_reason`), each mapped to a fixed category (hire, rehire, probation, status conversion, promotion, demotion, lateral transfer, reclassification, reorganization, pay change, hours change, leave, acting, assignment end, termination, correction, data update, other). Rules, reports and the HR list in §7.4 use the category; the change set copies it (`reason_category`).

---

## 8. Collective agreements

### 8.1 Agreements and employment standards law

The general rule: where an agreement and the employment standards law differ, the agreement applies, as long as the jurisdiction's law lets an agreement replace that part of the law. Where the law does not allow it, CanDo pays the law's minimum even when the agreement's own rule is lower.

What an agreement may replace is data, per jurisdiction, in the employment standards key `agreement_may_replace` (`rules/employment-standards/ca-2026-core-hr-additions.json`):

- **British Columbia:** hours of work and overtime (except averaging agreements), statutory holidays (except the National Day for Truth and Reconciliation), annual vacation, special clothing, and seniority retention, recall, termination and layoff, when the agreement's provisions on the matter meet or exceed the Act's; minimum wage and several other sections always apply (ESA s. 3). Marked `secondary` until counsel confirms.
- **Ontario:** no standard can be contracted out of; an agreement's provision applies instead of a standard only when it gives a greater right or benefit on the same subject (ESA 2000 s. 5). Marked `secondary`.
- **Every other jurisdiction:** `verify_at_load`.

When an agreement version is verified (`docs/08` §4), the verifier compares it with the law for every jurisdiction it covers and records a finding per standard in `core.agreement_standards_finding`:

| Finding | Meaning | Before activation |
| --- | --- | --- |
| `meets_or_exceeds` | The agreement gives at least the law | Nothing |
| `below_law_replaceable` | The agreement gives less, in a part the law lets it replace | Approval by the HR administrator **and** the payroll administrator, two different people (`AGREEMENT_BELOW_LAW_NOT_APPROVED`, `two_people_approve`) |
| `below_law_not_replaceable` | The agreement gives less, in a part the law does not let it replace | Nothing to approve: CanDo pays the law's minimum; the finding is shown to both administrators |
| `not_verified` | The jurisdiction's rule is still `verify_at_load` | Activation refused (`RULE_NOT_VERIFIED`) |

Both administrators see every finding as a warning on the agreement and in their task lists. The comparison method is a setting of each agreement version (`standardsComparison.method`): `per_hour` (default: no hour is ever paid below the law) or `whole_standard` (the statute's greater-right test over the standard as a whole), which needs the name and date of the labour counsel who confirmed it. This closes `docs/16` Q9.

Standard codes used by findings: `minimum_wage`, `overtime.daily`, `overtime.weekly`, `overtime.rate`, `hours.rest`, `statutory_holiday.entitlement`, `statutory_holiday.pay`, `vacation.entitlement`, `vacation.pay`, `leave.<type>`, `notice.termination`, `notice.layoff`, `severance`, `seniority.recall`, `special_clothing`.

### 8.2 Who sets agreements up

An agreement is first set up in CanDo by CanDo's implementation team or a certified partner, as a setup service: grids, rules, scopes and premiums are entered from the agreement, and the customer verifies and activates it (`agreement_version.prepared_by = cando | partner`). After that, the customer's HR can amend and update the agreement through CanDo's screens without coming back to CanDo (`agreements.customer_can_amend`, default on; `prepared_by = customer`). Every version, whoever prepared it, goes through the same verification, findings and two-person activation (`docs/08` §4).

### 8.3 Seniority and the agreement library

Seniority by date, by hours and by points is supported from launch (`docs/17` §11.3). The agreement library structure, rules scoped to sub-groups and unit transfers are as in `docs/17` §11; `requirements/01` now says so.

---

## 9. Self-service, security and privacy

### 9.1 Bank account changes

Changing where pay goes (a new account, a changed account or an added split) is a `payroll.bank_change_request`:

1. **Second factor.** In self-service the employee signs in again with their second factor at the moment of the change (`self_service_needs_second_factor`).
2. **Notices.** A notice goes at once to the email and phone already on file (not the ones in the request), saying a change was requested and how to stop it.
3. **Hold.** Pay can go to the new account only after `bank_change.hold_hours` (default 72) from the request (`BANK_CHANGE_ON_HOLD`). A pay run inside the hold uses the previous account.
4. **Live check by HR** (`bank_change.hr_live_verification`, default on). HR approves only after speaking with the employee by video call or by phone, confirming the employee made the request, and seeing government photo ID on camera. By phone, HR calls the number already on file, never one given with the request (`BANK_CHANGE_PHONE_NOT_ON_FILE`). CanDo records who verified, how, when and the type of ID seen; it never stores an image or number of the ID. The verifier cannot be the requester.

An organization can switch off the live check; the second factor, notices and hold stay. Payment files use an account only when its change is in effect (`payroll.bank_account_usable()`).

### 9.2 Self-identification categories

`core.self_id_category` is a library of categories each organization switches on, rewords, switches off or adds to. CanDo ships standard categories:

- the four employment equity designated groups (women, Indigenous peoples, persons with disabilities, members of visible minorities);
- First Nations, Métis and Inuit identity;
- Black identity;
- 2SLGBTQI+ identity;
- gender identity.

Each category has its question, its purpose statement in English and French, its answer options (always including "prefer not to answer"), and its own consent (`core.self_id_consent`), which the employee can withdraw at any time. Answers stay encrypted in `core.self_identification`.

Government reports (federal employment equity, for example) read only CanDo standard categories mapped to an official group (`official_group`); an organization's own categories appear only in its own reports. Rewording a standard category that feeds a government report raises a warning that the report may no longer be comparable. All reporting uses small-group suppression (Module 12).

### 9.3 OCAP® for First Nation customers

OCAP® (ownership, control, access and possession) is a registered trademark of the First Nations Information Governance Centre. When a First Nation government uses CanDo, the data about its people belongs to the Nation. At setup the Nation chooses how far CanDo goes on possession (`platform.tenant.data_isolation`):

| Option | Where the data is | Price |
| --- | --- | --- |
| `shared` with OCAP® controls (standard) | CanDo's shared database in Canada, kept apart by row-level security | Standard |
| `dedicated` | The Nation's own Supabase project in Canada (`docs/16` Q17) | Paid option |

With OCAP® controls on (`platform.tenant.ocap_controls`), in both options:

- CanDo staff can see the Nation's data only under a `platform.support_access_grant`: requested by a named CanDo person, with a purpose, approved by a user of the Nation, for at most seven days (`support.access_requires_approval`, on for every customer by default and always on for OCAP® tenants);
- the Nation sees every access to its data in the audit log and its daily digest (`docs/10` §5);
- the Nation can export all its data at any time in open formats, and on leaving CanDo its data is returned and then destroyed, with a destruction certificate;
- community membership is recorded only where the employer needs it and with consent (`requirements/01` public-sector structures).

### 9.4 Channels, sign-in and history

- **Mobile** is an installable web app (`docs/13` §5), not an app-store app; "mobile app" in the requirements means this.
- **Single sign-on and provisioning** at launch: Microsoft Entra ID and Okta (closes the `requirements/01` question; `docs/16` Q3 decided). Google Workspace later.
- **History:** every effective-dated record is bi-temporal (`docs/03`), as already designed.

---

## 10. Data model (migration 0007)

| Table or change | Purpose |
| --- | --- |
| `platform.setting_definition`, `platform.tenant_setting`, `platform.setting()` | Settings catalogue, an organization's values by scope and date, the value in force |
| `core.assignment_version.employment_type`, `core.employment_status_type()` | Employment type per position; status worked out |
| `core.probation` | Agreement, employer and trial probations with measures, counters and outcomes |
| `core.rehire_reason`, `core.rehire_eligibility`, `core.rehire_signal()` | Rehire status kept by HR; recruiters' signal |
| `core.person.employee_number`, `core.employee_number_counter`, `core.next_employee_number()` | One number per person, generated once, immutable |
| `platform.tenant.org_mode` (position only), `core.position.origin`, `reviewed_at`, `reviewed_by` | Light mode removed; automatic positions and their review |
| `core.position_control_override` | Over-budget and over-complement approvals with reasons |
| `org_unit_version.head_position_id` foreign key, `core.org_units_without_head()`, `core.next_filled_position_up()` | Unit heads; routing past vacant positions |
| `core.shared_services_arrangement`, `core.has_shared_services()`, `core.position_legal_entity()` | Reporting across employers |
| `core.position_title`, `core.position_title_for()` | Titles per purpose |
| `core.change_reason`, `change_set.reason_category`, `linked_case_id`, `linked_leave_request_id`, `reaches_finalized_pay`, `communicated_*`, `approval_task.capability`, `platform.required_approvals()`, `platform.employee_sees_change()` | Change reasons, required approvals, communicated changes |
| `payroll.overpayment`, `retro_request` status `overpayment_held`, `one_time_item.overpayment_id` | Overpayments held until recovery is authorized |
| `core.agreement_version.prepared_by`, `core.agreement_standards_finding` | Who prepared a version; findings against the law and their approvals |
| `payroll.bank_change_request`, `payroll.bank_account_usable()` | Bank account changes |
| `core.self_id_category`, `core.self_id_consent` | Self-identification library and consent per category |
| `platform.tenant.data_isolation`, `ocap_controls`, `platform.support_access_grant` | OCAP® options and support access |

Read-only after 0007, kept for the data migration: `employment_version.employment_type`, `probation_end` and `rehire_eligible`; `employment.employee_number`; `position_version.title_override_en/_fr`; `assignment_version.manager_assignment_id`. Every new tenant table has `tenant_id` with forced row-level security; `platform.tenant` stays outside tenant RLS.

The migration was loaded on PostgreSQL 16 on top of the initial schema and the parts of 0003 it depends on; its smoke test (19 check groups) passes. It alters no table that 0004, 0005 or 0006 alters, except new columns on `core.assignment_version`. It is designed so that the fixtures of the earlier smoke tests stay valid: employee numbers are assigned, not demanded; cross-employer checks apply only when both employers are known from org unit versions; `POSITION_REQUIRED` and `DIRECT_MANAGER_NOT_USED` are change-set validations. Step 1 runs all seven migrations and every smoke test together for the first time.

---

## 11. Operations, validation, API and events

**Change set operations** (added to `docs/03` §4):

- `setting.set`, `setting.end`;
- `probation.start`, `probation.extend`, `probation.record_outcome`;
- `rehire_eligibility.set`, `rehire_reason.*`;
- `position.mark_reviewed`;
- `position_title.set`, `position_title.end`;
- `shared_services_arrangement.set`, `shared_services_arrangement.end`;
- `change_set.mark_communicated` (a workflow action on an approved change set, audited);
- `overpayment.request_authorization`, `overpayment.authorize`, `overpayment.waive`;
- `change_reason.*`, `self_id_category.*`.

**Validation** (added to `docs/03` §6):

- `POSITION_REQUIRED`, `DIRECT_MANAGER_NOT_USED`, `EMPLOYMENT_TYPE_REQUIRED` on every new assignment version;
- position control with `positions.over_budget` and `over_complement` (§5.2), creating the override row and the finance step;
- `UNIT_HEAD_REQUIRED` when `org.unit_without_head = block`;
- `POSITION_GRADE_DIFFERS` when an approved position-specific evaluation lands outside the job's grade band;
- `reaches_finalized_pay` set from the pay periods; the retro estimate shown;
- the database checks listed in §10 surface with their codes.

**API:** settings (`GET /settings`, `GET /settings/{key}?asOf=&legalEntityId=`, writes through `POST /change-sets`), probations, rehire status (HR) and signal (recruiting), position titles, shared-services arrangements, overpayments, agreement findings with approve actions for HR and payroll, bank change requests with verify, approve and cancel actions, self-identification categories and consent, support access grants. The paths are added to `api/openapi.yaml` in Steps 3, 4, 5, 7, 10, 12 and 18 with the features.

**Events:** `setting.changed`, `probation.started`, `probation.outcome_recorded`, `rehire_eligibility.changed` (HR subscribers only; no reason in the payload), `position.auto_created`, `shared_services_arrangement.ending`, `change_set.communicated`, `overpayment.held`, `overpayment.authorized`, `agreement.finding_recorded`, `agreement.finding_approved`, `bank_change.requested` (notices), `bank_change.in_effect`, `support_access.requested`, `support_access.approved`. Payloads carry identifiers only (AGENTS rule 9).

---

## 12. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| HR-001 | Organization sets over-budget to hard stop; its library board keeps finance approval | Each employer gets its own value as of the date | smoke 2a–b | 1 |
| HR-002 | Organization tries to switch off no self-approval | Refused, `SETTING_LOCKED` | smoke 2c | 1 |
| HR-003 | Jordan: permanent A1 from 2026, casual A2 from 2025 | Casual before 2026, permanent after; organization's own order applies | smoke 4 | 5 |
| HR-004 | Probation in two units at once; a second one in the same unit | Both allowed; second in the same unit refused | smoke 5 | 5 |
| HR-005 | Part-time probation of 624 paid hours with a parental leave inside it | Counter excludes the leave hours as the agreement says; probation passes on the right date | — | 7, 11 |
| HR-006 | Trial period on promotion fails | Outcome `returned` with reason; return change set proposed | — | 5 |
| HR-007 | HR restricts rehire with a reason and a 12-month review | Recruiter sees "check with HR" only; HR task on the review date | smoke 6 | 5, 14 |
| HR-008 | Rehire reason "left on medical leave" | No such category exists | smoke 6e | 1 |
| HR-009 | Person with a legacy number hired by a second employer | Keeps one number; the second employer's number kept as a code | smoke 3 | 5, 9 |
| HR-010 | Manager position vacant; staff leave request | Routed to the head two levels up; HR task to name an acting manager | smoke 8 | 4, 11 |
| HR-011 | Reorganization leaves a unit without a head | Warning (default) or refusal (`block`) | smoke 9 | 5 |
| HR-012 | Employee views the org chart | Filled positions as of today; no vacancies, badges or future dates by default | — | 5 |
| HR-013 | Library position reports to a City director | Refused without an arrangement; allowed with one; director sees work fields only | smoke 10 | 1, 3 |
| HR-014 | Small organization on `automatic` hires its first employee | Position created under the manager's position, `origin = auto_at_hire` | — | 5 |
| HR-015 | It switches to `managed` | Review list of automatic positions; control applies from the switch date | — | 5 |
| HR-016 | Hire over budget | Finance step and override with reason; requester cannot approve | smoke 11 | 5, 14 |
| HR-017 | Same hire with `hard_stop` on the legal entity | Refused until the budget changes | — | 5 |
| HR-018 | Position-specific evaluation lands in a higher band | `POSITION_GRADE_DIFFERS`; new job proposed; no grade on the position | — | 15 |
| HR-019 | Job without NOC | Warning; similarity without occupation; reports list it as not coded | — | 5 |
| HR-020 | Organization starts from the non-profit catalogue | Jobs copied with NOC and proposed requirements; required items need the organization's rationale | — | 5 |
| HR-021 | Draft a job description | Built from NOC duties and requirements in the template; no assistant tool exists for it | — | 5, 19 |
| HR-022 | Position with a funder's title | Funder report uses it; directory uses the working title; payroll and pay equity use the job title | smoke 12 | 5, 12 |
| HR-023 | Promotion back-dated four months into paid periods | Needs two HR approvals and payroll; then retro recalculates overtime, taxes, CPP, EI, pension and costing for every period | smoke 13d–e | 4, 10 |
| HR-024 | Correction produces an overpayment of $312.50 | Held; no deduction until written authorization and schedule are recorded | smoke 14 | 10 |
| HR-025 | Termination approved but not yet communicated | Employee does not see it; badge hidden; visible once marked communicated | smoke 13h–i | 4, 5 |
| HR-026 | Manager submits a termination; workflow has no HR step | Refused, `APPROVALS_MISSING` | smoke 13a | 4 |
| HR-027 | BC agreement with overtime below the Act's daily standard | Finding `below_law_replaceable`; activation waits for HR and payroll, two people | smoke 15 | 7 |
| HR-028 | Same agreement pays less than minimum wage on one step | Finding `below_law_not_replaceable`; CanDo pays minimum wage | — | 7, 9 |
| HR-029 | Agreement covering a jurisdiction still `verify_at_load` | Activation refused, `RULE_NOT_VERIFIED` | smoke 15e | 7 |
| HR-030 | Customer HR amends a CanDo-prepared agreement | New version, `prepared_by = customer`, same verification and activation | — | 7 |
| HR-031 | Employee changes bank account in self-service | Second factor; notices to contacts on file; HR live check with photo ID; pay goes there after 72 hours | smoke 16 | 12 |
| HR-032 | HR calls the number given in the request | Refused, `BANK_CHANGE_PHONE_NOT_ON_FILE` | smoke 16e | 12 |
| HR-033 | Organization adds its own self-ID category | Allowed, with purpose, consent and a decline option; not in government reports | smoke 17 | 18 |
| HR-034 | CanDo support needs to look at a Nation's data | Grant requested, approved by the Nation, at most seven days, visible in its audit log | smoke 18 | 3 |
| HR-035 | Another tenant reads settings, rehire status or titles | Sees none; gets CanDo's defaults | smoke 19 | 1 |

---

## 13. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/01` | Rewritten to these decisions and to `docs/17`, `18` and `20` |
| `requirements/02` | Probation and status conversion per §3.2 and §3.1; rehire signal only (§3.4); posting titles (§6.4); requisitions over budget follow §5.2; no AI drafting of job descriptions or postings from job descriptions (§6.3) |
| `requirements/03` | Retro and overpayments per §7.1–§7.2; bank account changes per §9.1; employee number per §3.5 |
| `requirements/06` | Vacant manager routing (§4.1); escalation default (§7.5) |
| `requirements/11` | Terminations always need HR (§7.4); communicated date (§7.3); rehire status set at separation (§3.4); assignment end versus termination unchanged (`docs/17` §4.4) |
| `requirements/12` | Self-ID reporting per §9.2; reports state which title they use (§6.4) |
| `requirements/13` | Pay equity predominance with recorded basis (§3.3); agreement findings and dual approval (§8.1); agreement setup and amendments (§8.2); OCAP® (§9.3) |
| `docs/03` §4–§6 | Operations and validation in §11; `Two org modes` withdrawn; Assignment gains `employment_type`; Employment loses `employment_type` as a stored fact |
| `docs/04` §1, §2, §6 | Light-mode line and light-mode drag action withdrawn; employee view and badges per §4.3 and §7.3 |
| `docs/06` §6 | Negative retro differences become held overpayments (§7.2) |
| `docs/08` §2, §4, §5 | Greater right per §8.1 with findings and `standardsComparison`; `prepared_by` |
| `docs/10` | Field classes: rehire status HR-only, signal for recruiting; cross-employer work-field access (§4.4); support access grants (§9.3); bank change verification (§9.1) |
| `docs/12` | No job description drafting tool, now or later (§6.3) |
| `docs/13` | Admin → Settings; profile "communicated" action; bank change verification screen; automatic position review list |
| `docs/16` | Q3, Q9, Q33 and Q34 closed; new questions from §14 |
| `docs/17` §4.3 | "Probation and trial periods" row replaced by §3.2; §5.1 "explicit in light mode" withdrawn; §7.1 greater right per §8.1 |
| `docs/18` §3.4 and `schemes.json` | NOC template `required_on` empty; warning via `codes.warn_when_missing` (§6.1); `NO_OCCUPATION_CODE` reason; no AI ranking writes description text |
| `docs/19` §5.4, §5.6 | Position-specific evaluations never set a grade (§5.3); predominance basis (§3.3) |
| `docs/20` | SP1 and SP2 closed (§7.5) |
| `AGENTS.md` | Reading order item; rules 39 to 42; Step 1 migration 0007 and its smoke test |
| `rules/agreements/agreement.schema.json` | `standardsComparison` and `preparedBy`, added in Step 7 from the additions file |
| `rules/employment-standards/ca-2026.json` | `agreement_may_replace` and `overpayment_recovery` merged in Step 7 from the additions file |

Where a listed document still says otherwise, this document wins (precedence above).

---

## 14. Open questions

| # | Question | Default until decided |
| --- | --- | --- |
| H1 | Price of the dedicated-database option for First Nation customers | Quoted per customer by sales; shared with OCAP® controls is the standard price |
| H2 | Default non-union probation length | 3 calendar months, extendable; each organization sets its own |
| H3 | Bank change hold length | 72 hours; each organization can change it |
| H4 | Employee number format | No prefix, 6 digits |
| H5 | Overpayment recovery and what agreements may replace, per jurisdiction | British Columbia and Ontario `secondary`, the rest `verify_at_load`; employment counsel before Step 7 |
| H6 | Wording of CanDo's standard self-identification categories | Draft wording reviewed with equity and Indigenous advisers before Step 18 |
| H7 | Which sector starter catalogues first | Non-profit, then First Nation government, then municipal |

---

## Sources

- British Columbia, Employment Standards Act, Part 1 section 3, Interpretation Guidelines Manual: https://www2.gov.bc.ca/gov/content/employment-business/employment-standards-advice/employment-standards/forms-resources/igm/esa-part-1-section-3
- British Columbia, Unionized workplaces: https://www2.gov.bc.ca/gov/content/employment-business/employment-standards-advice/employment-standards/do-employment-standards-apply-to-you/unionized-workplaces
- Ontario, Employment Standards Act, 2000 (s. 5 no contracting out and greater right; s. 13 deductions): https://www.ontario.ca/laws/statute/00e41
- First Nations Information Governance Centre, The First Nations Principles of OCAP®: https://fnigc.ca/ocap-training/
