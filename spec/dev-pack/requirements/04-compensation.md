# CanDo HRIS — 04 Compensation Management

Oct 17, 2026 · @Wael

> **Owner's review, 27–28 October 2026.** The decisions from the Module 04 review are in `docs/25-compensation-decisions.md`, which wins where this document differs. In short: the philosophy is pre-filled and approved by an executive before a market-based structure; structures, pay decisions, payouts and disclosure lists go through the organization's routes; spreads are pre-filled by track; people below the minimum get a catch-up plan; above the maximum the manager proposes; promotions pay at least the new minimum and 5%; demotions keep pay, with a caution to reduce it; acting pay is chosen at setup; cycles start from pre-filled rules, exceptions need a reason and HR's approval, and HR releases letters; clawbacks only from the signed agreement; bonuses prorated by eligible days; basic commissions and long-term incentive tracking at launch; moderate transparency by default; pay gaps by gender and self-identification groups, never below 10 people; BC and federal reports at launch; statements on request; bargaining costed at launch. The sections below are marked where they changed.

## Overview and scope

Compensation Management decides what people should be paid and why. It turns an organization's pay philosophy into market-priced structures, administers pay within them, runs planning cycles, and proves the results are fair. Payroll (Module 03) pays what this module approves.

**In scope:** compensation philosophy; job architecture (families and career levels) and job evaluation; benchmark jobs, labour markets, salary surveys and public wage data; market pricing analysis; salary structures, ranges and union wage grids; pay administration rules; merit, market and promotional increase planning; variable pay and incentives; pay equity and pay transparency compliance; taking part in salary surveys; total rewards valuation and statements.

**Out of scope:** pay calculation and disbursement (03); benefits plan administration (05), though benefits and practice benchmarking is shared with 05; the job catalogue (01); performance ratings (07, consumed here); the competency framework (shared by 02, 07, 08 and 09, used here as evidence for job evaluation).

**Design:** `docs/19-competencies-job-evaluation-and-total-rewards.md` is the detailed design for job architecture, competencies, job evaluation, surveys, market pricing, structures, practice benchmarking and survey participation, and wins where it differs from this module. `docs/25` adds the owner's decisions and wins over both.

**Who uses it:** compensation analysts and HR (structures, market data, cycles); managers (recommendations within budget); finance (budgets and cost modelling); executives (approvals, philosophy); employees (own range position and total rewards, at the transparency level the employer chooses).

## Compensation philosophy and strategy alignment

The module starts by recording a documented philosophy, because every later step (market selection, positioning, ranges, increase guidelines) refers to it.

**Philosophy record:** target competitive position versus market (lead, match or lag) overall and by job group, level or function; pay mix (base, variable, benefits); role of performance, seniority and skills in pay progression; transparency level; how the strategy supports business objectives; executive approval and review date. Setup pre-fills "match the market median"; the organization edits it, and an executive approves it through the organization's route before a market-based structure is approved (`docs/25` §3).

**Strategy alignment guidance shown during setup:**

| Business strategy | Market pricing focus | Target positioning |
| --- | --- | --- |
| Operational excellence | Cost efficiency with targeted premiums | Match market, or lead-lag |
| Product or service leadership | Premium for innovation-critical roles | Lead market for key positions |
| Customer intimacy | Premium for customer-facing roles | Lead market for customer roles |

| Lifecycle stage | Considerations |
| --- | --- |
| Start-up | Conserve fixed costs; use variable pay for upside |
| Growth | Keep pace with fast-moving rates, especially for high-demand skills |
| Mature | Balance competitiveness with cost control; focus on retention |
| Decline | Re-evaluate premium positions; focus on cost efficiency |

**Canadian context the system prompts for:** unionized groups paid on negotiated grids rather than market structures; pay equity obligations that constrain structure design; public-sector or funder-imposed pay limits for non-profits; regional differences between and within provinces (for example northern and remote premiums).

## Benchmark jobs, labour markets and survey sources

**Benchmark job selection.** The system flags candidate benchmarks from the job catalogue (Module 01) and the analyst confirms. Criteria: easily defined and found in other organizations (at least a 70% match of duties); representative of all levels; important to the internal hierarchy; established with multiple incumbents. Target coverage: at least 50% of jobs benchmarked when using market-based job evaluation. Each benchmark needs current documentation: responsibilities and duties, required knowledge, skills and abilities, reporting relationships, essential functions and job specifications.

**Labour market definitions** are stored per job group, combining organization size, geography and industry. Defaults the system proposes:

| Job group | Default market |
| --- | --- |
| Executive | National data by organization size |
| Professional and technical | Industry-specific, regional or national |
| Administrative and clerical | Local data across industries |
| Skilled trades and operations | Local or regional data; union rates where they set the market |

**Data collection options:**

| Method | Best when | Considerations |
| --- | --- | --- |
| Published surveys | Market is well defined; budget is limited | Verify quality; may need several sources |
| Custom third-party survey | Specific data needed for unique roles or industries | Higher cost, more targeted |
| Self-conducted survey | Very specialized roles with little published data | Time-intensive; participation risk |
| Complimentary sources | Supplementing other data | May lack depth; validate methodology |

Survey sources are evaluated on cost versus benefit, time required, reliability, availability in time for decisions and data format compatibility.

**Survey library** (`docs/19` §6):

| Item | What CanDo keeps |
| --- | --- |
| Survey | Publisher, licence (licensee, allowed uses, whether employees may see figures, expiry, delete at expiry), the role that may see its data, whether the tenant takes part |
| Edition | Effective date, participants, currency, hours basis for hourly data, the masking rules it publishes, organization and incumbent weightings, file hashes |
| Job catalogue | The survey's jobs as values of the survey's own code scheme (`docs/18`), with family, sub-family and level as attributes; descriptions visible only to the survey's role |
| Data cuts | Region, size by employees or budget, complexity, sector focus, all participants |
| Market data | Per job, cut, weighting and element (base, hourly, range, incentive target and paid, total cash): organizations, incumbents, mean, P10, P25, P50, P75, P90; masked values stay empty |

Each organization imports its own licensed copy of each survey. CanDo ships no survey data. Imports use generic profiles (statistics in columns or in rows, job catalogue, cut dictionary, practice prevalence) with a dry run that lists errors and warnings before anything is published. A publisher's own template is added only when a customer sends a sample file and the publisher allows it (`docs/25` §8.3).

**Public wage data.** Job Bank wages from Employment and Social Development Canada are loaded once for every customer, by NOC 2021 code and region: low (P10 in most cases), median and high (P90 in most cases). Any job with a NOC code has a free benchmark without matching work, useful on its own for support, skilled and professional jobs and as a second source next to a survey.

**Matching** (`docs/19` §6.3): a survey match is a code on the job, inherited by its positions, with overrides on a position or an incumbent when the work differs. Each match records quality (exact, close, partial, blended with shares), the estimated share of the survey job's main duties performed (default threshold 70%, or the survey's own rule), and its source. The level is matched on responsibility, never on pay, performance or title. For submissions, each incumbent has one match per survey. Matches are suggested from the mapping between the organization's job families and career levels and the survey's (§ Job architecture below), from similar positions and from the last edition. A coverage meter shows benchmark jobs, positions and incumbents matched.

## Market data analysis

**Statistical measures** (the analyst picks one per job group and the choice is stored with the analysis):

| Measure | When to use | Limitation |
| --- | --- | --- |
| Median | Default; minimizes the effect of extreme values | May not reflect market value if data is skewed |
| Weighted mean | Shows what incumbents are paid | Skewed by companies with many incumbents |
| Unweighted mean | Shows what companies pay | Ignores incumbent counts |
| Trimmed mean | Removes outliers | Must be applied consistently |

Percentiles (25th, 50th, 75th, 90th) are kept alongside so the target position from the philosophy can be read directly.

**Market definitions** say how a group of jobs is priced: the sources (survey editions and public wages) with weights, the weighting (organization or incumbent), the pay element, the cuts in order of preference, the target statistic and lead or lag from the philosophy, the minimum sample (never below the survey's own masking) and the ageing method.

**Usable values.** A value is used only if the survey published it and its counts meet the minimum. For each source, pricing takes the first cut in the chain where every matched survey job is usable; if none is, the source is left out for that job and the reason is shown. Nothing is estimated where a survey masked a value.

**Aging to a common date.** Survey data with different effective dates is aged to the structure's effective date:

> Aged amount = Original amount × (1 + aging factor × months ÷ 12)

Months are whole calendar months plus the difference in day of month as a fraction of 30. Aging factors are configurable by job level (hourly, salaried, executive), industry, geography and pay element (base, total cash). Compounding, (1 + factor) ^ (months ÷ 12), is available for periods over 12 months.

**Blending for hybrid roles.** Component jobs and weights are recorded; the system calculates the weighted market rate. Example: Director, HR & Security = HR Director $150,000 × 60% ($90,000) + Security Director $140,000 × 40% ($56,000) = blended rate $146,000.

**Geographic differentials.** National data adjusted to local markets using configurable differentials by city, region or province, including northern and remote locations; differentials can apply to the structure (location-based ranges) or to individuals (location premium). Each structure says which it uses (`docs/25` §4.4).

**Market composite.** For each benchmark: the sources used, weights per source, aged and adjusted values, the resulting market rate at each percentile, and a competitiveness ratio (current average pay ÷ market rate). When a source cannot be used for a job, its weight is spread over the others. Composites are produced by pricing runs at a common date; an approved run is frozen, keeps the lineage of every number, and is superseded by the next approved run. Runs on an edition are marked stale when a newer edition is published. Arithmetic is decimal and specified by `reference/market_pricing_reference.py` and `tests/compensation/market_pricing_cases.json`.

**Validation checklist before finalizing:**

- [ ] Sufficient sample size for statistical validity
- [ ] All data aged consistently to a common date
- [ ] Appropriate geographic adjustments
- [ ] Outliers analysed and handled consistently
- [ ] Consistent job matching methodology
- [ ] Results aligned with the compensation philosophy
- [ ] Executive approval of market positioning

## Pay structure design

The structure builder follows an eight-step method, each step a screen with its own sign-off:

| Step | What the system supports |
| --- | --- |
| 1. Analyse and document job content | Flags jobs with missing or stale descriptions (duties, skills, reporting, decision authority) |
| 2. Select benchmark jobs | Coverage meter against the 50% target; representation check across levels and functions; leadership validation of matches |
| 3. Identify relevant labour markets | Market definitions per job group (geography, industry, size) |
| 4. Identify survey sources | Survey library with fit, sample size and methodology notes |
| 5. Collect and analyse benchmark data | Matching, composite, aging, geographic adjustment, competitiveness assessment |
| 6. Develop grade midpoints | Midpoints reflecting the target position; midpoint differential typically 15–20% between grades; smoothing to keep progression logical |
| 7. Assign benchmarks to grades | Each benchmark placed in the grade whose midpoint is closest to its market rate, with override for scope and responsibility |
| 8. Slot non-benchmark jobs | Comparison to benchmarks by relative value within the family, across functions and by supervisor-subordinate relationships |

**Market line.** Where jobs are evaluated with points, the builder fits ln(market rate) = a + b × points over the priced benchmarks, shows R², the progression per 100 points and each job's distance from the line, and flags jobs more than 15% (configurable) above or below it. The analyst can exclude an outlier with a reason or treat it as a hot job. Grade midpoints come from the line at the middle of each grade's point band, rounded to the structure's unit (default $100); the analyst can smooth them, with a reason recorded.

**Range construction:** range spread configurable by grade or level, starting from CanDo's pre-filled spreads by career track: support 30%, professional 40%, management 50%, executive 60% (`docs/25` §4.1); minimum = midpoint ÷ (1 + spread ÷ 2); maximum = minimum × (1 + spread); optional zones or quartiles within each range; overlap between adjacent grades reported.

**Posting ranges.** Postings take their range from the grade. Where a grade's range is wider than a posting rule allows (in Ontario, no wider than $50,000 for postings whose expected pay is $200,000 or less), the builder proposes a posting range centred on the hiring zone for the analyst to confirm.

**Structure types supported:** traditional graded ranges; broadbands; market-based ranges per job; step grids (fixed steps with time-based or merit-based progression); collective agreement wage grids imported from Module 01; hourly rate tables; location-differentiated structures.

**Modelling:** before approval, the builder shows how many employees fall below minimum and above maximum, the cost to bring everyone to minimum (prorated by FTE), compa-ratio distribution by gender and other groups (for pay equity review), and the change from the current structure. Structures are versioned and effective-dated; two approved versions of a structure cannot overlap, and approving a version writes its salary ranges, recomputes compa-ratios and flags open requisitions whose posting range changes. A version is approved through the organization's route; the starter copy is HR, then finance, then an executive (`docs/25` §4.2).

## Job architecture, job evaluation and competencies

**Job architecture** (`docs/19` §3): job families with sub-families, and career levels in four tracks: support and operations (S1–S4), professional and technical (P1–P5), management (M1–M4) and executive (E1–E2). Both are code schemes the organization can rename, trim or replace. Each level describes scope, autonomy, problem solving and influence, and carries typical TEER, typical evaluation points and default competency targets. These are used for suggestions and warnings only, never to block. Mapping the organization's families and levels to a survey's once makes most survey matches a confirmation.

**Job evaluation** (`docs/19` §5): versioned point-factor plans. CanDo provides a sample plan of 12 factors and 1,000 points covering skill, effort, responsibility and working conditions, the four groups pay equity laws compare. It rates emotional effort, responsibility for others' wellbeing, communication and relationship skill, fine motor work and exposure to bodily fluids, which older plans missed in female-predominant work. It stays a sample until a pay equity adviser reviews it (`docs/25` §10.2).

- **Publishing a plan.** A plan used for pay equity cannot be published without all four groups and a recorded gender-neutral review.
- **Rating.** Each factor rating has a degree and a rationale. Evidence is shown beside it: NOC TEER, career level, competency targets, requirements and reports. A rating outside the evidence's suggested range needs a reason.
- **Approval.** Approval computes points and grade. Approved evaluations never change; a re-evaluation supersedes them. The grade change for the job is proposed as a change set.
- **Other methods.** Classification, ranking and market slotting can be recorded, but only point-factor scores feed pay equity comparisons in Module 13.

**Competencies** (`docs/19` §4): one framework, shared with Modules 02, 07, 08 and 09, gives target levels on jobs and positions and assessments of people. In job evaluation, competency targets are evidence only. Assessments are never used for grades, pay equity or market pricing. The owner accepted the Unified Competency Model and the starting targets by career level as written (`docs/25` §9).

## Pay administration

**Position-in-range metrics** calculated for every employee and assignment:

| Metric | Formula |
| --- | --- |
| Compa-ratio | Actual pay ÷ range midpoint |
| Range penetration | (Actual pay − minimum) ÷ (maximum − minimum) |
| Market ratio | Actual pay ÷ market rate for the job |
| Quartile | Position within the range's four zones |

**Rules the system enforces or flags** (each is the organization's setting, `docs/25` §4 and §5):

| Situation | Rule |
| --- | --- |
| New hire offer | Recommended range by experience and internal equity check against incumbents in the same job; offers above a configured point need approval (shared with Module 02) |
| Below minimum (green circle) | Flag; a catch-up plan to reach the minimum within the months the organization sets (12 pre-filled); included in cycle modelling |
| Above maximum (red circle) | Flagged; no CanDo rule by default: the manager proposes a lump sum, a base increase or none, and the organization's route approves |
| Promotion | At least the new range minimum and at least the organization's minimum percentage (5% pre-filled) |
| Demotion or reclassification down | Non-union: pay kept and red-circled by default; reducing it needs a caution with a reason (constructive dismissal risk). Agreements keep their own pay protection rules |
| Acting pay | Non-union: the method the organization chooses at setup (percentage above, acting job minimum, the higher of the two, or the first step above); agreements keep their own rules |
| Step progression | Automatic step increases on anniversary or hours thresholds for grid-based groups, feeding Module 03 |
| Minimum wage | Rates below the jurisdiction's minimum wage blocked |

**Off-cycle changes:** market adjustments, retention increases, equity adjustments and counter-offers run as individual requests with justification, budget check and approval through the organization's route (`docs/25` §2.3); all approved changes publish to Core HR and Payroll with effective dates.

## Compensation planning cycles

**Cycle setup:** eligible population, starting from the organization's pre-filled rules (union groups on negotiated increases excluded, people hired in the last 3 months excluded, people on unpaid leave given their increase when they return; each cycle can change them, `docs/25` §6.1); budget pools by department or entity as a percentage of eligible payroll for merit, market, promotion and equity; effective date; guideline matrix; approval chain; deadlines.

**Merit matrix:** increase guidelines by performance rating (from Module 07) and position in range, so lower-paid strong performers move faster. Organizations without ratings use range position only; across-the-board and manager-discretion cycles are also available (`docs/25` §6.2). Example structure:

| Performance \\ Compa-ratio | Below 0.90 | 0.90–1.10 | Above 1.10 |
| --- | --- | --- | --- |
| Exceeds | Highest guideline | High | Moderate |
| Meets | High | Moderate | Low or lump sum |
| Below | Low or none | None | None |

Percentages are set each cycle against the budget.

**Manager worksheet:** team list with current pay, range, compa-ratio, rating, last increase and guideline; recommendation by percentage or amount; budget meter updating live; warnings for out-of-guideline, above-maximum or inequitable outcomes; a written reason and HR's approval for a recommendation outside the guideline (`docs/25` §6.3); comments for the next approver.

**Approvals and calibration:** roll-up review by senior leaders; HR calibration view comparing outcomes across teams and by gender and other groups; finance view of total cost; final approval locks the cycle.

**Outputs:** approved changes to Core HR and Payroll; employee letters generated from the organization's templates in the employee's language, reviewed and released by HR (`docs/25` §6.4); cycle audit report. Unionized groups receive negotiated increases through mass transactions in Module 01 rather than through the cycle.

## Variable pay and incentives

| Plan type | Features |
| --- | --- |
| Annual bonus | Target as percentage of base by grade or role; funding from company, unit and individual metrics with weights; thresholds, targets and caps; proration for hires, leaves and transfers (by eligible days by default, `docs/25` §7.2); manager discretion within limits |
| Sales commission | At launch: plan rates, tiers and caps, results imported by file, statements and payout through Module 03. Quotas with accelerators, draws, recoverable advances and crediting from CRM systems come later (`docs/25` §7.5) |
| Spot and recognition awards | Cash or points tied to Module 10 recognition; budgets per manager; taxable benefit treatment flagged for Payroll |
| Retention and signing bonuses | Amount, payment schedule, clawback terms with dates; recovered on early exit only as the employee's signed agreement allows, within the law (`docs/25` §7.3, Module 11) |
| Profit sharing and gainsharing | Pool formulas, eligibility, allocation by pay or hours; DPSP option |
| Long-term incentives | At launch: grants and vesting schedules recorded, and the taxable benefit sent to Payroll when it arises; no valuations (`docs/25` §7.4). Valuations and the stock option deduction reporting come later |

**Payout process:** metrics loaded or entered; calculations previewed; manager adjustments within rules; approval through the organization's route (starter: manager, HR, finance; `docs/25` §7.1); payout file to Payroll with earning codes and taxation method (bonus method); employee statements explaining the calculation.

**Controls:** plan documents versioned and acknowledged by participants; calculation audit trail; segregation between people who set targets, enter results and approve payouts.

## Pay equity and pay transparency compliance

> Legislative status checked October 2026. Rules change often; the rules repository holds them as effective-dated configuration, and Module 13 owns monitoring.

**Pay equity (equal pay for work of equal value):**

| Regime | System support |
| --- | --- |
| Ontario Pay Equity Act | Job classes and gender predominance; job comparison using evaluation scores; plan maintenance when jobs or pay change |
| Quebec Pay Equity Act | Pay equity exercise and maintenance evaluation every five years; posting of results; CNESST declarations |
| Federal Pay Equity Act | Plans for federally regulated employers with 10 or more employees; committee support; annual statements |
| Other provinces | Public-sector pay equity statutes configured where the customer is covered |

**Pay transparency in job postings** (enforced in Module 02 at posting time, with ranges sourced from this module):

| Jurisdiction | Requirement configured |
| --- | --- |
| British Columbia | Expected pay or pay range in all publicly advertised postings since 1 November 2023; ban on asking pay history; pay transparency reports for employers phased in by size, reaching employers with 50 or more employees on 1 November 2026 |
| Prince Edward Island | Expected pay or range in publicly advertised postings |
| Ontario | From 1 January 2026, employers with 25 or more employees must show expected pay or a range of no more than $50,000 a year, disclose AI use in screening, and state whether the posting is for an existing vacancy |
| Newfoundland and Labrador | Provisions passed but awaiting proclamation; configured as inactive |
| Federal | Employment equity wage gap reporting for federally regulated employers |
| Others | Monitored (for example New Brunswick legislation introduced in 2026) |

**Analytics supporting compliance:** pay gap analysis by gender and the voluntary self-identification groups (Indigenous, racialized, disability), with consent only (mean, median, by quartile, adjusted for job and level); outlier detection for unexplained differences; remediation modelling with cost; report formats for BC pay transparency reports and the federal pay equity and employment equity filings, both at launch (`docs/25` §8.2, §8.3). Groups below 10 people are suppressed to protect privacy; an organization can raise that number, never lower it.

**Job evaluation for pay equity:** Module 13 values job classes from approved evaluations under a published pay equity plan. When a job's description, requirements or competency targets change after approval, the evaluation is flagged for review and the maintenance log records the change. Survey data, competency assessments and individual performance are never inputs to pay equity comparisons.

## Total rewards statements and communication

**Total rewards statement:** base pay, variable pay received, employer CPP/QPP, EI and health tax contributions, benefits premiums paid by the employer (from Module 05), pension and savings contributions, paid time off value, learning investment (Module 08), recognition awards (Module 10) and perks. Produced on request by HR or the employee by default, in English or French; the organization can choose once a year, or once a year plus an up-to-date view in self-service (`docs/25` §8.4).

**Valuation rules** (`docs/19` §9), set per component:

| Component | Valuation |
| --- | --- |
| Base pay, allowances | Rate components (`docs/17` §6.1) and recurring allowances |
| Variable pay, recognition | Paid in the last 12 months |
| Statutory contributions, benefits | Employer amounts paid |
| Retirement | Employer contributions; for defined benefit plans, the employer's current service rate × pensionable earnings |
| Paid time off | Paid days off × the daily rate |
| Learning | Spend on the person |

Statements never show survey figures for a job unless the survey's licence allows sharing with employees.

**Total rewards benchmarking:** total cash is priced like base pay where surveys publish it. Benefits and practices are compared in the scorecard shared with Module 05 (`requirements/05`, Benefits and practice benchmarking). The two are not combined into one index unless the organization imports one from its adviser.

**Transparency levels** the employer chooses, separately for each item (starting defaults in bold, `docs/25` §8.1):

| Item | Options |
| --- | --- |
| Compensation philosophy and strategy | Not shown, **summary**, full |
| Market positioning | **Not shown**, general statement, by job group |
| Pay ranges | **Own range only**, own job family, all ranges |
| Individual position in range | Not shown, **quartile**, compa-ratio |

Managers see their team's ranges by default, and their team's market ratios only when the organization switches it on (never where a survey's licence restricts derived results).

**Management communication:** purpose and method of market pricing; positioning rationale; data sources and reliability; implementation timeline; training on talking to employees about pay.

**Employee communication tools:** pay structure overview, FAQ, manager talking points, individual compensation statements, and a career path view showing ranges for next roles when ranges are visible.

## Taking part in salary surveys

Organizations that contribute to a survey prepare the submission in CanDo (`docs/19` §10):

- **Organization profile:** employees, budget, structure complexity, sector focus and regions.
- **Incumbent rows:** one per incumbent with a match (optionally one per matched vacant position), with a pseudonym, survey job code and match quality, FTE, annualized base and hourly rate, incentive eligibility, target and payment, and location.
- **Practice answers:** taken from the organization's own benefits, time-off and policy setup.

Privacy rules:

- **Pseudonyms.** Each pseudonym is random and stays the same for that person and that survey every year, so the publisher can compare years without knowing who anyone is.
- **Never included.** Names, SIN, birth dates, contact details and employee numbers are never included.
- **Self-identification.** Gender and other self-identification data are included only if the survey asks, the privacy officer approves, and groups are large enough.
- **Freeze and record.** Approval freezes the rows, and export records the file hash, who exported it and when.

## Data model, integrations and security

**Entities:**

| Entity | Key fields |
| --- | --- |
| Compensation Philosophy | Positioning by job group, pay mix, transparency settings, approval through the route, dates (`comp.philosophy`) |
| Labour Market | Job group, geography, industry, organization size |
| Job Evaluation Plan / Version | Method, purposes, factors and degrees, grade bands, gender-neutral review, status |
| Job Evaluation | Job or position, plan version, ratings with rationale and evidence, points, grade, status, supersedes |
| Survey | Publisher, licence, access role, participation |
| Survey Edition | Effective date, participants, hours basis, masking, weightings, cuts, files, status |
| Market Data | Survey job, cut, weighting, element, counts, statistics, masked fields |
| Survey Match | Job, position or incumbent; survey job; match quality; share; duties match (a code assignment, `docs/18`) |
| Market Definition | Job group, sources and weights, statistic, lead or lag, minimum sample, ageing |
| Pricing Run / Market Composite | Common date, status, per-job percentiles and target with lineage |
| Salary Structure / Version | Version, effective dates, type, location method, grades, market line, status, route |
| Survey Submission | Survey, edition, organization profile, pseudonymous rows, approvals, file hash |
| Grade / Range | Midpoint, minimum, maximum, spread, zones, location group |
| Catch-up Plan | Assignment, range, gap, target date, status (`comp.range_catch_up`) |
| Wage Grid | Agreement, classification, steps, rates, progression rule |
| Compensation Cycle | Type, population and eligibility, budgets, guideline method, letter release, deadlines, status |
| Recommendation | Employee, type, amount, guideline, exception and reason, approvals |
| Incentive Plan / Award / Long-term Grant | Plan rules, proration, clawback terms, participants, awards with route and signed agreement, grants and vesting |
| Pay Equity Plan | Job classes, comparisons, adjustments, postings |
| Salary Disclosure | Statute, year, drafted list, approval, publication (`compliance.salary_disclosure`) |
| Bargaining Scenario | Agreement, term, proposals, cost results, shared, ratified version (`comp.bargaining_scenario`) |

**Integrations:** reads jobs, positions, incumbents, NOC codes, requirements and agreements from Module 01 and ratings from Module 07; reads competency targets from the shared framework as evaluation evidence; sends approved changes and payouts to Modules 01 and 03; supplies ranges to Module 02 postings and offers; supplies approved evaluations to Module 13 for pay equity; supplies cost data to Modules 09 and 12; imports survey files through the import profiles (CSV or Excel) and publisher APIs where a licence allows; loads public wage data by NOC; exports survey submissions and cycle results.

**Security:** compensation data is restricted by default; managers see only their own reports during cycles and cannot see their own recommendation; analysts can be limited to entities; survey data access follows licence terms: each survey's market data, job descriptions and submission pseudonyms are visible only to the survey's role, enforced in the database, and results derived from a survey can be restricted the same way when its licence requires; evaluators see evaluations assigned to them but no pay or survey data; every change and approval is logged; self-identification data used in pay gap analysis follows the Module 01 privacy rules.

## Reporting and analytics

| Report | Content |
| --- | --- |
| Market competitiveness | Average pay vs market by job, family, level and location; lead, match or lag versus target |
| Range position | Compa-ratio and penetration distributions; below minimum (with catch-up plans) and above maximum lists |
| Structure health | Range overlap, midpoint progression, grade population |
| Cycle | Budget vs spend by unit; distribution by rating and compa-ratio; exceptions; approval status |
| Pay equity and gap | Gaps by gender and other groups, raw and adjusted; outliers; remediation cost |
| Incentives | Payout vs target, cost by plan, correlation with performance |
| Cost modelling | Impact of structure changes, cycle scenarios, collective agreement settlements and bargaining scenarios |
| Hot jobs | Jobs with fast market movement or high turnover linked to pay |
| Benchmark coverage | Benchmark jobs, positions and incumbents matched by survey, family and level |
| Evaluation consistency | Points against level and grade; evaluations flagged for review |
| Survey usage | Editions in use, licence expiry dates, runs that use each edition |

Dashboards for compensation analysts, managers (team only) and executives; scenario modelling exports to Excel. Cross-module analytics in Module 12.

## Implementation timeline and ongoing maintenance

**Customer implementation of market pricing (16 weeks, from the source guide):**

| Weeks | Activities |
| --- | --- |
| 1–2 | Establish compensation philosophy and strategy |
| 3–4 | Identify benchmark jobs and select survey sources |
| 5–8 | Collect and analyse market data |
| 9–10 | Develop structure midpoints and ranges |
| 11–12 | Slot jobs and validate the structure |
| 13–14 | Finalize implementation and communication plans |
| 15 | Roll out to management |
| 16 | Roll out to employees |

Employers that only need grids for unionized groups, or that already have a validated structure, can load it directly and skip weeks 1–12.

**Ongoing maintenance:**

| Frequency | Actions |
| --- | --- |
| Annually | Review the full structure against market movement; refresh survey data; pay equity maintenance |
| Quarterly | Monitor hot jobs and market shifts |
| As needed | Evaluate new positions and changed roles |

**Market monitoring:** industry pay trends, geographic differentials, skill premiums for high-demand roles, and economic indicators affecting pay.

**Documentation the system keeps:** survey sources used and why; aging method; market composite approach; slotting decisions; structure validation; approvals.

## Public-sector and large-employer compensation

| Area | Requirement |
| --- | --- |
| Negotiated grids at scale | Hundreds of grids across bargaining units, read from the Module 13 agreement library; general increases, step progression and retro settlements modelled before ratification |
| Excluded and management groups | Separate structures and policies for non-union staff, often tied to union settlements by policy |
| Government frameworks | Executive compensation frameworks and compensation restraint rules set by provincial or territorial governments for their broader public sector, modelled as caps and approval rules |
| Salary disclosure | Statutory lists by threshold (for example Ontario's $100,000 list, BC's Financial Information Act and Societies Act $75,000 schedules, First Nations council remuneration), drafted from paid amounts by the statute's rules, reviewed by HR and finance and approved through the organization's route before publication (`docs/25` §10.1) |
| Elected officials | Council and board remuneration reviews, allowances and indexation by bylaw |
| Comparators | Peer employers for market studies taken from public agreements in the library and from published surveys |
| Bargaining costing | At launch: cost of proposals over the agreement term using live payroll, benefits and schedule data, shared with labour relations and Module 13; nothing changes pay until the agreement is ratified (`docs/25` §10.3) |
| European readiness | The EU Pay Transparency Directive reuses this module's ranges and pay gap analytics when Europe is added |

## How CanDo compares

| Vendor | Compensation position | CanDo response |
| --- | --- | --- |
| Workday, Dayforce | Full compensation planning for large employers | Match planning; lead on Canadian pay equity and transparency |
| BambooHR | Compensation planning with Mercer benchmark data built in | Import any survey the customer licenses, plus free public wage data by NOC for every job |
| Rippling | Compensation management in its suite | Match |
| Canadian SMB tools (Humi, Payworks, Collage, Folks, Rise) | Little or no market pricing or pay equity tooling | Clear gap CanDo fills |

Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Sources and open questions

**Primary source:** Compensation module 3.docx (market pricing implementation guide) — strategy alignment, benchmark selection, data collection, statistical measures, aging, blending, eight-step structure design, timeline, communication, maintenance and validation checklist are taken from it.

**Added in consolidation:** pay administration rules, planning cycles, variable pay, pay equity and pay transparency, total rewards, data model, integrations and reporting (the source covers market pricing only); compensation items that appeared in the payroll files were moved here, with Payroll keeping calculation of what this module approves. Pay transparency rules were checked against public sources in October 2026.

**Added in October 2026 (second review):** job architecture, job evaluation with a sample gender-neutral plan, the competency link, the survey library with licences and import profiles, public wage data by NOC, market definitions and pricing runs, market line, posting ranges, survey participation and total rewards valuation, from `docs/19`. CanDo ships no survey data, survey job descriptions or survey level definitions; each customer imports its own licensed copy.

**Open questions (closed in the owner's review, `docs/25`):**

- [x] Survey publisher templates: generic profiles; a template only with a customer's sample file and the publisher's permission (`docs/16` Q31)
- [x] Results derived from survey data shown to managers: not by default; the organization can switch it on, never for restricted surveys (`docs/16` Q32)
- [x] Default transparency settings: moderate (philosophy summary, own range, quartile)
- [x] Long-term incentive scope at launch: basic tracking, no valuations
- [x] Report formats first: BC pay transparency and the federal reports, both at launch
- [x] Self-identified data beyond gender in cycles and pay equity analysis: yes, with consent, groups of at least 10

**October 2026 review:** added public-sector and large-employer compensation (grids at scale, government frameworks, salary disclosure, bargaining costing), EU readiness and competitor comparison.
