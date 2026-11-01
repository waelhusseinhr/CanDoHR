# 02 Recruitment & Onboarding · Review decisions

Review of 25 Oct 2026 with Wael, round by round.

**Status: applied (25 Oct 2026).** The decisions are in the developer pack:

- `dev-pack/docs/23-recruitment-onboarding-decisions.md` (new): every decision with its setting or rule, cautions and acknowledgements, approval routes the organization builds, requisitions, postings, selection, retention, offers, pre-boarding, onboarding, probation, open cases before an ending, conversion, fallbacks, the data model, errors, API and events, scenarios REC-015 to REC-039, and the changes to other documents. It wins over `requirements/02` and `stories/02`.
- `dev-pack/schema/0009_recruitment_onboarding.sql` and `dev-pack/tests/schema/schema_0009_smoke.sql` (new): loaded on PostgreSQL 16 after 0001 and 0003 to 0008, on an empty database and on one holding the earlier smoke tests' data; all seven smoke tests pass (0009: 13 check groups).
- `dev-pack/rules/employment-standards/ca-2026-recruitment-additions.json` (new): SIN due within 3 days of starting; candidate retention per jurisdiction (BC and Ontario from the law, the rest to verify); Newfoundland and Labrador and Nova Scotia pay-history rules.
- `dev-pack/rules/register/values-and-fallbacks.json`: the new lists and defaults classified; FB-024 and FB-028 decided; FB-034 (probation end date passes) and FB-035 (proposed) added. `tests/hardcoding/check_values.py` passes and now reads docs/23.
- `dev-pack/requirements/02`, `stories/02`, `docs/13`, `docs/15` (Step 14), `docs/16` (Q46, Q47, settings chosen at setup), `docs/21` §3.2, `docs/22` (rebuilt), `AGENTS.md` (reading order 10, rules 46 and 47, Step 1 and Step 14), `.cursor/rules/00-cando.mdc`.

Two questions came out of the write-up and were decided on 25 Oct 2026 (applied in docs/23, migration 0009 and docs/16):

| # | Decision |
| --- | --- |
| Q46 | **The setup screen pre-fills starting numbers the organization can change:** offers open 5 working days; an overdue task's owner is reminded 2 days before, their manager told 1 day after, HR 3 days after. |
| Q47 | **Cases closed in the last 12 months also trigger HR's review before an ending** (reprisal risk can outlast a case); each organization can change the 12. |

Rounds: 1 scope · 2 requisitions and approvals · 3 postings and union rules · 4 applications and selection · 5 offers and hand-off to Core HR · 6 pre-boarding and onboarding · 7 probation and status conversion.

The principle from Module 01 applies: every decision is a default each organization can change at setup or later, except legal floors and safety rules. Wael added for this module: **every workflow, approval route, message and rule is configurable by the organization and can be changed again later.**

## Round 1 · Scope

| # | Decision |
| --- | --- |
| 1 | **No Bubble prototype.** Recruitment is built on the same stack as every other module. |
| 2 | **Core hiring built in; outside providers for the rest.** Built in: requisition, posting, application, screening, interview, offer, hire, onboarding tasks, probation. Through providers: job boards, background checks, tests, video interviews, e-signature. |
| 3 | **A requisition before every hire, with approval routes the organization builds.** Routes differ by requisition type (replacement, new position, additional headcount), by term or permanent, and by budget; approvers can be the department, HR, finance, an executive, or several. A new position needs its job description, pay grade and budget approved. A requisition lists the certifications and qualifications candidates must show. |
| 4 | **AI match suggestions, off unless the employer switches them on.** The employer sets the criteria and the weight of each one. Resume reading fills applications. The Ontario AI notice is added to postings automatically when suggestions are on. AI never rejects a candidate. |
| 5 | **Who screens and who sees applicants is chosen at setup (no CanDo default):** HR, the department, or both. A hiring manager sees the applicants for their own requisition as the setup allows. Candidates can choose to join a talent pool for other positions, which authorized users can search. |

## Round 2 · Requisitions and approvals

| # | Decision |
| --- | --- |
| 1 | **Starter routes** (each organization edits them): replacement: hiring manager → HR; new position: hiring manager → department head → HR (job description, pay grade) → finance (budget); additional headcount: as new position plus an executive; over budget: finance approval with a written reason (Module 01, R3.2). |
| 2 | **Replacing someone who resigned: recruiting can start once the resignation is recorded.** |
| 3 | **Term requisitions use the same routes as permanent ones by default;** each organization can set lighter routes. |
| 4 | **Requisition content:** budget coding with cost centres, and several funding sources with their shares for one position (`docs/17` §8); duration (end date for term, none for ongoing); employment type (full-time or part-time by FTE; permanent, term or fixed-term, seasonal, casual, student; the organization's own types per `docs/22` §3.4). |
| 5 | **A candidate missing a required certification:** the organization chooses per posting whether the candidate is flagged for a person to decide or screened out. |
| 6 | **Candidate messages are the organization's:** mass emails to candidates not selected or shortlisted, with or without a reason, from the organization's templates. |
| 7 | **Direct hire without a requisition is allowed with special approvals** that the organization defines (its own "direct hire" route). |
| 8 | *(Added in Round 6)* **Hiring without a posting follows the organization's own rules.** For example: calling a person the manager already has in mind, someone from the external or internal talent pool, giving a current employee extra duties as a second position (`docs/20`), or hiring on-call staff without a posting. Where a collective agreement or a policy requires a posting, CanDo shows a caution, and going ahead needs the acknowledgement and approval the organization sets. |

## Round 3 · Postings and union rules

Where a collective agreement sets a rule, the agreement's rule applies as the organization has set it up.

| # | Decision |
| --- | --- |
| 1 | **Internal-first posting is chosen on each posting;** the starting choice is internal and public at the same time. |
| 2 | **Pay is shown on postings by default;** the employer can remove it where the law allows (it cannot where the province requires it: Ontario, BC, PEI). What is shown is the employer's choice within the province's rules: a range, the average of current incumbents, a market point such as the 75th percentile, or another value. |
| 3 | **Union seniority in selection is the organization's choice:** CanDo can apply the agreement's seniority order, and the organization can choose not to, or override it later. |
| 4 | **The union is told by HR, with a CanDo reminder** when an agreement requires notice of a posting or a result. |
| 5 | **Posting channels are the organization's choice per posting:** the boards CanDo connects to (through a posting partner), the organization's own career page, Google, Indeed's free listings, and professional and regulatory bodies (for example engineers' or physicians' associations). |
| 6 | **"Average of current incumbents" is offered only with at least 3 incumbents** (a number the organization can change), with a notice when it is not available. |
| 7 | **Overriding the agreement's seniority order needs a written reason,** and the approval the organization sets, if any. |

## Round 4 · Applications and selection

| # | Decision |
| --- | --- |
| 1 | **No account needed to apply.** A candidate gives at least an email or a phone number. The employer adds its own questions (multiple choice, yes/no, dates, text), each optional or mandatory. |
| 2 | **Candidate data is kept as the organization sets at setup, never less than the law:** per province where it has locations (for example BC one year after a decision, Ontario three years for postings and applications), or the longest of them for all. The legal minimums come from the rules files. |
| 3 | **Interview scoring kits are the organization's choice** (every interview scored, or optional). Interview notes and scores are kept as long as the applications. |
| 4 | **Blind screening is off by default;** the organization can turn it on at setup. |
| 5 | **An internal applicant decides when to tell their manager.** Once accepted, telling the current supervisor is a condition of the move. Whether the move is an internal transfer or a resignation from the current position depends on the organization and the position. |

## Round 5 · Offers and hand-off to Core HR

| # | Decision |
| --- | --- |
| 1 | **Offer approvals are built by each organization** to fit its size and needs (a 250-person employer and a 5,000-person employer route differently); CanDo offers starter routes to copy. For union positions the pay step comes from the agreement's grid. |
| 2 | **The employee record is created when the offer is accepted and the contract is signed.** Before the contract is signed the person is still a candidate, not an employee. Creating the record asks for the information the job needs. |
| 3 | **Offer expiry has a default the organization sets;** HR or the offering manager can change it for each offer. |
| 4 | **Background and criminal record checks, where required, come after a conditional offer** and are a condition of it. |
| 5 | **Any change to offer terms goes back for approval,** unless the organization sets otherwise. |

**Cross-module rule (Wael):** everything is flexible and configurable. Users get reminders and cautions. When a user goes past a caution, they acknowledge that they read it and are overriding it on purpose (with a reason where the organization asks for one), and CanDo records who did what and when, for audit.

## Round 6 · Pre-boarding and onboarding

Pre-boarding opens when the contract is signed (Round 5, decision 2).

| # | Decision |
| --- | --- |
| 1 | **The new hire uses the same CanDo login they will have as an employee.** Until the start date they see only pre-boarding screens. |
| 2 | **Each form has a due date set in the organization's onboarding process.** Pre-boarding and payroll information can be completed any time from contract signing up to the first day at the latest. Some items are due on or before the first day (for example the SIN and the bank account). Others are due later, tied to their own event (for example benefit enrolment when benefits start after three months). A due date can be stricter than the law but never later (the SIN is due within 3 days of starting, per CRA); CanDo warns HR when a legal due date is about to pass. |
| 3 | **Onboarding checklists start from CanDo starter checklists that the organization edits and can change at any time.** Each department in the same organization can have its own. Training differs by role (for example IT-specific training, or health and safety training for safety staff), alongside training for everyone (such as orientation). |
| 4 | **Overdue tasks:** reminder to the task owner, then their manager, then HR, each after a number of days the organization sets. |
| 5 | **The manager chooses buddies and mentors, and CanDo suggests names.** A new hire can have several buddies and mentors, each covering part of the work (a function or a task) for part of the timeline. |
| 6 | **Optional extras (welcome videos, check-in surveys, an Indigenous and culturally aligned track, the buddy program) are all available, and each stays off until the organization turns it on.** The organization decides at setup whether each one is required. |

## Round 7 · Probation and status conversion

The length of probation was decided in Module 01 (`docs/21` §3.2).

| # | Decision |
| --- | --- |
| 1 | **Each organization sets the check-ins for each type of probation;** the starting set is 30 days, 60 days and 2 weeks before the end. |
| 2 | **If the end date passes with no decision, probation is treated as passed and HR is told.** Before that, the organization sets as many reminders as it wants (for example 30, 15, 10, 5, 3, 2 and 1 days before the end). When a vacation or leave is requested that falls before the end date, the approver sees a caution before approving; statutory holidays in that period are shown too. |
| 3 | **The employer can extend probation for any reason it chooses, before the end date, after telling the employee.** The reason is recorded. The agreement's maximum applies to union staff; the organization may set a maximum for others. A caution reminds the manager that extending probation does not delay the law's notice rights. |
| 4 | **No warning signs or risk scores during probation.** Reminders to the manager to complete and sign reviews stay. Before anyone recommends or approves ending employment, CanDo shows a caution when the person has an open matter (a warning letter, misconduct, an investigation, a dispute, a grievance, or a complaint or claim, including one against their manager), so everyone deciding is aware before acting. |
| 5 | **Conversion from temporary or casual to regular starts when a manager asks.** An organization can also set thresholds so CanDo flags people who reach them; a person decides. |
| 6 | **CanDo prepares a confirmation letter when probation is passed,** from the organization's template, for HR to send or sent automatically if the organization chooses; it can be turned off. |

**Fallbacks decided in this review:** FB-028, no TD1 on file: tax on the basic personal amount only (CRA's rule), and HR is reminded to collect the form. FB-024, no s. 87 exemption recorded: normal deductions until HR records it with its basis; pre-boarding asks whether the person claims it, and a "yes" gives HR a task before the first pay.

**Confirmed by Wael after Round 7:**

- The leave caution in decision 2 applies when the probationary employee requests a leave and when their manager goes on leave in that period.
- The caution in decision 4 covers **any open case HR should know about**, not only a complaint against the manager (for example an accommodation, a leave, a workers' compensation claim, a grievance, an investigation, a human rights or employment standards complaint). HR reviews before probation is failed or employment ends, so the decision does not breach the law. When a case is against the manager, the manager sees only that HR must review, not the case.
- Where a collective agreement loaded in CanDo requires a conversion to regular, HR is notified even when the organization has not set thresholds (as for union notices, Round 3, decision 4).

## Also decided in this review (values and languages)

| Item | Decision |
| --- | --- |
| Translation service | **Per word translated (AI cost plus margin), quoted and approved by the organization before each job** (`docs/22` §4.6, Q45 decided 25 Oct 2026). |
