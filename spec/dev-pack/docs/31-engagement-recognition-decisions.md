# 31 · Engagement and recognition decisions

Oct 30, 2026 · @Wael

This document records the owner's review of Module 10 (Employee Engagement & Recognition) and turns each decision into something the build can follow: a setting with its default, a database check, a rule the organization sets, a route it edits, a caution, or a screen behaviour. The review went round by round; the working record is `claude/review/10-engagement-recognition-decisions.md` in the project.

It covers the survey tool and what can be uploaded, AI, confidential and anonymous surveys, the smallest group shown, employers covered by freedom-of-information laws, how surveys reach people, lifecycle surveys, union consultation, flagged comments, results for managers, comments and themes, action plans, recognition and who makes it public, points, recognition in performance reviews, CRA's gift and award rules, cash awards, service milestones, celebrations, award programs, announcements and urgent alerts, ideas, the anonymous feedback box, the speak-up channel, Teams and Slack, wellbeing, groups, observances, the directory and packaging.

**Precedence.** On these topics this document wins over `requirements/10` and the ENG stories in `stories/07-to-10-talent.md`. `docs/21` still governs service dates and self-identification, `docs/24` payroll and its earnings codes, `docs/25` §8 pay transparency and the smallest self-identified group, `docs/26` the EAP and wellness accounts, `docs/28` reviews, and `docs/22` still wins on values, defaults, languages and fallbacks. §14 lists every place that changes. The schema is `schema/0017_engagement_decisions.sql` (migration 0017, Step 1), checked by `tests/schema/schema_0017_smoke.sql`. CRA's gift and award rules are in `rules/recognition/ca-2026-gifts-and-awards.json`, and the starter rules for flagged comments in `rules/engagement/comment-flag-rules.json`.

**The owner's rules for this module.**

1. Every decision is a default each organization can change at setup or later; only legal floors and safety rules are fixed. CanDo pre-fills its suggested numbers at setup, and the organization keeps or changes them (Q46).
2. People can speak without being identified. Survey answers never carry a person, results are shown only for groups large enough, open comments are read by HR, and an employer covered by a freedom-of-information law runs anonymous surveys only.
3. Recognition belongs to the person recognized. It is private until they choose to make it public, and it reaches their performance review only if they attach it.
4. CRA's rules are applied, not guessed. Each gift and award is recorded with what CRA needs, the taxable part is worked out, and payroll confirms it.

---

## 1. Decisions at a glance

| # | Decision | Setting or rule | Section |
| --- | --- | --- | --- |
| R1.1 | CanDo builds its own survey tool, and organizations can upload external or partner surveys | `talent.survey.source` | §3.1 |
| R1.2 | AI comment themes later, off until switched on; AI only summarises, above the minimum group | `engagement.ai_comment_themes` (off) | §4.2 |
| R1.3 | Confidential by default, with a fully anonymous option per survey | `engagement.default_mode`: confidential | §3.2 |
| R1.4 | Smallest group shown: 5 by unit (never below 3); 10 by self-identified group | `engagement.min_group_size`: 5; `privacy.min_group_size_self_id`: 10 | §3.3 |
| R2.1 | Both question sets and results can be uploaded; imported results meet the same minimum groups | `IMPORT_BELOW_MIN_GROUP` | §3.1 |
| R2.2 | A comment suggesting harassment, a safety risk or self-harm is flagged by rule to a named HR contact, without identity; every survey shows the speak-up link and crisis resources | `talent.comment_flag`; `rules/engagement` | §3.8 |
| R2.3 | Surveys reach people by email and the app at launch | `survey_invitation.channel` | §3.5 |
| R2.4 | Where an agreement requires union consultation, opening the survey needs a caution | Caution `engagement.union_consultation` | §3.7 |
| R3.1 | A manager sees the team's results from 5, plus a roll-up of everyone under them | `talent.survey_scores()` | §4.1 |
| R3.2 | Open comments are read by HR only; managers see themes | Access rule | §4.2 |
| R3.3 | Managers are expected to agree 2 or 3 actions within 60 days, with reminders; progress shown to the team | `engagement.action_plan_days`: 60 | §4.3 |
| R3.4 | All lifecycle surveys run automatically: onboarding at 30 and 90 days, exit, after a promotion, return from leave | `engagement.lifecycle_surveys` | §3.6 |
| R4.1 | Recognition is private by default; only the recipient can make it public | `RECIPIENT_CONSENT_REQUIRED` | §5.1 |
| R4.2 | HR approves recognition before it goes public | Route `recognition_publication` (starter: HR) | §5.2 |
| R4.3 | Points and budgets tracked in CanDo; the organization hands out rewards itself | `talent.points_budget`, `talent.reward` | §5.3 |
| R4.4 | Recognition appears in a performance review only if the employee attaches it | `RECIPIENT_CONSENT_REQUIRED` | §5.4 |
| R5.1 | Service milestones every 5 years from the continuous service date, changeable | `recognition.milestone_years` | §6.3 |
| R5.2 | CRA's gift and award rules tracked; the taxable part sent to payroll, which confirms it | `ref.gift_award_rule`; `talent.reward` | §6.1 |
| R5.3 | Cash awards go through the organization's route | Route `recognition_award` | §6.2 |
| R5.4 | Formal award programs later | — | §6.5 |
| R6.1 | Targeted announcements with read receipts for important notices | `announcements.read_reminder_days` | §7.1 |
| R6.2 | Urgent alerts by push and email, plus SMS used only for emergencies | `announcements.sms_for_urgent` (on); `SMS_URGENT_ONLY` | §7.2 |
| R6.3 | Ideas with voting and an anonymous feedback box at launch, plus a whistleblower channel | `talent.idea`, `talent.feedback_thread` | §7.3 |
| R6.4 | Microsoft Teams and Slack at launch | Channels | §7.5 |
| R7.1 | The whistleblower channel is a separate speak-up channel at launch, designed in the Module 13 review | Module 13 | §7.4 |
| R7.2 | Wellbeing at launch is a resource hub only | `talent.wellbeing_resource` | §8.1 |
| R7.3 | Engagement is included in every plan; advanced survey features are an add-on | Packaging | §9 |
| R8.1 | Groups (ERGs and committees) later | — | §8.2 |
| R8.2 | A starter observances calendar the organization edits; none becomes a paid holiday | `ref.observance`, `talent.observance` | §8.3 |
| R8.3 | Directory: name, role, unit and work contact; photo, skills, interests and name pronunciation only if the employee adds them | `talent.profile_extra` | §8.4 |
| R8.4 | An employer covered by a freedom-of-information law runs anonymous surveys only | `SURVEY_MODE_NOT_ALLOWED` | §3.4 |

---

## 2. How the module is set up

### 2.1 Settings

| Setting | Decides | CanDo default | Set per |
| --- | --- | --- | --- |
| `engagement.default_mode` | How a new survey keeps answers | Confidential | Organization, employer |
| `engagement.min_group_size` | Smallest group whose results are shown (by unit or any breakdown except self-identified groups) | 5, never below 3 | Organization |
| `engagement.ai_comment_themes` | AI summaries of comment themes | Off | Organization |
| `engagement.action_plan_days` | Days after a survey closes to agree actions | 60 | Organization, employer |
| `engagement.lifecycle_surveys` | Events that send a survey automatically | Onboarding at 30 and 90 days, exit, promotion, return from leave | Organization, employer |
| `recognition.milestone_years` | Years of service celebrated | 5, 10, 15 … 50 | Organization, employer |
| `recognition.milestone_reminder_days` | Days before a milestone the manager is reminded | 30 | Organization, employer |
| `announcements.read_reminder_days` | Days after an important notice when people who have not read it are reminded | 3 and 7 | Organization, employer |
| `announcements.sms_for_urgent` | Urgent alerts also go by SMS | On | Organization, employer |

Pre-filled values follow the Q46 rule: the setup screen shows CanDo's suggestion and the organization keeps or changes them. The 30-day milestone reminder and the reminders on days 3 and 7 are CanDo's suggestions. `engagement.min_group_size` and `recognition.milestone_years` were planned in `docs/22` §10.2 and are created here. Self-identified groups keep `privacy.min_group_size_self_id` (10, `docs/25` §8.2). No setting is left to choose at setup.

### 2.2 Set up by each organization

| What | Where | Until it is set |
| --- | --- | --- |
| Whether each employer is covered by a freedom-of-information law, and which | `core.legal_entity_version.information_access_covered` and `information_access_law` (§3.4) | Its surveys cannot be created (`INPUT_REQUIRED`) |
| The HR contact flagged comments go to | `talent.survey_escalation_contact` (§3.8) | A survey with open comments cannot open (`ESCALATION_CONTACT_REQUIRED`) |
| Its values for recognition | The organization list `recognition_value` | Recognition cannot be given |
| Points budgets | `talent.points_budget` (§5.3) | Recognition without points |
| Observances | Copied from the starter list, then its own (§8.3) | The starter list is shown as a suggestion |
| Wellbeing links | `talent.wellbeing_resource` (§8.1) | The EAP from Benefits and the crisis lines only |
| Teams and Slack channels | The integration settings (§7.5) | CanDo's app and email |

### 2.3 Routes

Two starter routes are copied to every organization, and each organization edits them like any other route (`docs/23` §2.2):

| Route | Subject | Steps |
| --- | --- | --- |
| `recognition_publication` | A recognition its recipient asked to make public | HR |
| `recognition_award` | A cash or near-cash award | The proposer's manager; HR |

The sender of a recognition, its recipient and the proposer of an award never approve it (`SELF_APPROVAL`).

### 2.4 Cautions

| Caution | When | Section |
| --- | --- | --- |
| `engagement.union_consultation` | A survey opens for a group whose collective agreement requires the union to be consulted | §3.7 |

It always needs a written reason and shows what the agreement requires.

---

## 3. Surveys

### 3.1 CanDo's own tool, uploads and imports (R1.1, R2.1)

CanDo builds the survey tool: a question library with drivers (engagement, leadership, manager, growth, recognition, workload, belonging, pay fairness), Likert, eNPS, choice, ranking, yes or no and open questions, English and French texts, and accessibility. A survey's `source` says where it came from:

- `cando`: built from the library and the organization's own questions.
- `uploaded_questions`: a partner's or the organization's own questionnaire, loaded from a file and run in CanDo like any other survey.
- `imported_results`: results from another tool (Qualtrics, Culture Amp or the organization's previous system), loaded into a closed survey. Each row is a group, never a person, and a group under its minimum is refused (`IMPORT_BELOW_MIN_GROUP`).

Questions are fixed once the survey opens, and so are its mode and audience (`SURVEY_LOCKED`).

### 3.2 Confidential by default, anonymous by choice (R1.3)

A new survey is confidential (`engagement.default_mode`). Its answers are kept with group attributes (unit, location, employer, employment type, tenure band, career level, union or not, shift, the lifecycle event, and self-identified groups only with consent). They are never kept with a person. A fully anonymous survey keeps only the unit. Either way, `talent.survey_submission` has no person link and keeps the date, not the time, so answers cannot be matched to who logged in when. No administrator can look up a person's answers, and answers are never changed once given. `talent.survey_response` (0001) is kept as history and read-only.

### 3.3 The smallest group shown (R1.4)

Results by unit, and every breakdown except self-identified groups, are shown from `engagement.min_group_size` (5); the organization can raise it but never set it below 3. A survey can raise its own minimum, never lower it (`SURVEY_MIN_GROUP_BELOW_ORGANIZATION`). A breakdown by self-identified group is shown only from `privacy.min_group_size_self_id` (10). An item is shown only when enough people answered that item. This closes the open question on the anonymity threshold and settles `engagement.min_group_size` against the rule of 10 (`docs/22` §10.2).

### 3.4 Employers covered by a freedom-of-information law (R8.4)

Survey answers CanDo holds for a public body are that body's records, open to access requests. An employer covered by a freedom-of-information law (for example BC's FIPPA, Ontario's MFIPPA, the federal Access to Information Act) runs anonymous surveys only: its surveys are created anonymous and cannot be made confidential (`SURVEY_MODE_NOT_ALLOWED`). A survey of the whole organization is anonymous if any of its employers is covered. Each employer records whether it is covered and by which law; until it does, its surveys cannot be created (`INPUT_REQUIRED`). First Nations governments are generally not covered by these laws and follow their own policies.

### 3.5 Reaching people (R2.3)

Invitations and reminders go by email and the mobile app at launch. CanDo records who was invited (`talent.survey_invitation`) only to send reminders and count participation by unit, shown from the minimum group (`talent.survey_participation()`); it never shows who did not answer. SMS, kiosk mode and QR codes are not used for surveys at launch.

### 3.6 Lifecycle surveys (R3.4)

The events in `engagement.lifecycle_surveys` send a survey automatically: onboarding at 30 and 90 days (with Module 02), exit (with Module 11), after a promotion and on return from leave. A return-from-leave survey never states the kind of leave. Few people go through each event, so results are grouped over longer windows until a group reaches the minimum (`talent.survey_scores()` with a window).

### 3.7 Unions (R2.4)

Where a collective agreement requires the union to be consulted on surveys (a field the agreement library adds in Step 7), the survey records `union_consultation_required`, and opening it needs the caution `engagement.union_consultation` with how and when the union was consulted. Results can be shared with joint committees at the same minimum groups.

### 3.8 Flagged comments and crisis resources (R2.2)

Open comments are checked against the keyword rules in `rules/engagement/comment-flag-rules.json` (harassment, safety, self-harm, in English and French; the organization adds terms and cannot remove a starter one). A match sends the comment's text, never the writer's identity, to the HR contact the organization names (`talent.comment_flag`), who records how it was handled. A survey with open questions cannot open until a contact is named (`ESCALATION_CONTACT_REQUIRED`). Every survey's confidentiality notice says this can happen, and every survey shows the speak-up channel (§7.4), the crisis lines (9-8-8, the Hope for Wellness Help Line) and the EAP.

---

## 4. Results and action

### 4.1 What managers see (R3.1)

Each manager whose team has at least the minimum group of answers sees the team's scores, trend and comparison to the organization, and a roll-up of everyone under them; a team under the minimum is counted only in the roll-up (`talent.survey_scores()` for a set of units, `talent.survey_breakdown()` by attribute). Executives see the organization and their areas the same way.

### 4.2 Comments and themes (R3.2, R1.2)

Original comments are read by HR only. Managers see themes: until the organization switches on `engagement.ai_comment_themes`, themes come from fixed keyword rules grouped by the question's driver; once it is on, AI summarises them. Either way themes are shown only above the minimum group and never quote a comment. AI only summarises and never decides (AGENTS rule 14).

### 4.3 Action plans (R3.3)

Each manager with results gets an action plan (`talent.action_plan`) due `engagement.action_plan_days` (60) after the survey closes, to agree 2 or 3 actions with the team (`talent.action_item`), each linked to the questions it answers. A plan is agreed only with at least one action. Owners are reminded once a plan is past its date (`talent.action_plans_overdue()`). Actions marked for the team are shown to them as "you said, we did"; organization-wide actions are owned by executives. The next pulse shows whether things moved.

---

## 5. Recognition

### 5.1 Private until the recipient chooses (R4.1)

Recognition is tied to one of the organization's values (`recognition_value`) and starts private: the recipient and their manager see it. Only the person recognized can ask to make it public; the sender cannot (`RECIPIENT_CONSENT_REQUIRED`). No one recognizes themself (`SELF_RECOGNITION`). The same message to several people is a batch, and each recipient decides for themself.

### 5.2 HR approves before it goes public (R4.2)

A request to go public goes through the organization's `recognition_publication` route (starter: HR) before it appears on the feed, the recipient's profile, or Teams and Slack. HR, or whoever the organization names, can remove a public recognition with a reason. Recognition distribution reports (by team, location and shift, and by self-identified group from 10) help leaders see who is overlooked.

### 5.3 Points and rewards (R4.3)

Points are optional. A giver can award points only from their own budget for the period (`talent.points_budget`, `POINTS_BUDGET_EXCEEDED`). There is no rewards catalogue at launch: the organization hands out rewards itself and records each one (`talent.reward`), so CRA's rules apply to it (§6.1). This closes the open question on a rewards partner.

### 5.4 Performance reviews (R4.4)

Recognition reaches a performance review only when the person recognized attaches it to their own review (`RECIPIENT_CONSENT_REQUIRED`); managers never pull it in.

---

## 6. Rewards, milestones and tax

### 6.1 CRA's gift and award rules (R5.2)

Each reward records its kind (cash, near-cash, gift card, non-cash), occasion (special occasion, recognition, long service, performance), value including taxes and, for a gift card, its retailers and whether it is prepaid and cannot be converted to cash. When it is given, CanDo applies the year's rules from `ref.gift_award_rule` (loaded from `rules/recognition`; `GIFT_RULE_MISSING` if the year is not loaded, `RULE_NOT_VERIFIED` if it is not checked):

- Cash, near-cash, a gift card that fails CRA's conditions and any reward for performance are taxable in full.
- Other non-cash gifts and awards share $500 a year; only the amount over $500 is taxable.
- A long-service award for 5 or more years of service, at least 5 years after the last one, has its own $500; the amount over it is taxable.

Any taxable amount goes to payroll as `to_confirm` with the earnings code `AWARD-CASH` (tax, CPP and EI) or `AWARD-BENEFIT` (tax and CPP, not EI), and payroll confirms it; the person who recorded or proposed the award never does (`SELF_APPROVAL`). `talent.cra_award_year()` shows each person's year. CRA's page was checked on 30 October 2026; the 2026 values are `official`.

### 6.2 Cash awards (R5.3)

A cash or near-cash award (a spot award, a recognition bonus) is proposed and goes through the organization's `recognition_award` route (starter: the proposer's manager, then HR) before it is approved (`ROUTE_APPROVALS_MISSING`). It is paid through payroll as a one-time item. The proposer and the recipient never approve it.

### 6.3 Service milestones (R5.1)

Milestones come from the continuous service date in Core HR (`docs/21`) and `recognition.milestone_years` (every 5 years, changeable). `talent.milestones_due()` lists them for a period, and the manager is reminded `recognition.milestone_reminder_days` (30) before (`talent.milestone_reminders()`). A milestone gift is a long-service award for CRA when it meets §6.1.

### 6.4 Birthdays and other celebrations

Birthdays and personal celebrations are shown only when the employee opts in (`talent.celebration_consent`), giving the day themselves; CanDo never uses the date of birth from Core HR.

### 6.5 Award programs (R5.4)

Formal programs (nominations, criteria, judging panels) come in a later release.

---

## 7. Announcements and employee voice

### 7.1 Announcements (R6.1)

Announcements (`talent.announcement`) are targeted by employer, location, unit, union, language or employment type (`AUDIENCE_SCOPE_UNKNOWN` for anything else) and scheduled ahead, in the organization's languages (`docs/22` §4), with the reader's language first. A notice marked important needs a read receipt (`talent.announcement_receipt`), and people who have not read it are reminded on the days in `announcements.read_reminder_days` (`talent.receipts_to_remind()`).

### 7.2 Urgent alerts (R6.2)

An urgent alert (site closure, weather, safety incident) goes by push and email, and by SMS to everyone at the location with a phone number while `announcements.sms_for_urgent` is on; the organization pays per message. SMS is used for nothing else (`SMS_URGENT_ONLY`), and an alert sent by SMS cannot later be turned into an ordinary notice.

### 7.3 Ideas and the anonymous feedback box (R6.3)

Ideas (`talent.idea`) are submitted by name, voted on once per person and tracked to a status; declining one gives a reason. The anonymous feedback box (`talent.feedback_thread`, `talent.feedback_message`) is always open: the writer is never recorded, reads HR's replies with a secret only they hold (CanDo keeps its hash), and HR replies by name. Messages are checked against the same flag rules (§3.8).

### 7.4 The speak-up channel (R7.1)

The whistleblower channel is a separate speak-up channel at launch for harassment, safety, ethics and fraud reports, apart from engagement feedback. Reporters can stay anonymous and still get replies, and only investigators the organization names see the cases. Its design (intake, case handling, protection from reprisal, the law's requirements) is part of the Module 13 review; surveys, the feedback box and the voice page link to it.

### 7.5 Teams and Slack (R6.4)

Public recognition, announcements and survey invitations can be posted to Microsoft Teams and Slack channels the organization connects (`docs/11`). Survey answers are always given in CanDo, never in a chat tool.

---

## 8. Wellbeing, groups, observances and the directory

### 8.1 Wellbeing hub (R7.2)

At launch wellbeing is a hub of links (`talent.wellbeing_resource`): the EAP and wellness accounts from Benefits (`docs/26`), mental health supports, crisis lines and financial wellness. CanDo collects no health information, participation is voluntary, and managers never see individual use. Challenges and events come later.

### 8.2 Groups (R8.1)

Employee resource groups and committees come in a later release, with membership hidden by default because belonging to some groups reveals sensitive information.

### 8.3 Observances (R8.2)

A starter calendar (`ref.observance`) is offered at setup: National Day for Truth and Reconciliation, National Indigenous Peoples Day, Black History Month, Asian Heritage Month, Pride Month and major religious observances (dated ones loaded each year in `ref.observance_date`). The organization keeps what it observes in `talent.observance` and adds its own community events, ceremonies and land-based activities. An observance is never a paid holiday; holidays come only from the organization's holiday calendar (`docs/27`).

### 8.4 The directory (R8.3)

Staff see each other's name, role, unit and work contact from Core HR. A photo, interests, name pronunciation and the skills profile appear only if the employee adds them (`talent.profile_extra`; skills as in `docs/29` §7.2).

---

## 9. Packaging (R7.3)

Engagement is included in every plan: recognition, milestones, announcements, the feedback box and basic surveys come with CanDo; advanced survey features (uploaded questionnaires, imported results, AI themes, large-scale breakdowns) are an add-on. This closes the open question on selling the module separately.

---

## 10. Fallbacks

None added. A survey's mode comes from `engagement.default_mode`, or is anonymous for a covered employer (§3.4); an employer whose coverage is not recorded stops its surveys rather than being assumed either way.

---

## 11. Data model (migration 0017)

| Object | What it holds |
| --- | --- |
| Settings in §2.1 | 9 settings with CanDo defaults |
| `core.legal_entity_version.information_access_covered`, `information_access_law`; `core.information_access_covered()` | §3.4 |
| `talent.survey` (mode filled), `talent.survey_question`, `talent.survey_escalation_contact`, `talent.survey_invitation`, `talent.survey_submission`, `talent.comment_flag`, `talent.imported_result` | §3 |
| `talent.survey_min_group()`, `talent.survey_scores()`, `talent.survey_breakdown()`, `talent.survey_participation()`, `talent.action_plan` (due date filled), `talent.action_item`, `talent.action_plans_overdue()` | §4 |
| Organization list `recognition_value`; `talent.recognition`, `talent.points_budget` | §5 |
| `ref.gift_award_rule`, `talent.reward` (bucket and taxable amount computed), `talent.cra_award_year()`, `talent.milestones_due()`, `talent.milestone_reminders()`, `talent.celebration_consent` | §6 |
| `talent.announcement`, `talent.announcement_channel`, `talent.announcement_receipt`, `talent.receipts_to_remind()`, `talent.idea`, `talent.idea_vote`, `talent.feedback_thread`, `talent.feedback_message` | §7 |
| `talent.wellbeing_resource`, `talent.profile_extra`, `ref.observance`, `ref.observance_date`, `talent.observance` | §8 |
| Route subjects `recognition_publication` and `recognition_award`, two starter routes, the caution, `check_approval_task()` with the new subjects | §2 |
| `rules/payroll/starter-pay-codes.json` gains `AWARD-CASH` and `AWARD-BENEFIT` | §6.1 |

Every new tenant table has `tenant_id` with forced row-level security; text fields are registered as translatable (`docs/22` §4.3). The starter routes are copied to existing organizations, skipping one that keeps a third language as required for its data (FB-035).

---

## 12. Validation, API and events

**Errors added by 0017:** `SURVEY_MODE_NOT_ALLOWED`, `AUDIENCE_SCOPE_UNKNOWN`, `SURVEY_MIN_GROUP_BELOW_ORGANIZATION`, `SURVEY_LOCKED`, `ESCALATION_CONTACT_REQUIRED`, `SURVEY_NOT_OPEN`, `SUBMISSION_ATTRIBUTE_NOT_ALLOWED`, `ANSWER_UNKNOWN_ITEM`, `IMPORT_BELOW_MIN_GROUP`, `SELF_RECOGNITION`, `RECIPIENT_CONSENT_REQUIRED`, `POINTS_BUDGET_EXCEEDED`, `GIFT_RULE_MISSING`, `SMS_URGENT_ONLY`. Existing ones used: `INPUT_REQUIRED`, `FEATURE_OFF`, `RULE_NOT_VERIFIED`, `SELF_APPROVAL`, `ROUTE_APPROVALS_MISSING`, `CAUTION_NOT_ACKNOWLEDGED`, `LIST_VALUE_UNKNOWN`.

**Checks in the application (Step 17 unless noted), not the database:** the question library and survey builder; uploading questionnaires and result files (refusing any column that names a person); sending invitations and reminders by email and the app and marking an invitation answered in the same transaction as the answer, with no link between them; never exposing invitations per person; snapshotting group attributes, and self-identified groups only with consent; running the flag rules on comments and feedback-box messages; lifecycle surveys on events (with Steps 5, 14 and 16); who sees results (managers' units and roll-ups) and HR-only comments; keyword themes, and AI themes once switched on; action plan reminders; recognition feeds and notifications; the union consultation field from the agreement library (Step 7); rewards to payroll as one-time items with the award codes (with Step 9); milestone reminders and certificates; announcement delivery, receipts and reminders, and the SMS gateway for urgent alerts; ideas and the feedback box's secret; Teams and Slack posting; the wellbeing hub, directory and observances screens; loading `rules/recognition` into `ref.gift_award_rule` and yearly observance dates into `ref.observance_date`.

**API** (added to `api/openapi.yaml` in Step 17): `GET/POST /surveys` with questions, `open`, `close`, `upload-questions` and `import-results`; `POST /surveys/{id}/answers` (no identity returned); `GET /surveys/{id}/results?units=&window=`, `/breakdown?by=`, `/participation?units=`, `/themes`, `/comments` (HR); `GET/POST /survey-escalation-contacts`; `GET /comment-flags` (the named contact) with `handle`; `GET/POST /action-plans` with items and `agree`; `GET/POST /recognitions` with `request-public`, `remove` and `attach-to-review`; `GET/POST /points-budgets`; `GET/POST /rewards` with `submit`, `approve`, `give` and `confirm` (payroll); `GET /people/{id}/cra-awards?year=`; `GET /milestones?from=&to=`; `PUT/DELETE /me/celebrations`; `GET/POST /announcements` with channels and `read`; `GET/POST /ideas` with `vote` and `decide`; `POST /feedback` and `GET/POST /feedback/{secret}` (the writer) and `/feedback/threads` (HR); `GET/POST /wellbeing-resources`; `GET/PUT /me/profile-extras`; `GET/POST /observances`.

**Events** (added to `api/events.yaml`; identifiers only, AGENTS rule 9): `survey.opened`, `survey.closed`, `survey.comment_flagged`, `action_plan.due`, `recognition.given`, `recognition.made_public`, `reward.given`, `reward.taxable_to_confirm`, `milestone.upcoming`, `announcement.published`, `announcement.urgent`, `idea.decided`, `feedback.replied`.

---

## 13. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| ENG-020 | New organization opens setup | Defaults pre-filled; starter routes, caution and observances in place | smoke 1a–d | 1, 17 |
| ENG-021 | Employer covered by a freedom-of-information law with no law named | Refused | smoke 0 | 1 |
| ENG-022 | Survey for an employer whose coverage is not recorded | `INPUT_REQUIRED` | smoke 2a | 17 |
| ENG-023 | Survey for the society; for the town; the town's made confidential; the whole organization confidential | Confidential; anonymous; `SURVEY_MODE_NOT_ALLOWED` twice | smoke 2b–c | 17 |
| ENG-024 | Audience by "teams"; a survey minimum of 4; a lifecycle survey with no event | `AUDIENCE_SCOPE_UNKNOWN`; `SURVEY_MIN_GROUP_BELOW_ORGANIZATION`; refused | smoke 2d | 17 |
| ENG-025 | Opening without dates; with open comments and no contact; for a group whose agreement requires consultation | `INPUT_REQUIRED`; `ESCALATION_CONTACT_REQUIRED`; `CAUTION_NOT_ACKNOWLEDGED` until acknowledged | smoke 2f | 17 |
| ENG-026 | A question added or the mode changed after opening | `SURVEY_LOCKED` | smoke 2g | 17 |
| ENG-027 | An answer with a person link; to an unknown item; after closing; changed later | `SUBMISSION_ATTRIBUTE_NOT_ALLOWED`; `ANSWER_UNKNOWN_ITEM`; `SURVEY_NOT_OPEN`; `SURVEY_LOCKED` | smoke 2h–i | 17 |
| ENG-028 | An anonymous answer with its tenure | `SUBMISSION_ATTRIBUTE_NOT_ALLOWED` | smoke 2j | 17 |
| ENG-029 | A comment about threats | Flag to the named contact without identity; handled with a note | smoke 2k | 17 |
| ENG-030 | Imported groups of 4, a self-identified group of 8, a row naming a person, results into CanDo's own survey | Refused | smoke 2l | 17 |
| ENG-031 | Programs with 6 answers (4 on workload); Outreach with 3; both together | Item 1 shown at 4.00, workload hidden; Outreach hidden; roll-up of 9 shown | smoke 3a–b | 17 |
| ENG-032 | Breakdown by tenure (5 and 4); by self-identified group (6) | One group shown; none shown | smoke 3c | 17 |
| ENG-033 | Participation for 2 invited | Not shown | smoke 3d | 17 |
| ENG-034 | Plan for a survey closing 23 October; agreed with no action | Due 22 December; `INPUT_REQUIRED`; reminders after the due date | smoke 3e–f | 17 |
| ENG-035 | Self-recognition; posted public by the sender; a value the organization does not have | `SELF_RECOGNITION`; `RECIPIENT_CONSENT_REQUIRED`; `LIST_VALUE_UNKNOWN` | smoke 4a | 17 |
| ENG-036 | The sender asks to make it public; the recipient asks with no route | `RECIPIENT_CONSENT_REQUIRED`; `INPUT_REQUIRED` | smoke 4b | 17 |
| ENG-037 | Public before HR; approved by the recipient; by the sender; by HR | `ROUTE_APPROVALS_MISSING`; `SELF_APPROVAL` twice; public | smoke 4c | 17 |
| ENG-038 | The manager attaches it to a review; the recipient attaches it to someone else's | `RECIPIENT_CONSENT_REQUIRED`; `INPUT_REQUIRED` | smoke 4d | 17 |
| ENG-039 | Removed with no reason | `INPUT_REQUIRED` | smoke 4e | 17 |
| ENG-040 | 50 points with no budget; 60 then 50 from a budget of 100 | `POINTS_BUDGET_EXCEEDED`; second refused with 40 left | smoke 4f | 17 |
| ENG-041 | A gift in a year not loaded; in a year still to verify | `GIFT_RULE_MISSING`; `RULE_NOT_VERIFIED` | smoke 5a | 17 |
| ENG-042 | $300 then $300 of non-cash gifts | $0 then $100 taxable, to payroll to confirm | smoke 5b | 17 |
| ENG-043 | A gift card with no terms; a qualifying card after the limit; a card usable anywhere | Refused; taxable under the limit; taxable in full | smoke 5c | 17 |
| ENG-044 | $600 ten-year award; another within 5 years; a long-service award at 2 years | $100 taxable; general limit; general limit | smoke 5d | 17 |
| ENG-045 | A tablet for meeting targets | Taxable in full | smoke 5e | 17 |
| ENG-046 | Cash award approved without the route; by the proposer; by the recipient; by the manager's manager and HR | `ROUTE_APPROVALS_MISSING`; `SELF_APPROVAL` twice; approved | smoke 5f | 9, 17 |
| ENG-047 | Payroll confirmation by the proposer; by payroll | `SELF_APPROVAL`; confirmed; yearly totals | smoke 5g–h | 9, 17 |
| ENG-048 | Ben's 5 years on 29 November | Listed alone; manager reminded on 30 October | smoke 6a–b | 17 |
| ENG-049 | Birthday opt-in with no day; month 13 | Refused | smoke 6c | 17 |
| ENG-050 | Announcement by "teams"; a policy notice by SMS; an SMS alert made ordinary; SMS once switched off | `AUDIENCE_SCOPE_UNKNOWN`; `SMS_URGENT_ONLY` twice; `FEATURE_OFF` | smoke 7a–c | 17 |
| ENG-051 | Important notice unread on days 3, 4 and 7 | Reminded on 3 and 7 | smoke 7d | 17 |
| ENG-052 | A second vote; an idea declined with no reason; an HR reply with no HR user | Refused | smoke 7e–f | 17 |
| ENG-053 | The anonymous tables | No person link, no time of day | smoke 7g | 1 |
| ENG-054 | Observances, a crisis line link, directory extras | Recorded; no pay on an observance | smoke 8a | 17 |
| ENG-055 | Another organization reads engagement data | Nothing visible | smoke 9 | 1 |

---

## 14. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/10` | Points here at the top; open questions closed; surveys, results, recognition, tax, announcements, voice, wellbeing and groups marked where they changed |
| `stories/07-to-10-talent.md` | ENG-001 to ENG-004 follow this document; new stories ENG-005 to ENG-012; scenarios ENG-020 to ENG-055 in §13 |
| `docs/15` Step 17 | Read this document; build on migration 0017; pass ENG-001 to ENG-012 and ENG-020 to ENG-055 |
| `docs/16` | Items to verify for this module; starter pay codes now 27 |
| `docs/22` | Settings from 0017 are listed here, not in `docs/22` §2; `engagement.min_group_size` and `recognition.milestone_years` created as planned in §10.2 |
| `docs/24` §5.4 | Two award codes in the starter catalogue |
| `AGENTS.md` | Reading order item 18; rule 55; Step 1 migration 0017 and its smoke test; Step 7 and Step 17 |
| `.cursor/rules/00-cando.mdc` | Rule 55 in short |
| `rules/recognition/ca-2026-gifts-and-awards.json`, `rules/engagement/comment-flag-rules.json` | New |
| `rules/payroll/starter-pay-codes.json` | `AWARD-CASH` and `AWARD-BENEFIT` |

Where a listed document still says otherwise, this document wins.

---

## 15. Open questions and items to verify

| Item | Until decided |
| --- | --- |
| The keyword rules for flagged comments | Draft starter terms in English and French; review with a clinical adviser (self-harm) and employment counsel before Step 17 |
| Crisis lines shown on every survey (9-8-8, Hope for Wellness Help Line) | `verify_at_load`; check each number and site before launch |
| Which laws make an employer "covered" by province and sector | Each employer records its own; a reference list per province (FIPPA, MFIPPA, FOIP and others) built with the Module 13 privacy review |
| Union consultation on surveys in the agreement library | A field added in Step 7 (`docs/08`) |
| CRA's gift and award rules for each new year | 2026 `official` from CRA's page (modified 27 July 2026); reloaded each January |
| The speak-up channel | Designed in the Module 13 review; at launch |
| Award programs, groups (ERGs and committees), wellbeing challenges, a rewards catalogue | Later releases |

---

## Sources

- Canada Revenue Agency, Gifts, awards, and long-service awards: https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/payroll/benefits-allowances/gifts-awards-social-events/gifts-awards-long-service-awards.html
- EY Tax Alert 2023 No. 01, CRA's changes to its administrative policy on gift cards (secondary): https://www.ey.com/en_ca/technical/tax/tax-alerts/2023/tax-alert-2023-no-01
