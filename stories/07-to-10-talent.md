# Stories · 07 Performance, 08 Learning, 09 Succession & Workforce Planning, 10 Engagement & Recognition

Requirements: `requirements/07` to `requirements/10`. These modules build on Core HR records and the shared platform. They have no special calculation engines.

## 07 Performance

The owner's decisions are in `docs/28-performance-decisions.md`, which wins where a story differs; its scenarios PERF-020 to PERF-050 (`docs/28` §13) are acceptance tests for these stories.

**PERF-001 — Reviewer follows the reporting line on the review date.** AC: the reviewer of each position's section is the manager derived from the reporting line as of the review's due date. If the employee moves mid-cycle, the previous manager rates their own period when it reached `reviews.min_section_days` (90 days worked), and otherwise adds comments for the new manager (`docs/28` §6.3).

**PERF-002 — Goals cascade and are agreed by both.** AC: mission, organization, department, team and individual goals link upward. The employee or the manager proposes an individual goal, and it stands once both have agreed (`GOAL_NOT_AGREED`). Progress rolls up, and every amendment after agreement is kept with who, what, when and why (`docs/28` §4.1).

**PERF-003 — Calibration.** AC: calibration is part of each cycle unless the cycle turns it off, and no review is released before it (`CALIBRATION_REQUIRED`). The calibration view shows rating distributions by unit, job level and demographic group in aggregate (minimum group size 10). Changes made in calibration are logged with who and why (`docs/28` §5.2).

**PERF-004 — Probation reviews feed Core HR.** AC: a probation review outcome (pass, extend, fail) creates the corresponding change set draft (`employment.status_changed` or extension) for HR.

**PERF-005 — Unionized environments.** AC: for bargaining units where the agreement limits or forbids ratings, read from the agreement library, the review is development-only or the agreement's own form, with no rating and no merit link (`RATING_NOT_ALLOWED`). Representation and sunset periods come from the agreement (`docs/28` §8.4, §9).

**PERF-006 — Leave-adjusted expectations.** AC: goals and review timelines prorate for employees on protected leave; days on protected leave are not days worked, so under 90 days worked a position gets comments only; absence on protected leave never counts against the rating (`docs/28` §9.4).

**PERF-007 — PIP safeguards.** AC: a performance improvement plan is submitted only after unclear expectations, training gaps, workload and accommodation needs are ruled out; HR approves it through the organization's `pip` route, never its manager or the employee; it never starts during a protected leave; a possible protected ground needs the caution `performance.pip_protected_ground` with the accommodation review; the employee acknowledges it before it starts; it runs 60 days unless it sets its own end, and extensions need a reason (`docs/28` §8).

**PERF-008 — Suggested and chosen ratings, each position by itself.** As a manager, I see CanDo's suggested rating for each position's section from the cycle's weights, and I choose the rating, explaining any difference (`RATING_REASON_REQUIRED`). A person in two positions gets two ratings and no combined rating unless the organization chooses one (`docs/28` §3.2, §6.1).

**PERF-009 — The one-up look and HR on a concern.** As an organization, I want my managers' managers to look at each review before the employee sees it, through our `performance_review` route, and HR to look as well when a concern we listed is found (`HR_REVIEW_REQUIRED`). No reviewing manager or employee approves the one-up step (`SELF_APPROVAL`) (`docs/28` §5.3).

**PERF-010 — Seen, not agreed.** As an employee, I sign to say I have seen my review, add my comments and can ask HR to review it; HR decides with a reason. After release, only HR changes a rating, with a reason, and I am told (`docs/28` §5.4–§5.5).

**PERF-011 — 360° feedback that protects raters.** As an employee, I nominate raters, and my manager and others can too; each group has 3 to 5 raters, and a group's answers are shown only when at least 3 answered; my manager's input is never anonymous. Results are for my development unless the cycle lets them inform ratings (`FEEDBACK_DEVELOPMENT_ONLY`) (`docs/28` §7.2–§7.3).

**PERF-012 — Check-in nudges and sunset clauses.** AC: a manager is nudged after the organization's or the team's days without a check-in (30 pre-filled). An adverse record stops counting after the agreement's sunset period, or the organization's months for non-union staff (none unless set); managers no longer see it and HR keeps it (`docs/28` §7.4, §9.2).

## 08 Learning

The owner's decisions are in `docs/29-learning-development-decisions.md`, which wins where a story differs; its scenarios LRN-020 to LRN-050 (`docs/29` §14) are acceptance tests for these stories.

**LRN-001 — Mandatory training by job and jurisdiction.** AC: the training the law requires is loaded by CanDo by jurisdiction and sector; an organization's rule can be stricter but never looser (`TRAINING_RULE_LOOSER_THAN_LAW`). Required courses are assigned from job, location and role on hire, job change, promotion, transfer and return from a long leave (for example health and safety awareness, WHMIS, accessibility training). The employee is reminded 14 and 3 days before the due date, the manager told 1 day and HR 7 days after; completions update the record. Training the law requires is never waived (`docs/29` §3.3, §4).

**LRN-002 — Credentials with expiry.** AC: licences and certifications have expiry dates and are valid only once HR or its delegate verifies them. The employee is alerted at 90, 60 and 30 days, the manager and HR at 30 days and on the expiry date. Publishing a shift for someone without a valid credential the law requires is refused with no override (`CREDENTIAL_REQUIRED_BY_LAW`); any other required credential, or training required before the work, needs the caution `learning.not_ready_for_work` (`docs/29` §5, §6).

**LRN-003 — Training budgets and Quebec 1% rule (phase 2 reporting).** AC: training spend by department is tracked against its budget, and approval over budget needs the caution `learning.over_budget`. Eligible Quebec spending is recorded from launch; for Quebec entities above the payroll threshold, the phase 2 report shows eligible spending against the 1% obligation (`docs/29` §9).

**LRN-004 — Onboarding learning path.** AC: `employment.hired` assigns the onboarding path for the job and location, in the organization's main language.

**LRN-005 — Learning outside any LMS.** As HR, I record classroom and virtual attendance, on-the-job training signed off by a supervisor (never the learner: `SIGNOFF_REQUIRED`), policy acknowledgements and external courses with their certificate, while e-learning comes in from our LMS or the partner (`docs/29` §3.1).

**LRN-006 — Refreshers and changes in the law.** AC: a refresher done within 60 days before its due date keeps its cycle; earlier, the next one counts from the completion. A new or changed legal requirement is assigned on its effective date, due by the law's deadline or within 30 days (`docs/29` §4.5, §4.6).

**LRN-007 — Training time is paid.** AC: mandatory training taken outside scheduled hours records its minutes, which go to the timesheet as training time for the manager's approval and are always paid (`docs/29` §4.7).

**LRN-008 — Training requests and repayment.** As an employee, I request a course with its cost and time off; it goes to my manager, and to HR above the amount our organization set. HR marks it for CRA before it is paid. Where our repayment rules apply, I sign the agreement before reimbursement, and nothing is recovered without my written authorization (`docs/29` §8).

**LRN-009 — Skills and development plans.** AC: my skills profile is shown for internal opportunities only after I opt in, and I can withdraw. My development plan is agreed by my manager and me, and every change is kept; the 70-20-10 mix is shown as guidance (`docs/29` §7).

## 09 Succession & Workforce Planning

The owner's decisions are in `docs/30-succession-workforce-planning-decisions.md`, which wins where a story differs; its scenarios SUCC-020 to SUCC-059 (`docs/30` §14) are acceptance tests for these stories.

**SUCC-001 — Critical roles.** AC: leaders score positions 1 to 5 on the organization's weighted criteria (impact, difficulty to replace, single point of failure, scarcity, required by law; equal weights pre-filled, adding up to 100), and HR confirms the list, never the leader who scored it. A position the law requires states its legal basis and is always critical. Score history is kept (`docs/30` §4.1–§4.2).

**SUCC-002 — Succession plans.** AC: each critical position can have a plan with successors and readiness for that role from the organization's list (ready now, 1 to 2 years, 3 years or more at the start), an emergency successor and a review date. The owner proposes and the organization's `succession_plan` route approves; a change on an approved plan goes back through it. Plans appear on the org chart as an overlay only for the people named on them and HR (`docs/30` §6.1).

**SUCC-003 — Workforce plans use the same plan mechanism as the org chart.** AC: a workforce or position plan is a `platform.plan` of draft change sets (new positions, eliminations, moves) with its kind and fiscal year. It shows headcount and cost by fiscal year of the effective dates, and approval through the organization's route submits the change sets (`docs/30` §10.1).

**SUCC-004 — Headcount and budget planning.** AC: the plan compares approved complement, filled FTE and vacancies by unit for each fiscal year. Cost assumptions come from actuals (agreement grids and the compensation cycle, the organization's own overtime and vacancy history, burden from payroll and benefits), and a planner's change states why (`docs/30` §10.3).

**SUCC-005 — Parts switched on.** As an organization, I switch on talent reviews, the nine-box and workforce planning when I want them; until then they are refused (`FEATURE_OFF`), and key roles, backups and plans still work (`docs/30` §3.1).

**SUCC-006 — Who sees succession data.** AC: potential, placements, successor lists and continuity sheets are seen only by the people named on the review or plan, and HR; every view is logged; age is shown only in totals and a possible vacancy date reaches planners without its reason (`docs/30` §3.4, §4.4–§4.5).

**SUCC-007 — Flight risk and aspirations.** As a manager, I record an employee's flight risk as low, medium or high with a note; there is no model and the employee never rates their own. As an employee, I keep my own career aspiration, which is shown beside every assessment and nomination about me, and a mismatch is flagged (`docs/30` §4.3, §4.6, §6.2).

**SUCC-008 — Talent reviews and the nine-box.** AC: managers assess potential on the organization's criteria (each assessed, no one their own); the nine-box, once on, places people with box names the organization edits, and every move needs a reason and is kept. Bias prompts show only when each group compared has 10 or more people (`docs/30` §5).

**SUCC-009 — Unionized roles.** AC: a plan for a position under a collective agreement is development only; the position is filled through the agreement's posting and seniority rules, and a direct-hire offer for it needs the caution `succession.appoint_without_posting` with a reason (`docs/30` §6.3).

**SUCC-010 — Emergency coverage.** As an incumbent of a critical role, I keep a one-page continuity sheet that my interim successor, my manager and HR can see; CanDo refuses passwords, PINs and tokens (`SECRET_NOT_ALLOWED`), and I am reminded to update it yearly (`docs/30` §6.5).

**SUCC-011 — Talent pools and career paths.** AC: managers nominate and employees apply where a pool allows; the pool owner approves through the route, never the nominator or the nominee. Career steps are proposed from the job architecture and the moves people made, and HR confirms them (`docs/30` §6.6, §7).

**SUCC-012 — Workforce scenarios.** As a planner, I project supply from our own history (including history uploaded from our previous system), use the next level up or my own rate with a reason where history is thin, enter our own drivers and ratios, save versions that stay as they were, and draft gap strategies that people approve in their own modules; a reduction in a unionized group needs labour relations and the caution `workforce.reduction_unionized` (`docs/30` §9).

## 10 Engagement & Recognition

The owner's decisions are in `docs/31-engagement-recognition-decisions.md`, which wins where a story differs; its scenarios ENG-020 to ENG-055 (`docs/31` §13) are acceptance tests for these stories.

**ENG-001 — Surveys that protect people.** AC: answers are stored with no person link and only the date; a confidential survey keeps group attributes and an anonymous one only the unit. Results are suppressed for groups under the minimum (default 5, never below 3) and for self-identified groups under 10; an attempt to filter down to a smaller group shows nothing. An employer covered by a freedom-of-information law runs anonymous surveys only (`docs/31` §3.2–§3.4).

**ENG-002 — Service milestones and CRA.** AC: service anniversaries come from `continuous_service_date` every 5 years (the organization's years), and the manager is reminded 30 days before. Each gift and award is recorded as cash, near-cash, gift card or non-cash; CanDo works out the taxable part under CRA's $500 limits (general and long-service) and sends it to payroll, which confirms it (`docs/31` §6.1, §6.3).

**ENG-003 — Peer recognition.** AC: recognition is tied to the organization's values and starts private (the recipient and their manager); only the recipient can ask to make it public, and HR approves through the organization's route. It never shows on performance records unless the employee attaches it to their own review (`docs/31` §5).

**ENG-004 — Action plans.** AC: each manager with results gets a plan due 60 days after the survey closes, agrees 2 or 3 actions with the team and is reminded when late; progress is visible to the team as "you said, we did" (`docs/31` §4.3).

**ENG-005 — Results for managers, comments for HR.** As a manager, I see my team's results from 5 answers and a roll-up of everyone under me; I see comment themes, never the comments, which HR reads (`docs/31` §4.1–§4.2).

**ENG-006 — Flagged comments.** AC: a survey with open questions opens only once the organization names its HR contact; a comment suggesting harassment, a safety risk or self-harm is sent to that contact without identity, and handling it records what was done. Every survey shows the speak-up channel and crisis lines (`docs/31` §3.8).

**ENG-007 — Uploads, imports and unions.** As HR, I upload a partner's questionnaire to run in CanDo, or import results from our previous tool, with groups under the minimum refused. A survey of a group whose agreement requires union consultation opens only after the caution (`docs/31` §3.1, §3.7).

**ENG-008 — Lifecycle surveys.** AC: onboarding at 30 and 90 days, exit, promotion and return-from-leave surveys are sent automatically; results are grouped over time until a group reaches the minimum, and a return-from-leave survey never names the leave (`docs/31` §3.6).

**ENG-009 — Points and cash awards.** AC: points come only from the giver's budget; a cash award goes through the organization's route (the proposer's manager, then HR) and never past the proposer or the recipient, and is paid through payroll (`docs/31` §5.3, §6.2).

**ENG-010 — Announcements and urgent alerts.** As HR, I target announcements and require read receipts on important notices, with reminders on days 3 and 7; urgent alerts go by push, email and SMS, and SMS is used for nothing else (`docs/31` §7.1–§7.2).

**ENG-011 — Ideas and the anonymous box.** As an employee, I submit ideas and vote once; I can write to HR anonymously and read replies with my own secret, and CanDo never records who I am (`docs/31` §7.3).

**ENG-012 — Wellbeing, observances and the directory.** AC: the wellbeing hub links the EAP, crisis lines and supports with no health data collected; the observances calendar starts from CanDo's list and the organization adds its own, never as paid holidays; the directory shows extras only if the employee adds them (`docs/31` §8).
