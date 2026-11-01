# 29 · Learning and development decisions

Oct 28, 2026 · @Wael

This document records the owner's review of Module 08 (Learning & Development) and turns each decision into something the build can follow: a setting with its default, a database check, a rule the organization sets, a route it edits, a caution, or a screen behaviour. The review went round by round; the working record is `claude/review/08-learning-development-decisions.md` in the project.

It covers how courses are delivered, ready-made courses, the training the law requires, AI, training rules and their events, reminders and escalation, refresher cycles, changes in the law, credentials and their verification, continuing education, apprenticeships, readiness for a shift, skills and consent, development plans, training time and pay, training requests, CRA's taxable benefit test, tuition repayment, budgets, grants, Quebec's 1% rule, mentoring, records, council and board members, collective agreements, who sees what and course languages.

**Precedence.** On these topics this document wins over `requirements/08` and the LRN stories in `stories/07-to-10-talent.md`. `docs/18` §6 still governs requirements on jobs and positions, `docs/19` §4 the competency model and gaps, `docs/23` §6 onboarding plans, `docs/27` scheduling, and `docs/22` still wins on values, defaults, languages and fallbacks. §15 lists every place that changes. The schema is `schema/0015_learning_decisions.sql` (migration 0015, Step 1), checked by `tests/schema/schema_0015_smoke.sql`. The training the law requires is in `rules/learning/ca-2026-training-requirements.json`.

**The owner's rules for this module.**

1. Every decision is a default each organization can change at setup or later; only legal floors and safety rules are fixed. CanDo pre-fills its suggested numbers at setup, and the organization keeps or changes them (Q46).
2. CanDo keeps the record; courses run elsewhere. CanDo is integration-first: it holds assignments, completions, credentials and plans, and links to the customer's LMS, a partner library or free government courses. It has no course player or authoring tool.
3. The law is the floor. CanDo loads the training the law requires; an organization can be stricter, never looser. A licence the law requires stops the work with no override.
4. No AI in learning. Suggestions come from fixed rules, each with its reason shown; people decide.

---

## 1. Decisions at a glance

| # | Decision | Setting or rule | Section |
| --- | --- | --- | --- |
| R1.1 | Integration-first: CanDo keeps the record, assignments, compliance and credentials; courses run in the customer's LMS or the provider's platform (SCORM, xAPI, LTI or the provider's API); no course player or authoring. CanDo still records classroom and virtual attendance, on-the-job sign-offs, policy acknowledgements and external certificates | `talent.learning_item`, `talent.learning_completion` | §3.1 |
| R1.2 | No ready-made CanDo courses: free government courses linked; licensed bilingual libraries through a partner | Q50 | §3.2 |
| R1.3 | CanDo loads the training the law requires by province and sector; an organization can be stricter, never looser, and adds its own rules | `ref.training_requirement`; `TRAINING_RULE_LOOSER_THAN_LAW` | §3.3 |
| R1.4 | No AI in learning; rule-based suggestions with their reason are allowed | Product rule | §3.4 |
| R2.1 | Training required before certain work stops scheduling the person for it, unless someone acknowledges a caution with a reason | Caution `learning.not_ready_for_work` | §6 |
| R2.2 | Overdue mandatory training: employee reminded 14 and 3 days before, manager told 1 day after, HR 7 days after | `learning.overdue_escalation` | §4.4 |
| R2.3 | No grace period by default; an organization can add one to its own rules | `training_rule.grace_days` | §4.5 |
| R2.4 | A refresher done within 60 days before its due date keeps its cycle; earlier, the next one counts from the completion | `learning.refresher_early_window_days`: 60 | §4.5 |
| R2.5 | When the law adds or changes a requirement, current employees are assigned it on the effective date, due by the law's deadline, or within 30 days; HR is told | `learning.law_change_due_days`: 30 | §4.6 |
| R2.6 | The role's and location's training is assigned automatically on hire, job change, promotion, transfer to another location and return from a long leave | `learning.assignment_events` | §4.3 |
| R3.1 | An expired credential the law requires stops the work with no override; other credentials need a caution and a reason | `CREDENTIAL_REQUIRED_BY_LAW`; caution `learning.not_ready_for_work` | §6 |
| R3.2 | Expiry alerts: employee at 90, 60 and 30 days; manager and HR at 30 days and on the expiry date | `learning.credential_alert_days` | §5.2 |
| R3.3 | HR or a named delegate verifies each credential, with the method and date; pending until then | `talent.credential` | §5.3 |
| R3.4 | No registry integrations at launch; manual checks with a link to the registry | Step 17 | §5.4 |
| R3.5 | Apprenticeships basic at launch: hours by trade and level, technical training, the wage step; ratio checks later | `talent.apprenticeship` | §5.6 |
| R3.6 | Continuing education hours tracked against each licensing body's requirement, with reminders | `talent.ce_requirement` | §5.5 |
| R4.1 | Skills start from CanDo's Unified Competency Model; ESDC's Skills and Competencies Taxonomy is an optional add-on | Setup choice | §7.1 |
| R4.2 | The skills profile is seen for internal opportunities only after the employee opts in | `talent.skills_consent` | §7.2 |
| R4.3 | A development plan works like goals: proposed by either, agreed by both, every change kept | `talent.development_plan` (`PLAN_NOT_AGREED`) | §7.3 |
| R4.4 | The 70-20-10 mix is shown as guidance | `talent.development_mix()` | §7.3 |
| R5.1 | Mandatory training outside scheduled hours goes to the timesheet as training time and is always paid | `learning_completion.training_minutes` | §4.7 |
| R5.2 | Training requests go through the organization's route: the manager, and HR above an amount the organization sets | Route `training_request`; `learning.request_hr_above_amount` (chosen at setup) | §8.1 |
| R5.3 | Tuition repayment is the organization's decision: its own rules by kind of training and cost; what happens when no rule fits is also its choice | `talent.repayment_rule`; `learning.repayment_without_rule` (chosen at setup) | §8.3 |
| R5.4 | HR marks each paid training as mainly for the employer or the employee (CRA); the second is a taxable benefit | `training_request.primarily_for` | §8.2 |
| R6.1 | Budgets by department at launch, per employee optional; over budget needs a caution, a reason and finance through the route | `talent.training_budget`; caution `learning.over_budget` | §9.1 |
| R6.2 | Quebec's 1% rule: eligible spending recorded from launch; the report in phase 2 | `wsdrf_eligible` | §9.3 |
| R6.3 | Grant-funded training tracked at launch (basic): each program is a funding source with claims | `talent.grant_claim` | §9.2 |
| R7.1 | Mentoring basic at launch: HR or the manager pairs people, with rule-based suggestions; session logs and feedback | `talent.mentoring_pair` | §10.1 |
| R7.2 | Records kept at least as long as the law and regulators expect, longer if the organization chooses; inspection-ready export | `learning.records_keep_extra_years`: 0 | §10.2 |
| R7.3 | Council and board members' training tracked as non-employees | `learning_assignment.employment_id` empty | §10.3 |
| R7.4 | Learning rights in collective agreements read from the agreement library | Step 7 agreement fields | §10.5 |
| R7.5 | HR and a compliance role see training status across the organization; managers their teams; employees their own | Access rule | §10.4 |
| R7.6 | Courses assigned in the organization's main language; other versions on request | `learning_assignment.language` | §10.6 |

---

## 2. How the module is set up

### 2.1 Settings

| Setting | Decides | CanDo default | Set per |
| --- | --- | --- | --- |
| `learning.overdue_escalation` | Reminders before a mandatory training is due, then who is told when it is overdue | Employee 14 and 3 days before; manager 1 day after; HR 7 days after | Organization, employer |
| `learning.refresher_early_window_days` | How early a refresher can be done and keep its cycle | 60 days | Organization, employer |
| `learning.law_change_due_days` | Days to complete a new or changed legal requirement when the law gives no deadline | 30 days | Organization, employer |
| `learning.assignment_events` | Events on which a new training rule assigns training automatically | Hire, job change, promotion, transfer to another location, return from a long leave | Organization, employer; each rule can change its list |
| `learning.credential_alert_days` | Days before a credential expires when people are alerted | Employee 90, 60 and 30; manager and HR 30 and on the expiry date | Organization, employer |
| `learning.request_hr_above_amount` | Cost above which HR approves a training request as well as the manager | **None: chosen at setup** | Organization, employer |
| `learning.repayment_without_rule` | A paid request no repayment rule covers: HR decides, or no repayment | **None: chosen at setup** | Organization, employer |
| `learning.records_keep_extra_years` | Years records are kept beyond the law's longest period | 0 (the law's period) | Organization |

Pre-filled values follow the Q46 rule: the setup screen shows CanDo's suggestion and the organization keeps or changes it. The 60-day early window and the 30-day deadline are CanDo's suggestions, which the owner accepted.

### 2.2 Set up by each organization

| What | Where | Until it is set |
| --- | --- | --- |
| The HR amount for training requests and what happens when no repayment rule fits | The two settings chosen at setup (`docs/16`) | The request route and reimbursement stop with `SETTING_NOT_SET` |
| Tuition repayment rules, by kind of training and cost | `talent.repayment_rule` (§8.3) | The setup choice above applies |
| Training rules: who takes what, by when, how often | `talent.training_rule` (§4) | The law's requirements are listed for HR to turn into rules |
| The catalogue: courses in its LMS, the partner library, government courses, its own sessions and checklists | `talent.learning_item` (§3.1) | Rules cannot be written without a course |
| Credentials each position needs | Requirements on jobs and positions (`docs/18` §6) with the credential codes that satisfy them | Nothing is checked on shifts |
| Continuing education requirements and apprenticeships | `talent.ce_requirement`, `talent.apprenticeship` (§5) | Not tracked |
| Department training budgets | `talent.training_budget` (§9.1) | No budget check |

### 2.3 Routes

Two starter routes are copied to every organization for the subject `training_request`, and each organization edits them like any other route (`docs/23` §2.2):

| Route | Covers | Steps |
| --- | --- | --- |
| `training_request_hr` | A request above the organization's HR amount (`aboveHrAmount`) | The employee's manager; HR |
| `training_request` | Every other request | The employee's manager |

The route condition `aboveHrAmount` is new. An organization can also add finance for requests over budget (`overBudget`). No one approves their own request or a request about themselves (`SELF_APPROVAL`).

### 2.4 Cautions

| Caution | When | Section |
| --- | --- | --- |
| `learning.not_ready_for_work` | A shift is published to someone missing training required before the work, or a credential the organization (not the law) requires | §6 |
| `learning.over_budget` | A training request is approved for more than what is left in the budget | §9.1 |

Both always need a written reason.

---

## 3. Scope, content and AI

### 3.1 Integration-first (R1.1)

CanDo holds the learning record and runs no courses. Each catalogue item (`talent.learning_item`) says where the course runs: the customer's LMS, a partner library, a government site, an external provider, or internal (a classroom session, an on-the-job checklist, a policy to acknowledge). Items carry their standard (SCORM 1.2 or 2004, xAPI, cmi5, LTI, or the provider's API), the course id or link, the language versions, the duration, the credits and the version, so a completion shows which version was taken.

CanDo still records learning that happens outside any LMS (`talent.learning_completion.source`): attendance at classroom and virtual sessions (`talent.learning_session`, `talent.session_attendee`, with capacity and a waitlist; `SESSION_FULL`), on-the-job training signed off by a supervisor, never the learner (`SIGNOFF_REQUIRED`), policy acknowledgements, external courses with their certificate (`INPUT_REQUIRED` without it), and HR entries. Completions from an LMS or a provider come in by import.

### 3.2 Courses (R1.2)

CanDo ships no courses of its own. It links free government courses (for example provincial health and safety awareness courses) and offers licensed bilingual libraries through a partner, delivered on the partner's platform. The partner is still to be chosen (Q50).

### 3.3 The training the law requires (R1.3)

CanDo loads the training the law requires, by jurisdiction and sector, from `rules/learning/ca-2026-training-requirements.json` into `ref.training_requirement`: who must take it, whether it comes before the work, the deadline, how often it is repeated and the citation. An organization turns each into a training rule (`source = law`), which can be stricter but never looser: no later deadline, no less frequent refresher, no grace period, and training the law wants before the work stays before the work (`TRAINING_RULE_LOOSER_THAN_LAW`). An entry still marked `verify_at_load` cannot be applied (`RULE_NOT_VERIFIED`). The organization adds its own rules (`source = organization`) for anything else.

At launch the file holds the federal harassment and violence prevention training (SOR/2020-130 s. 12: within three months of starting, every three years) and British Columbia's young and new worker orientation (OHS Regulation s. 3.23: before starting work) from the official text, Ontario's worker and supervisor awareness training (O. Reg. 297/13, supervisors within one week) from a secondary source, and WHMIS, Ontario accessibility and Ontario harassment program training to verify. Other jurisdictions are added before the first customer there (§16).

### 3.4 No AI (R1.4)

Nothing in learning uses AI: no drafting of quizzes or summaries, no AI recommendations. CanDo suggests courses only from fixed rules: the role's required training, a competency gap (`docs/19` §4.6), an expiring credential or a development goal. Each suggestion shows its reason, and a person assigns it (`learning_assignment.source = suggestion`).

---

## 4. Mandatory training

### 4.1 Training rules

A rule (`talent.training_rule`) names the course, who it applies to (`applies_to`: jobs, positions, units, locations, provinces, agreements, employment types, employers, person types, supervisors; `TRAINING_SCOPE_UNKNOWN` otherwise), the events that assign it, the deadline in days, how often it repeats, any grace period and whether it comes before the work (`blocks_work`).

### 4.2 Before the work (R2.1)

A rule that comes before the work has no deadline in days: the person is not ready for that work until it is done. Publishing a shift for them is covered in §6.

### 4.3 Events (R2.6)

The role's and location's training is assigned automatically on every event in the rule's list, pre-filled from `learning.assignment_events`: hire, job change, promotion, transfer to another location and return from a long leave. The manager can assign more (`source = manager`). Onboarding plans (`docs/23` §6.3) can include learning items, which are assigned with the plan.

### 4.4 Reminders and escalation (R2.2)

For mandatory training (`learning.overdue_escalation`): the employee is reminded 14 and 3 days before the due date, the manager is told 1 day after it is overdue, and HR 7 days after. `talent.learning_notices_due()` lists who is told on a date.

### 4.5 Grace periods and refresher cycles (R2.3, R2.4)

There is no grace period by default, so legal training does not lapse quietly. An organization can add one to its own rules (`grace_days`), never to a rule that carries out the law; the manager and HR notices count from the end of the grace period. A refresher done within `learning.refresher_early_window_days` (60) before its due date keeps its cycle: the next one is due a full period after the old due date. Done earlier, or after the due date, the next one counts from the completion (`talent.next_due_on()`).

### 4.6 Changes in the law (R2.5)

When CanDo loads a new or changed requirement, current employees it covers are assigned it on the effective date (`source = law_change`), due by the law's own deadline, or `learning.law_change_due_days` (30) after the effective date where the law gives none (`talent.law_change_due_on()`), and HR is told. The law's deadline is kept with the assignment (`legal_due_on`), and the organization's date is never later. Training the law requires is never waived (`LEGAL_TASK_CANNOT_BE_WAIVED`); an organization's own training can be waived with a reason.

### 4.7 Training time is paid (R5.1)

Mandatory training taken outside scheduled hours records its minutes (`training_minutes`; `INPUT_REQUIRED` without them). The completion adds them to the timesheet as training time for the manager's approval, and they are paid as hours worked are (`docs/27`).

---

## 5. Credentials and licences

### 5.1 What a credential is

`talent.credential` holds a person's licences, registrations, trade and safety certificates, driver's licences, screenings and operator tickets, with the issuer, number, dates, status, how it was verified and the document. Its `credential_code` is what a job's or position's requirements name in `satisfied_by` (`docs/18` §6).

### 5.2 Expiry alerts (R3.2)

`learning.credential_alert_days`: the employee is alerted 90, 60 and 30 days before expiry; the manager and HR 30 days before and on the expiry date (`talent.credential_alerts_due()`). This replaces the "everyone at 90, 60 and 30" of `docs/22` §10.2.

### 5.3 Verification (R3.3)

HR, or a delegate the organization names, verifies a credential against the document, the public registry or the issuer, and records the method and date. Until then it is pending and does not count (`talent.credential_valid()`); a person never verifies their own (`SELF_APPROVAL`). A credential is valid until its expiry date.

### 5.4 Registries (R3.4)

No registry integrations at launch: the verification screen links to the registry, and HR records what it saw. Integrations are built as customers need them.

### 5.5 Continuing education (R3.6)

Where a licensing body requires hours over a period (`talent.ce_requirement`), CanDo counts the credits of completions (`talent.ce_progress()`) and reminds the person before the period ends.

### 5.6 Apprenticeships (R3.5)

Basic at launch (`talent.apprenticeship`, `talent.apprenticeship_hours`): hours on the job and in technical training by trade and level, the registration number, and the wage step of the level from the pay grid or agreement (Module 04). Journeyperson ratio checks on schedules come later.

---

## 6. Ready for the work (R2.1, R3.1)

When a shift is published, or a published shift is moved to another person or date, CanDo checks the person against the position on that date (`talent.work_readiness()`, trigger on `timeleave.shift`):

- **A credential the law requires** (a requirement from legislation, such as a nursing registration) that is missing, pending or expired stops the shift, with no override (`CREDENTIAL_REQUIRED_BY_LAW`).
- **A credential the organization requires**, or **training required before the work** that is not done, needs the caution `learning.not_ready_for_work` with a reason (`CAUTION_NOT_ACKNOWLEDGED`); the training or credential stays due.

Swaps and offers already check credentials (`docs/27` §9) with the same rule.

---

## 7. Skills and development plans

### 7.1 The skills list (R4.1)

A new organization starts from CanDo's Unified Competency Model (`docs/19` §4, `docs/25` §9). ESDC's Skills and Competencies Taxonomy, linked to NOC, is offered at setup as an optional add-on framework. The organization edits both.

### 7.2 Consent for internal opportunities (R4.2)

Managers and recruiters see an employee's skills profile for internal opportunities only after the employee opts in (`talent.skills_consent`, `talent.skills_visible()`), and the employee can withdraw at any time. The employee, their manager and HR see it for development as before.

### 7.3 Development plans (R4.3, R4.4)

A development plan (`talent.development_plan`) works like goals (`docs/28` §4.1): the employee or the manager proposes it, both agree (`PLAN_NOT_AGREED`), and once agreed every added or changed action names who changed it, and the change is kept (`talent.development_plan_change`). Actions are experience, relationships or formal learning, can point to a course and to a development goal in Performance, and have a target date. The 70-20-10 mix is shown as guidance (`talent.development_mix()`); nothing is enforced.

---

## 8. Training requests and tuition

### 8.1 Requests (R5.2)

A request for an external course, conference, certification or program (`talent.training_request`) states its cost, time off, business case, budget and any grant or agreement right, and goes through the organization's route (`INPUT_REQUIRED` without one; `ROUTE_APPROVALS_MISSING` until complete). The starter routes send it to the manager, and to HR as well above `learning.request_hr_above_amount`, which each organization chooses at setup (`talent.training_request_facts()`).

### 8.2 Taxable or not (R5.4)

Before anything is paid, HR marks each request as mainly for the employer or mainly for the employee, with CRA's test shown (`primarily_for`; `INPUT_REQUIRED`). CRA treats specific job-related training and general business-related courses (such as first aid, language or stress management) as mainly for the employer, and not taxable; training mainly for the employee's personal interest is a taxable benefit, which goes to payroll.

### 8.3 Repayment (R5.3)

Repayment is the organization's decision. It writes its own rules by kind of training and cost (`talent.repayment_rule`: none, prorated or full, over a number of months); CanDo gives no starting rule, and two rules that fit the same request are an error (`REPAYMENT_RULE_AMBIGUOUS`). When no rule fits, the organization's setup choice applies (`learning.repayment_without_rule`): HR decides on the request, or there is no repayment. Where repayment applies, the employee signs the agreement before reimbursement (`REPAYMENT_AGREEMENT_REQUIRED`), and anything owed when they leave (`talent.repayment_owed()`) is recovered only with their written authorization (`docs/21` §7.2, Module 11).

---

## 9. Budgets and funding

### 9.1 Budgets (R6.1)

Each department can have a training budget for a period (`talent.training_budget`), with an optional amount per employee. Spend is the cost of approved and later requests (`talent.budget_remaining()`). Approving a request over what is left needs the caution `learning.over_budget` with a reason, and finance approves where the organization's route has an `overBudget` step.

### 9.2 Grants and training funds (R6.3)

Each program (Canada-Province Job Grants, wage subsidies, Indigenous skills and employment programs, union training trusts) is a funding source (`docs/17` §8). A request names the source that pays part of it, and claims are recorded with the eligible cost, the employer's share and the amount claimed (`talent.grant_claim`).

### 9.3 Quebec's 1% rule (R6.2)

An employer whose payroll is over $2 million invests at least 1% of it in eligible training, or pays the difference to the Fonds de développement et de reconnaissance des compétences de la main-d'œuvre on its RL-1 summary (Revenu Québec). CanDo records whether each request and completion is eligible (`wsdrf_eligible`) from launch; the report comes with Quebec payroll in phase 2.

---

## 10. Mentoring, records and special populations

### 10.1 Mentoring (R7.1)

HR or the manager pairs a mentor and a mentee for a purpose and a period (`talent.mentoring_pair`), with rule-based suggestions by skills and goals (no AI). Sessions are logged with notes and feedback from both (`talent.mentoring_session`). No one mentors themself. Onboarding buddies stay in `docs/23` §6.5.

### 10.2 Records (R7.2)

Training and credential records are kept at least as long as the law and safety regulators expect (`training_records_retention` in the rules file), plus `learning.records_keep_extra_years` (0) if the organization wants longer, and can be exported per person or site, ready for an inspection. The retention job is part of Module 13 (Step 18).

### 10.3 Council and board members (R7.3)

People of a non-employee type (council and board members, volunteers, contractors) get training assignments with no employment and no pay record; an employee's training always names its employment (`INPUT_REQUIRED`).

### 10.4 Who sees what (R7.5)

Employees see their own records; managers see their teams; HR and a compliance role the organization grants see training status across the organization. Credential documents and numbers are for HR.

### 10.5 Collective agreements (R7.4)

Paid education leave, tuition support and training funds are read from the agreement library and applied to requests and leave (`agreement_right` on the request; education leave in `docs/27` §8). HR is reminded of any union notice. The agreement fields are added to `rules/agreements/agreement.schema.json` in Step 7.

### 10.6 Languages (R7.6)

A course is assigned in the organization's main language (`learning_assignment.language`, filled from the organization's main language). Other versions it offers (French, Inuktut or another Indigenous language) are given on request.

---

## 11. Fallbacks

None added. What happens when no repayment rule fits is a setting each organization chooses at setup, and a course is assigned in the organization's main language as a column filled from it (`docs/22` §3).

---

## 12. Data model (migration 0015)

| Object | What it holds |
| --- | --- |
| Settings in §2.1 | 8 settings: 6 with CanDo defaults, 2 chosen at setup |
| `ref.training_requirement` | The training the law requires, loaded from `rules/learning` (§3.3) |
| `talent.learning_item`, `talent.learning_session`, `talent.session_attendee` | §3.1 |
| `talent.training_rule` (events and early window filled from the settings), `talent.learning_assignment` (language filled from the main language), `talent.learning_completion`; `talent.law_change_due_on()`, `talent.next_due_on()`, `talent.learning_notices_due()` | §4 |
| `talent.credential`, `talent.credential_valid()`, `talent.credential_alerts_due()`, `talent.ce_requirement`, `talent.ce_progress()`, `talent.apprenticeship`, `talent.apprenticeship_hours`, `talent.apprentice_hours()` | §5 |
| `talent.position_requirements()`, `talent.work_readiness()`, trigger `a20_shift_readiness` on `timeleave.shift` | §6 |
| `talent.skills_consent`, `talent.skills_visible()`, `talent.development_plan`, `talent.development_action`, `talent.development_plan_change`, `talent.development_mix()` | §7 |
| `talent.training_request`, `talent.repayment_rule`, `talent.repayment_rule_for()`, `talent.repayment_owed()`, `talent.training_request_facts()`, `talent.training_budget`, `talent.budget_remaining()`, `talent.grant_claim` | §8, §9 |
| `talent.mentoring_pair`, `talent.mentoring_session` | §10.1 |
| Route subject `training_request`, condition `aboveHrAmount`, two starter routes; cautions; `check_approval_task()` with training requests | §2 |

Every new tenant table has `tenant_id` with forced row-level security; text fields are registered as translatable (`docs/22` §4.3). The starter routes are copied to existing organizations, skipping one that keeps a third language as required for its data (FB-035). `talent.learning_record` (0001) is kept as history and read-only; the data migration moves its rows into completions and credentials.

---

## 13. Validation, API and events

**Errors added by 0015:** `SESSION_FULL`, `TRAINING_SCOPE_UNKNOWN`, `TRAINING_EVENT_UNKNOWN`, `TRAINING_RULE_LOOSER_THAN_LAW`, `SIGNOFF_REQUIRED`, `CREDENTIAL_REQUIRED_BY_LAW`, `PLAN_NOT_AGREED`, `REPAYMENT_RULE_AMBIGUOUS`, `REPAYMENT_AGREEMENT_REQUIRED`. Existing ones used: `INPUT_REQUIRED`, `RULE_NOT_VERIFIED`, `LEGAL_TASK_CANNOT_BE_WAIVED`, `SELF_APPROVAL`, `CAUTION_NOT_ACKNOWLEDGED`, `ROUTE_APPROVALS_MISSING`, `SETTING_NOT_SET`.

**Checks in the application (Step 17 unless noted), not the database:** generating assignments from rules, events and changes in the law; matching the audience of the law's requirement to the organization's scope; LMS and provider imports (SCORM, xAPI, cmi5, LTI, APIs); rule-based suggestions with their reasons; adding training minutes to the timesheet (with Step 11); sending notices and alerts; continuing education reminders; the HR capability for verification; repayment recovery with written authorization (with Step 16); the taxable benefit to payroll (with Step 9); the compliance view and inspection exports; the ESDC taxonomy add-on; mentoring suggestions.

**API** (added to `api/openapi.yaml` in Step 17): `GET/POST /learning/items`, `/learning/sessions` with attendees; `GET /learning/law-requirements?jurisdiction=`; `GET/POST /learning/rules`; `GET/POST /learning/assignments` with `waive`; `POST /learning/completions` and `POST /learning/imports`; `GET/POST /credentials` with `verify`; `GET /credentials/alerts?on=`; `GET/POST /learning/ce-requirements`, `GET /people/{id}/ce-progress`; `GET/POST /apprenticeships` with hours; `GET /assignments/{id}/work-readiness?on=`; `POST/DELETE /people/{id}/skills-consent`; `GET/POST /development-plans` with actions and `agree`; `GET/POST /training-requests` with `submit`, `approve`, `mark`, `reimburse`; `GET/POST /learning/repayment-rules`, `/learning/budgets`, `/learning/grant-claims`; `GET/POST /mentoring/pairs` with sessions.

**Events** (added to `api/events.yaml`; identifiers only, AGENTS rule 9): `learning.assigned`, `learning.due_soon`, `learning.overdue`, `learning.completed`, `learning.law_requirement_changed`, `credential.verified`, `credential.expiring`, `credential.expired`, `shift.not_ready_acknowledged`, `development_plan.agreed`, `training_request.approved`, `training_request.reimbursed`, `mentoring.paired`.

---

## 14. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| LRN-020 | New organization opens setup | Defaults pre-filled; HR amount and repayment choice asked | smoke 1a–c | 1, 17 |
| LRN-021 | BC supervisor rule at 14 days where the law says 7; at 5 | `TRAINING_RULE_LOOSER_THAN_LAW`; accepted | smoke 2a–b | 17 |
| LRN-022 | Law rule with a grace period, or a 4-year refresher where the law says 3 | `TRAINING_RULE_LOOSER_THAN_LAW` | smoke 2c–d | 17 |
| LRN-023 | Orientation the law wants before work set as "within 30 days" | Refused | smoke 2e | 17 |
| LRN-024 | Rule from a requirement still `verify_at_load` | `RULE_NOT_VERIFIED` | smoke 2f | 17 |
| LRN-025 | The organization's own wound care rule with a 14-day grace | Accepted; notices count from the end of the grace | smoke 2, 3i | 17 |
| LRN-026 | HR waives the harassment training the law requires | `LEGAL_TASK_CANNOT_BE_WAIVED` | smoke 3b | 17 |
| LRN-027 | Council member assigned the code of conduct course; an employee assigned training without her employment | Accepted; `INPUT_REQUIRED` | smoke 3c | 17 |
| LRN-028 | Learner signs off her own on-the-job training | `SIGNOFF_REQUIRED` | smoke 3d | 17 |
| LRN-029 | Mandatory course done on a day off with no minutes; with 90 minutes | Refused; completed, 90 minutes to the timesheet | smoke 3e–f | 11, 17 |
| LRN-030 | Refresher due 1 March done 15 January; done 1 November; done 10 April | Next due 1 March three years on; 1 November; 10 April | smoke 3g | 17 |
| LRN-031 | Law adds training with a 90-day deadline; one with none | Due in 90 days; due in 30 days | smoke 3h | 17 |
| LRN-032 | Overdue training | Employee 14 and 3 days before; manager 1 day and HR 7 days after | smoke 3i | 17 |
| LRN-033 | Registration marked valid without verification, or verified by the nurse herself | Refused; `SELF_APPROVAL` | smoke 4a–b | 17 |
| LRN-034 | Registration expiring 1 January | Employee alerted at 90, 60, 30 days; manager and HR at 30 days and on 1 January; not valid from 1 January | smoke 4c–d | 17 |
| LRN-035 | Nurse with 30 continuing education hours due every 2 years | Progress counted from completion credits | smoke 4e | 17 |
| LRN-036 | Cook apprentice, level 1 | On-the-job hours counted apart from technical training | smoke 4f | 17 |
| LRN-037 | Shift for a nurse without first aid | `CAUTION_NOT_ACKNOWLEDGED` until acknowledged with a reason | smoke 5a | 11, 17 |
| LRN-038 | Shift for a nurse whose registration is pending, with a caution acknowledged | `CREDENTIAL_REQUIRED_BY_LAW` | smoke 5b | 11, 17 |
| LRN-039 | Shift after a transfer, before the new orientation | Training before work counted | smoke 5c | 11, 17 |
| LRN-040 | Recruiter opens a skills profile before and after the employee opts in, and after she withdraws | Hidden; shown; hidden | smoke 6a–c | 17 |
| LRN-041 | Development plan agreed by the employee alone; agreed by both, then changed | `PLAN_NOT_AGREED`; change kept with who and why | smoke 6d–f | 17 |
| LRN-042 | $1,200 certificate request before the HR amount is chosen; after it is set to $500 | `SETTING_NOT_SET`; manager then HR | smoke 7b–c | 17 |
| LRN-043 | The employee approves her own request; approval over the remaining budget | `SELF_APPROVAL`; caution needed | smoke 7e–f | 17 |
| LRN-044 | Reimbursement before HR marks it for CRA | `INPUT_REQUIRED` | smoke 7g | 17 |
| LRN-045 | No repayment rule and no setup choice; HR decides; a prorated 12-month rule | `SETTING_NOT_SET`; `INPUT_REQUIRED`; agreement signed first | smoke 7h–j | 17 |
| LRN-046 | Employee leaves 6 months after a $1,200 prorated course | $600 owed, recovered only with written authorization | smoke 7k | 16, 17 |
| LRN-047 | Two repayment rules fit | `REPAYMENT_RULE_AMBIGUOUS` | smoke 7l | 17 |
| LRN-048 | Grant claim above the eligible cost | Refused | smoke 8a | 17 |
| LRN-049 | Mentoring oneself; a full session | Refused; `SESSION_FULL`, waitlist | smoke 8b–c | 17 |
| LRN-050 | Another organization reads learning data | Nothing visible | smoke 9 | 1 |

---

## 15. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/08` | Points here at the top; open questions closed; the LMS build, content creation with AI and recommendations replaced by integration-first, partner and government content and rule-based suggestions |
| `stories/07-to-10-talent.md` | LRN-001 to LRN-004 follow this document; new stories LRN-005 to LRN-009; scenarios LRN-020 to LRN-050 in §14 |
| `docs/15` Step 17 | Read this document; build on migration 0015; pass LRN-001 to LRN-009 and LRN-020 to LRN-050 |
| `docs/16` | Two settings chosen at setup; new Q50 (course library partner); items to verify for this module |
| `docs/22` | Settings from 0015 are listed here, not in `docs/22` §2; `learning.credential_alert_days` as decided here (§5.2) |
| `docs/27` §9 | Shifts are checked for readiness when published (§6) |
| `AGENTS.md` | Reading order item 16; rule 53; Step 1 migration 0015 and its smoke test; Step 17 |
| `.cursor/rules/00-cando.mdc` | Rule 53 in short |
| `rules/learning/ca-2026-training-requirements.json` | New: the training the law requires (federal, BC, Ontario), records retention, Quebec's 1% rule and CRA's taxable benefit test |

Where a listed document still says otherwise, this document wins.

---

## 16. Open questions and items to verify

| Item | Until decided |
| --- | --- |
| Partner for the licensed bilingual course library (Q50) | Government courses linked; each organization's own LMS or provider |
| The training the law requires, by jurisdiction and sector | Federal harassment and violence and BC orientation from the official text; Ontario awareness training `secondary`; WHMIS, Ontario accessibility and Ontario harassment program `verify_at_load`; other jurisdictions not entered. Counsel review before Step 17 |
| Training records retention by jurisdiction | BC keeps records with no period found; Ontario's six-month proof rule `secondary`; others not entered. Reviewed with the Module 13 retention schedule |
| ESDC Skills and Competencies Taxonomy | Loaded as an optional framework from ESDC's published files in Step 17; licence and update cycle to confirm |
| Journeyperson ratio checks on schedules | Later phase (R3.5) |

---

## Sources

- Work Place Harassment and Violence Prevention Regulations (SOR/2020-130), s. 12: https://laws-lois.justice.gc.ca/eng/regulations/SOR-2020-130/section-12.html
- WorkSafeBC, OHS Regulation Part 3 (ss. 3.22 to 3.25, young and new workers): https://www.worksafebc.com/en/law-policy/occupational-health-safety/searchable-ohs-regulation/ohs-regulation/part-03-rights-and-responsibilities
- Siskinds, Ontario O. Reg. 297/13 awareness training (secondary): https://www.siskinds.com/new-ohsa-regulations-coming-into-force-on-july/
- Revenu Québec, Fonds de développement et de reconnaissance des compétences de la main-d'œuvre: https://www.revenuquebec.ca/fr/entreprises/retenues-et-cotisations/calculer-les-retenues-a-la-source-et-vos-cotisations-demployeur/fonds-de-developpement-et-de-reconnaissance-des-competences-de-la-main-doeuvre/
- Canada Revenue Agency, Educational assistance (employer-paid training): https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/payroll/benefits-allowances/subsidized-school-services.html
