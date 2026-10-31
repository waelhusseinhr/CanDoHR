# 10 Employee Engagement & Recognition · Review decisions

Review started 29 Oct 2026 with Wael. Decisions are logged here round by round; the developer pack is updated when the review is complete.

**Status: applied 30 Oct 2026.** The decisions are in `dev-pack/docs/31-engagement-recognition-decisions.md`, migration `dev-pack/schema/0017_engagement_decisions.sql` and its smoke test, the register, `rules/recognition/ca-2026-gifts-and-awards.json` (CRA's gift and award rules for 2026, from CRA's own page), `rules/engagement/comment-flag-rules.json` (draft keyword rules and crisis lines), two award codes in the starter pay codes, and the updates listed in docs/31 §14. Pre-filled, each organization's to change (the Q46 principle): confidential by default; results from 5 (never below 3); action plans within 60 days; all lifecycle surveys on; milestones every 5 years; SMS for urgent alerts on. CanDo's suggestions, not from the review: the manager is reminded 30 days before a milestone, and unread important notices are reminded on days 3 and 7. Off until switched on: AI comment themes. Fixed: anonymous surveys only for employers covered by a freedom-of-information law; self-identified groups from 10; recognition made public only by its recipient. Interpretations: while AI themes are off, managers see themes from keyword rules grouped by question driver; private recognition is seen by the recipient and their manager (and its sender); HR's approval of public recognition is a route the organization can edit; the cash award route starts with the proposer's manager, then HR; points come from the giver's own budget; a whole-organization survey is anonymous if any employer in it is covered; each employer must record whether it is covered before its first survey; a return-from-leave survey never names the leave; survey answers keep the date, not the time; the whistleblower channel gets no tables until the Module 13 review.

Planned rounds: 1 scope, surveys, AI and anonymity · 2 survey design, distribution and escalation · 3 results and action planning · 4 recognition and rewards · 5 awards, milestones and tax · 6 announcements and employee voice · 7 wellbeing, inclusion and Canadian considerations.

The principle from Modules 01 to 09 applies: every decision is a default each organization can change at setup or later, except legal floors and safety rules; routes and rules are the organization's, with reminders, cautions and recorded acknowledgements; CanDo pre-fills its suggested numbers at setup and the organization can change them (Q46).

Already decided elsewhere and not asked again: self-identification is voluntary and consented, and self-identified groups are never shown under 10 (`docs/21` §9.2, `docs/25` §8.2, `privacy.min_group_size_self_id`); the survey minimum group size is still open between Modules 10 and 12 (`docs/22` §10.2, `engagement.min_group_size`); service dates come from Core HR per agreement (`docs/21`); taxable benefits go to payroll through earnings codes (`docs/24`); the EAP and wellness accounts are in Benefits (`docs/26`); the organization's own words stay in the language it entered, with translation through CanDo's paid service (`docs/22` §4); people decide and AI never decides (AGENTS rule 14); the speak-up channel for harassment and ethics is Module 13.

## Round 1 · Scope, surveys, AI and anonymity

| # | Decision |
| --- | --- |
| 1 | **CanDo builds its own survey tool and can also take in external or partner surveys** (Wael's own answer: option 1, "but also can upload external or partner ones"); what can be uploaded is confirmed in Round 2. |
| 2 | **AI comment themes later, off until the organization switches them on;** AI only summarises, never decides, and runs only above the anonymity threshold. |
| 3 | **Confidential by default (answers linked to HR details, shown only as group results), with a fully anonymous option per survey.** |
| 4 | **Smallest group shown: 5 by unit (never below 3), 10 by self-identified group** (closes the open question on the anonymity threshold and settles `engagement.min_group_size` against `privacy.min_group_size_self_id`). |

## Round 2 · Survey design, distribution and escalation

| # | Decision |
| --- | --- |
| 1 | **An organization can upload both question sets and results:** a partner's or its own questionnaire, run in CanDo, and results from another survey tool; CanDo applies its anonymity limits to imported results too (confirms Round 1.1). |
| 2 | **A comment suggesting harassment, a safety risk or self-harm is flagged by rule and its text, without the person's identity, goes to an HR contact the organization names;** survey terms tell employees this can happen; every survey shows the speak-up link and crisis resources. |
| 3 | **Surveys reach people by email and the mobile app at launch;** no SMS gateway, kiosk mode or QR distribution at launch (Wael chose this over all channels). |
| 4 | **Where a collective agreement requires the union to be consulted, the agreement library marks it and launching a survey to that group needs a caution confirming the union was consulted;** results can be shared with joint committees. |

## Round 3 · Results and action planning

| # | Decision |
| --- | --- |
| 1 | **Each manager whose team meets the minimum of 5 sees the team's scores, trend and comparison to the organization, plus a roll-up of everyone under them;** a team under 5 counts only in the roll-up. |
| 2 | **Original open comments are read by HR only; managers see themes** (Wael chose this over managers reading comments after an identity screen). |
| 3 | **Managers are expected to make action plans, with reminders:** each manager with results gets a task to agree 2 or 3 actions with the team within 60 days (pre-filled, editable); progress is shown to the team ("you said, we did"). |
| 4 | **All lifecycle surveys run automatically:** onboarding at 30 and 90 days, exit, after a promotion and on return from leave (Wael chose all on); small numbers are grouped over time to reach the minimum of 5. |

## Round 4 · Recognition and rewards

| # | Decision |
| --- | --- |
| 1 | **Recognition is private by default: the recipient and their manager see it; only the recipient, not the sender, can make it public** (Wael's own answer). |
| 2 | **HR approves a recognition before it goes public** (Wael chose this over posting at once with report and remove). |
| 3 | **Points and budgets are tracked in CanDo; the organization hands out rewards itself** (no catalogue partner at launch; closes the open question). |
| 4 | **Recognition appears in a performance review only if the employee attaches it.** |

## Round 5 · Awards, milestones and tax

| # | Decision |
| --- | --- |
| 1 | **Service milestones pre-filled every 5 years (5, 10, 15, 20 …) from the continuous service date; the organization can change them** (Wael's own answer). |
| 2 | **CanDo tracks CRA's gift and award rules:** each award recorded as cash, gift card or non-cash, with what CRA needs logged; yearly totals per person against the $500 limits (general and long-service); cash and any excess sent to payroll as a taxable benefit, which payroll confirms. |
| 3 | **Cash awards (spot awards, recognition bonuses) go through the organization's route** (starter: the manager's manager, then HR), paid through payroll as taxable; the person who proposes one never approves it. |
| 4 | **Formal award programs (nominations, panels) come later, not at launch.** |

## Round 6 · Announcements and employee voice

| # | Decision |
| --- | --- |
| 1 | **Announcements at launch, targeted by employer, location, department, union or language and scheduled ahead;** notices marked important need a read receipt and remind those who have not read them. |
| 2 | **Urgent alerts (site closure, weather, safety incident) go by push and email, plus SMS used only for emergencies,** reaching everyone with a phone number; the organization pays per message (Wael chose this). |
| 3 | **Ideas with voting and status, and an always-open anonymous feedback box with two-way anonymous replies, both at launch, and a whistleblower channel** (Wael's own answer: "1 and whistleblower"); what the whistleblower channel covers is confirmed in Round 7. |
| 4 | **Microsoft Teams and Slack at launch:** public recognition, announcements and survey invitations can be posted to channels the organization connects; survey answers are always given in CanDo. |

## Round 7 · Whistleblowing, wellbeing and packaging

| # | Decision |
| --- | --- |
| 1 | **The whistleblower channel is a separate speak-up channel at launch,** apart from engagement feedback, for harassment, safety, ethics and fraud reports; reporters can stay anonymous and still get replies; only investigators the organization names see the cases; detailed design in the Module 13 review (confirms Round 6.3). |
| 2 | **Wellbeing at launch is a resource hub only:** links to the EAP, mental health supports, financial wellness and wellness accounts from Benefits; no health data collected; managers never see individual use. |
| 3 | **Engagement is included in every plan:** recognition, milestones, announcements and basic surveys come with CanDo; advanced survey features are an add-on (closes the open question). |

## Round 8 · Groups, observances and the directory

| # | Decision |
| --- | --- |
| 1 | **Groups (ERGs and committees) come later, not at launch** (after an explanation of ERGs and the privacy of their membership). |
| 2 | **A starter observances calendar, which the organization edits:** National Day for Truth and Reconciliation, National Indigenous Peoples Day, Black History Month, Asian Heritage Month, Pride and major religious observances; the organization adds community events, ceremonies and land-based activities; none becomes a paid holiday unless its holiday calendar says so. |
| 3 | **People directory: name, role, unit and work contact shown to staff; photo, skills, interests and name pronunciation only if the employee adds them.** |
| 4 | **An organization covered by a freedom-of-information law (a municipality, school board, health authority or government body) runs surveys fully anonymous only; confidential mode is not available to it** (Wael chose this over an anonymous default, after an explanation of access requests; First Nations governments are generally not covered by these laws and follow their own policies). |
