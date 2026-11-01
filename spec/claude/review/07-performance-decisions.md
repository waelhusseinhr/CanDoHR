# 07 Performance Management · Review decisions

Review started 28 Oct 2026 with Wael. Decisions are logged here round by round; the developer pack is updated when the review is complete.

**Status: applied 28 Oct 2026.** The decisions are in `dev-pack/docs/28-performance-decisions.md`, migration `dev-pack/schema/0014_performance_decisions.sql` and its smoke test, the register (FB-038 new, proposed), and the updates listed in docs/28 §14. Pre-filled, each organization's to change (the Q46 principle): a 5-point scale; goals and competencies 50/50; calibration on; HR looks before release on four concerns (the lowest rating, a rating different from the suggestion, protected leave in the cycle, flagged by the one-up reviewer); new hires in the last 3 months not rated; each position rated by itself from 90 days worked, with no combined rating; 360° groups of 3 to 5 raters, shown from 3 answers, for development only; a check-in nudge after 30 days (CanDo's reading of "a month"); improvement plans of 60 days; no sunset for non-union records unless the organization sets one; AI writing help off. Two starter routes: the one-up look before release and HR's approval of an improvement plan. Open: the advisers for the Indigenous and non-profit templates (docs/16 Q49). Interpretations: the "overall rating" CanDo suggests is each position's rating, as positions are not combined; days on protected leave are not days worked; mid-year reviews and units whose agreement forbids ratings carry no rating, enforced in the database; reviews written before 0014 are marked rated and keep their ratings (FB-038, confirmed by Wael after the write-up). Wael also accepted the 30-day check-in nudge and protected leave not counting as days worked.

Planned rounds: 1 scales, overall ratings and AI · 2 goals and cycles · 3 reviews, sign-off and calibration · 4 people in several positions · 5 feedback, 360° reviews and check-ins · 6 performance improvement plans · 7 unions, records and special populations.

The principle from Modules 01 to 06 applies: every decision is a default each organization can change at setup or later, except legal floors and safety rules; routes and rules are the organization's, with reminders, cautions and recorded acknowledgements; CanDo pre-fills its suggested numbers at setup and the organization can change them (Q46).

Already decided elsewhere and not asked again: one review per cycle with a section per position, rated by that position's manager (`docs/20` §5); the competency model and its targets by career level (`docs/25` §9); merit guidelines from rating and range position, or range position only where there are no ratings (`docs/25` §6.2); probation check-ins, reminders and the end date passing (`docs/23` §7); HR reviews open cases before an ending (`docs/23` §7.5); people decide, AI never rates, ranks or decides (AGENTS rule 14); results using self-identification never show a group under 10 (`privacy.min_group_size_self_id`, `docs/25` §8.2); job, market and person kept separate (AGENTS rule 34).

## Round 1 · Scales, overall ratings and AI

| # | Decision |
| --- | --- |
| 1 | **A new organization starts with a 5-point scale (pre-filled),** from "not meeting" to "exceptional"; it can switch to 3 or 4 points or its own wording, and use separate scales for goals, competencies and values. |
| 2 | **Reviews end with one overall rating: CanDo suggests it from the goal and competency weights, and the manager chooses it,** explaining any difference from the suggestion. |
| 3 | **AI writing help comes later, with the platform assistant, and stays off until the organization switches it on;** then wording help, bias-language flags and feedback summaries, all marked as AI and editable. AI never rates, ranks or recommends terminations. |
| 4 | **CanDo develops starter review templates for Indigenous and non-profit organizations with advisers** (team-based, strengths-based, the organization's own values and teachings, Elder or community input); each organization edits them (closes the open question in `requirements/07`). |

## Round 2 · Goals and cycles

| # | Decision |
| --- | --- |
| 1 | **Goals are a living, shared document, set dynamically:** the manager or the employee can propose goals, and they discuss and agree them together. Goals align upward to the organization's vision and mission, organizational, departmental and team goals, and include the person's development and training goals (for example training that the role needs: IT training for IT staff, not for finance staff). Once both agree, the goals stand; every later amendment is tracked (who changed what, and when). Employees can assess their own strengths and areas to develop beside the manager's view, and either can ask others for input at any time. (Wael's own answer.) |
| 2 | **People hired in the last 3 months get goals but no year-end rating, pre-filled and editable** (the same 3 months as the pay cycle rule). |
| 3 | **The mid-year review records progress (on track, at risk, off track) and comments, and goal changes with reasons; no rating.** |
| 4 | **Goals and competencies count 50/50 in the suggested overall rating, pre-filled and changed per cycle or group.** |

## Round 3 · Reviews, sign-off and calibration

| # | Decision |
| --- | --- |
| 1 | **Calibration is part of each cycle, pre-filled on;** ratings are final only after it, and any change needs a reason. Each cycle can turn it off. |
| 2 | **Before the employee sees a review, the manager's own manager looks at it (one-up), through the organization's route; when there is a concern, HR also looks at it before release.** What counts as a concern is set up by each organization (for example the lowest ratings, an overall rating far from CanDo's suggestion, protected leave in the cycle, or the one-up reviewer flagging it). (Wael's own answer.) |
| 3 | **Signing a review means "I have seen it", not "I agree"; the employee can add comments and ask HR to review it,** and HR decides whether to reopen it, with a reason. |
| 4 | **After a rating is final, only HR can change it, with a written reason;** the employee is told, the history is kept, and pay already decided on it is reviewed separately. |

## Round 4 · People in several positions

| # | Decision |
| --- | --- |
| 1 | **Each position stands by itself: a person with two or more positions gets a rating for each position's section, and no combined rating across positions** (Wael's own answer; replaces the FTE × days weighting in `docs/20` §5 and closes docs/16 Q35). |
| 2 | **A position held for at least 90 days in the cycle gets its section rated; a shorter period gets comments only (pre-filled, editable).** |
| 3 | **When someone moves during the cycle, the previous manager rates their period if it reached the minimum days; otherwise they add comments for the new manager.** |
| 4 | **Each position's manager sees their own section (and the person's overall where one exists); other sections only through HR.** |

## Round 5 · Feedback, 360° reviews and check-ins

| # | Decision |
| --- | --- |
| 1 | **Confirmed: for someone in two positions, each position's rating is used on its own,** for that position's pay increase; where a person-level view is needed (succession, the nine-box), each position's rating is shown side by side. |
| 2 | **360° raters can be nominated by the employee, the manager or others (for example HR or a project lead); each rater group has 3 to 5 raters (pre-filled, editable), and a group's answers are shown only when at least 3 answered,** so nobody can be identified; the manager's own input is never anonymous. (Wael's own answer.) |
| 3 | **360° results are for development only (pre-filled):** shown to the employee and the manager, not used in ratings or pay; a cycle can allow them to inform ratings. |
| 4 | **Managers are nudged when a month passes with no check-in (pre-filled, editable per organization or team).** |

## Round 6 · Performance improvement plans

| # | Decision |
| --- | --- |
| 1 | **A performance improvement plan starts only after the manager rules out unclear expectations, training gaps, workload and accommodation needs, and HR approves it through the organization's route;** then the employee acknowledges it. |
| 2 | **A plan runs 60 days by default (pre-filled);** each plan can set its own length and be extended with a reason. |
| 3 | **No plan starts during a protected leave; where a protected ground (for example a disability) may be involved, a caution asks for an accommodation review and HR's approval, with a reason.** |
| 4 | **Unionized staff have a representative notified or present as their agreement says; non-union staff may bring a support person;** recorded on each meeting. |

## Round 7 · Unions, records and special populations

| # | Decision |
| --- | --- |
| 1 | **Where a collective agreement limits or forbids ratings, CanDo reads it from the agreement library:** those units automatically get development-only reviews (goals and feedback, no rating, no merit link) or the agreement's own form. |
| 2 | **Sunset clauses: after the agreement's period, an adverse record (a poor review, a plan) is hidden from managers and cannot be used in decisions, but kept for HR as retention law requires;** non-union staff have no sunset unless the organization sets a period. |
| 3 | **Board or council evaluation of the chief executive or chief administrative officer comes in a later phase.** |
| 4 | **Someone on a protected leave for part of the cycle is reviewed on the time worked, with goals prorated; under 90 days worked, no rating;** absence never lowers a rating. |
