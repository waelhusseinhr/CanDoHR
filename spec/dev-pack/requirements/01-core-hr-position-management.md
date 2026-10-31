# CanDo HRIS — 01 Core HR & Position Management

Oct 25, 2026 · @Wael

## Overview and scope

> **Status:** reviewed with the owner in October 2026, round by round. The decisions, their settings and the database rules that enforce them are in the developer pack, `docs/21-core-hr-decisions.md`, which takes precedence over this module on those topics. Organization structures, people in several positions and codes follow `docs/17`, `docs/20` and `docs/18`.

Core HR is the system of record for people, jobs and organization. Every other module reads from and writes back to the single person record it holds, so there is one version of who someone is, which positions they hold, where they work, who they report to in each position and which agreement covers each position.

**In scope:** the person and employee record; employments and the positions each person holds; organization structure and reporting relationships; position management and position control; job architecture, codes and requirements; employment status and lifecycle transactions; collective agreement and seniority data; employee and manager self-service for personal data; the employee file; effective-dated history of every change; the organization's settings for all of the above.

**Out of scope (owned elsewhere):** pay calculation (03), compensation planning (04), benefits plans (05), time and leave (06), performance (07), learning (08), succession and workforce planning (09), engagement (10), separation processing (11), analytics (12), compliance programs and labour relations casework (13).

**Design principles:**

| Principle | Meaning |
| --- | --- |
| One person, one record | A person has one record and one employee number for life, across employers, positions and rehires |
| Never one of anything | A person can have several employments (one per employer of record) and several positions in each, each with its own job, type, agreement, rates, managers, funding and end date |
| Effective dating | Every change has an effective date and is stored as history, never overwritten; future-dated changes are allowed |
| Positions for everyone | Every assignment fills a position. Organizations that do not manage positions get them created automatically at hire |
| Configurable by default | Every rule in this module is a default each organization can change in its settings, at setup or later. Legal floors and safety rules cannot be changed |
| Canadian by default | Provinces, territories, bargaining units, bilingual data, Indigenous identity (voluntary) and federal versus provincial jurisdiction are first-class |
| Event driven | Every committed change publishes an event other modules subscribe to |

## Organization settings

Each organization has its own settings, effective-dated and changed through approved change sets, with history. A setting can be set for the whole organization and, where useful, differently for one employer of record (for example a city and its library board). CanDo ships a default for each.

A short list cannot be changed by any organization because it protects people or the law: no self-approval; HR approval for terminations, demotions and changes linked to a leave or accommodation; a recorded arrangement before staff of one employer report to another; dual approval when an agreement gives less than a law it may replace. Statutory minimums, privacy limits and the audit trail are not settings at all.

The settings that belong to this module, with their defaults, are listed in `docs/21` §1. Admin → Settings shows each one with CanDo's default, the organization's value, who changed it, when and why.

## Employee record

| Section | Data held |
| --- | --- |
| Identity | Employee number (one per person, for life), legal name, preferred name, pronouns (optional), date of birth, SIN (encrypted), photo. There is no gender or sex field |
| Contact | Home and mailing addresses with province or territory, phones, personal email, emergency contacts |
| Language | Preferred official language for communication, other languages spoken, proficiency for bilingual positions |
| Voluntary self-identification | Categories from a library each organization switches on, edits or adds to (employment equity groups, First Nations, Métis and Inuit identity, Black identity, 2SLGBTQI+ identity, gender identity, and the organization's own), each with its purpose and its own consent; stored separately and encrypted, reported only in aggregate |
| Work authorization | Citizenship or permanent residence confirmation, work permit type, number and expiry with renewal alerts |
| Employment (one per employer of record) | Original hire date, continuous service date, status, service bridging decisions. The employment type shown here (permanent, casual …) is worked out from its positions |
| Positions held | One or more assignments, each with its position, job, employment type, FTE, agreement and bargaining unit, schedule, pay group, rates, managers and other relationships, cost distribution, probation or trial period, start and end dates and end reason |
| Rehire eligibility | Kept by HR only, with a reason category and a review date; recruiters see only "check with HR" |
| Credentials | Professional licences, certifications and registrations with issuing body, expiry and verification (shared with Module 08) |
| Documents | Signed offer and agreements, policies acknowledged, ID verification, permits, accommodations (restricted), disciplinary file (restricted) |
| History | Effective-dated log of every change with reason, approver, source module and the date it was communicated to the employee |

**Employee number.** CanDo gives each person one number with their first employment, in the organization's format, and it never changes or gets reused. A legacy number loaded at go-live becomes the person's number. Another employer's or system's numbers are kept as codes, so they can still be searched and exported (`docs/21` §3.5).

**Employment type and status.** Each position carries its own employment type (permanent, term, casual, auxiliary, seasonal, student): a person can be permanent in one position and casual in another. The employment's status is worked out from its positions in the organization's order (by default, permanent if any active position is permanent). A position suspended while its holder acts elsewhere still counts. Rules about the person (benefits waiting periods, notice, headcount) read the worked-out status; rules about one job (seniority, conversion, dues) read the position's own type.

**Gender.** There is no gender field. Gender identity is collected only as voluntary self-identification. Pay equity job classes get their gender predominance from HR, with the basis recorded (historical incumbency, stereotypes of the work, sector comparison, and aggregate self-identification counts as support), in Module 13.

## People in several positions

A person can hold several positions with one employer, and positions with several employers (a city and its library board are two employers of record, with two employments). The full rules are in `docs/17` §4 and `docs/20`:

| Topic | Rule |
| --- | --- |
| Assignment types | Regular, term, casual pool, acting, relief pool, secondment in and out, overlap, job share |
| Which position governs what | A configurable table: statutory maximums combine per payroll account; statutory hours combine per employer; agreement thresholds, leave plans, seniority, dues and probation follow each position's agreement; benefits eligibility combines FTE; the primary flag is for headcount and display only |
| Ending one position | Not a termination: the position is vacated, its schedule, leave plan, dues, funding and access end, benefits are re-evaluated by the organization's rules, and no ROE is issued while earnings continue in the same payroll account. Ending the last position proposes the termination |
| Two managers on one position | Each manager approves the days, hours and places they cover, or both approve, or either decides; requests are split to the minute across positions and managers; partial approval is possible |
| Reviews | One review per employment with a section per position, rated by that position's manager |

## Probation and trial periods

| Kind | When | Length |
| --- | --- | --- |
| Agreement probation | First position in a bargaining unit; a person in two units can be on two probations | The agreement's rule, often in paid hours (for example 624) |
| Employer probation | First position outside every bargaining unit | The organization's setting (default 3 calendar months, extendable) |
| Trial period | Moving to another position inside the same unit, where the agreement provides one; non-union moves only if the organization switches it on | The agreement's rule or the setting |

Hours-based probations are counted from paid or worked hours, with the agreement's rules for leaves. Outcomes are passed, extended, failed, waived or returned (a trial that ends with a return to the former position); every outcome other than passing needs a written reason. Probation completion feeds benefits waiting periods, seniority lists and Module 07 reviews.

## Rehires

A returning person reactivates the same record and keeps the same employee number. The agreement or policy rule covering the new position proposes which prior service counts for seniority, vacation, benefits and notice; HR confirms or changes it with a reason (by default).

**Rehire eligibility** is HR-only: eligible, check with HR, or not eligible, with a reason category from the organization's list (mapped to conduct, performance, job abandonment, policy breach, misrepresentation, safety, contract terms or other; there is no category for health, leave, complaints or any protected ground) and a review date no more than 24 months ahead (a setting). HR gets a task on the review date. Recruiters and hiring managers see only "check with HR".

## Organization structure

The structure is a set of effective-dated hierarchies with levels each organization defines (`docs/17` §3). A reorganization is planned as a future-dated version and goes live on its effective date.

**Levels.** There is no fixed list. A city might use Corporation → Cluster → Division → Section → Unit → Crew; a health authority Authority → Portfolio → Program → Site → Unit; a non-profit Organization → Program area → Program → Site. Each level type says which levels it may sit under, and whether its units own a budget, map to a cost centre, appear in approval chains, can be a bargaining employer or anchor a security scope.

**Several hierarchies.** Every organization has one management hierarchy (reporting lines, approvals, the org chart, positions) and can add financial, funding and program, geographic, governance and custom hierarchies. A position sits in one management unit; its place in the other hierarchies comes from that unit's mapping, or from an override with a reason.

**Employer and location data.** Legal entities carry business numbers, payroll accounts, the Quebec enterprise number, federal or provincial jurisdiction, workers' compensation accounts and the fiscal calendar. Locations carry the address, province or territory, holiday calendar, time zone, remote or northern zone and the on-reserve flag for s.87 assessment. The location, not the org unit, decides province, time zone and holidays.

**Unit heads.** Each unit names its head position, with dates. Approvals, agreement groupings such as "the first excluded head" and reports use it. A unit without a head raises a warning (or blocks the change, if the organization chooses).

**Reporting relationships.** Each position has one line manager, from the position tree. Other relationships are typed and can be several: administrative, functional or professional, project or program, timekeeper or scheduler, acting manager, delegate, HR business partner, mentor. Each type has its own authorities (approve time, leave or overtime; initiate changes; contribute to reviews; see credentials), set per organization. Delegations and acting arrangements carry start and end dates.

**Vacant manager positions.** When the manager's position is vacant and no acting manager or delegate is named, approvals go to the next filled position up, and HR is alerted to name an acting manager (a setting).

**Reporting across employers.** Staff of one employer can report to a manager employed by another (for example a Nation's housing society and the Nation) only while a shared-services arrangement between the two employers is recorded, with its purposes and privacy basis. The manager then sees work fields only. This cannot be switched off.

**Org charts.** Interactive chart by position or by person, filtered by any hierarchy, entity, location or unit; a person with several positions appears in each, with a marker linking them; dotted lines on request; export to PDF; future-state and plan views; two-way sync with every other screen (`docs/04`). What employees see is set per organization: by default, filled positions as of today only, while vacancies, change badges ("Leaving", "Moving", "Starting") and future dates are shown to managers for their own area and to HR. A badge about a person appears only once the change has been communicated to them.

**Reorganization tools:** move a unit and every position under it in one transaction; mass transfer with a preview of affected approvals, cost allocations, security scopes, seniority groupings and bargaining unit changes; impact report before go-live.

## Position management

A position is a seat in the organization that exists whether or not it is filled. Requisitions in Module 02 open against a position, and hires fill it.

**Positions for everyone.** Every assignment fills a position, and the line manager always comes from the position tree. Each organization (or employer) chooses how positions come into being:

| Choice | What happens |
| --- | --- |
| Managed (default) | HR creates and approves positions before recruiting; position control applies |
| Automatic | At hire, HR picks the manager and the job; CanDo creates the position under the manager's position. Position control is off. Suited to small organizations that do not want to manage positions |

Switching from automatic to managed keeps every position and shows a review list of the automatic ones, so HR can merge, rename, budget and approve them; control applies from the switch date.

**Position attributes:** position number, job (which gives the official title and the pay grade), working title and other titles by purpose, org unit, location, reports-to position, FTE, budgeted hours, default employment type, bargaining unit (defaulting from the job), cost distribution with funding sources, language requirement (English, French, bilingual with level), security clearance, physical demands, status (active, frozen, eliminated), confidential flag, incumbent(s), codes and requirements.

**Titles.** The job's title stays official for pay, pay equity, job evaluation, reports and government forms. A position can also carry a working title (shown on the org chart and directory), a title required by each funder, a posting title, legacy titles and other titles with a stated purpose, each with dates. Every screen, posting and report states which title it uses; funder reports use that funder's title.

**Position control:**

| Control | Rule |
| --- | --- |
| Headcount and FTE | A hire cannot exceed the position's FTE without an approved overlap with an end date |
| Budget and complement | Position cost (salary and burden, projected to year end) is checked against the unit's budget and the approved complement. By default a change that goes over is allowed with finance approval and a written reason, and every override is recorded; an organization (or one employer, such as one with a council-approved complement) can make it a hard stop |
| Funding | Funded positions carry their funding sources and end dates; alerts before expiry; term end dates aligned (`docs/17` §8) |
| Job sharing and pools | One position with several part-time incumbents, or pool positions for casual and seasonal staff, budgeted in hours |
| Freeze and elimination | Frozen positions cannot be recruited to; eliminations trigger notices in Module 11 and bumping rights in Module 13 where an agreement applies |

**Vacancy management:** vacancy created automatically when an incumbent leaves or transfers; vacancy age tracked; manager prompted to backfill, modify or eliminate; vacancies feed Module 09.

**Position lifecycle:** create → approve (budget and HR) → active → modify (with reason and effective date) → freeze or eliminate. Each step uses the shared workflow with approval chains from the delegation-of-authority matrix by level, transaction type and amount.

## Job architecture

| Element | Content |
| --- | --- |
| Job catalogue | Job codes and titles (English and French), summary, duties, qualifications, competencies, working conditions |
| Job family and career level | Code schemes for career paths, compensation surveys and succession |
| Pay grade | Belongs to the job only. A position that needs a different grade needs a different job; a position-specific evaluation that lands in another grade band proposes a new job |
| NOC code | Recommended, not required: a job without one shows a warning, and the features that use NOC (requirement proposals, the occupation part of the similarity score, employment equity groups, public wage data) say the job is not coded. An organization can make NOC, or another scheme, required |
| Employment equity occupational group | Derived from the NOC code through ESDC's correspondence |
| Overtime eligibility | Eligible or exempt under each jurisdiction's rules |
| Default bargaining unit | Union and local, or excluded with a reason |
| Pay equity class | Job class held as a code; predominance kept in Module 13 with its basis |
| Other codes | Any scheme the organization uses, as codes rather than fixed fields |
| Requirements | Education, training, experience, licences, registrations, language, screening and physical demands, each required (with a rationale), preferred or an asset |

**Starter catalogues.** At setup an organization can start from a CanDo sector catalogue (non-profit, First Nation government, municipal), load its own, or start empty. A starter catalogue is copied and then belongs to the organization; NOC is optional, and an organization can classify with its own or a funder's scheme instead.

**Job descriptions:** versioned documents with approval workflow. A draft is assembled from the job's NOC unit group (lead statement and main duties) and the job's requirements, in a template, and HR edits it freely or writes or uploads its own. **CanDo does not use AI to draft or rewrite job descriptions**, because each organization's descriptions are its own. A rule-based inclusive-language check flags wording for HR. Changes that affect evaluation or pay equity trigger a review task.

**Job evaluation:** point-factor or other method; factor ratings stored with evaluator, date, rationale and evidence; results propose the job's grade (Module 04, `docs/19`) and feed pay equity maintenance (Module 13).

## Position codes, classification and requirements

The full design is in `docs/18-position-codes-and-requirements.md`, which takes precedence over this section, as amended by `docs/21` §6.

**One way to hold every code.** NOC, salary survey matches, department codes, position control numbers, legacy IDs, other employers' employee numbers and any internal classification are codes from a *code scheme*, attached to a job, a position, an incumbent's assignment, a person, an org unit, a location or a requisition, with effective dates and history. An organization adds a new scheme without a system change.

| Scheme setting | Choices |
| --- | --- |
| Source | Published (NOC 2021 V1.0 and later versions, other countries' classifications), the organization's own, or derived from another scheme |
| Order | Natural code order (G2 before G10), alphabetical by code or by title in English or French, a custom rank, or the hierarchy |
| Values | A managed list (flat or hierarchical), free codes that match a format, or both |
| Where it applies | Job, position, incumbent, person, org unit, location, requisition; required, recommended with a warning, or optional |
| How many | One code per target, or several (for example a blended survey match of 60% and 40%) |
| Unique | Optionally, a code belongs to one target at a time |
| Inheritance | Codes flow from job to position to incumbent unless overridden with a reason |

**NOC 2021 Version 1.0** is loaded from Statistics Canada's publication with all 516 unit groups, their definitions, example titles, duties and employment requirements, and 28,012 titles for search. A coding assistant searches by title, shows the profile, or walks the structure. NOC 2026 Version 1.0 (announced for December 2026) will load as a new version with the official correspondence, and a recoding campaign proposes the new codes for HR approval.

**Requirements of each position.** Requirements live on the job and can be added to or switched off (with a reason) on the position. Coding a job with NOC proposes the unit group's employment requirements; HR accepts, edits or rejects them, and a required item needs a recorded bona fide occupational requirement rationale.

**Most similar position.** From a position, job, NOC code, title, person or foreign code, CanDo ranks positions using NOC proximity and cross-references, TEER, shared requirements and the organization's own codes, and explains each result. Results are suggestions, never use protected grounds, and never override an agreement's posting, bumping or recall rules.

## Employment status and lifecycle transactions

Every change runs as a change set with a type, a reason from the organization's list (mapped to a fixed category), an effective date, its approvals and the events it publishes.

| Transaction | Typical reasons | Downstream effects |
| --- | --- | --- |
| Hire | New hire, rehire, conversion from contractor | Payroll setup (03), benefits eligibility (05), onboarding (02), learning plan (08); position created at hire for organizations on automatic positions |
| Probation or trial outcome | Passed, extended, failed, waived, returned | Status, benefits waiting period, seniority, Module 07 review; a returned trial proposes the move back |
| Status conversion | Temporary to permanent, casual to regular, auxiliary to regular, part-time to full-time | Benefits and seniority recalculation; conversion rules per agreement (Module 02, `docs/17` §4.5) |
| Job change | Promotion, demotion, lateral transfer, reclassification | Pay change (04), possible bargaining unit change, trial period, learning requirements |
| Location or unit transfer | Reorganization, employee request | Province change for tax and employment standards, cost distribution, holiday calendar |
| Pay change | Merit, step increase, market adjustment, agreement increase | Payroll (03) from approved Module 04 decision |
| Hours or FTE change | Request, operational | Benefits eligibility, accruals |
| Leave of absence | Statutory, medical, personal, union, secondment | Module 06; status on leave; job protection dates |
| Acting or relief | Coverage, development | Acting assignment or relief on the timesheet, acting pay, temporary approval authority |
| Second position, or end of one position | Additional job, end of term, layoff from one job | Rules in "People in several positions" above |
| Termination | Resignation, retirement, dismissal, layoff, end of term, death | Module 11 separation process |

**Mass changes:** annual agreement increases, reorganizations and grid progressions run as batch change sets with preview, approval and rollback before the effective date.

**Approvals:**

- Routing from the delegation-of-authority matrix by transaction type, cost, entity, level and bargaining unit, and from each position's managers.
- **Always HR, whatever the organization's workflow:** terminations, demotions, and changes linked to a leave or an accommodation. "HR" is whoever holds the HR approval role (in a small organization, perhaps the executive director). No one approves their own change.
- When either of two managers can decide, the first decision is final. An undecided approval also goes to the approver's own manager after 3 working days (a setting).

**Back-dated changes.** A change whose effective date reaches a pay period already paid needs HR approval and payroll approval, and two HR approvals from different people when it goes back more than one month (all settings). Approvers see the retro estimate. Once approved, retro is calculated automatically however far back, following the payroll rules: overtime and premiums on the new rate, income tax, CPP, EI, pension, salary-based benefits, costing and GL are all recalculated. Retro from a ratified agreement follows the agreement's activation instead.

**Overpayments.** A negative result is never deducted automatically. It is held as an overpayment and recovered only with the employee's written authorization and an agreed schedule, unless the organization chooses to allow recovery where a verified provincial rule, the collective agreement or a court order permits it. HR can also waive it with a reason.

**Communicated changes.** An employee sees an approved change about them on their own profile, and in badges on the org chart, only once HR or the manager marks it communicated, with the date and method. Changes the employee asked for are always visible to them. An organization can show changes when approved or from their effective date instead.

## Collective agreement and seniority management

Core HR holds the agreement terms other modules apply; Module 13 handles grievances and bargaining. The structure follows `docs/17` §11.

**Library structure:** union → local (shared by every agreement it signs) → agreement, signed with one bargaining employer (a legal entity, or a unit such as a parks board) → bargaining units → letters of understanding, schedules and side agreements → versions → rules. Every rule can be scoped to sub-groups (classifications, units, locations, schedules, employment types, hour or age bands), and the most specific scope wins. A labour board decision that moves positions between units is one effective-dated change set.

**Terms stored as rules:** wage grids with steps, progression by months, hours or points, and floors tied to minimum wage; hours of work, averaging cycles and overtime; premiums; acting and relief pay; status conversion; vacation and leave plans beyond statute; cash in lieu of benefits; benefits and pension plans; probation and trial periods; seniority; layoff, recall and bumping; posting and work offering; union dues, including dues that continue after a transfer out. Modules 02, 03, 05, 06 and 11 read these terms instead of keeping their own copies.

**Agreements and employment standards law.** Where an agreement and the law differ, the agreement applies, as long as the province's law lets an agreement replace that part of the law (British Columbia lets an agreement replace hours of work and overtime, statutory holidays except the National Day for Truth and Reconciliation, annual vacation, and seniority, recall, termination and layoff provisions; Ontario keeps every standard as a floor unless the agreement gives a greater benefit). When an agreement version is checked, CanDo compares it with the law and records each difference:

- where the agreement gives less in a part the law lets it replace, both the HR administrator and the payroll administrator see a warning and must both approve, as two different people, before the version can be activated;
- where the law does not let it replace that part, CanDo pays the law's minimum, whatever is approved;
- where the province's rule has not yet been verified, the version cannot be activated.

How the comparison is made is set per agreement: hour by hour (default; no hour is ever paid below the law), or over the standard as a whole once labour counsel has confirmed it.

**Who sets agreements up.** CanDo's implementation team or a certified partner first sets up each agreement as a setup service, and the organization verifies and activates it. After that, the organization's HR can amend and update its agreements through CanDo's screens without coming back to CanDo. Every version goes through the same verification and two-person activation.

**Seniority:** several seniority types per agreement; accrual by date, by hours worked or paid, or by points with caps, from launch; rules for leaves, layoffs, transfers out of the unit and reciprocal transfers; groupings defined by the org chart (for example "the Branch"); tie-breakers; published seniority lists with posting date and challenge period; history of every adjustment with reason.

**Retroactivity:** when a new agreement is ratified with retroactive increases, Core HR loads the new grid with its effective dates and Module 03 calculates retro from history, across as many tax years as the agreement reaches.

## Employee and manager self-service

**Employee:** view and update personal and contact details, emergency contacts, preferred language and pronouns; voluntary self-identification with a purpose statement and consent for each category, withdrawable at any time; view each position, its manager, seniority and service dates; upload documents (permits, certifications); acknowledge policies; request letters of employment from templates; see a timeline of their employment history, including changes once communicated to them. Changes to legal name or SIN need document evidence and HR approval.

**Bank account changes** (where pay goes):

1. The employee makes the change and signs in again with their second factor.
2. A notice goes at once to the email and phone already on file.
3. HR approves only after speaking with the employee by video call or by phone, confirming the employee made the request and seeing government photo ID on camera. HR calls the number already on file, never one given with the request. CanDo records who checked, how, when and the type of ID, and never keeps a copy of the ID.
4. Pay goes to the new account only after a hold (72 hours by default).

An organization can switch off the live check; the second factor, notices and hold remain.

**Manager:** team directory and org chart for each of their positions; employee profiles limited to work-related fields; initiate transactions (job change, transfer, hours change, termination request) with guided forms that show policy and agreement rules; approve requests for the days, hours and places they cover; mark changes as communicated; view vacancies and position budgets for their area; delegate approvals while away.

**HR:** full record maintenance within their scope; transaction queue; document review; rehire eligibility; data quality dashboard; review list of automatically created positions; units without a head.

**Channels:** responsive web and an installable web app (on phones and tablets, with offline punches, approvals, leave requests, pay statements and schedule), and kiosk mode for shared devices in plants, stores and remote sites; English and French throughout; WCAG 2.1 AA.

## Data model

| Entity | Key fields | Relationships |
| --- | --- | --- |
| Person | Person ID, employee number (for life), legal and preferred names, date of birth, SIN (encrypted), languages | Has one or more Employments; has Contacts, Documents, Self-identification answers and consents (separate store), Rehire eligibility |
| Employment | Employment ID, employer of record, hire and service dates, status; employment type worked out from assignments | Belongs to Person and Legal Entity; has Assignments, Probations |
| Assignment | Assignment ID, type, employment type, position, FTE, agreement and unit, schedule, pay group, status, end reason, primary flag | Links Employment to Position; has Relationships, Rate components, Cost distribution |
| Probation | Kind (agreement, employer, trial), unit, measure and amount, counter, status, outcome and reason | Belongs to Employment; trial periods name their Assignment |
| Position | Position number, origin (planned, created at hire …), FTE, status, funding, language requirement | Belongs to an Org Unit and Location; refers to Job; reports to Position; has Titles, Codes, Requirements |
| Position title | Purpose (working, funder, posting, legacy, other), funder, titles EN/FR, dates | Belongs to Position |
| Job | Job code, titles, grade, overtime eligibility, default bargaining unit | Has Job Description versions, Codes, Requirements, Evaluations |
| Code scheme and Code | As in `docs/18` | Codes belong to a Job, Position, Assignment, Person, Org Unit, Location or Requisition |
| Requirement | Kind, strength, text (EN/FR), structured criteria, jurisdictions, verification, rationale, source | Belongs to a Job or Position |
| Hierarchy, Level type, Org Unit | Organization's levels and rules; unit with level, parent, head position, cost centre, bargaining employer flag | Several hierarchies with mappings |
| Relationship | Type, scope, dates | Links two Assignments, with the type's authorities |
| Shared-services arrangement | Serving and served employers, purposes, privacy basis, dates | Allows reporting across employers |
| Location | Address, province, holiday calendar, zone flags | Used by Positions and Assignments |
| Collective Agreement | Local, bargaining employer, units, term dates, status; versions with rules, who prepared them, and findings against the law | Has Terms, Wage Grids, Seniority Rules |
| Seniority and counters | Type, date, hours or points, adjustments | Belongs to Employment and Agreement |
| Rehire eligibility | Status, reason category, review date | Belongs to Person; visible to HR only |
| Change set | Kind, reason and category, effective date, before and after values, approvals, communicated date | Changes any entity above; publishes Events |
| Setting | Key, value, scope, dates | Belongs to the organization or one employer |
| Document | Type, file, retention class, access class | Belongs to Person or Position |

All entities are effective-dated with valid-from and valid-to plus system timestamps, giving both "what was true on date X" and "what did the system say on date Y" (bi-temporal history), for every record, as retro pay and audits require.

## Integrations and events

**Events published:** person.created, person.updated, employment.hired, employment.status\_changed, assignment.changed (job, location, manager, FTE, pay), assignment.ended, position.created, position.auto\_created, position.changed, position.vacated, org.reorganized, agreement.updated, agreement.finding\_recorded, probation.started, probation.outcome\_recorded, change\_set.communicated, employment.terminated, code.assigned, code.changed, code.ended, requirement.changed, classification\_version.published, setting.changed. Each event carries the effective date and identifiers, so subscribers can act without re-reading the record; no personal data travels in events.

| Subscriber | Uses |
| --- | --- |
| 02 Recruitment & Onboarding | Positions, vacancies, posting titles and requirements; the rehire signal; writes hires back |
| 03 Payroll | Assignments, rates, pay groups, provinces, cost distributions; bank account changes in effect; back-dated changes and overpayments |
| 04 Compensation | Jobs, grades, incumbents for planning |
| 05 Benefits | Eligibility events (hire, status, hours, end of a position, termination) |
| 06 Time, Attendance & Leave | Schedules, managers and coverage, agreement rules, locations |
| 07 Performance | Reporting lines and review sections per position |
| 08 Learning | Job and position requirements |
| 09 Succession & Workforce Planning | Positions, vacancies, structure, similar positions |
| 11 Offboarding | Assignment ends and terminations |
| 12 Analytics | All of the above for headcount and turnover |
| 13 Compliance | Self-identification (aggregate), employment equity groups, pay equity classes, licences, seniority lists, agreement findings |

**External:** identity provider sign-in and provisioning (SAML and SCIM) with Microsoft Entra ID and Okta at launch, Google Workspace later; ERP cost centre sync; background check and credential verification vendors; government e-services where APIs exist. Bulk import and export use validated templates.

## Security, privacy and data governance

**Access model:** role-based access combined with record scope (any hierarchy node, employer, location, bargaining unit, funding source, reporting relationship) and field-level classes:

| Class | Examples | Default visibility |
| --- | --- | --- |
| Public directory | Name, working title, unit, work contact, photo | All employees |
| Employment | Positions, managers, hire date, status | Managers in each position's chain, HR |
| Personal | Home address, personal contacts, date of birth | Employee, HR |
| Restricted | SIN, permits, accommodations, disciplinary records, rehire eligibility and its reason | HR roles designated for each type |
| Self-identification | Equity and diversity answers | Employee and equity program administrators only; reported in aggregate with minimum group sizes |

A manager employed by another employer under a shared-services arrangement sees work fields only.

**Privacy:** purpose stated at collection; consent recorded per self-identification category; access and correction requests through self-service and a tracked request queue; retention schedule by document and data class with legal holds; secure destruction logs; compliance with PIPEDA, Quebec Law 25, Alberta and BC PIPA, and public-sector statutes where the customer is covered.

**Data quality:** mandatory fields by transaction; validation (postal codes, SIN check digit, permit expiry); duplicate detection; dashboards showing missing and stale data, jobs without NOC (where NOC is used), units without a head and automatic positions not yet reviewed.

**First Nation customers and OCAP®.** When a First Nation government uses CanDo, the data about its people belongs to the Nation. At setup the Nation chooses: the shared platform in Canada with OCAP® controls (standard price), or its own database in Canada (paid option). With OCAP® controls, CanDo staff see the Nation's data only under a time-limited grant the Nation approves, the Nation sees every access in its audit log, can export all its data at any time, and gets its data back and destroyed on leaving. Community membership is recorded only where the employer needs it and with consent.

## Reporting

| Report | Content |
| --- | --- |
| Headcount and FTE | By any hierarchy, entity, location, job family, employment type (per position and worked out per person), bargaining unit, as of any date; people and positions counted separately |
| Movement | Hires, transfers, promotions, terminations, positions added and ended, for a period |
| Position | Filled, vacant, frozen; vacancy age; FTE and budget against actual; funding expiry; position control overrides with reasons; automatic positions to review |
| Probation | Probations and trial periods ending in a date range, by unit |
| Seniority lists | By agreement and unit, posting-ready |
| Work permit and credential expiry | Upcoming expiries by date range |
| Service anniversaries | For recognition (Module 10) |
| Org chart | Current, future-dated and plans |
| Data quality | Missing and invalid fields, stale records, units without a head |
| Audit | Changes by user, field, record and date, including settings changes |

All reports run as of any effective date and state which title and which code version they use. Advanced analytics, turnover and diversity reporting are in Module 12; employment equity statutory reports in Module 13.

## Implementation and data migration

Core HR is implemented first because every other module depends on it.

| Step | Activities |
| --- | --- |
| 1. Design | Employers of record, hierarchies and level types, locations, job catalogue (CanDo sector catalogue, own file or empty), code schemes, how positions are managed (managed or automatic), agreements, security model, settings that differ from CanDo's defaults |
| 2. Configure | Units and heads, locations, jobs, grades, agreements and terms (set up by CanDo or a partner), change reasons, approval chains and delegation of authority, field security, document types and retention, self-identification categories |
| 3. Migrate | Persons with one employee number each (other numbers kept as codes), employments, assignments with their employment types, positions (created per assignment where the old system had none), history (at minimum current record plus hire, job and pay changes for retro and seniority), probations in progress, seniority balances, documents |
| 4. Validate | Headcount reconciliation to payroll and finance; org chart review by managers; seniority list review with unions where required |
| 5. Launch | Self-service rollout with communications; HR training on transactions, communicated changes and bank account checks |

**Small organizations** start with automatic positions: HR picks each person's manager and job, and CanDo creates the positions behind the scenes. They switch to managed positions when they are ready, without re-implementation.

## Public-sector and large-employer structures

Core HR must model a municipality, a health authority or a First Nations government as easily as a 30-person non-profit.

| Need | Specification |
| --- | --- |
| Governance layers | Council or board, chief administrative officer or deputy head, clusters, departments and divisions as the organization defines them; agencies, boards and commissions (a police services board, a library board) as separate employers or as bargaining employers inside the corporation |
| Shared services | One HR team serving several employers, each with its own payroll accounts, agreements, pension plans and disclosure; staff of one employer reporting to another's manager only under a recorded shared-services arrangement |
| Bargaining structures | Many bargaining units and locals; excluded and management groups; sector and multi-employer bargaining; every unit linked to its agreement in the library |
| Approved complement | Council- or board-approved complement enforced by position control, as a hard stop if the organization chooses; vacancy management tied to budget cycles; acting and temporary assignments at scale |
| People who are not employees | Council members, board appointees, volunteer firefighters, election workers, co-op students and contractors as distinct person types with the right records, pay where applicable, and access |
| Language profiles | Positions with second-language requirements and employee proficiency levels; English, French and, for Nunavut, Inuktut communications |
| First Nations governments | The nation or band as employer, with program and housing entities as separate employers; s.87 status per employee; OCAP® options; community membership only where needed and with consent |
| Scale | 100,000 records per tenant; reorganizations moving thousands of people in one effective-dated transaction; bulk loads with validation |

## How CanDo compares

| Vendor | Core HR strength | CanDo response |
| --- | --- | --- |
| Workday, Dayforce, UKG | Deep position management and effective dating for large employers | Match, at a lower implementation cost |
| HiBob | Strong usability, org charts and people analytics; payroll handed to partners in Canada | Match usability; keep payroll and agreements native |
| Rippling | One employee record across HR, IT and finance | One record across HR, payroll, agreements and compliance |
| BambooHR, Collage, Rise | Simple records for SMBs | Automatic positions for small organizations, full position control when needed, on one model |

Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Sources and open questions

**Sources:** hr-integration-architecture.svg (Core HRIS as hub); employee-lifecycle-workflow.svg (lifecycle stages); status-conversion-workflow.svg (conversion types); Module 02 data model and requisition rules; Module 03 employee master and multi-position requirements; the owner's Core HR review (October 2026, `claude/review/01-core-hr-decisions.md`); `docs/17`, `docs/18`, `docs/20` and `docs/21`.

**Decided in the October 2026 review** (previously open):

- [x] Position control: positions for everyone; managed by default, automatic positions for organizations that do not manage them
- [x] Self-identification categories: a library each organization switches on, edits or adds to; final wording of CanDo's standard categories still to be reviewed with equity and Indigenous advisers (`docs/21` H6)
- [x] Bi-temporal history for every entity
- [x] Seniority by date, hours or points at launch
- [x] Identity providers at launch: Microsoft Entra ID and Okta
- [x] OCAP®: shared platform with OCAP® controls or the Nation's own database, chosen at setup and priced accordingly

**Still open:**

- [ ] When to adopt NOC 2026 Version 1.0 after Statistics Canada releases it (announced for December 2026; `docs/16` Q23)
- [ ] Load the French NOC (CNP 2021) before the first French-speaking customer (`docs/16` Q22)
- [ ] The defaults and items to verify listed in `docs/21` §14 (dedicated-database price, probation length, bank change hold, number format, provincial rules for overpayments and agreements, self-identification wording, first sector catalogues)

**Review history:** October 2026, added public-sector and large-employer structures, non-employee person types and competitor comparison; replaced a US labour-law term. 24 October 2026, added position codes and classification, requirements of each position, the similar-position search and NOC 2026 readiness. 25 October 2026, rewritten after the owner's round-by-round review: organization settings; employment type per position; probation per bargaining unit; no gender field; rehire eligibility for HR only; one employee number per person; tenant-defined levels and typed relationships; unit heads; vacant manager routing; reporting across employers; org chart visibility; positions for everyone with automatic positions; budget overrides; grade from the job; NOC recommended; optional starter catalogues; job descriptions without AI; several titles per position; back-dated changes, overpayments and communicated changes; changes that always need HR; agreements against the law; agreement setup and amendments; bank account checks; self-identification library; OCAP® options; installable web app.
