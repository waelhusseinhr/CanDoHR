# CanDo HRIS — 08 Learning & Development

Oct 17, 2026 · @Wael

> **Owner's review (28 October 2026):** the decisions are in `docs/29-learning-development-decisions.md`, which wins where this file differs. Changed here: integration-first, with no course player or authoring in CanDo, while CanDo still records classroom attendance, sign-offs, policy acknowledgements and external certificates; no ready-made CanDo courses (government courses linked, a partner library); the training the law requires loaded by CanDo, stricter but never looser; no AI in learning, rule-based suggestions only; training before work and credentials checked when shifts are published (a licence the law requires with no override); reminders 14 and 3 days before, manager and HR after; refresher cycles kept when done within 60 days; credentials verified by HR; skills seen for internal opportunities only with consent; development plans agreed by both; requests through the organization's route; repayment rules the organization's own; budgets with a caution; grants tracked; Quebec's 1% recorded for phase 2; basic mentoring; council and board members' training. The open questions are closed, except the course library partner (`docs/16` Q50).

## Overview and scope

> **Draft status:** new specification. No learning source file exists; drafted from cross-references in the recruitment, onboarding and performance material (onboarding training tasks, development goals, credential checks) and the integration architecture.

Learning & Development makes sure people have the training the law and their job require, and gives them room to grow. It tracks what has been completed, what is due, and what skills the organization has.

**In scope:** mandatory and compliance training; the learning catalogue; the record of courses taken in the customer's LMS or a provider's platform, and of learning outside any LMS (classroom, virtual, on-the-job, policy acknowledgements, external courses); assignments and learning paths; skills and competency profiles; individual development plans; credentials, certifications and professional licences; training administration, budgets and external funding programs; mentoring.

**Out of scope:** performance goals and ratings (07, which sends development needs here); succession readiness (09, which uses skills data from here); health and safety programs beyond training records (13); delivering courses (the customer's LMS or the provider's platform).

**Build or integrate (decided, `docs/29` §3.1):** integration-first. CanDo provides the HR-side learning record, assignments, compliance tracking, credentials and skills profiles natively, and links to the customer's LMS, a partner library or government courses through SCORM, xAPI, cmi5, LTI or the provider's API. CanDo has no course player or authoring tool.

## Mandatory and compliance training

Requirements are held as rules (who must take what, by when, how often) so assignments happen automatically from Core HR data: jurisdiction, location, job, position, hazards and bargaining unit. **CanDo loads the training the law requires by jurisdiction and sector; an organization can make each one stricter but never looser, and adds its own rules (`docs/29` §3.3).**

| Area | Examples configured |
| --- | --- |
| Occupational health and safety | Worker and supervisor health and safety awareness; WHMIS; joint health and safety committee member certification; job-specific hazards (fall protection, confined space, lockout, forklift); first aid where required by the workplace |
| Workplace violence and harassment | Provincial programs (for example Ontario's OHSA policy and program requirements) and federal harassment and violence prevention training for federally regulated employers |
| Accessibility | Customer service and standards training under Ontario's AODA and other provincial accessibility laws as they come into force |
| Privacy and information security | Privacy law basics, Quebec Law 25 awareness, phishing and security |
| Human rights and respectful workplace | Discrimination, accommodation duty, bystander training |
| Indigenous awareness | Intercultural competency and Indigenous history training, reflecting the Truth and Reconciliation Commission's Call to Action 92 for business |
| Sector-specific | Food safety, safe handling of medications, Smart Serve or provincial equivalents, vulnerable sector requirements |
| Role-specific | Manager training on hiring, leave and accommodation; payroll confidentiality; anti-bribery and code of conduct |

**Rules (`docs/29` §4):** due dates relative to hire, job change, promotion, transfer to another location, return from a long leave or last completion, assigned automatically on each of those events; refresher frequency, with a refresher done within 60 days before its due date keeping its cycle; no grace period unless the organization adds one to its own rule (never to the law's); training required before work (for example WHMIS before handling hazardous products) stops scheduling the person for that work until done, unless someone acknowledges a caution with a reason, and is shown as a blocking onboarding task in Module 02; the employee reminded 14 and 3 days before the due date, the manager told 1 day and HR 7 days after it is overdue; when the law adds or changes a requirement, current employees assigned it on its effective date, due by the law's deadline or within 30 days; training the law requires never waived.

**Evidence:** completion records with date, version of content, score, trainer and attestation; certificates stored; records kept at least as long as the law and regulators expect, longer if the organization chooses, and exportable for an inspection.

## Learning catalogue, content and delivery

**Catalogue items:** e-learning modules in the customer's LMS or a partner library (SCORM 1.2 and 2004, xAPI, cmi5, LTI or the provider's API); video; documents and policies with acknowledgement; classroom and virtual instructor-led sessions; on-the-job training checklists signed off by a supervisor; external courses and conferences; mentoring and job shadowing; free government courses (linked) and licensed bilingual libraries through a partner (`docs/16` Q50). CanDo ships no courses of its own.

**Item attributes:** title and description in English and French; language versions; duration; delivery method and where it runs; audience; skills developed; prerequisites; cost; provider; continuing education credits; accessibility notes; version and effective date (so records show which version someone completed).

**Delivery:** in the customer's LMS or the provider's platform (player, offline mode, captioning, assessments, surveys). CanDo records the completion and its evidence.

**Instructor-led sessions:** scheduling with rooms, instructors and capacity; waitlists; invitations and reminders; attendance capture (including by sign-in sheet scan or QR code), recorded by a named person; no-show tracking; virtual sessions through Teams or Zoom links.

**Content creation:** none in CanDo, and no AI drafting (`docs/29` §3.4); policies to acknowledge are documents in CanDo's document module.

## Assignment, enrolment and learning paths

**Ways learning is assigned:**

| Trigger | Example |
| --- | --- |
| Rule-based | Every new supervisor in Ontario gets supervisor health and safety awareness within one week |
| Event-based | Hire, job change, promotion, location transfer, return from long leave |
| Change in the law | A new requirement assigned on its effective date to everyone it covers |
| Manager assignment | Manager assigns a course to a team member or whole team |
| Development plan | Items linked to goals in an IDP |
| Self-enrolment | Employee browses catalogue, with manager approval for cost or time off |
| Suggestion | Suggested by fixed rules from the role's required training, competency gaps, expiring credentials and development goals; each suggestion shows its reason; no AI |

**Learning paths:** ordered sequences (for example new manager program, onboarding by role, apprenticeship tracks) with milestones, prerequisites and target dates; progress shown to the learner and manager.

**Onboarding link:** role-based paths attach to the onboarding plan in Module 02; required pre-start items can be completed in the pre-boarding portal.

**Time and pay:** mandatory training time is paid working time; training outside scheduled hours is added to the timesheet as training time when completed, for the manager's approval, and is always paid (`docs/29` §4.7); unionized groups may have training rights and paid education leave from their agreement, read from the agreement library.

## Skills, competencies and individual development plans

**Skills framework:** CanDo's Unified Competency Model as the starting framework, with ESDC's Skills and Competencies Taxonomy (linked to NOC) as an optional add-on; proficiency levels; required skills per job and position (from Module 01); competency model shared with Module 07.

**Employee skills profile:** skills with proficiency from self-assessment, manager validation, assessments, completed learning and credentials; languages with proficiency (including second official language levels for bilingual positions); interests and mobility preferences; visible to the employee, the manager and HR, and to managers and recruiters for internal opportunities only after the employee opts in, which they can withdraw at any time (`docs/29` §7.2).

**Gap analysis:** profile compared with current role and with target roles; gaps feed rule-based suggestions and IDPs; aggregated gaps by team or organization feed workforce planning (Module 09).

**Individual development plan (IDP):** works like goals in Module 07: proposed by the employee or the manager, agreed by both, every change kept with who and why; development goals (from Module 07 or self-created); actions with the 70-20-10 mix (experience, relationships, formal learning) shown as guidance; target dates; progress check-ins.

**Mentoring (basic at launch):** HR or the manager pairs a mentor and a mentee for a purpose and a period, with rule-based suggestions by skills and goals; session logs; feedback from both.

## Credentials, certifications and licences

**Credential types:** professional licences and registrations (nursing colleges, engineering associations, CPA, law societies, teaching certificates); trade certifications (Red Seal, provincial certificates of qualification, apprenticeship hours); safety certifications (first aid, CPR, fall protection); driver's licences and abstracts; vulnerable sector and other checks with renewal dates; equipment operator tickets.

**Tracking:** issuing body, number, issue and expiry dates, status, verification method and date, document copy; required credentials per position; alerts to the employee at 90, 60 and 30 days before expiry and to the manager and HR at 30 days and on the expiry date; when a shift is published, a missing or expired credential the law requires stops it with no override, and any other required credential needs a caution with a reason (`docs/29` §6).

**Verification:** HR, or a delegate the organization names, verifies each credential against the document, the public registry or the issuer, with the method and date; until then it is pending and does not count. No registry integrations at launch, with a link to the registry; integrations as customers need them. Continuing education hours tracked against each body's requirement, with reminders.

**Apprenticeships (basic at launch):** hours by trade and level, technical training periods, and wage progression by level linked to Module 04 grids; journeyperson ratio checks later.

## Training administration, budgets and funding

**Budgets:** training budgets by department, per employee optional; requests for external courses with cost, time off and business case; approval through the organization's route (the manager, and HR above an amount the organization sets at setup); spend tracked against budget, and approval over budget needs a caution, a reason and finance as the route says; accruals for finance.

**Tuition and education assistance:** policy rules (eligible programs, maximum per year, grade requirements); pre-approval and reimbursement on proof of completion; repayment rules that each organization writes by kind of training and cost (none, prorated or full, over a period), with no CanDo starting rule, and its own choice of what happens when none fits; a repayment agreement signed before reimbursement, and recovery only with written authorization (tracked to Module 11); HR marks each paid training as mainly for the employer or the employee (CRA's test), and the second goes to Payroll as a taxable benefit.

**Funding programs tracked:**

| Program | Support |
| --- | --- |
| Quebec workforce skills development | Employers with payroll over $2 million must invest at least 1% of payroll in eligible training or pay the difference to the FDRCMO; eligible spending recorded from launch, the RL-1 summary figures in phase 2 with Quebec payroll |
| Canada-\[Province\] Job Grants and similar | Eligible training, employer share, grant claims and reporting (basic at launch) |
| Apprenticeship incentives | Employer tax credits and grants for hiring and training apprentices |
| Indigenous skills and employment programs | Partnerships with ISET service delivery organizations; trainee tracking |
| Union training trust funds | Contributions and member training records |
| Wage subsidy programs | Eligibility, hours and claim documentation (for example student hiring programs) |

**Vendors and instructors:** training providers, contracts, rates and evaluations; internal instructors with qualifications.

## Data model, integrations and security

Detailed model: `docs/29` §12.

| Entity | Key fields |
| --- | --- |
| Learning Item | Type, where it runs, standard, titles (EN/FR), versions, duration, skills, cost, provider, credits |
| Session | Item, dates, location or link, instructor, capacity, roster |
| Law Requirement | Jurisdiction, sector, audience, before work, deadline, frequency, citation, status |
| Training Rule | Law or organization, audience, item, events, due rule, frequency, grace period, before work |
| Assignment | Learner, item or path, source, due date, the law's due date, language, status |
| Completion | Learner, item version, date, source, score, credits, paid minutes, sign-off, evidence |
| Learning Path | Ordered items, milestones, prerequisites |
| Skill | Name, category, levels, taxonomy reference |
| Skill Profile Entry | Employee, skill, level, source, validated by, date |
| Development Plan | Employee, actions, agreement by both, change history |
| Credential | Employee, type, issuer, number, dates, verification, document |
| Training Request | Employee, item, cost, route, budget, CRA mark, repayment, grant |

**Integrations:** Core HR (jobs, positions, locations, events); Recruitment & Onboarding (onboarding paths, pre-start training); Time (training hours, shift readiness); Payroll (taxable tuition benefits, repayment recovery); Performance (development goals, competencies); Succession (skills and readiness); the customer's LMS and content libraries (LTI, SCORM, xAPI, APIs); video meeting tools; credential registries later.

**Security:** learners see their own records; managers see their teams; HR and a compliance role the organization grants see completion status across the organization; credential documents and numbers restricted to HR; skills profiles shown for internal opportunities only with the employee's consent.

## Public-sector and large-employer learning

| Area | Requirement |
| --- | --- |
| Statutory and sector training at scale | Compliance assignments for tens of thousands across jurisdictions, with inspection-ready records per site |
| Professional and trade credentials | Nursing, teaching, firefighting, policing, water and wastewater operator and Red Seal credentials tracked against position requirements, with expiry blocking scheduling in Module 06 |
| Elected officials | Orientation and code of conduct training for council and board members where required, recorded as non-employees |
| Agreement-based learning rights | Paid education leave, tuition support and training funds read from the agreement library |
| Languages | Courses assigned in the organization's main language; French, Inuktut and other Indigenous-language versions on request |
| Territories and remote sites | Offline and low-bandwidth delivery through the LMS or provider chosen |

## How CanDo compares

| Vendor | Learning position | CanDo response |
| --- | --- | --- |
| Rippling, ADP, Dayforce | LMS inside the suite | Integrate; lead on compliance rules and credential control |
| Humi by Employment Hero | LMS and learning bundles as paid add-ons | Partner library and government courses |
| BambooHR | No learning module evidenced | Differentiator |

CanDo's edge is compliance rules by jurisdiction and credential control tied to scheduling. Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Reporting, implementation and open questions

**Reports:** compliance status by requirement, team and location (completed, due, overdue); inspection-ready training records for an employee or site; expiring credentials; learning hours and spend per employee; Quebec 1% training investment total (phase 2); course evaluations; skills inventory and gaps; IDP completion; mentoring participation.

**Implementation:**

| Step | Activities |
| --- | --- |
| 1. Requirements inventory | Legal and policy training by jurisdiction, site and job; credentials by position |
| 2. Content | Connect the LMS or the partner library; link government courses; build policy acknowledgements |
| 3. Configure | Rules, paths, routes and the HR amount, repayment rules, budgets, notifications |
| 4. Migrate | Historical completions needed to prove compliance, current credentials with expiry dates |
| 5. Launch | Compliance assignments first; development features second |

**Sources:** onboarding-workflow.svg and Module 02 (training and credential tasks); performance-management-workflow.svg (development goals, coaching); hr-integration-architecture.svg. Everything else is new drafting.

**Open questions:**

- [x] Native LMS versus integration-first approach, and which LMSs to integrate with: integration-first; standards-based links (SCORM, xAPI, cmi5, LTI, APIs) (`docs/29` §3.1)
- [x] Whether to ship a starter library of Canadian compliance courses (bilingual) or rely on partners: no CanDo courses; government courses linked and a partner library (`docs/29` §3.2); the partner is `docs/16` Q50
- [x] Skills taxonomy to seed from: CanDo's Unified Competency Model, with ESDC's taxonomy as an optional add-on (`docs/29` §7.1)
- [x] Credential registry integrations to prioritize by sector: none at launch, as customers need them (`docs/29` §5.4)

**October 2026 review:** added public-sector and large-employer learning, credentials, territorial delivery and competitor comparison.

**28 October 2026 (owner's review):** the decisions in `docs/29`.
