# CanDo HRIS — 11 Offboarding & Separation

Oct 17, 2026 · @Wael

## Overview and scope

> **Draft status:** new specification. Drafted from the final pay, termination, retiring allowance and Record of Employment content in the payroll files, the separation stage of the employee lifecycle diagram, and the PIP decision point in the performance workflow.

Offboarding & Separation makes every departure lawful, consistent and respectful: the right notice and pay, a clean handover, access removed on time, and records kept as required.

**In scope:** resignations, retirements, terminations with and without cause, end of term, layoffs (temporary and permanent), group terminations, deaths; notice and severance calculation; separation documents; offboarding tasks; access and property recovery; final pay coordination; ROE; benefits end; exit surveys; rehire eligibility; alumni.

**Out of scope:** payroll calculation of final pay (03); benefit conversion administration with carriers (05); grievances and litigation case management (13).

**Legal caution built in:** the system calculates statutory minimums under employment standards. Common law reasonable notice for non-unionized employees (often much higher than statutory minimums) and contractual terms require legal judgment; the system records the amounts decided and flags when a termination clause or release needs legal review.

## Separation types and initiation

| Type | Initiated by | Key checks |
| --- | --- | --- |
| Resignation | Employee (self-service) or manager on their behalf | Written resignation captured; notice period per policy or agreement; employer may waive notice (pay for the statutory notice period may still apply in some jurisdictions) |
| Retirement | Employee | Pension and retiree benefit eligibility; phased retirement options |
| Termination without cause | Manager with HR | Statutory notice and severance; contract terms; release; protected-ground risk check |
| Termination for cause | Manager with HR | Documentation of misconduct or failed PIP; HR and legal review required; wilful misconduct standards for statutory entitlements where applicable |
| End of probation (unsuccessful) | Manager with HR | Probation terms and agreement rules |
| End of term or contract | System (from end date) | Renewal decision prompted in advance; repeated renewals flagged as possible indefinite employment |
| Temporary layoff | Employer | Jurisdiction limits on length before it becomes a termination; recall rights |
| Permanent layoff or position elimination | Employer | Bumping and recall under the agreement; group termination thresholds |
| Death | HR | Estate payments, benefits claims, compassionate process |
| Job abandonment | Manager with HR | Attempts to contact documented before treating as resignation |

**Initiation workflow:** request with type, reason code, last day worked, effective date and notice details → risk checks (employee on protected leave, recent accommodation request, complaint or claim filed, union member, pregnancy, workers' compensation claim) → HR review (and legal review when flagged) → approval → separation case opened with tasks for every module and stakeholder.

**Confidentiality:** involuntary terminations are hidden from the employee and broader manager chain until the meeting; tasks for IT and facilities are released at a set time.

## Notice, severance and termination entitlements

**Statutory individual notice (examples held in the rules repository; all jurisdictions loaded and verified at build):**

| Jurisdiction | Minimum notice or pay in lieu |
| --- | --- |
| Federal | 2 weeks after 3 months, rising by service to 8 weeks after 8 years |
| British Columbia | 1 week after 3 months; 2 weeks after 12 months; 3 weeks after 3 years plus 1 week per additional year, to 8 weeks |
| Alberta | 1 week (90 days to 2 years) rising in steps to 8 weeks (10+ years) |
| Ontario | 1 week per year of service, to 8 weeks |
| Quebec | 1 week (3 months to 1 year); 2 weeks (1–5 years); 4 weeks (5–10 years); 8 weeks (10+ years) |

**Statutory severance pay where it exists:** Ontario (1 week per year of service, prorated, up to 26 weeks, for employees with five or more years where the employer's payroll is at least $2.5 million or a qualifying group termination occurs); federal (the greater of 2 days' wages per year of service or 5 days, after 12 months).

**Calculator outputs:** service (with bridging and prior service rules); statutory notice; statutory severance; benefits continuation through the statutory notice period; vacation pay owing; other contractual or collective agreement entitlements; total; split into working notice versus pay in lieu as decided.

**Beyond statute:** a field records the common law or negotiated package (amount, components, payment schedule, whether paid as a retiring allowance with RRSP transfer) entered by HR after legal advice; enforceability of the employment contract's termination clause is flagged for legal review rather than assumed.

**Documents:** termination letters, release and settlement templates, and letters of reference generated in English or French; Quebec French-language requirements respected; e-signature with copies to the employee file.

## Group terminations, layoffs and recall

**Group (mass) termination:** thresholds by jurisdiction (number of employees terminated at an establishment within a period) trigger longer notice and notice to the labour ministry; the system counts terminations in rolling windows and warns before a threshold is crossed; ministry notice forms prepared; Quebec, federal and other regimes with joint committees or adjustment programs supported.

**Temporary layoff:** start date, expected recall date; jurisdiction limits (for example a maximum number of weeks within a period) tracked with alerts before a layoff becomes a deemed termination; benefits continuation options; ROE issued with the right code.

**Collective agreement processes:** layoff order by seniority within classification; bumping options calculated and offered; recall lists with rights expiry dates; recall offers tracked with response deadlines; union notifications.

**Workforce reduction planning:** scenarios from Module 09 converted into separation cases in bulk, with consistency checks (selection criteria applied evenly, adverse impact analysis by age, gender and other groups in aggregate) before execution.

## Final pay, ROE and benefits end

**Final pay deadline:** calculated per jurisdiction from the separation date and who initiated it (for example Ontario: the later of seven days or the next regular pay day; BC: within 48 hours when the employer terminates, six days when the employee quits); Payroll is alerted and an off-cycle run is scheduled automatically if the next regular run is too late.

**Final pay components sent to Payroll (Module 03):** wages to the last day; outstanding overtime and banked time; vacation pay owing; statutory holiday pay; pay in lieu of notice; statutory severance; retiring allowance with eligible and non-eligible portions and any RRSP direct transfer; bonuses or commissions owed under plan terms; recoveries permitted by law with written authorization (advances, overpayments, equipment), never reducing pay below statutory minimums; clawbacks of signing or retention bonuses or tuition per signed agreements.

**Record of Employment:** reason code mapped from the separation reason; issued electronically within the legislated deadline; insurable earnings and hours; vacation and severance amounts reported in the correct blocks; amendments if final amounts change.

**Benefits:** coverage end dates per plan; continuation through the statutory notice period where required; conversion notices sent; group RRSP and pension options communicated through the record-keeper; flex or spending account run-out period.

**Equity and incentives:** vesting and exercise windows per plan terms flagged to the employee and Compensation.

## Offboarding checklist

Tasks are generated from templates by separation type, role, location and systems used; each has an owner and due date relative to the last day.

| Area | Tasks |
| --- | --- |
| HR | Confirm dates and entitlements; documents signed; exit survey sent; rehire eligibility set; personnel file closed |
| Manager | Knowledge transfer plan; handover of work, clients and files; team and client communication; reassign approvals and delegations |
| IT and security | Accounts disabled at the exact time (immediately for involuntary terminations) through identity provider deprovisioning (SCIM); mailbox and file retention or transfer; MFA devices revoked; shared passwords rotated |
| Facilities | Keys, badges and parking returned; building access removed |
| Assets | Laptop, phone, tools, uniforms, vehicles, corporate cards returned and checked off against the asset list |
| Finance | Outstanding expenses and advances settled; corporate card cancelled |
| Payroll and benefits | Final pay, ROE, benefits end and conversion notices (automatic from this case) |
| Compliance | Return or destruction of confidential information confirmed; reminders of continuing confidentiality and non-solicitation obligations where they exist |
| Learning | Outstanding tuition repayment agreements checked |

**Knowledge transfer:** structured handover document (responsibilities, contacts, recurring tasks, systems, open issues); successor assigned; for critical roles, the continuity sheet from Module 09 updated.

**Status tracking:** case dashboard shows outstanding tasks and overdue items; the case cannot close until required tasks (access removal, final pay, ROE) are complete.

## Exit surveys, interviews and alumni

**Exit survey:** sent automatically for voluntary departures (optional for others); reasons for leaving (pay, manager, growth, workload, flexibility, relocation, personal), what would have kept them, likelihood to return or recommend; confidential reporting through Module 10 with group-size thresholds so managers see trends, not individual responses.

**Exit interview:** optional conversation with HR (not the manager) with a structured guide; notes kept confidential and themes coded for analysis.

**Regrettable turnover:** manager and HR classify departures (regrettable or not) for retention analytics; reasons feed Module 12.

**Rehire eligibility:** eligible, eligible with conditions, or not eligible, with a reason visible only to HR; Module 02 checks it when a former employee applies.

**Alumni:** opt-in alumni contact list for rehiring and referrals; boomerang hires recognised in Module 01 with service bridging rules.

## Retirement and death of an employee

**Retirement:** planning conversation tools (employee-initiated); pension estimates from the plan administrator; phased retirement arrangements (reduced hours, mentoring role) as Core HR transactions; retiree benefits enrolment in Module 05; recognition through Module 10; knowledge transfer emphasised in the checklist.

**Death of an employee:** a separate, compassionate workflow with restricted visibility:

| Step | Detail |
| --- | --- |
| Notification | HR records date of death; automatic emails and system notices to the employee are suppressed |
| Family contact | Single HR contact assigned; condolence and support resources (EAP for colleagues) |
| Pay | Final pay and other amounts paid to the estate with correct tax treatment (year of death amounts on T4, amounts after death on T4A or as rights or things where applicable), handled by Payroll |
| Benefits | Life and AD&D claims initiated with beneficiary information; dependent coverage continuation per plan |
| Pension and savings | Death benefit processes started with the record-keeper |
| ROE | Issued with the appropriate reason |
| Records | Personal effects returned; records retained per schedule |

## Data model, integrations, security and records

| Entity | Key fields |
| --- | --- |
| Separation Case | Employee, type, reason code, initiated by, notice date, last day worked, effective date, status, risk flags |
| Entitlement Calculation | Service, statutory notice, severance, benefits continuation, vacation owing, contractual and negotiated amounts, approvals |
| Separation Document | Type, language, template version, signatures |
| Offboarding Task | Case, area, owner, due, status, evidence |
| Asset Return | Asset, condition, date |
| Layoff / Recall Record | Employee, layoff dates, recall rights expiry, offers, responses |
| Group Termination Window | Establishment, period, count, threshold, ministry notice |
| Exit Feedback | Survey link (confidential), interview notes (restricted), coded themes |
| Rehire Eligibility | Status, reason (restricted) |

**Integrations:** Core HR (termination transaction, status), Payroll (final pay, ROE), Benefits (end dates, conversions), Time (final hours, banked time), Compensation (incentives, clawbacks), Learning (repayment agreements), Succession (vacancy risk), Recruitment (backfill requisition prompt, rehire eligibility), identity providers and IT service desks (deprovisioning tickets), asset management systems.

**Security:** separation cases are visible to HR and named approvers only until effective; termination reasons, legal notes and settlements restricted further; audit of every view.

**Records after separation:** personnel and payroll records retained for the required periods (for example payroll records for six years for CRA and employment standards periods by province) and then destroyed securely; former employees can still access their slips and ROEs through a limited alumni login; access requests from former employees handled through the privacy request queue.

## Notice in the remaining jurisdictions

The notice table above covers federal, BC, Alberta, Ontario and Quebec. The other nine jurisdictions also graduate statutory notice by service; the full scales are loaded from each statute and verified at load.

| Jurisdiction | Statutory notice pattern |
| --- | --- |
| Newfoundland and Labrador | Graduated by service, to a maximum of 6 weeks |
| Prince Edward Island | Graduated by service, to a maximum of 8 weeks |
| Nova Scotia | 1 week (3 months to 2 years), 2 weeks (2–5 years), 4 weeks (5–10 years), 8 weeks (10+ years) |
| New Brunswick | 2 weeks (6 months to 5 years), 4 weeks (5+ years) |
| Manitoba | 1 week to 8 weeks across five service bands, the top band at 10+ years |
| Saskatchewan | 1 week to 8 weeks across five service bands, the top band at 10+ years |
| Yukon | Graduated by service, to a maximum of 8 weeks |
| Northwest Territories | Graduated by service, to a maximum of 8 weeks |
| Nunavut | Graduated by service, to a maximum of 8 weeks |

Group termination thresholds, temporary layoff limits and final pay deadlines are loaded for all 14 jurisdictions in the same way.

## Public-sector separations

| Area | Requirement |
| --- | --- |
| Workforce adjustment | Workforce adjustment terms in public-sector agreements: job offer guarantees, alternation between employees, income protection, education allowances, surplus and priority lists |
| Bumping and recall at scale | Layoff order by seniority across many units, bumping options calculated for each affected employee, recall rights tracked for the agreement period |
| Pension at termination | Deferred pension, commuted value transfer or locked-in account options from the public-sector plan; retirement eligibility and bridging; options passed from Module 05 |
| Early retirement programs | Incentive offers modelled on cost, eligibility and pension impact before launch |
| Elected and appointed officials | End of term for council and board members, with final pay and disclosure |
| Records and access | Separation records subject to public-sector access-to-information laws, with exemptions applied |

## How CanDo compares

Humi files ROEs within one business day of submission but leaves stat holiday pay and ROE block 15B to the user; most SMB tools stop at checklists and ROEs. None of the vendors reviewed advertises notice, severance, group termination and workforce adjustment calculation across all Canadian jurisdictions; CanDo makes that a standard feature. Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Reporting, implementation and open questions

**Reports:** separations by type, reason, unit and tenure; voluntary and regrettable turnover; exit survey themes; time to complete offboarding; late access removals; final pay timeliness; ROE timeliness; severance and notice costs; layoff and recall status; group termination window counts.

**Implementation:**

| Step | Activities |
| --- | --- |
| 1. Rules | Notice, severance, final pay deadlines, group termination thresholds and temporary layoff limits for each jurisdiction in use; agreement layoff and recall terms |
| 2. Templates | Letters, releases and checklists in English and French reviewed by the customer's counsel |
| 3. Integrations | Identity provider deprovisioning, IT ticketing, asset lists |
| 4. Migrate | Open layoffs and recall lists; rehire eligibility for past employees |
| 5. Test | Scenario tests per jurisdiction and separation type, including final pay timing with Payroll |

**Sources:** payroll files (termination pay, vacation payout, retiring allowance, ROE, deceased employee payments); employee-lifecycle-workflow.svg (separation stage); performance-management-workflow.svg (PIP decision point). Everything else is new drafting.

**Open questions:**

- [ ] Whether to include a common law reasonable notice estimator (high legal risk; possibly partner with legal content providers)
- [ ] Templates: CanDo-provided versions per province, or customer-supplied only
- [ ] Alumni portal scope at launch

**October 2026 review:** added notice patterns for the remaining nine jurisdictions, public-sector separations (workforce adjustment, pensions, early retirement) and competitor comparison.
