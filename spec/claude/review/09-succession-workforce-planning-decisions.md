# 09 Succession & Workforce Planning · Review decisions

Review started 29 Oct 2026 with Wael. Decisions are logged here round by round; the developer pack is updated when the review is complete.

**Status: applied 29 Oct 2026.** The decisions are in `dev-pack/docs/30-succession-workforce-planning-decisions.md`, migration `dev-pack/schema/0016_succession_workforce_decisions.sql` and its smoke test, the register, and the updates listed in docs/30 §15. Pre-filled, each organization's to change (the Q46 principle): equal weights on the five criteria; the starter potential criteria and nine-box names; plan reviews every 12 months with a reminder 30 days before; continuity sheets updated every 12 months; thin history under 10 people or 2 years; bias prompts on for groups of 10 or more. Off until each organization switches them on: talent reviews, the nine-box, workforce planning, and showing employees their own placement. Confirmed after the write-up: FB-039 (plans made before 0016 are marked org chart plans) is decided. Open: Indigenous leadership development with advisers (docs/16 Q51). Interpretations: "named on a plan" means its owner and members, and on a review its owner and participants, with HR by capability; a unionized role is a position with a collective agreement, and the caution applies to a direct-hire offer for it; the continuity sheet is seen by its keeper, the incumbent, the incumbent's manager (the holder of the position it reports to), the emergency successor and HR; a change to an approved plan's successors goes back through the route; thin history suggests the first level up that is not thin; the labour relations review covers redeployment as well as reduction in a unionized segment; language levels are the federal public service results (A, B, C, X below A, E exempt); the opt-in for recommended openings is Learning's skills consent.

Planned rounds: 1 scope, AI and access · 2 critical roles and risk · 3 talent review and the nine-box · 4 succession plans and talent pools · 5 career paths and internal mobility · 6 workforce planning · 7 headcount and budget planning, and Canadian considerations.

The principle from Modules 01 to 08 applies: every decision is a default each organization can change at setup or later, except legal floors and safety rules; routes and rules are the organization's, with reminders, cautions and recorded acknowledgements; CanDo pre-fills its suggested numbers at setup and the organization can change them (Q46).

Already decided elsewhere and not asked again: successor readiness levels are an organization list mapped to ready now, near term and long term (`docs/22` §3.4); workforce and position plans use the same plan of draft change sets as the org chart (`platform.plan`, SUCC-003); position control, over-budget approvals and complement (`docs/21` §5.2); funding sources and salary and burden projections (`docs/17` §8); the similar-position scorer suggests successors and career paths with its reasons (`docs/18` §7); competency gaps per position (`docs/19` §4.6); each position's rating is shown side by side for the nine-box (`docs/28` §6.1); adverse records stop counting after their sunset (`docs/28` §9.2); skills shown for internal opportunities only with the employee's consent (`docs/29` §7.2); development plans agreed by both (`docs/29` §7.3); employment equity groups use consented self-identification, never shown under 10 (`docs/25` §8.2); internal posting and seniority rules from agreements (`docs/23` §4.3); people decide and AI never decides (AGENTS rule 14).

## Round 1 · Scope, AI and access

| # | Decision |
| --- | --- |
| 1 | **One module for every organization, with parts switched on at setup:** everyone gets key roles and named backups; talent reviews and workforce planning scenarios are switched on by each organization. No size rule. |
| 2 | **Flight risk is the manager's assessment only** (low, medium or high, with a note); no prediction model, for privacy and fairness (closes the open question in `requirements/09`). |
| 3 | **Successor suggestions are rule-based, with their reasons:** CanDo's similar-position scorer (job, requirements, competencies, readiness); people choose. No AI. |
| 4 | **Succession data (potential, the nine-box, successor lists) is seen only by the people named on each talent review or plan, and HR;** every view is logged; a manager sees only the plans they are named on. |

## Round 2 · Critical roles and risk

| # | Decision |
| --- | --- |
| 1 | **Leaders score roles on five criteria, pre-filled with equal weights (impact, hard to replace, single point of failure, market scarcity, required by law); the organization changes the weights; HR confirms the critical list.** |
| 2 | **Positions the law requires (a municipal clerk or treasurer, a designated safety officer, a licensed professional) are always critical and must have a succession plan with an emergency successor;** HR is reminded until they do. |
| 3 | **Retirement risk uses pension eligibility dates and the intentions the employee chooses to share;** age itself is shown to planners only in totals, never per person. |
| 4 | **Work permit expiry is shown to HR only, as "the role may become vacant on this date",** with no immigration details to planners. |

## Round 3 · Talent review and the nine-box

| # | Decision |
| --- | --- |
| 1 | **The manager assesses potential against defined criteria:** starter criteria (learning agility, leadership, aspiration, engagement) with level descriptions, which the organization edits; the employee's own stated aspiration is always included. |
| 2 | **The nine-box is optional, off until the organization switches it on;** when on, the box names and suggested actions are editable, and each move is recorded with a reason and kept. |
| 3 | **Potential and nine-box placement are hidden from the employee by default;** the manager shares the readiness feedback they choose, and an organization can switch on showing the placement. |
| 4 | **Bias prompts are on in talent reviews, for groups of 10 or more:** self-identification groups only with consent and never under 10, as in pay gaps. |

## Round 4 · Succession plans and talent pools

| # | Decision |
| --- | --- |
| 1 | **The plan owner (often the incumbent's manager) proposes successors, with readiness for that role; the organization's route approves them** (starter: HR). |
| 2 | **A person is not asked before being named a successor;** plans stay confidential, the person's stated interest and mobility are shown beside the nomination, and a mismatch is flagged. |
| 3 | **For a unionized role, a succession plan is a development pipeline, not an appointment:** labelled as such; the role is still filled through the agreement's posting and seniority rules, and appointing a successor directly needs a caution. |
| 4 | **Plans are reviewed yearly (pre-filled, editable); the owner is reminded 30 days before,** and a plan for a role the law requires is also reviewed when its incumbent gives notice. |
| 5 | **Every critical role has an emergency (interim) successor and a one-page continuity sheet** (key contacts, systems, delegations) kept by the incumbent and seen by the incumbent, the interim successor, the manager and HR; no passwords or secrets are stored in CanDo; the incumbent is reminded to update it yearly. |
| 6 | **Talent pools: managers nominate and employees can apply; the pool owner approves through the organization's route;** each pool shows its criteria. |

## Round 5 · Career paths and internal mobility

| # | Decision |
| --- | --- |
| 1 | **Career paths come from the job architecture (career levels and job families) and the moves people actually made;** HR edits them, and each step shows the requirement and skill gaps. |
| 2 | **Pay ranges on career paths follow the organization's pay transparency setting** (Module 04). |
| 3 | **Recommended internal openings are rule-based (skills, requirements and stated interests, with reasons), only for employees who opt in to be visible,** as in Learning. |
| 4 | **Stretch assignments, gigs and secondments at launch, through positions:** posted as short assignments and done as a second position or an acting assignment, so pay, time and approvals already work. |

## Round 6 · Workforce planning

| # | Decision |
| --- | --- |
| 1 | **Supply is projected from the organization's own turnover history by segment, retirement eligibility and internal moves;** planners can adjust a rate with a reason. |
| 2 | **Demand comes from the organization's own drivers (beds, caseloads, students, projects, funded programs) and ratios (for example 1 supervisor per 12 staff);** CanDo pre-fills none. |
| 3 | **When turnover history is too thin (below a minimum of people or years), the planner can use the next level up (for example the department instead of the team) or enter a rate with a reason; and the organization can upload its historical data (from a previous system) to build the history** (Wael's own answer). Confirmed after the round: the organization can upload its past data; where history is still thin, CanDo shows the next level up as a suggestion and the planner accepts it or enters their own rate with a reason; "thin" means under 10 people or 2 years of data (pre-filled, editable). |
| 4 | **Scenarios are unlimited and versioned:** planners copy and change them, each saved version is kept for board or funder presentations, and scenarios are compared side by side. |
| 5 | **A gap strategy drafts actions, and people approve them in their own modules:** buy drafts a requisition forecast, build a training plan, reduce a draft plan; nothing happens until approved. |
| 6 | **A reduction in a unionized group is modelled only (cost and timing from the agreement's rules), with a caution and labour relations review before any real step;** nothing is sent. |

## Round 7 · Headcount and budget planning, and Canadian considerations

| # | Decision |
| --- | --- |
| 1 | **The annual position and headcount plan goes through the organization's route;** the starter route has department leaders submit, finance and HR review and the executive approve; a council or board step is added where the organization needs it. |
| 2 | **Once approved, the plan's changes become position budgets and complement on their effective dates;** position control and requisition approvals check them. |
| 3 | **Cost assumptions come from actuals, and the planner can edit them with a reason:** increases from the agreements and the compensation cycle, overtime and vacancy from the organization's own history, burden from payroll and benefits. |
| 4 | **The plan and forecast are exported as generic CSV and Excel files and in the payroll journal file profiles;** direct links to named planning tools (Adaptive, Anaplan, Sage) are built as customers need them. |
| 5 | **Employment equity: an aggregate report of designated groups in successor lists and talent pools against the workforce,** for HR and named reviewers, from consented self-identification only, never for a group under 10; goals tracked for employment equity plans. |
| 6 | **Indigenous community governance (for example council approval of senior appointments) is a step the organization adds to its own route;** Indigenous leadership development features are designed with advisers. |
| 7 | **Successors for bilingual positions: the position's language requirement is compared with the successor's recorded proficiency;** a gap shows in readiness and can feed a development plan. |
