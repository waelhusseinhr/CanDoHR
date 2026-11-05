# Stories · 12 Analytics & Reporting

Requirements: `requirements/12-analytics-reporting.md`. Decisions from the November 2026 review: `docs/33-analytics-reporting-decisions.md`, which wins where it differs from the acceptance criteria below.

**ANA-001 — Metrics as of any date.** AC: headcount, FTE, vacancies and turnover compute from effective-dated records as of any date and match Core HR lists for the same date.

**ANA-002 — One metric definition library.** AC: each metric (for example voluntary turnover rate) has one definition with formula, inclusions and exclusions, used by every dashboard and export (`ref.metric_definition`). Changing a definition creates a new version, never an edit to the published one.

**ANA-003 — Report builder with field security.** AC: users build reports only from fields they may read. Masked fields stay masked in exports, and scheduled reports run with the owner's current permissions.

**ANA-004 — Small-group suppression.** AC: any report breaks down into a group hides it below `analytics.min_group_size` (default 5; an organization can raise it, never lower it below 5) and prevents differencing attacks (for example by suppressing complementary cells). A self-identification breakdown keeps `privacy.min_group_size_self_id` (10, never lower) instead, and an engagement-survey breakdown keeps `engagement.min_group_size` (default 5, floor 3); neither uses `analytics.min_group_size`.

**ANA-005 — Statutory reports.** AC: the catalogue (`ref.statutory_report`) includes employment equity (federal LEEP where applicable), pay transparency (BC), salary disclosure (public sector), EHT and levy returns, WCB annual statements and union dues remittances, each tied to its source data and rule edition.

**ANA-006 — Predictive models with explanations.** AC: attrition and early-turnover risk scores show top contributing factors, are tested for disparate impact quarterly (`analytics.model_fairness_test`), and are never used for individual employment decisions without human review. No model scores a named individual (ANA-010).

**ANA-007 — BI export.** AC: ships after launch, not at launch. When built: governed exports to Power BI, Tableau or a warehouse, with row-level security per tenant and the same masking rules.

**ANA-008 — Customer-defined metrics need an owner and an approval.** As an HR analyst, I want to add my own metric to the semantic layer with someone else's sign-off, so that local definitions do not drift.
- AC1: `analytics.custom_metric` records an owner and a submitter; it goes through the organization's `custom_metric` route, and the submitter never approves it (`SELF_APPROVAL`).
- AC2: once approved, a custom metric is frozen (`METRIC_APPROVED_FROZEN`); a correction is a new version, linked to the one it supersedes, never an edit to the approved row.

**ANA-009 — Every export is logged.** AC: `analytics.export_log` records the user, report, format, fields and whether the export was sensitive for every Excel, CSV, PDF or BI export; an export of a sensitive field needs a permission, checked before it is logged.

**ANA-010 — No predictive model ever scores a named individual.** AC: every row in `ref.predictive_model` has `output_level = 'group'`, enforced by a database check; there is no screen, import or API path that adds an individual-level model or turns on `analytics.individual_predictive_scores_enabled` (locked off).

**ANA-011 — An organization can switch any predictive model off.** AC: `analytics.model_enablement` records who switched a model off and when; a model with no row is enabled by CanDo's default. Fairness testing (ANA-006) runs whether or not a model is currently switched off, so re-enabling it starts from a current result.

**ANA-012 — Anomaly detection needs a human reviewer.** AC: an `analytics.anomaly_flag` cannot move to `resolved` or `dismissed` without a reviewer and a time recorded; the reviewer's feedback is kept to improve the model's thresholds.

**ANA-013 — Data quality scorecard feeds the compliance calendar.** AC: `analytics.data_quality_score` holds a completeness, validity and timeliness score per domain and date with a named steward; `ref.statutory_report` lists every government or regulator report across modules with its owner and frequency, for Module 13's compliance calendar to read.
