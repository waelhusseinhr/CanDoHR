# Stories · 13 Compliance, Labour Relations & Privacy

Requirements: `requirements/13-compliance-labour-relations-privacy.md`. Design: `docs/08`, `docs/10`, `docs/34`.

> **Decisions:** `docs/34-compliance-labour-relations-privacy-decisions.md`, migration `schema/0020_compliance_labour_relations_privacy_decisions.sql`, smoke test `tests/schema/schema_0020_smoke.sql`. Existing stories below are annotated with their docs/34 section; new stories cover entities the requirements' data model calls for that had no acceptance criteria yet but are now built.

## Agreement library

> **Already built** (migration 0003, `docs/08`), before any module review began.

**LR-001 — Import an agreement.** AC: upload or registry fetch stores the PDF, SHA-256 hash and registry reference. The agreement record links bargaining units and legal entities.

**LR-002 — Extract rules with citations.** AC: the assistant proposes rules in `agreement.schema.json` shape, each with the article and quote, marked `extracted_by: ai, verified: false`. The example file `rules/agreements/example-municipal-agreement.json` validates against the schema.

**LR-003 — Verify before activation.** AC: activation is blocked while any rule is unverified (`422 UNVERIFIED_RULES`). Verification shows the clause side by side, records the verifier, and activation needs two people.

**LR-004 — Renewal diff.** AC: a new version copies the previous one. The diff view lists changed rules, and only changed rules need re-verification.

**LR-005 — Activation with retro.** AC: activating a version with `retro_from` creates retro requests (PAY-021) and grid rate changes, previewed with total cost before approval.

**LR-006 — Sandbox test of rule changes.** AC: before activation, a simulation over a sample of employees and periods shows old versus new results per employee and the total cost (`docs/08` §6).

**LR-007 — Explicit pay composition.** As a labour relations specialist, I want every combination of overtime, holiday and premium spelled out and cited before an agreement goes live, so that pay never depends on a developer's guess.
- AC1: Every case in `tests/agreements/stacking_cases.json` passes in the TypeScript engine with the same totals, lines and multipliers as `reference/premium_stacking_reference.py`.
- AC2: Given a version without `default_resolution` and without a rule for holiday + weekly overtime, then verification lists `UNRESOLVED_INTERACTION weekly+holiday` and activation is refused (`422`).
- AC3: Given a premium marked `in_regular_rate` but `flat` on overtime, then verification fails with `INCONSISTENT_INTERACTION`.
- AC4: The verification screen shows each open combination in plain language ("A holiday that is also a second rest day: which rate applies?") with the clause search, and records the specialist's answer with its article.
- AC5: Each pay line's explanation shows its rule path with article numbers.

## Rules repository and compliance calendar (docs/34 §3, §4)

**COMPL-010 — Seeded rules need the organization's own review before they go active.** As a compliance owner, I want a CanDo starter rule to stay a draft until my organization has reviewed it, so that nothing goes live on CanDo's say alone.
- AC1: A tenant creation seeds one `compliance.rule` row per CanDo-verified `ref.rule_starter` row, as `status = 'draft'` and `verification = 'verify_at_load'`, regardless of CanDo's own verification state.
- AC2: Setting `status = 'active'` with no `owner_user_id` recorded is refused (`rule_active_needs_owner_and_review`).
- AC3: Setting `status = 'active'` with an owner but `verification` still `verify_at_load` is refused.
- AC4: Setting `status = 'active'` with both an owner and `verification = 'organization_verified'` succeeds.

**COMPL-011 — Obligations register and reminders.** AC: an obligation records its owner, due date and recurrence; `compliance.obligation_reminder_days` (default 30) controls how far ahead its owner is reminded; waiving it requires a reason.

## Policy library and inspections (docs/34 §5, §6)

**COMPL-012 — Policy acknowledgement.** AC: a policy requiring acknowledgement records at most one acknowledgement per employment per policy (`UNIQUE (policy_id, employment_id)`); a second attempt is refused.

**COMPL-013 — Inspection record.** AC: an inspection logs its regulator, category, findings and whether an order is still outstanding, closed only when resolved.

## Human rights, accommodation and return to work

**EQ-002 — Accommodation cases.** AC: accommodation cases restrict medical details to designated HR roles. Managers see only functional limitations and agreed measures, and the attendance program excludes related absences (TIME-009). *(docs/34 §7, §13: every view of a case is logged to `compliance.case_view_log`.)*

**EQ-003 — No one approves their own accommodation outcome.** As HR, I want an accommodation decision to go through the organization's route, so that neither the case owner nor the employee it concerns can approve it themselves.
- AC1: An `accommodation_outcome` approval task decided by the case's `case_owner_user_id` is refused with `SELF_APPROVAL`.
- AC2: An `accommodation_outcome` approval task decided by the app_user linked to the case's employee is refused with `SELF_APPROVAL`.
- AC3: Decided by anyone else succeeds.

**COMPL-014 — Return-to-work plan linked to either source.** AC: an RTW plan names its source as an accommodation case or a WCB claim (`source_type`), never both and never neither, with a weekly plan of hours and duties.

## Occupational health and safety (docs/34 §8)

**HS-001 — Incident and WCB claim tracking.** AC: workplace incidents record the facts, notifications and deadlines per board. Lost-time claims link to time and payroll for top-up rules.

**HS-002 — One incident register for injuries and hazards.** AC: `compliance.incident.kind` distinguishes an injury, near miss, property damage, hazard observation or violence incident; a hazard observation names no employment; a critical injury sets `is_critical_injury` for the jurisdiction's immediate-notification duty.

**HS-003 — Joint health and safety committee.** AC: a committee records its worker and employer members and keeps its meeting log (minutes, attendees, action items) inline, read as a timeline per committee.

**HS-004 — SDS register.** AC: a safety data sheet names its product, manufacturer, revision date and the locations where it must be accessible, pointing at the actual document.

**HS-005 — Work refusal.** AC: a work refusal records the supervisor's and committee member's investigation and its outcome, including a case where the regulator is called in to rule.

## Harassment, violence, investigations, discipline and speak-up (docs/34 §9)

**COMPL-015 — Investigation case.** AC: an investigation records its category, respondent, investigator, allegations, findings and outcome; a complainant may be anonymous or absent (speak-up-originated).

**COMPL-016 — Discipline stays apart from performance.** AC: `compliance.discipline_record` is written independently of any `talent` performance table; a discipline record may link back to the investigation and the grievance it produced, never to a performance review.

**COMPL-017 — In-house speak-up channel with identity consistency.** As a compliance owner, I want the speak-up channel to be CanDo's own, so case management stays in one system.
- AC1: A non-anonymous speak-up report with no reporter named is refused (`speakup_identity_consistent`).
- AC2: An anonymous report is accepted with no reporter named, identified only by its `case_token`.
- AC3: `compliance.speakup_ack_hours` (default 48) governs when an unacknowledged report is flagged overdue.
- AC4: Messages on a report are addressed by side (`reporter` or `organization`), never by identity, when the report is anonymous.

## Labour relations (docs/34 §10)

**LR-010 — Grievance tracking.** AC: grievances record the article, step deadlines from the agreement, meetings, outcomes and linked documents. Step deadlines alert before expiry, and the case is restricted to LR roles. *(Steps and arbitration detail live as structured fields on `compliance.grievance`, read as a case file.)*

**LR-011 — Essential services.** AC: designated essential positions and staffing levels are stored per agreement, and schedules during a strike check them (Module 06).

**LR-012 — No one approves their own grievance settlement.** As labour relations, I want a settlement to go through the organization's route, so that the officer who proposed it cannot approve it herself.
- AC1: A `grievance_settlement` approval task decided by the grievance's `settlement_proposed_by` is refused with `SELF_APPROVAL`.
- AC2: Decided by anyone else succeeds.

**LR-013 — Bargaining proposals never change pay by themselves.** AC: a `compliance.bargaining_proposal` records a tabled article, side and estimated cost impact; only a ratified `core.agreement_version` ever changes what is actually paid.

## Employment equity (docs/34 §11)

**EQ-001 — Employment equity data.** AC: voluntary self-identification is collected with consent text versions, stored separately and encrypted, and reported only in aggregate with suppression. *(Reuses `privacy.min_group_size_self_id`, 10, never a third suppression mechanism.)*

## Privacy and records (docs/34 §12)

**PRIV-001 — Access requests.** AC: an employee's access request creates a case with a statutory due date by jurisdiction, assembles an export of their data within scope, supports redaction, and logs delivery. *(The due date is read from `compliance.rule`, not a hard-coded default — rule 43.)*

**PRIV-002 — Retention and legal hold.** AC: a nightly job identifies records past retention by class and jurisdiction, excludes legal holds, and destroys or anonymizes them with a destruction log. Payroll records are kept at least 6 years after the end of the tax year.

**PRIV-003 — Quebec Law 25.** AC: enabling a feature that moves Quebec employees' personal information outside Quebec requires a recorded privacy impact assessment. Confidentiality incidents are logged in the register.

**PRIV-004 — OCAP® option.** AC: a First Nations tenant can choose a dedicated database, and grant and revoke CanDo support access. The tenant can export all its data in open formats on request. *(Already built, migration 0008; Indigenous data governance beyond this option stays an open question — docs/34 §16.)*

**PRIV-005 — A cross-border feature needs an approved PIA before it can go live.** As the privacy officer, I want a feature that moves data outside Canada to be blocked from going live until its privacy impact assessment is approved.
- AC1: Setting `compliance.cross_border_feature.status = 'live'` with no `pia_id` is refused (`cross_border_needs_approved_pia`).
- AC2: Setting it `live` with a `pia_id` whose PIA is not yet approved still succeeds at the database layer (the constraint only requires a `pia_id` to be present) but the API layer blocks it until `compliance.pia.status = 'approved'` — tested at the API level, not the schema level, since the schema's own check is deliberately on presence, not approval status, to keep the constraint simple and the approval workflow the API's job.
- AC3: Once the PIA is approved, setting the feature live succeeds.

## Equity, accessibility, health and safety

**COMPL-001 — Compliance calendar.** AC: filing and remittance deadlines (CRA remittances, T4 by the end of February, EHT returns, WCB statements, pay transparency reports, equity reports) appear on one calendar per entity, with owners and reminders.

## Case view logging (docs/34 §13)

**COMPL-018 — Every sensitive case view is logged.** AC: viewing an accommodation case, an RTW plan, an investigation, a speak-up report, a grievance, a WCB claim or a discipline record writes a row to `compliance.case_view_log` with the viewer and the time, the same pattern `talent.succession_view_log` already applies to succession data.
