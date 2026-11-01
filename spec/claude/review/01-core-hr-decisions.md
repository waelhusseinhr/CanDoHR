# 01 Core HR & Position Management · Review decisions

Review started 24 Oct 2026 with Wael and completed 25 Oct 2026. Decisions are logged here round by round.

**Status: applied (25 Oct 2026).** The decisions are now in the developer pack:

- `dev-pack/docs/21-core-hr-decisions.md` (new): every decision as a setting with its default, or as a database or validation rule; acceptance scenarios HR-001 to HR-035; changes to other documents. It takes precedence over the other docs and requirements on these topics.
- `dev-pack/requirements/01-core-hr-position-management.md`: rewritten to these decisions and to docs/17, 18 and 20; its open questions closed.
- `dev-pack/schema/0007_core_hr_decisions.sql` and `dev-pack/tests/schema/schema_0007_smoke.sql` (new): loaded on PostgreSQL 16; 19 smoke check groups pass.
- `dev-pack/rules/employment-standards/ca-2026-core-hr-additions.json` (new): what an agreement may replace and overpayment recovery, per jurisdiction (BC and ON researched; the rest verify_at_load).
- `dev-pack/AGENTS.md`: reading order item 8, rules 39 to 42, Step 1 migration 0007, build steps, HR- scenarios.
- `dev-pack/docs/16-open-questions.md`: Q3, Q9, Q33 and Q34 closed; Q38 to Q43 added; items to verify added.

The other requirements files (02, 03, 06, 11, 12, 13) and the technical docs listed in docs/21 §13 keep their current wording until their own module reviews; docs/21 wins where they differ, and AGENTS.md tells the coding agent so.

Rounds: 1 employee record · 2 org structure · 3 positions · 4 jobs, codes and requirements · 5 lifecycle transactions and approvals · 6 agreements and seniority · 7 self-service, security, privacy and reporting.

## Principle for every decision (Wael, 25 Oct 2026)

CanDo is sold to many different organizations. **Every decision in this review is a default that each organization can change in its own settings, at setup or later.** The exceptions are legal floors and safety rules, which no setting can turn off: statutory minimums, no self-approval, privacy and security limits, and the audit trail. Each decision states its setting name and default in docs/21 §1.

## Round 1 · Employee record and people in several positions

| # | Decision | Where applied |
| --- | --- | --- |
| 1 | **Employment type lives on each position (assignment).** The employment carries a status worked out from its positions (permanent if any active position is permanent, by default; the order is a setting). | docs/21 §3.1; requirements/01; schema 0007 §2 |
| 2 | **Probation per bargaining unit** (from the agreement's rules), **one employer probation for non-union positions**, and a **trial period** when moving positions inside a unit. | docs/21 §3.2; requirements/01; schema 0007 §3 |
| 3 | **Gender stays voluntary only** (self-identification); no gender field in the record. Pay equity predominance per job class is set by HR with a recorded basis; self-ID counts are aggregate support only. | docs/21 §3.3; requirements/01 |
| 4 | **Rehire eligibility is HR-only,** with a reason category and a review date. Recruiters see only "check with HR". | docs/21 §3.4; requirements/01; schema 0007 §4 |
| 5 | **One employee number per person for life.** Employer-specific and legacy numbers are kept as codes. | docs/21 §3.5; requirements/01; schema 0007 §5 |

**Also applied:** service bridging on rehire proposed by the rule and confirmed by HR; the "low-code front end" note removed; the several-positions rules restated in requirements/01.

## Round 2 · Organization structure and reporting lines

| # | Decision | Where applied |
| --- | --- | --- |
| 1 | **Vacant manager position with no acting manager:** approvals route to the next filled position up, and HR is alerted to name an acting manager. | docs/21 §4.1; schema 0007 §7 |
| 2 | **Each org unit names its head position, effective-dated,** with a warning when a unit has none. | docs/21 §4.2; schema 0007 §7 |
| 3 | **Org chart visibility for employees is set per organization,** starting from filled positions as of today only. | docs/21 §4.3; requirements/01 |
| 4 | **Reporting across employers only under a recorded shared-services arrangement;** the manager sees work fields only. | docs/21 §4.4; schema 0007 §8 (locked setting) |

**Also applied:** tenant-defined levels and several hierarchies; typed relationships and the authority matrix.

## Round 3 · Positions and position control

| # | Decision | Where applied |
| --- | --- | --- |
| 1 | **Positions always; light mode removed.** Organizations that do not manage positions get them created automatically at hire; position control switches on when they are ready. | docs/21 §5.1; requirements/01; schema 0007 §6 |
| 2 | **Over budget or over complement: allowed with finance approval and a written reason;** a hard stop where the organization chooses. | docs/21 §5.2; schema 0007 §6 |
| 3 | **Pay grade comes from the job only;** bargaining unit stays on the position. | docs/21 §5.3; requirements/01 |

## Round 4 · Jobs, codes and requirements

| # | Decision | Where applied |
| --- | --- | --- |
| 1 | **NOC recommended, not required,** with a warning; each organization can make it (or another scheme) required. | docs/21 §6.1 |
| 2 | **Starter job catalogues optional;** organizations can use their own coding scheme instead of NOC. | docs/21 §6.2 |
| 3 | **Job description drafts from NOC duties and the job's requirements. No AI for job descriptions, now or later.** Amended 25 Oct 2026: AI may translate them through CanDo's paid translation service, never write them. | docs/21 §6.3; AGENTS rule 42 |
| 4 | **Several titles per position, each with its purpose** (working, funder, posting, legacy, other); the job title stays official. | docs/21 §6.4; schema 0007 §9 |

## Round 5 · Lifecycle transactions and approvals

| # | Decision | Where applied |
| --- | --- | --- |
| 1 | **Back-dated changes into paid periods need HR and payroll approval; two HR approvals when more than one month back.** Retro is then automatic and recalculates everything that depends on the change. **Overpayments are never deducted without the employee's written authorization.** | docs/21 §7.1–7.2; schema 0007 §10–11; rules additions file |
| 2 | **An employee sees an approved change once it is marked "communicated".** | docs/21 §7.3; schema 0007 §10 |
| 3 | **Terminations, demotions and leave- or accommodation-linked changes always need HR.** | docs/21 §7.4; schema 0007 §10 (locked setting) |

**Also applied:** `any` decisions final (Q33); escalation after 3 working days (Q34); change reasons per organization mapped to fixed categories.

## Round 6 · Agreements and seniority

| # | Decision | Where applied |
| --- | --- | --- |
| 1 | **Where an agreement and the law differ, the agreement applies where the law lets it replace that part.** Below-law parts warn both the HR and payroll administrators, and both must approve before activation; where the law does not allow it, CanDo pays the law's minimum. Comparison per agreement: per hour by default. Closes Q9. | docs/21 §8.1; schema 0007 §12; rules additions file |
| 2 | **CanDo or a certified partner sets agreements up; the customer's HR can amend them through CanDo's screens.** | docs/21 §8.2; schema 0007 §12 |

**Also applied:** seniority by date, hours or points from launch; agreement library structure per docs/17 §11.

## Round 7 · Self-service, security, privacy and reporting

| # | Decision | Where applied |
| --- | --- | --- |
| 1 | **Bank account changes: second factor, notices, hold, and HR approval after a live video or phone check with photo ID,** calling the number on file, keeping no copy of the ID. | docs/21 §9.1; schema 0007 §13 |
| 2 | **Self-identification library** that each organization switches on, edits or adds to; government reports read only standard categories mapped to official groups. | docs/21 §9.2; schema 0007 §14 |
| 3 | **OCAP® for First Nation customers: the Nation chooses at setup** between the shared platform with OCAP® controls (standard price) and its own separate database (paid option). Confirmed 25 Oct 2026. | docs/21 §9.3; schema 0007 §15 |

**Also applied:** installable web app; Entra ID and Okta at launch (Q3); full history for every record.
