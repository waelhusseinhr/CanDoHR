# Stories · 02 Recruitment & Onboarding

Requirements: `requirements/02-recruitment-onboarding.md`. Decisions: `docs/23-recruitment-onboarding-decisions.md`, which wins where a story here differs (owner's review, 25 October 2026). Scenarios REC-015 to REC-039 are in `docs/23` §12.

**REC-001 — Requisition from a position.** As a hiring manager, I want to open a requisition on a vacant position, so that headcount and budget are already approved.
- AC1: Given a vacant active position, when I create a requisition, then title, unit, location, agreement, grade range and FTE prefill from the position as of the target start date.
- AC2: Given a frozen position, then the requisition cannot be submitted (`POSITION_FROZEN`).
- AC3: Requisition types are the organization's, mapped to replacement, additional headcount or new position. A new position creates a `position.create` change set that is approved together with the requisition.
- AC4: The requisition carries its funding lines (cost centres and funding sources with shares adding to 100), its employment type and, for term hires, its end date (`docs/23` §3.2).

**REC-002 — Approval routing.** AC: requisitions, direct hires, offers, probation extensions and conversions follow the organization's routes (`platform.workflow_route`), chosen by their conditions and priority, with "any" or "all" steps; starter routes are copied at setup and edited by the organization; no route matching is an error, never a default route; no one approves their own request; undecided approvals escalate (`docs/21` §7.5). Going past a caution records an acknowledgement and, where the organization asks, an approval (`docs/23` §2).

**REC-003 — Posting validator by jurisdiction.** As a recruiter, I want postings blocked until they meet the rules of the job's location.
- AC1 (ON, employer with 25+ employees): a public posting without pay or with a range wider than $50,000 is blocked. The AI-use statement is inserted automatically when AI screening is on. The posting states whether the vacancy exists, and any "Canadian experience" requirement is rejected.
- AC2 (BC, PE): a public posting without expected pay or a range is blocked. For BC roles (and NL), pay-history questions are removed from the application form.
- AC3 (QC): publication requires the French version.
- AC4: Rules come from `rules/employment-standards` (`pay_transparency`) and are effective-dated.
- AC5: Pay is shown by default; the incumbents' average needs at least 3 incumbents (`docs/23` §4.2).

**REC-004 — Internal candidates and seniority.** As a recruiter in a unionized workplace, I want internal applicants ranked per the agreement's selection rule.
- AC1: Given the selection rule `relatively_equal_then_seniority`, when two internal candidates have equal assessment scores, then the more senior is ranked first, and the reason is recorded.
- AC2: The posting stays internal for the agreement's `internal_posting_days` before going external.
- AC3: The organization can switch the seniority order off; overriding it on a posting needs the caution and a written reason (`docs/23` §4.3).

**REC-005 — Ontario 45-day follow-up.** AC: given an interviewed applicant on an Ontario public posting, then a task is due 45 days after the last interview, and the dashboard shows tasks at risk.

**REC-006 — Structured interviews and scorecards.** AC: interview kits with competency questions and rating scales. Scores are locked once submitted, and the panel sees others' scores only after submitting their own. Whether every interview is scored before a decision is chosen at setup.

**REC-007 — Offer within range.** AC: an offer outside the grade range or agreement step goes through the organization's route for it (starter: HR, then finance). Offer letters are generated in the organization's languages from templates and signed electronically. Any change to approved terms goes back for approval unless the organization sets otherwise; earlier approvals do not count.

**REC-008 — Signed contract becomes a hire.** As an HR administrator, I want the hire created through the normal change set once the offer is accepted and the contract signed, so that Core HR, payroll and benefits are set up once.
- AC1: Once the offer is accepted **and** the contract signed, an `employment.hire` change set is drafted with person, position, rate, start date and pay group (`HIRE_BEFORE_CONTRACT_SIGNED` before that). On commit, the position is filled, payroll setup tasks (TD1 federal and provincial, banking) are sent to the new hire's pre-boarding screens, and benefits eligibility starts per plan rules.
- AC2: No data is typed twice. Candidate fields map to person fields with the consent recorded.
- AC3: An internal applicant's move is stated as a transfer or a resignation and rehire; telling the current supervisor is a condition of the offer.

**REC-009 — Pre-boarding.** AC: from the contract signing to the first day, the new hire completes, on their own CanDo login, the forms the organization's plan lists: SIN (by the first day, legally within 3 days of starting), TD1 forms, banking, emergency contacts, policy acknowledgements, the s. 87 question, and the voluntary self-identification form (optional, with purpose statements). Forms tied to later events (benefits) are due on those events. Their access is limited to pre-boarding until the start date.

**REC-010 — Onboarding checklist.** AC: tasks are generated from every plan that applies (hire kind, and the organization's scopes by unit, job, location, province, agreement and employment type), with owners (IT, facilities, manager, HR and others). Overdue tasks remind the owner, then tell their manager, then HR, on the organization's days. The manager chooses buddies, mentors and trainers, several if needed. IdP provisioning is triggered by the hire event.

**REC-011 — Probation tracking.** AC: the probation end date comes from the agreement (months or hours worked) or the organization's setting. Check-ins and reminders before the end follow the organization's settings. A leave near the end shows a caution before it is approved. An extension has a recorded reason, is told to the employee before the end date and respects the agreement's or organization's maximum. If the end date passes with no decision, the probation is passed and HR is told. Completion triggers `employment.status_changed` and the benefits waiting period, and a confirmation letter where the organization uses one.

**REC-012 — Status conversion.** AC: temporary-to-permanent, casual-to-regular and auxiliary-to-regular conversions start when a manager asks, or when an organization's threshold or a collective agreement flags them, and follow the workflow in `requirements/02` through the organization's route. Seniority and benefits are recalculated per agreement, and the conversion is an effective-dated change set. Declining a conversion the agreement requires needs the caution and a reason.

**REC-013 — Candidate privacy.** AC: each decided application has a retention date: never less than the law of each jurisdiction that applies (BC one year after the decision; Ontario three years after the posting closes) and the organization's own minimum. Unsuccessful candidates are purged or anonymized after retention unless they consent to a talent pool.

**REC-014 — AI screening guardrails.** AC: AI match suggestions are off until the organization switches them on; scores show their reasons; blind review mode hides names and photos when the organization turns it on; a person makes every reject or advance decision (the only exception is a screen-out by the posting's own rule for a missing required qualification, when the posting is set to screen out). Disparate impact reports run monthly when suggestions are on.
