# 30 · Succession and workforce planning decisions

Oct 29, 2026 · @Wael

This document records the owner's review of Module 09 (Succession & Workforce Planning) and turns each decision into something the build can follow: a setting with its default, a database check, a rule the organization sets, a route it edits, a caution, or a screen behaviour. The review went round by round; the working record is `claude/review/09-succession-workforce-planning-decisions.md` in the project.

It covers how the module is switched on, AI, who sees succession data, critical roles and the positions the law requires, flight risk, retirement and vacancy dates, career aspirations, talent reviews, potential, the nine-box, bias prompts, succession plans and their approval, emergency successors and continuity sheets, unionized roles, talent pools, career paths, internal mobility, workforce segments, supply and thin history, demand drivers, scenarios, gap strategies, reductions in unionized groups, the annual position plan, cost assumptions, exports, employment equity, Indigenous governance and bilingual successors.

**Precedence.** On these topics this document wins over `requirements/09` and the SUCC stories in `stories/07-to-10-talent.md`. `docs/04` still governs plans of draft change sets on the org chart, `docs/17` §8 funding sources and salary and burden projections, `docs/18` §7 the similar-position scorer, `docs/19` §4.6 competency gaps, `docs/21` §5.2 position control and complement, `docs/23` §4.3 internal postings and seniority, `docs/28` §6.1 performance ratings, `docs/29` §7 skills consent and development plans, and `docs/22` still wins on values, defaults, languages and fallbacks. §15 lists every place that changes. The schema is `schema/0016_succession_workforce_decisions.sql` (migration 0016, Step 1), checked by `tests/schema/schema_0016_smoke.sql`.

**The owner's rules for this module.**

1. Every decision is a default each organization can change at setup or later; only legal floors and safety rules are fixed. CanDo pre-fills its suggested numbers at setup, and the organization keeps or changes them (Q46).
2. One module for every organization. Key roles, named backups and succession plans are always there; talent reviews, the nine-box and workforce planning are switched on by each organization. No size rule.
3. People decide; CanDo suggests by rule. Flight risk is the manager's assessment, successors and openings are suggested by fixed rules with their reasons, and gap strategies only draft actions that people approve in their own modules. No AI and no prediction model.
4. Succession data is among the most sensitive in CanDo. It is seen only by the people named on a review or plan, and HR; every view is logged; age is shown only in totals and immigration details never reach planners.

---

## 1. Decisions at a glance

| # | Decision | Setting or rule | Section |
| --- | --- | --- | --- |
| R1.1 | One module for every organization: key roles and named backups for everyone; talent reviews and workforce planning switched on by each organization; no size rule | `succession.talent_review_enabled`, `workforce.planning_enabled` (off) | §3.1 |
| R1.2 | Flight risk is the manager's assessment only (low, medium or high, with a note); no prediction model | `talent.flight_risk_assessment` | §4.3 |
| R1.3 | Successor suggestions are rule-based, with their reasons (the similar-position scorer); people choose; no AI | `docs/18` §7 | §3.3 |
| R1.4 | Succession data is seen only by the people named on each review or plan, and HR; every view logged | `talent.named_on()`, `talent.succession_view_log` | §3.4 |
| R2.1 | Leaders score roles on five criteria with equal weights pre-filled; the organization changes the weights; HR confirms the critical list | `succession.critical_weights`; `talent.critical_role` | §4.1 |
| R2.2 | Positions the law requires are always critical and must have a succession plan with an emergency successor; HR reminded until they do | `required_by_law`; `EMERGENCY_SUCCESSOR_REQUIRED`; `talent.required_roles_without_plan()` | §4.2 |
| R2.3 | Retirement risk from pension eligibility and the intentions the employee shares; age shown only in totals | `talent.retirement_outlook` | §4.4 |
| R2.4 | Work permit expiry shown to HR only, as a date the role may become vacant; no immigration details to planners | `talent.vacancy_risk` | §4.5 |
| R3.1 | The manager assesses potential against defined criteria the organization edits; the employee's stated aspiration always included | `succession.potential_criteria`; `talent.potential_assessment` | §5.2 |
| R3.2 | The nine-box is optional, off until switched on; box names and actions editable; each move recorded with a reason | `succession.nine_box_enabled` (off), `succession.nine_box_boxes`; `PLACEMENT_REASON_REQUIRED` | §5.3 |
| R3.3 | Potential and placement hidden from the employee by default; the manager shares the readiness feedback they choose | `succession.employee_sees_placement` (off) | §5.4 |
| R3.4 | Bias prompts on in talent reviews, for groups of 10 or more | `succession.bias_prompts` (on); `privacy.min_group_size_self_id` | §5.5 |
| R4.1 | The plan owner proposes successors with readiness for that role; the organization's route approves | Route `succession_plan` (starter: HR) | §6.1 |
| R4.2 | A person is not asked before being named; their stated interest and mobility shown, a mismatch flagged | `successor.aspiration_mismatch` | §6.2 |
| R4.3 | For a unionized role, a plan is a development pipeline, not an appointment; a direct appointment needs a caution | `development_only`; caution `succession.appoint_without_posting` | §6.3 |
| R4.4 | Plans reviewed yearly, owner reminded 30 days before; a plan for a role the law requires also reviewed when its incumbent gives notice | `succession.plan_review_months`: 12, `succession.plan_review_reminder_days`: 30 | §6.4 |
| R4.5 | Every critical role has an emergency successor and a one-page continuity sheet; no passwords or secrets; updated yearly | `talent.continuity_sheet`; `SECRET_NOT_ALLOWED`; `succession.continuity_review_months`: 12 | §6.5 |
| R4.6 | Talent pools: managers nominate, employees can apply; the pool owner approves through the route; criteria shown | Route `talent_pool_membership` | §6.6 |
| R5.1 | Career paths from the job architecture and the moves people made; HR edits them; each step shows the gaps | `talent.career_path_step`, `talent.observed_job_moves()` | §7.1 |
| R5.2 | Pay ranges on career paths follow the organization's pay transparency setting | `transparency.employee_view` (`docs/25` §8.1) | §7.2 |
| R5.3 | Recommended internal openings are rule-based, only for employees who opt in to be visible | `talent.skills_visible()` (`docs/29` §7.2) | §8.1 |
| R5.4 | Stretch assignments, gigs and secondments at launch, through positions | Second or acting assignments (`docs/20`, `docs/21`) | §8.2 |
| R6.1 | Supply from the organization's own turnover history by segment, retirement eligibility and internal moves; rates adjusted with a reason | `talent.supply_rate` | §9.2 |
| R6.2 | Demand from the organization's own drivers and ratios; CanDo pre-fills none | `talent.workforce_driver`, `talent.workforce_ratio` | §9.3 |
| R6.3 | Thin history (under 10 people or 2 years): the next level up as a suggestion, or the planner's rate with a reason; history can be uploaded | `workforce.thin_history`; `HISTORY_TOO_THIN` | §9.2 |
| R6.4 | Scenarios unlimited and versioned; saved versions kept; compared side by side | `SCENARIO_VERSION_LOCKED` | §9.4 |
| R6.5 | A gap strategy drafts actions; people approve them in their own modules | `talent.gap_strategy` | §9.5 |
| R6.6 | A reduction in a unionized group is modelled only, with a caution and labour relations review before any real step | `LABOUR_RELATIONS_REVIEW_REQUIRED`; caution `workforce.reduction_unionized` | §9.5 |
| R7.1 | The annual position plan goes through the organization's route: leaders submit, finance and HR review, the executive approves | Route `position_plan` | §10.1 |
| R7.2 | Once approved, the plan's changes become position budgets and complement on their effective dates | `docs/21` §5.2 | §10.2 |
| R7.3 | Cost assumptions from actuals; the planner edits them with a reason | `talent.plan_assumption` | §10.3 |
| R7.4 | Plan and forecast exported as generic CSV and Excel files and in the payroll journal profiles; named planning tools as customers need them | Export profiles | §10.5 |
| R7.5 | Employment equity: aggregate report of designated groups in successor lists and pools against the workforce; consented self-identification only; never under 10 | Report | §10.6 |
| R7.6 | Indigenous community governance is a step the organization adds to its own route; Indigenous leadership development features designed with advisers | Route step; Q51 | §10.7 |
| R7.7 | Successors for bilingual positions: the language requirement compared with the successor's proficiency; a gap shows in readiness | `talent.language_proficiency`, `talent.language_gap()` | §10.4 |

---

## 2. How the module is set up

### 2.1 Settings

| Setting | Decides | CanDo default | Set per |
| --- | --- | --- | --- |
| `succession.talent_review_enabled` | Whether talent reviews (potential and review meetings) are used | Off | Organization, employer |
| `succession.nine_box_enabled` | Whether talent reviews use the nine-box | Off | Organization, employer |
| `workforce.planning_enabled` | Whether workforce planning (segments, supply, demand, scenarios, gap strategies) is used | Off | Organization |
| `succession.critical_weights` | Weights of the five criteria leaders score a role on, adding up to 100 | 20 each: impact, hard to replace, single point of failure, market scarcity, required by law | Organization, employer |
| `succession.potential_criteria` | The criteria and level descriptions managers assess potential against, in English and French | Learning agility, leadership, aspiration, engagement, each low, moderate or high with a description | Organization, employer |
| `succession.nine_box_boxes` | Names and suggested actions of the nine boxes | Future leader, rising star, emerging talent, high performer, core contributor, developing, trusted expert, solid contributor, needs attention | Organization, employer |
| `succession.employee_sees_placement` | Whether employees see their own potential and placement | Off: the manager shares the feedback they choose | Organization, employer |
| `succession.bias_prompts` | Bias prompts in talent reviews | On, for groups of `privacy.min_group_size_self_id` (10) or more | Organization, employer |
| `succession.plan_review_months` | Months between reviews of a succession plan | 12 | Organization, employer |
| `succession.plan_review_reminder_days` | Days before the review date when the owner is reminded | 30 | Organization, employer |
| `succession.continuity_review_months` | Months between updates of a continuity sheet | 12 | Organization, employer |
| `workforce.thin_history` | Below how many people or years a segment's history is too thin to project from | 10 people, 2 years | Organization |

Pre-filled values follow the Q46 rule: the setup screen shows CanDo's suggestion and the organization keeps or changes them. The equal weights, the starter criteria and box names, and the 12-month cycles are CanDo's suggestions, which the owner accepted; "thin" at 10 people or 2 years was confirmed after Round 6. No setting is left to choose at setup.

### 2.2 Set up by each organization

| What | Where | Until it is set |
| --- | --- | --- |
| Its critical roles, scored by leaders and confirmed by HR, and the positions the law requires with their legal basis | `talent.critical_role` (§4.1) | No reminders; succession plans can still be made |
| Readiness levels | The organization list `succession_readiness`, mapped to ready now, near term and long term (`docs/22` §3.4) | The starter list |
| Workforce segments, their drivers and ratios | `talent.workforce_segment`, `talent.workforce_driver`, `talent.workforce_ratio` (§9) | No projections |
| Past turnover from a previous system | Upload to `talent.turnover_history` (§9.2) | CanDo's own records only |
| Talent pools and their criteria | `talent.talent_pool` (§6.6) | No pools |
| Career paths | Proposed from the job architecture and real moves; HR confirms (§7.1) | Suggestions only |
| A council, board or community approval step | Added to the `position_plan` or `succession_plan` route (§10.1, §10.7) | The starter route |

### 2.3 Routes

Three starter routes are copied to every organization, and each organization edits them like any other route (`docs/23` §2.2):

| Route | Subject | Steps |
| --- | --- | --- |
| `succession_plan` | A succession plan, and any change to its successors once approved | HR |
| `talent_pool_membership` | A nomination or application to a talent pool | The pool's owner |
| `position_plan` | The annual position and headcount plan | Finance; HR; the executive |

The approver kind `subject_owner` is new: the step goes to the owner named on the subject (a pool's owner). No one approves their own plan or nomination, and a nominee never approves their own membership (`SELF_APPROVAL`). A council or board approval of the position plan, or a community approval of a senior appointment, is a step the organization adds (§10.1, §10.7).

### 2.4 Cautions

| Caution | When | Section |
| --- | --- | --- |
| `succession.appoint_without_posting` | A direct-hire offer is approved for a unionized position whose succession plan is for development only | §6.3 |
| `workforce.reduction_unionized` | A reduction or redeployment in a unionized segment is released to its module | §9.5 |

Both always need a written reason and show the law and the agreement.

---

## 3. Scope, AI and access

### 3.1 One module, parts switched on (R1.1)

Every organization gets critical roles, named backups, emergency successors, continuity sheets, succession plans, talent pools and career paths. Talent reviews (`succession.talent_review_enabled`), the nine-box (`succession.nine_box_enabled`) and workforce planning (`workforce.planning_enabled`) start off and are switched on at setup or later; a review or scenario created while its part is off is refused (`FEATURE_OFF`). There is no minimum size: a 40-person organization can switch on workforce planning and a 5,000-person one can keep it off. This closes the open question on minimum customer size in `requirements/09`.

### 3.2 No prediction model (R1.2)

CanDo has no flight risk model, no AI potential score and no AI successor ranking. Flight risk is the manager's assessment (§4.3). Engagement signals from Module 10 and the market ratio from Module 04 are shown in aggregate beside a role's risk, never as a score about a person.

### 3.3 Suggestions by rule (R1.3)

Successors and career moves are suggested by CanDo's similar-position scorer (`docs/18` §7), which compares job, requirements, competencies and readiness and shows its reasons. The plan owner chooses. No AI is used.

### 3.4 Who sees succession data (R1.4)

Potential assessments, nine-box placements, successor lists and continuity sheets are seen only by the people named on the talent review or plan (its participants or members and its owner) and by HR. A manager sees only the plans and reviews they are named on, not every plan for their unit. `talent.named_on()` answers who is named; the API adds HR by capability and writes each view to `talent.succession_view_log` (viewer, subject, time). Employees never see other employees' placements. Flight risk and retirement outlooks are shown to the people named on a plan and HR; vacancy dates to HR only (§4.5).

---

## 4. Critical roles and risk

### 4.1 Scoring roles (R2.1)

Leaders score a position from 1 to 5 on each of the five criteria in `succession.critical_weights`: impact on strategy or operations, how hard it is to replace, whether it is a single point of failure, market scarcity, and whether the law requires it. CanDo computes the weighted score (1 to 5). The organization changes the weights, which must add up to 100 (`CRITICAL_WEIGHTS_INVALID`); a role scored on a different set of criteria, or outside 1 to 5, is refused (`CRITICAL_SCORE_INVALID`). The leader proposes; HR confirms the critical list, never the leader who scored it (`SELF_APPROVAL`). Score changes are kept with the row's history.

### 4.2 Positions the law requires (R2.2)

A position the law requires (a municipal clerk or treasurer under Ontario's Municipal Act, 2001, ss. 228 and 286, a designated safety officer, a licensed professional the organization must have) is marked `required_by_law` with its legal basis (`critical_role_law`). It is always critical. Its succession plan cannot be approved without an emergency successor (`EMERGENCY_SUCCESSOR_REQUIRED`), and `talent.required_roles_without_plan()` lists every such position with no approved plan or no emergency successor, so HR is reminded until both exist.

### 4.3 Flight risk (R1.2)

The manager records low, medium or high with a note on what it is based on (`talent.flight_risk_assessment`). An employee never assesses their own (`SELF_REVIEW`). It is never the only basis for an action and is not shown to the employee.

### 4.4 Retirement (R2.3)

Retirement risk uses the date a person becomes eligible under their pension plan, agreement or the organization's policy (`talent.retirement_outlook`), and what the employee chooses to share: an intended window and interest in phased retirement. An intention is recorded only when the employee shared it (`retirement_intention`). Canada has no mandatory retirement age in most cases, and age is a protected ground: CanDo shows age only in totals (by department or occupation) from the analytics service, never per person, and never uses eligibility to pressure anyone to retire.

### 4.5 A date a role may become vacant (R2.4)

When a work authorization or a term ends, HR records the date the role may become vacant (`talent.vacancy_risk`: authorization end, term end or other). Planners see only that a role in their plan has a possible vacancy date, never the reason or any immigration detail. CanDo stores no permit numbers or immigration status here.

### 4.6 Career aspirations

Each person keeps one career aspiration (`talent.career_aspiration`): target jobs, a description, mobility (relocation and locations), a timeframe and whether they are open to being considered for succession. It is the employee's own and is shown beside potential assessments (§5.2) and nominations (§6.2).

---

## 5. Talent reviews, potential and the nine-box

### 5.1 The talent review

A talent review (`talent.talent_review`) has a period, its participants (the leaders in the meeting), an owner (usually HR) and whether it uses the nine-box, filled from `succession.nine_box_enabled`. Inputs are gathered before the meeting: ratings history from Performance (each position's rating side by side, `docs/28` §6.1), potential, aspirations, skills and credentials, and time in role.

### 5.2 Potential (R3.1)

The manager assesses potential against the organization's criteria in `succession.potential_criteria` (starter: learning agility, leadership, aspiration, engagement, each low, moderate or high with a description in English and French). Every criterion is assessed (`INPUT_REQUIRED`), only the organization's criteria are accepted (`POTENTIAL_CRITERION_UNKNOWN`), and no one assesses their own potential (`SELF_REVIEW`). The employee's own stated aspiration is copied onto each assessment, or marked as not stated, so the meeting always sees it.

### 5.3 The nine-box (R3.2)

The nine-box is off until the organization switches it on; a review created while it is off does not use it, and a placement in such a review is refused (`FEATURE_OFF`). Placements are potential by performance (low, moderate, high); the box names and suggested actions come from `succession.nine_box_boxes`, which the organization edits. Moving someone to another box needs a reason (`PLACEMENT_REASON_REQUIRED`) and is kept in `talent.placement_history` with who moved them and why.

### 5.4 What the employee sees (R3.3)

By default employees do not see their potential or placement. They see their own aspiration, their development plan and the readiness feedback their manager chooses to share. An organization can switch on `succession.employee_sees_placement` to show employees their own placement; never anyone else's.

### 5.5 Bias prompts (R3.4)

The review screen prompts when a group is consistently placed lower: part-time employees (`talent.bias_check_part_time()`), people returning from parental leave, and members of employment equity groups. A prompt shows only when every group compared has at least `privacy.min_group_size_self_id` people (10), and equity groups use only consented self-identification, as in pay gaps (`docs/25` §8.2). The prompt asks the meeting to look again; it changes nothing by itself.

---

## 6. Succession plans and talent pools

### 6.1 Plans and their approval (R4.1)

A succession plan (`talent.succession_plan`) covers one position: its owner (often the incumbent's manager), other members named on it, the emergency successor, whether external hiring is an option, and its successors with readiness for that role from the organization's `succession_readiness` list. The owner submits it with the organization's `succession_plan` route (starter: HR); it is approved when the route is complete (`ROUTE_APPROVALS_MISSING`), and the owner never approves it (`SELF_APPROVAL`). Successors are approved with the plan. A change to a successor's readiness, a new successor or a removal on an approved plan sends the plan back through the route, and approvals given before the change no longer count. Each successor can link to their own development plan (`docs/29` §7.3).

### 6.2 Naming a successor (R4.2)

A person is not asked before being named; plans stay confidential (§3.4). Beside each nomination CanDo shows the person's stated interest and mobility (§4.6), and flags a mismatch (`aspiration_mismatch`) when they said they are not open to succession or their target jobs do not include this one. The owner decides; a mismatch is a prompt to talk, not a block.

### 6.3 Unionized roles (R4.3)

A plan for a position under a collective agreement is marked `development_only`: it builds a development pipeline and does not appoint anyone. The role is still filled through the agreement's posting and seniority rules (`docs/23` §4.3). Approving a direct-hire offer for such a position needs the caution `succession.appoint_without_posting` with a reason (for example the posting closed with no internal bidders).

### 6.4 Reviews (R4.4)

When a plan is approved, its review date is set `succession.plan_review_months` (12) later. `talent.plans_due_for_review()` reminds the owner `succession.plan_review_reminder_days` (30) before, and every day once it is overdue. A plan for a position the law requires is also reviewed when its incumbent gives notice: the separation recorded in Core HR (`docs/21`) opens a review task for the plan's owner and HR.

### 6.5 Emergency successor and continuity sheet (R4.5)

Every critical role names an emergency (interim) successor on its plan, and the incumbent keeps a one-page continuity sheet (`talent.continuity_sheet`): key contacts, systems and how access is granted, and delegations. It is seen by the incumbent, the emergency successor, the incumbent's manager and HR (`talent.continuity_sheet_can_see()`). CanDo stores no passwords, PINs, tokens or other secrets: a key or note that holds one is refused (`SECRET_NOT_ALLOWED`), and the sheet says where they are kept instead. The incumbent is reminded to update it every `succession.continuity_review_months` (12).

### 6.6 Talent pools (R4.6)

A talent pool (`talent.talent_pool`) has an owner and its criteria in English and French, shown to everyone who can see the pool. Managers nominate; employees can apply themselves where the pool accepts applications (`POOL_CLOSED_TO_APPLICATIONS`). The pool owner approves through the `talent_pool_membership` route; neither the nominating manager nor the nominee approves. Declining or ending a membership states why. Pools can hold cohorts such as future managers or Indigenous leadership development (§10.7).

---

## 7. Career paths

### 7.1 Paths (R5.1)

Career path steps (`talent.career_path_step`) link one job to another as a vertical, lateral or cross-functional move. CanDo proposes them from the job architecture (career levels and job families, `docs/19`) and from the moves people actually made (`talent.observed_job_moves()`); HR confirms and edits them. Each step shows the requirement and competency gaps against the employee's own profile (`docs/18` §6, `docs/19` §4.6).

### 7.2 Pay ranges (R5.2)

A step shows the target job's pay range only where the organization's `transparency.employee_view` setting lets employees see ranges (`docs/25` §8.1).

---

## 8. Internal mobility

### 8.1 Recommended openings (R5.3)

The internal job board shows Module 02 postings. Recommended openings come from fixed rules (skills, requirements and the employee's stated interests), each with its reasons, and only for employees who opted in to be visible (`talent.skills_visible()`, `docs/29` §7.2). Internal candidate rules from collective agreements apply as in Recruitment (`docs/23` §4.3).

### 8.2 Stretch assignments, gigs and secondments (R5.4)

These are posted as short assignments and done through positions: a second position (`docs/20`) or an acting assignment (`docs/21`), with an end date. Pay, time, approvals and the return to the home position already work there; no separate gig marketplace at launch.

---

## 9. Workforce planning

### 9.1 Segments

A segment (`talent.workforce_segment`) is defined by the organization's own scope: org units, jobs, job families, career levels, locations, agreements, employment types or employers (`SEGMENT_SCOPE_UNKNOWN` for anything else). Each can name the next level up (`parent_code`), used when its history is thin. A segment with agreements is unionized for §9.5.

### 9.2 Supply and thin history (R6.1, R6.3)

Supply is projected from each segment's own turnover history, retirement eligibility (§4.4, in totals) and internal moves. History comes from CanDo's records and from what the organization uploads from a previous system (`talent.turnover_history`, `source` upload with its file); the same period cannot be loaded twice. `talent.history_summary()` gives people, years and the annual rate; a segment is thin below `workforce.thin_history` (10 people or 2 years). For a thin segment CanDo suggests the rate of the first level up that is not thin (`talent.suggested_turnover_rate()`); the planner accepts it (`next_level`) or enters their own rate with a reason (`planner`). A rate from a thin segment's own history is refused (`HISTORY_TOO_THIN`), and every planner's rate states why (`SUPPLY_RATE_REASON_REQUIRED`).

### 9.3 Demand (R6.2)

Demand comes from the organization's own drivers (beds, caseloads, students, lane kilometres, projects, funded programs) by segment and period, and its ratios (units per FTE, for example 12 staff per supervisor). `talent.demand_fte()` divides each driver by its ratio. CanDo pre-fills no drivers or ratios.

### 9.4 Scenarios (R6.4)

Scenarios (`talent.workforce_scenario`) are unlimited. A planner copies a version to change it (`copied_from`); a saved version is kept as it was, with its drivers, ratios and rates (`SCENARIO_VERSION_LOCKED`), for board, council or funder presentations. Scenarios are compared side by side on headcount, gaps and cost.

### 9.5 Gap strategies and unionized reductions (R6.5, R6.6)

For each segment and period the gap is demand minus supply. A gap strategy (`talent.gap_strategy`) is build, buy, borrow, bind, bot, redeploy or reduce, and drafts an action in its own module: a training plan, a requisition forecast, a contingent workforce budget, a retention action, a process change or a draft position plan. Nothing happens until the draft is approved there. A reduction or redeployment in a unionized segment is modelled only (cost and timing from the agreement's layoff, bumping and recall rules); releasing it needs a labour relations reviewer other than the person releasing it (`LABOUR_RELATIONS_REVIEW_REQUIRED`) and the caution `workforce.reduction_unionized` with a reason. Nothing is sent to the union or to employees from here.

---

## 10. Headcount and budget planning, and Canadian considerations

### 10.1 The annual position plan (R7.1)

The annual position and headcount plan is a plan of draft change sets (`platform.plan`, `docs/04`) of kind `position_budget` with its fiscal year: new positions, eliminations and changes with effective dates, each with its cost. Department leaders submit it with the organization's `position_plan` route; the starter route has finance, HR and the executive approve. A council or board step is added where the organization needs it. The plan's owner never approves it (`SELF_APPROVAL`), and it is approved only when the route is complete (`ROUTE_APPROVALS_MISSING`). Org chart plans keep working as before; plans made before 0016 are marked as org chart plans (FB-039).

### 10.2 Budgets and complement (R7.2)

Once approved, the plan's change sets apply on their effective dates and become position budgets and complement. Position control and requisition approvals check them as they check any position budget (`docs/21` §5.2, `docs/23`). Tracking compares the plan with actual headcount and cost by month.

### 10.3 Cost assumptions (R7.3)

Assumptions (`talent.plan_assumption`) come from actuals: increases from the agreements and the compensation cycle, overtime and vacancy from the organization's own history, burden from payroll and benefits, each with its source (the agreement version, cycle or period). The planner can change one with a reason. Salary and burden projections follow `docs/17` §8.

### 10.4 Bilingual successors (R7.7)

A position's language requirement comes from the organization's `language_requirement` list (for example English and French at level B). Proficiency is recorded per person and language (`talent.language_proficiency`) with the federal public service results: A, B and C, X below A, and E for exempt from further testing. `talent.language_gap()` shows what a successor lacks for a position needing two languages, and the gap shows beside their readiness and can feed their development plan.

### 10.5 Exports (R7.4)

The plan and forecast are exported as generic CSV and Excel files and in the payroll journal file profiles (`docs/24` §8.3). Direct links to named planning tools (Adaptive Planning, Anaplan, Sage Intacct Planning) are built as customers need them. This closes the open question on finance planning integrations in `requirements/09`.

### 10.6 Employment equity (R7.5)

An aggregate report compares designated groups in successor lists and talent pools with the workforce, for HR and the reviewers the organization names. It uses consented self-identification only and never shows a group under 10 (`docs/25` §8.2). Goals are tracked for employment equity plans (Module 13).

### 10.7 Indigenous community governance (R7.6)

Where an organization's governance requires it (for example council approval of senior appointments), it adds that step to its own `succession_plan`, `position_plan` or offer route. Indigenous leadership development features (cohorts, partnerships with Indigenous training organizations, community-member hiring plans) are designed with Indigenous advisers before they are built (`docs/16` Q51). Data governance follows Module 01.

---

## 11. Fallbacks

One added, confirmed by the owner after the write-up:

| ID | When | Then | Status |
| --- | --- | --- | --- |
| FB-039 | Migration 0016 meets plans made before it | They are marked org chart plans, the only feature that made plans before 0016 | Decided (owner, 29 Oct 2026) |

Everything else is a setting with its default (§2.1) or a column filled from one: a talent review's nine-box from `succession.nine_box_enabled` (`docs/22` §3).

---

## 12. Data model (migration 0016)

| Object | What it holds |
| --- | --- |
| Settings in §2.1 | 12 settings with CanDo defaults; `talent.feature_on()` |
| `talent.critical_role` (weighted score computed), `talent.flight_risk_assessment`, `talent.retirement_outlook`, `talent.vacancy_risk`, `talent.career_aspiration`; `talent.required_roles_without_plan()` | §4 |
| `talent.talent_review` (nine-box filled from the setting), `talent.potential_assessment` (aspiration copied), `talent.nine_box_placement` (box computed), `talent.placement_history`; `talent.bias_check_part_time()` | §5 |
| `talent.succession_plan` (development only computed; review date from the setting), `talent.successor` (readiness from the organization list; aspiration mismatch and language gap computed), `talent.continuity_sheet` (update date from the setting), `talent.succession_view_log`; `talent.plans_due_for_review()`, `talent.continuity_sheet_can_see()`, `talent.named_on()`; trigger on `recruit.offer` | §3.4, §6 |
| `talent.talent_pool`, `talent.pool_member` | §6.6 |
| `talent.career_path_step`; `talent.observed_job_moves()` | §7 |
| `talent.workforce_segment`, `talent.turnover_history`, `talent.workforce_scenario`, `talent.workforce_driver`, `talent.workforce_ratio`, `talent.supply_rate`, `talent.gap_strategy`; `talent.history_summary()`, `talent.suggested_turnover_rate()`, `talent.demand_fte()` | §9 |
| `platform.plan` gains `kind`, `fiscal_year`, `route_id`, `submitted_at`; `talent.plan_assumption` | §10.1–§10.3 |
| `talent.language_proficiency`; `talent.language_gap()` | §10.4 |
| Route subjects `succession_plan`, `talent_pool_membership`, `position_plan`; approver kind `subject_owner`; three starter routes; two cautions; `check_approval_task()` with the new subjects | §2 |

Every new tenant table has `tenant_id` with forced row-level security; text fields are registered as translatable (`docs/22` §4.3). The starter routes are copied to existing organizations, skipping one that keeps a third language as required for its data (FB-035). `talent.succession_slate` (0001) is kept as history and read-only; the data migration moves its rows into plans and successors, mapping its readiness through the organization list.

---

## 13. Validation, API and events

**Errors added by 0016:** `FEATURE_OFF`, `CRITICAL_WEIGHTS_INVALID`, `CRITICAL_SCORE_INVALID`, `POTENTIAL_CRITERION_UNKNOWN`, `PLACEMENT_REASON_REQUIRED`, `EMERGENCY_SUCCESSOR_REQUIRED`, `SECRET_NOT_ALLOWED`, `POOL_CLOSED_TO_APPLICATIONS`, `SEGMENT_SCOPE_UNKNOWN`, `HISTORY_TOO_THIN`, `SUPPLY_RATE_REASON_REQUIRED`, `SCENARIO_VERSION_LOCKED`, `LABOUR_RELATIONS_REVIEW_REQUIRED`. Existing ones used: `INPUT_REQUIRED`, `SELF_APPROVAL`, `SELF_REVIEW`, `ROUTE_APPROVALS_MISSING`, `CAUTION_NOT_ACKNOWLEDGED`, `LIST_VALUE_UNKNOWN`.

**Checks in the application (Step 17 unless noted), not the database:** HR's capability for succession data and writing every view to the log; age in totals only, from the analytics service; the risk matrix and bench strength; the similar-position scorer's suggestions with their reasons; review meeting tools (talent cards, comparison, drag-and-drop placement); prompts for people returning from parental leave and equity groups; the review task when the incumbent of a position the law requires gives notice (with Steps 5 and 16); resolving the `subject_owner` approver; recommended openings for people who opted in; turning gap strategy drafts into training plans, requisition forecasts and draft position plans in their modules; projecting supply and comparing scenarios; applying an approved position plan's change sets (with Steps 4 and 6); cost projections (with Steps 12 and 15); the CSV, Excel and journal exports (with Step 12); the employment equity report (with Step 18).

**API** (added to `api/openapi.yaml` in Step 17): `GET/POST /succession/critical-roles` with `confirm`; `GET /succession/critical-roles/missing-plans`; `POST /people/{id}/flight-risk`, `/people/{id}/retirement-outlook`, `/people/{id}/vacancy-risk` (HR); `GET/PUT /people/{id}/career-aspiration`; `GET/POST /talent-reviews` with assessments and placements; `GET /talent-reviews/{id}/bias-prompts`; `GET/POST /succession/plans` with successors, `submit` and `approve`; `GET /succession/plans/due?on=`; `GET/PUT /positions/{id}/continuity-sheet`; `GET/POST /talent-pools` with members; `GET/POST /career-paths`, `GET /career-paths/observed?since=`; `GET/POST /people/{id}/language-proficiency`; `GET/POST /workforce/segments`, `/workforce/history` (with upload), `/workforce/scenarios` with `copy` and `save`, drivers, ratios, supply rates and gap strategies with `release`; `GET /workforce/segments/{code}/suggested-rate`; `GET/POST /position-plans` with assumptions, `submit`, `approve` and `export?format=csv|xlsx|journal`.

**Events** (added to `api/events.yaml`; identifiers only, AGENTS rule 9): `critical_role.confirmed`, `succession_plan.submitted`, `succession_plan.approved`, `succession_plan.review_due`, `continuity_sheet.update_due`, `talent_review.closed`, `talent_pool.member_approved`, `workforce_scenario.saved`, `gap_strategy.released`, `position_plan.approved`.

---

## 14. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| SUCC-020 | New organization opens setup | Defaults pre-filled; talent reviews, the nine-box and workforce planning off; bias prompts on | smoke 1a–c | 1, 17 |
| SUCC-021 | Clerk scored on four criteria; scored 6 | `CRITICAL_SCORE_INVALID` | smoke 2a | 17 |
| SUCC-022 | Deputy clerk marked required by law with no legal basis | Refused | smoke 2b | 17 |
| SUCC-023 | Organization sets weights adding up to 120 | `CRITICAL_WEIGHTS_INVALID` | smoke 2c | 17 |
| SUCC-024 | Clerk scored 5, 4, 5, 3, 5 with equal weights; confirmed by the scorer; by HR | Score 4.40; `SELF_APPROVAL`; confirmed | smoke 2d–e | 17 |
| SUCC-025 | The clerk has no succession plan | HR reminded | smoke 2f | 17 |
| SUCC-026 | Analyst assesses her own flight risk; the manager assesses it medium with a note | `SELF_REVIEW`; recorded | smoke 2g | 17 |
| SUCC-027 | Retirement intention recorded that the employee did not share; eligibility without its source | Refused | smoke 2h | 17 |
| SUCC-028 | A work authorization ends | HR records the date; no age or immigration column exists | smoke 2i | 17 |
| SUCC-029 | Talent review while reviews are off; the nine-box while it is off | `FEATURE_OFF` | smoke 3a–b | 17 |
| SUCC-030 | Nine-box switched on | New reviews use it | smoke 3c | 17 |
| SUCC-031 | Analyst assesses her own potential; a criterion the organization does not use; two of four criteria | `SELF_REVIEW`; `POTENTIAL_CRITERION_UNKNOWN`; `INPUT_REQUIRED` | smoke 3d | 17 |
| SUCC-032 | Potential assessed for someone not open to succession, and for someone with no aspiration | The aspiration shown; "not stated" | smoke 3e | 17 |
| SUCC-033 | Dee moved from moderate-high to high-high without a reason; with one | `PLACEMENT_REASON_REQUIRED`; move kept | smoke 3f | 17 |
| SUCC-034 | Bias prompt with one part-time person; with 11 in each group | Suppressed; shown (63.6% and 18.2% at low potential) | smoke 3g, 3i | 17 |
| SUCC-035 | A participant and a non-participant open the review | Named on it; not named | smoke 3h | 17 |
| SUCC-036 | Clerk's plan submitted without its route; readiness "soon" | `INPUT_REQUIRED`; `LIST_VALUE_UNKNOWN` | smoke 4a–b | 17 |
| SUCC-037 | Ben (wants to be clerk, French A) and Dee (not open to succession, bilingual C) named | Ben: language gap fr B; Dee: mismatch | smoke 4c | 17 |
| SUCC-038 | Plan approved without HR; by its owner; by HR without an emergency successor | `ROUTE_APPROVALS_MISSING`; `SELF_APPROVAL`; `EMERGENCY_SUCCESSOR_REQUIRED` | smoke 4d–f | 17 |
| SUCC-039 | Plan approved with Ben as emergency successor | Successors approved; review in 12 months; HR no longer reminded | smoke 4g | 17 |
| SUCC-040 | 30 days before the review; 29 days before; the day after | Owner reminded; nothing; overdue | smoke 4h | 17 |
| SUCC-041 | Dee's readiness changes on the approved plan | Back through the route; the earlier approval does not count | smoke 4i | 17 |
| SUCC-042 | Plan for the unionized roads operator; direct-hire offer approved | Development only; `CAUTION_NOT_ACKNOWLEDGED` until acknowledged with a reason | smoke 4j–k | 14, 17 |
| SUCC-043 | Continuity sheet with an admin password; a PIN in the notes; where the vault is | `SECRET_NOT_ALLOWED`; accepted, update due in 12 months | smoke 5a–b | 17 |
| SUCC-044 | Incumbent, interim successor and another analyst open the sheet | Seen; seen; not seen | smoke 5c | 17 |
| SUCC-045 | Analyst applies to a nominations-only pool; someone applies for her | `POOL_CLOSED_TO_APPLICATIONS`; `INPUT_REQUIRED` | smoke 6a | 17 |
| SUCC-046 | Nomination approved without the pool owner; by the nominating manager; by the nominee; by the owner | `ROUTE_APPROVALS_MISSING`; `SELF_APPROVAL`; `SELF_APPROVAL`; approved | smoke 6b–c | 17 |
| SUCC-047 | An application declined without a reason | `INPUT_REQUIRED` | smoke 6d | 17 |
| SUCC-048 | Ben moved from analyst to deputy clerk | Proposed as a career step | smoke 7a | 17 |
| SUCC-049 | Scenario while workforce planning is off; a segment by "teams" | `FEATURE_OFF`; `SEGMENT_SCOPE_UNKNOWN` | smoke 7b–c | 17 |
| SUCC-050 | Department history uploaded without its file; the same year twice | Refused | smoke 7d | 17 |
| SUCC-051 | Analysts' history (3 people, 1 year) | Thin; the department's 5.00% suggested | smoke 7e | 17 |
| SUCC-052 | Analysts' own rate used; planner's rate without a reason; the next level up for the department | `HISTORY_TOO_THIN`; `SUPPLY_RATE_REASON_REQUIRED`; `INPUT_REQUIRED` | smoke 7f | 17 |
| SUCC-053 | 360 lane km at 12 per operator | 30 FTE | smoke 7g | 17 |
| SUCC-054 | A saved scenario changed or renamed; copied to version 2 | `SCENARIO_VERSION_LOCKED`; copy accepted | smoke 7h | 17 |
| SUCC-055 | Unionized reduction released without a draft; without labour relations; reviewed by the releaser; without the caution; with both | Refused; `LABOUR_RELATIONS_REVIEW_REQUIRED` twice; `CAUTION_NOT_ACKNOWLEDGED`; released | smoke 7i–j | 17 |
| SUCC-056 | Position plan without its kind or year; submitted without its route | Refused; `INPUT_REQUIRED` | smoke 8a–b | 4, 17 |
| SUCC-057 | The department leader approves her own plan; finance and HR approve; the executive approves | `SELF_APPROVAL`; `ROUTE_APPROVALS_MISSING`; approved | smoke 8c–d | 4, 17 |
| SUCC-058 | Planner's overtime assumption without a reason; an agreement increase without the agreement | Refused | smoke 8e | 17 |
| SUCC-059 | Another organization reads succession data | Nothing visible | smoke 9 | 1 |

---

## 15. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/09` | Points here at the top; open questions closed except Indigenous leadership development (Q51); flight risk prediction, retirement by age and work permit expiry for planners replaced as decided here |
| `stories/07-to-10-talent.md` | SUCC-001 to SUCC-004 follow this document; new stories SUCC-005 to SUCC-012; scenarios SUCC-020 to SUCC-059 in §14 |
| `docs/15` Step 17 | Read this document; build on migration 0016; pass SUCC-001 to SUCC-012 and SUCC-020 to SUCC-059 |
| `docs/16` | New Q51 (Indigenous leadership development with advisers); items to verify for this module |
| `docs/22` | Settings from 0016 are listed here, not in `docs/22` §2; FB-039 |
| `AGENTS.md` | Reading order item 17; rule 54; Step 1 migration 0016 and its smoke test; Step 17 |
| `.cursor/rules/00-cando.mdc` | Rule 54 in short |
| `tests/hardcoding/check_values.py` | Reads every decisions document from `docs/21` onward |

Where a listed document still says otherwise, this document wins.

---

## 16. Open questions and items to verify

| Item | Until decided |
| --- | --- |
| Indigenous leadership development features, designed with Indigenous advisers (Q51) | Pools can hold cohorts; community approval steps are added to routes |
| Positions the law requires, by province and sector | Ontario's clerk and treasurer (Municipal Act, 2001, ss. 228 and 286) from secondary sources; other provinces' statutory officers (for example BC's corporate officer and financial officer) and sector roles entered by each organization with their legal basis. Counsel review before Step 17 |
| Notice to the union or under employment standards for a reduction | Shown in the caution; the rules themselves are applied in Module 11 and the agreement library |
| Planning tool links (Adaptive Planning, Anaplan, Sage) | Generic files at launch (R7.4) |

---

## Sources

- Ontario Municipal Act, 2001, ss. 228 (clerk) and 286 (treasurer), as cited in the City of Guelph's statutory appointments by-law: https://guelph.ca/wp-content/uploads/Statutory-Appointments-Bylaw-2024-21004-Office-Consolidation-1.pdf
- Treasury Board of Canada Secretariat, Qualification Standards in Relation to Official Languages (levels A, B, C, X and the exemption): https://www.canada.ca/en/treasury-board-secretariat/services/staffing/qualification-standards/relation-official-languages.html
