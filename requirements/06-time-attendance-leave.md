# CanDo HRIS — 06 Time, Attendance & Leave

Oct 17, 2026 · @Wael

> **Owner's review (28 October 2026):** the decisions are in `docs/27-time-attendance-leave-decisions.md`, which wins where this file differs. Changed here: full scheduling in CanDo; app, web and kiosk punching with clock imports and one hardware partner; no biometrics; exact minutes unless the organization rounds; breaks deducted only when taken; unapproved overtime flagged and always paid; rest and hours limits stop for a caution; exemptions with their legal basis; recording method per group; second approvals only where the organization adds them; unapproved timesheets paid at the cut-off; employees confirm their time; leave plans with their own carry-over, payout and year; no proof of leave; a team availability bar; protected leave reasons for HR only; the attendance program off until turned on; schedule notice and swaps. The open questions are closed, except the choice of clock partner (`docs/16` Q48).

## Overview and scope

> **Draft status:** new specification. Drafted from the time, overtime, holiday and leave sections of the payroll files, which mixed administration rules with pay calculation. Administration now lives here; Module 03 keeps valuation and pay calculation.

Time, Attendance & Leave records when people are scheduled, when they actually work, and when they are away, and applies the employment standards and collective agreement rules that govern each. It produces approved hours and leave for Payroll.

**In scope:** scheduling and shift management; time capture; hours of work, rest and overtime rules; timesheet approval; leave types and entitlements; accruals and balances; leave requests and approvals; job-protected statutory leaves; statutory holiday calendars and eligibility; absence management and attendance programs.

**Out of scope:** pay calculation and valuation of hours (03); disability claims with carriers (05); accommodation and return-to-work case management (13).

**Principle:** rules are configuration, not code. Each jurisdiction's employment standards and each collective agreement's terms are loaded into the rules repository with effective dates; schedules, timesheets and leave requests are evaluated against the rules in force on the date worked or taken.

## Scheduling and shift management

**Schedule types:** fixed (standard weekly pattern); rotating (repeating patterns such as 4-on-4-off or DuPont 12-hour rotations); flexible (core hours with flexible start and end); compressed work weeks under averaging or written agreements; on-call and standby rosters; split shifts.

**Schedule building (all at launch, `docs/27` §9.4):** templates by department or location; demand-based staffing levels (for example residents per care aide, sales forecast per hour); drag-and-drop editor with conflict checks; auto-fill that respects availability, qualifications and seniority rules; publication with a notice period configured per jurisdiction or agreement.

**Rule checks while scheduling:** minimum rest between shifts; maximum hours per day and week; daily and weekly overtime exposure shown before publishing; minimum call-in or reporting pay rules; split shift premiums; required credentials (for example first aid, licence) still valid; minors' hours restrictions by province; employee availability and approved leave.

**Employee tools:** view schedule on mobile; set availability; request shift swaps or give-aways with automatic eligibility checks and manager approval; pick up open shifts; notifications of changes.

**Union rules:** offering overtime and extra shifts by seniority or rotation; equitable distribution tracking; posting of schedules as the agreement requires; grievance-ready history of every offer and acceptance.

## Time capture

| Method | Use | Controls |
| --- | --- | --- |
| Physical time clocks | Plants, warehouses, stores | Badge or PIN; offline buffering; clock health monitoring |
| Mobile app | Field, home care, construction, remote sites | Optional location check at punch time only, off until the organization turns it on, keeping only inside or outside the site; offline punches synced later with original timestamp |
| Web punch | Office and hybrid staff | IP or network restrictions optional |
| Kiosk | Shared tablet at a site | Photo capture optional; PIN |
| Timesheet (positive time) | Salaried, project and professional staff | Hours by day and project or cost code |
| Exception-only | Salaried staff paid to schedule | Only deviations (leave, overtime) entered |
| Import | Time clocks of any vendor, third-party time or scheduling systems | Validated file or API; one certified clock hardware partner at launch (`docs/16` Q48) |

**Punch rules:** exact minutes unless the organization turns on rounding (applied the same way up and down so it never systematically underpays); early and late punch windows; an unpaid meal break deducted only where the employee punched it or confirms it was taken (`docs/27` §4); hours beyond the schedule without approval flagged to the manager the same day and to the manager and HR before payroll, and always paid; missed punch alerts and correction requests with manager approval; job and cost code switching during a shift.

**Privacy controls for monitoring:** CanDo offers no biometric punching at launch and stores no biometric data (`docs/27` §3.3); location checks are off until the organization turns them on, run only at the moment of punching and keep only whether the punch was inside the site, never coordinates; Ontario employers with 25 or more employees are prompted to keep their written electronic monitoring policy current, and the policy is distributed through the document module.

## Hours of work, rest periods and overtime rules

The rules engine evaluates each worked day and week against the employee's jurisdiction (from their work location and whether the employer is federally or provincially regulated) and any collective agreement.

**Overtime thresholds (examples held in the rules repository; verified at load):**

| Jurisdiction | Standard |
| --- | --- |
| Federal (Canada Labour Code) | After 8 hours a day or 40 a week |
| British Columbia | After 8 hours a day and 40 a week; double time after 12 hours a day |
| Alberta | After 8 hours a day or 44 a week, whichever is greater |
| Ontario | After 44 hours a week |
| Quebec | After 40 hours a week |
| Others | Loaded per province and territory |

**Other rules configured:** averaging agreements and permits; compressed work week agreements; excess hours limits and agreements (for example Ontario's 48-hour weekly limit unless an agreement exists); meal breaks (typically 30 minutes after five hours); daily and weekly rest periods; right to refuse overtime where legislated; minimum reporting or call-in pay; time off in lieu at 1.5 hours per overtime hour where permitted, with bank limits and payout deadlines; exempt classes (managers, certain professionals, sectors with special rules).

**Rest periods, hours limits, averaging and exemptions (`docs/27` §5):** a schedule or timesheet that breaks a rest period or maximum-hours rule stops until someone acknowledges a caution with a reason; averaging agreements and permits are recorded with their document, who they cover and their end date; HR marks a position exempt from overtime by picking the province's exemption with its legal basis; how each group records time (punches, a timesheet or exceptions only) is set per group, pre-filled as exceptions for salaried staff and punches for hourly staff.

**Collective agreement overrides:** more generous thresholds, multipliers, shift and weekend premiums, call-back and standby pay apply where they exceed statute; the engine always applies the greater right.

**Results:** each day is split into pay codes (regular, overtime 1.5×, double time, premiums, banked time) that Payroll values. Payroll also handles regular-rate questions (inclusion of premiums) per Module 03.

## Timesheet approval and payroll handoff

**Approval flow:** employee reviews and confirms each period, with reminders (or punches are auto-assembled into a timesheet) → manager approves with exceptions highlighted (missed punches, unapproved overtime, schedule variances, unconfirmed breaks) → a second approval only where the organization adds one to its timesheet route (for example overtime above a number of hours, or cost centres outside the manager's area) → payroll cut-off lock.

**Cut-off handling:** reminders before cut-off; escalation to the next manager or delegate if not approved; a timesheet still not approved at the cut-off is paid as recorded and the manager reviews it after, so payroll never waits; corrections after lock flow to the next run as adjustments, or to an off-cycle run if the shortfall would breach employment standards pay rules or is above the organization's amount (`docs/27` §6).

**Handoff to Payroll:** approved hours by pay code, date, assignment and cost allocation; leave taken by type; banked time earned and used; premiums; corrections to prior periods flagged as retroactive so Payroll recalculates the original period.

**Audit:** every punch, edit, approval and correction is logged with before and after values; employees can see edits made to their time and why, which supports compliance with record-keeping obligations and grievance responses.

## Leave types

Every leave type is configured with: its category from CanDo's fixed list (`docs/27` §8); jurisdiction(s); eligibility (service, status); entitlement (days, weeks, hours); paid or unpaid and pay percentage; job protection; whether managers see it only as "protected leave"; benefits and seniority continuation; notice requirements; interaction with EI benefits and Record of Employment. CanDo never asks for sick notes or other proof of leave (`docs/27` §8.1).

**Statutory leave categories loaded per jurisdiction:**

| Category | Examples and notes |
| --- | --- |
| Vacation | Minimum weeks by service (for example federal 2, 3 and 4 weeks at 1, 5 and 10 years; most provinces 2 weeks rising to 3); vacation pay percentage; scheduling and carry-over rules |
| Sick and medical leave | Paid days where legislated (federal 10 days; BC 5; Quebec 2) and unpaid entitlements elsewhere; doctor's note restrictions |
| Pregnancy or maternity and parental | Lengths aligned with EI standard and extended parental options; QPIP in Quebec |
| Family and caregiver | Compassionate care, family caregiver, critical illness of child or adult, family responsibility |
| Bereavement | Days and paid portion by jurisdiction |
| Domestic or sexual violence | Days with paid portion where legislated (for example 5 paid days federally and in Ontario); confidentiality of the reason |
| Indigenous practices | Federal leave for traditional Indigenous practices; customer-configurable cultural leave for any jurisdiction |
| Civic | Jury and witness duty, voting time, reservist, citizenship ceremony |
| Other | Organ donor, crime-related child death or disappearance, long-term illness, public health emergency leaves when declared |

**Employer and agreement leave:** additional vacation, personal days, floating holidays, union business leave, education and sabbatical, secondments, unpaid personal leave, deferred salary leave plans.

**Always the greater right:** where policy or agreement is more generous than statute, the engine applies the greater entitlement and records which source applied.

## Accruals, balances and requests

**Accrual methods:** front-loaded at the start of the year or anniversary; per pay period; per hour worked or paid; percentage of wages (vacation pay accumulated as dollars); tiered by service with automatic step-up on anniversary; proration for part-time, mid-year hire and unpaid leave.

**Leave plans (`docs/27` §7):** each plan has its own year (calendar, fiscal, hire or service anniversary, or the date the person joined the plan through a promotion, becoming exempt or a move of location or union) and its own date for service tiers, so one person can hold plans on different years.

**Balance rules:** maximum balance caps; carry-over limits and expiry dates set per plan, with advance warnings; mandatory scheduling of statutory vacation within the legislated window after the entitlement year; negative balances blocked unless the plan allows them, up to its limit; payout on termination set per plan, pre-filled as vacation and banked time as the law requires and sick and personal days not paid; balance as of any future date for planning.

**Request flow:** employee requests by day, part day or hours, seeing a team availability bar (green, amber, red or unknown, with no names) for the dates → system checks balance (including future accruals if allowed), blackout periods, team coverage and minimum staffing → manager is warned of conflicts and approves or declines with a category and reason; a statutory leave is never declined for staffing (`docs/27` §8.5) → schedule and timesheet update automatically → Payroll receives leave taken. Cancellations and changes follow the same path.

**Long leaves:** a guided case for pregnancy, parental and other extended leaves: expected dates; EI or QPIP application reminder and ROE trigger to Payroll; benefits continuation choice (Module 05); top-up plan if any; seniority and service continuation; return-to-work date and reinstatement to the same or comparable position as required by statute.

**Team calendar:** who is away when, by team, with privacy: managers see the leave type, sensitive leaves only as "protected leave" with the reason for HR only, and co-workers see "away" (`docs/27` §8.2); conflicts highlighted for managers.

## Absence management and attendance programs

**Unplanned absence reporting:** employee reports by app, phone line or manager entry; reason category only (no diagnosis); expected return; automatic notification to the scheduler to fill the shift.

**Attendance management programs** (at launch, off until the organization turns them on, `docs/27` §8.4; configurable stages): thresholds based on frequency or days absent; stage letters and meetings tracked; protected absences excluded automatically (statutory leaves, disability-related absences, approved accommodation, workers' compensation, domestic violence leave), so the program does not count protected grounds under human rights law; managers prompted to consider accommodation before progressing a stage; HR review required before any disciplinary stage.

**Extended absence triggers:** absences over a set number of consecutive working days (5 pre-filled, editable) prompt a check on STD eligibility (Module 05) and an accommodation or return-to-work case (Module 13); workers' compensation claims from Module 13 mark the absence accordingly.

**Analytics:** absence rates by type, team and location; Bradford factor or similar indices available but hidden by default and never used alone for decisions; cost of absence; patterns such as Monday and Friday absences shown in aggregate for managers with HR guidance.

## Statutory holidays

**Calendars:** a holiday calendar per jurisdiction per year, generated from rules (fixed date, nth weekday, observed date when falling on a weekend) and reviewed annually; the National Day for Truth and Reconciliation (30 September) for federally regulated employers and provinces that observe it; employer-added holidays; holidays assigned to locations so employees get their work location's calendar.

**Eligibility rules per jurisdiction:** for example, worked the scheduled day before and after, or earned wages on a number of days in the prior period, or a minimum length of service.

**Treatment when:**

| Situation | Configured outcome |
| --- | --- |
| Holiday on a regular working day, not worked | Holiday pay per jurisdiction's formula (calculated by Payroll) |
| Holiday worked | Premium rate plus holiday pay, or regular rate plus substitute day, per jurisdiction and agreement |
| Holiday on a non-working day | Substitute day or holiday pay per jurisdiction |
| Holiday during vacation | Vacation day restored or extra day per jurisdiction |
| Holiday during leave | Eligibility per rules (often not eligible on unpaid leave) |
| Continuous operations and retail | Special provisions where provinces have them |

**Religious and cultural observance:** holidays not on the statutory calendar handled through accommodation requests and floating days so employees can observe them without loss of pay where policy allows.

## Data model, integrations and security

| Entity | Key fields |
| --- | --- |
| Schedule Template | Pattern, shifts, cycle length, location or department |
| Shift | Employee or open, date, start, end, breaks, position, premiums, published flag |
| Availability | Employee, days and times, effective dates |
| Punch | Employee, timestamp, type, device, location (optional), original and edited values |
| Timesheet | Employee, period, daily lines by pay code and cost code, status, approvals |
| Time Rule Set | Jurisdiction or agreement, thresholds, multipliers, breaks, rest, effective dates |
| Leave Type | Jurisdiction, entitlement, paid portion, protection, documentation, EI interaction |
| Leave Plan | Accrual method, tiers, year and tier-step basis, caps, carry-over, negative limit, payout rules |
| Leave Balance | Employee, leave plan, balance, accrued, used, as-of date |
| Leave Request | Type, dates, hours, status, approver, linked case |
| Holiday Calendar | Jurisdiction, year, dates, observed dates |

**Integrations:** Core HR for employees, assignments, locations, agreements and managers; Payroll for approved hours, leave and banked time; Benefits for leave events and STD triggers; Compliance for accommodation, return to work and workers' compensation; time clock hardware via vendor APIs; third-party schedulers via import.

**Security:** managers see their teams' schedules, time and leave; leave reasons for protected categories are visible only to HR; location results (inside or outside the site) restricted and retained only as long as needed for payroll verification; no biometric data.

## Overtime and holidays in all 14 jurisdictions

Standard overtime thresholds loaded in the rules repository, before averaging agreements, permits or collective agreement terms. Verified at each load against the statute.

| Jurisdiction | Overtime after |
| --- | --- |
| Federal | 8 hours a day or 40 a week |
| Newfoundland and Labrador | 40 hours a week |
| Prince Edward Island | 48 hours a week |
| Nova Scotia | 48 hours a week |
| New Brunswick | 44 hours a week |
| Quebec | 40 hours a week |
| Ontario | 44 hours a week |
| Manitoba | 8 hours a day or 40 a week |
| Saskatchewan | 8 hours a day or 40 a week |
| Alberta | 8 hours a day or 44 a week, whichever is greater |
| British Columbia | 8 hours a day and 40 a week; double time after 12 hours a day |
| Yukon | 8 hours a day or 40 a week |
| Northwest Territories | 8 hours a day or 40 a week |
| Nunavut | 8 hours a day or 40 a week |

**Holiday calendars** carry each jurisdiction's own days, for example Nunavut Day (9 July), National Indigenous Peoples Day in the Northwest Territories (21 June), Yukon's Discovery Day, PEI's Islander Day, Nova Scotia's Heritage Day, Manitoba's Louis Riel Day and Quebec's Fête nationale. The National Day for Truth and Reconciliation (30 September) is a statutory holiday federally and in several provinces and territories; each calendar records where it applies.

## Public-sector and 24/7 scheduling

| Workforce | Requirement |
| --- | --- |
| Fire services | Platoon schedules with 24-hour shifts, minimum staffing per station, call-back and acting pay |
| Police and corrections | 12-hour rotations, court time, overtime banks by agreement |
| Health care and long-term care | Self-scheduling, float pools, agency staff, minimum staffing ratios, multiple concurrent positions |
| Transit and public works | Seniority-based shift and route bidding (picks); winter on-call rosters |
| Essential services | Designated staffing levels maintained during strikes, per essential services agreements |
| Many agreements | Different overtime, premium and scheduling rules per bargaining unit in the same department |

## People in several positions

Detailed design: `docs/20` §2–§3, which takes precedence.

- **Each position has its own approvers.** A leave or time request covering two positions is split into one component per position, each approved by that position's manager.
- **Two managers on one position.** Each position can choose how its requests are approved:
  - **By coverage** (the default): each manager approves the days, hours or locations they supervise;
  - **All:** every manager approves;
  - **Any:** either manager decides.

  The position also sets what happens to hours both managers cover and to hours nobody covers.
- **Split to the minute.** Requests are split from each position's shifts or weekly pattern, including several positions on the same day, overnight shifts (counted on the day they start) and unpaid breaks. A casual position with no schedule is shown as not scheduled.
- **Partial approval.** If one manager approves and another declines, the request is partially approved, and the employee keeps or cancels the approved part.
- **No self-approval.** A person who manages one of their own positions never approves their own request; it goes to their manager's manager.

## How CanDo compares

| Vendor | Time and scheduling position | CanDo response |
| --- | --- | --- |
| UKG | Workforce management heritage (Kronos); UKG Pro Workforce Management used by municipalities such as the City of Hamilton | The benchmark for union and 24/7 rules; match on rules depth |
| Dayforce | Workforce management in its single platform | Match |
| Sparkrock, Rise | Scheduling inside non-profit and SMB suites | Match for non-profits |
| Humi by Employment Hero | Scheduling in higher HR plans | Match for SMBs |

Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Reporting, implementation and open questions

**Reports:** scheduled vs actual hours; overtime by employee, team and reason with cost; premium pay; missed punches and edits; timesheet approval status; leave balances and liability (dollar value of accrued vacation for finance); leave taken by type; absence rates; holiday pay cost; compliance exceptions (rest period breaches, excess hours, minimum wage); equitable overtime distribution for unions.

**Implementation:**

| Step | Activities |
| --- | --- |
| 1. Rules inventory | Jurisdictions, agreements, policies, current practices for rounding, breaks, overtime approval |
| 2. Configure | Rule sets, schedules, pay codes, leave plans, holiday calendars, approval chains |
| 3. Devices | Clock selection, network and installation, mobile app rollout |
| 4. Migrate | Leave balances (verified by employees), banked time, future approved leave |
| 5. Test | Parallel time and leave processing for at least one pay cycle alongside Module 03 parallel runs |
| 6. Launch | Manager training on approvals; employee training on punching and requests |

**Sources:** payroll files (overtime, holidays, vacation, sick leave, TOIL, leave valuation); employee-lifecycle-workflow.svg; hr-integration-architecture.svg. Everything else is new drafting.

**Open questions:**

- [x] Build scheduling in-house at launch, or integrate: full scheduling in CanDo at launch (`docs/27` §9.4)
- [ ] Supported time clock hardware vendors: imports from any clock and one certified partner at launch; the partner is still to be chosen (`docs/16` Q48)
- [x] Whether biometric punching is offered at all: not at launch (`docs/27` §3.3)
- [x] Attendance management program at launch or later: at launch, off until the organization turns it on (`docs/27` §8.4)
- [x] Ownership of the annual employment standards rule refresh: CanDo loads statutory tables and employment standards centrally (`docs/16` Q7)

**October 2026 review:** added overtime thresholds and holiday calendars for all 14 jurisdictions, public-sector and 24/7 scheduling, and competitor comparison.

**October 2026 (several positions):** added approval by manager coverage, splitting requests to the minute and partial approval (`docs/20` §2–§3).

**28 October 2026 (owner's review):** the decisions in `docs/27`.
