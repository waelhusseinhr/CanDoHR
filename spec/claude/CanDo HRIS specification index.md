# CanDo HRIS specification index (October 2026)

Consolidated module specifications built from the project files, reviewed for the Canadian market (federal, 10 provinces, 3 territories; municipal, provincial and First Nations public sector; unionized employers; 25 to 50,000+ employees) and benchmarked against 15 HRIS vendors.

The full text of every document below (except the Vendor Explorer and the Developer Pack overview) is also in this project under `dev-pack/requirements/`.

| # | Document | Link | Text in this project | Owner's review |
|---|---|---|---|---|
| 00 | Master Platform Overview (scope, Quebec assessment, government integration, Europe readiness) | https://claude.ai/artifact/1Mwrv4ymGTjzfAAnyw1bmK | `dev-pack/requirements/00-master-platform-overview.md` | Languages decided (`docs/22`) |
| 01 | Core HR & Position Management (including position codes, NOC classification and requirements) | https://claude.ai/artifact/RysDb8HJLrTkD2v4weNaQW | `dev-pack/requirements/01-core-hr-position-management.md` | Done, 25 Oct 2026 (`docs/21`) |
| 02 | Recruitment & Onboarding | https://claude.ai/artifact/XPQe5UxGjQDp6S6E4gqTR4 | `dev-pack/requirements/02-recruitment-onboarding.md` | Done, 25 Oct 2026 (`docs/23`) |
| 03 | Payroll (CRA T4127/T4032, Revenu Québec, 2026 values, all 14 jurisdictions, pay per position) | https://claude.ai/artifact/ShDbiQ9x7PZuYCfdJna4tS | `dev-pack/requirements/03-payroll.md` | Done, 27 Oct 2026 (`docs/24`) |
| 04 | Compensation Management (including job evaluation, salary surveys, market pricing and survey participation) | https://claude.ai/artifact/2tGuCzRvKZs89jnJd1k1P9 | `dev-pack/requirements/04-compensation.md` | Done, 28 Oct 2026 (`docs/25`) |
| 05 | Benefits Administration (including benefits and practice benchmarking, and benefits across unions and positions) | https://claude.ai/artifact/Dj9TCMNuMZbDD7uDZ5RRRu | `dev-pack/requirements/05-benefits.md` | Done, 28 Oct 2026 (`docs/26`) |
| 06 | Time, Attendance & Leave (including approval by each manager's coverage) | https://claude.ai/artifact/3MDbd14ApJMZM2cdQ8RtBU | `dev-pack/requirements/06-time-attendance-leave.md` | Done, 28 Oct 2026 (`docs/27`) |
| 07 | Performance Management (including review sections per position) | https://claude.ai/artifact/KJCL8LPCM3RPKoG6Z1Ag2W | `dev-pack/requirements/07-performance.md` | Done, 28 Oct 2026 (`docs/28`) |
| 08 | Learning & Development | https://claude.ai/artifact/L3Ft4g89AhL6dBLHHoNyzT | `dev-pack/requirements/08-learning-development.md` | Done, 28 Oct 2026 (`docs/29`) |
| 09 | Succession & Workforce Planning | https://claude.ai/artifact/Ty6h2aYdwkFhNhnA9sFaop | `dev-pack/requirements/09-succession-workforce-planning.md` | Done, 29 Oct 2026 (`docs/30`) |
| 10 | Employee Engagement & Recognition | https://claude.ai/artifact/4gTQYKEVQbJ65YhtTf1B5m | `dev-pack/requirements/10-engagement-recognition.md` | Done, 30 Oct 2026 (`docs/31`) |
| 11 | Offboarding & Separation | https://claude.ai/artifact/B165fuwgXrakj5Go8pqBEP | `dev-pack/requirements/11-offboarding-separation.md` | Next |
| 12 | Analytics & Reporting | https://claude.ai/artifact/9u9E6gEM2BE3fyjoQ1BYNc | `dev-pack/requirements/12-analytics-reporting.md` | — |
| 13 | Compliance, Labour Relations & Privacy (collective agreement library) | https://claude.ai/artifact/AutBBcLUJeU6J35MHeBEC9 | `dev-pack/requirements/13-compliance-labour-relations-privacy.md` | — |
| — | Competitive Analysis (Dayforce, ADP, UKG, Workday, Rippling, HiBob, BambooHR, Sparkrock, Humi, Payworks, Collage, Folks, Nethris, Rise, Wagepoint) | https://claude.ai/artifact/HKne7KHHJ9DvRnYxc5GWTH | `dev-pack/requirements/competitive-analysis.md` | — |
| — | CanDo Vendor Explorer (interactive comparison) | https://claude.ai/artifact/RFLT6phVob9B2BuBotcv3G | — | — |
| — | Developer Pack overview (for developers and AI coding agents) | https://claude.ai/code/artifact/2be393ef-753c-4e0e-b04a-56ee84863dab | — | — |

## Owner's module reviews (October 2026)

The owner reviews the requirements module by module. Each review is logged round by round in `claude/review/`, then applied to the developer pack before the next module starts. A decisions document in `dev-pack/docs/` wins over the requirements and stories on its topics.

**The principle for every module:** each decision is a default that each organization can change at setup or later; only legal floors and safety rules are fixed. Routes, workflows, messages and checklists are the organization's, starting from CanDo's starter copies. Users get reminders and cautions; a user who overrides a caution on purpose acknowledges it, and CanDo records who did what, when and why, for audit.

| Review | Log | Applied in |
| --- | --- | --- |
| 01 Core HR & Position Management | `claude/review/01-core-hr-decisions.md` | `dev-pack/docs/21`, migration 0007 |
| Values, defaults, fallbacks and languages (whole pack) | `claude/review/00-values-and-fallbacks.md` | `dev-pack/docs/22`, migration 0008, the register and its automatic check |
| 02 Recruitment & Onboarding | `claude/review/02-recruitment-onboarding-decisions.md` | `dev-pack/docs/23`, migration 0009 |
| 03 Payroll | `claude/review/03-payroll-decisions.md` | `dev-pack/docs/24`, migration 0010 |
| 04 Compensation Management | `claude/review/04-compensation-decisions.md` | `dev-pack/docs/25`, migration 0011 |
| 05 Benefits Administration | `claude/review/05-benefits-decisions.md` | `dev-pack/docs/26`, migration 0012 |
| 06 Time, Attendance & Leave | `claude/review/06-time-attendance-leave-decisions.md` | `dev-pack/docs/27`, migration 0013 |
| 07 Performance Management | `claude/review/07-performance-decisions.md` | `dev-pack/docs/28`, migration 0014 |
| 08 Learning & Development | `claude/review/08-learning-development-decisions.md` | `dev-pack/docs/29`, migration 0015 |
| 09 Succession & Workforce Planning | `claude/review/09-succession-workforce-planning-decisions.md` | `dev-pack/docs/30`, migration 0016 |
| 10 Employee Engagement & Recognition | `claude/review/10-engagement-recognition-decisions.md` | `dev-pack/docs/31`, migration 0017 |

**Core HR (01), in short:** employment type on each position; probation per bargaining unit; no gender field (voluntary self-identification only); rehire eligibility for HR only; one employee number per person for life; positions for everyone (created automatically for small organizations); NOC recommended, not required; job descriptions drafted from NOC, never by AI (AI may only translate, as a paid service); back-dated changes approved by HR and payroll; overpayments never deducted without the employee's written authorization; terminations, demotions and leave-linked changes always approved by HR; agreements compared with employment standards law.

**Values and languages, in short:** every value an organization could want different is a setting, an organization list or a rule value; no silent fallbacks, only registered ones; each user picks the screen language (English or French); the organization's own words show as typed, in the language it chose at setup; Quebec organizations keep their words in French; translation is a paid service quoted before each job.

**Recruitment & Onboarding (02), in short:** a requisition before every hire, with direct hires and hires without a posting through the organization's own rules and approvals; pay shown on postings by default, within the law; AI match suggestions off unless the organization turns them on, and AI never decides; candidate records kept never less than the law; the employee record created only when the offer is accepted and the contract signed; background and criminal checks only after a conditional offer; any change to an offer re-approved; pre-boarding on the employee's own login; onboarding checklists by hire kind, department and role; several buddies and mentors; probation check-ins and reminders on the organization's days, passed when the end date passes without a decision; HR reviews any open case before probation is failed or employment ends; conversion to regular when a manager asks.

**Payroll (03), in short:** CanDo calculates, prepares the bank, remittance, slip and ROE files and reminds; the employer moves the money, pays the remittances and uploads the filings; one T4 for the whole year after a mid-year move; pay runs approved through the organization's route, never by the person who prepared them; failed checks hold only the affected employees unless the organization stops the run; pay dates on the previous banking day; outside payroll providers act for a client only with its approval; vacation pay, proration and banked time set per group of employees within the law; a starter catalogue of earnings codes; garnishments worked out from the law and confirmed by payroll; voluntary deductions in self-service; money owed recovered only with written authorization; pay statements and slips delivered by CRA's rule (self-service for current staff, paper on request, consent for former staff and email); former employees keep access for a period the organization sets; all major banks at launch; HR reviews every ROE; journal files for accounting systems; a parallel run before going live; CRA tables loaded centrally by CanDo.

**Compensation (04), in short:** a pre-filled pay philosophy, approved by an executive before a market-based structure; structures, pay decisions, bonus payouts and salary disclosure lists approved through the organization's own routes; range spreads pre-filled by track; a catch-up plan for anyone below the minimum; above the maximum the manager proposes; promotions pay at least the new minimum and 5%; demotions keep pay unless someone acknowledges a caution; acting pay chosen at setup; increase cycles from pre-filled rules, with exceptions needing a reason and HR's approval and letters released by HR; clawbacks only from the signed agreement; bonuses prorated by eligible days; basic commissions and long-term incentive tracking; employees see a moderate level of pay information; pay gaps by gender and self-identification groups, never for groups under 10; BC and federal reports at launch; total rewards statements on request; bargaining proposals costed at launch; the competency model accepted as written.

**Benefits (05), in short:** spending accounts administered by a partner; a generic carrier file at launch, each carrier's format as customers need it; benefits advisors get an included read-only role the organization grants; the enrolment assistant later, off until switched on; each organization sets waiting periods, the life event window and how far back premium adjustments go; late enrolment by each plan's rule; elections roll over in open enrolment; HR chooses the governing agreement and which of two plans pays first, with a reason, and CanDo never picks; variable-hour re-tests proposed to HR; during statutory leave the employee chooses how to pay their share among the organization's ways; the organization's rules for other unpaid leaves and for coverage on termination by class, never before the law; outside Ontario a caution about common-law reasonable notice; carrier invoices reconciled and approved through the route; dependents told 60 days before ageing out; opt-outs with proof (RAMQ rules in Quebec); pension files for the BC Municipal Pension Plan, OMERS, HOOPP and LAPP at launch; automatic enrolment in mandatory pension plans; union trusts through a generic file; retiree benefits later.

**Time, Attendance & Leave (06), in short:** full scheduling in CanDo (auto-fill, demand staffing, shift bidding, self-scheduling); punching by app, web and kiosk, imports from any clock and one hardware partner (still to choose); no biometrics; hours paid to the exact minute unless the organization rounds both ways; breaks deducted only when taken; unapproved overtime flagged the same day and before payroll, always paid, and payroll never waits; location checks optional and inside-or-outside only; rest-period and hours-limit breaches stop for a caution; averaging recorded with its document and end; overtime exemptions by HR with the legal basis; recording method per group; second timesheet approvals only where the organization adds them; unapproved timesheets paid at the cut-off; employees confirm their time; each leave plan sets its own carry-over, negative limit, payout and year (calendar, fiscal, anniversary or a promotion or union change); no sick notes; a team availability bar before requesting; statutory leave never refused for staffing; protected leave reasons for HR only; the attendance program off until turned on; schedule notice from the agreement or law, else 14 days; offers logged; swaps approved by the manager.

**Performance (07), in short:** a 5-point starter scale; CanDo suggests each position's rating from the goal and competency weights (50/50) and the manager chooses it, explaining any difference; AI writing help later, off until switched on, and AI never rates; starter templates for Indigenous and non-profit organizations developed with advisers; goals as a living document, proposed by either side, agreed by both, aligned to the mission and every amendment kept; new hires in the last 3 months not rated; mid-year reviews without ratings; calibration on by default; the manager's manager looks at each review before release, with HR on the concerns the organization lists; signing means seen, and the employee can comment and ask HR; only HR changes a final rating, with a reason; each position rated by itself from 90 days worked, with no combined rating; 360° raters nominated by anyone, 3 to 5 per group, shown from 3 answers, for development only; a check-in nudge after a month; improvement plans only after causes are ruled out and HR approves, 60 days, never during protected leave, with an accommodation caution; union representation or a support person; development-only reviews where the agreement limits ratings; sunset clauses from the agreement, none for non-union staff unless the organization sets one; board evaluation of the chief executive later; protected leave rated on time worked.

**Learning & Development (08), in short:** integration-first: CanDo keeps the record and links to the customer's LMS, a partner library or free government courses, with no course player; it still records classroom attendance, supervisor sign-offs, policy acknowledgements and certificates; CanDo loads the training the law requires, which an organization can make stricter but not looser; no AI, only rule-based suggestions with their reason; training required before the work stops scheduling unless someone acknowledges a caution; reminders 14 and 3 days before, manager and HR after; refreshers done within 60 days keep their cycle; changes in the law assigned automatically; credentials verified by HR, alerts at 90, 60 and 30 days, and a licence the law requires stops a shift with no override; continuing education and basic apprenticeships; skills seen for internal opportunities only with the employee's consent; development plans agreed by both; mandatory training time paid; requests through the organization's route (HR above an amount it sets); HR marks training for CRA; repayment rules the organization's own; department budgets with a caution; grants tracked; Quebec's 1% recorded for phase 2; basic mentoring; council and board members' training; courses in the organization's main language.

**Succession & Workforce Planning (09), in short:** one module for every organization: key roles, named backups and succession plans for all, with talent reviews, the nine-box and workforce planning switched on by each organization; flight risk is the manager's note, with no prediction model and no AI; succession data seen only by the people named on a review or plan, and HR, with every view logged; leaders score roles on five criteria (equal weights pre-filled) and HR confirms; positions the law requires always have a plan with an emergency successor; retirement from pension eligibility and what the employee shares, age only in totals; a work permit's end shown to HR only as a possible vacancy date; potential on the organization's criteria with the employee's own aspiration beside it; placements hidden from employees by default; bias prompts for groups of 10 or more; plans approved through the organization's route (starter: HR), reviewed yearly, development only for unionized roles; continuity sheets with no passwords or secrets; talent pools by nomination or application; career paths from the job architecture and real moves; stretch assignments through positions; supply from the organization's own history (uploads allowed; the next level up when under 10 people or 2 years), demand from its own drivers; versioned scenarios; gap strategies that only draft; labour relations before a unionized reduction; the position plan through finance, HR and the executive; generic CSV, Excel and journal exports.

**Employee Engagement & Recognition (10), in short:** CanDo's own survey tool, with uploaded questionnaires and imported results; confidential by default with an anonymous option, and anonymous only for employers covered by a freedom-of-information law; answers never linked to a person and kept with the date only; results from 5 by unit and 10 by self-identified group; flagged comments (harassment, safety, self-harm) to a named HR contact without identity, with the speak-up channel and crisis lines on every survey; email and the app for surveys; a caution where an agreement requires union consultation; managers see their team and roll-up, HR reads comments, managers see themes (AI themes later, off until switched on); action plans within 60 days; all lifecycle surveys on; recognition private until its recipient makes it public, after HR approves; points tracked and rewards handed out by the organization; CRA's $500 gift and long-service limits applied and confirmed by payroll; cash awards through the route; milestones every 5 years; birthdays by opt-in; targeted announcements with read receipts; SMS only for urgent alerts; ideas, an anonymous feedback box and a separate speak-up channel at launch; Teams and Slack; a wellbeing hub; a starter observances calendar; directory extras only if the employee adds them; included in every plan. Award programs, groups (ERGs) and wellbeing challenges come later.

Open questions for the owner are in `dev-pack/docs/16-open-questions.md`. Q45 (translation pricing), Q46 (setup-wizard numbers) and Q47 (recently closed cases) were decided on 25 Oct 2026; Q2, Q7, Q11, Q12 and Q14 were decided in the payroll review; Q27, Q29, Q31 and Q32 in the compensation review; Q6, Q13 and Q37 in the benefits review; Q4 in the time and leave review (Q48, the time clock partner, is new); Q35 in the performance review (Q49, the advisers for the Indigenous and non-profit templates, is new); Q50 (the course library partner) is new from the learning review; Q51 (advisers for Indigenous leadership development) is new from the succession review, and FB-039 (plans made before migration 0016 marked as org chart plans) was confirmed. The engagement review closed its four open questions and added none.

## Developer pack files

The build files are in this project under `dev-pack/`:

- `AGENTS.md`: rules for the AI agent (reading order, rules 1 to 55, the step-by-step build instructions).
- `docs/01` to `docs/31`: technical design, build plan and the owner's decisions (`docs/21` Core HR, `docs/22` values and languages, `docs/23` recruitment and onboarding, `docs/24` payroll, `docs/25` compensation, `docs/26` benefits, `docs/27` time, attendance and leave, `docs/28` performance, `docs/29` learning and development, `docs/30` succession and workforce planning, `docs/31` engagement and recognition).
- `requirements/`: the 14 module specifications and the competitive analysis.
- `schema/`: PostgreSQL 16 and migrations 0003 to 0017.
- `api/`: OpenAPI, the codes API, the total rewards API, the several-positions API and events.
- `rules/`: 2026 Canadian payroll and employment rules as data (including benefits during notice, separation values, Core HR, recruitment and payroll additions; starter earnings and deduction codes; salary disclosure statutes; the training the law requires; CRA's gift and award rules; keyword rules for flagged survey comments), the register of every value, default and fallback, the collective agreement format, the NOC 2021 structure with the code scheme catalogue, career levels and job families, the competency model, a sample job evaluation plan, the benefits and practice catalogue, survey import profiles and benefit-change rule templates.
- `reference/`: reference payroll calculator, pay composition evaluator, audit hashing, similar-position scorer, market pricing, several positions.
- `tests/`: 77 payroll cases, 25 pay composition cases, audit hashing vectors, 19 similarity cases, 17 market pricing cases, 35 several-positions cases, smoke tests for migrations 0003 to 0017, and the hard-coding check.
- `stories/`: user stories with acceptance criteria; scenario lists in `docs/17` to `docs/31`.

Start with `dev-pack/README.md`.

The full NOC 2021 content (definitions, duties, 2,063 requirement statements, example titles, exclusions) and the 28,012-title index are too large for the project and are distributed as `CanDo-NOC-2021-data.zip`, to be unzipped into `rules/classifications/`.

The Lovable demo kit (for the clickable demo only, not the production build) was removed from the project on 28 Oct 2026 to free space; the demo itself is finished and lives in Lovable.

## Design hardening (October 2026)

Adopted after review and built into the pack:

- **Tamper-evident audit:** hourly signed Merkle batches anchored in write-once storage (`dev-pack/docs/10` §5).
- **Partitioned pay runs:** one open run per person, with YTD written only at finalization (`dev-pack/docs/06` §9).
- **Frozen locked runs:** locked to the data known at the lock and to rules pinned by content hash, with immutable rule editions and nightly replay (`dev-pack/docs/06` §8).
- **Explicit pay combinations:** cited rules for how overtime, holiday and premium pay combine, checked for completeness before an agreement can go live (`dev-pack/docs/08` §5).

## Position codes and NOC (24 October 2026)

`dev-pack/docs/18` adds:

- NOC 2021 Version 1.0 loaded from Statistics Canada's publication, with every occupation's duties and requirements;
- any number of other classification schemes (internal, alphabetical, foreign) in any order;
- several codes per job, position or incumbent (salary surveys, departments, unique control numbers, legacy IDs), inherited by date;
- requirements proposed from NOC and decided by HR with a rationale;
- a similar-position search that uses NOC's hierarchy and cross-references and explains every result;
- NOC 2026 Version 1.0 (announced for December 2026) as a version to load with its correspondence table and a recoding campaign.

## Benchmarking, job evaluation and total rewards (24 October 2026)

`dev-pack/docs/19` adds:

- a job architecture: 15 career levels in four tracks and starter job families, as code schemes that map to any salary survey;
- the owner's Unified Competency Model as a shared framework (targets on jobs and positions, assessments of people, gaps for hiring, reviews, learning and succession), with level-by-level indicators proposed for the four functional competencies;
- a sample gender-neutral point-factor plan (12 factors, 1,000 points) that uses NOC, requirements and competency targets as evidence, with a rationale for every rating;
- a survey library: each organization imports its own licensed surveys, with masking respected and access enforced in the database; no survey data ships with CanDo;
- free public wage data by NOC code from Job Bank for every job;
- market pricing with lineage, the market line, grades, ranges and posting ranges;
- a benefits and practice scorecard (54 practices) read from the organization's own plans and policies;
- survey submissions with stable pseudonyms, one per position held, and no direct identifiers.

## People in several positions (24 October 2026)

`dev-pack/docs/20` adds, on top of the multiple assignments, rates, funding and reporting lines in `docs/17`:

- a position with two managers: each approves the days, hours or places they supervise (the default), or both must approve, or either can;
- leave and time requests split to the minute across positions and managers, from each position's shifts, with partial approval and no self-approval from another position;
- allowances, stipends, on-call pay and duty rates per position, and one-time payments per position or shared by earnings;
- one review per cycle with a section per position, each position rated by itself (an overall rating weighted by FTE and days held only where the organization chooses it, `docs/28` §6), and competency assessments per position;
- benefit plans per union agreement with coordination of benefits, for people in two unions or in a union and an exempt position;
- benefits when one position ends decided by the organization's own rules or by HR case by case, with a written reason, and never below the statutory floor (Ontario requires benefits during statutory notice).

## Quebec

Decided October 2026: build the French interface and Quebec data model from day one, launch payroll for the federal jurisdiction and the other 12 provinces and territories first, and add Quebec payroll in phase 2 after Revenu Québec certification (renewed every year). Until then, Quebec payroll can be exported to a certified Quebec provider. Organizations with a Quebec work location keep their own words in French.

## Statutory values

Payroll values are the 2026 CRA T4127 (122nd edition, 1 January 2026; 123rd edition, 1 July 2026). They change every January and some provinces change in July, so each value needs re-verification against the current CRA and Revenu Québec publications before build and every year after. CRA's CSV tables (attached by the owner each January and July) are the preferred source. The bi-weekly CPP basic exemption is $134.61 (CRA truncates $3,500 ÷ 26), corrected in Module 03 in October 2026.
