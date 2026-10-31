# 23 · Recruitment and onboarding decisions

Oct 25, 2026 · @Wael

This document records the owner's review of Module 02 (Recruitment & Onboarding) and turns each decision into something the build can follow: a setting with its default, a database check, a starter copy the organization edits, or a screen behaviour. The review went round by round; the working record is `claude/review/02-recruitment-onboarding-decisions.md` in the project.

It covers requisitions and their approvals, hiring with or without a posting, postings and pay, collective agreement rules in selection, applications, screening and interviews, how long candidate records are kept, offers and the hand-off to Core HR, pre-boarding and onboarding, probation and conversion to regular status, and the rule that runs through the whole module: **cautions and acknowledgements**.

**Precedence.** On these topics this document wins over `requirements/02`, `stories/02-recruitment-onboarding.md` and the Bubble and recruitment guides in the project, and over `docs/21` §3.2 where it adds to probation. `docs/22` still wins on values, defaults, languages and fallbacks. §13 lists every place that changes. The schema is `schema/0009_recruitment_onboarding.sql` (migration 0009, Step 1), checked by `tests/schema/schema_0009_smoke.sql`. New employment standards values are in `rules/employment-standards/ca-2026-recruitment-additions.json`.

**The owner's rules for this module.**

1. Every workflow, approval route, rule and message belongs to the organization. CanDo gives starter copies; the organization edits them at setup and can change them again at any time. A 250-person employer and a 5,000-person employer will set them up differently, and both are right.
2. Users get reminders and cautions. When a user goes past a caution, they acknowledge that they read it and are overriding it on purpose, with a reason where one is needed, and CanDo records who did what and when, so an audit can follow it (§2.1).
3. Legal floors and safety rules stay fixed: what the law requires is never set lower, and a person (never AI) makes every hiring decision.

---

## 1. Decisions at a glance

| # | Decision | Setting or rule | Section |
| --- | --- | --- | --- |
| R1.1 | No Bubble prototype; recruitment is built on the same stack as every module | Build plan | §13 |
| R1.2 | Core hiring built in (requisition to probation); job boards, background checks, tests, video interviews and e-signature through providers | Integrations | §4.1, §5.3 |
| R1.3 | A requisition before every hire, with routes the organization builds; a new position needs its job description, pay grade and budget approved; the requisition lists required certifications | `platform.workflow_route` | §3 |
| R1.4 | AI match suggestions off until switched on; the employer sets criteria and weights; resume reading fills applications; the Ontario AI notice is added when suggestions are on; AI never rejects | `recruit.ai_match`: off | §4.6 |
| R1.5 | Who screens and sees applicants is chosen at setup (no CanDo default); candidates can join a talent pool | `recruit.screening_owner`: chosen at setup | §4.6 |
| R2.1 | Starter routes for replacement, new position, additional headcount and over budget | Starter routes | §3.4 |
| R2.2 | Replacing someone who resigned: recruiting can start once the resignation is recorded | Rule | §3.4 |
| R2.3 | Term requisitions use the same routes by default; organizations can set lighter ones | Route conditions | §3.4 |
| R2.4 | A requisition carries its cost centres and funding sources with their shares, its duration and its employment type | `recruit.requisition_funding` | §3.2 |
| R2.5 | A candidate missing a required certification is flagged or screened out, chosen per posting | `recruit.missing_requirement`: chosen at setup | §4.6 |
| R2.6 | Messages to candidates come from the organization's templates, with or without a reason | `recruit.message_template` | §4.8 |
| R2.7 | Direct hire without a requisition is allowed through the organization's direct-hire route | `recruit.direct_hire`: allowed with route | §3.1 |
| R2.8 | Hiring without a posting follows the organization's own rules; where an agreement or policy requires a posting, a caution and the organization's approval | `recruit.posting_default`: required; `recruit.posting_exemption_rule` | §3.3 |
| R3.1 | Internal-first is chosen on each posting; the starting choice is internal and public at once | `recruit.posting_audience`: internal and public | §4.1 |
| R3.2 | Pay shown on postings by default; removable only where the law allows; shown as a range, the incumbents' average, a market point or another value | `recruit.posting_pay_shown`: on; `recruit.posting_pay_basis`: range | §4.2 |
| R3.3 | The agreement's seniority order is applied unless the organization chooses not to | `recruit.apply_agreement_seniority`: on | §4.3 |
| R3.4 | The union is told by HR, with a CanDo reminder, when an agreement requires notice | Reminder | §4.3 |
| R3.5 | Posting channels are chosen on each posting | `posting_channel` list | §4.1 |
| R3.6 | The incumbents' average is offered only with at least 3 incumbents; HR is told why when it is not available | `recruit.incumbent_average_min`: 3 (never lower) | §4.2 |
| R3.7 | Overriding the seniority order needs a written reason and the approval the organization sets | Caution `recruit.seniority_order_overridden` | §4.3 |
| R4.1 | No account needed to apply; at least an email or a phone number; the employer's own questions | `recruit.applicant_contact`: email or phone | §4.4 |
| R4.2 | Candidate records kept as the organization sets at setup, never less than the law | `recruit.candidate_retention`: chosen at setup | §4.5 |
| R4.3 | Interview scoring: every interview, or optional; notes and scores kept as long as the applications | `recruit.interview_scoring`: chosen at setup | §4.7 |
| R4.4 | Blind screening off by default | `recruit.blind_screening`: off | §4.6 |
| R4.5 | An internal applicant decides when to tell their manager; once accepted, telling the supervisor is a condition; transfer or resignation depends on the organization and position | Offer condition; `internal_move` | §4.9 |
| R5.1 | Offer approval routes built by each organization; union pay steps from the agreement's grid | Starter routes | §5.1 |
| R5.2 | The employee record is created when the offer is accepted **and** the contract is signed | Rule (`HIRE_BEFORE_CONTRACT_SIGNED`) | §5.5 |
| R5.3 | Offer expiry: a default the organization sets; HR or the offering manager can change it per offer | `offers.default_expiry`: 5 working days, pre-filled at setup (Q46); `offers.expiry_changed_by` | §5.2 |
| R5.4 | Background and criminal record checks only after a conditional offer, as a condition of it | Rule (`CHECK_BEFORE_CONDITIONAL_OFFER`) | §5.3 |
| R5.5 | Any change to offer terms goes back for approval, unless the organization sets otherwise | `offers.reapprove_on_change`: any change | §5.4 |
| R6.1 | The new hire uses the login they keep as an employee, limited to pre-boarding until the start date | `platform.app_user.preboarding_until` | §6.1 |
| R6.2 | Each form has a due date; pre-boarding and payroll information by the first day at the latest; later forms tied to their own event; never later than the law (SIN within 3 days of starting) | Plan items; `sin_due` rule | §6.2 |
| R6.3 | Starter checklists by hire kind, edited by the organization; each department can have its own; training by role | Starter plans | §6.3 |
| R6.4 | Overdue tasks: owner, then the owner's manager, then HR, on days the organization sets | `onboarding.escalation`: owner 2 days before, manager 1 day after, HR 3 days after, pre-filled at setup (Q46) | §6.4 |
| R6.5 | The manager chooses buddies and mentors, CanDo suggests; several per new hire, each for part of the work and the timeline | `recruit.onboarding_support` | §6.5 |
| R6.6 | Welcome videos, check-in surveys, an Indigenous and culturally aligned track and the buddy program: available, off until switched on; the organization says whether each is required | `onboarding.extras`: all off | §6.6 |
| R7.1 | Check-ins per type of probation; starting set 30 days, 60 days and 2 weeks before the end | `probation.check_ins` | §7.1 |
| R7.2 | Many reminders before the end, on the organization's days; leave or holidays near the end shown before a leave is approved; the end date passing with no decision means passed, and HR is told | `probation.end_reminders_days`: 30, 15, 10, 5, 3, 2, 1; FB-034 | §7.2, §7.3 |
| R7.3 | The employer can extend for any reason it records, before the end date, after telling the employee | `probation.non_union_extension_max`: no maximum | §7.4 |
| R7.4 | No warning signs or risk scores during probation; before probation is failed or employment ends, HR reviews any open or recently closed case, or leave | `endings.open_case_review`: **locked**; `endings.closed_case_lookback_months`: 12 (Q47) | §7.5 |
| R7.5 | Conversion to regular starts when a manager asks; organizations can add thresholds; conversions an agreement requires are flagged to HR | `conversion.thresholds`: off | §8 |
| R7.6 | Confirmation letter when probation is passed | `probation.confirmation_letter`: HR sends | §7.6 |
| X1 | Cautions, acknowledgements and a recorded reason when a user overrides on purpose | `cautions.reason_required`, `cautions.approval_required` | §2.1 |
| F1 | No TD1 by the first payroll: tax on the basic personal amount only (CRA's rule), and HR is reminded | FB-028 decided | §9 |
| F2 | No s. 87 exemption recorded: normal deductions; pre-boarding asks, and a yes gives HR a task before the first pay | FB-024 decided | §9 |

---

## 2. How the module is set up

### 2.1 Cautions and acknowledgements (X1)

A caution is a short message, in the user's screen language, that tells them what they are about to go past: a rule of the organization, the law, or a collective agreement. CanDo's cautions are listed in `ref.caution` with their wording in English and French; each says whether it states the law (`shows_law`) and whether a written reason is always needed (`reason_always`).

| Caution | When it appears | Reason |
| --- | --- | --- |
| `recruit.seniority_order_overridden` | Choosing a different order than the agreement's seniority order | Always |
| `recruit.posting_skipped_where_required` | Filling a position without a posting where an agreement or policy requires one | Always |
| `recruit.missing_requirement_advanced` | Moving forward a candidate who has not shown a required qualification | If the organization asks |
| `probation.leave_near_end` | Approving a leave of the employee, or of their manager, near the end of a probation | If the organization asks |
| `probation.extension_past_notice_threshold` | Extending probation past the date the law's notice rights begin | If the organization asks |
| `endings.open_cases` | Failing probation or ending employment while the employee has an open case or leave | Always |
| `conversion.agreement_requires` | Declining or delaying a conversion the agreement requires | Always |

Going past a caution writes a `platform.caution_acknowledgement`: the caution, the subject, the text exactly as it was shown and its language, who acknowledged it, when, and the reason. Acknowledgements are never changed or deleted (`CAUTION_ACK_IMMUTABLE`); the only change allowed is attaching the approval they needed. The organization can ask a reason for more cautions (`cautions.reason_required`) and an approval for some (`cautions.approval_required`); the approval goes through the organization's `caution` route and cannot be given by the person who acknowledged (`SELF_APPROVAL`). The action the caution guards checks `platform.caution_cleared()` and stops with `CAUTION_NOT_ACKNOWLEDGED` until the caution is cleared.

Reminders are not cautions: they are notifications on dates (an offer about to expire, a probation decision due, a union notice to send, a legal due date coming) and need no acknowledgement.

### 2.2 Approval routes the organization builds

Requisitions, direct hires, offers, probation extensions, conversions and caution approvals each follow a route in `platform.workflow_route`. A route has conditions and steps:

- **Conditions** say which subjects it covers, using the facts CanDo knows about the subject: requisition type, employment type, term or ongoing, over budget, offer outside the range or step, filled under a posting exemption, unionized, legal entity, org unit, probation kind, caution, and annual cost from a number. `{}` covers every subject of its type. An unknown condition is refused (`ROUTE_CONDITION_UNKNOWN`).
- **Steps** name who approves: the hiring manager, the requester's manager, the unit head (`docs/21` §4.2), a capability (HR, finance, payroll, labour relations, executive, manager), a role or a named person, with "any" (a number of people) or "all".

CanDo picks the first active route, by priority, whose conditions match (`platform.route_for()`). If a condition needs a fact the caller did not give, it stops (`ROUTE_FACT_MISSING`); if nothing matches, it stops (`ROUTE_NOT_FOUND`). Nothing is approved by a default route. A subject is approved only when every step has its approvals from people other than the requester and no task is rejected (`platform.route_complete()`; `ROUTE_APPROVALS_MISSING`). No one approves their own requisition, offer, extension, conversion or caution (`SELF_APPROVAL`).

Starter routes (§3.4, §5.1, §7.4, §8) are copied to each organization, which edits, adds or retires them at any time. A route with no steps is allowed: it is the organization's choice that a kind of subject needs no approval.

### 2.3 Settings

| Setting | Decides | CanDo default | Set per |
| --- | --- | --- | --- |
| `recruit.direct_hire` | Whether hiring without a requisition is allowed (through the direct-hire route) | Allowed with route | Organization, employer |
| `recruit.posting_default` | Whether a requisition needs a posting unless an exemption rule applies | Required | Organization, employer |
| `recruit.screening_owner` | Who screens and sees applicants first: HR, the department or both | **None: chosen at setup** | Organization, employer |
| `recruit.ai_match` | AI match suggestions | Off | Organization |
| `recruit.missing_requirement` | Starting choice for candidates missing a required qualification: flag or screen out | **None: chosen at setup** | Organization, employer |
| `recruit.posting_audience` | Starting audience of a posting | Internal and public at once | Organization, employer |
| `recruit.posting_pay_shown` | Pay shown on postings | On | Organization, employer |
| `recruit.posting_pay_basis` | What pay is shown: range, incumbents' average, market point, other | Range | Organization, employer |
| `recruit.incumbent_average_min` | Fewest incumbents for showing their average | 3, never lower | Organization |
| `recruit.apply_agreement_seniority` | The agreement's seniority order applied in selection | On | Organization, employer |
| `recruit.applicant_contact` | Contact needed to apply without an account | Email or phone | Organization |
| `recruit.candidate_retention` | How long candidate records are kept: per province or the longest of all, plus the organization's own minimum | **None: chosen at setup** | Organization |
| `recruit.interview_scoring` | Every interview scored, or optional | **None: chosen at setup** | Organization, employer |
| `recruit.blind_screening` | Blind screening | Off | Organization, employer |
| `offers.default_expiry` | How long an offer stays open by default | 5 working days, pre-filled at setup | Organization, employer |
| `offers.expiry_changed_by` | Who can change the expiry on one offer | HR and the offering manager | Organization |
| `offers.reapprove_on_change` | Which changes to approved terms go back for approval | Any change | Organization, employer |
| `onboarding.escalation` | Days for reminding the owner, telling their manager and telling HR | Owner 2 days before, manager 1 day after, HR 3 days after, pre-filled at setup | Organization, employer |
| `onboarding.extras` | Welcome videos, check-in surveys, cultural track, buddy program: on or off, required or not | All off | Organization, employer |
| `probation.check_ins` | Check-ins per kind of probation | 30 days, 60 days, 2 weeks before the end | Organization, employer |
| `probation.end_reminders_days` | Days before the end when the manager and HR are reminded | 30, 15, 10, 5, 3, 2, 1 | Organization, employer |
| `probation.non_union_extension_max` | Longest total extension of a non-union probation | No maximum | Organization, employer |
| `probation.confirmation_letter` | Letter when probation is passed: HR sends, sent automatically, or none | HR sends | Organization, employer |
| `conversion.thresholds` | Thresholds that flag people for conversion to regular | Off | Organization, employer |
| `cautions.reason_required` | More cautions that need a written reason | None | Organization |
| `cautions.approval_required` | Cautions that also need an approval | None | Organization |
| `endings.open_case_review` | HR reviews open and recently closed cases and leave before an ending | **Locked: on** | — |
| `endings.closed_case_lookback_months` | How far back a closed case still needs HR's review before an ending | 12 months (never negative) | Organization, employer |

### 2.4 Chosen at setup

Four settings have no CanDo default because the owner left them to each organization: `recruit.screening_owner`, `recruit.missing_requirement`, `recruit.candidate_retention` and `recruit.interview_scoring`. The setup wizard asks each one; until it is answered, the feature that needs it stops with `SETTING_NOT_SET` (`docs/22` FB-003). For offer expiry and onboarding escalation the setup screen pre-fills CanDo's suggested numbers, which the organization can change (Q46, decided 25 Oct 2026).

---

## 3. Requisitions

### 3.1 A requisition before every hire; direct hire (R1.3, R2.7)

Every hire starts from a requisition on a position (`docs/21` §5.1), except a direct hire. A direct hire is an offer with `hire_path = direct_hire`, naming the candidate and the position, approved through the organization's `direct_hire` route. An organization can forbid direct hires (`recruit.direct_hire = not_allowed`; `DIRECT_HIRE_NOT_ALLOWED`).

### 3.2 What a requisition holds (R1.3, R2.4)

- Type (the organization's requisition types mapped to replacement, additional headcount or new position), the position, and for a replacement the employment it replaces.
- Employment type (the organization's own types, `docs/22` §3.4), FTE, target start and, for term, fixed-term, seasonal and student hires, the end date. Full-time or part-time is the FTE.
- Funding: one or more lines in `recruit.requisition_funding`, each with its GL segments (cost centre, fund, program, funder) and, where it applies, a funding source, with shares that add up to 100 (`REQUISITION_FUNDING_MISSING`, `REQUISITION_FUNDING_NOT_100`). One position can have several funders (`docs/17` §8).
- Required certifications and qualifications: the position's and job's requirements (`docs/18` §6), shown on the requisition and used in screening (§4.6).
- A new position also carries its job description, pay grade and budget for approval in the same route (`docs/21` §5 and §6.3).

A requisition is submitted with its requester, employment type and route (`INPUT_REQUIRED`). Over budget or over complement follows `docs/21` §5.2 and the `overBudget` route condition.

### 3.3 Hiring without a posting (R2.8)

By default a requisition is posted (`recruit.posting_default = required`). The organization writes its own exemption rules in `recruit.posting_exemption_rule`, each in one category: a candidate the manager already has in mind, someone from the talent pool, extra duties for a current employee as a second position (`docs/20`), on-call staff, or other; a rule can be limited to some employment types. A requisition filled under an exemption names the rule (`POSTING_EXEMPTION_UNKNOWN` if it is not active). An offer on a requisition with no posting and no exemption stops (`POSTING_REQUIRED`).

When a collective agreement or a policy requires a posting for the position, CanDo lists them on the requisition (`posting_required_by`) and the approver must acknowledge `recruit.posting_skipped_where_required` with a reason before approving. The organization's route can add approvals for exemptions with the `postingExemption` condition.

### 3.4 Starter routes (R2.1, R2.2, R2.3)

| Route | Covers | Steps |
| --- | --- | --- |
| `req_over_budget` | Any requisition over budget | Department head; HR (job description and pay grade); finance (budget, with the written reason) |
| `req_additional_headcount` | Additional headcount | Department head; HR; finance; executive |
| `req_new_position` | New position | Department head; HR (job description and pay grade); finance (budget) |
| `req_replacement` | Replacement | HR |
| `direct_hire` | Direct hire | Department head; HR |

Term requisitions follow the same routes; an organization wanting lighter routes for term hires adds a route with the `term` condition. Recruiting to replace someone who resigned can start once the resignation is recorded: the requisition can be raised from that date. A handover period with the person leaving is an `overlap` assignment on the position.

---

## 4. Postings and selection

### 4.1 Audience and channels (R3.1, R3.5, R1.2)

Each posting chooses its audience: internal and public at once (the starting choice from `recruit.posting_audience`), internal first for a number of days (from the agreement's `internal_posting_days` where there is one), internal only, or public only. Channels are the organization's `posting_channel` list, mapped to job boards through CanDo's posting partner, its own career page, Google for Jobs, Indeed's free listings, professional and regulatory bodies (for example engineers' or physicians' associations), or other. Job boards, assessments, video interviews and e-signature are provider integrations (`docs/11`).

### 4.2 Pay on postings (R3.2, R3.6)

Pay is shown by default (`recruit.posting_pay_shown`). The employer can remove it only where the law of the posting's jurisdiction allows: the posting validator (Step 14) reads `pay_transparency` in the employment standards edition and blocks a public posting without pay in Ontario (employers of 25 or more, range no wider than $50,000), British Columbia and Prince Edward Island, and removes pay-history questions where they are banned (British Columbia; Newfoundland and Labrador). What is shown is the employer's choice within those rules (`recruit.posting_pay_basis`): a range from the pay structure (`docs/19` §7.7), the average of current incumbents, a market point such as the 75th percentile, or another value.

The incumbents' average is offered only when the job has at least `recruit.incumbent_average_min` current incumbents (3, never lower, so no one's own pay can be worked out). When there are fewer, HR, or whoever builds the posting, sees why the option is not available; publishing with it stops (`INCUMBENT_AVERAGE_UNAVAILABLE`). A posting is published only on an approved requisition (`POSTING_REQUISITION_NOT_APPROVED`) and a range states its minimum, maximum and unit.

### 4.3 Collective agreements in selection (R3.3, R3.4, R3.7)

Where an agreement sets a selection rule, CanDo applies it as the organization has set it up: by default the agreement's seniority order (`recruit.apply_agreement_seniority`, copied to each posting as `seniority_applies`). The organization can switch it off, or override it on a posting; overriding needs the caution `recruit.seniority_order_overridden` with a written reason, and the approval the organization asks for (`cautions.approval_required`). When an agreement requires notice to the union of a posting or a result, HR sends it and CanDo reminds HR; CanDo does not write to the union itself.

### 4.4 Applying (R4.1)

No account is needed to apply. A candidate gives at least an email or a phone number (`candidate_contact`), or what the organization asks for (`recruit.applicant_contact`; `CANDIDATE_CONTACT_REQUIRED`). The employer adds its own questions to each posting (`recruit.posting_question`: multiple choice, yes or no, date, number, text), each optional or mandatory; answers are kept with the application. A candidate can choose to join the talent pool (`talent_pool_consent`, off unless they say yes), which authorized users search for other positions.

### 4.5 How long candidate records are kept (R4.2)

At setup the organization chooses (`recruit.candidate_retention`): the law of the posting's jurisdiction (`per_province`), or the longest period of every jurisdiction where it has a location (`longest_for_all`), and its own minimum after the decision (`organizationMonths`). When an application is decided, CanDo works out its `retention_until`: the later of the organization's minimum and each jurisdiction's minimum from `candidate_records_retention` in the rules (for example British Columbia one year after the decision; Ontario three years after the posting is taken down). The candidate keeps the latest date of its applications; interview notes and scores are kept as long as the applications. A jurisdiction without a verified rule stops the decision (`JURISDICTION_RULE_MISSING`, `RULE_NOT_VERIFIED`); a rule counted from the posting's closing date needs that date (`INPUT_REQUIRED`). Purging or anonymizing after the date, unless the candidate is in the talent pool, is a scheduled job (Step 18).

### 4.6 Screening (R1.4, R1.5, R2.5, R4.4)

- **Who screens:** HR, the department or both, chosen at setup (`recruit.screening_owner`). A hiring manager sees the applicants for their own requisitions as the setup allows.
- **Missing qualifications:** each posting says whether a candidate who has not shown a required qualification is flagged for a person to decide or screened out (`missing_requirement`, starting from the organization's choice at setup). Moving a flagged candidate forward shows the caution `recruit.missing_requirement_advanced`.
- **Decisions are people's:** every outcome names who decided and when (`APPLICATION_DECISION_UNSIGNED`). The only decision not made by a person is a screen-out by the posting's own rule when the posting is set to screen out and the candidate lacks a required qualification (`REQUIREMENT_RULE_NOT_ALLOWED` otherwise). There is no AI or assistant decider.
- **AI match suggestions:** off until the organization switches them on (`recruit.ai_match`; `MATCH_SUGGESTIONS_OFF`). The employer sets the criteria and their weights on each posting; a score always shows its reasons (`MATCH_WITHOUT_REASONS`); suggestions never use protected grounds or self-identification (AGENTS rule 33). Resume reading fills the application for the candidate to confirm. When suggestions are on, the posting validator adds the AI notice where the law requires it (Ontario).
- **Blind screening:** off by default (`recruit.blind_screening`); when on, screeners do not see names, photos or other identifying details until the organization's chosen stage.

### 4.7 Interviews (R4.3)

Interview kits come from the organization's question banks. Whether every interview is scored before a decision is chosen at setup (`recruit.interview_scoring`; `INTERVIEW_SCORE_REQUIRED` when it is `every_interview`). A submitted score is locked (`SCORE_LOCKED`); a panelist sees the others' scores only after submitting their own. Ontario's notice to interviewed applicants within 45 days comes from the rules (`pay_transparency.applicant_outcome_notice_days`) as a task for HR.

### 4.8 Messages to candidates (R2.6)

Messages come from the organization's templates (`recruit.message_template`) for each purpose (not selected, shortlisted, interview invitation, offer, talent pool, general), in its own words. A template either includes a reason or does not; a mass message from a template that includes one needs the reason (`MESSAGE_REASON_REQUIRED`). Each batch is recorded with who sent it, when and to how many.

### 4.9 Internal applicants (R4.5)

An internal applicant decides when to tell their manager; nothing is sent to the manager when they apply. When the offer is accepted, CanDo adds the condition "tell the current supervisor" to the offer. Whether the move is an internal transfer or a resignation and rehire depends on the organization and the position, and is stated on the offer before the hire (`internal_move`; `INPUT_REQUIRED`). Extra duties as a second position use `docs/20`.

---

## 5. Offers

### 5.1 Approvals (R5.1)

Each offer is submitted with its route (`INPUT_REQUIRED`) and approved only when the route is complete (`ROUTE_APPROVALS_MISSING`). Starter routes: `offer_outside_range` (HR, then finance) for pay outside the grade range or the agreement's step, and `offer_standard` (HR) for the rest. For union positions the pay step comes from the agreement's grid (`docs/08`). The approved terms are kept (`approved_terms`).

### 5.2 Expiry (R5.3)

The organization sets how long an offer stays open (`offers.default_expiry`, pre-filled with 5 working days at setup, in working or calendar days); HR or the offering manager can change it on each offer (`offers.expiry_changed_by`). An offer is sent once approved, with its expiry date and who set it (`OFFER_NOT_READY`). The candidate and the offering manager are reminded before it expires; an expired offer is `expired`.

### 5.3 Conditional offers and checks (R5.4)

An offer says whether it is conditional. Background, criminal record, reference, credential, licence and medical checks are conditions of a conditional offer only (`CHECK_NEEDS_CONDITIONAL_OFFER`). They start only after the offer has been sent (`CHECK_BEFORE_CONDITIONAL_OFFER`), and a background or criminal record check needs the candidate's signed consent (`CONSENT_REQUIRED`). Reference checks an organization does before deciding to make an offer belong to selection, not to the offer. Checks run through providers; each condition is pending, requested, met, not met or waived, with who decided. Open conditions are counted with `recruit.open_conditions()` before the start date.

### 5.4 Changed terms (R5.5)

Any change to approved terms goes back through the offer's route (`offers.reapprove_on_change = any_change`; `OFFER_CHANGE_NEEDS_APPROVAL`), and approvals given before the change do not count. An organization can limit re-approval to a higher pay rate or a different start date, or switch it off.

### 5.5 The employee record after the contract is signed (R5.2)

Accepting an offer is not yet a hire. The employee record (the hire change set, `REC-008`) is created when the offer is accepted **and** the contract is signed (`HIRE_BEFORE_CONTRACT_SIGNED`); a contract is signed only on an accepted offer (`CONTRACT_BEFORE_ACCEPTANCE`). Creating the record asks for the information the job needs (position, rate, start date, pay group, probation from `docs/21` §3.2) and carries the candidate's data without retyping. Pre-boarding opens at the same moment (§6.1).

---

## 6. Pre-boarding and onboarding

### 6.1 One login (R6.1)

When the contract is signed the new hire gets the CanDo login they will keep as an employee. Until the start date (`platform.app_user.preboarding_until`) they see only pre-boarding screens.

### 6.2 Forms and due dates (R6.2)

Each item of an onboarding plan has a due date counted from an event: the contract signing, the start date, the first pay, the start of benefits or the end of probation. Pre-boarding and payroll items are due by the first day at the latest (`PREBOARDING_DUE_AFTER_START`); later items, such as benefits enrolment when benefits start after three months, are due on their own event, set when that date is known. A due date can be earlier than the law but never later: the SIN is due within 3 days of starting (`sin_due`, a rule for every employer in Canada), so its task gets a `legal_due_date` (`DUE_AFTER_LEGAL_DATE`) and cannot be waived (`LEGAL_TASK_CANNOT_BE_WAIVED`). HR is reminded before a legal date passes. A completed task names who completed it and when (`TASK_COMPLETION_UNSIGNED`).

The forms CanDo knows: SIN, federal TD1, the provincial form (the province's TD1, or TP-1015.3 in Quebec), direct deposit, emergency contacts, proof of the right to work, the Indian Act s. 87 question, policy acknowledgements, voluntary self-identification (never required: `plan_item_self_id_voluntary`) and benefits enrolment. What happens when a TD1 or the s. 87 answer is missing is in §9.

### 6.3 Checklists (R6.3)

Onboarding plans (`recruit.onboarding_plan`) are the organization's. Each is for one hire kind (new hire, rehire, internal transfer, student, contractor, other) and a scope (`applies_to`: org units, jobs, locations, provinces, agreements, employment types; `{}` is everyone of that kind). A new hire gets the tasks of **every** active plan that applies, so organization-wide items (orientation), department items (IT's own training, health and safety training for safety staff) and role items combine; an item in several plans becomes one task with the earliest due date (`recruit.generate_onboarding_tasks()`). Each item has an owner (the new hire, HR, payroll, IT, facilities, finance, the hiring manager, learning, security, communications, a buddy), a due event and offset, an optional dependency and whether it is required.

CanDo copies five starter plans to each organization (new hire, rehire, internal transfer, student, contractor) with their items in English and French; the organization edits them, adds department plans and retires what it does not use, at any time.

### 6.4 Overdue tasks (R6.4)

Before a task is due its owner is reminded; when it is overdue, the owner's manager is told, then HR, each after the number of days the organization sets (`onboarding.escalation`, pre-filled at setup with 2 days before, 1 day after and 3 days after; `recruit.tasks_to_escalate()`).

### 6.5 Buddies, mentors and trainers (R6.5)

The manager chooses; CanDo suggests people in the same unit, then the same location (`recruit.suggest_supporters()`). A new hire can have several buddies, mentors and trainers, each for a part of the work (a function or a task, written by the manager) and a period (`recruit.onboarding_support`). A buddy needs the buddy program switched on (`FEATURE_OFF`); no one supports themselves (`SUPPORT_SELF`).

### 6.6 Optional extras (R6.6)

Welcome videos, check-in surveys on the organization's days, an Indigenous and culturally aligned track, and the buddy program are available and stay off until the organization turns each on, saying whether it is required (`onboarding.extras`). Plan items tied to an extra are left out while it is off.

---

## 7. Probation

Kinds and lengths of probation are in `docs/21` §3.2 (per bargaining unit; non-union 3 months by default; trial periods). This section adds what happens during and after it.

### 7.1 Check-ins (R7.1)

Each organization sets the check-ins for each kind of probation (`probation.check_ins`), counted from the start or back from the end; the starting set is 30 days, 60 days and 2 weeks before the end. An agreement's own schedule wins for its probations. Check-ins are recorded in `core.probation_check_in` with the manager's and employee's signatures; the manager is reminded to complete and sign them.

### 7.2 Reminders and the end date (R7.2)

The manager and HR are reminded before the end on the organization's days (`probation.end_reminders_days`, starting 30, 15, 10, 5, 3, 2 and 1 days before). If the end date passes and no decision is recorded, the probation is **passed on its end date and HR is told** (`core.close_lapsed_probations()`, run daily; `docs/22` FB-034). Legally the probation is over, and the file must not say otherwise. A probation counted in hours, days or shifts ends when its counter reaches the amount (`docs/21` §3.2); asking for its calendar end is an error (`PROBATION_MEASURE_COUNTED`).

### 7.3 Leave and holidays near the end (R7.2)

When a leave of the probationary employee, or of their manager, falls in the decision window (from the first reminder day to the end date), the approver sees the caution `probation.leave_near_end` before approving, with the end date and the statutory holidays in the window (`core.probation_leave_caution()`; `HOLIDAY_CALENDAR_MISSING` when a work location has no holiday calendar). For a probation counted in hours, days or shifts, any leave shows the caution, since the agreement may move its end.

### 7.4 Extensions (R7.3)

The employer can extend probation for any reason it chooses, and the reason is recorded (`core.probation_extension`). An extension goes through the organization's route (starter: HR), and takes effect only when the employee has been told (`EXTENSION_NOT_COMMUNICATED`), on or before the end date (`EXTENSION_AFTER_END`). The agreement's maximum applies to union probations; the organization can set one for others (`probation.non_union_extension_max`, none by default; `EXTENSION_ABOVE_MAXIMUM`). When the agreement requires notice to the union, HR is reminded. Extending past the date the law's notice rights begin (the first band of `termination_notice` in the rules, for example 3 months in Ontario and British Columbia) shows the caution `probation.extension_past_notice_threshold`: extending probation does not delay those rights. When the extension takes effect the probation gets a new version with the longer period.

### 7.5 Open cases before an ending (R7.4)

There are no warning signs or risk scores during probation. Before probation is failed or employment ends, CanDo looks for any open matter of the employee (`core.open_matters()`): an open case they are the subject of or brought (accommodation, return to work, workers' compensation claim, grievance, investigation, complaint about human rights, employment standards or harassment, warning letter or discipline, pay equity, privacy request, other), and any leave requested, approved or under way. A case closed within the last 12 months also counts (`endings.closed_case_lookback_months`, which the organization can change), because protection against reprisal can outlast a case (Q47). When there is one, an HR approver of the change acknowledges `endings.open_cases` with a reason before it can be approved (`OPEN_CASES_NOT_REVIEWED`), so the decision does not breach the law, for example as a reprisal. This cannot be switched off (`endings.open_case_review`, locked).

When a case names someone as respondent (`compliance.case_party`), for example a complaint against the manager, that person sees only that HR must review (`core.viewer_is_case_respondent()`), never the case. Details are for HR.

### 7.6 Confirmation letter (R7.6)

When probation is passed, CanDo prepares a confirmation letter from the organization's template (`probation.confirmation_letter`): HR sends it, it is sent automatically, or there is none.

---

## 8. Status conversion (R7.5)

A conversion from temporary, casual or auxiliary to regular starts when a manager asks (`core.status_conversion_request`, `started_by = manager_request`) and goes through the organization's route (starter: HR, then finance for the budget). An organization can set thresholds in `conversion.thresholds` (for example 12 months of regular hours) so CanDo flags people who reach them; a person decides (`CONVERSION_THRESHOLDS_OFF` while none are set). Where a loaded collective agreement requires a conversion, CanDo flags it to HR whatever the thresholds; declining or delaying it needs the caution `conversion.agreement_requires` with a reason. The conversion itself is an effective-dated change set (`REC-012`), with seniority and benefits recalculated as the agreement says.

---

## 9. Fallbacks decided in this review

| ID | When | CanDo does |
| --- | --- | --- |
| FB-028 | No federal or provincial TD1 by the first payroll | Tax on the basic personal amount only (claim code 1), as CRA requires; HR is reminded to collect the form (F1) |
| FB-024 | No Indian Act s. 87 exemption recorded | Normal deductions until HR records the exemption with its basis; pre-boarding asks every new hire, and a yes gives HR a task due before the first pay (F2) |
| FB-034 | A calendar probation reaches its end date with no decision | Passed on the end date; HR is told (R7.2) |
| FB-035 (proposed) | Migration 0009 meets an organization that keeps a language other than English or French as required for its data | Its starters are not copied, and the migration says so; HR adds them with their texts (§10) |

The register is `rules/register/values-and-fallbacks.json`; `docs/22` §5 lists every fallback.

---

## 10. Data model (migration 0009)

| Object | What it holds |
| --- | --- |
| `ref.caution`, `platform.caution_acknowledgement`, `platform.caution_cleared()` | Cautions and who went past them (§2.1) |
| `platform.workflow_route`, `platform.workflow_route_step`, `route_for()`, `route_matches()`, `route_complete()` | Routes the organization builds (§2.2); `approval_task.capability` gains `executive` |
| `ref.employment_standard()`, `ref.notice_threshold_date()` | Values from the active employment standards edition, strictly (`JURISDICTION_RULE_MISSING`, `RULE_NOT_VERIFIED`) |
| `recruit.requisition` (new columns), `recruit.requisition_funding`, `recruit.posting_exemption_rule` | §3 |
| `recruit.posting`, `recruit.posting_channel`, `recruit.posting_question`, `recruit.incumbent_count()` | §4.1 to §4.3; a posting names its employer, and its starting values come from that employer's settings through `platform.column_default` |
| `recruit.candidate` (email optional, talent pool consent), `recruit.application` (decisions, retention), `recruit.retention_until()`, `recruit.application_answer`, `recruit.interview`, `recruit.interview_score`, `recruit.message_template`, `recruit.message_batch` | §4.4 to §4.9 |
| `recruit.offer` (new columns), `recruit.offer_condition`, `recruit.open_conditions()` | §5 |
| `platform.app_user.preboarding_until`, `recruit.onboarding_plan`, `recruit.onboarding_plan_item`, `recruit.onboarding_task` (new columns), `plans_for()`, `generate_onboarding_tasks()`, `tasks_to_escalate()`, `recruit.onboarding_support`, `suggest_supporters()` | §6 |
| `core.probation_calendar_end()`, `core.probation_check_in`, `probation_check_in_dates()`, `probation_reminders_due()`, `close_lapsed_probations()`, `core.probation_extension`, `probation_leave_caution()` | §7.1 to §7.4 |
| `compliance.case_party`, `core.open_matters()`, `core.viewer_is_case_respondent()`, change-set check `change_set_3_open_matters`; case kinds gain the categories complaint and discipline | §7.5 |
| `core.status_conversion_request` | §8 |
| `ref.workflow_route_starter`, `ref.workflow_route_step_starter`, `ref.onboarding_plan_starter`, `ref.onboarding_plan_item_starter`, list `posting_channel`; `core.seed_tenant()` copies them | Starter copies each organization edits |

Every new tenant table has `tenant_id` with forced row-level security; text fields are registered as translatable (`docs/22` §4.3). Existing organizations get the starters when 0009 runs, except one that keeps another language as required for its data (FB-035): the migration names it, and HR adds the starters with their texts or copies them with `core.seed_tenant()` once its texts can be completed.

---

## 11. Validation, API and events

**Errors added by 0009:** `CAUTION_REASON_REQUIRED`, `CAUTION_ACK_IMMUTABLE`, `CAUTION_NOT_ACKNOWLEDGED`, `ROUTE_CONDITION_UNKNOWN`, `ROUTE_FACT_MISSING`, `ROUTE_NOT_FOUND`, `ROUTE_APPROVALS_MISSING`, `REQUISITION_FUNDING_MISSING`, `REQUISITION_FUNDING_NOT_100`, `POSTING_EXEMPTION_UNKNOWN`, `POSTING_REQUISITION_NOT_APPROVED`, `INCUMBENT_AVERAGE_UNAVAILABLE`, `POSTING_REQUIRED`, `CANDIDATE_CONTACT_REQUIRED`, `MATCH_SUGGESTIONS_OFF`, `MATCH_WITHOUT_REASONS`, `APPLICATION_DECISION_UNSIGNED`, `REQUIREMENT_RULE_NOT_ALLOWED`, `INTERVIEW_SCORE_REQUIRED`, `SCORE_LOCKED`, `MESSAGE_REASON_REQUIRED`, `DIRECT_HIRE_NOT_ALLOWED`, `OFFER_CHANGE_NEEDS_APPROVAL`, `OFFER_NOT_READY`, `OFFER_NOT_SENT`, `CONTRACT_BEFORE_ACCEPTANCE`, `HIRE_BEFORE_CONTRACT_SIGNED`, `CHECK_NEEDS_CONDITIONAL_OFFER`, `CHECK_BEFORE_CONDITIONAL_OFFER`, `CONSENT_REQUIRED`, `ONBOARDING_SCOPE_UNKNOWN`, `DUE_AFTER_LEGAL_DATE`, `PREBOARDING_DUE_AFTER_START`, `LEGAL_TASK_CANNOT_BE_WAIVED`, `TASK_COMPLETION_UNSIGNED`, `SUPPORT_SELF`, `FEATURE_OFF`, `PROBATION_UNKNOWN`, `PROBATION_MEASURE_COUNTED`, `PROBATION_AMOUNT_NOT_WHOLE`, `PROBATION_NOT_OPEN`, `EXTENSION_NOT_APPROVED`, `EXTENSION_NOT_COMMUNICATED`, `EXTENSION_AFTER_END`, `EXTENSION_ABOVE_MAXIMUM`, `EXTENSION_MEASURE_DIFFERS`, `HOLIDAY_CALENDAR_MISSING`, `OPEN_CASES_NOT_REVIEWED`, `CONVERSION_THRESHOLDS_OFF`. Existing ones used: `SETTING_NOT_SET`, `SETTING_BELOW_MINIMUM`, `SETTING_LOCKED`, `SETTING_VALUE_NOT_ALLOWED`, `SELF_APPROVAL`, `INPUT_REQUIRED`, `LIST_VALUE_UNKNOWN`, `JURISDICTION_RULE_MISSING`, `RULE_NOT_VERIFIED`.

**Checks in the application (Step 14), not the database:** the posting validator by jurisdiction (REC-003) from `pay_transparency`; internal-first days from the agreement; the seniority order (REC-004); Ontario's 45-day notice (REC-005); blind screening and who sees applicants; expiry counted in working days and who may change it; the leave caution on every leave approval screen, for the employee's and the manager's leave; union notice reminders; the confirmation letter; threshold flags for conversion; due dates for later events.

**API** (added to `api/openapi.yaml` in Step 14): `GET/POST /workflow-routes` and steps; `POST /cautions/acknowledgements`; requisitions with funding and `submit`, `approve`; `posting-exemption-rules`; postings with channels, questions, `publish`; candidates and public `apply` without an account; applications with `decide`; interviews and scores with `submit`; message templates and batches; offers with `submit`, `approve`, `send`, `accept`, `sign-contract`, conditions; onboarding plans and items; `POST /employments/{id}/onboarding/generate`; onboarding tasks with `complete`; supporters and suggestions; probation check-ins, extensions with `approve`, `notify-employee`, `apply`; `GET /employments/{id}/open-matters` (HR only); status conversion requests.

**Events** (added to `api/events.yaml` in Step 14; identifiers only, AGENTS rule 9): `caution.acknowledged`, `requisition.approved`, `posting.published`, `application.decided`, `offer.approved`, `offer.sent`, `offer.accepted`, `offer.contract_signed`, `offer.expired`, `onboarding.task_overdue`, `onboarding.legal_due_soon`, `probation.reminder_due`, `probation.extended`, `probation.lapsed_passed`, `probation.leave_caution_shown`, `status_conversion.flagged`.

---

## 12. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| REC-015 | An override past a caution that needs a reason | Refused without a reason; recorded with the text shown; never changed | smoke 2 | 1, 14 |
| REC-016 | The organization asks an approval for a caution; the acknowledger approves it | Refused (`SELF_APPROVAL`); cleared after someone else approves | smoke 2d | 1, 14 |
| REC-017 | Routes chosen by priority and conditions; a fact missing; no route | First match; `ROUTE_FACT_MISSING`; `ROUTE_NOT_FOUND` | smoke 3 | 1, 4 |
| REC-018 | Requisition funded 60/30 by two cost centres, then 60/30/10 | Refused at 90; submitted at 100 | smoke 4a–b | 14 |
| REC-019 | Named candidate hired without posting where the agreement requires one | Approval stops until the caution is acknowledged with a reason | smoke 4e | 14 |
| REC-020 | Posting created before the organization chose how missing qualifications are handled | `SETTING_NOT_SET`; after setup, the posting starts from the settings | smoke 5a–b | 1, 14 |
| REC-021 | Posting shows the incumbents' average with 2 incumbents | `INCUMBENT_AVERAGE_UNAVAILABLE`; HR sees why | smoke 5c | 14 |
| REC-022 | AI score stored while suggestions are off; rule screen-out on a flagging posting | Both refused | smoke 7a, 7c | 14 |
| REC-023 | Ontario application decided; Alberta location with an unverified rule | Kept 3 years after the posting closed; Alberta stops with `RULE_NOT_VERIFIED` | smoke 7e–j | 14, 18 |
| REC-024 | Approved offer's pay changed | Back to approval; old approvals do not count | smoke 8g | 14 |
| REC-025 | Criminal record check before the offer is sent, or without consent | Refused | smoke 8e, 8h | 14 |
| REC-026 | Offer accepted, contract not signed, hire attempted | `HIRE_BEFORE_CONTRACT_SIGNED`; hire allowed once signed | smoke 8j | 14 |
| REC-027 | Internal applicant accepts | "Tell the current supervisor" added; transfer or resignation stated before the hire | smoke 8k | 14 |
| REC-028 | New hire starting 2 November: tasks generated | 22 tasks from the starter plan (extras off left out); SIN due by 2 November, legally by 5 November, never waived | smoke 9a–d | 14 |
| REC-029 | New hire says yes to the s. 87 question | HR task due before the first pay; deductions continue until HR records the exemption | smoke 9f | 9, 14 |
| REC-030 | Buddy, trainer and mentor for one new hire | All three kept, each with its part and period; buddy refused while the program is off | smoke 9g | 14 |
| REC-031 | TD1 two days overdue; personnel file three days overdue | Owner's manager told; HR told | smoke 9h | 14 |
| REC-032 | Probation of 3 months from 5 January | Ends 4 April; check-ins 4 February, 6 March, 21 March; reminder on 30 March | smoke 10a–c | 5, 14 |
| REC-033 | Leave from 30 March to 2 April | Caution with the end date and Good Friday | smoke 10d | 11, 14 |
| REC-034 | Extension told after the end date; extension past Ontario's 3-month threshold | `EXTENSION_AFTER_END`; caution needed; applied as a new version | smoke 10f | 14 |
| REC-035 | Second extension above the organization's maximum | `EXTENSION_ABOVE_MAXIMUM` | smoke 10g | 14 |
| REC-036 | End date passes with no decision | Passed on the end date, HR told (FB-034) | smoke 10h | 14 |
| REC-037 | Termination of an employee with an open complaint against the manager | Stops until an HR approver acknowledges; the manager sees only "HR review required" | smoke 11 | 14, 16 |
| REC-038 | Agreement-required conversion declined | Needs the caution and a reason | smoke 12b | 14 |
| REC-039 | Grievance closed three months before an ending | Counts as an open matter; not counted when the organization's look-back is 2 months | smoke 11e | 14, 16 |

---

## 13. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/02` | Points here at the top; the Bubble implementation, mandatory risk scores, automatic AI ranking, the 30-60-90 default as a fixed rule, background checks before an offer and "acceptance creates the employee" are replaced by §4 to §8 |
| `stories/02` | REC-002 routes per §2.2; REC-007 re-approval per §5.4; REC-008 the record after the contract is signed (§5.5); REC-009 pre-boarding forms and due dates (§6.2); REC-010 plans and escalation (§6.3, §6.4); REC-011 check-ins, reminders, extensions and the end date (§7); REC-012 conversion starts with a manager (§8); REC-013 retention per §4.5; REC-014 no disparate-impact job that ranks people, AI off by default (§4.6). New REC-015 to REC-039 in §12 |
| `docs/15` Step 14 | Read this document; build on migration 0009; pass REC-001 to REC-039 |
| `docs/16` | Settings chosen at setup listed; Q46 and Q47 added; FB-024 and FB-028 decided |
| `docs/21` §3.2 | Check-ins, reminders, extensions and the end date passing are here (§7) |
| `docs/22` | FB-024 and FB-028 decided; FB-034 and FB-035 added; settings from 0009 are listed here, not in docs/22 §2 |
| `AGENTS.md` | Reading order item 10; rules 46 and 47; Step 1 migration 0009 and its smoke test; Step 14 |
| `.cursor/rules/00-cando.mdc` | Rules 46 and 47 in short |
| `docs/13` §3 | The caution-and-acknowledgement dialog and reminders as patterns every screen follows |
| `rules/employment-standards` | `ca-2026-recruitment-additions.json` merged into the edition in Step 7 |
| `tests/hardcoding/check_values.py` | Reads this document for settings |

Where a listed document still says otherwise, this document wins.

---

## 14. Open questions

| # | Question | Until decided |
| --- | --- | --- |
| Q45 | ~~Price of CanDo's translation service~~ **Decided (25 Oct 2026):** per word translated (AI cost plus margin), quoted and approved by the organization before each job (`docs/22` §4.6) | — |
| Q46 | ~~Starting numbers in the setup wizard~~ **Decided (25 Oct 2026):** pre-filled and editable: offers open 5 working days; task owner reminded 2 days before, manager told 1 day after, HR 3 days after | — |
| Q47 | ~~Recently closed cases before an ending~~ **Decided (25 Oct 2026):** cases closed in the last 12 months also trigger HR's review; each organization can change the 12 | — |

---

## Sources

- Canada Revenue Agency, Get the social insurance number from the individual: https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/payroll/set-up-new-employee/social-insurance-number.html
- Employment and Social Development Canada, Employer information on the SIN: https://www.canada.ca/en/employment-social-development/programs/ei/ei-list/ei-employers-sin.html
- British Columbia, Personal Information Protection Act, s. 35 (retention after a decision); secondary summary: https://www.rbs.ca/publications/privacy-in-the-workplace/
- Ontario, new job posting requirements in force 1 January 2026: https://www.hcamag.com/ca/specialization/employment-law/new-job-posting-requirements-for-ontario-employers-take-effect/560964
- Pay transparency laws across Canada, 2026 employer guide (secondary): https://employmenthero.com/en-ca/blog/pay-transparency-laws
