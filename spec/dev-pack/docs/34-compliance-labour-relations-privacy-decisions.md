# Compliance, labour relations and privacy decisions

Date: 3 November 2026
Owner review: Module 13 (claude/review/13-compliance-labour-relations-privacy-decisions.md)
Schema: `schema/0020_compliance_labour_relations_privacy_decisions.sql`, smoke-tested by `tests/schema/schema_0020_smoke.sql`

This is the last of the thirteen module reviews (`docs/15` Step 18, completing it alongside `docs/33`). Where this document differs from `requirements/13-compliance-labour-relations-privacy.md`, `stories/13-compliance-labour-privacy.md`, or any other doc, this document wins on compliance, labour relations and privacy topics; `docs/22` still wins on values, fallbacks and languages, and `docs/21` still wins on self-identification and support access.

CanDo is not a law firm. Nothing in this module gives legal advice, and nothing here lets an AI feature interpret, summarize or draft an opinion on what a law or regulation requires (`compliance.rule_ai_interpretation_enabled`, locked off forever). CanDo states citations and a verified starting position; a person always draws the conclusion and decides what to do about it.

## 1. Decisions at a glance

| # | Question | Decision |
|---|---|---|
| 1 | Who owns the rules repository's currency? | CanDo seeds a starter/reference copy by jurisdiction; **the organization** owns keeping it current from there. CanDo never silently re-syncs a live tenant's rules. |
| 2 | Which jurisdictions at launch? | Every Canadian jurisdiction CanDo already supports for payroll and employment standards (the same federal and ten provincial/three territorial set); no new jurisdiction is added solely for this module. |
| 3 | A third-party speak-up/hotline partner? | No. Built in-house, in the same system as the rest of case management (requirements/13 "How CanDo compares"), not a bolted-on EHS or hotline product. |
| 4 | OHS scope vs. a separate EHS product? | Full in-house case management: incidents, hazards, WCB claims, the joint health and safety committee, the SDS register and work refusals, in the same system as investigations and grievances. |
| 5 | Indigenous data governance / OCAP? | Stays open. CanDo already supports an OCAP-aligned data residency and sovereignty option in Core HR (migration 0008); nothing new is built for OCAP in this module pending the owner's advisers. |
| 6 | What does "the organization owns the repository" mean mechanically? | A seeded rule starts as a tenant `draft` with `verification = 'verify_at_load'`; it can go `active` only once the organization records an owner and its own review (`rule_active_needs_owner_and_review`). |

## 2. Precedence and what was already decided

The owner's rules for this review (unchanged from prior modules): recommend first, ask only when a decision cannot be undone and could reasonably go either way, keep options to at most four with a recommended default first, and continue building whatever doesn't depend on an open question.

Two things were already decided before this review began and are not reopened here:

- **The statutory-tables ownership precedent** (`docs/16` Q7 / `docs/22` Module 00 review): CanDo centrally owns and maintains statutory reference content (tax tables, employment standards, training requirements) that it ships to every tenant. The rules *repository* in this module is different in kind: it is the organization's own compliance program (its policies, its tracked obligations, its jurisdiction-specific legal positions), which the organization must keep current for itself once seeded — CanDo cannot be the backstop for every customer's legal currency the way it is for payroll tax tables, because the repository covers far more jurisdiction-specific and fact-specific ground (human rights, OHS, labour relations, privacy, employment equity, pay equity, accessibility, immigration) than a single verifiable number. This is why decision 1 reads "CanDo seeds, the organization owns," not "CanDo owns," even though Q7's precedent is CanDo-owns-and-maintains for the narrower statutory-tables case.
- **The collective agreement library** (`docs/08`, migration 0003): import, extraction, verification, activation, retro, sandbox testing and pay composition for collective agreements (stories LR-001 to LR-007) were built in the original base specification, before any of the thirteen module reviews began. This migration does not touch that machinery; it only adds the genuinely new Module 13 entities (grievances, essential services, bargaining proposals) that sit alongside it.

## 3. Rules repository

`ref.rule_starter` is CanDo's own verified starting catalogue, one row per jurisdiction and topic (human rights, OHS, labour relations, employment equity, privacy, immigration, pay equity, accessibility), loaded from `rules/compliance/` once CanDo's own legal review has verified a jurisdiction (`verification = 'cando_verified'`). A jurisdiction CanDo has not yet verified (`verify_at_load`) is never copied into a tenant.

`compliance.rule` is the organization's own live, editable copy. Every seeded row starts as `status = 'draft'` with `verification = 'verify_at_load'`, regardless of CanDo's own verification state for the starter — because the decision is specifically that the *organization's own* review is what the status depends on, not CanDo's. A rule can go `active` only once both are true: an `owner_user_id` is recorded (someone in the organization has taken ownership of keeping it current) and `verification <> 'verify_at_load'` (the organization has done its own review, recorded as `organization_verified`). Both conditions are enforced by one constraint, `rule_active_needs_owner_and_review`, rather than a trigger that could drift out of sync with the column checks.

`compliance.legislative_change` logs a pending or adopted change against a rule, feeding the obligations calendar when it becomes something the organization must act on.

## 4. Compliance calendar and obligations register (COMPL-001)

`compliance.obligation` is the recurring and one-time obligations register: filings, training, postings, audits, inspection responses, renewals and reports, each with an owner, a due date and a recurrence. `compliance.obligation_reminder_days` (default 30, not locked) is how far ahead CanDo starts reminding the owner. Waiving an obligation needs a reason on the row (`waived_reason`); there is no silent skip.

## 5. Policy library

`compliance.policy` is the policy library (harassment and violence, OHS, privacy, code of conduct, accommodation and others), each version pointing at its document and carrying whether it requires acknowledgement. `compliance.policy_acknowledgement` records one acknowledgement per employment per policy, so the organization can always see who has not yet signed.

## 6. Inspections

`compliance.inspection` is a flat register of a regulator's visit or review (OHS, employment standards, human rights, privacy, immigration), its findings as a structured list, and whether an order is still outstanding.

## 7. Human rights, accommodation and return-to-work (EQ-002)

`compliance.accommodation_case` tracks a request by protected ground, with functional-limitations documentation only (never a diagnosis field) attached as a `platform.document`, a set of measures tried, and a final decision. The decision goes through the organization's new `accommodation_outcome` approval route; neither the case owner nor the employee the case is about can approve it (extended in `platform.check_approval_task()`).

`compliance.rtw_plan` is deliberately a separate table linked polymorphically to either an accommodation case or a WCB claim, because the law requires return-to-work planning for a workplace injury whether or not it also becomes a human-rights accommodation.

## 8. Occupational health and safety (HS-001)

Built in full, in the same system as the rest of case management, per the owner's decision on question 4:

- `compliance.incident` is one register for injuries, near misses, property damage, hazard observations and violence incidents (a `kind` column tells a hazard observation, which names no one, apart from an injury). A critical injury is flagged for the jurisdiction's immediate-notification duty.
- `compliance.wcb_claim` tracks the workers'-compensation-board claim linked to an incident.
- `compliance.ohs_committee` is the joint health and safety committee, with its worker and employer members and its meeting log kept inline (read as a timeline, never joined across committees for reporting).
- `compliance.sds_document` is the safety data sheet register, each pointing at its actual document and the locations where it must be accessible.
- `compliance.work_refusal` tracks an unsafe-work refusal through its supervisor and committee-member investigation to its outcome.

## 9. Harassment, violence, investigations, discipline and speak-up

`compliance.investigation` covers harassment, violence, discrimination, misconduct and policy-breach complaints. A respondent's visibility into an open investigation is restricted at the API layer, the same boundary rule 47 already applies to a respondent in an onboarding-stage case.

`compliance.discipline_record` is **its own record, never folded into a performance review** — the same separation `docs/28` already keeps between ratings and discipline. A discipline record can point back at the investigation and, if one follows, the grievance it produced.

The speak-up channel is built **in-house**, per the owner's decision on question 3, so it stays in the same case-management system as everything else in this module rather than routing to a third-party hotline. `compliance.speakup_report` supports both anonymous and named reports (`speakup_identity_consistent`: a named report must name a reporter), with a rotating `case_token` letting an anonymous reporter check back in. `compliance.speakup_message` is the two-way thread, addressed by side (reporter or organization) rather than by identity when anonymous. `compliance.speakup_ack_hours` (default 48, not locked) is the SLA for a report's first acknowledgement.

## 10. Labour relations (LR-010, LR-011)

`compliance.grievance` tracks a grievance filed by the employee, the union or the employer against a named `core.agreement`, with its steps and any arbitration kept inline (read as a case file, not joined across a steps table). A settlement goes through the new `grievance_settlement` route; the labour relations officer who proposed the settlement cannot approve it herself.

`compliance.essential_position` lists an essential-services designation by position and minimum headcount, decided by HR and labour relations and never auto-applied — the same pattern rule 56 already uses for bumping options.

`compliance.bargaining_proposal` records a tabled proposal by round and article. Like `comp.bargaining_scenario` (`docs/25` rule 49), a proposal never changes pay or terms by itself; only a ratified `core.agreement_version` does.

## 11. Employment equity, pay equity and accessibility (EQ-001)

`compliance.employment_equity_report` tracks federal employment equity, pay equity and accessibility-plan filings by legal entity and year. Any breakdown behind it reuses **`privacy.min_group_size_self_id`** (10, from migration 0011) — this module does not create a third, near-duplicate suppression mechanism alongside `analytics.min_group_size` (5, migration 0019) and engagement's own floor (migration 0017).

Pay-equity-committee detail, job-class and posting detail, the accessibility plan's own feedback process, and a dedicated immigration-case record are explicit scope cuts: none of them is covered by a story acceptance criterion, and they are not built here. They would be natural follow-on stories, not a silent omission.

## 12. Privacy and data protection (PRIV-001, PRIV-002, PRIV-003)

`compliance.privacy_officer` names the designated contact per legal entity. `compliance.pia` is the privacy impact assessment, covering Quebec Law 25's own trigger as well as a cross-border transfer, a new system or a voluntary assessment. **A cross-border feature cannot go live without an approved PIA** (`cross_border_needs_approved_pia`) — `compliance.cross_border_feature` is the register a go-live gates against.

`compliance.access_request` is the PIPEDA/Law 25 access, correction or deletion request. Its statutory response deadline is **law content, read from `compliance.rule`, not a setting or a column default** — a legislated day-count is not "a value the organization could want different" (rule 43), so it is never hard-coded the way an ordinary business default would be.

`compliance.retention_schedule`, `compliance.legal_hold` and `compliance.destruction_log` cover PRIV-002's retention, hold and destruction-logging requirement. A legal hold is polymorphic (a person, an employment, an investigation, a grievance or a document set), mirroring `platform.document.legal_hold` for the file store itself. `compliance.breach` is the confidentiality-incident and privacy-breach register, covering both Quebec Law 25's "incident de confidentialité" and the general PIPEDA breach-response flow in one table, since both follow the same assess-notify-close pattern.

## 13. Case view logging

`compliance.case_view_log` logs every view of an accommodation case, an RTW plan, an investigation, a speak-up report, a grievance, a WCB claim or a discipline record — the same protective pattern `talent.succession_view_log` already applies to succession data (migration 0016).

## 14. Routes, approvals and the register fix

Two new approval routes join `platform.workflow_route`'s subject types: `accommodation_outcome` (one HR step) and `grievance_settlement` (one labour-relations step). `platform.check_approval_task()` is extended with both, reproducing the full prior chain verbatim so no earlier module's self-approval protection is dropped.

**Register gap found and fixed:** while researching this module's own rules-repository pattern, it became clear that migrations 0018 and 0019 had each added new `platform.workflow_route.subject_type` values (`separation_case`, `entitlement_calculation`, `reduction_batch`, `early_retirement_program` from 0018; `custom_metric` from 0019) without updating `rules/register/values-and-fallbacks.json`, which `tests/hardcoding/check_values.py --db` checks against the live database. This migration adds all five of those, plus this module's own two new subject types and every new fixed list, column default and function default it introduces, to the register. A full retroactive audit of every other possible register gap from migrations 0003 to 0019 was not performed — that is a larger undertaking than this fix — and is flagged in `docs/16` as a follow-up rather than silently assumed complete.

## 15. Validation

The migration was built and verified against a real PostgreSQL 16 instance in this session (not just read for syntax): a minimal stand-in schema covering the tables this migration's own objects reference, every `CREATE TABLE`/`ALTER TABLE`/`INSERT`/`DO` block run to completion, the rules-repository seeding loop exercised with a real starter row (catching and fixing a verification-value mismatch between `ref.rule_starter` and `compliance.rule` before it reached the pack), and the smoke test's ten sections all passing end-to-end, including both new self-approval checks, the `cross_border_needs_approved_pia` gate, the `speakup_identity_consistent` gate, RLS on all thirty new tables, and tenant isolation.

## 16. Open questions closed

1. **Rules repository ownership** — closed. CanDo seeds a starter/reference copy by jurisdiction; the organization owns keeping it current (§3).
2. **Jurisdictions at launch** — closed. The same federal/provincial/territorial set CanDo already supports elsewhere; no new jurisdiction added for this module alone.
3. **Third-party hotline partner** — closed. Built in-house (§9).
4. **OHS scope vs. EHS integration** — closed. Full in-house case management (§8).
5. **Indigenous data governance / OCAP** — **stays open**, pending the owner's advisers. CanDo's existing OCAP-aligned residency option in Core HR (migration 0008) is unaffected and is not extended in this module.

## Sources

- requirements/13-compliance-labour-relations-privacy.md
- stories/13-compliance-labour-privacy.md
- docs/10-security-privacy-audit.md (privacy and data-protection design intent)
- docs/16-open-questions.md (Q7 precedent)
- docs/08-rules-engine-and-agreements.md (collective agreement library, already built)
- claude/review/13-compliance-labour-relations-privacy-decisions.md
