# Stories · 00 Platform (shared services)

Format: each story has an ID, a statement and acceptance criteria (AC) written as Given / When / Then. Every story also meets the definition of done in `docs/14-testing-and-quality.md` §3.

## Change sets (the single write path)

**PLAT-001 — Create and validate a change set.** As an HR administrator, I want every edit to be a change set with an effective date, so that every screen stays consistent and every change is traceable.
- AC1: Given a draft with one `assignment.update` operation, when I call validate, then I receive `errors`, `warnings` and `consequences` arrays, and nothing is written to business tables.
- AC2: Given an operation that references a position that is frozen on the effective date, when I validate, then I receive error `POSITION_FROZEN`.
- AC3: Given a change set built on version 7 of an assignment that is now at version 8, when I submit, then I receive `409 VERSION_CONFLICT` with the current state.

**PLAT-002 — Commit atomically.** As a developer, I want a change set to commit in one transaction, so that partial updates can never happen.
- AC1: Given a change set with three operations where the third fails a database constraint, when commit runs, then no version rows, audit entries or outbox events are written.
- AC2: Given a successful commit, then each new version row carries the change set ID, superseded rows have a closed `sys_period`, one audit entry exists per operation, and one outbox event exists per affected subject.

**PLAT-003 — Change versus correction.** As an HR administrator, I want to choose whether a past-dated edit is a new change or a correction, so that history stays truthful.
- AC1: Given an edit with an effective date before today, when I open the form, then I must choose "New change" or "Correction".
- AC2: Given a correction, then the old row remains readable with `knownAt` before the correction, and the corrected row has the same valid time.

**PLAT-004 — Future-dated conflict handling.** As an HR administrator, I want to be warned when my change conflicts with an approved future change, so that I don't overwrite planned data.
- AC1: Given a raise effective 1 January exists, when I submit a transfer effective 1 December, then the raise remains and applies from 1 January with the new org unit, and no warning appears (different attributes).
- AC2: Given a rate change effective 1 January exists, when I submit a different rate effective 1 December, then validation returns warning `FUTURE_CONFLICT`, and I must choose keep, replace or merge.

**PLAT-005 — Approvals.** As an approver, I want change sets routed to me by kind, amount, unit and bargaining unit, so that the right people approve.
- AC1: Given a workflow requiring HRBP then Finance for transfers with a budget impact over $10,000, when such a change set is submitted, then approval tasks are created in that order.
- AC2: Given the requester is also in the approver list, then the requester's own step is skipped to the next eligible approver, and self-approval is impossible (`SELF_APPROVAL_BLOCKED`).
- AC3: Given an approver is on leave with a delegate, then the task goes to the delegate and the audit shows both.

## Identity, access, audit

**PLAT-010 — Tenant isolation.** As a security officer, I want tenant data isolated in the database, so that a bug cannot leak data across customers.
- AC1: `tests/schema/schema_smoke.sql` passes: other tenants see 0 rows and cross-tenant inserts are rejected.
- AC2: An integration test runs every list endpoint as tenant B against data for tenant A and receives empty results.

**PLAT-011 — Field-level permissions.** As an HR administrator, I want field classes enforced, so that managers cannot see SINs or home addresses.
- AC1: Given a manager reads a direct report's employment, then `personal` and `payroll restricted` fields are absent, not null-filled.
- AC2: Given a payroll administrator reveals a SIN with a reason, then the full SIN is returned once and an audit entry `sensitive.reveal` exists.

**PLAT-012 — Tamper-evident audit rows.** As an auditor, I want every audit row hashed on insert and impossible to change, so that I can trust the history.
- AC1: Every row stores `leaf_hash = SHA-256(0x00 ‖ canonical(row))` over the fields in `reference/audit_merkle_reference.py` `AUDIT_FIELDS`. The TypeScript hasher reproduces every `leaf_hashes` value in `tests/audit/merkle_vectors.json`.
- AC2: The application role cannot `UPDATE` or `DELETE` audit rows (permission error). Even a superuser cannot delete a row or change a sealed row (trigger `AUDIT_IMMUTABLE`, see `tests/schema/schema_smoke.sql`).
- AC3: Changing the IP address or user agent of a row (for example, redaction under a privacy request) does not change its `leaf_hash`.

**PLAT-014 — Hourly sealing and anchoring.** As a security officer, I want the audit log sealed into signed batches stored where nobody can alter them, so that even a database administrator cannot rewrite history unnoticed.
- AC1: Given unsealed rows for a tenant, when the hourly job runs, then they form batch *n* in `audit_id` order, with the RFC 6962 root and the chained `batch_hash` exactly as in `tests/audit/merkle_vectors.json`.
- AC2: Given a transaction still open while the job runs, then its row lands in the next batch, and no row is ever in two batches or none.
- AC3: Given a tenant with no activity for a day, then one empty batch (root = SHA-256 of nothing) is still sealed that day.
- AC4: The batch hash is signed with the KMS key and the record is written to the anchor bucket (separate AWS account, ca-west-1, Object Lock compliance mode); `anchor_uri`, `anchor_version_id` and `anchored_at` are filled once and cannot change.
- AC5: Given the anchor write fails, then the job retries with back-off and alerts after 3 hours without anchoring; the rows stay sealed and the next run anchors the pending batches in order.

**PLAT-015 — Verifier and inclusion proofs.** As an external auditor, I want to check the log myself, so that I do not have to trust CanDo.
- AC1: Given an intact log, then the verifier reports every batch valid: roots recomputed, chain unbroken, signatures and anchored copies matching.
- AC2: Given a test database where one row's `after` was edited directly, then the verifier names that batch and that row, and reports every other batch valid.
- AC3: Given a deleted row, then the verifier reports the gap in `audit_id` and the root mismatch for its batch.
- AC4: `GET /audit/entries/{id}/proof` returns the row's leaf hash, batch header, audit path, batch hash, signature and key ID. The open-source script in `reference/audit_merkle_reference.py` (`verify_inclusion`) accepts it using only the published public key.

**PLAT-016 — Customer-held digest.** As a customer's security contact, I want my own copy of the latest seal every day, so that I hold proof CanDo cannot change.
- AC1: Each day the last batch hash, batch number and signature are available in the admin portal and sent to the security contact; `customer_digest_sent_at` is recorded.
- AC2: Given an OCAP® or dedicated tenant with its own storage configured, then the digest is also written there, and the tenant has its own signing key and anchor bucket.
- AC3: Given a digest the customer kept from 30 days ago, when they run the verifier against today's log, then it confirms that batch is still in the chain.

**PLAT-013 — SSO and SCIM.** As an IT administrator, I want users created and disabled from our identity provider, so that access follows employment.
- AC1: Given an `employment.hired` event with a start date, then a SCIM user is created in the IdP at the configured lead time.
- AC2: Given `employment.terminated` with access removal at 17:00 on the last day, then the IdP user is disabled within 5 minutes of that time.

## Events, notifications, i18n, live updates

**PLAT-020 — Outbox delivery.** As a developer, I want reliable event delivery, so that modules stay in sync.
- AC1: Given a subscriber that fails twice and then succeeds, then it processes the event exactly once (idempotency table) and the event shows `published_at`.
- AC2: Given 10 consecutive failures, then the event appears in the dead-letter view and can be replayed.

**PLAT-021 — Live screen updates.** As a user, I want open screens to refresh when data changes, so that I never act on stale information.
- AC1: Given two browsers showing the same org unit, when a change set affecting it commits, then both refresh within 1 second without reload.
- AC2: Given a user without permission to a unit, then they receive no message about it.

**PLAT-022 — Bilingual everything.** As a French-speaking employee, I want the whole product in Canadian French, so that I can work in my language.
- AC1: A CI check fails if any UI string is missing in `fr-CA`.
- AC2: Given a user with locale `fr-CA`, then dates, numbers and currency use French Canadian formats (for example `1 234,56 $`).

**PLAT-023 — As-of date control.** As any user, I want to view any screen as of a date, so that I can see the past or a planned future.
- AC1: Given I set as-of to a future date, then every list, profile and chart shows data valid on that date, and a banner says so.
