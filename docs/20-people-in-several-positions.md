# 20 · People in several positions

Oct 24, 2026 · @Wael

This document completes the rules for a person who holds more than one position at the same time. `docs/17` §4–§8 already gives every position (assignment) its own job, agreement, rates, schedule, reporting lines, funding, leave plan and end date. This document adds what was still missing:

- a position with two managers, and which of them approves what;
- leave and time split to the minute across positions and managers;
- extra pay for allowances and particular duties, per position;
- one review with a section per position, and competency assessments made in a position;
- benefits when the person is in two unions, or in one union and exempt in another position;
- what happens to benefits when one position ends, decided by the organization's own rules or by HR case by case.

**Precedence.** On these topics this document wins over `docs/17`, `requirements/03`, `05`, `06` and `07`, and `docs/19` §6.3 and §10.2. §12 lists every place that changes. The schema is `schema/0006_several_positions.sql` (migration 0006, Step 1), checked by `tests/schema/schema_0006_smoke.sql`. The calculations are specified by `reference/several_positions_reference.py` and `tests/assignments/several_positions_cases.json`; the TypeScript port must reproduce every case exactly.

**The rule behind everything here** is the one in `docs/17`: never assume one of anything per person. It now also applies to managers within one position. Code that reads "the position's manager" without naming the date, the hours and the capability is a bug, in the same way as "the employee's manager".

---

## 1. What was already in place, and what this adds

| Need | Already in `docs/17` | Added here |
| --- | --- | --- |
| More than one position | Several employments, each with several assignments (§4) | — |
| A job description, job evaluation and competency profile per position | Each assignment fills its own position and job | Reviews and competency assessments per position (§5) |
| More than one salary or hourly rate | Rate components per assignment (§6) | Allowances, stipends and duty rates per position (§4) |
| Funding from several funders or sources | Cost distribution per position or assignment, with funding lines, caps and fallbacks (§8) | Allowances charged to their own funding; one-time payments allocated by position (§4.3–§4.4) |
| Leaving one position and keeping the other | Ending one assignment cascades (§4.4) | Benefit changes by the organization's rules, or HR case by case, never below the statutory floor (§6.2) |
| More than one union, or exempt in one position | Agreement per assignment; leave plan per agreement (§4.3, §7.5) | Benefit plans per agreement, enrolment where each agreement requires, coordination of benefits (§6.1) |
| Each position reports to its own manager | Line relationship per assignment; requests split per assignment (§5.2) | — |
| One position reporting to two managers | Typed relationships (§5.1) | Approval by the days and hours each manager covers, or by both, or by either (§2) |
| Work split by days or by hours in the same day | Schedules per assignment (§7.3) | Requests split to the minute from each position's shifts (§3) |

---

## 2. Approvals when a position has more than one manager

### 2.1 Approval policy

Each position can have its own approval policy for each capability (`leave`, `time`, `overtime`, `expense`, `availability`), stored in `core.approval_policy`. An assignment can override its position's policy, for example during a job share. Without a policy, the mode is `by_coverage`.

| Mode | What it means | Example |
| --- | --- | --- |
| `by_coverage` (default) | Each part of the request goes to the manager who supervises those days and hours | Monday to Wednesday at the community centre, Thursday and Friday at the arena |
| `all` | Every manager of the position must approve | A shared clinical and administrative position where both managers want a say |
| `any` | The first manager to act decides for all of them | Two co-managers who cover for each other |

Two more settings apply in `by_coverage` mode:

- **Overlap.** For hours that two managers both cover, `all` (default) means both approve; `any` means either can.
- **Uncovered hours.** For hours that no manager covers, `line` (default) sends them to the line manager; `hr` sends them to HR.

### 2.2 Coverage

`core.approval_coverage` records what each manager supervises on a position: the line manager, or another relationship such as `program`, `functional` or `administrative` (`docs/17` §5.1). A coverage row can use any combination of three things:

- **Days of the week** (ISO 1 = Monday to 7 = Sunday). An overnight shift belongs to the day it starts.
- **Time windows** in the location's local time, for example `[["08:00","14:00"]]`. A window can run past midnight, as in `["22:00","06:00"]`.
- **Locations**, for a position worked at more than one site.

A row also lists the capabilities it covers (by default `leave`, `time` and `overtime`). A program manager might approve time on the program but not leave, for example.

When a position has one manager and no coverage rows, that manager gets everything, as before.

### 2.3 Several positions, each with its own manager

This needs nothing new. The request is split by position first (§3), and each position's part follows that position's own policy. A person with two positions and one manager on each sends one request, and it produces two parts for two managers.

### 2.4 Approval parts

Each part of a request is stored in `core.approval_part`, with:

- the request (`subject_type`: `leave_request`, `timesheet`, `overtime_preauth` or `availability_change`);
- the assignment it belongs to;
- its approvers and their rule (`all` or `any`);
- its minutes and intervals;
- why it was routed this way (`coverage`, `uncovered_line`, `uncovered_hr`, `all`, `any` or `escalated`).

The database computes each part's status from its decisions:

| Rule | Status |
| --- | --- |
| `any` | The first decision decides: `approved` or `declined`; `pending` until then |
| `all` | `declined` as soon as one approver declines; `approved` when every approver has approved; otherwise `pending` |

Statuses then roll up, ignoring cancelled parts. The parts of one assignment give the leave request component's status, and all the parts together give the request's status:

- all approved → `approved`;
- all declined → `declined`;
- any pending → `requested`;
- otherwise → `partially_approved`.

As in `docs/17` §5.2, the employee then keeps or cancels what was approved. Cancelling an approved part is allowed. Changing a decided part is not, and decisions can only be added, never edited.

### 2.5 Self-approval, delegates and absences

- **Self-approval.** No one approves their own request, including from another of their own positions. The database refuses a part whose approvers include any assignment of the requester (`SELF_APPROVAL`). The routing service sends that part to the manager's own approver (`routed_by = escalated`). `docs/17` §5.2 rule 4 still applies to the chain above.
- **Absent managers.** A delegate or acting manager (`docs/17` §5.1) takes the part during their period. If a part is not decided by the tenant's deadline, the routing service cancels it and creates a new part for the same minutes, addressed to the original approver and the approver's own manager under `any` (`routed_by = escalated`). Parts are never edited to add an approver.
- **Schedule changes.** If the schedule changes after a request is split, pending parts are cancelled and the request is split again. Decided parts stay, and any new minutes become new parts.

---

## 3. Splitting a request across positions and managers

### 3.1 What the split uses

For each assignment that the request covers (by default every active one):

| Schedule | Source |
| --- | --- |
| Published shifts | Each shift's start, end and unpaid break |
| Weekly pattern | The assignment's pattern for each day of the week |
| No schedule (casual, on call) | Nothing to split. The assignment is listed as skipped (`NOT_SCHEDULED`) and the employee may add hours by hand, which then route to that assignment's line manager |

### 3.2 The rule

For every minute of the request that falls in a shift of an assignment:

1. Find the assignment's approvers for the capability. Replace the requester, if listed, by their own approver.
2. Apply the policy (§2.1). In `by_coverage` mode, find who covers that minute: the shift's start day, the minute's clock time and the location.
3. Add the minute's paid share to the part for that set of approvers and rule. The paid share is (shift minutes − unpaid break) ÷ shift minutes, so a 7.5-hour shift with a 30-minute unpaid break counts 7.5 hours over 8 elapsed hours.

The result is one leave request component per assignment, each with one or more parts, plus the assignments that were skipped and why (`NOT_SCHEDULED`, `NO_WORK_IN_RANGE`).

### 3.3 Rounding

The calculation uses exact fractions. Each component's minutes are rounded half up once. Its parts then share those minutes by largest remainder, in the order the parts were first met, so the parts always add up exactly to the component. Hours are shown to two decimals.

### 3.4 Who writes the parts

Only the routing service writes `core.approval_part` rows, in the same transaction as the request and its components. Every part records the policy and coverage versions used, so an auditor can see why a manager received it.

### 3.5 Examples (from the cases file)

Jordan holds A1 (Program Coordinator, 0.6 FTE) and A2 (Lifeguard-Instructor). 2027-03-01 is a Monday.

| Case | Situation | Parts |
| --- | --- | --- |
| SPLIT-001 | Sick Wednesday (A1 shift) and Thursday (A2 shift) | A1 → M1 7.50 h; A2 → M2 7.50 h |
| SPLIT-002 | Same day: A1 09:00–11:00, A2 13:00–15:00 | A1 → M1 2.00 h; A2 → M2 2.00 h |
| SPLIT-003 | A1 has two managers, MA Monday to Wednesday and MB Thursday and Friday; leave Wednesday and Thursday | MA 7.50 h; MB 7.50 h |
| SPLIT-004 / 005 | The same position in `all` / `any` mode | One part to MA and MB, 15.00 h, rule `all` / `any` |
| SPLIT-006 | Friday not covered by anyone | Line manager MA 7.50 h (`uncovered_line`) |
| SPLIT-007 | MA covers 08:00–14:00, MB 12:00–20:00, shift 08:00–20:00 | MA 4.00 h; MA and MB together (`all`) 2.00 h; MB 6.00 h |
| SPLIT-008 | Casual position with no schedule | Skipped, `NOT_SCHEDULED` |
| SPLIT-009 | Half a shift with an unpaid break | 3.75 h |
| SPLIT-010 | Friday overnight shift 22:00–06:00 | All of it goes to the Friday manager |
| SPLIT-011 | Jordan manages her own second position | Escalated to her director |

---

## 4. Several rates, duties and allowances

### 4.1 Rates

Each assignment keeps its own rate components (`docs/17` §6). A person paid a salary in one position and an hourly rate in another is two assignments with two rates. Overtime follows the jurisdiction's rule for people with several rates (`docs/17` §7.2), never a blended rate by default.

### 4.2 Pay items per position

`core.assignment_pay_item` holds recurring extra pay that belongs to one position. Each item is effective-dated, has a source (`agreement`, `policy`, `offer`, `compensation_decision` or `manual`), and a manual item needs a reason.

| Kind | Basis | Example |
| --- | --- | --- |
| `allowance` | per pay period, per month, per year, per day worked, per shift, per hour worked, or percent of base | Car allowance of $150 a month on A1 only |
| `stipend` | as above | Coordinator stipend while leading a program |
| `duty_rate` | `rate_for_duty_hours`: the hours spent on the duty are paid at this rate instead of the base rate | Driving the program van at $28.50 an hour |
| `duty_premium` | `per_duty_hour`: added to the base rate for duty hours | Interpreting premium of $1.25 an hour |
| `on_call` | per shift or per day | Standby on weekends |

Duties are the tenant's list (`payroll.duty`, each with its pay code). A time line names the duty it was worked on (`timeleave.time_line.duty_code`). An item can carry conditions in `applies_when`, such as a required credential, which the time engine checks. Allowances and premiums set by an agreement stay in the agreement's rules (`docs/08`). A pay item is for pay that the agreement does not define, or that is specific to the person.

### 4.3 One-time payments

A one-time item (bonus, award, retro adjustment) now either names its assignment (`allocation = assignment`, the default since the Module 03 review: it cannot be saved until someone picks the position, `docs/24` §8.2) or, where the organization chose it in `payroll.one_time_allocation`, is shared across the employment's assignments by their earnings in the period (`earnings_share`). Sharing is to the cent, by largest remainder, in assignment order. If there are no earnings to share, the item stops with `NO_EARNINGS_TO_SHARE` until HR names an assignment.

Examples:

- ALLOC-001: $500 shared over earnings of 1,800 and 700 gives $360.00 and $140.00.
- ALLOC-002: $100 shared in three equal parts gives $33.34, $33.33 and $33.33.

### 4.4 Funding and costing

Every dollar is still distributed by the order in `docs/17` §8.2.

- A pay item is costed with its assignment (`cost_target = assignment`), or to its own funding lines (`cost_target = explicit`), for example a stipend paid from a different grant.
- A position funded by several sources, and a source funding portions of several positions, are both cost distribution lines. Each line has a percentage or a fixed amount, and the source's budget, eligible categories and cap behaviour apply across every position that draws on it.
- A shared one-time item is costed with each assignment's share.

---

## 5. Job descriptions, evaluations, competencies and reviews

### 5.1 One of each per position

Each assignment's position resolves to its own job, so a person in two positions has two job descriptions, two job evaluations (per job, or per position where the position has its own: `docs/19` §5.4), two sets of competency targets and two sets of requirements. No new tables are needed. The person's profile and the manager screens show them per position.

The conflict-of-interest rule for evaluations (`docs/19` §5.4) covers every job the evaluator holds or reports to, in any of their positions.

### 5.2 One review, one section per position

A review is still one per employment per cycle (`docs/17` §4.3). Each assignment held during the cycle gets a section in `talent.review_section`:

- **Owner.** The section is rated by that position's line manager. Where `docs/17` §5.1 relationships contribute (functional, program), they are contributors on that section.
- **Weight.** The section's FTE and its days held in the cycle; `days_worked` (protected leave not counted) decides whether it is rated (`docs/28` §6.2).
- **Rating exclusions.** A section can be unrated where the position's agreement excludes ratings (`rated = false`).
- **No self-rating.** No one owns or contributes to a section of their own review (`SELF_REVIEW`).
- **Same employment.** A section must belong to the review's employment (`SECTION_NOT_IN_EMPLOYMENT`).

### 5.3 The overall rating

> **Owner's review (28 October 2026, Module 07 R4.1–R4.2):** each position stands by itself. The default method is now `none`, with no combined rating, and a section is rated only from 90 days worked in the position (`reviews.min_section_days`); a shorter period gets comments only (`docs/28` §6). The FTE × days method below stays available as an organization's choice. This closes Q35.

`talent.review.overall_method` chooses how the overall rating is set:

| Method | Overall |
| --- | --- |
| `none` (default) | No overall rating; each section stands alone |
| `fte_weighted` | Σ(FTE × days × rating) ÷ Σ(FTE × days), over rated sections worked at least `min_section_days` (default 90), rounded half up to the scale's step |
| `primary_manager` | Set by the primary assignment's line manager, who sees every section |

Examples, for an organization that chooses `fte_weighted`:

- RATING-001: A1 0.6 FTE rated 4 and A2 0.4 FTE rated 3, both held the whole year, gives a score of 3.6000 and an overall rating of 4.
- RATING-002: a section held only 45 days is not rated and is left out.
- RATING-003: with a half-point step, a score of 3.6865 becomes 3.5.

Calibration (`requirements/07`) works on sections, and the overall rating is recomputed after calibration.

### 5.4 Competency assessments in a position

A competency assessment can name the assignment and review section it was made in. When CanDo computes a gap for a position (`talent.competency_gap`), it prefers the latest assessment made in that same position, then falls back to the latest one from anywhere. So a person can be at level 3 in client-centred practice in their coordinator role and at level 1 as a lifeguard, and each position's development plan reads its own.

### 5.5 Pay decisions per position

Merit guidelines read the rating of the position being increased (`comp.cycle.merit_rating_source = section`, the default). A tenant can choose the overall rating instead. Each increase applies to that assignment's own rate.

---

## 6. Benefits, unions and leaving one position

### 6.1 Two unions, or a union and an exempt position

- **Plan scope.** Each benefit plan has an eligibility scope:
  - `employer`: combined FTE of benefit-eligible assignments, as in `docs/17` §7.7;
  - `agreement`: the plan of one collective agreement, for example a union trust plan, for assignments under that agreement;
  - `assignment`: eligibility judged on one position alone.
- **Exempt positions.** An assignment with no agreement is in the employer's own plans.
- **Enrolment where each agreement requires.** A person is enrolled in each plan their positions qualify for. An enrolment in an `agreement` or `assignment` plan names the position that makes the person eligible (`via_assignment_id`). That position must belong to the person, and for an agreement plan it must be under that agreement on the coverage start date.
- **Coordination of benefits.** When two plans of the same kind cover the person (two health plans, for example), HR sets which plan pays first for that person and records why (owner's decision, 28 October 2026, `docs/26` §5.2, FB-020). Any order a plan contract sets (a union trust plan's, for example) is shown beside the decision; CanDo never orders the plans itself. The order is stored as `cob_rank` with who decided and why, and sent to carriers; until HR decides, the person is left out of the carrier file (`COB_ORDER_NOT_SET`).
- **Cash in lieu.** An assignment paid cash in lieu of benefits under its agreement stays out of the FTE count for the plans it replaces (`docs/17` §7.7).
- **Union dues** stay per assignment, on that assignment's earnings (`docs/17` §4.3).

### 6.2 When one position ends: the organization decides

Ending one position is not a termination (`docs/17` §4.4). What happens to the person's benefits depends on the organization, the reason and the province, so CanDo does not hard-code it. For every enrolment that the end affects, it proposes a decision:

1. **Eligibility on what remains.** Recompute eligibility on the remaining positions under the plan's scope. If the person is still eligible, the outcome is `no_change`. Class changes still follow `docs/17` §7.7.
2. **The statutory floor.** If the end is employer-initiated and notice is owed (from the notice calculation in Module 11, or entered by HR), the jurisdiction's `benefits_during_notice` rule applies:
   - `continue_required`: coverage cannot end before the notice period ends;
   - `not_explicit`: there is no statutory floor, but a warning is raised (`COMMON_LAW_REVIEW`) because a court may still award benefits for the reasonable notice period;
   - `verify_at_load`: the rule has not been checked yet, and the decision carries `RULE_NOT_VERIFIED`.
3. **The organization's rules.** `benefits.change_rule` holds the tenant's rules in priority order. Each rule matches on any of:
   - plan kinds or plans;
   - plan scope;
   - end reason categories;
   - employer-initiated or not;
   - jurisdiction;
   - agreement;
   - whether employment continues;
   - the ending position's employment type, for rules by class when employment ends (`docs/26` §7.1).

   Its action is one of:
   - `continue_until`, with a date rule: end of month, end of next month, a number of days or weeks, end of notice, end of severance (`docs/26` §7.1), or a fixed date;
   - `end_on_date`;
   - `hr_decides`.

   A rule can also offer conversion to an individual plan, and it cites its policy, plan contract or agreement article.
4. **Case by case.** If no rule matches, or the rule says `hr_decides`, the decision goes to HR with the facts and the floor.

The rule's date is raised to the statutory floor if it is earlier. HR can change any proposal, within these limits, which the database enforces:

| Constraint | Effect |
| --- | --- |
| `statutory_floor_respected` | Coverage can never end before the statutory floor, whoever decides |
| `case_by_case_needs_reason` | A decision with no rule behind it needs a written reason |
| `override_needs_reason` | Choosing a date other than the proposed one needs a written reason |
| `CHANGE_DECISION_FACTS_FROZEN` | The facts and the proposal cannot be edited. To change them, cancel the decision and recompute |
| `CHANGE_DECISION_IMMUTABLE` | An applied decision never changes |

End reasons are the tenant's own list (`core.end_reason`). Each reason maps to a category (`resignation`, `retirement`, `end_of_term`, `layoff`, `position_eliminated`, `termination_without_cause`, `termination_with_cause`, `reduction_by_employer`, `transfer`, `death`, `other`) and is marked as employer-initiated or not. The rules use the category, so each organization can name its own reasons freely.

### 6.3 The statutory floor by jurisdiction

`rules/employment-standards/ca-2026.json` gains `benefits_during_notice` for each jurisdiction:

- **Ontario: `continue_required`.** The employer must keep up benefit plan contributions during the statutory notice period.
- **British Columbia: `not_explicit`.** Research found no explicit statutory duty to continue benefits with pay in lieu, although conditions of employment must not be changed during working notice.
- **Every other jurisdiction: `verify_at_load`** until it has been researched. As with every `verify_at_load` entry, the rule set cannot be activated in production until it is checked.

The Ontario and British Columbia entries are `status: secondary` until an employment lawyer confirms them.

Until each province is confirmed, a decision that carries `COMMON_LAW_REVIEW` or `RULE_NOT_VERIFIED` is not decided until HR acknowledges the caution `benefits.common_law_notice` and writes a reason; the database refuses it otherwise (owner's decision, 28 October 2026, `docs/26` §7.2).

Templates for the common rules are in `rules/benefits/benefit-change-rule-templates.json`. A tenant starts from them and changes anything it needs.

### 6.4 Worked outcomes (cases BEN-001 to BEN-009)

Jordan's A2 ends on 2027-03-15. A1 continues at 0.6 FTE. The employer health plan needs 0.75 FTE.

| Case | Situation | Outcome |
| --- | --- | --- |
| BEN-001 | She resigns from A2 | Rule R10: coverage continues until 2027-03-31 |
| BEN-002 | A2 is eliminated in Ontario, with 4 weeks' notice owed | The R20 date of 03-31 is raised to the floor: **2027-04-12** (`STATUTORY_FLOOR`), and conversion is offered |
| BEN-003 | The same in British Columbia | 2027-03-31, with a `COMMON_LAW_REVIEW` warning |
| BEN-004 | The PT union trust plan, through A2 | Rule R05: end of next month, 2027-04-30 |
| BEN-005 | Reason category `other` | `hr_decides` by rule R90 |
| BEN-006 | No rule matches | `hr_decides` (`NO_MATCHING_RULE`) |
| BEN-007 | 0.9 FTE remains | `no_change` |
| BEN-008 | Manitoba, rule not yet verified | 2027-03-31, with `RULE_NOT_VERIFIED` |
| BEN-009 | Dismissal for cause from one position | Coverage ends on 2027-03-15 |

### 6.5 Everything else when one position ends

`docs/17` §4.4 still applies: the position is vacated, the schedule closes, the leave plan settles, seniority follows the agreement, dues stop, funding ends, access is revoked, and ROE and statutory notice are handled as described there. Two additions:

- The end proposes the benefit change decisions (§6.2) in the same change set. The change set cannot be committed while any decision for an affected enrolment is still `hr_decides`.
- Approval coverage rows where the ending assignment is the approver end on the same date. Pending parts addressed to it are cancelled and re-created for the new approvers.

---

## 7. Surveys and analytics

- **Survey pseudonyms.** A pseudonym is kept per survey per assignment (`comp.survey_pseudonym`, corrected in migration 0005). A person in two matched positions appears as two incumbents, as surveys expect, and the two rows cannot be linked to each other.
- **Headcount and FTE.** Reports count people and positions separately (`requirements/12`). A person in two positions is one head and the sum of FTEs. Workload and turnover per position count assignments.

---

## 8. Data model (migration 0006)

| Table or change | Purpose |
| --- | --- |
| `core.end_reason` | The tenant's end reasons, with category and employer-initiated; `assignment_version.end_reason` references it |
| `core.approval_policy` | Mode, overlap and uncovered setting per position or assignment and capability; one at a time |
| `core.approval_coverage` | Days, time windows and locations each approver covers; windows validated |
| `core.approval_part` | One part of a split request: approvers, rule, minutes and decisions. Status is computed, decisions are append-only, and self-approval is refused |
| `timeleave.leave_request_component.status` | Adds `partially_approved`; components and requests roll up from parts |
| `payroll.duty`, `core.assignment_pay_item`, `timeleave.time_line.duty_code` | Pay items and duty rates per position |
| `payroll.one_time_item.assignment_id`, `.allocation` | One-time payments per position, or shared by earnings |
| `talent.review` (`overall_method`, `overall_score`, `min_section_days`), `talent.review_section`, `talent.review_overall()` | Review sections and overall rating |
| `talent.competency_assessment` (`assignment_id`, `review_section_id`), `talent.competency_gap()` | Assessments in a position and gaps that prefer them |
| `comp.cycle.merit_rating_source` | Merit by section rating (default) or overall rating |
| `benefits.plan` (`eligibility_scope`, `agreement_id`), `benefits.enrolment` (`via_assignment_id`, `cob_rank`) | Plans per agreement or position; coordination of benefits |
| `benefits.change_rule`, `benefits.change_decision` | The organization's rules and the decisions, with the statutory floor and reasons enforced |

Every new table has `tenant_id` with forced row-level security.

---

## 9. API

The operations are in `api/openapi-several-positions.yaml`:

- **Approvals.** Set and read approval policies and coverage. Preview a split for a person and period.
- **Approval parts.** List the parts of a request, decide a part, cancel a part, and list the approver's inbox.
- **Duties and pay items.** Manage duties, and set and list pay items per assignment.
- **Reviews.** Open the review sections for an employment and cycle, rate a section, and read the overall rating.
- **Benefit changes.** Manage end reasons and benefit-change rules. Preview the benefit decisions for an assignment end, and decide one.

Every write goes through a change set (`docs/03`), except decisions on approval parts and benefit-change decisions, which are workflow actions with their own audit.

---

## 10. Events

| Event | When |
| --- | --- |
| `approval_part.created` | A request is split; one event per part, to its approvers |
| `approval_part.decided` | A part is approved or declined; the requester is notified with the roll-up |
| `approval_part.cancelled` | The requester cancels a part, or a schedule change re-routes it |
| `leave_request.partially_approved` | The roll-up reaches `partially_approved`; the employee is asked to keep or cancel |
| `assignment_pay_item.changed` | A pay item starts, changes or ends; payroll preview refreshed |
| `review_section.submitted` | A section is rated; the overall rating is recomputed |
| `benefits.change_decision.proposed` | An assignment end produces a decision; `hr_decides` decisions open an HR task |
| `benefits.change_decision.decided` / `.applied` | HR decides; the enrolment change is applied and sent to the carrier |

---

## 11. Acceptance scenarios

| ID | Scenario | Expected | Check | Step |
| --- | --- | --- | --- | --- |
| MP-001 | Leave over two positions on different days | Two parts to two managers | SPLIT-001, smoke 4 | 11 |
| MP-002 | Two positions on the same day | Split by hours | SPLIT-002 | 11 |
| MP-003 | One position, two managers by days | Each manager gets their days | SPLIT-003, smoke 3 | 11 |
| MP-004 | Policy `all` / `any` | One part, both must approve / either decides | SPLIT-004/005, STATUS-*, smoke 5 | 11 |
| MP-005 | Hours nobody covers | Line manager, or HR if so configured | SPLIT-006 | 11 |
| MP-006 | Overlapping time windows | Overlap goes to both | SPLIT-007 | 11 |
| MP-007 | Casual position without a schedule | Skipped with `NOT_SCHEDULED` | SPLIT-008 | 11 |
| MP-008 | Unpaid break, overnight shift | Prorated; start day decides | SPLIT-009/010 | 11 |
| MP-009 | Requester is the manager of her other position | Escalated; database refuses self-approval | SPLIT-011, smoke 4a | 4 |
| MP-010 | One manager declines, the other approves | `partially_approved`; employee keeps or cancels | STATUS-002, smoke 4d–4f | 11 |
| MP-011 | Car allowance on one position, driving rate on the other | Paid only with that position's earnings and hours | smoke 6–7 | 9 |
| MP-012 | Award with no position named | Shared by earnings to the cent | ALLOC-001/002 | 9 |
| MP-013 | Stipend paid from a separate grant | Costed to its own funding lines | — | 12 |
| MP-014 | One review, two managers | Two sections, overall by FTE × days | RATING-001–004, smoke 8 | 17 |
| MP-015 | Competency gap per position | Uses the same position's assessment first | smoke 9 | 17 |
| MP-016 | Two unions with two health plans | Enrolled in both; HR sets which pays first, with a reason, beside any order the trust contract sets (`docs/26` §5.2) | COB-001/002, smoke 10; `docs/26` BEN-030 | 15 |
| MP-017 | Resigns one position | The organization's rule applies | BEN-001 | 16 |
| MP-018 | Position eliminated in Ontario with notice owed | Never below the statutory floor | BEN-002, smoke 11b | 16 |
| MP-019 | No rule matches | HR decides with a written reason | BEN-005/006, smoke 11 | 16 |
| MP-020 | Two survey matches | Two pseudonyms that cannot be linked | `schema_0005_smoke` 21 | 15 |

---

## 12. Changes to other documents

| Document | Change |
| --- | --- |
| `docs/17` §5.2 | Rule 2 is refined by §2–§3: components are split into parts by manager coverage |
| `docs/17` §4.3 "Performance review" row | One review per employment with a section per assignment (§5.2) |
| `docs/17` §4.4 | Benefits row: decided by §6.2 |
| `docs/19` §6.3, §10.2, TR-028 | The pseudonym is per assignment (§7) |
| `requirements/03` | Pay items, duty rates and one-time allocation per position |
| `requirements/05` | Plan scope, enrolment per agreement, coordination of benefits, change rules and decisions |
| `requirements/06` | Approval by coverage, split to the minute, partial approval |
| `requirements/07` | Review sections, overall method, competency assessments per position |
| `AGENTS.md` | Reading order; rules 37–38; Steps 1, 9, 11, 15, 16, 17 |
| `docs/16` | Questions Q33–Q37 (SP1–SP5 below), one adopted design decision and one item to verify |

---

## 13. Open questions

| # | Question | Default until decided |
| --- | --- | --- |
| SP1 | Should an `any` part let a second manager reverse the first manager's decision? | No. Decisions are final; the employee resubmits |
| SP2 | Deadline before an undecided part goes to the approver's own manager | 3 working days, per tenant |
| SP3 | Should the overall rating use FTE × days, or scheduled hours in the cycle? | FTE × days |
| SP4 | Benefits during notice outside Ontario | `not_explicit` with `COMMON_LAW_REVIEW`; the decision stops for the caution `benefits.common_law_notice` and a reason (`docs/26` §7.2); lawyer review per province before Step 16 |
| SP5 | ~~Coordination of benefits when one plan is a union trust plan with its own rules~~ **Decided (28 Oct 2026):** HR decides, with the contract's order shown (`docs/26` §5.2) | — |

---

## Sources

- Ontario, Your guide to the Employment Standards Act: termination of employment (benefits continued during the statutory notice period): https://www.ontario.ca/document/your-guide-employment-standards-act-0/termination-employment
- HR Reporter, How to handle benefits during the notice period: https://www.hrreporter.com/focus-areas/compensation-and-benefits/how-to-handle-benefits-during-the-notice-period/393390
- HR Insider forum, Benefits extension during the statutory notice period (practice outside Ontario): https://hrinsider.ca/forums/topic/benefits-extension-during-stat-notice-period/
- Miller Thomson, Termination clauses and continuation of benefits in Ontario: https://millerthomson.com/fr/perspectives-juridiques/communique-droit-du-travail-et-de-lemploi-1-fr/termination-clauses-and-continuation-of
