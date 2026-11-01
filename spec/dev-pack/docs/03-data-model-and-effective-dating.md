# 03 · Data model, effective dating and change sets

This is the foundation everything else depends on. Build it first and test it hardest.

## 1. Two kinds of time

Every business fact carries two time ranges.

| Range | Column | Meaning | Example |
| --- | --- | --- | --- |
| Valid time | `valid_period daterange` | When the fact is true in the real world. Inclusive start, exclusive end, `[2026-04-01, infinity)` | Salary $72,000 from 1 April |
| System time | `sys_period tstzrange` | When CanDo held this row as current knowledge | Entered on 20 March at 10:02, still current |

With both, CanDo answers two different questions:

- **"What was true on date X?"** Filter on valid time, using rows current in system time. This drives the org chart as of a date, headcount reports and payroll ("should have been paid").
- **"What did CanDo say on date Y about date X?"** Filter on both. This drives audits and retro pay ("was paid, based on what we knew then").

Dates are calendar dates in the legal entity's time zone. Timestamps are UTC.

## 2. Table pattern

Each effective-dated entity has a stable identity table and a version table.

```sql
-- identity: never changes, referenced by foreign keys
CREATE TABLE core.assignment (
  tenant_id     uuid NOT NULL,
  assignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment(employment_id),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- versions: one row per (valid period × system period)
CREATE TABLE core.assignment_version (
  tenant_id      uuid NOT NULL,
  version_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  assignment_id  uuid NOT NULL REFERENCES core.assignment(assignment_id),
  valid_period   daterange NOT NULL,
  sys_period     tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id  uuid NOT NULL,
  -- business attributes
  position_id    uuid, org_unit_id uuid NOT NULL, location_id uuid NOT NULL,
  manager_assignment_id uuid, fte numeric(5,4) NOT NULL, pay_group_id uuid,
  agreement_id   text, is_primary boolean NOT NULL,
  -- one current row per assignment per day
  EXCLUDE USING gist (assignment_id WITH =, valid_period WITH &&)
    WHERE (upper_inf(sys_period))
);
```

Rules:

1. Rows are never updated in place, apart from closing `sys_period` when a row is superseded.
2. For any entity and any day there is exactly one current row. The exclusion constraint enforces it.
3. Gaps are allowed only where the entity does not exist (before hire, after termination).
4. Each version row records the `change_set_id` that produced it, so every value traces back to a person, a reason and an approval.

The full schema is in `schema/cando_schema.sql`.

## 3. Reading "as of"

Every read API accepts `asOf` (valid date, default today) and, for auditors, `knownAt` (system timestamp, default now).

```sql
SELECT * FROM core.assignment_version
WHERE assignment_id = $1
  AND valid_period @> $asOf::date
  AND sys_period   @> $knownAt::timestamptz;
```

Shared helper views expose `*_current` (as of today, current knowledge) for convenience. Lists, the org chart, reports and payroll all call the same helper functions, so "as of" means the same thing everywhere.

## 4. Change sets: the only write path

A change set is a proposal to change data, with one effective date, a reason, and one or more operations. Every write in CanDo goes through it: the org chart, forms, imports, mass changes, API calls and approved requests.

### Structure

```json
{
  "changeSetId": "0d6c…",
  "tenantId": "…",
  "kind": "transfer",
  "reasonCode": "REORG",
  "effectiveDate": "2026-11-01",
  "source": "org_chart",
  "requestedBy": "user:…",
  "operations": [
    { "op": "assignment.update", "assignmentId": "…", "set": { "orgUnitId": "…", "managerAssignmentId": "…" } },
    { "op": "position.update", "positionId": "…", "set": { "reportsToPositionId": "…" } }
  ],
  "baseVersions": { "assignment:…": 7, "position:…": 3 },
  "status": "draft"
}
```

### Operation catalogue (initial)

| Operation | Entity | Notes |
| --- | --- | --- |
| `person.create` / `person.update` | Person | Name, contact, language. Legal name and SIN need document evidence. |
| `employment.hire` / `employment.rehire` / `employment.terminate` | Employment | Hire creates an assignment too. Terminate closes every open assignment. |
| `assignment.create` / `assignment.update` / `assignment.end` | Assignment | Position, org unit, location, manager, FTE, pay group, agreement, primary flag |
| `position.create` / `position.update` / `position.freeze` / `position.eliminate` | Position | Reports-to position, FTE budget, funding, language requirement |
| `org_unit.create` / `org_unit.update` / `org_unit.move` / `org_unit.close` | OrgUnit | Moving a unit moves its subtree |
| `compensation.set_rate` | Pay rate | Grid step or salary; from Module 04 decisions or agreement progression |
| `agreement.activate_version` | Agreement | Loads a ratified rule version; may set `retro_from` |
| `time.correct` | Timesheet | Correction to a locked period, which triggers retro |
| `payroll_profile.update` | TD1, banking, tax province override, s.87 status | Banking changes need verification and dual control |

Modules add their own operations, such as `benefits.enrol` or `leave.approve`, through the same mechanism.

### Lifecycle

```
draft ──validate──► validated ──submit──► pending_approval ──approve──► approved
   │                    │                        │                         │
   └── discard          └── edit → draft         └── reject                ├─ effective date ≤ today → committed
                                                                           └─ effective date > today → scheduled ──(date arrives or immediately)──► committed
```

- **Validate** runs every operation against the rules (see section 6) and runs the cascade (`05-integration-and-events.md`) in preview mode. It returns errors (must fix), warnings (must acknowledge) and **consequences** (what else will change).
- **Approve** follows the workflow chosen by kind, amount, entity and bargaining unit. Self-approval is blocked.
- **Commit** happens in one transaction: version rows written, superseded rows closed in system time, audit entry, outbox events.
- **Scheduled** change sets are committed to the database immediately, because their valid time is in the future. "Scheduled" is a status for users, telling them it is not in force yet. Projections as of a later date already show it.

### Past, present and future effective dates

| Effective date | What happens on commit |
| --- | --- |
| Future | Rows written with future valid time. Future views of the org chart and payroll previews show the change. Notifications go out as configured. |
| Today | Takes effect immediately. |
| Past, no finalized pay since | Treated like today; payroll inputs for the open period pick it up. |
| Past, with finalized pay after it | A retro request is created for every affected employee and finalized period (`06-payroll-engine.md` §6). Approvers see the estimated retro amount before approving. |
| Before a closed tax year | Allowed only for HR history, never for payroll, unless a payroll administrator opens a prior-year adjustment with reason. |

### Corrections versus changes

- A **change** is a new real-world fact ("from 1 Nov, Ana reports to Ben"). It adds a version with a later valid time.
- A **correction** fixes a mistake ("Ana's salary was keyed as $27,000 instead of $72,000 since 1 April"). It supersedes the wrong row in system time and writes a corrected row with the same valid time. The audit shows both.

The UI asks which one the user means whenever an edit touches a date in the past.

### Future rows and conflicts

If a future-dated change exists (a raise on 1 January) and someone commits an earlier change (a transfer on 1 November), the 1 November change applies only until the next future version starts. Attributes it does not touch carry forward. The validator flags any future version that **conflicts** (the same attribute set differently) and asks the user to keep it, replace it or merge it. Never silently overwrite future data.

## 5. Core entities

| Entity | Effective-dated | Key attributes |
| --- | --- | --- |
| Tenant | No | Residency setting, languages, modules enabled |
| LegalEntity | Yes | BN, RP accounts, Revenu Québec number (phase 2), jurisdiction (federal or provincial), fiscal year start, WCB accounts |
| EmployerGroup | Yes | Associated employers for EHT and levy thresholds |
| Location | Yes | Address, province or territory, time zone, holiday calendar, northern zone, on-reserve flag |
| OrgUnit | Yes | Type (division, department, team), parent, manager position, cost centre, fund |
| Job | Yes | Code, titles EN/FR, family, level, grade, NOC 2021, overtime eligibility, bargaining unit default, pay equity class |
| Position | Yes | Number, job, org unit, location, reports-to position, FTE budget, funding lines, status, language requirement |
| Person | Yes (names, contacts) | Legal and preferred names, date of birth, SIN (encrypted), languages |
| Employment | Yes | Legal entity, hire date, service and seniority dates, employment type, status |
| Assignment | Yes | Employment, position (optional in light mode), org unit, location, manager, FTE, pay group, agreement, primary flag |
| PayRate | Yes | Assignment, basis (hourly, salary), amount, grid and step, source |
| PayrollProfile | Yes | Tax province (derived, can be overridden with reason), TD1 claims, s.87 status, CPP/EI exemptions, banking split |
| Agreement / AgreementVersion | Yes | Rule set per `rules/agreements/agreement.schema.json` |
| ChangeSet / Operation | No (append-only) | As above |
| AuditEntry | No (append-only) | Who, what, when, before, after, reason, IP, device; `leaf_hash` on insert, sealed hourly into an `AuditBatch` (`10` §5) |

### Two org modes

- **Position mode** (default for 50+ employees): reporting lines come from `position.reports_to_position_id`. The manager of an assignment is whoever holds the parent position as of the date, or the acting holder.
- **Light mode** (small employers): no positions. The reporting line is `assignment.manager_assignment_id`.

A tenant can switch from light to position mode at any time. A migration creates one position per assignment and preserves reporting lines.

## 6. Validation rules (run on every change set)

- Referential: everything referenced exists and is active on the effective date.
- Position control: FTE in use does not exceed the position budget unless an overlap is approved; frozen positions cannot be filled.
- Cycles: no reporting loops in positions or in light-mode managers.
- Jurisdiction: work location and legal entity give a valid employment standards jurisdiction (federal or provincial).
- Pay: rate at or above minimum wage for the location (`rules/employment-standards`); grid step exists in the agreement version in force.
- Agreement: bargaining unit matches the job and position, or the exclusion has a reason.
- Payroll safety: the effective date is not inside a pay period that is currently calculating. If it is, the user chooses to wait or to make it effective next period.
- Privacy: the requester may change every field touched (field-level permissions).
- Dates: valid ranges well-formed; no edits to closed tax years without the prior-year adjustment permission.

## 7. Identifiers

- UUID v7 for all new identities (time-ordered, index-friendly).
- Human-readable numbers (employee number, position number, change set number) are generated per tenant from sequences and are never reused.
- External references (IdP subject, ERP cost centre code, carrier member ID) live in `core.external_ref` keyed by system and type.
