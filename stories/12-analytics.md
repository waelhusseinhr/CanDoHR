# Stories · 12 Analytics & Reporting

Requirements: `requirements/12-analytics-reporting.md`.

**ANA-001 — Metrics as of any date.** AC: headcount, FTE, vacancies and turnover compute from effective-dated records as of any date and match Core HR lists for the same date.

**ANA-002 — One metric definition library.** AC: each metric (for example voluntary turnover rate) has one definition with formula, inclusions and exclusions, used by every dashboard and export. Changing a definition creates a new version.

**ANA-003 — Report builder with field security.** AC: users build reports only from fields they may read. Masked fields stay masked in exports, and scheduled reports run with the owner's current permissions.

**ANA-004 — Small-group suppression.** AC: any report that breaks down self-identification or survey data hides groups under the minimum size (default 10) and prevents differencing attacks (for example by suppressing complementary cells).

**ANA-005 — Statutory reports.** AC: the catalogue includes employment equity (federal LEEP where applicable), pay transparency (BC), salary disclosure (public sector), EHT and levy returns, WCB annual statements and union dues remittances, each tied to its source data and rule edition.

**ANA-006 — Predictive models with explanations.** AC: attrition and early-turnover risk scores show top contributing factors, are tested for disparate impact quarterly, and are never used for individual employment decisions without human review.

**ANA-007 — BI export.** AC: governed exports to Power BI, Tableau or a warehouse, with row-level security per tenant and the same masking rules.
