# 05 · Integration fabric: cascade rules and events

CanDo stays consistent across 14 modules through three mechanisms, in this order of preference:

1. **Derive, don't copy.** If a value can be computed from records that already exist, compute it when it is read. Examples: an employee's manager (from the parent position), tax province (from work location unless overridden), holiday calendar (from location), employment standards jurisdiction (from legal entity and location), approver (from the reporting line on the date). Derived values can never be out of date.
2. **Cascade inside the change set.** When a change necessarily implies another change, the cascade adds the operation to the same change set, so both commit together or not at all. Example: ending the last assignment in a position marks the position vacant.
3. **React to events.** Work that belongs to another module, takes time, or needs a person happens after commit through outbox events. Examples: benefits eligibility re-evaluation, accrual recalculation, retro pay requests, IdP deprovisioning, notifications.

## 1. Event envelope

```json
{
  "eventId": "01JB…",
  "type": "assignment.changed",
  "version": 1,
  "tenantId": "…",
  "occurredAt": "2026-10-18T14:02:11Z",
  "effectiveDate": "2026-11-01",
  "changeSetId": "…",
  "subject": { "type": "assignment", "id": "…", "employmentId": "…", "personId": "…" },
  "changes": { "orgUnitId": { "from": "…", "to": "…" }, "locationId": { "from": "…", "to": "…" } },
  "derived": { "taxProvince": { "from": "ON", "to": "MB" } },
  "actor": { "type": "user", "id": "…" }
}
```

- Events carry identifiers and changed field names, plus before and after values for non-sensitive fields. Sensitive values (SIN, banking, salary) are never in the event body. Subscribers read them through the service API with their own permissions.
- Every subscriber records `eventId` in its own `processed_event` table and skips duplicates (idempotency).
- Events are ordered per subject. The relay delivers events for one subject in commit order.

## 2. Event catalogue

| Event | Emitted when | Main subscribers |
| --- | --- | --- |
| `person.created`, `person.updated` | Person data changes | Directory, IdP sync, Analytics |
| `employment.hired`, `employment.rehired` | Hire or rehire committed | Payroll (setup), Benefits (eligibility), Learning (onboarding plan), Onboarding tasks, IdP (provision), Time (schedule) |
| `employment.status_changed` | Probation passed, conversion, leave start or end | Benefits, Time, Performance, Payroll (ROE trigger on leave) |
| `employment.terminated` | Termination committed | Offboarding (tasks), Payroll (final pay, ROE), Benefits (coverage end), IdP (deprovision at time), Time (cancel future shifts) |
| `assignment.changed` | Any assignment field changes | Payroll (inputs), Time (approver, rules), Benefits (class), Analytics, Org chart push |
| `position.created`, `position.changed`, `position.vacated`, `position.eliminated` | Position changes | Recruitment (requisition prompts), Workforce planning, Org chart push, Offboarding (layoff notices when eliminated with incumbents) |
| `org.changed` | Units moved, created or closed; reporting lines changed | Org chart push, Workflow (reroute approvals), Analytics |
| `rate.changed` | Pay rate changes | Payroll, Compensation statements |
| `agreement.version_activated` | Ratified version loaded | Payroll (retro if `retro_from`), Time (rules), Benefits, Core HR (grid progression jobs) |
| `time.approved`, `time.corrected` | Timesheet approved, or a locked period corrected | Payroll (inputs, retro) |
| `leave.approved`, `leave.cancelled` | Leave decisions | Time (schedule), Payroll (valuation), Benefits (long leave) |
| `benefit.enrolled`, `benefit.ended` | Benefits changes | Payroll (deductions, taxable benefits) |
| `payrun.finalized`, `payment.released` | Payroll milestones | GL export, Remittances, Notifications, Analytics |
| `retro.requested`, `retro.calculated` | Retro lifecycle | Payroll workspace, Approvers |
| `rule_edition.loaded` | New statutory edition activated | Payroll (pre-run checks), Compliance dashboard |

The canonical machine-readable list is in `api/events.yaml`.

## 3. Cascade matrix

The cascade runs in **preview** during validation, so users see consequences before approving, and again for real at commit. Each row is a rule in `packages/changesets/cascade/`.

| When this changes | Derived at read time | Added to the same change set | After commit (events and jobs) |
| --- | --- | --- | --- |
| Assignment → position | Manager, org unit default, job, grade range | Old position vacated if no other holder; new position filled | Recruitment closes any open requisition on the new position; workforce plan updated |
| Assignment → org unit | Cost centre, approver chain | Reroute open time, leave and expense approvals | GL distribution from effective date; budget actuals move |
| Assignment → location | Province or territory, time zone, holiday calendar, ES jurisdiction, EHT and WCB allocation | Payroll profile tax province updated unless overridden; TD1 provincial form requested if the province changed | Payroll warns if mid-period; Time re-evaluates rules from the date; Benefits checks provincial plan rules |
| Assignment → agreement or bargaining unit | Grid, premiums, leave plan, dues | Rate mapped to the new grid (step chosen by rule, confirmation required) | Seniority record opened or closed per agreement; Labour relations task created |
| Assignment → FTE | Benefits class thresholds, accrual rate | — | Benefits eligibility re-evaluated; leave accruals prorated from the date |
| Position → reports-to | Manager for every holder and every descendant | — | Org chart push; approval reroute |
| Org unit → parent | Hierarchy for every descendant | — | Org chart push; security scopes recalculated |
| Employment → terminated | Status for all modules | All assignments ended; positions vacated; future change sets cancelled (listed for confirmation) | Final pay, ROE, coverage end, deprovisioning, exit survey, asset recovery |
| Pay rate (past date) | — | — | Retro request per finalized period affected |
| Agreement version with `retro_from` | — | — | Retro requests for everyone covered, created in batches |
| Timesheet correction (locked period) | — | — | Retro request for that period |
| Person → legal name | Display everywhere | — | IdP sync; T4 name updated for the current year only |

Rules for writing cascade rules:

- A cascade rule may add operations, warnings and tasks. It may not silently change something the user did not see. Every added operation appears in the consequences list.
- Cascade rules are pure functions of (current state as of the effective date, proposed operations) → (added operations, warnings, tasks). This makes them unit-testable without a database.
- Cascades must terminate. The engine runs to a fixed point and fails the validation if it exceeds 10 rounds.

## 4. Outbox and relay

```sql
CREATE TABLE platform.outbox (
  tenant_id   uuid NOT NULL,
  event_id    uuid PRIMARY KEY,
  subject_key text NOT NULL,          -- e.g. 'assignment:…' for per-subject ordering
  type        text NOT NULL,
  payload     jsonb NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz
);
```

- The change-set commit inserts outbox rows in the same transaction.
- The relay polls with `FOR UPDATE SKIP LOCKED` in `created_at` order, dispatches to in-process subscribers and to the webhook queue, then sets `published_at`.
- Failed subscriber handling retries with backoff. After 10 failures, the event goes to a dead-letter view that an admin can replay.

## 5. External webhooks

Customers subscribe to any event type. Payloads follow the envelope above. Deliveries are signed with HMAC-SHA256 (`X-CanDo-Signature`), carry a timestamp to prevent replay, and retry for 24 hours. Webhook payloads never include sensitive values. Receivers call the API for details.

## 6. Consistency checks (nightly)

A reconciliation job compares projections with the source records and raises data-quality issues instead of fixing them silently:

- Filled position counts versus assignments
- Payroll profile tax province versus location province (where there is no override)
- Open approvals whose approver is no longer in the reporting line
- Employees with an active assignment but no pay group
- Org units with no manager position
