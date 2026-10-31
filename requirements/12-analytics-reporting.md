# CanDo HRIS — 12 Analytics & Reporting

Oct 17, 2026 · @Wael

## Overview and scope

> **Draft status:** new specification. Brings together the reporting sections of Modules 01–11 and the recruitment analytics and payroll reporting in the source files, and adds the cross-module layer they all point to.

Analytics & Reporting turns data from every module into consistent numbers people trust. Each module keeps its operational reports; this module owns shared metric definitions, cross-module analytics, executive dashboards, the self-service report builder, predictive models and the statutory reporting catalogue.

**Principles:**

| Principle | Meaning |
| --- | --- |
| One definition per metric | Turnover, headcount, time to fill and the rest are defined once and used everywhere |
| Point-in-time accuracy | Any metric can be run as of any past date using effective-dated history |
| Security follows the user | Reports never show data the user could not see on a screen |
| Privacy by aggregation | Sensitive analyses (equity, engagement, health-adjacent) shown only in groups above a minimum size |
| Explainable insights | Every prediction or alert shows what drives it |

## Data architecture and metric definitions

**Analytics store:** module events and nightly snapshots flow into a reporting store separate from the transactional database, so heavy queries never slow down payroll or self-service; data refresh is near real time for operational metrics and daily for trend metrics; history is kept as effective-dated facts so trends are reproducible.

**Semantic layer:** a governed catalogue of dimensions (employee, position, job, org unit, location, province, entity, bargaining unit, time) and measures with plain-language definitions in English and French, the formula, the source fields, filters, and an owner. Reports and dashboards use the semantic layer rather than raw tables.

**Example definitions:**

| Metric | Definition |
| --- | --- |
| Headcount | Count of active employees (one per person, primary assignment) on a date |
| FTE | Sum of FTE across active assignments on a date |
| Turnover rate | Separations in period ÷ average headcount in period; variants for voluntary, involuntary, regrettable, first-year |
| Retention rate | Employees present at start and end of period ÷ headcount at start |
| Time to fill | Days from requisition approval to offer acceptance |
| Time to hire | Days from candidate application to offer acceptance |
| Absence rate | Unplanned absence hours ÷ scheduled hours |
| Compa-ratio | Pay ÷ range midpoint |
| Labour cost | Gross pay plus employer statutory and benefits costs |

Customers can add their own metrics through the semantic layer with an owner and approval, so local definitions do not drift.

## Standard metric library

| Domain | Metrics |
| --- | --- |
| Workforce | Headcount, FTE, hires, separations, net change, span of control, layers, contingent ratio, average tenure, age and service profiles (aggregated) |
| Recruitment | Requisitions open and aging, time to fill and hire, source effectiveness, pipeline conversion by stage, offer acceptance, cost per hire, quality of hire (performance and retention of hires), diversity of applicant pools (voluntary data, aggregated), agency performance |
| Onboarding | Task completion on time, time to productivity, new hire survey scores, first-year turnover |
| Payroll and cost | Labour cost by unit, overtime share, premium pay, payroll accuracy (corrections per run), cost per FTE, budget vs actual |
| Compensation | Compa-ratio distribution, market ratio, pay gap (raw and adjusted), increase distribution, incentive payout vs target |
| Benefits | Participation, cost per employee, cost trend, spending account use |
| Time and leave | Absence rate, overtime hours, leave liability, schedule adherence |
| Performance | Review completion, rating distribution, goal completion, check-in frequency |
| Learning | Compliance completion, overdue training, hours and spend per employee, expiring credentials |
| Succession | Critical role coverage, bench strength, internal fill rate, promotion rate |
| Engagement | Engagement index, eNPS, participation, recognition activity |
| Separation | Turnover by type and reason, regrettable turnover, exit themes, cost of turnover |
| Equity | Representation by designated group vs availability, hires, promotions and separations by group, pay gap |

## Dashboards by audience

| Audience | Dashboard content |
| --- | --- |
| Executive and board | Headcount and cost trend, turnover and retention, critical role coverage, engagement, equity representation, compliance status, top risks; one-page board pack export |
| HR leadership | All domains with drill-down; alerts for metrics outside thresholds |
| Managers | Their team only: headcount, open requisitions, absences, overtime, pending approvals, overdue training, review completion, team engagement (above threshold), upcoming milestones and expiries |
| Finance | Labour cost vs budget, overtime and premium cost, vacation liability, benefits cost, forecast |
| Payroll | Run status, errors, remittance calendar, filings |
| Recruiters | Pipeline, aging, source mix, time to fill |
| Compliance and health and safety | Training compliance, credential expiry, incident and claim counts, filing deadlines |
| Employees | Personal dashboard: leave balances, pay, learning progress, goals |

**Dashboard features:** filters by any dimension the user may see; drill-through to the underlying records (respecting permissions); trend and comparison periods; targets and thresholds with colour that is never the only signal; annotations; scheduled email or PDF delivery; mobile layouts; English and French labels.

## Self-service reporting and exports

**Report builder:** pick a subject area (employees, positions, requisitions, pay results, leave, reviews, training and so on) and drag fields from the semantic layer; filters, grouping, totals, calculated fields; as-of date or date range; charts; save, share with roles or people, and schedule.

**Natural-language questions:** users can ask questions in plain English or French ("how many hires in BC last quarter by department?"); the assistant builds the query on the semantic layer, shows the report definition it used so the user can check it, and applies the same permissions and suppression rules.

**Exports:** Excel, CSV and PDF; large exports run in the background with a notification; exports of sensitive fields require a permission and are logged; watermarking optional for restricted reports.

**External BI:** governed data feeds or a read-only connector to Power BI, Tableau and similar tools, carrying row-level security; customers own their data and can extract it in full.

## Predictive analytics and AI

| Use | Output | Guardrails |
| --- | --- | --- |
| Turnover risk (group level) | Segments with rising risk and the drivers behind it | Shown for groups by default; individual scores only if the customer enables them after a privacy impact assessment, never visible to the employee's manager alone, never used as the sole basis for any decision |
| Hiring forecast | Expected requisitions by month from turnover and growth plans | Assumptions visible and editable |
| Time-to-fill prediction | Expected days for a new requisition | Comparable past requisitions shown |
| Overtime and absence forecast | Expected hours by unit and week | Seasonality explained |
| Labour cost forecast | Cost to year-end | Linked to Module 09 scenarios |
| Anomaly detection | Unusual payroll, overtime, leave or access patterns | Human review queue; feedback improves thresholds |
| Narrative insights | Plain-language summaries of dashboard changes | Each sentence links to the numbers behind it |

**Model governance:** each model documented (purpose, data used, excluded fields, performance, fairness tests across groups, owner, review date); protected characteristics are never model inputs, and proxies are tested; customers can switch any model off; Quebec Law 25 requirements to inform people about automated decisions and let them ask for review are met by design, since no model makes a decision on its own.

**Performance claims:** any accuracy figures are measured on the customer's own data after deployment and shown in the model card; no vendor-sourced benchmark claims are reused (consistent with the source reconciliation in Module 02).

## Statutory and regulatory reporting catalogue

The catalogue lists every government or regulator report the platform produces, its owning module, frequency and due date, so the compliance calendar in Module 13 can track them.

| Report | Owner module | Frequency |
| --- | --- | --- |
| T4, T4A, NR4, RL-1, RL-2 slips and summaries | 03 Payroll | Annual |
| Source deduction remittances (PD7A) and Revenu Québec remittances | 03 Payroll | Per remitter schedule |
| Records of Employment | 03 Payroll / 11 Offboarding | Per event |
| Employer health tax returns | 03 Payroll | Annual and instalments |
| Workers' compensation payroll reports | 03 Payroll / 13 Compliance | Per board schedule |
| Quebec workforce skills development (1% training) | 08 Learning / 03 Payroll | Annual |
| Pay equity plans, postings and maintenance | 04 Compensation / 13 Compliance | Per regime |
| BC pay transparency report | 04 Compensation | Annual by 1 November for covered employers |
| Federal employment equity report (LEEP) | 13 Compliance | Annual |
| Group termination notices | 11 Offboarding | Per event |
| Statistics Canada surveys (for example payroll employment surveys when selected) | 12 Analytics | When requested |
| Workplace injury and illness reports | 13 Compliance | Per event and annual summaries |

Each report shows the data lineage (which fields and rules produced each number) to support audits.

## Privacy, security and data quality

**Access:** row-level security by org scope and field-level security by data class are inherited from Module 01 and applied to every report, dashboard, export, natural-language answer and BI connector.

**Small-group suppression:** results for self-identification, engagement, inclusion and pay gap analyses are hidden when the group is below the configured minimum (default 5); complementary suppression stops people working out a hidden cell from totals; drill-through blocked where it would reveal individuals.

**De-identification:** analytics datasets for advanced work can be de-identified (pseudonymous keys, generalised dates and ages) with re-identification restricted.

**Audit:** report runs, exports and natural-language queries logged with user, time and fields.

**Data quality:** quality scores per domain (completeness, validity, timeliness) shown on dashboards; known issues annotated on affected metrics; stewards assigned per domain to fix problems at the source.

## Public-sector and large-employer reporting

| Report | Content |
| --- | --- |
| Salary disclosure | Statutory public lists by threshold (for example Ontario's $100,000 list), with review before publication |
| Council and board reporting | Headcount, vacancies, overtime, absence and labour cost by department for budget and committee meetings |
| Statistics Canada | Responses to payroll and labour surveys when the employer is selected |
| Auditor general and internal audit | Payroll accuracy, access and control evidence |
| Bargaining | Cost and headcount by bargaining unit; settlement scenarios |
| Funders | Funding-agreement reports for First Nations, non-profits and agencies |
| Equity | Employment equity and pay equity reports with small-group suppression |

**Scale:** the analytics store handles 100,000 employees and multi-year history per tenant; dashboards stay interactive through pre-aggregation.

## How CanDo compares

| Vendor | Analytics position | CanDo response |
| --- | --- | --- |
| Workday, Dayforce, UKG | Deep analytics for large employers | Match, with a Canadian statutory report catalogue |
| HiBob | People analytics for mid-size employers | Match the experience |
| Payworks | Workforce analytics add-on | Exceed for SMBs |
| Collage, Rise | Lighter reporting | Exceed |

Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Implementation, sources and open questions

**Implementation:**

| Phase | Delivered |
| --- | --- |
| With Core HR and Payroll | Semantic layer for workforce and cost; standard dashboards for executives, HR, managers and finance; statutory catalogue for payroll filings |
| With each later module | That module's metrics added to the semantic layer and dashboards |
| After six months of data | Trend dashboards, forecasting and group-level turnover insights |
| On request | BI connector, natural-language questions, individual-level models (after privacy impact assessment) |

**Sources:** recruitment analytics and dashboards in Recruitment 1.docx, DD Recruitment Module.docx and the Bubble build guide (Module 02); payroll reporting in the April 16 payroll file (Module 03); reporting sections drafted in Modules 01 and 04–11. Vendor performance claims from the DD Recruitment Module were excluded.

**Open questions:**

- [ ] Build the analytics store and dashboards in-house or embed a BI product
- [ ] Whether natural-language reporting ships at launch
- [ ] Default suppression threshold (5 recommended) and whether customers may lower it to 3
- [ ] Policy on individual-level predictive scores
- [ ] Benchmarking across customers (anonymised industry benchmarks) and the consent model it would need

**October 2026 review:** added public-sector reporting (salary disclosure, council, Statistics Canada, audit, funders), scale target and competitor comparison.
