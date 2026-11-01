# CanDo HRIS — 03 Payroll

Oct 17, 2026 · @Wael

> **Owner's review, 27 October 2026.** The decisions from the Module 03 review are in `docs/24-payroll-decisions.md`, which wins where this document differs. In short: CanDo calculates, prepares and reminds, and the employer moves the money, pays the remittances and uploads the filings (`docs/24` §2.1); pay runs are approved through the organization's route; failed checks hold only the affected employees unless the organization stops the run; vacation pay, proration and banked time are set per group of employees within the law; money owed is recovered only with written authorization; pay statements and slips follow CRA's delivery rule; HR reviews every ROE; the parallel run's length is the organization's setting, at least one period. The sections below are marked where they changed.

The Payroll module calculates, prepares the payment and remittance files for, and reports employee compensation (the employer sends the payments and remittances, `docs/24` §2.1) for every Canadian jurisdiction natively, with a framework for phased US expansion. This consolidated specification replaces the seven payroll files in the project; the April 16, 2025 combined file was the base.

## Overview, scope and regulatory framework

Payroll covers the full compensation lifecycle: initial pay setup, regular and off-cycle runs, special events, termination pay, remittances and year-end slips. It supports multiple countries, provinces, employment classifications and organization-specific pay policies, with complete audit trails.

**Jurisdictions:** all 13 Canadian provinces and territories plus federally regulated employers, including Quebec's separate system, at launch. US payroll follows the phased framework in this document. The architecture accepts further jurisdictions (for example Middle East) as country modules.

**Regulatory framework**

| Level | Bodies and rules |
| --- | --- |
| Federal | Canada Revenue Agency (CRA); Employment and Social Development Canada (ESDC); Income Tax Act; Canada Pension Plan Act; Employment Insurance Act; Canada Labour Code; PIPEDA; Bank Act |
| Provincial and territorial | Employment standards legislation; workers' compensation boards; employer health tax authorities; Revenu Québec and CNESST in Quebec |
| Other | Collective agreements; industry rules; provincial privacy laws |

**Design principles:** compliance with every statutory requirement; accuracy to CRA formulas and tables; flexibility for varied pay arrangements; auditability of every calculation and change; usability for each user type; integration with HR, time, benefits, finance and banks; future-proofing for regulatory change and new jurisdictions.

## Architecture and data model

The engine separates configurable rules from calculation code, and stores every result as effective-dated, non-overwritten transactions.

**Components**

| Component | Contents |
| --- | --- |
| Calculation engine | Earnings calculation; statutory deductions (CPP/QPP, EI/QPIP, income tax); other deductions; net pay |
| Rules repository | Pay rules; federal and provincial tax rules; statutory contribution rules; validation rules; effective-dated and versioned |
| Period management | Pay calendars, period definitions, cycle tracking |
| Supporting services | Security manager (authorization, access control, audit log); integration framework (APIs, import/export, connectors); reporting services (standard, ad-hoc, compliance, analytics) |
| Tiers | Database (secure transactional store); business logic (calculation and processing services); API; presentation |
| Deployment | Cloud with geographic redundancy; containerized services; separate development, test and production; encrypted channels |

**Employee payroll schema**

| Entity | Fields |
| --- | --- |
| Employee | EmployeeID (PK) |
| PersonalInfo | SIN (encrypted), date of birth, gender (statistical reporting), address, contact info |
| EmploymentInfo | Hire date, termination date, employment status, employment type, union membership, work location |
| PayrollInfo | Pay group, pay frequency, pay method, direct deposit details (encrypted), statutory exemptions |
| TaxationInfo | Tax province, TD1 amounts, TD1X amounts, additional tax, TP-1015 amounts (Quebec) |
| Position (one or more) | PositionID, job title, department, supervisor, pay type (hourly, salary, commission), pay rate, standard hours, overtime eligibility, allowance eligibility, work schedule |

**Transaction schema**

| Entity | Fields |
| --- | --- |
| PayrollPeriod | PayPeriodID (PK), start date, end date, pay date, frequency, pay group, status, year-end indicator |
| PayrollRun | PayrollRunID (PK), PayPeriodID (FK), run type (regular, off-cycle), status, created by and date, approved by and date, processed date |
| EmployeePayroll | EmployeePayrollID (PK), EmployeeID, PayrollRunID, gross earnings, taxable earnings, pre-tax deductions, tax deductions, post-tax deductions, net pay, payment reference |
| PayrollLineItem | LineItemID (PK), EmployeePayrollID, line type (earning, deduction, benefit), code, description, amount, hours, rate, GL account, tax treatment |

## Payroll processing engine

Every pay run follows the same seven-step workflow, with validations before calculation and approvals before money moves.

**Pay run workflow**

1. **Data collection:** time import, absence processing, new hires, terminations, compensation changes, one-time payments, adjustments.
2. **Pre-calculation validation:** missing time, excessive hours, missing employee or tax data, rate changes, payment method checks.
3. **Calculation:** gross-to-net for every employee in the run.
4. **Results review:** payroll register, exception report, variance against prior periods, high and low payments, missing deductions; corrections trigger recalculation with audit log.
5. **Approval:** multi-level, digitally signed, against a verification checklist.
6. **Finalization and disbursement:** EFT and cheque files, pay statements.
7. **Post-processing:** GL posting, remittance calculation, tax liabilities, period closed and archived.

**Gross-to-net sequence:** gross earnings → pre-tax deductions → add taxable benefits → income tax, CPP/QPP, EI/QPIP → post-tax deductions → net pay. Safeguards prevent negative net pay through minimum net thresholds and deduction priority rules when net pay cannot cover every deduction.

| Capability | Specification |
| --- | --- |
| Pay cycles and calendars | Weekly, bi-weekly, semi-monthly, monthly; several calendars per instance for different groups, companies or regions; annual calendar generation with holiday and banking-day adjustment; open, close, reopen and lock periods; in-progress, completed and future cycles kept separate |
| Run controls | Processing groups by department, location or employee type; progress tracking; configurable pre-flight and post-processing checklists; exception options (continue, hold affected employees, pause run); batch control totals, record counts and balancing; concurrent processing of pay groups with lock management |
| Multi-position | Hours, rates and premiums tracked per position; separate timesheet approvals; labour cost by department or cost centre; tax and employee-level deductions calculated on combined earnings; primary and secondary position eligibility; overtime rate per the jurisdiction's rule for people with several rates (`docs/17` §7.2), never a blended rate by default; allocation of employer costs by earnings, hours or formula; position-level and consolidated reporting |
| Retroactive processing | Backdated increases, reclassifications, corrected hours, late time, status changes; differential calculation instead of full reprocessing where appropriate; spans prior quarters and tax years; original, corrected and difference values with reason; jurisdiction-correct tax treatment; prior-period GL entries |
| Off-cycle runs | Terminations, bonuses and commissions, corrections, manual or emergency cheques, settlements and grievance awards, contract completion; own approval path; bonus and lump-sum tax methods; special direct deposit run, cheque, same-day transfer or wire; included in period, quarter and year-to-date totals |
| Final pay | Prorated final period; unpaid earnings; vacation payout; sick leave conversion where policy allows; notice and severance; final commissions and bonuses; recovery of advances, negative balances and unearned benefits (tuition, relocation, training) only with the employee's written authorization (`docs/24` §6.4); deadlines by jurisdiction (see reference tables); ROE and separation documents; benefit end dates and premium collection |

## Earnings

Earnings codes carry their own calculation, tax treatment, GL account and slip box, so a new pay element is configured rather than coded. Salary structures and progression rules live in Compensation (Module 04); Payroll consumes the approved rates.

| Earnings area | Specification |
| --- | --- |
| Pay types | Salaried (annual, monthly or period; annual-to-period conversion); hourly (rate × hours, rounding rules, minimum shift guarantees, standby and on-call pay); commission (flat, tiered, graduated; draws and recoverable draws; minimum guarantees; monthly payout on a bi-weekly calendar); piece rate (unit rate × production); hybrids |
| Proration | Calendar days, working days or scheduled hours, chosen for each pay group at setup within the law (`docs/24` §5.2); mid-period hire, termination, leave, rate change, schedule change; multiple changes in one period; leap years and month length |
| Premium and differential pay | Overtime 1.5×, 2× and higher; shift differentials (evening, night, weekend, split shift) as percentage, flat per hour, flat per shift or separate rate; skill premiums (first aid, licences, language); hazard, dirty work and height pay; lead hand, training and acting supervisor premiums; out-of-classification pay; call-back minimums |
| Allowances and reimbursements | Taxable: vehicle, tool, uniform, housing and living, northern benefits. Non-taxable: travel, mileage at CRA prescribed rates, per diems, relocation, professional memberships; receipts and approvals; GL coding |
| Taxable benefits | Personal use of company vehicle (standby charge); group term life over $50,000; interest-free and low-interest loans; board and lodging; employee discounts; gifts and awards; stock options; GST/HST included where required; per-pay, lump-sum or year-end inclusion |
| Statutory holiday pay | Eligibility by province; regular day's pay, average daily wage or percentage of earnings methods; premium for working the holiday; substitute days; provincial holiday calendars |
| Vacation pay | Accrual on eligible earnings at provincial minimums (4% to 8% depending on province and service); with each cheque or on scheduled vacation, chosen per group of employees by the organization's rules (`docs/24` §5.1); advances; payout on termination; rate change mid-year handled by period |
| Paid leave | Sick, personal, bereavement, jury duty, voting time |
| Time off in lieu | Overtime banking at 1:1, 1:1.5 or other rates; bank maximums; year-end payout, carryover with limits, or a mix, per the organization's policy for each group within the law (`docs/24` §5.3); minimum usage increments; payout on demand, scheduled or at termination at original or current rate |
| Other variable pay | Bonuses and incentives on schedule or off-cycle; signing and retention bonuses; tips and service charges; prevailing wage and certified payroll (US contracts) |

## Canadian statutory deductions and taxation

Statutory calculations follow CRA payroll formulas (T4127) and Revenu Québec equivalents, with rates, maximums and brackets loaded as effective-dated tables each January and whenever governments change them mid-year.

| Program | Specification |
| --- | --- |
| CPP / QPP | Basic exemption ($3,500 a year, prorated per pay period); contribution rate and maximum pensionable earnings; enhanced CPP; second additional contribution (CPP2/QPP2) on earnings between the first and second ceilings, in force since 2024 and missing from the source specs; pensionable earnings identification and exclusions; exemptions for under 18, over 70 (CPP) and disability pension recipients; year-to-date tracking; multiple employers; over-contribution handling; QPP rate differential |
| EI / QPIP | Insurable earnings including vacation pay; rate and maximum insurable earnings; employer share at 1.4× or a reduced rate for registered wage-loss plans, with the employee share of the reduction; reduced EI rate for Quebec employees plus QPIP employee and employer premiums; non-insurable employment; over-contribution handling |
| Federal income tax | TD1 claim amounts and credits; brackets and indexing; annualization; Canada employment amount and other non-refundable credits; additional tax requested; non-resident withholding (15% or 25%, Regulation 102 and 105, treaty rates, NR4); commission method (TD1X); pension income; directors' fees |
| Provincial and territorial tax | Provincial brackets, credits, surtaxes and reductions; territorial credits and northern residents deductions; Ontario Health Premium; Quebec provincial tax calculated entirely separately from TP-1015.3 (TP-1015.F formulas) |
| Employer health and payroll taxes | Ontario EHT (exemption threshold, 1.95% top rate, associated employer allocation, instalments, annual return); BC EHT (graduated rates on BC remuneration); Manitoba Health and Education Levy; Newfoundland and Labrador Health and Post-Secondary Education Tax; Quebec Health Services Fund (tiered by payroll size, sector reductions); NWT and Nunavut payroll tax; due-date tracking and returns |
| Workers' compensation | Provincial board rate tables by industry classification; assessable earnings and maximums; experience rating; cost allocation by department or project; monthly, quarterly or annual remittance; annual reconciliation and electronic filing |
| Quebec employer contributions | Workforce Skills Development (WSDRF); CNESST labour standards and health and safety contributions; pay equity reporting |
| Indigenous tax exemption | Indian Act s.87 exemption for eligible income situated on reserve, with connecting-factor documentation; TD1-IN on file; CPP not deducted on exempt income unless the employer elects coverage; EI always deducted, because EI premiums are not exempt under s.87; T4 and T4A reporting codes |

**Tax calculation methods:** periodic (regular earnings); bonus method for lump sums; TD1X averaging for commission and irregular income; separate calculation for non-periodic amounts; simultaneous federal and provincial calculation with tax-on-tax where it applies; income from all positions aggregated so no position is under-withheld; mid-year rate changes spread over remaining periods; manual override with audit.

**Special payment treatment:** bonuses (method notified to employee); vacation pay in-period, lump sum or with each cheque; retiring allowances split into eligible (pre-1996 service) and non-eligible portions with direct transfer to an RRSP and special withholding; current-year and prior-year retroactive pay with lump-sum method and correct slip reporting.

## Jurisdiction coverage: federal, 10 provinces, 3 territories

The engine must calculate, remit and report correctly for every Canadian jurisdiction. CRA administers income tax for every province and territory except Quebec; employer and territorial payroll taxes, workers' compensation and employment standards are separate in each.

| Jurisdiction | Income tax and slips | Employer or payroll tax | Workers' compensation | Employment standards | Payroll notes |
| --- | --- | --- | --- | --- | --- |
| Federal (Canada Labour Code employers) | Tax of the province or territory of employment, via CRA | By province of employment | Provincial boards; federal public servants under the Government Employees Compensation Act | Canada Labour Code Part III | Covers most First Nations band council employment; 10 paid medical leave days |
| Newfoundland and Labrador | CRA; T4 | Health and Post-Secondary Education Tax above its exemption | WorkplaceNL | Labour Standards Act | Provincial tax change effective 1 July 2026 |
| Prince Edward Island | CRA; T4 | None | WCB of PEI | Employment Standards Act | Provincial tax change effective 1 July 2026 |
| Nova Scotia | CRA; T4 | None | WCB Nova Scotia | Labour Standards Code | — |
| New Brunswick | CRA; T4 | None | WorkSafeNB | Employment Standards Act | Officially bilingual province |
| Quebec | Revenu Québec for provincial tax, CRA for federal; RL-1 and T4 | Health Services Fund; CNESST; 1% training rule above the payroll threshold | CNESST | Act respecting labour standards | QPP, QPIP, reduced EI; federal Quebec abatement in federal tax |
| Ontario | CRA; T4 | Employer Health Tax | WSIB | Employment Standards Act, 2000 | Ontario Health Premium withheld with provincial tax |
| Manitoba | CRA; T4 | Health and Education Levy | WCB Manitoba | Employment Standards Code | — |
| Saskatchewan | CRA; T4 | None | WCB Saskatchewan | The Saskatchewan Employment Act | — |
| Alberta | CRA; T4 | None | WCB-Alberta | Employment Standards Code | — |
| British Columbia | CRA; T4 | Employer Health Tax | WorkSafeBC | Employment Standards Act | Provincial tax change effective 1 July 2026 |
| Yukon | CRA, territorial tax; T4 | None | Yukon workers' compensation board | Employment Standards Act | Northern residents deduction zones |
| Northwest Territories | CRA, territorial tax; T4 | 2% payroll tax withheld from employees and remitted to the territory; not reported on the T4 | WSCC | Employment Standards Act | Northern residents deduction |
| Nunavut | CRA, territorial tax; T4 | 2% payroll tax withheld from employees and remitted to the territory; employees who normally work outside Nunavut are exempt below $5,000 earned there | WSCC | Labour Standards Act | Nunavut Day (9 July); Inuktut communications |

Sources: CRA [T4127](https://www.canada.ca/en/revenue-agency/services/forms-publications/payroll/t4127-payroll-deductions-formulas.html), the Government of Nunavut [payroll tax page](https://www.gov.nu.ca/en/taxation-and-insurance/payroll-tax), [Employment Hero on the July 2026 changes](https://employmenthero.com/en-ca/blog/cra-july-tax-changes-payroll-deductions/).

**Canada Child Benefit and other CRA benefits:** the CCB, GST/HST credit and similar benefits are paid by CRA directly to families; payroll neither deducts nor calculates them. Payroll's part is accurate T4 and RL-1 income, which feeds family net income, and employee self-service can point to CRA's benefit calculators.

## Other deductions and contributions

| Category | Specification |
| --- | --- |
| Registered pension plans | Defined benefit and defined contribution; employee and employer contributions; pre-tax treatment; pension adjustment (PA) calculation for T4 box 52; past service and buy-back contributions; contribution limits; plan-specific eligibility and waiting periods; multi-employer and union plans |
| Group savings | Group RRSP (pre-tax at source when employer can reduce withholding), group TFSA, employee share purchase plans, DPSP; employer match rules and vesting; contribution room checks |
| Union dues | Rand formula; fixed, percentage or hours-based dues; initiation fees and special assessments; multiple locals; union remittance reports; T4 box 44 reporting |
| Benefit premiums | Employee share of health, dental, life, disability and other premiums; pre-tax vs post-tax handling; employer-paid life and other taxable benefits added to income; arrears when pay is insufficient; flex credit and health spending account allocations from Module 05 |
| Garnishments and court orders | Family support orders (highest priority), CRA requirements to pay, federal garnishments (FENA), provincial wage garnishments; jurisdiction-specific exemption calculations; payroll confirms the first deduction of each order (`docs/24` §6.1); multiple-order priority and proration; remittance to courts and agencies; employee notification |
| Recoveries | Salary advances, employee loans (with taxable interest benefit where applicable), overpayment recovery (gross or net, current or prior year, with ESA-compliant written consent and per-period limits), equipment and other recoveries |
| Voluntary deductions | Charitable donations with receipt tracking, social club, parking, purchase plans, other employee-authorized deductions with start and end dates and goal amounts, started or stopped in self-service with the approval the organization sets (`docs/24` §6.2) |

**Deduction sequencing:** a configurable priority order applies when net pay cannot cover everything — statutory deductions first, then court-ordered support, then other garnishments, then pre-tax plan deductions, then other authorized deductions. Shortfalls create arrears balances recovered as each deduction code says (take in full next pay, spread, HR decides, or not recovered; write-offs with a reason; `docs/24` §6.3), and no deduction may take pay below the minimum protected by the applicable employment standards or garnishment legislation.

## Time, overtime and leave inputs

Payroll consumes approved time and leave from Module 06; it does not own scheduling or timekeeping. This section specifies what payroll needs from those inputs and how it values them.

**Time import:** approved timesheets, punches converted to paid hours, shift and premium codes, cost allocation codes, retroactive time corrections with automatic recalculation of the affected periods, and a cut-off with late-time handling (pay next period or off-cycle).

**Overtime calculation by jurisdiction:**

| Rule | Coverage |
| --- | --- |
| Daily and weekly thresholds | Ontario 44 h/week; BC 8 h/day and 40 h/week with double time after 12 h/day; Alberta 8 h/day or 44 h/week, whichever gives more; Quebec 40 h/week; federal 8 h/day and 40 h/week; other provinces from the rules table |
| Averaging agreements | Multi-week averaging where a permit or written agreement exists |
| Collective agreement rules | Thresholds, multipliers, call-back, standby and shift premiums overriding statutory minimums where more generous |
| Banked time | Time off in lieu at overtime rate, bank limits and mandatory payout dates |
| Regular rate | Inclusion of shift premiums and non-discretionary bonuses where jurisdiction requires |
| Exempt classes | Managers, professionals and other excluded classes flagged per jurisdiction |

**Statutory holidays:** holiday lists by jurisdiction and year; eligibility rules (days worked in qualifying period, work before and after); holiday pay formulas per province (for example 1/20 of four weeks' wages in Ontario; average day's pay in BC); premium rate and substitute day when worked; holidays falling on non-working days.

**Leave valuation:** vacation accrual by percentage or hours with minimum entitlements by jurisdiction and service; vacation pay on termination; sick leave paid days (federal 10 days, BC 5 days, Quebec 2 paid days, and others as legislated); top-ups for maternity, parental and other EI-supported leaves; ROE triggers for interruption of earnings; continuation of benefits and pension contributions during statutory leave.

## Disbursement and pay statements

**Payment methods:** direct deposit (Payments Canada CPA Standard 005 files, with multiple accounts per employee split by amount or percentage); cheques with MICR printing, positive pay files and void and reissue controls; pay cards for unbanked employees; manual and emergency cheques recorded in payroll; US dollar payments for cross-border staff.

**Banking controls:** bank account changes require verification and a waiting period or notification to the previous address; prenotification where the bank supports it; maximum payment thresholds per employee per run; dual approval before file release; rejected deposit handling with automatic reissue; reconciliation of funded amounts to bank confirmations.

**Pay statements:**

| Element | Requirement |
| --- | --- |
| Content | Employer name, pay period and pay date, hours and rates by earning type, gross pay, each deduction itemized, net pay, year-to-date totals, vacation and leave balances, employer contributions (optional) |
| Jurisdiction rules | Statement content mandated by each province's employment standards (for example vacation pay shown separately in Ontario and BC) |
| Delivery | By CRA's rule (`docs/24` §7.1): self-service for current employees, paper on request; former employees and people on extended leave electronically only with consent, otherwise paper; email only with consent. Notifications carry a link, never pay data |
| Language and access | English and French; WCAG 2.1 AA; plain-language earning and deduction descriptions |
| History | All past statements and slips retained and viewable for the record retention period |

**Remittances:** CRA source deductions by remitter type (quarterly, regular monthly, accelerated threshold 1 or 2) with due dates calculated automatically; Revenu Québec remittances; employer health taxes; union, pension, benefits and garnishment payees; payment files and remittance vouchers generated and reconciled; reminders before each due date on the organization's days (`remittances.reminder_days`). The employer pays every remittance (`docs/24` §3.2).

## Specialized features

**Off-cycle and adjustment runs:** manual cheques, bonus runs, corrections, reversals and voids; retroactive pay calculated period by period against historical rates and rules with the lump sum taxed correctly; termination and final pay runs on the legislated deadline (Module 11 supplies the separation event).

**Sector and employer-type features:**

| Employer type | Features |
| --- | --- |
| Indigenous organizations and First Nations governments | s.87 eligibility tracking by employee and position; connecting-factor evidence; band council and nation entity structures; CPP opt-in elections; funding agreement cost tracking |
| Unionized employers | Multiple collective agreements per employer; wage grids with step progression; premiums, call-back and standby; retroactive settlements after ratification; seniority-based entitlements; dues remittance and union reports |
| Non-profits and charities | Grant and fund cost allocation by percentage or hours; restricted funding tracking; funder-specific reports; T4A for honoraria |
| Education | 10-month pay spread over 12 months with summer holdback; substitute and occasional teacher pay |
| Healthcare | Shift differentials, weekend and on-call premiums, float pool rates, multiple concurrent positions |
| Construction | Union hall dispatch, travel and board allowances, multi-site cost allocation, CCQ reporting for Quebec construction, union trust fund remittances |
| Seasonal and agricultural | Piece rates, harvest bonuses, temporary foreign worker housing deductions within program limits |

**Multi-jurisdiction:** employees who work in more than one province are taxed based on the province of the establishment they report to, with employer health tax and workers' compensation allocated by work location; mid-year province changes handled correctly for slips.

**Remote and northern:** isolated post and northern allowances; northern residents travel benefits as taxable or exempt per CRA zones; housing benefits.

**Other payees:** directors' fees, T4A recipients (honoraria, contractors where the employer issues slips), deceased employee payments (to the estate with correct slip treatment), and students under work-study programs.

## Year-end processing

**Slips and returns:**

| Form | Coverage |
| --- | --- |
| T4 and T4 Summary | All boxes and other information codes, including box 52 pension adjustment, box 44 union dues, s.87 exempt income codes, and dental benefits coverage code (box 45) |
| T4A and T4A Summary | Pension and other income, honoraria, retiring allowances, fees for services where reportable |
| RL-1 and RL-1 Summary | Quebec employment income with all cases, plus RL-2 where pensions are paid |
| NR4 | Non-resident amounts |
| T4 amendments and cancellations | After-filing corrections with audit history |
| PIER | Pensionable and Insurable Earnings Review to identify CPP and EI under-deductions before filing |

**Filing and distribution:** electronic filing in CRA XML and Revenu Québec formats (CRA requires electronic filing for more than five slips of a type since 2024); validation against schemas before submission; slips delivered by CRA's rule (`docs/24` §7.1) by the last day of February; reprints and duplicate requests self-service.

**Reconciliations:** remittances to slip totals (PD7A reconciliation); employer health tax annual returns; workers' compensation annual statements; benefits taxable amounts confirmed with Module 05.

**Year-end rollover:** new statutory tables loaded and tested before the first January pay date; year-to-date counters reset with prior-year history locked; TD1 change reminders sent to employees; first-run comparison report highlighting net pay changes caused by rate updates.

**Records of Employment:** prepared by CanDo from payroll data, reviewed by HR (reason code and comments) and uploaded by the employer to ROE Web (`docs/24` §7.4), within five calendar days after the end of the pay period in which the interruption occurred (or by the legislated alternative deadline), with insurable earnings and hours by pay period, reason codes and amendment handling.

## Compliance, audit and error detection

**Pre-run validation** (`docs/24` §4.2: affected employees held with a reason and paid off-cycle once fixed, or the whole run stopped, as the organization chose; a missing TD1 follows FB-028): missing bank details; employees with no rate, no tax province or terminated status but active pay; hours over threshold without overtime; minimum wage breaches by jurisdiction; negative net pay; deductions without authorization documents; duplicate employees or bank accounts.

**Variance and anomaly detection:**

| Check | Rule |
| --- | --- |
| Period-over-period variance | Gross, net, tax and deductions compared with the prior period and with the same period last year; configurable percentage and dollar thresholds |
| Statutory reasonableness | CPP, EI and tax amounts checked against expected ranges for the earnings; maximums reached early or not at all flagged |
| Outliers | Unusually high payments, rates or hours compared with peer group in the same job |
| Fraud indicators | Shared bank accounts, recent bank change followed by a large payment, payments to terminated employees, manual payments outside normal pattern |
| AI-assisted review | Anomaly scoring with an explanation of contributing factors; payroll staff confirm or dismiss, and feedback tunes thresholds; the model never changes a payment |

**Audit trail:** every change to employee pay data, rules, rates and payments records who, what, when, before and after values and the reason; payroll results are immutable once finalized, with corrections posted as new transactions; audit reports by employee, user, field and date range; logs retained for the record retention period and protected from alteration.

**Compliance monitoring:** dashboard of remittance due dates, filings and their status; alerts when legislation changes affect configured rules; statutory table version in force for every calculation; minimum wage and pay equity checks; employment standards pay timing (pay frequency, final pay deadlines); payroll records kept for at least the longest applicable retention period (CRA six years from the end of the year; provincial ESA periods).

## Reporting and analytics

**Standard reports:**

| Category | Reports |
| --- | --- |
| Run reports | Payroll register, pre-run and post-run variance, exceptions, net pay and payment method summary, deduction register, earnings register |
| Statutory | Remittance summaries (CRA, Revenu Québec, EHT, WSIB/WCB), PD7A reconciliation, T4/RL-1 reconciliation, ROE status, PIER |
| Accounting | General ledger journal by cost centre, project and fund; labour distribution; accruals; benefits and pension cost |
| Third-party | Union dues by local, pension contributions, benefits premiums, garnishment remittances |
| Workforce cost | Total cost of employment, overtime cost and trends, premium pay, cost per FTE, budget vs actual |
| Audit | Change history, user activity, bank changes, manual payments, overrides |

**Dashboards:** current run status and approvals; error rates and corrections per run; overtime and premium cost trends by department; remittance calendar; year-to-date labour cost vs budget.

**Self-service reporting:** ad hoc report builder with field-level security enforced, saved and scheduled reports, export to Excel, CSV and PDF; all reports respect the same role permissions as the payroll screens, with sensitive fields (SIN, bank) masked by default. Cross-module analytics are specified in Module 12.

## Integrations and API

**Internal (shared employee record and event bus):**

| Module | Payroll receives | Payroll sends |
| --- | --- | --- |
| 01 Core HR | Hires, job and position changes, rates, cost centres, status, addresses, banking | Pay history, YTD totals |
| 02 Recruitment & Onboarding | New hire record with TD1, banking and start date | Payroll setup complete flag |
| 04 Compensation | Approved salary changes, bonuses, incentive payouts, effective dates | Actual paid amounts for comp statements |
| 05 Benefits | Enrolments, premium deductions, taxable benefit values, flex credits | Benefits deductions taken, arrears |
| 06 Time, Attendance & Leave | Approved hours, premiums, leave taken and balances | Banked time payouts, valuations |
| 11 Offboarding | Termination date, reason, severance and notice amounts | Final pay results, ROE status |
| 12 Analytics | — | Labour cost and payroll data |

**External:**

| System | Integration |
| --- | --- |
| Banks | CPA 005 direct deposit files, positive pay, returns |
| CRA | My Business Account payments, XML slip filing, ROE Web via Service Canada |
| Revenu Québec | Slip filing and remittances |
| Accounting / ERP | GL journal export or API (QuickBooks, Sage, Xero, Microsoft Dynamics, NetSuite, others via mapping) |
| Benefits carriers and pension administrators | Contribution files and remittances |
| Unions | Dues files and reports |
| Time clocks | Through Module 06 |

**API:** REST endpoints for employees' pay data (read), payroll results, deductions setup, GL export and run status, secured with OAuth 2.0 and scoped tokens; webhooks for run finalized, payment released and remittance due; bulk import and export templates with validation; versioned API with deprecation notices; rate limiting and full request logging.

## Security and access control

Payroll applies the shared security services in Module 00 with stricter defaults.

**Data protection:** TLS 1.2 or higher in transit; AES-256 at rest; field-level encryption for SIN, bank accounts and garnishment details; masked display (last three digits) with reveal logged; data residency in Canadian data centres; encrypted backups with tested restores.

**Payroll roles:**

| Role | Access |
| --- | --- |
| Payroll administrator | Configure rules, process runs, view all pay data in assigned entities |
| Payroll processor | Enter data, run calculations, prepare reports; cannot approve own runs or change own pay |
| Payroll approver | Review and approve runs and payment release |
| Finance | GL, cost and remittance reports; no individual pay data changes |
| HR | View compensation and deductions as needed; no payroll processing |
| Manager | Team cost summaries only, where configured |
| Employee | Own statements, slips, TD1 and banking via self-service |
| Auditor | Read-only, time-limited |

**Controls:** segregation of duties (no user can both change bank details and release payments, or process and approve the same run); dual approval for rule changes, bank file release and off-cycle payments over a threshold; multi-factor authentication for all payroll roles; session timeouts; IP and device restrictions available; quarterly access recertification; privileged access logged and reviewed.

**Privacy:** collection limited to what payroll needs; SIN used only for statutory purposes; employee access to their own payroll records on request; retention schedule enforced with secure destruction; breach notification under PIPEDA and provincial law (including Quebec Law 25).

## User experience and configuration

**Payroll workspace:** run calendar showing every pay group's status; guided run wizard (inputs → calculate → review exceptions → approve → release); exception queue with one-click drill-down from any total to the employee transactions behind it; side-by-side comparison with the prior period; bulk edits with preview; keyboard-driven data entry for high-volume processors.

**Employee self-service:** pay statements and slips; TD1 federal and provincial forms completed online with e-signature; banking changes with verification; direct deposit split; pay calculator to model net pay for changes in claim amounts or deductions; questions routed to payroll as cases.

**Manager view:** team labour cost, overtime trends and approvals pending, without individual pay details unless permitted.

**Configuration without code:** pay groups and calendars; earning and deduction codes with tax, CPP, EI, vacation and pension treatment flags; GL mapping; collective agreement rules; approval chains; notification templates; validation thresholds. Configuration changes go through a sandbox with test calculations, approval and effective dating before they reach production.

**Accessibility and language:** WCAG 2.1 AA; English and French throughout, including statements and slips; plain-language help text for every earning and deduction code.

## Implementation

**Build approach:** the calculation engine, rules repository and statutory tables run on a conventional backend with automated regression tests against CRA and Revenu Québec published examples; a low-code front end (such as the Bubble option in Module 02) can host screens and self-service but must not perform calculations.

**Customer implementation phases:**

| Phase | Activities |
| --- | --- |
| 1. Discovery | Pay groups, entities, jurisdictions, collective agreements, earning and deduction inventory, GL structure, remitter types, legacy system review |
| 2. Configuration | Company and pay calendars, codes and treatments, rules, approval chains, GL mapping, bank setup |
| 3. Data migration | Employee master and pay data, banking, TD1s, deductions and arrears, current-year YTD balances by employee and code, leave balances, history for reports |
| 4. Testing | Unit tests of each rule, scenario tests by employee type, parallel runs comparing old and new results to the cent |
| 5. Training | Payroll staff, approvers, managers, employees; job aids in English and French |
| 6. Go-live | Cut-over checklist, first live run with heightened review, hypercare for the first three pay cycles |

**Parallel run standard:** at least `payroll.parallel_run_periods` full cycles (1 by default, never fewer; an organization can ask more) with every difference explained and accepted by a named person before the first live run (`docs/24` §4.4).

**Go-live timing:** the start of a calendar year avoids YTD migration; start of a quarter simplifies remittance reconciliation; mid-quarter go-lives are supported with full YTD loading and reconciliation.

**Typical durations:** small single-province employer 6–10 weeks; multi-province or unionized employer 12–20 weeks; large multi-entity with Quebec and complex agreements 20–30 weeks. These are planning estimates, not commitments.

## International expansion: Europe first

Europe is the first market after Canada; US payroll is no longer on the roadmap unless a customer requires it. Country rules stay in the rules repository, so a country is added as a country pack.

| Area | Requirement for a European country pack |
| --- | --- |
| Payroll | Partner payroll providers per country first, fed from CanDo's employee record; native calculation only for priority countries |
| Statutory data | Country tax and social security identifiers, contribution bases, payslip content rules, year-end reporting |
| Pay transparency | EU Pay Transparency Directive (transposition deadline 7 June 2026): pay ranges before interview, no pay history questions, gender pay gap reporting, employee right to pay information |
| Privacy | GDPR lawful basis, data protection impact assessments, data subject rights, EU data region, transfer safeguards |
| Working time | Working Time Directive limits and national rules in Module 06 rule sets |
| Employee representation | Works council consultation before changes to pay systems, monitoring or organization |
| AI | Employment AI is high-risk under the EU AI Act; obligations apply from 2 December 2027 after the 2026 Digital Omnibus |
| US (optional) | W-4, FICA, FUTA, state taxes, W-2 only if a customer needs it; earlier US requirements are retained in the source files |

## CRA and Revenu Québec source documents

The engine is built to the government specifications, not to secondary summaries. Each is loaded when it is published and tested before the first pay date it applies to.

| Document | Publisher | Use in CanDo |
| --- | --- | --- |
| T4127 Payroll Deductions Formulas: 122nd edition (1 January 2026) and 123rd edition (1 July 2026) | CRA | The calculation specification for federal, provincial (except Quebec) and territorial tax, CPP, CPP2 and EI, including bonus, retroactive and commission methods; two editions a year |
| T4032 Payroll Deductions Tables and T4008 Supplementary Tables | CRA | Cross-check fixtures for each province and territory |
| Payroll Deductions Online Calculator (PDOC) | CRA | Independent test oracle for regression suites |
| T4001 Employers' Guide: Payroll Deductions and Remittances | CRA | Remitter types, due dates, special payments, CPP and EI rules |
| T4130 Employers' Guide: Taxable Benefits and Allowances | CRA | Benefit and allowance treatment codes |
| RC4120 (T4 slip and summary) and RC4157 (T4A) | CRA | Box and code mapping, XML specifications |
| TD1 federal, provincial and territorial forms; TD1X; TD1-IN | CRA | Claim amounts; commission method; s.87 exemption declaration |
| Indian Act exemption guidelines and First Nations payroll pages | CRA | Connecting factors; CPP election; EI always applies |
| Records of Employment guide and ROE Web specifications | Service Canada | ROE blocks, codes and deadlines |
| Source deduction formulas, employer guide, RL-1 guide and software requirements (IN-412-V) | Revenu Québec | Quebec engine, RL slips and the annual authorization and certification requested by 1 February |
| Payroll tax guides (NT, NU) and employer health tax guides (ON, BC, MB, NL, QC) | Territories and provinces | Payroll taxes outside CRA |

## 2026 statutory values

Loaded and checked in October 2026. Provincial and territorial brackets and credits are loaded from the T4127 tables in full rather than retyped here.

| Item | 2026 value |
| --- | --- |
| CPP contribution rate | 5.95% employee and employer |
| Year's maximum pensionable earnings (YMPE) | $74,600; basic exemption $3,500; maximum contribution $4,230.45 each |
| CPP2 rate and ceiling | 4% on earnings between $74,600 and the YAMPE of $85,000; maximum $416 each |
| EI employee rate outside Quebec | 1.63% on maximum insurable earnings of $68,900; maximum premium $1,123.07; employer 1.4× ($1,572.30) |
| EI employee rate in Quebec | 1.30%; maximum premium $895.70 |
| QPIP | Maximum insurable earnings $103,000; employee 0.430%, employer 0.602% |
| Federal brackets | 14% to $58,523; 20.5% to $117,045; 26% to $181,440; 29% to $258,482; 33% above |
| Federal basic personal amount | $16,452, reducing to $14,829 for income above $258,482 |
| Canada employment amount | $1,501 |
| Mid-year change | 123rd edition, effective 1 July 2026: provincial tax changes in BC, NL and PEI |

Sources: [CRA T4127](https://www.canada.ca/en/revenue-agency/services/forms-publications/payroll/t4127-payroll-deductions-formulas.html), [Carleton University statutory deductions](https://carleton.ca/hr-payroll/your-pay-information/statutory-deductions/), [TaxTips federal rates](https://taxtips.ca/taxrates/canada.htm), [Teamed on EI and QPIP 2026](https://www.teamed.global/ca-employment-law/cpp-ei-payroll-2026).

## Reference tables

**Tables the rules repository maintains (all effective-dated and versioned):** federal and provincial tax brackets, rates, credits and indexing factors; CPP/QPP rates, exemption and ceilings (first and second); EI and QPIP rates and maximums; employer health tax thresholds and rates by province; workers' compensation rates by board and classification; minimum wages by jurisdiction and class; statutory holidays by jurisdiction and year; overtime thresholds; vacation and sick leave entitlements; prescribed interest rates for taxable loan benefits; automobile benefit rates; northern residents zones; remittance thresholds and due dates.

**2023 values carried from the source specification.** These are retained as regression-test fixtures only; the values in force for 2026 are in the section above.

| Item | 2023 value |
| --- | --- |
| CPP employee and employer rate | 5.95% each |
| CPP year's maximum pensionable earnings | $66,600 |
| CPP basic exemption | $3,500 |
| CPP maximum employee contribution | $3,754.45 |
| QPP rate | 6.40% each |
| EI employee rate (outside Quebec) | 1.63% |
| EI employee rate (Quebec) | 1.27% |
| EI maximum insurable earnings | $61,500 |
| EI maximum employee premium (outside Quebec) | $1,002.45 |
| EI employer multiplier | 1.4× employee premium |
| QPIP rates | 0.494% employee, 0.692% employer |
| Federal basic personal amount | $15,000 (maximum) |
| Federal brackets | 15% to $53,359; 20.5% to $106,717; 26% to $165,430; 29% to $235,675; 33% above |
| Ontario EHT exemption | $1,000,000 for eligible employers |

CPP2 did not exist in 2023, so the 2023 fixtures do not test it; current-year fixtures must add it.

## Checklists, year-end calendar and worked examples

**Per-run checklist:**

- [ ] Pay calendar confirmed and cut-off communicated
- [ ] New hires, terminations and changes since last run reviewed
- [ ] Time and leave imported and approved
- [ ] Pre-run validation exceptions cleared
- [ ] Calculation run and variance report reviewed
- [ ] Exceptions explained or corrected
- [ ] Run approved by a second person
- [ ] Bank file released and confirmed
- [ ] GL journal posted
- [ ] Remittances scheduled
- [ ] Statements published to employees

**Year-end calendar:**

| When | Task |
| --- | --- |
| November | Confirm last pay date of the year; run PIER review; check CPP and EI maximums; review taxable benefits with Module 05 |
| December | Final run of the year; post year-end adjustments; lock current-year data after final run |
| Early January | Load and test new statutory tables; send TD1 update reminders; first-run comparison report |
| By last day of February | File T4, T4A and RL-1 slips and summaries; distribute slips to employees |
| March | Employer health tax annual returns (for example Ontario by 15 March, BC by 31 March); workers' compensation annual reconciliations by board deadline |
| Ongoing | Amendments and reissues as corrections arise |

**Worked example (2023 fixture rates, Ontario, bi-weekly, 26 periods):** an employee earns $2,500 gross with a $100 group RRSP deduction at source.

| Step | Calculation | Result |
| --- | --- | --- |
| CPP pensionable earnings | $2,500 (RRSP does not reduce CPP earnings) | $2,500.00 |
| Period basic exemption | $3,500 ÷ 26, truncated to the cent (CRA rule) | $134.61 |
| Employee CPP | ($2,500 − $134.61) × 5.95% | $140.74 |
| Employee EI | $2,500 × 1.63% | $40.75 |
| Income subject to tax | $2,500 − $100 RRSP | $2,400.00 |
| Federal and Ontario tax | T4127 formula on $2,400 annualized, claim code 1, with CPP and EI credits | From the engine |
| Employer CPP | Matches employee | $140.74 |
| Employer EI | $40.75 × 1.4 | $57.05 |

The example is a test case for the engine: the tax figure is produced by the T4127 implementation and compared with the CRA Payroll Deductions Online Calculator for the same inputs.

## Public-sector and government payroll

Municipalities, provincial and territorial agencies, school boards, health authorities and First Nations governments bring requirements most SME payroll tools never meet.

| Area | Requirement |
| --- | --- |
| Many agreements at once | Dozens to hundreds of collective agreements per employer (for example CUPE locals, fire and police associations, transit, nurses, teachers); each with its own grids, premiums and retro terms read from the agreement library |
| Retroactive settlements | Mass recalculation across several years after ratification or an arbitration award, period by period at historical rules, with interest where awarded and correct slip and pension adjustments |
| Public-sector pension plans | Defined benefit contributions with different rates below and above the YMPE; plan-specific pensionable earnings; remittance files for OMERS, HOOPP, LAPP, BC Municipal Pension Plan, public service plans and others; pension adjustments and past service adjustments |
| Elected and appointed officials | Council and board remuneration and allowances in their own pay groups, with CPP, EI and tax treatment set per CRA rules and public disclosure |
| Emergency services | Volunteer firefighter and emergency volunteer payments using CRA's exemption; platoon schedules; call-out, standby and acting pay |
| Salary disclosure | Annual public-sector salary disclosure lists by statute and threshold (for example Ontario's $100,000 list) |
| Funding agreements | Cost allocation to programs and funding sources, including Indigenous Services Canada funding for First Nations |
| Control and audit | Segregation of duties, audit trails and payroll accuracy measures that satisfy auditors general; parallel runs and staged rollout for large conversions |
| Volume | Pay groups of tens of thousands; the enterprise targets in Module 00 apply |

## Quebec

Module 00 sets out the Quebec assessment. For payroll, Quebec means a second tax engine built to Revenu Québec's formulas, RL-1 slips and the RLZ-1.S summary, QPP and QPIP in place of CPP and EI parts, HSF, CNESST and training-law contributions, and annual software authorization and certification by 1 February. The recommended path is the Quebec data model and French interface from day one and Quebec payroll in phase 2, with an export to a certified Quebec payroll provider in the interim.

## People in several positions

Detailed design: `docs/20` §4, which takes precedence.

- **A rate per position.** Each position keeps its own salary or hourly rate and rate components. Overtime follows the jurisdiction's rule for people with several rates, never a blended rate by default.
- **Allowances and duty pay per position.** Car allowances, stipends, on-call pay, duty rates and duty premiums are pay items of one position. Each is effective-dated and has a source, and a manual item needs a reason. With a duty rate, hours spent on a duty (driving, interpreting) are paid at the duty's rate. Time lines name the duty worked.
- **One-time payments.** A bonus, award or adjustment names its position, or is shared across the person's positions by earnings in the period, to the cent.
- **Costing.** A pay item is costed with its position, or to its own funding lines (a stipend paid from a separate grant). A position can be funded by several sources, and one source can fund portions of several positions (`docs/17` §8).

## How CanDo compares

| Vendor | Canadian payroll position (October 2026) | What CanDo takes from it |
| --- | --- | --- |
| Dayforce | Native; chosen by the Government of Canada for HR and pay | Enterprise and public-sector scale is a buying criterion |
| ADP Workforce Now | Native; French options for Bill 96; built-in error detection | Pre-run validation and French by default |
| UKG Pro | Native Canadian payroll with its own Canadian compliance team; UKG Pro Workforce Management used by municipalities such as the City of Hamilton | Unionized time-to-pay depth must match |
| HiBob | Native payroll in the US and UK only; Canada through Payroll Hub sync to ADP | Native Canadian payroll is a differentiator against HR-first suites |
| BambooHR | No Canadian payroll | Same |
| Humi by Employment Hero | Native, s.87 applied automatically, ROEs within one business day; Quebec on a separate product; stat holiday pay and ROE block 15B manual | One product for all of Canada; automate stat pay and ROE blocks |
| Payworks, Wagepoint | Canada-only payroll specialists; Wagepoint does not file the RL-1 summary | Complete Quebec filing when Quebec ships |
| Rise | Tax-exempt pay for Indigenous organizations; payroll by funding source | s.87 and funding allocation as standard |

Detail and sources: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Source reconciliation

**Primary source:** CanDoHRIS\_Payroll\_Module\_Combined\_FULL April 16 2025.docx (summary spec, detailed spec, Canadian implementation guide and appendices).

**Cross-checked against:** Payroll Module 1.docx; Can Do HRIS Payroll Module 2.docx; CanDoHRIS\_Payroll\_Module\_Combined\_FULL.docx; CanDo\_HRIS\_Payroll\_Module.docx; CanDoHRIS\_Payroll\_Module\_Full.docx; CanDoHRIS\_Payroll\_Module\_Complete.docx; CanDoHRIS\_Payroll\_Module\_FULL\_REDO.docx. The April 16 file contains everything in the earlier versions; no content unique to an earlier version was found.

**Changes made during consolidation:**

| Issue | Resolution |
| --- | --- |
| Repeated sections across the combined file's four parts | Merged into one section per topic |
| Rates presented as current | Labelled 2023 fixtures; annual update ownership flagged as an open decision |
| CPP2 missing | Added to statutory deductions and fixture notes |
| Time and leave rules spread between payroll and HR sections | Payroll keeps valuation and calculation; scheduling, timekeeping and leave administration moved to Module 06 |
| Compensation planning content in payroll files | Moved to Module 04; payroll consumes approved changes |
| Benefits plan administration in payroll files | Moved to Module 05; payroll keeps deductions and taxable benefits |
| Performance figures stated as achieved | Restated as targets pending pilot data |
| Low-code build for calculations | Calculations specified for a conventional backend |

**To verify before build:** current-year statutory values; provincial employment standards changes since 2023 (sick leave, minimum wages, holidays); employer health tax thresholds; CRA and Revenu Québec filing format versions.

**October 2026 review:** added the 14-jurisdiction coverage table, CRA and Revenu Québec source documents, 2026 values (T4127 122nd and 123rd editions), public-sector payroll, the Quebec recommendation and competitor comparison; corrected the s.87 EI treatment and removed a US-only reporting term; replaced the US expansion section with Europe.

**October 2026 (several positions):** added rates, allowances, duty pay and one-time payments per position (`docs/20` §4).
