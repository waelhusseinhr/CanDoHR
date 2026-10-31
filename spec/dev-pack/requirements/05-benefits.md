# CanDo HRIS — 05 Benefits Administration

Oct 17, 2026 · @Wael

> **Owner's review (28 October 2026):** the decisions are in `docs/26-benefits-decisions.md`, which wins where this file differs. Changed here: spending accounts administered by a partner; generic carrier files first; an included advisor role; the enrolment assistant later; waiting periods, life event windows and retro months set by each organization; late enrolment by each plan's rule; the governing agreement and coordination of benefits decided by HR; leave contributions and unpaid leave rules; coverage on termination by class; carrier invoices through the route; pension plan files; automatic pension enrolment; retirees later. The open questions are closed.

## Overview and scope

> **Draft status:** new specification. Drafted from the benefits deduction and taxable-benefit sections of the payroll files, the integration architecture diagram and the onboarding workflow's enrolment step. No dedicated benefits source file exists.

Benefits Administration manages which plans an employee is eligible for, what they elected, who their dependents and beneficiaries are, what it costs and who pays. It keeps carriers, payroll and the employee in step as life and employment change.

**In scope:** group health, dental, vision, life, AD&D, critical illness, short- and long-term disability, EAP; health and wellness spending accounts; flexible benefits; group retirement and savings plan enrolment; eligibility rules and waiting periods; enrolment events; dependents and beneficiaries; premium and cost-share calculation; taxable benefit values; carrier and administrator data exchange; benefits continuation during leaves and after termination.

**Also in scope:** benefits and HR practice benchmarking against market surveys, shared with Module 04 (detailed design in `docs/19` §8).

**Out of scope:** payroll deductions and tax calculation (03, which takes this module's outputs); statutory leave administration (06); disability case management and return to work (13 under accommodation and health and safety); pension plan actuarial administration (handled by the plan administrator); claims administration for spending accounts (a partner's, `docs/26` §3.1); retiree benefits administration (a later phase, `docs/26` §9.4).

**Canadian context:** most Canadian employers buy group benefits through an insurer or an administrative-services-only (ASO) arrangement via an advisor; provincial health plans cover hospital and physician care, so group plans fill gaps (drugs, dental, paramedical, vision); Quebec requires private drug coverage to meet RAMQ public plan minimums for employees and dependents who have access to a group plan.

## Plan types and tax treatment

The tax treatment of each plan drives what Payroll must do, so it is configured with the plan and verified annually.

| Plan | Typical design | Employer-paid premium treatment |
| --- | --- | --- |
| Extended health (drugs, paramedical, vision, travel) | Single, couple, family tiers; co-insurance; maximums | Not a taxable benefit federally (private health services plan); taxable benefit for Quebec provincial tax |
| Dental | Basic, major, orthodontic; fee guide year | Same as health |
| Group term life | Flat amount or multiple of salary; optional employee-paid top-up | Taxable benefit |
| AD&D and dependent life | Matches basic life or flat | Taxable benefit |
| Critical illness | Lump sum on diagnosis | Taxable benefit |
| Short-term disability | Weekly indemnity; may be EI premium reduction registered plan | If employer-paid, payments to employee are taxable; if fully employee-paid, payments are non-taxable |
| Long-term disability | Percentage of salary after elimination period | Same principle as STD; employee-paid LTD is a common design |
| Employee assistance program | Counselling and support services | Generally not taxable |
| Health spending account | Annual credit for eligible medical expenses | Not taxable federally if it meets private health services plan rules; Quebec treatment configured |
| Wellness or lifestyle account | Fitness, wellness, other listed items | Taxable benefit when used |
| Group RRSP, DPSP, TFSA, RPP | See retirement and savings section | Varies by plan |

**Dental coverage reporting:** whether an employee and family had access to employer dental coverage is reported on the T4 (box 45) because of the Canadian Dental Care Plan; this module supplies the code to Payroll at year-end.

## Plan configuration

**Plan setup:** carrier or administrator; policy and group numbers; plan year; coverage options and tiers; benefit amounts or formulas (for example life = 2× annual earnings rounded to the next $1,000, to a maximum); non-evidence maximums and evidence of insurability rules; termination age (for example life coverage ending at 65 or 70); rates and the date they renew. Every plan states its waiting period and its late-enrolment rule when it is set up (`docs/26` §4.1, §4.3).

**Benefit classes:** groups of employees who share eligibility and plan design, defined by rules on Core HR data: employment type, bargaining unit, hours or FTE, job level, entity and location. Examples: full-time non-union; executives; Local 123 members; part-time 20+ hours; retirees.

**Eligibility rules:**

| Rule | Options |
| --- | --- |
| Waiting period | None; days or months from hire; first of month after; hours worked threshold. Set by the organization for each plan at setup; no CanDo default (`docs/26` §4.1) |
| Minimum hours | Per week average over a look-back period, with re-test schedule for variable-hour staff, as the organization sets per plan or class; CanDo re-tests and proposes, HR confirms (`docs/26` §4.7) |
| Age limits | Coverage ending or reducing at set ages, consistent with human rights legislation exemptions for bona fide plans |
| Dependents | Spouse (married or common-law per provincial rules), children to a set age, older children in full-time study, disabled dependents without age limit, as the plan contract says |
| Collective agreement | Plan design and cost sharing taken from the agreement terms in Module 01; for a person under two agreements, HR chooses the governing one (`docs/26` §5.1) |
| Rehire | Waiting period waived if rehired within a set period |

**Plan design values:** each plan also records its design in standard keys for its kind, for example drug reimbursement percentage and pay-direct card, paramedical and mental health maximums, vision maximum, dental basic and major percentages and orthodontic maximum, life and AD&D multiples, disability waiting days, benefit percentage, duration and elimination period, employer share of premiums, waiting months, retirement contribution percentage. The keys are those named in `rules/total-rewards/benefit-practices.json`, so the benchmarking scorecard reads them directly and nothing is retyped.

**Rates:** per employee, per coverage tier, per $1,000 of volume, or percentage of payroll; rates by class; employer and employee shares by percentage or flat amount; provincial sales tax on premiums (Ontario, Quebec, Saskatchewan and others that apply it) and premium tax handled as configured; effective-dated rate changes at renewal.

## Enrolment

**New hire enrolment:** triggered by the hire event from Module 01 and surfaced as a task in onboarding (Module 02); the window opens when the waiting period ends (or earlier for pre-enrolment); employee selects coverage, adds dependents and beneficiaries, uploads proof where required and confirms; late enrolment follows each plan's rule after the window closes, starting from evidence of insurability for life and disability and limited coverage for dental (`docs/26` §4.3).

**Annual or open enrolment:** configurable window per plan year; employees review current elections, see next year's costs and change elections; reminders and manager visibility of completion rates; when no action is taken, current elections roll over, or a flex plan's default option applies (`docs/26` §4.4).

**Life events:**

| Event | Effect | Window |
| --- | --- | --- |
| Marriage or start of common-law relationship | Add spouse, change tier | The plan's own, or the organization's, set at setup with no CanDo default (`docs/26` §4.2) |
| Birth or adoption | Add child | Same |
| Divorce, separation, end of relationship | Remove spouse, change tier | Same |
| Dependent ages out or leaves school | Remove or convert | Employee and HR told 60 days before (pre-filled, editable); proof of full-time studies asked each year (`docs/26` §4.5) |
| Loss of other coverage | Enrol or change tier | Same as marriage |
| Employment change (class, hours, province) | Re-evaluate eligibility and design | Automatic from Core HR event |
| Leave of absence | Continuation options and contributions | Module 06 event |
| Termination, retirement, death | End or convert coverage | Module 11 event |

**Coordination of benefits:** spouse's coverage recorded; opt-out allowed for health and dental with proof of other coverage where the plan permits; Quebec opt-out rules respect RAMQ requirements (`docs/26` §4.6). When two of the person's own plans of one kind cover them, HR sets which pays first (`docs/26` §5.2).

**Evidence of insurability:** requests flagged when elected amounts exceed non-evidence maximums or enrolment is late; pending status tracked with the carrier; approved amount updates coverage and deductions automatically.

## Flexible benefits and spending accounts

**Flex credits:** credits per employee from a formula (flat, by class, percentage of salary, or by coverage tier); priced options per plan; employee allocates credits across options; surplus credits flow to a health spending account, wellness account, RRSP or cash (taxable) per plan rules; deficits taken as payroll deductions. The election screen shows remaining credits and payroll impact live.

**Health spending account (HSA):** annual allocation; eligible expenses limited to medical expenses that qualify for the tax credit; carry-forward of unused balance or unused claims for one year (the plan must choose one method); claims processed by the administrator, balances synchronised; non-taxable federally when it meets private health services plan rules, with Quebec taxability configured. Spending accounts are always administered by a partner; CanDo holds allocations, balances, carry-forward and taxable amounts and stores no claim details (`docs/26` §3.1).

**Wellness or lifestyle account:** allocation and eligible categories (fitness, wellness, childcare, professional development, home office, and so on); taxable when reimbursed, so each claim is sent to Payroll as a taxable benefit.

**Year-end:** forfeiture of unused balances per plan rules; carry-forward processed; employee statements of allocations and use.

## Premiums, cost sharing and taxable benefits

**Calculation per employee per plan:** coverage volume (for example life amount from salary formula, recalculated on pay change) × rate, or tier rate; split into employer and employee shares; provincial sales tax and premium tax where applicable; converted to per-pay-period amounts using the pay group frequency.

**Outputs to Payroll (Module 03):**

| Output | Payroll treatment |
| --- | --- |
| Employee premium deductions | Pre-tax or post-tax per plan; arrears if pay is insufficient |
| Employer-paid taxable premiums (life, AD&D, critical illness, PST on taxable portions) | Added to taxable income; CPP pensionable; EI insurable where applicable |
| Quebec taxable health and dental | Added to provincial income only |
| Wellness account reimbursements | Taxable benefit |
| Flex cash-out | Taxable earnings |
| Disability plan employee-paid designation | Affects taxability of future claims payments |

**Retroactive changes:** late enrolments, life events and rate changes generate retroactive premium adjustments (collect or refund) automatically within the months the organization sets at setup; older adjustments go to HR to approve (`docs/26` §8.1).

**Billing reconciliation:** carrier invoices imported or entered and reconciled to system enrolment and premiums by employee; differences listed for correction; invoices approved through the organization's route (HR, then finance, in the starter copy) before they pass to accounts payable, never by the person who prepared them. Self-billing (employer sends the bill) supported per carrier (`docs/26` §8.2).

## Disability and leave coordination

**Short-term disability:** plan type (insured, ASO or salary continuance); elimination period; benefit percentage and weekly maximum; duration; integration with EI sickness benefits (STD as primary or EI as primary, top-ups); EI premium reduction program registration so Payroll applies the reduced employer rate.

**Long-term disability:** elimination period aligned to end of STD; integration with CPP/QPP disability and workers' compensation (offsets); continued coverage of other benefits while on claim (premium waiver).

**Claim workflow (benefits side):** employee or manager reports absence in Module 06 → STD claim package generated (employer statement, earnings, job description) → sent to carrier → status tracked (pending, approved, denied, closed) → approved benefit amount sent to Payroll (if salary continuance) or recorded (if insurer pays) → transition to LTD or return to work. Medical information is never stored in the HRIS; only claim status, dates and functional restrictions needed for accommodation (handled under Module 13).

**Benefits during statutory leave:** pregnancy, parental and other job-protected leaves keep benefits in force where employment standards require the employer to continue contributions; the employee chooses how to pay their share (ahead, as arrears on return, or through payroll while still paid) among the ways the organization offers, and the organization can pay the share itself (`docs/26` §6.1).

**Unpaid and other leaves:** continuation options by leave type (continue at employee cost, suspend, or continue employer-paid for a period), set by the organization for each leave type and class at setup; a leave with no rule stops for the organization to set one, never assumed (`docs/26` §6.2).

**Termination and retirement:** coverage end dates set by the organization for each class at setup (date of termination, end of month, or end of the notice or severance period), never before the end of statutory notice where employment standards require continuation; outside Ontario, until counsel confirms each province, HR sees a caution about common-law reasonable notice and records why (`docs/26` §7); conversion privileges for life and health; retiree benefits in a later phase (`docs/26` §9.4); post-termination continuation during statutory notice when pay in lieu is given, coordinated with Module 11.

## Retirement and savings plans

| Plan | Enrolment and administration in this module | Payroll (03) |
| --- | --- | --- |
| Registered pension plan (DB or DC) | Eligibility (often mandatory after a waiting period, or by collective agreement), with automatic enrolment on the eligibility date where membership is mandatory, the employee told and HR confirming (`docs/26` §9.2); beneficiary designation; spousal waivers; contribution rates; investment elections (DC) passed to the record-keeper | Contributions, pension adjustment |
| Group RRSP | Voluntary enrolment; contribution percentage or amount; employer match rules; spousal RRSP option | Deductions, withholding reduction |
| DPSP | Often paired with group RRSP to hold employer match; vesting up to 24 months | Employer contributions (not taxed until withdrawal) |
| Group TFSA | Voluntary; after-tax contributions | Post-tax deductions |
| Multi-employer union plans | Membership by bargaining unit; contribution rates from the agreement | Remittances to plan trustees |
| Employee share purchase plan | Enrolment, contribution percentage, employer match | Deductions, taxable benefit on employer portion |

**Record-keeper integration:** enrolments, contribution files and investment elections exchanged with the record-keeper; contribution remittance reconciliation; annual statements linked in self-service.

**Limits:** RRSP deduction limit is the employee's responsibility, but the system warns when payroll contributions plus the pension adjustment approach the annual dollar limit; DC and DPSP limits checked per CRA rules from the rules repository.

## Carrier and administrator integration

**Data exchange:** enrolment and change files (full file or changes only) on a schedule after each payroll or weekly; a generic file at launch, and each carrier's own format (CSV, fixed width, or carrier API) built as anchor customers need it (`docs/26` §3.2); acknowledgement and error files imported and turned into tasks for the benefits administrator; termination notices sent promptly so coverage and claims stop on time.

**Typical partners:** major Canadian group insurers, third-party administrators for ASO and spending accounts, pension and group RRSP record-keepers, EAP providers, and benefits advisors who need read access to enrolment and cost reports. Specific vendor connections are chosen per customer.

**Advisor access:** an included, read-only role the organization grants lets the customer's benefits advisor see plan design, enrolment counts and costs, without individual employee data unless the customer allows it (`docs/26` §3.3).

**Reconciliation:** monthly comparison of carrier-held enrolment with system enrolment; mismatches resolved before billing reconciliation.

## Employee experience and decision support

**My benefits:** current coverage, dependents, beneficiaries, costs per pay and per year, employer contribution, spending account balances, plan booklets (English and French), carrier contacts and digital benefits cards where the carrier provides them.

**Decision support during enrolment:** side-by-side option comparison; cost calculator showing per-pay deduction and taxable benefit impact; plain-language explanations of co-insurance, maximums and waiting periods; an AI assistant, later and off until the organization switches it on, that answers questions from the plan booklet only, cites the booklet section, and never recommends a specific election (`docs/26` §3.4).

**Manager and HR:** enrolment completion tracking for their teams; HR can enrol on behalf of an employee with a reason logged (for example an employee without computer access).

**Accessibility:** WCAG 2.1 AA; mobile-first enrolment; kiosk support; English and French throughout.

## Benefits and practice benchmarking

The scorecard answers "how do our benefits and practices compare?" for each benefit class or agreement (`docs/19` §8).

**Practice catalogue:** 54 practices in ten categories: health and dental, spending accounts, life and disability, retirement and savings, time off and leave, wellness, learning, work arrangements, allowances and pay practices. Each practice has:

- a value type (yes or no, amount, multiple of salary, percentage, days, weeks, months, count or a choice);
- whether more or less is richer (a shorter waiting period is richer);
- where the organization's own value comes from.

The organization enables the practices it uses and can add its own.

**Own values, read from setup:**

| Source | Examples |
| --- | --- |
| Plan design values (this module) | Drug reimbursement, paramedical maximum, life multiple, disability waiting days and elimination period, employer share of premiums |
| Leave policies and agreements (Module 06) | Vacation at hire and at maximum, years to maximum, paid sick and personal days, extra holidays, winter closure, parental leave top-up |
| Earning codes and expense rates (Module 03) | Home office, phone and transit allowances, kilometre rate |
| Policies (Modules 01, 02, 04 and 08) | Remote work, flexible hours, compressed week, parking, professional dues, education assistance, increase budget, pay ranges in postings |

Values are recomputed when a plan, policy or agreement changes, per benefit class or agreement. A value can be entered by hand with a reason where the setup cannot express it.

**Market data:** practice sections of salary and benefits surveys the organization licenses are imported with the practice prevalence profile. For each practice and cut the import loads:

- the number of organizations reporting and the share offering the practice;
- P25, P50 and P75 and the most common value;
- the distribution of values, where the survey publishes one.

Like salary data, it is visible only to the survey's role.

**Comparison rules:**

| Practice kind | Rule |
| --- | --- |
| Numbers | Compared with the market median. Within 5% for amounts, or exactly equal for other types, is at market; otherwise richer or leaner in the practice's direction |
| Yes or no | A practice offered by at least half of the market is common. Offering a common practice is at market; offering an uncommon one is richer; not offering a common one is leaner |
| Choices | Compared with the most common choice |
| Information only | Shown with prevalence and not compared |

Prevalence is always shown beside the result.

**Limits:** the scorecard shows where plans sit. It does not price plan changes (the carrier and advisor do) or compute an actuarial value of benefits. A benefits value index from an advisor can be imported as a practice.

**Survey participation:** when the organization takes part in a survey, its practice answers are taken from the same own values (`requirements/04`, Taking part in salary surveys).

## Data model, security and privacy

| Entity | Key fields |
| --- | --- |
| Carrier / Administrator | Name, contacts, file formats, connection details |
| Plan | Type, carrier, policy number, plan year, options, tax treatment flags, design values, waiting period, late-enrolment rule, life event window, hours test |
| Benefit Class | Rules on Core HR attributes, plans offered, cost sharing |
| Option / Tier | Coverage level, rate basis, rates by effective date |
| Eligibility Status | Employee, plan, eligible date, reason |
| Election | Employee, plan, option, tier, volume, effective dates, source event |
| Dependent | Name, relationship, date of birth, student or disability status, coverage periods |
| Beneficiary | Plan, name, relationship, percentage, revocable or irrevocable, trustee for minors |
| Life Event | Type, date, documents, window, status |
| EOI Request | Plan, amount requested, status, approved amount |
| Spending Account | Allocation, balance, carry-forward, claims summary |
| Premium | Employee, plan, period, employee and employer amounts, tax portions |
| Carrier File | Type, period, records, acknowledgement, errors |
| Carrier Invoice | Carrier, period, amount, self-billed, differences by employee, route and status |
| Opt-out | Plan kind, other coverage, proof document, period |
| Leave Rule | Leave types and classes, action, employer-paid months, priority |
| Practice | Catalogue or own practice, category, value type, richer direction, source of the own value |
| Practice Market Data | Survey edition, cut, organizations, prevalence, percentiles, most common value, distribution |
| Own Practice Value | Practice, benefit class or agreement, value, derived or manual with reason, effective dates |

**Security:** benefits data restricted to benefits roles; managers see completion status only; dependents' personal data is held under the employee's record with the same protections; beneficiary designations are visible to the employee and benefits administrators only.

**Privacy:** no medical information or claims details are stored; disability claims hold status and dates only; dependents' data is collected for plan administration only and deleted on schedule after coverage ends; data sharing with carriers limited to what the policy needs and covered by data processing agreements.

## Public-sector pensions and large-employer benefits

| Area | Requirement |
| --- | --- |
| Public-sector pension plans | Enrolment, contributions and member data for defined benefit plans such as OMERS, HOOPP, LAPP, the BC Municipal Pension Plan, public service and teachers' plans; plan-specific eligibility (mandatory for full-time, optional or hours-based for part-time); pensionable earnings definitions; contribution rates below and above the YMPE. Files for the BC Municipal Pension Plan, OMERS, HOOPP and LAPP at launch; a generic contribution file for other plans until a customer needs theirs (`docs/26` §9.1) |
| Pension events | Leaves with contributions or buy-backs, service purchases, transfers between employers in the same plan, annual member data reconciliation with the plan administrator, termination and retirement options passed to Module 11 |
| Union benefit trusts | Multi-employer health and welfare trusts and pension trusts: contribution rates by agreement, hours-based remittances, member eligibility files; a generic file at launch, each trust's format per customer (`docs/26` §9.3) |
| Large self-insured plans | Administrative-services-only plans with several carriers and third-party administrators; flex plans for tens of thousands; retiree benefit populations (retiree administration in a later phase) |
| Northern and isolated posts | Vacation travel assistance and northern allowances with their tax treatment, linked to Module 03 |
| Agreement-driven design | Plan, eligibility and cost-sharing terms read from the agreement library, so a settlement changes benefits and payroll together |

## People in several positions

Detailed design: `docs/20` §6 and `docs/26` §5, which take precedence.

- **Plans by employer, agreement or position.** A plan's eligibility is judged on the combined FTE with the employer, on the positions under one collective agreement (a union trust plan, for example), or on one position alone. Exempt positions use the employer's plans.
- **Enrolment where each agreement requires.** A person in two unions is enrolled in each plan their positions qualify for, and each enrolment names the position that qualifies them.
- **The governing agreement.** When a benefit rule must pick one of a person's agreements, HR chooses and records why; CanDo makes no automatic choice (`docs/26` §5.1).
- **Coordination of benefits.** When two plans of the same kind cover the person, HR sets which pays first and records why; any order a plan contract sets is shown beside the decision (`docs/26` §5.2).
- **When one position ends.** The organization's own rules decide, by plan, end reason, who initiated the end, province, agreement and employment type: coverage continues to a date, ends on the end date, or goes to HR for a case-by-case decision. If the person is still eligible on the remaining positions, nothing changes.
- **The statutory floor.** Where a province requires benefits to continue during the notice period, as Ontario does, coverage can never end earlier, whoever decides. Elsewhere CanDo stops the decision with a caution about common-law reasonable notice, and HR records why. A decision without a rule, or one that changes the proposed date, needs a written reason.

## How CanDo compares

| Vendor | Benefits position | CanDo response |
| --- | --- | --- |
| Collage | Integrations with Canada Life, Manulife, Sun Life, Equitable and others; sold through a benefits broker network | Match carrier integrations; build a broker and advisor program |
| Humi by Employment Hero | Carrier-agnostic benefits administration (Benefits+ add-on) | Match, plus public pension plans |
| Payworks | Real-time link between payroll and benefits | Same single record across payroll and benefits |
| Dayforce, ADP, UKG | Benefits inside large-employer suites | Match for pensions and union trusts |
| BambooHR, HiBob | Benefits administration aimed at US employees | Native Canadian benefits as a differentiator |

Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Reporting, implementation and open questions

**Reports:** benefits and practice scorecard by category and benefit class; enrolment by plan, option and class; participation and waiver rates; cost by plan, entity and department with employer and employee shares; premium reconciliation; pending EOI and life events; dependents ageing out; spending account utilization and forfeitures; disability claim counts and durations (no medical data); renewal analysis support (cost per employee trends); T4 box 45 dental access coding.

**Implementation:**

| Step | Activities |
| --- | --- |
| 1. Plan inventory | Policies, booklets, rates, classes, eligibility rules, collective agreement terms, tax treatment confirmed with the advisor |
| 2. Configure | Carriers, plans (with waiting periods and late-enrolment rules), options, classes, rates, events, flex rules, leave rules, termination rules per class, carrier file formats; the life event window and retro months |
| 3. Migrate | Current elections, dependents, beneficiaries, EOI status, spending account balances |
| 4. Reconcile | System enrolment and premiums versus last carrier invoice, to the employee |
| 5. Test | Carrier file round-trip; payroll deductions and taxable benefits for sample employees in each class and province |
| 6. Launch | Employee review of their data; first open enrolment in the system |

**Sources:** payroll files (benefit deductions, taxable benefits, Quebec health treatment); hr-integration-architecture.svg; onboarding-workflow.svg (benefits enrolment step). Everything else is new drafting.

**Open questions:**

- [x] Which carriers and administrators to build file integrations for first: a generic carrier file at launch, each carrier's format as anchor customers need it; pension files for the BC Municipal Pension Plan, OMERS, HOOPP and LAPP; union trusts through a generic file (`docs/26` §3.2, §9)
- [x] Whether to offer CanDo-branded spending account administration or always partner: always a partner (`docs/26` §3.1)
- [x] Scope of retiree benefits administration at launch: a later phase (`docs/26` §9.4)
- [x] Advisor portal as a paid add-on or included: included, read-only, granted by the organization (`docs/26` §3.3)
- [x] AI enrolment assistant at launch or later: later, with the platform assistant, off until switched on (`docs/26` §3.4)

**October 2026 review:** added public-sector pension plans, union benefit trusts, large self-insured plans, northern benefits and competitor comparison.

**October 2026 (second review):** added plan design values and benefits and practice benchmarking, shared with Module 04 (`docs/19` §8).

**October 2026 (several positions):** added people in several positions: plans by agreement or position, coordination of benefits, and benefit changes when one position ends (`docs/20` §6).

**28 October 2026 (owner's review):** the decisions in `docs/26`.
