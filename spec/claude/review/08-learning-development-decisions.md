# 08 Learning & Development · Review decisions

Review started 28 Oct 2026 with Wael. Decisions are logged here round by round; the developer pack is updated when the review is complete.

**Status: applied 28 Oct 2026.** The decisions are in `dev-pack/docs/29-learning-development-decisions.md`, migration `dev-pack/schema/0015_learning_decisions.sql` and its smoke test, the register, `rules/learning/ca-2026-training-requirements.json` (the training the law requires: federal harassment and violence prevention and BC new worker orientation from the official text, Ontario awareness training from a secondary source, WHMIS and Ontario accessibility to verify; Quebec's 1% rule; CRA's taxable benefit test), and the updates listed in docs/29 §15. Pre-filled, each organization's to change (the Q46 principle): reminders 14 and 3 days before, manager 1 day and HR 7 days after; the 60-day early window for refreshers and 30 days after a change in the law (CanDo's suggestions, accepted); assignments on all five events; credential alerts (employee 90, 60, 30; manager and HR 30 and on expiry); records kept for the law's period. Chosen by each organization at setup, with no CanDo number: the cost above which HR approves a training request, and what happens when no repayment rule fits; repayment rules themselves are the organization's. Open: the course library partner (docs/16 Q50). Interpretations: a licence the law requires means a position requirement whose source is legislation; readiness is checked when a shift is published or moved; no AI includes no AI mentoring matches.

Planned rounds: 1 scope, content and AI · 2 mandatory training rules · 3 credentials and licences · 4 skills and development plans · 5 training time, requests and tuition · 6 budgets and funding programs · 7 mentoring, records and special populations.

The principle from Modules 01 to 07 applies: every decision is a default each organization can change at setup or later, except legal floors and safety rules; routes and rules are the organization's, with reminders, cautions and recorded acknowledgements; CanDo pre-fills its suggested numbers at setup and the organization can change them (Q46).

Already decided elsewhere and not asked again: requirements on jobs and positions, with the courses and credentials that satisfy them (`docs/18` §6); the competency model, targets by career level and gaps (`docs/19` §4, `docs/25` §9); onboarding plans with training items by role, pre-boarding and buddies, mentors and trainers (`docs/23` §6); training goals in performance point to the learning the role needs (`docs/28` §4.1); schedules and swaps check credentials (`docs/27` §9); education leave is a leave category (`docs/27` §8); money owed (such as tuition repayment) is recovered only with written authorization (`docs/21` §7.2, `docs/24`); people decide and AI never decides (AGENTS rule 14); Quebec payroll is phase 2 (`docs/24`); credential expiry alerts become the setting `learning.credential_alert_days`, pre-filled 90, 60 and 30 days (`docs/22` §10.2).

## Round 1 · Scope, content and AI

| # | Decision |
| --- | --- |
| 1 | **Integration-first:** CanDo keeps the learning record, assignments, compliance tracking and credentials; courses run in the customer's LMS or the provider's platform, linked through SCORM, xAPI, LTI or the provider's API. CanDo has no course player or authoring tool. |
| 2 | **No ready-made CanDo courses:** CanDo links free government courses and offers licensed bilingual libraries through a partner. |
| 3 | **CanDo loads the training the law requires, by province and sector; an organization can make it stricter but not looser, and adds its own rules.** |
| 4 | **No AI in learning:** no AI drafting of quizzes or summaries and no AI recommendations. |

Confirmed after Round 1:

- **CanDo still records learning that happens outside any LMS:** classroom and virtual session attendance, on-the-job checklists signed off by a supervisor, policy acknowledgements, and external courses with their certificate. No course player or authoring.
- **Rule-based suggestions are allowed, not AI:** CanDo suggests courses from fixed rules (the role's required training, competency gaps, an expiring credential), each with its reason shown; people decide.

## Round 2 · Mandatory training rules

| # | Decision |
| --- | --- |
| 1 | **A training required before certain work that is not done stops scheduling the person for that work,** unless someone acknowledges a caution with a reason. |
| 2 | **Overdue mandatory training (pre-filled, editable): the employee is reminded 14 and 3 days before the due date, the manager told 1 day after, HR 7 days after.** |
| 3 | **No grace period by default:** legal training does not lapse quietly; an organization can add a grace period to its own rules. |
| 4 | **A refresher done early keeps its cycle when done within 60 days before the due date (pre-filled, editable); earlier, the next one counts from the completion.** |
| 5 | **When the law adds or changes a training requirement, current employees are assigned it automatically on the effective date, due by the law's deadline, or within 30 days (pre-filled) where the law gives none; HR is told.** |
| 6 | **The role's and location's training is assigned automatically on every event: hire, job change, promotion, transfer to another location and return from a long leave;** the manager can add more. |

## Round 3 · Credentials and licences

| # | Decision |
| --- | --- |
| 1 | **An expired credential the position requires: where the law requires the licence to do the work, the person cannot be scheduled for it, with no override; for other credentials, a caution with a reason lets the work go ahead.** |
| 2 | **Expiry alerts (pre-filled, editable): the employee at 90, 60 and 30 days; the manager and HR at 30 days and on the expiry date** (changes the spec's "everyone at 90, 60 and 30"). |
| 3 | **HR, or a delegate the organization names, verifies a credential against the document or the public registry, recording the method and date;** until then it counts as pending, not valid. |
| 4 | **No registry integrations at launch:** manual checks with a link to the registry; integrations built as customers need them. |
| 5 | **Apprenticeships basic at launch:** hours by trade and level, technical training periods, and the wage step from the grid; journeyperson ratio checks on schedules come later. |
| 6 | **Continuing education hours a licensing body requires are tracked against each body's requirement,** with progress and reminders before the period ends. |

## Round 4 · Skills and development plans

| # | Decision |
| --- | --- |
| 1 | **A new organization starts from CanDo's Unified Competency Model; ESDC's Skills and Competencies Taxonomy (linked to NOC) is offered as an optional add-on;** the organization edits both. |
| 2 | **Managers and recruiters see an employee's skills profile for internal opportunities only after the employee opts in,** and the employee can withdraw at any time. |
| 3 | **A development plan works like goals:** proposed by the employee or the manager, agreed by both, every change kept, and linked to the person's development goals in Performance. |
| 4 | **The 70-20-10 mix (experience, relationships, formal learning) is shown as guidance;** nothing is enforced. |

## Round 5 · Training time, requests and tuition

| # | Decision |
| --- | --- |
| 1 | **Mandatory training taken outside scheduled hours is added to the timesheet as training time when completed, for the manager's approval, and is always paid,** as hours worked are. |
| 2 | **Requests for external courses, conferences and certifications go through the organization's route;** the starter route is the manager, and HR as well above an amount the organization sets. |
| 3 | **Tuition repayment is the organization's decision:** it depends on the kind of training, its cost and the organization's own rules (Wael's own answer). Confirmed after the round: the organization sets its repayment rules by kind of training and cost (none, prorated or full, over a period), with no CanDo starting rule, and what happens when no rule fits is also the organization's own choice. The law's floor stays: an agreement signed before reimbursement where repayment applies, and written authorization before anything is recovered (`docs/21` §7.2). |
| 4 | **HR marks each paid training as mainly for the employer or mainly for the employee, with CRA's guidance shown;** training mainly for the employee goes to payroll as a taxable benefit. |

## Round 6 · Budgets and funding programs

| # | Decision |
| --- | --- |
| 1 | **Training budgets by department at launch, per employee optional;** spend comes from approved requests; going over needs a caution, a reason and finance through the organization's route. |
| 2 | **Quebec's 1% training rule: eligible spending recorded from launch; the report comes with Quebec payroll in phase 2.** |
| 3 | **Grant-funded training tracked at launch (basic):** each program (Canada-Province Job Grants, wage subsidies, Indigenous skills programs, union training trusts) is a funding source with its eligible training, employer share, claims and reports. |

## Round 7 · Mentoring, records and special populations

| # | Decision |
| --- | --- |
| 1 | **Mentoring basic at launch:** HR or the manager pairs people, with rule-based suggestions by skills and goals (no AI); session logs and feedback. |
| 2 | **Training and credential records are kept at least as long as the law and safety regulators expect, longer if the organization chooses,** with an inspection-ready export per person or site. |
| 3 | **Council and board members' training (orientation, code of conduct where required) is tracked, as people of a non-employee type** with their own required training and no pay or employment record. |
| 4 | **Learning rights in collective agreements (paid education leave, tuition support, training funds) are read from the agreement library** and applied to requests and leave automatically; HR is reminded of union notices. |
| 5 | **HR and a compliance role the organization grants see training status across the organization;** managers see their teams and employees their own records. |
| 6 | **Courses are assigned in the organization's main language;** other language versions (French, Inuktut or another Indigenous language) are given on request. |
