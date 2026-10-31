# Stories · 13 Compliance, Labour Relations & Privacy

Requirements: `requirements/13-compliance-labour-relations-privacy.md`. Design: `docs/08`, `docs/10`.

## Agreement library

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

## Labour relations

**LR-010 — Grievance tracking.** AC: grievances record the article, step deadlines from the agreement, meetings, outcomes and linked documents. Step deadlines alert before expiry, and the case is restricted to LR roles.

**LR-011 — Essential services.** AC: designated essential positions and staffing levels are stored per agreement, and schedules during a strike check them (Module 06).

## Privacy and records

**PRIV-001 — Access requests.** AC: an employee's access request creates a case with a statutory due date by jurisdiction, assembles an export of their data within scope, supports redaction, and logs delivery.

**PRIV-002 — Retention and legal hold.** AC: a nightly job identifies records past retention by class and jurisdiction, excludes legal holds, and destroys or anonymizes them with a destruction log. Payroll records are kept at least 6 years after the end of the tax year.

**PRIV-003 — Quebec Law 25.** AC: enabling a feature that moves Quebec employees' personal information outside Quebec requires a recorded privacy impact assessment. Confidentiality incidents are logged in the register.

**PRIV-004 — OCAP® option.** AC: a First Nations tenant can choose a dedicated database, and grant and revoke CanDo support access. The tenant can export all its data in open formats on request.

## Equity, accessibility, health and safety

**EQ-001 — Employment equity data.** AC: voluntary self-identification is collected with consent text versions, stored separately and encrypted, and reported only in aggregate with suppression.

**EQ-002 — Accommodation cases.** AC: accommodation cases restrict medical details to designated HR roles. Managers see only functional limitations and agreed measures, and the attendance program excludes related absences (TIME-009).

**HS-001 — Incident and WCB claim tracking.** AC: workplace incidents record the facts, notifications and deadlines per board. Lost-time claims link to time and payroll for top-up rules.

**COMPL-001 — Compliance calendar.** AC: filing and remittance deadlines (CRA remittances, T4 by the end of February, EHT returns, WCB statements, pay transparency reports, equity reports) appear on one calendar per entity, with owners and reminders.
