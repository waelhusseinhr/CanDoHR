# CanDo HRIS — 07 Performance Management

Oct 17, 2026 · @Wael

> **Owner's review (28 October 2026):** the decisions are in `docs/28-performance-decisions.md`, which wins where this file differs. Changed here: a 5-point starter scale; CanDo suggests the rating from the weights and the manager chooses it with a reason for any difference; goals proposed by either side, agreed by both, aligned to the mission and kept with every amendment; new hires in the last 3 months get no rating; calibration on by default; the one-up look before release, with HR on the organization's concerns; signing means seen; only HR changes a final rating; each position rated by itself from 90 days worked, with no combined rating; 360° raters nominated by anyone, 3 to 5 per group, shown from 3 answers, for development only; monthly check-in nudges; improvement plans only after causes are ruled out and HR approves, never during protected leave; sunset clauses from the agreement or the organization; board evaluation of the chief executive later. The open questions are closed, except the advisers for the Indigenous and non-profit templates (`docs/16` Q49).

## Overview and scope

> **Draft status:** new specification, built on performance-management-workflow.svg, which defines three tracks integrated with Core HRIS.

Performance Management helps people know what is expected, get regular feedback, and have fair, documented decisions about their progress. It feeds compensation, promotion, learning and succession decisions.

**The three tracks from the workflow diagram:**

| Track | Stages | Covered in |
| --- | --- | --- |
| Annual performance cycle | Goal setting (individual objectives, development goals, metrics definition) → mid-year review (progress assessment, feedback exchange, goal adjustment) → year-end review (self-assessment, manager evaluation, final rating) → rewards and recognition (compensation review, promotion assessment) → next cycle | Goal setting; Reviews; Rewards handoff |
| Continuous performance management | Check-ins (one-on-one meetings) → peer feedback (360° reviews) → recognition (spot awards) → coaching (development support) | Continuous performance |
| Performance improvement process | Identification → PIP creation → regular reviews → final assessment → decision point | Performance improvement |

**Out of scope:** pay decisions (04, using this module's ratings); learning delivery (08); succession nominations (09); recognition programs beyond spot awards (10); discipline for conduct as opposed to performance (13).

## Goal setting

**Goal types:** individual objectives (what the employee will deliver); development goals (skills and growth, linked to Module 08); training goals for what the role needs (for example IT training for IT staff, not for finance staff); team, department and organizational goals, and the vision and mission, that individual goals align to; job-standard goals for roles where expectations are fixed (for example front-line or unionized roles).

**Metrics definition:** each goal has a measure, target, timeframe and weight; SMART prompts; optional key results under objectives (OKR style); quantitative goals can pull progress from connected data (sales, tickets, production) where available.

**Process (`docs/28` §4.1):** goals are a living, shared document. Organizational goals are published and managers cascade team goals; the employee or the manager proposes individual goals and links them to the goals above; they discuss and agree, and a goal stands once both have agreed. Every later amendment is kept with who made it, what changed, when and why. The employee records their own strengths and areas to develop beside the manager's view, and either can ask others for input at any time. Goal libraries by job help managers with less experience. AI drafting assistance can suggest goals from the job description, with the employee and manager editing and agreeing (with the platform assistant, off until the organization switches it on).

**Cycle configuration:** cycle dates per population (calendar or fiscal year, or anniversary-based); which elements apply (goals, competencies, values); weighting between goals and competencies (50/50 pre-filled, changed per cycle); employees eligible (people hired in the last 3 months of the cycle get goals and no rating, pre-filled and editable: `docs/28` §4.2).

## Mid-year and year-end reviews

**Mid-year review:** progress assessment against each goal (on track, at risk, off track, with comments); feedback exchange (employee and manager both comment); goal adjustment with reasons when priorities change; never a rating, so the conversation stays developmental (`docs/28` §4.3).

**Year-end review:**

| Step | Detail |
| --- | --- |
| Self-assessment | Employee rates and comments on goals, competencies and development; can attach evidence |
| Feedback inputs | Peer and 360° feedback gathered during the year or requested now; check-in notes visible to the manager |
| Manager evaluation | Ratings per goal and competency with required comments; for each position, CanDo suggests a rating from the cycle's weights and the manager chooses it, with a reason when it differs (`docs/28` §3.2) |
| Calibration | Part of each cycle unless the cycle turns it off; leaders and HR review rating distributions across teams; changes require a recorded reason |
| One-up look | The manager's own manager looks at the review through the organization's route; HR also looks when there is a concern the organization lists (`docs/28` §5.3) |
| Review conversation | Meeting held; manager records the date |
| Final rating and sign-off | Employee acknowledges (acknowledgement is not agreement), may add comments and ask HR to review it; HR decides with a reason whether to reopen it; after release only HR changes a rating, with a reason, and the employee is told (`docs/28` §5.4–§5.5) |

**Rating scales:** configurable (3, 4 or 5 points, 5 pre-filled); descriptors in English and French; separate scales for goals, competencies and values allowed.

**Competency models:** organization-wide values, job-family competencies and leadership competencies with behavioural indicators by level, shared with Modules 08 and 09.

**Calibration tools:** distribution charts by team, gender and other self-identified groups (aggregated), tenure and part-time status to spot bias; nine-box view (performance by potential) shared with Module 09, showing each position's rating side by side for people in several positions; side-by-side comparison of employees in similar roles.

## Rewards and recognition handoff

The final stage of the annual cycle passes results to the modules that act on them.

| Output | Destination | Use |
| --- | --- | --- |
| Final rating of each position | 04 Compensation | Merit matrix guideline for that position's increase |
| Promotion readiness assessment | 01 Core HR and 09 Succession | Promotion transactions; talent pools |
| Potential rating and nine-box placement | 09 Succession | Succession slates and development planning |
| Development goals and gaps | 08 Learning | Individual development plan and recommended learning |
| Recognition highlights | 10 Engagement & Recognition | Awards and nominations |
| Incentive metrics achieved | 04 Compensation | Bonus calculation |

**Promotion assessment:** manager nominates with justification; readiness criteria (performance history, competencies at next level, time in role); HR and leader review; approved promotions become job change transactions with pay set in Module 04.

**Timing:** compensation cycles open only after ratings are final and calibrated, so the order in the diagram is enforced by the workflow engine.

## Continuous performance management

**Check-ins (one-on-one meetings):** recurring meetings scheduled with calendar integration; shared agenda that both people add to; talking point templates (priorities, blockers, wellbeing, development); private manager notes and shared notes kept separate; action items with owners and dates; goals and recent feedback shown on the check-in page; nudges when a month passes with no check-in, editable per organization or team (`docs/28` §7.4).

**Peer feedback and 360° reviews:** request feedback from anyone at any time; structured 360° surveys with rater groups (manager, peers, direct reports, others); raters nominated by the employee, the manager or others; 3 to 5 raters per group, and a group's answers shown only when at least 3 answered, so nobody can be identified; the manager's input is never anonymous (`docs/28` §7.2); question sets by competency model; reports with group averages, gaps between self and others, and verbatim comments; 360° for development only by default, and a cycle can let it inform ratings (`docs/28` §7.3).

**Recognition (spot awards):** quick public or private recognition tied to company values; optional spot award amounts within manager budgets that flow to Payroll as taxable earnings; full recognition program features in Module 10.

**Coaching and development support:** development conversations logged; coaching notes; links to learning content and mentors; career conversation templates; employees can set and track their own development goals at any time.

**Feedback quality:** AI writing help with the platform assistant, off until the organization switches it on: clearer, specific, behaviour-based wording, flags for potentially biased language and feedback summaries, all marked as AI and editable; it never writes the assessment, rates, ranks or recommends an ending (`docs/28` §3.3).

## Performance improvement process

| Stage | What happens | System support |
| --- | --- | --- |
| 1. Identification | Manager identifies a gap through reviews, check-ins or results | The manager must rule out unclear expectations, training gaps, workload and accommodation needs (Module 13) before a plan is submitted (`docs/28` §8.1) |
| 2. PIP creation | Written plan with specific gaps, expected standards, measures, support (training, coaching, resources), check-in schedule and duration (60 days unless the plan sets its own) | Template; HR approval through the organization's route; employee acknowledgement before it starts; union representative as the agreement says, or a support person for non-union staff, recorded per meeting |
| 3. Regular reviews | Scheduled progress meetings with documented results against each measure | Meeting reminders; notes; progress tracking; extension with a reason and a later end |
| 4. Final assessment | Overall evaluation against the plan at the end date | Structured assessment form; HR review |
| 5. Decision point | Successful completion, extension, change of role, or termination for cause or without cause | Decision recorded with rationale; next step routed (Module 01 transaction, Module 11 separation, or closure) |

**Safeguards:** a PIP cannot start during a protected leave; where a protected ground may be involved, a caution asks for an accommodation review and HR approves with a reason (`docs/28` §8.3); documentation is kept consistent and factual because it may be evidence in a wrongful dismissal claim, grievance or human rights complaint; access is restricted to the manager chain, HR and the employee.

## Probation reviews and unionized environments

**Probation reviews:** scheduled automatically from the probation end date in Core HR (Module 02 covers probation management); interim reviews at set points (for example 30, 60 and 90 days); outcomes (confirm, extend where policy or agreement allows, or end employment) with reminders well before the end date so decisions are not missed by default; outcome publishes a status change to Core HR.

**Unionized employees:** many collective agreements limit formal performance ratings or prohibit linking them to pay. CanDo reads the limit from the agreement library (`docs/28` §9.1):

| Option | Use |
| --- | --- |
| Exclude from annual ratings | Agreements that do not permit appraisals |
| Development-only reviews | Goals and feedback without ratings or pay links |
| Agreement-specific forms | Review forms negotiated with the union |
| Representation | Union representative notification or attendance recorded for meetings that may lead to discipline |
| Access to file | Employee's right to see and respond to documents placed in their file, with time limits on retaining adverse records (“sunset clauses”) enforced automatically: after the agreement's period a record is hidden from managers and unusable in decisions, and kept for HR; non-union staff have no sunset unless the organization sets one (`docs/28` §9.2) |

**Non-profit and Indigenous organizations:** CanDo develops starter templates with advisers: team-based and strengths-based reviews, values drawn from the organization's own culture and teachings, and Elder or community input where an organization chooses; each organization edits them (`docs/28` §3.4).

## Fairness, AI and legal safeguards

**Bias checks:** rating distribution analysis by self-identified group, part-time status, leave history and remote or on-site work, in aggregate with small-group suppression; calibration prompts when a manager's ratings differ markedly by group; language analysis of written reviews for gendered or coded terms.

**Leave-adjusted reviews:** employees on statutory or disability leave during the cycle are evaluated on the time worked, and goals are prorated; under 90 days worked in a position, no rating; absence for protected reasons cannot lower a rating. Protected leave in the cycle is a concern that sends the review to HR where the organization lists it (`docs/28` §9.4).

**AI guardrails** (shared with Module 00): AI may summarise feedback, suggest goals or improve wording; it never assigns ratings, recommends terminations or ranks employees; every AI suggestion is visible as such and editable; employees can see when AI assisted with their review.

**Records:** reviews are part of the employee file; retention follows the schedule in Module 13; employees can request access to their performance records under privacy law; disputed content can be annotated by the employee.

## Data model, integrations and security

Detailed model: `docs/28` §11.

| Entity | Key fields |
| --- | --- |
| Review Cycle | Population, dates, elements, weights, scales, calibration, 360° use, stages |
| Goal | Owner, level, type, measure, target, weight, alignment parent, agreement by both, status, change history |
| Competency Model | Competencies, levels, behavioural indicators |
| Review | Employee, cycle, stage, rating mode, sections per position with suggested and chosen ratings, comments, calibration, one-up and HR looks, sign-offs |
| Calibration Session | Population, participants, changes with reasons |
| Check-in | Participants, date, agenda, shared and private notes, actions |
| Feedback | Giver, receiver, type, content, visibility |
| 360 Survey | Subject, raters by group and who nominated them, questions, responses (anonymized), report |
| Recognition | Giver, receiver, value, message, award amount |
| PIP | Employee, causes ruled out, gaps, standards, measures, support, schedule, meetings with representation, reviews, outcome |
| Adverse record | The review or plan, basis (agreement or organization), sunset date |

**Integrations:** Core HR (reporting lines, jobs, probation dates, leaves); Compensation (ratings, incentive results); Learning (development and training goals, competency gaps); Succession (potential, nine-box, readiness); Engagement (recognition); Compliance (accommodation flags, discipline cases); calendar systems (Microsoft 365, Google Workspace) for check-ins; business systems for goal metrics.

**Security:** employees see their own records; each position's manager sees their own section, and other sections only through HR; private manager notes are visible only to the author and HR; 360° responses are anonymous below the rater threshold; PIPs and calibration notes restricted to HR and the manager chain; adverse records past their sunset only to HR.

## Public-sector and large-employer performance

| Area | Requirement |
| --- | --- |
| Agreement limits | Bargaining units where the agreement limits or prohibits ratings get development-only reviews automatically, read from the agreement library |
| Excluded staff | Merit and performance pay for management and excluded groups under policy or government frameworks |
| Senior officials | Council or board evaluation of the chief administrative officer or chief executive, with confidential board workflows (later phase, `docs/28` §9.3) |
| Probation at scale | Probation reviews for hundreds of seasonal and new hires at once, with reminders before deadlines |
| Discipline separation | Performance processes kept separate from conduct discipline, which follows agreement procedures in Module 13 |
| Scale | Review cycles for tens of thousands with calibration by department and bargaining unit |

## People in several positions

Detailed design: `docs/20` §5, with the owner's decisions in `docs/28` §6, which take precedence.

- **One review, one section per position.** Each position held during the cycle has its own section, rated by that position's manager, with any functional or program managers as contributors. When the manager changes during the cycle, the previous manager rates their own period if it reached the minimum days. A section can be unrated where its agreement excludes ratings.
- **Each position stands by itself.** A position worked at least 90 days in the cycle is rated; a shorter period gets comments only. There is no combined rating across positions unless the organization chooses the FTE × days method or the primary manager.
- **Competencies per position.** Each position has its own job description, evaluation and competency targets. Assessments made in a position's section are used first for that position's gaps and development plan.
- **Merit per position.** Compensation cycles use each position's own section rating; succession and the nine-box show them side by side.

## How CanDo compares

| Vendor | Performance position | CanDo response |
| --- | --- | --- |
| HiBob | Strong performance, goals and engagement experience for mid-size employers | Match the experience |
| Workday, Dayforce, UKG | Talent suites for large employers | Match calibration and scale |
| BambooHR, Rippling, Humi, Collage | Reviews and goals in mid-tier plans | Match for SMBs; lead on union-aware reviews |

Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Reporting, implementation and open questions

**Reports:** cycle completion by stage and team; rating distributions before and after calibration; goal alignment and completion; check-in frequency; feedback volume; 360° participation; PIP counts, durations and outcomes; rating trends over time; correlation of ratings with pay increases and turnover (in Module 12).

**Implementation:**

| Step | Activities |
| --- | --- |
| 1. Design | Cycle timing, elements, scales, competency model, populations (including unionized exclusions), calibration approach, concerns that need HR |
| 2. Configure | Forms, scales, workflows, routes, notifications, permissions, templates in English and French |
| 3. Migrate | Prior-year ratings and current goals where available (needed for merit matrix and succession) |
| 4. Pilot | One department through goal setting before organization-wide launch |
| 5. Train | Managers on goal writing, feedback, calibration and PIP documentation; employees on self-assessment |

**Sources:** performance-management-workflow.svg (three tracks and their stages); Module 02 probation and status conversion; hr-integration-architecture.svg. Everything else is new drafting.

**Open questions:**

- [x] Default rating scale and whether to offer “no overall rating” as the default for new customers: 5 points pre-filled; CanDo suggests and the manager chooses each position's rating, with no combined rating across positions (`docs/28` §3, §6.1)
- [x] Anonymity threshold for 360°: at least 3 answers per group, 3 to 5 raters (`docs/28` §7.2)
- [x] Which AI writing features ship at launch: none; AI writing help comes with the platform assistant, off until switched on (`docs/28` §3.3)
- [x] Indigenous and non-profit review templates: developed with advisers as starters each organization edits (`docs/28` §3.4); who advises is `docs/16` Q49

**October 2026 review:** added public-sector and large-employer requirements and competitor comparison.

**October 2026 (several positions):** added review sections per position, the overall rating and competency assessments per position (`docs/20` §5).

**28 October 2026 (owner's review):** the decisions in `docs/28`.
