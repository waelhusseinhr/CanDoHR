# 12 Analytics & Reporting · Review decisions

Review started and finished 3 Nov 2026 with Wael.

**Status: applied 3 Nov 2026.** The decisions are in `dev-pack/docs/33-analytics-reporting-decisions.md`, migration `dev-pack/schema/0019_analytics_reporting_decisions.sql` and its smoke test, and the updates listed in docs/33 §12. All six decisions matched CanDo's recommended option. Decided: build the metric library, report builder and dashboards in-house on the Supabase read replica rather than embedding a BI product; predictive models never score a named individual, group level only, forever; the small-group suppression floor defaults to 5 and can never be set below 5; natural-language reporting is not built at launch; cross-customer benchmarking is not built at launch; the external BI connector ships after launch, not at launch.

Already decided elsewhere and not asked again: `privacy.min_group_size_self_id` (10, never lower) for self-identification breakdowns in any module (`docs/25` §8.2); `engagement.min_group_size` (5, floor 3) for survey and engagement results (`docs/31` §3.3); the regrettable-turnover classification itself, which this module only reads as a metric source (`docs/32` §8.2); people decide and AI never decides (AGENTS rule 14); no flight-risk model or AI ranking anywhere in succession or workforce planning (`docs/30` rule 54).

Planned rounds: 1 build approach, individual scores, suppression floor, natural-language reporting · 2 benchmarking and the external BI connector's timing.

The principle from Modules 01 to 11 applies: every decision is a default each organization can change at setup or later, except legal floors, safety rules and the handful of product-scope decisions (such as never scoring a named individual) that are not organization choices; routes are the organization's; CanDo pre-fills its suggested numbers at setup and the organization can change them (Q46).

## Round 1 · Build approach, individual scores, suppression floor, natural-language reporting

| # | Decision |
| --- | --- |
| 1 | **Build the metric library, report builder and dashboards in-house, on the Supabase read replica, rather than embedding a third-party BI product** (CanDo's recommended handling applied). Customers can still extract their own data to an external BI tool later (Round 2 #2). Closes the module's first open question. |
| 2 | **Predictive models never score a named individual; group level only, forever** (CanDo's recommended handling applied, over the alternative of letting a customer enable individual scores after a privacy impact assessment). Closes the module's fourth open question. |
| 3 | **The suppression floor defaults to 5 and can never be set below 5** (CanDo's recommended handling applied, over the alternative of a customer-lowerable floor of 3). Closes the module's third open question. |
| 4 | **Natural-language questions over the semantic layer are not built at launch** (CanDo's recommended handling applied). Closes the module's second open question. |

## Round 2 · Benchmarking and the external BI connector

| # | Decision |
| --- | --- |
| 1 | **Anonymised cross-customer benchmarking is not built at launch; its consent model is a separate future decision** (CanDo's recommended handling applied). Closes the module's fifth open question. |
| 2 | **The external BI connector (a governed, read-only feed to Power BI, Tableau or similar) ships after launch, not at launch** (CanDo's recommended handling applied). |
