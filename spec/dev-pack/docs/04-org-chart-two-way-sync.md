# 04 · Org chart and employee data: two-way sync

**Requirement from the owner:** "If I move the organization chart, this will be reflected in the data of employees, and vice versa."

**How CanDo meets it:** the org chart is not a separate drawing. It is a live view of the same effective-dated records that the employee profile, position list, payroll and budgets read. Dragging a card on the chart creates a change set. Editing a profile creates a change set. Both go through one write path (`03` §4), so neither can drift from the other.

## 1. What the chart is made of

| Chart element | Source records (as of the chosen date) |
| --- | --- |
| Box for a position | `position_version`: title from job, org unit, location, FTE budget, status |
| Person inside the box | Current assignment(s) holding the position, with acting and overlap holders |
| Vacant box | Position with FTE budget not filled on the date |
| Line between boxes | `position.reports_to_position_id` (position mode) or `assignment.manager_assignment_id` (light mode) |
| Dotted line | Matrix or functional relationship (`assignment_relationship` with type `dotted`) |
| Group frame | Org unit and its subtree |
| Badges | Agreement, language requirement, funding end date, upcoming change, vacancy age |

The chart API (`GET /org-chart?asOf=&rootId=&depth=&mode=position|person`) returns nodes and edges computed by query, never from a cached copy. Large tenants load subtrees on demand.

## 2. Moving things on the chart

When the user drops something, CanDo works out what the move means and asks only when it is ambiguous.

| User action | Meaning CanDo proposes | Operations in the change set |
| --- | --- | --- |
| Drag a **position box** under another position | Restructure: the position and everyone below it now report to the new parent | `position.update { reportsToPositionId }` |
| Drag an **org unit frame** under another unit | Reorganization of the unit and its subtree | `org_unit.move` (positions keep their unit) |
| Drag a **person** onto a **vacant position** | Transfer the person into that position | `assignment.update { positionId, orgUnitId, locationId? }` (and a backfill vacancy appears on the old position) |
| Drag a **person** onto **another manager's box** (position mode) | Ambiguous. Ask: (a) move their position under that manager, (b) move them into a vacant position on that team, (c) create a new position on that team for them, (d) only change who they report to as a temporary arrangement (acting or matrix) | (a) `position.update`; (b) `assignment.update`; (c) `position.create` + `assignment.update`; (d) `assignment_relationship.create` with an end date |
| Drag a **person** onto a manager (light mode) | Change their manager | `assignment.update { managerAssignmentId }` |
| Click **+** on a box | Add a vacant position under it | `position.create` (budget and approval rules apply) |
| Mark a box **acting** | Acting assignment with dates | `assignment.create { type: acting, end }` |
| Multi-select and drag | Mass transfer | One change set with many operations |

Every action is also available without a mouse: select a card, press `M` (or "Move to…" in the card menu), search for the target, and confirm. Screen readers announce the tree structure, and the move dialog works fully by keyboard.

## 3. The move dialog (before anything is saved)

1. **Effective date:** defaults to the start of the next pay period. The user can choose today, a future date, or a past date (past dates show a retro warning).
2. **Reason code:** for example reorganization, promotion, lateral transfer or correction.
3. **Consequences**, computed by the cascade in preview mode (`05` §3) and shown as a checklist:
   - Department, cost centre and GL distribution change
   - Work location change, and with it province or territory, which changes income tax province, employment standards, statutory holidays and EHT allocation
   - Bargaining unit or agreement change, with seniority and grid-step implications and a flag for labour relations review
   - New approver for time, leave and expenses, with open requests rerouted
   - Benefits eligibility class change
   - Budget impact on both units for the current fiscal year
   - Pending future-dated changes that conflict
   - Retro pay estimate, when the date is in the past
4. **Approval route:** who has to approve, based on the workflow rules.
5. **Save as draft, add to a plan, or submit.**

Nothing on the chart changes for other users until the change set is approved and committed. The user's own view shows the draft in a dashed style.

## 4. The other direction: edits elsewhere update the chart

Every other screen writes through the same change-set service, so the chart reflects the result automatically.

| Edit made in | Example | What the chart shows |
| --- | --- | --- |
| Employee profile, Job tab | Manager changed from Ben to Chloe from 1 Dec | From 1 Dec, the person appears under Chloe. As of today, the chart shows a "moving 1 Dec" badge. |
| Position screen | Position eliminated from 31 Jan | From 31 Jan, the box disappears. Before then it shows an "ending 31 Jan" badge. |
| Recruitment (Module 02) | Hire approved into a vacant position, start 5 Jan | From 5 Jan, the vacant box becomes filled. Until then it shows "hire starting 5 Jan". |
| Offboarding (Module 11) | Termination effective 15 Nov | From 15 Nov, the box becomes vacant, and a backfill prompt goes to the manager. |
| Compensation (Module 04) | Promotion to a new job in the same position | The title updates from the effective date. |
| Import or API | Bulk reorganization file | Same as a mass move, with one change set and one approval. |
| Agreement library (Module 13) | Unit decertified or merged | Agreement badges update from the effective date. |

When a change set commits, the outbox emits `org.changed` with the affected units and dates. Every open chart showing those units refreshes within a second, without a page reload.

## 5. Time travel and planning

- **Date slider:** shows the organization as of any date, past or future. Future-dated approved changes are already visible on future dates.
- **Compare:** shows two dates side by side, or "today vs plan", with moved, added and removed boxes highlighted, plus headcount and cost differences.
- **Plans (what-if scenarios):** a plan is a named collection of draft change sets that only the plan's members can see. People can model a reorganization on the chart, see total cost and headcount by unit, share it for comments, and then submit the whole plan for approval as one batch. Plans never affect live data until approved. Module 09 (workforce planning) uses the same mechanism.
- **History:** shows every change to a box (who, when, why) through its change sets.

## 6. Permissions

| Role | On the chart |
| --- | --- |
| Employee | View the published chart (directory fields only). Cannot move. |
| Manager | View their subtree with work fields. Propose moves within their subtree; HR approves. |
| HRBP | Propose and approve within assigned units, per workflow |
| HR administrator | Any move, any date, plans, corrections |
| Finance | View budget and cost overlays |
| Auditor | Read-only, including history and `knownAt` views |

Confidential positions (for example an investigation unit) can be hidden from the published chart and shown only to roles with the right scope.

## 7. Performance and scale

- Position mode builds the tree with a recursive query on `position_version` as of the date. An index on `(tenant_id, reports_to_position_id)` over current rows keeps this fast.
- Over 5,000 nodes, the client loads collapsed subtrees and expands on demand. The layout runs in a Web Worker.
- A move of a unit with 3,000 people is one operation (`org_unit.move` or `position.update` on the head position). It does not touch 3,000 assignments, because their reporting line is derived.

## 8. Acceptance tests (must pass)

1. Drag Ana's position under Chloe effective next Monday → Ana's profile shows manager Chloe from Monday; the chart as of today still shows Ben; the chart as of Monday shows Chloe; Ana's timesheets dated from Monday route to Chloe.
2. Change Ana's manager on her profile → the chart moves her card after commit, and other open browser sessions update without reload.
3. Move a department to a unit in another province, with a past effective date that falls in a finalized pay period → the dialog shows the tax-province change and a retro estimate; after approval, a retro request exists for each affected employee.
4. Drag two people at once onto one vacant position with FTE budget 1.0 → validation error for over-filling unless an overlap with an end date is approved.
5. Create a plan with five moves → live chart unchanged; plan view shows the moves and cost difference; approving the plan commits five operations in one change set.
6. Keyboard only: move a position using "Move to…" and confirm → same result as drag and drop.
7. Conflict: a future raise exists for 1 Jan; a transfer is made effective 1 Dec → the raise is kept and still applies from 1 Jan, with the new org unit.
