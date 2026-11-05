# 33 · Analytics and reporting decisions

Nov 3, 2026 · @Wael

This document records the owner's review of Module 12 (Analytics & Reporting) and turns each decision into something the build can follow: a setting with its default, a database check, a rule the organization sets, a route it edits, or a scope decision for later. The working record is `claude/review/12-analytics-reporting-decisions.md` in the project.

It covers the metric library and semantic layer, customer-defined metrics, the self-service report builder, exports and external BI, predictive models and their governance, small-group suppression, data quality, and the statutory and regulatory reporting catalogue that feeds Module 13's compliance calendar.

**Precedence.** On these topics this document wins over `requirements/12` and the ANA stories in `stories/12-analytics.md`. `docs/25` §8.2, §8.3 and §10.1 still govern pay gap analysis and `privacy.min_group_size_self_id` (10, never lower); `docs/31` still governs survey results and `engagement.min_group_size` (5, never below 3); `docs/32` still governs the regrettable-turnover classification itself, which this module only reads as a metric source; `docs/22` still wins on values and fallbacks. §12 lists every place that changes. The schema is `schema/0019_analytics_reporting_decisions.sql` (migration 0019, Step 18), checked by `tests/schema/schema_0019_smoke.sql`.

**The owner's rules for this module.**

1. CanDo builds its own metric library, report builder and dashboards, on the Supabase read replica (`docs/15` Step 18), rather than embedding a third-party BI product in the base platform. Customers can still extract their own data to an external BI tool, but only as a later addition, not at launch.
2. Predictive models stay at the group level. CanDo will not build a model that scores a named individual; the switch for one is locked off, not merely off by default.
3. Every breakdown this module produces is hidden below the organization's minimum group size, and that floor can never be set below 5. Self-identification and engagement-survey breakdowns keep their own, higher floors (10 and 5/3 respectively) and are untouched by this review.

---

## 1. Decisions at a glance

| # | Decision | Setting or rule | Section |
| --- | --- | --- | --- |
| R1.1 | The metric library, report builder and dashboards are CanDo's own, built on the Supabase read replica; no embedded BI product | — (architecture) | §3.1 |
| R1.2 | Predictive models never score a named individual; the switch is locked off, enforced by the schema itself | `analytics.individual_predictive_scores_enabled` (locked off) | §5.1 |
| R1.3 | The small-group suppression floor defaults to 5 and can never be set below 5 (not the alternative of a customer-lowerable floor of 3) | `analytics.min_group_size` | §6.1 |
| R1.4 | Natural-language questions over the semantic layer are not built at launch | — (scope) | §4.3 |
| R2.1 | Anonymised cross-customer benchmarking is not built at launch | — (scope) | §8.1 |
| R2.2 | The external BI connector (governed read-only feed to Power BI/Tableau) ships after launch, not at launch | — (scope) | §4.4 |

---

## 2. How the module is set up

### 2.1 Settings

| Setting | Decides | CanDo default | Set per |
| --- | --- | --- | --- |
| `analytics.min_group_size` | The smallest group any CanDo report, dashboard or export shows a result for | 5 (floor 5; an organization can raise it, never lower it) | Organization, legal entity |
| `analytics.individual_predictive_scores_enabled` | Whether any predictive model may score a named individual | Off, **locked** | — |

`analytics.min_group_size` is separate from `engagement.min_group_size` (5, floor 3, survey and engagement breakdowns only) and `privacy.min_group_size_self_id` (10, never lower, self-identification breakdowns in any module including this one); it applies to every other breakdown this module produces — turnover, absence, time-to-fill and the rest by department, location or any other non-self-identification grouping. `analytics.individual_predictive_scores_enabled` is a product-scope decision, not an organization choice, so no screen, import or API path changes it (`SETTING_LOCKED`, AGENTS rule 39).

### 2.2 Set up by each organization

| What | Where | Until it is set |
| --- | --- | --- |
| Raising the suppression floor above 5 | `analytics.min_group_size` (§6.1) | CanDo's default of 5 applies |
| Switching off a predictive model | `analytics.model_enablement` (§5.2) | Every model in the catalogue is enabled by default |

### 2.3 Routes

One starter route is copied to every organization, and the organization edits it like any other route (`docs/23` §2.2):

| Route | Subject | Steps |
| --- | --- | --- |
| `custom_metric` | A customer-defined metric | HR |

The person who submits a custom metric never approves it (`SELF_APPROVAL`).

### 2.4 Cautions

None added by this module.

---

## 3. Data architecture and the standard metric library

### 3.1 Built in-house, on the read replica (R1.1)

The metric library, semantic layer and report builder are CanDo's own, built on the Supabase read replica so heavy analytical queries never slow down payroll or self-service (`docs/15` Step 18). CanDo will not embed a third-party BI product (Looker, Power BI embedded, and similar) as the analytics engine itself; §4.4 covers the separate, later decision to let customers feed their own data to an external BI tool they already run.

### 3.2 One definition per metric

`ref.metric_definition` holds CanDo's own catalogue — headcount, FTE, turnover rate (with voluntary, involuntary, regrettable and first-year variants), retention rate, time to fill, time to hire, absence rate, compa-ratio and labour cost to start — each with one formula, its source fields and dimensions, in English and French (ANA-002). Every dashboard, report and export reads from this catalogue rather than raw tables; a correction to a formula is a new version, never an edit in place, matching the freeze-once-published rule already used for job evaluations, pay structures and survey editions (AGENTS rule 34).

### 3.3 Customer-defined metrics, owned and approved

An organization can add its own metric (`analytics.custom_metric`) alongside CanDo's standard library, so a local definition — such as "regrettable turnover in Engineering" — does not drift between the people who use it. It names an owner and goes through the organization's `custom_metric` route (§2.3); the person who submitted it never approves it. Once approved, a custom metric is frozen exactly like an approved job evaluation or structure version: a change is a new version, with the prior one marked superseded, never an edit to the approved row.

---

## 4. Self-service reporting, exports and external BI

### 4.1 Report builder and field security

`analytics.report` holds a saved report's subject area, fields, filters, grouping, calculated fields, as-of date or range, chart choice, and who it is shared with. Field security and small-group suppression (§6) are enforced by the permission engine when a report runs — for an ad-hoc run, a scheduled run (with the owner's current permissions, not the permissions at save time), or an export — never by what the report definition itself claims (ANA-003).

### 4.2 Exports and the audit log

Every report run, export and (once built) natural-language query is logged with who ran it, when, and which fields (`analytics.export_log`), per requirements/12's audit requirement. An export of a sensitive field needs a permission, checked by the API before the export is logged; the database's role is the audit trail, not the permission check itself.

### 4.3 Natural-language questions: not at launch (R1.4)

Plain-English or French questions over the semantic layer ("how many hires in BC last quarter by department?") are not built for launch. When CanDo builds this, the assistant must build its query only on the semantic layer (§3), show the report definition it used so the person can check it, and apply the same permissions and suppression rules as every other report (requirements/12 "Self-service reporting and exports").

### 4.4 External BI connector: after launch (R2.2)

A governed, read-only data feed or connector to Power BI, Tableau or a similar tool, carrying the same row-level security and masking rules as every other report, ships as a later addition rather than at launch. Customers can already extract their own data in full through the ordinary export path (§4.2) before the connector exists.

---

## 5. Predictive analytics and model governance

### 5.1 Group level only, enforced by the schema (R1.2)

`ref.predictive_model` catalogues CanDo's seven models — turnover risk, hiring forecast, time-to-fill prediction, overtime and absence forecast, labour cost forecast, anomaly detection, and narrative insights — each with its purpose, the data it uses, and the fields it never uses (protected characteristics and their proxies). Every row's `output_level` is fixed to `group` by a database check: the schema itself rules out an individual-level model, so this decision cannot be reopened by a later migration or a seed script without a deliberate schema change the owner would see. `analytics.individual_predictive_scores_enabled` (§2.1) stays locked off for the same reason, in case a future model's design is tempted to add an individual mode.

### 5.2 A model an organization can switch off, and fairness testing

`analytics.model_enablement` lets an organization switch any model off, with who and when recorded; a model with no row is enabled by CanDo's own default. `analytics.model_fairness_test` logs the quarterly disparate-impact testing requirement from requirements/12 and ANA-006 (groups tested, result, who ran it, when). No model is ever the sole basis for an employment decision about a named person (AGENTS rule 14); Quebec's Law 25 requirement to inform people about automated decisions and let them ask for review is met by design, since every model here produces a group-level insight, not an individual decision.

### 5.3 Anomaly detection: a human review queue

`analytics.anomaly_flag` holds unusual payroll, overtime, leave or access patterns for a human reviewer; a flag needs a reviewer and a time before it is marked resolved or dismissed, and the reviewer's feedback is kept to improve the model's thresholds (requirements/12 "Predictive analytics and AI").

---

## 6. Small-group suppression

### 6.1 The floor, and how it differs from the self-identification and survey floors (R1.3)

Every breakdown this module produces — by department, location, job, tenure band and so on — is hidden when the group is smaller than `analytics.min_group_size` (default 5; an organization can raise it, never lower it below 5). The owner chose this over a customer-lowerable floor of 3, closing requirements/12's suppression-threshold open question. This floor is distinct from, and does not replace:

- `engagement.min_group_size` (default 5, floor 3) for survey and engagement results (`docs/31`);
- `privacy.min_group_size_self_id` (10, never lower) for any breakdown by a self-identified group, in this module or any other (`docs/25` §8.2).

A breakdown that crosses a self-identified group uses the higher of the two floors that apply.

### 6.2 Complementary suppression and drill-through

Complementary suppression (hiding a second cell so the first suppressed one cannot be worked out from totals) and blocking drill-through into an individual record are applied by the report engine against the fields and filters in a report's definition; this is an application-layer check, not a database constraint, because it depends on the shape of the specific report being run (requirements/12 "Privacy, security and data quality").

---

## 7. Data quality and the statutory reporting catalogue

### 7.1 Data quality scorecard

`analytics.data_quality_score` holds a completeness, validity and timeliness score per domain and date, with a steward named; dashboards show known issues against the metrics they affect rather than hiding them (requirements/12 "Data quality").

### 7.2 Statutory and regulatory reporting catalogue

`ref.statutory_report` lists every government or regulator report the platform produces across modules — T4/T4A/NR4/RL-1/RL-2, source-deduction and Revenu Québec remittances, the ROE, employer health tax, workers' compensation payroll reports, Quebec's 1% training levy, pay equity, BC's pay transparency report, the federal employment equity report (LEEP), group termination notices, Statistics Canada surveys, and workplace injury and illness reports — with its owning module and frequency, so the compliance calendar Module 13 builds can track every one from a single source rather than each module inventing its own list (ANA-005).

---

## 8. Benchmarking across customers

### 8.1 Not at launch (R2.1)

Anonymised, cross-customer industry benchmarks are not built at launch, closing requirements/12's benchmarking open question. Building this later needs its own consent model — which customers' data counts, how it is anonymised, and how a customer opts in or out — as a separate decision when the owner wants to revisit it; nothing here pre-commits to a design.

---

## 9. Fallbacks

None added.

---

## 10. Data model (migration 0019)

| Object | What it holds |
| --- | --- |
| Settings in §2.1 | 2 settings, 1 locked |
| `ref.metric_definition` | §3.2 |
| `analytics.custom_metric` | §3.3 |
| `analytics.report`, `analytics.export_log` | §4.1–§4.2 |
| `ref.predictive_model`, `analytics.model_enablement`, `analytics.model_fairness_test` | §5.1–§5.2 |
| `analytics.anomaly_flag` | §5.3 |
| `analytics.data_quality_score` | §7.1 |
| `ref.statutory_report` | §7.2 |
| `analytics.group_suppressed()` | §6.1 |
| Route subject `custom_metric`; one starter route; `check_approval_task()` with the new subject | §2.3 |

Every new tenant table has `tenant_id` with forced row-level security; organization-authored text fields are registered as translatable (`docs/22` §4.3). The starter route is copied to existing organizations, skipping one that keeps a third language as required for its data (FB-035).

---

## 11. Validation, API and events

**Errors added by 0019:** `METRIC_APPROVED_FROZEN`. Existing ones used: `SELF_APPROVAL`, `SETTING_LOCKED`, `SETTING_NOT_SET`.

**Checks in the application (Step 18), not the database:** the report builder's drag-and-drop field picker and field-security filtering; scheduled report delivery with the owner's current permissions; export formatting (Excel, CSV, PDF) and background processing for large exports; complementary suppression and drill-through blocking against a specific report's shape (§6.2); the natural-language assistant, once built (§4.3); the external BI connector's row-level security mapping, once built (§4.4); dashboard rendering and pre-aggregation for scale; data-quality issue annotation on affected metrics; model card presentation and the quarterly fairness-test scheduler.

**API** (added to `api/openapi.yaml` in Step 18): `GET /metric-definitions`; `GET/POST /custom-metrics` with `approve`; `GET/POST /reports` with `run`, `export`; `GET /export-log`; `GET /predictive-models` with `/enablement`; `GET/POST /model-fairness-tests`; `GET/POST /anomaly-flags` with `review`; `GET/POST /data-quality-scores`; `GET /statutory-reports`.

**Events** (added to `api/events.yaml`; identifiers only, AGENTS rule 9): `custom_metric.approved`, `custom_metric.superseded`, `report.exported`, `predictive_model.disabled`, `predictive_model.fairness_tested`, `anomaly_flag.raised`, `anomaly_flag.resolved`.

---

## 12. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/12` | Points here at the top; the five open questions closed |
| `stories/12-analytics.md` | ANA-001 to ANA-007 follow this document (ANA-004's suppression default corrected from 10 to 5); new stories ANA-008 to ANA-013 |
| `docs/15` Step 18 | Analytics built on migration 0019; pass ANA-001 to ANA-013 |
| `AGENTS.md` | Reading order item 20; rule 57; Step 1 migration 0019 and its smoke test; Step 18 |
| `.cursor/rules/00-cando.mdc` | Rule 57 in short |

Where a listed document still says otherwise, this document wins.

---

## 13. Open questions and items to verify

| Item | Status |
| --- | --- |
| Build the analytics store and dashboards in-house or embed a BI product | Closed: in-house, on the Supabase read replica (R1.1) |
| Whether natural-language reporting ships at launch | Closed: not at launch (R1.4) |
| Default suppression threshold (5 recommended) and whether customers may lower it to 3 | Closed: 5, and customers can never lower it (R1.3) |
| Policy on individual-level predictive scores | Closed: never; group level only, enforced by the schema (R1.2) |
| Benchmarking across customers and the consent model it would need | Closed: not at launch; the consent model is a separate future decision (R2.1) |

---

## Sources

- `requirements/12-analytics-reporting.md`, drafted 17 Oct 2026 and reviewed 20 Oct 2026, bringing together the reporting sections of Modules 01–11 and the recruitment analytics and payroll reporting in the source files.
