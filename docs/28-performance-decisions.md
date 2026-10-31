# 28 · Performance decisions

Oct 28, 2026 · @Wael

This document records the owner's review of Module 07 (Performance Management) and turns each decision into something the build can follow: a setting with its default, a database check, a rule the organization sets, a route it edits, a caution, or a screen behaviour. The review went round by round; the working record is `claude/review/07-performance-decisions.md` in the project.

It covers rating scales, the suggested and chosen rating, AI writing help, starter templates for Indigenous and non-profit organizations, goals and their alignment, new hires, mid-year reviews, weights, calibration, the one-up look and HR on a concern, sign-off, changes after a rating is final, people in several positions, 360° feedback, check-ins, performance improvement plans, union limits on ratings, sunset clauses, chief executive evaluation and protected leave.

**Precedence.** On these topics this document wins over `requirements/07`, `stories/07-to-10-talent.md` (the PERF stories) and `docs/20` §5 where it changes them. `docs/22` still wins on values, defaults, languages and fallbacks, and `docs/23` §2 still governs how routes and cautions work. §14 lists every place that changes. The schema is `schema/0014_performance_decisions.sql` (migration 0014, Step 1), checked by `tests/schema/schema_0014_smoke.sql`.

**The owner's rules for this module.**

1. Every decision is a default each organization can change at setup or later; only legal floors and safety rules are fixed. CanDo pre-fills its suggested numbers at setup, and the organization keeps or changes them (Q46).
2. People rate people. CanDo suggests a rating from the weights; the manager chooses it and explains any difference. AI never rates, ranks or recommends an ending (AGENTS rule 14).
3. Each position stands by itself. A person in two positions gets a rating per position and no combined rating, unless the organization chooses one.
4. The employee always sees and can answer what is written about them; changes are reasoned and kept.
5. Protected leave and protected grounds come first: absence never lowers a rating, no improvement plan starts during a protected leave, and a possible protected ground needs an accommodation review before a plan.

---

## 1. Decisions at a glance

| # | Decision | Setting or rule | Section |
| --- | --- | --- | --- |
| R1.1 | A new organization starts with a 5-point scale; it can use 3 or 4 points, its own wording, and separate scales for goals, competencies and values | `performance.rating_scale_starter`; `talent.rating_scale` | §3.1 |
| R1.2 | CanDo suggests the rating from the goal and competency weights; the manager chooses it and explains any difference | `suggested_rating`, `rating_reason` (`RATING_REASON_REQUIRED`) | §3.2 |
| R1.3 | AI writing help comes later with the platform assistant, off until the organization switches it on; never rates, ranks or recommends an ending | `performance.ai_writing_help`: off | §3.3 |
| R1.4 | CanDo develops starter review templates for Indigenous and non-profit organizations with advisers | Q49 | §3.4 |
| R2.1 | Goals are a living, shared document: proposed by either side, agreed by both, aligned up to the mission, with development and training goals; every amendment kept; strengths and areas to develop beside the manager's view; input from anyone | `talent.goal`, `talent.goal_change`, `talent.strengths_view` | §4.1 |
| R2.2 | People hired in the last 3 months of the cycle get goals and no rating | `performance.new_hire_no_rating_months`: 3 | §4.2 |
| R2.3 | The mid-year review records progress and comments, never a rating | Review type category `mid_year` | §4.3 |
| R2.4 | Goals and competencies count 50/50 in the suggested rating, changed per cycle | `performance.weights_starter` | §4.4 |
| R3.1 | Calibration is part of each cycle, pre-filled on; ratings are final only after it; changes need a reason | `performance.calibration`: on (`CALIBRATION_REQUIRED`) | §5.2 |
| R3.2 | The manager's own manager looks at a review before release, through the organization's route; HR also looks when there is a concern the organization has listed | Route `performance_review`; `performance.hr_review_concerns` (`HR_REVIEW_REQUIRED`) | §5.3 |
| R3.3 | Signing means "I have seen it"; the employee can comment and ask HR, who decides with a reason whether to reopen | `acknowledged_at`, `employee_comment`, `hr_review_outcome` | §5.4 |
| R3.4 | After release only HR changes a rating, with a reason; the employee is told; the history is kept | `talent.rating_history` (`RATING_CHANGE_REASON_REQUIRED`) | §5.5 |
| R4.1 | Each position stands by itself: a rating per position, no combined rating (closes Q35) | `reviews.overall_method`: none | §6.1 |
| R4.2 | A position held at least 90 days in the cycle is rated; a shorter period gets comments only | `reviews.min_section_days`: 90 (`SECTION_TOO_SHORT_TO_RATE`) | §6.2 |
| R4.3 | When someone moves during the cycle, the previous manager rates their period if it reached the minimum, otherwise adds comments | `talent.review_section.section_period` | §6.3 |
| R4.4 | Each position's manager sees their own section (and an overall where one exists); other sections only through HR | Access rule | §6.4 |
| R5.1 | Each position's rating is used on its own, for that position's increase; succession and the nine-box show them side by side | `docs/25` §6.2 | §6.1 |
| R5.2 | 360° raters nominated by the employee, the manager or others; 3 to 5 per group; a group shown only when at least 3 answered; the manager never anonymous | `performance.rater_group_min`: 3, `performance.rater_group_max`: 5 | §7.2 |
| R5.3 | 360° results are for development only; a cycle can let them inform ratings | `performance.feedback_360_use` (`FEEDBACK_DEVELOPMENT_ONLY`) | §7.3 |
| R5.4 | Managers are nudged after a month with no check-in, editable per organization or team | `performance.checkin_nudge_days`: 30; `talent.checkin_rule` | §7.4 |
| R6.1 | An improvement plan starts only after the manager rules out unclear expectations, training gaps, workload and accommodation needs, and HR approves through the route; the employee acknowledges it | Route `pip` (`PIP_CAUSES_NOT_REVIEWED`) | §8.1 |
| R6.2 | A plan runs 60 days unless it sets its own length; extensions need a reason | `performance.pip_default_days`: 60 | §8.2 |
| R6.3 | No plan during a protected leave; a possible protected ground needs a caution, an accommodation review and HR's approval | `PIP_DURING_PROTECTED_LEAVE`; caution `performance.pip_protected_ground` | §8.3 |
| R6.4 | Union representation as the agreement says; non-union staff may bring a support person; recorded per meeting | `talent.pip_meeting.representation` | §8.4 |
| R7.1 | Where an agreement limits or forbids ratings, CanDo reads it from the agreement library and gives those units development-only reviews or the agreement's own form | `talent.review.rating_mode` (`RATING_NOT_ALLOWED`) | §9.1 |
| R7.2 | After the agreement's sunset period an adverse record is hidden from managers and unusable in decisions, but kept for HR; non-union staff have no sunset unless the organization sets one | `performance.non_union_sunset`; `talent.adverse_record` | §9.2 |
| R7.3 | Board or council evaluation of the chief executive or chief administrative officer comes in a later phase | Later phase | §9.3 |
| R7.4 | Protected leave: rated on time worked, goals prorated; under 90 days worked, no rating; absence never lowers a rating | `days_worked` | §9.4 |

---

## 2. How the module is set up

### 2.1 Settings

| Setting | Decides | CanDo default | Set per |
| --- | --- | --- | --- |
| `performance.rating_scale_starter` | The scale a new organization starts from, in English and French | 5 points: not meeting, partly meeting, fully meeting, exceeding expectations, exceptional | Organization |
| `performance.ai_writing_help` | AI wording help, bias-language flags and feedback summaries in reviews | Off | Organization |
| `performance.new_hire_no_rating_months` | Hired within this many months of the cycle's end: goals, no rating | 3 | Organization, employer |
| `performance.weights_starter` | Goal and competency weights in the suggested rating for new cycles | 50/50 | Organization, employer |
| `performance.calibration` | New cycles include calibration | On | Organization, employer |
| `performance.hr_review_concerns` | Which concerns send a review to HR before release (§5.3) | The lowest rating, a rating different from the suggestion, protected leave in the cycle, flagged by the one-up reviewer | Organization, employer |
| `performance.rater_group_min` | Answers needed before a 360° group is shown | 3 (never below 3) | Organization, employer |
| `performance.rater_group_max` | Most raters in a 360° group | 5 | Organization, employer |
| `performance.feedback_360_use` | How a new cycle uses 360° results | Development only | Organization, employer |
| `performance.checkin_nudge_days` | Days without a check-in before the manager is nudged | 30 | Organization, employer; a team through `talent.checkin_rule` |
| `performance.pip_default_days` | Length of an improvement plan that sets none | 60 | Organization, employer |
| `performance.non_union_sunset` | Months after which a non-union adverse record stops counting | None | Organization, employer |
| `reviews.overall_method` (now decided) | Whether sections are combined into one rating | None: each position by itself (`docs/20` §5.3 changed) | Organization |
| `reviews.min_section_days` (now decided) | Days worked in a position before its section is rated | 90 | Organization |

Pre-filled values follow the Q46 rule: the setup screen shows CanDo's suggestion and the organization keeps or changes it. The rating scale, weights, calibration, 360° use and new-hire rule are copied into each cycle when it is created, so a cycle can differ from the organization's default.

### 2.2 Set up by each organization

| What | Where | Until it is set |
| --- | --- | --- |
| Rating scales (points, wording, separate scales for goals, competencies and values) | `talent.rating_scale` | The setup wizard offers the starter scale |
| Review cycles: period, who they cover, scale, weights, calibration, 360° use, mid-year | `talent.review_cycle` (§4) | A review cannot be released (`INPUT_REQUIRED`) |
| Organization, department and team goals; goal libraries by job | `talent.goal` (§4.1) | Individual goals stand alone |
| Concerns that need HR before release | `performance.hr_review_concerns` (§5.3) | The four starter concerns |
| Team check-in rhythms | `talent.checkin_rule` (§7.4) | The organization's days |
| Agreements that limit ratings, their own forms, representation and sunset periods | The agreement library (`docs/21` §8.3, Step 7) | Ratings allowed; representation and sunset as for non-union staff |

### 2.3 Routes

Two starter routes are copied to every organization, and each organization edits them like any other route (`docs/23` §2.2):

| Route | Subject | Starter step | Section |
| --- | --- | --- | --- |
| `performance_review` | `performance_review` | The reviewing manager's own manager (one-up) | §5.3 |
| `pip` | `pip` | HR | §8.1 |

No one approves a review they wrote or a review of themselves, and no one approves a plan they created or a plan about themselves (`SELF_APPROVAL`). An organization can add conditions or steps (for example a second HR step for a plan in a unionized unit).

### 2.4 Caution

| Caution | When | Section |
| --- | --- | --- |
| `performance.pip_protected_ground` | An improvement plan where a protected ground (a disability, family status) may be involved | §8.3 |

It always needs a written reason, which records the accommodation review.

---

## 3. Scales, ratings and AI

### 3.1 Rating scales (R1.1)

A new organization starts from the 5-point scale in `performance.rating_scale_starter`, with English and French wording. It can change the wording, use 3 or 4 points, and keep separate scales for goals, competencies and values (`talent.rating_scale`). Each cycle names its scale.

### 3.2 The suggested rating and the manager's choice (R1.2)

For each rated section, CanDo computes the goal score and the competency score and suggests a rating from the cycle's weights, rounded to the scale (`goal_score`, `competency_score`, `suggested_rating`). The manager chooses the rating. A rating different from the suggestion needs a reason (`rating_reason`, `RATING_REASON_REQUIRED`), which calibration, the one-up reviewer and HR see. With each position standing by itself (§6.1), "the overall rating" of the decision is the rating of each position's section.

### 3.3 AI writing help (R1.3)

AI writing help is built with the platform assistant (Step 19) and stays off until the organization switches on `performance.ai_writing_help`. Then it offers clearer, behaviour-based wording, flags potentially biased language and summarizes feedback. Every suggestion is marked as AI and editable, and the employee can see when AI assisted. It never writes a rating, ranks people or recommends an ending.

### 3.4 Indigenous and non-profit templates (R1.4)

CanDo develops starter review templates for Indigenous and non-profit organizations with advisers: team-based and strengths-based reviews, values from the organization's own culture and teachings, and Elder or community input where the organization chooses. Each organization edits them. Who advises and when they are ready is Q49; until then these organizations adapt the standard templates.

---

## 4. Goals and cycles

### 4.1 Goals (R2.1)

Goals are a living, shared document (`talent.goal`):

- **Levels.** Mission, organization, department, team and individual goals, each individual goal aligned to a goal above it (`parent_goal_id`).
- **Kinds.** Objectives, development goals, training goals and job-standard goals. A training goal points to the learning the role needs (`learning_ref`, Module 08): IT training for IT staff, not for finance staff.
- **Proposed by either side, agreed by both.** The employee or the manager proposes; they discuss; an individual goal is agreed only when both have agreed (`GOAL_NOT_AGREED`).
- **Every amendment kept.** Once agreed, any change names who made it, and CanDo keeps what changed, when and why (`talent.goal_change`; `INPUT_REQUIRED` without the author).
- **Strengths beside the manager's view.** The employee records their strengths and areas to develop, and the manager does too, side by side (`talent.strengths_view`).
- **Input from anyone.** Either can ask others for input at any time (`talent.feedback_request` of kind `ad_hoc`, §7.1).

Goals belong to a position: a person in two positions has goals for each.

### 4.2 New hires (R2.2)

A person whose employment started within `performance.new_hire_no_rating_months` (3) of the cycle's end gets goals and no rating in that cycle's annual review (`RATING_NOT_ALLOWED`). It is the same three months as the pay cycle rule.

### 4.3 Mid-year review (R2.3)

A review whose type falls in the `mid_year` category records progress against each goal (on track, at risk, off track), comments from both, and goal changes with reasons. It never carries a rating (`RATING_NOT_ALLOWED`).

### 4.4 Weights (R2.4)

Goals and competencies count 50/50 in the suggested rating by default (`performance.weights_starter`). Each cycle sets its own weights, which add up to 100 (`PERFORMANCE_WEIGHTS_INVALID`), and a cycle can cover a group of employees through its scope (`applies_to`: pay groups, employment types, agreements, employers, units).

---

## 5. Reviews, calibration, release and sign-off

### 5.1 The stages

A review moves through `not_started`, `self`, `manager`, `calibration`, `one_up`, `released`, `signed` and `closed`. Each review states how it is rated (`rating_mode`): `rated`, `not_rated` (new hire), `development_only` or `agreement_form`, with where that came from (`rating_mode_source`, for example `agreement:UA#2:12.3`). The API sets it from the agreement library, the cycle, the review type and the hire date.

### 5.2 Calibration (R3.1)

Each cycle includes calibration unless it turns it off (`performance.calibration`, copied into the cycle). Leaders and HR compare ratings across teams; a review is released only after calibration (`CALIBRATION_REQUIRED`). A rating changed in calibration names who changed it and why, and the change is kept (`talent.rating_history`, stage `calibration`).

### 5.3 The one-up look and HR on a concern (R3.2)

Before the employee sees a review, the reviewing manager's own manager looks at it through the organization's `performance_review` route (`ROUTE_APPROVALS_MISSING` until the route is complete). The concerns found are recorded on the review (`concerns`):

| Concern | Found when |
| --- | --- |
| `lowest_rating` | A section has the scale's lowest rating |
| `differs_from_suggestion` | A rating differs from CanDo's suggestion |
| `protected_leave` | The employee had a protected leave in the cycle |
| `flagged_by_reviewer` | The one-up reviewer flags it |

A concern the organization lists in `performance.hr_review_concerns` sends the review to HR as well: it is released only after someone other than the reviewing manager records HR's look (`HR_REVIEW_REQUIRED`). The organization can drop any concern from the list.

### 5.4 Sign-off and asking HR (R3.3)

Signing records that the employee has seen the review (`acknowledged_at`), not that they agree; a released review is signed only with it. The employee can add comments (`employee_comment`) and ask HR to review it (`hr_review_requested_at`). HR decides whether to reopen it or uphold it, always with a reason (`hr_review_outcome`, `hr_review_reason`, `hr_review_decided_by`).

### 5.5 Changes after release (R3.4)

After release, a rating is changed only by HR (checked by the API's capability check), with a written reason; the database refuses a change that does not name who made it and why (`RATING_CHANGE_REASON_REQUIRED`) and keeps it (`talent.rating_history`, stage `after_final`). The employee is told. A pay decision already made on the old rating is reviewed separately in the compensation module; nothing changes pay automatically.

---

## 6. People in several positions

### 6.1 Each position by itself (R4.1, R5.1)

A person with two or more positions gets a rating for each position's section and no combined rating: `reviews.overall_method` defaults to `none`, and `talent.review_overall()` returns nothing. An organization can still choose the FTE × days method or the primary manager (`docs/20` §5.3). Each position's rating is used for that position's pay increase (`docs/25` §6.2); succession and the nine-box show each position's rating side by side. This closes Q35.

### 6.2 Minimum days (R4.2)

A section is rated only when the person worked at least `reviews.min_section_days` (90) days in the position during the cycle (`days_worked`; `SECTION_TOO_SHORT_TO_RATE`). A shorter period gets comments only. Protected leave does not count as days worked (§9.4).

### 6.3 Moves during the cycle (R4.3)

When the manager or position changes during the cycle, the previous manager rates their own period if it reached the minimum days, and otherwise adds comments for the new manager. One position can have a section per period (`section_period`), never two for the same days.

### 6.4 Who sees what (R4.4)

Each position's manager sees their own section, and the overall rating where the organization uses one. Other sections are seen only through HR. Private check-in notes are seen by their author and HR; improvement plans and calibration notes by the manager chain and HR.

---

## 7. Feedback, 360° reviews and check-ins

### 7.1 Feedback at any time

Anyone can ask for feedback at any time (`talent.feedback_request`, kind `ad_hoc`), and 360° surveys run as requests of kind `360`.

### 7.2 Raters (R5.2)

The employee, the manager or others (HR, a project lead) nominate raters (`nominated_by`). Each group (peers, direct reports, others) has at most `performance.rater_group_max` (5) raters (`FEEDBACK_RATERS_OVER_MAX`), and its answers are shown only when at least `performance.rater_group_min` (3) have answered (`talent.feedback_group_visible()`), so nobody can be identified. The manager's input is never anonymous. No one rates themself (`SELF_REVIEW`).

### 7.3 Development only (R5.3)

360° results go to the employee and the manager for development and are not used in ratings or pay (`performance.feedback_360_use`). A cycle can let them inform ratings; a request for rating purposes in a cycle that does not is refused (`FEEDBACK_DEVELOPMENT_ONLY`), and one outside any cycle needs one (`INPUT_REQUIRED`).

### 7.4 Check-ins (R5.4)

Check-ins keep shared and private notes and actions (`talent.checkin`). The manager is nudged when a position has had no check-in for `performance.checkin_nudge_days` (30); a team can have its own rhythm (`talent.checkin_rule`). `talent.checkin_due()` answers for a position and a date.

---

## 8. Performance improvement plans

### 8.1 Starting a plan (R6.1)

A plan is submitted only after the manager records that unclear expectations, training gaps, workload and accommodation needs were ruled out (`causes_ruled_out`; `PIP_CAUSES_NOT_REVIEWED`). HR approves it through the organization's `pip` route (`ROUTE_APPROVALS_MISSING`); the manager who created it and the employee cannot approve it. It starts only after the employee acknowledges it (`INPUT_REQUIRED`). Each plan states its gaps, standards, measures and support.

### 8.2 Length and extensions (R6.2)

A plan runs `performance.pip_default_days` (60) unless it sets its own end. An extension needs a reason and a later end date. The outcome (successful, extended, change of role, ending, closed) is recorded with a reason; an ending goes to Module 11 with HR's open-case review (`docs/23` §7.5).

### 8.3 Protected leave and protected grounds (R6.3)

No plan is approved or started while the employee is on a protected leave: a statutory leave, a leave whose reason is restricted, or one with a protected reason (`PIP_DURING_PROTECTED_LEAVE`). Where a protected ground such as a disability or family status may be involved (`protected_ground_possible`), the caution `performance.pip_protected_ground` must be acknowledged with a reason that records the accommodation review, and HR approves through the route (`CAUTION_NOT_ACKNOWLEDGED`).

### 8.4 Representation (R6.4)

For unionized staff, the representative is notified or present as the agreement says; non-union staff may bring a support person. Each meeting records it (`talent.pip_meeting.representation`: union representative, support person, offered and declined, not required).

---

## 9. Unions, records and special populations

### 9.1 Agreements that limit ratings (R7.1)

Where a collective agreement limits or forbids ratings, the API reads it from the agreement library and creates the unit's reviews as `development_only` (goals and feedback, no rating, no merit link) or `agreement_form` (the agreement's own form), with the clause as the source. A rating on such a review is refused (`RATING_NOT_ALLOWED`). The agreement field is added to the agreement schema in Step 7.

### 9.2 Sunset clauses (R7.2)

An adverse record (a poor review, a plan) is recorded in `talent.adverse_record` with its basis. For unionized staff its sunset date comes from the agreement; for non-union staff from `performance.non_union_sunset`, which is none unless the organization sets a number of months. From the sunset date, `talent.adverse_record_in_force()` is false: managers no longer see it and decisions cannot use it, but HR keeps it as retention law requires.

### 9.3 Chief executive evaluation (R7.3)

Board or council evaluation of the chief executive or chief administrative officer, with confidential board workflows, comes in a later phase.

### 9.4 Protected leave in the cycle (R7.4)

Someone on a protected leave for part of the cycle is reviewed on the time worked, with goals prorated. Days on protected leave are not days worked, so a position with fewer than 90 days worked gets comments only. Absence never lowers a rating, and protected leave in the cycle is a concern that sends the review to HR when the organization lists it (§5.3).

---

## 10. Fallback decided in this module

| # | When | Then | Status |
| --- | --- | --- | --- |
| FB-038 | Migration 0014 meets reviews written before it | They are marked rated and keep their ratings and overall method; the 90-day rule and the reasons apply when a rating is next changed | Decided (owner, 28 Oct 2026) |

---

## 11. Data model (migration 0014)

| Object | What it holds |
| --- | --- |
| Settings in §2.1 | 12 new settings and 2 decided, all with CanDo defaults |
| `talent.rating_scale` | §3.1 |
| `talent.review_cycle` (weights, calibration, 360° use and new-hire months filled from the settings); trigger `talent.check_review_cycle()` | §4 |
| `talent.goal`, `talent.goal_change`, trigger `talent.check_goal()`; `talent.strengths_view` | §4.1 |
| `talent.review`: stages `one_up` and `released`; `rating_mode`, `rating_mode_source`, `calibrated_at`, `concerns`, `hr_reviewed_by` and `_at`, `release_route_id`, `released_at`, `acknowledged_at`, `employee_comment`, HR review fields; trigger `talent.check_review_release()` | §5 |
| `talent.review_section`: `goal_score`, `competency_score`, `suggested_rating`, `rating_reason`, `days_worked`, `section_period`, `changed_by`, `change_reason`; one section per position and period; trigger `talent.check_section_rating()`; `talent.rating_blocked()` | §3.2, §6 |
| `talent.rating_history` | §5.2, §5.5 |
| `talent.feedback_request`, `talent.feedback_rater`, `talent.feedback_group_visible()` | §7 |
| `talent.checkin`, `talent.checkin_rule`, `talent.checkin_due()` | §7.4 |
| `talent.pip`, `talent.pip_meeting`, trigger `talent.check_pip()` | §8 |
| `talent.adverse_record`, `talent.adverse_record_in_force()` | §9.2 |
| Route subjects `performance_review` and `pip` with starter routes; `check_approval_task()` also refuses the subject employee; caution `performance.pip_protected_ground` | §2 |

Every new tenant table has `tenant_id` with forced row-level security; text fields are registered as translatable (`docs/22` §4.3). The starter routes are copied to existing organizations, skipping one that keeps a third language as required for its data (FB-035).

**Upgrading.** Reviews from before 0014 are marked rated (FB-038). Sections keep their ratings; the new checks apply from the next change of a rating. `reviews.overall_method` and `reviews.min_section_days` change only for reviews created after 0014; an organization that wants the FTE × days method sets it before its next cycle.

---

## 12. Validation, API and events

**Errors added by 0014:** `PERFORMANCE_WEIGHTS_INVALID`, `GOAL_NOT_AGREED`, `RATING_NOT_ALLOWED`, `SECTION_TOO_SHORT_TO_RATE`, `RATING_REASON_REQUIRED`, `RATING_CHANGE_REASON_REQUIRED`, `CALIBRATION_REQUIRED`, `FEEDBACK_DEVELOPMENT_ONLY`, `FEEDBACK_RATERS_OVER_MAX`, `PIP_CAUSES_NOT_REVIEWED`, `PIP_DURING_PROTECTED_LEAVE`. Existing ones used: `INPUT_REQUIRED`, `HR_REVIEW_REQUIRED`, `ROUTE_APPROVALS_MISSING`, `SELF_APPROVAL`, `SELF_REVIEW`, `CAUTION_NOT_ACKNOWLEDGED`, `SETTING_BELOW_MINIMUM`, `PAYROLL_SCOPE_UNKNOWN`.

**Checks in the application (Step 17 unless noted), not the database:** goal and competency scores and the suggested rating from the cycle's weights; finding the concerns; the rating mode from the agreement library, the review type and the hire date; days worked net of protected leave; prorating goals for protected leave; only HR changes a released rating; telling the employee of a change; section visibility by manager; nudges; reading representation and sunset periods from the agreement (Step 7 adds the fields); AI writing help (Step 19).

**API** (added to `api/openapi.yaml` in Step 17): `GET/POST /performance/rating-scales`; `GET/POST /performance/cycles`; `GET/POST /goals` with `agree` and `GET /goals/{id}/changes`; `GET/POST /performance/strengths`; `GET/POST /reviews/{id}/sections` with `rate`; `POST /reviews/{id}/calibrate`, `release`, `acknowledge`, `request-hr-review`, `hr-review-decision`; `GET /reviews/{id}/rating-history`; `GET/POST /feedback-requests` with raters, `submit` and `GET /feedback-requests/{id}/results` (groups shown only from the minimum); `GET/POST /checkins`, `GET/POST /teams/{orgUnit}/checkin-rule`; `GET/POST /pips` with `submit`, `approve`, `acknowledge`, `extend`, `close` and `/pips/{id}/meetings`; `GET /adverse-records` (HR).

**Events** (added to `api/events.yaml`; identifiers only, AGENTS rule 9): `goal.agreed`, `goal.amended`, `review.calibrated`, `review.released`, `review.acknowledged`, `review.hr_review_requested`, `review.hr_review_decided`, `rating.changed_after_release`, `feedback.requested`, `checkin.due`, `pip.approved`, `pip.started`, `pip.extended`, `pip.closed`, `adverse_record.sunset`.

---

## 13. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| PERF-020 | New organization opens setup | 5-point scale, 50/50, calibration on, 360 development only, 90 days, no combined rating pre-filled | smoke 1a–b | 1, 17 |
| PERF-021 | Organization sets a 360° minimum of 2 | `SETTING_BELOW_MINIMUM` | smoke 1d | 1 |
| PERF-022 | New cycle with no weights given; with 60/50 | Copied from the settings; `PERFORMANCE_WEIGHTS_INVALID` | smoke 2a–b | 17 |
| PERF-023 | Department goal with no department; individual goal agreed by the employee alone | Refused; `GOAL_NOT_AGREED` | smoke 3a–b | 17 |
| PERF-024 | Manager changes an agreed target without naming themself; then with a reason | `INPUT_REQUIRED`; change kept with before and after | smoke 3c–d | 17 |
| PERF-025 | Employee and manager record strengths and areas to develop | Both kept side by side | smoke 3 | 17 |
| PERF-026 | Review created without a rating mode | Refused | smoke 4a | 17 |
| PERF-027 | Ana moved from Cy to Ben in May: Cy rates January to April, Ben May to December; a third section overlapping April | Both rated; overlap refused | smoke 4b | 17 |
| PERF-028 | Ben rates 2 where CanDo suggests 3 without a reason | `RATING_REASON_REQUIRED` | smoke 4c | 17 |
| PERF-029 | Second position held 60 days | `SECTION_TOO_SHORT_TO_RATE`; comments only | smoke 4d | 17 |
| PERF-030 | Two rated positions, default method | No combined rating | smoke 4e | 17 |
| PERF-031 | Mid-year review rated; development-only unit rated; new hire from November rated | `RATING_NOT_ALLOWED` each time | smoke 4f–i | 17 |
| PERF-032 | Calibration lowers a rating with no reason; with one | `RATING_CHANGE_REASON_REQUIRED`; kept in the history | smoke 5a–b | 17 |
| PERF-033 | Release before calibration; without the one-up look | `CALIBRATION_REQUIRED`; `ROUTE_APPROVALS_MISSING` | smoke 5c–d | 17 |
| PERF-034 | The reviewing manager or the employee approves the one-up step | `SELF_APPROVAL` | smoke 5e | 17 |
| PERF-035 | Rating differs from the suggestion; HR has not looked | `HR_REVIEW_REQUIRED`; released after HR | smoke 5f–g | 17 |
| PERF-036 | Organization drops protected leave from its HR concerns | Released after the one-up look alone | smoke 5 (review 5) | 17 |
| PERF-037 | Review signed without the employee seeing it; employee comments and asks HR; HR decides without a reason | Refused; kept; refused | smoke 5h–i | 17 |
| PERF-038 | HR changes a released rating with no new reason; with one | `RATING_CHANGE_REASON_REQUIRED`; history kept; employee told | smoke 5j–k; API test | 17 |
| PERF-039 | 360° for ratings in a development-only cycle | `FEEDBACK_DEVELOPMENT_ONLY` | smoke 6a | 17 |
| PERF-040 | Employee nominates herself; a sixth peer | `SELF_REVIEW`; `FEEDBACK_RATERS_OVER_MAX` | smoke 6b–c | 17 |
| PERF-041 | Two of five peers answered; three answered; manager group | Hidden; shown; manager always shown | smoke 6d–e | 17 |
| PERF-042 | No check-in; one 10 days ago; the team checks in weekly | Nudge; none; nudge | smoke 6f–h | 17 |
| PERF-043 | Plan submitted before workload was ruled out | `PIP_CAUSES_NOT_REVIEWED` | smoke 7a | 17 |
| PERF-044 | Plan with no end date | Ends 60 days after it starts | smoke 7b | 17 |
| PERF-045 | Plan approved without HR; by its manager; by the employee | `ROUTE_APPROVALS_MISSING`; `SELF_APPROVAL` | smoke 7c–d | 17 |
| PERF-046 | Plan started before the employee acknowledges it; extended without a reason or a later end | `INPUT_REQUIRED`; refused | smoke 7e–f | 17 |
| PERF-047 | Plan starting during parental leave | `PIP_DURING_PROTECTED_LEAVE` | smoke 7g | 17 |
| PERF-048 | Plan where a disability may be involved | `CAUTION_NOT_ACKNOWLEDGED` until the accommodation review is recorded | smoke 7h | 17 |
| PERF-049 | Non-union adverse record; then the organization sets 24 months; agreement record with no sunset | Never sunsets; stops counting after 24 months; refused | smoke 8a–c | 17 |
| PERF-050 | Another organization reads performance data | Nothing visible | smoke 9 | 1 |

---

## 14. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/07` | Points here at the top; open questions closed; ratings per position, minimum days, calibration and release, sign-off, 360°, PIP and union sections marked where they changed |
| `stories/07-to-10-talent.md` | PERF-001, PERF-002, PERF-003, PERF-005, PERF-006 and PERF-007 follow this document; new stories PERF-008 to PERF-012; scenarios PERF-020 to PERF-050 in §13 |
| `docs/20` §5.3 | Default method `none` and 90 days (owner, Module 07 R4.1–R4.2); the FTE × days method stays as an organization's choice |
| `docs/15` Step 17 | Read this document; build on migration 0014; pass PERF-008 to PERF-012 and PERF-020 to PERF-050 |
| `docs/16` | Q35 decided; new Q49 (advisers for the Indigenous and non-profit templates); items to verify for this module |
| `docs/22` | Settings from 0014 are listed here, not in `docs/22` §2; FB-038 |
| `AGENTS.md` | Reading order item 15; rule 52; Step 1 migration 0014 and its smoke test; Step 17 |
| `.cursor/rules/00-cando.mdc` | Rule 52 in short |
| `tests/schema/schema_0006_smoke.sql`, `schema_0008_smoke.sql` | Reviews state their rating mode and sections their days worked; 0006 states the FTE × days method it tests; 0008 checks the new defaults, then the organization's own method; no rule relaxed |

Where a listed document still says otherwise, this document wins.

---

## 15. Open questions and items to verify

| Item | Until decided |
| --- | --- |
| Advisers for the Indigenous and non-profit starter templates (Q49) | These organizations adapt the standard templates |
| Wording of the caution `performance.pip_protected_ground` | Reviewed with human rights counsel before Step 17 |
| Keeping adverse records after their sunset for HR only | Checked against each province's privacy and records retention rules with privacy counsel before Step 17 (Module 13 retention schedule) |
| Agreement fields for rating limits, representation and sunset periods | Added to `rules/agreements/agreement.schema.json` in Step 7 |
| AI writing help | Built with the platform assistant in Step 19 |
| Board or council evaluation of the chief executive | Later phase (R7.3) |
