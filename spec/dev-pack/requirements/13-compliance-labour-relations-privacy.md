# CanDo HRIS — 13 Compliance, Labour Relations & Privacy

Oct 17, 2026 · @Wael

## Overview and scope

> **Draft status:** new specification. Brings together the compliance content spread through the recruitment files (human rights, privacy, accessibility, Indigenous hiring, collective agreement hiring rules) and the payroll files (statutory compliance, audit, records), and adds the programs that had no source.

Compliance, Labour Relations & Privacy is where an organization manages its legal obligations as programs: knowing what applies, doing it on time, handling cases fairly and proving it. Other modules enforce rules in their own transactions; this module owns the rules repository, the obligations calendar and the case management for accommodation, health and safety, harassment and labour relations.

**In scope:** regulatory rules repository and change monitoring; compliance calendar; human rights accommodation and return to work; occupational health and safety; workplace harassment and violence programs and investigations; confidential speak-up channel; labour relations (agreements, grievances, bargaining support, arbitration); employment equity, pay equity program administration and accessibility; privacy program; immigration and hiring compliance support.

**Not legal advice:** the module tracks and applies rules and records decisions. Customers remain responsible for legal interpretation, and content is reviewed by Canadian employment counsel before release.

## Regulatory framework and rules repository

**Jurisdiction model:** each employer entity is federally regulated (Canada Labour Code: banks, interprovincial transport, telecommunications, First Nations band councils in many cases, and others) or provincially regulated; each employee's work location determines provincial or territorial rules; collective agreements and policies layer on top; the engine always applies the greater right.

**Law areas covered:**

| Area | Federal | Provincial and territorial |
| --- | --- | --- |
| Employment standards | Canada Labour Code Part III | Employment standards acts and codes in each jurisdiction |
| Human rights | Canadian Human Rights Act | Provincial and territorial human rights codes |
| Health and safety | Canada Labour Code Part II | OHS acts and regulations; workers' compensation acts |
| Labour relations | Canada Labour Code Part I | Labour relations acts; Quebec Labour Code |
| Employment equity and pay equity | Employment Equity Act; Pay Equity Act | Ontario and Quebec pay equity acts; public-sector statutes |
| Accessibility | Accessible Canada Act | AODA (Ontario), Accessible British Columbia Act, Manitoba and Nova Scotia accessibility acts, others |
| Privacy | PIPEDA | Quebec private sector act as amended by Law 25; Alberta and BC PIPA; public-sector statutes |
| Language | Official Languages Act (federal institutions) | Charter of the French Language as amended by Bill 96 |
| Tax and payroll | Income Tax Act, CPP, EI Act | Provincial tax, QPP, QPIP, health taxes |

**Rules repository:** every rule stored as structured, effective-dated configuration with its legal citation, jurisdiction, applicability conditions, owner and review date; rule changes go through drafting, legal review, testing against sample employees and approval; modules read rules at run time so a change takes effect without code releases.

**Change monitoring:** legislative and regulatory changes tracked from government sources; each change logged with impact assessment (which rules, modules and customers), target date and status; customers notified in plain language before effective dates.

## Compliance calendar and obligations tracking

**Obligations register:** every recurring obligation for the customer, generated from their entities, jurisdictions, size thresholds and agreements: filings, remittances, postings (for example employment standards posters, pay equity results), policy reviews (for example annual workplace violence and harassment policy review in Ontario), training renewals, committee meetings and inspections, privacy reviews, agreement expiry and bargaining notice windows.

**Calendar:** due dates with owners; reminders ahead of deadlines; evidence upload when done; overdue escalation; view by month, by entity and by law area.

**Policy library:** required policies per jurisdiction with templates, versions, approval, distribution and employee acknowledgement tracked (shared document service); policies due for review flagged.

**Self-assessments:** periodic checklists by law area (for example an employment standards self-audit) with findings and remediation actions.

**Inspections and audits:** visits from labour inspectors, health and safety officers, CRA payroll audits or privacy regulators logged with requests, documents provided, orders received, compliance dates and closure.

## Human rights, accommodation and return to work

**Accommodation cases:** request from the employee, a manager, a candidate (from Module 02) or a disability claim (Module 05); grounds category (disability, religion, family status, sex including pregnancy, and other protected grounds) recorded without diagnosis; functional limitations and restrictions from medical providers (not medical details); options considered with reasons; agreed accommodations (modified duties, schedules, equipment, leave, alternate role); undue hardship assessment documented where accommodation is refused; review dates; outcome.

**Return to work:** graduated return plans with hours and duties by week; coordination with STD or LTD carriers and workers' compensation boards; check-ins; adjustments; schedule and pay changes pushed to Modules 06 and 03.

**Duty to accommodate safeguards:** prompts when the system sees signals that may trigger the duty (repeated absences, performance concerns after a leave, requests mentioning a protected ground) so managers involve HR; attendance and performance processes in Modules 06 and 07 pause or exclude protected absences.

**Confidentiality:** case files restricted to the accommodation coordinator and HR; managers see only the agreed accommodations they must implement; medical documents, if received, stored in a sealed section with separate access logging and retention.

**Human rights complaints:** complaints to a tribunal or commission tracked with deadlines, representatives, documents and outcomes.

## Occupational health and safety

| Capability | Detail |
| --- | --- |
| Incident reporting | Mobile reporting of injuries, illnesses, near misses and hazards, with photos and witnesses; anonymous hazard reports allowed |
| Regulator notifications | Critical or serious injury and fatality notifications flagged as immediate; jurisdiction deadlines tracked |
| Workers' compensation claims | Employer reports to the provincial board (for example the employer's report of injury within the board's deadline, often three days); claim number, status, lost time, modified work, costs; experience rating impact |
| Investigation | Root cause analysis; corrective actions with owners and due dates; verification of completion |
| Hazard and risk assessment | Hazard register by site and job; controls; review dates; link to training requirements in Module 08 |
| Committees and representatives | Joint health and safety committees or representatives where thresholds require; members, certification, meeting minutes, recommendations and employer responses with legislated response times |
| Inspections | Workplace inspection schedules, checklists, findings and actions |
| WHMIS | Safety data sheet library by site; worker education records |
| Work refusals | Right-to-refuse process with each stage recorded, as legislated |
| Psychological safety | Optional program aligned with the CSA Z1003 standard |

**Metrics:** lost time injury frequency and severity, total recordable incident rate, days lost, claim costs, overdue corrective actions, committee recommendation response times.

## Harassment, violence, investigations and speak-up

**Prevention program:** policies and programs required by jurisdiction (for example Ontario's workplace violence and harassment policies and program with annual review; federal workplace harassment and violence prevention regulations with workplace assessment, prevention policy, designated recipient and training); risk assessments for workplace violence; training assignments through Module 08.

**Speak-up channel:** confidential intake by web, mobile and phone (third-party hotline option); anonymous reporting with two-way anonymous messaging; categories (harassment, discrimination, violence, safety, fraud, ethics, privacy); acknowledgment within a set time; protection against reprisal stated and monitored.

**Investigation case management:**

| Step | System support |
| --- | --- |
| Intake and triage | Category, severity, interim measures (separation of parties, leave with pay), conflict check on investigator |
| Investigation plan | Scope, allegations, investigator (internal or external), timelines per policy or regulation |
| Evidence | Interviews with notes and signed statements, documents, chain of custody |
| Findings | Each allegation substantiated or not, with reasons |
| Outcome | Corrective actions, discipline (through Core HR transactions with HR approval), communication of results to the parties as required (for example Ontario requires written results to the complainant and the alleged harasser) |
| Follow-up | Reprisal monitoring, climate actions, policy changes |

**Discipline records:** conduct-related discipline (as distinct from performance in Module 07) with progressive steps, union representation, and sunset clause enforcement from collective agreements.

**Access:** investigation files are visible only to assigned investigators and designated HR; parties never see each other's identities through the system beyond what the process requires.

## Labour relations

**Agreement administration:** agreement records and terms live in Core HR (Module 01); this module adds the full agreement text with article-level search, letters of understanding, memoranda of settlement, side agreements and interpretation notes, so managers can find the article that applies.

**Grievances:**

| Step | Detail |
| --- | --- |
| Filing | Grievor(s), union, article(s) cited, type (individual, group, policy), remedy sought, date filed |
| Steps | Configurable steps per agreement with time limits calculated automatically (including business-day rules) and reminders before they expire |
| Meetings | Dates, attendees, positions, notes |
| Responses | Written responses generated from templates and stored |
| Resolution | Settled, withdrawn, denied, referred to arbitration; settlement terms and any pay or record changes routed to the right module |
| Arbitration | Arbitrator, hearing dates, counsel, costs, award and implementation tracking |

**Bargaining support:** costing of union proposals using real payroll, benefits and schedule data (for example the cost of a 2% increase, an extra holiday or a premium change over the agreement term); proposal tracking by article and status; comparisons with other agreements; scenarios shared with Module 09 and Module 04.

**Union relations:** union contacts and stewards; joint committees; labour-management meeting minutes; information requests from the union with response dates; union leave tracking (Module 06); dues remittances (Module 03).

**Certification proceedings:** the system records only official proceedings (board applications, hearing dates, certificates issued) for legal follow-up. It never records or infers any individual employee's union support or activity, since that information is protected and collecting it could amount to interference.

## Employment equity, pay equity and accessibility

**Employment equity (federally regulated employers with 100 or more employees, and federal contractors):** workforce survey with voluntary self-identification; workforce analysis comparing representation of designated groups with labour market availability by occupational group; employment systems review; employment equity plan with goals and measures; annual report data including salary information; small-group suppression in every output. Provincially regulated employers can use the same tools voluntarily.

**Pay equity program administration:** committees, job class determination, gender predominance, evaluation, comparisons, required adjustments, postings and maintenance reviews, for the federal Pay Equity Act, Ontario and Quebec regimes and public-sector statutes; analytics come from Module 04.

**Accessibility:** organizational accessibility plans and progress reports where legislation requires them (for example federal entities under the Accessible Canada Act, Ontario AODA compliance reports); feedback process for accessibility barriers; accessible formats for employee documents on request; accommodation in recruitment (Module 02) and employment (accommodation cases above).

**Indigenous employment:** Indigenous hiring commitments, impact benefit agreement employment obligations, and reporting to communities or funders; s.87 tax exemption documentation (with Module 03); support for Indigenous organizations' own governance of HR data.

## Privacy and data protection program

The platform's technical controls are specified in Module 00 and each module; this section covers the customer's privacy program and the platform's own obligations as a service provider.

| Component | Capability |
| --- | --- |
| Accountability | Privacy officer designation (required in Quebec, with the title and contact published); privacy policies and notices by purpose; governance records |
| Inventory | Register of personal information held: categories, purposes, legal basis, retention, location, recipients |
| Privacy impact assessments | Templates and workflow for new systems, monitoring, AI features and cross-border transfers (Quebec Law 25 requires assessments before transferring personal information outside Quebec) |
| Consent and notices | Recorded consents for optional data (self-identification, biometrics, location, marketing to alumni), withdrawal handled |
| Access and correction requests | Request intake, identity verification, statutory response deadlines (for example 30 days), redaction support, response tracking |
| Retention and destruction | Retention schedules per data class and jurisdiction with legal holds; automated destruction or anonymisation with logs |
| Breach management | Incident intake, risk-of-significant-harm assessment, notification to regulators and individuals where required, breach register kept for the legislated period |
| Vendors | Service provider register, data processing agreements, sub-processor list, transfer assessments |
| Automated decisions | Notices and review requests where decisions rely on automated processing (Law 25), supported by the AI guardrails |

**CanDo as processor:** Canadian data residency; data processing agreement with every customer; sub-processor transparency; SOC 2 Type II and ISO 27001 targets; customer data export and deletion at contract end.

## Hiring compliance and immigration

Module 02 enforces these controls in the hiring workflow; this module holds the rules and the evidence.

| Area | Controls |
| --- | --- |
| Job postings | Pay disclosure where required (Module 04 has the jurisdiction table); no Canadian experience requirement in Ontario public postings; AI-use disclosure and existing-vacancy statement in Ontario; inclusive-language checks; accommodation statement |
| Applicant communications | Ontario requirement to tell interviewed applicants whether a decision has been made within the legislated period; posting and communication records retained for the required time |
| Pay history | Questions about prior pay blocked in jurisdictions that prohibit them |
| Human rights in selection | Interview questions screened for protected grounds; special programs and preferential hiring (for example Indigenous hiring preferences permitted under human rights law and agreements) documented with their legal basis |
| French language in Quebec | Postings and offers available in French; any requirement for a language other than French justified and the steps taken recorded, as Bill 96 requires |
| Background checks | Consent captured; checks limited to what the role justifies; police and vulnerable sector checks per role; protections against discrimination for pardoned or unrelated records in provinces that provide them; credit checks only where justified; results retained minimally |
| Immigration | Work permit type, conditions and expiry tracked; LMIA and employer-specific permit obligations (wages, duties, location) monitored so job changes that would breach permit conditions are flagged; compliance records kept for the period IRCC and ESDC can request them; permit renewal reminders |
| Unionized hiring | Posting periods, internal candidate rights and seniority-based selection rules enforced from agreement terms |

**Evidence pack:** for any hire, the system can assemble the posting, candidate communications, assessments, approvals and consents for an audit or complaint.

## Data model, integrations and security

| Entity | Key fields |
| --- | --- |
| Rule | Jurisdiction, law area, citation, conditions, parameters, effective dates, status, owner |
| Legislative Change | Source, summary, affected rules and customers, effective date, status |
| Obligation | Customer entity, type, frequency, due dates, owner, evidence |
| Policy | Jurisdiction, version, approval, distribution, acknowledgements |
| Accommodation Case | Employee or candidate, ground category, limitations, options, accommodations, reviews, outcome |
| RTW Plan | Case, weekly hours and duties, check-ins |
| Incident | Type, date, site, people, description, severity, notifications, actions |
| WCB Claim | Board, claim number, status, lost time, costs |
| Investigation | Category, parties (restricted), investigator, evidence, findings, outcome |
| Speak-up Report | Channel, category, anonymity, messages, status |
| Grievance | Agreement, articles, grievors, steps, deadlines, outcome, arbitration |
| Bargaining Proposal | Article, party, costing, status |
| Privacy Request / Breach | Type, dates, deadlines, actions, notifications |
| Inspection | Regulator, dates, orders, compliance dates |

**Integrations:** every module reads rules from the repository and writes compliance events (for example a missed final pay deadline or an overdue training) to the obligations register; external integrations with workers' compensation board portals, hotline providers, and legal research or legislative update services where available.

**Security:** separate access roles for accommodation coordinators, OHS staff, investigators, labour relations and privacy office; strictest default access in the platform; every view logged; legal privilege marking on documents prepared with counsel, with restricted sharing.

## Collective agreement library

Union terms come from the agreements themselves. The library imports agreements from government registries and the employer's signed copy, turns their terms into rules a specialist has checked, and keeps every generation.

&#91;embedded content: collective agreement library · import to rules, with the renewal loop\]

A renewal, memorandum of settlement or arbitration award re-enters at import, and the new rule set triggers retroactive pay in Module 03.

| Source | Content | Use |
| --- | --- | --- |
| [Negotech](https://negotech.service.canada.ca/search/index.html) (ESDC Labour Program) | Federal and provincial agreements received by the Labour Program, with several generations per bargaining relationship | Import, renewal monitoring, comparators for bargaining |
| Provincial and territorial registries | For example Ontario's Collective Agreements e-Library and databases in BC, Alberta, Newfoundland and Labrador, Nova Scotia, PEI, Yukon and the Northwest Territories ([U of T list](https://cirhr.library.utoronto.ca/research/collective-agreements)) | Same, where the agreement is filed provincially |
| The employer's signed agreement, memoranda of settlement and arbitration awards | The binding text | Always the version of record; registry copies are for comparison |

**Two-tier and sector agreements:** central or sectoral terms (for example province-wide education or health agreements) plus local terms for each employer, combined into one effective rule set per bargaining unit with the precedence each agreement sets.

**Controls:** registry copies may lag or differ from the signed text; the signed text always wins. Each rule cites its article. Language follows what was filed: agreements from organizations subject to the Official Languages Act are bilingual, others may be in one language.

## Public-sector obligations

| Area | Requirement |
| --- | --- |
| Freedom of information | Municipal and public bodies answer access requests under public-sector statutes (for example Ontario's MFIPPA, BC's FOIPPA); HR records searchable, exemptions applied, redaction and deadline tracking |
| Salary disclosure | Statutory public lists by threshold, produced from Module 03 data with review before publication |
| Essential services and interest arbitration | Essential service designations for police, fire, health and other services; interest arbitration timelines and awards tracked |
| Central bargaining | Employer associations and sector bargaining tables; costing at sector level |
| Official languages | Federal Official Languages Act, New Brunswick's Official Languages Act, Nunavut's official languages; documents and notices in each required language |
| Accessibility | Accessible Canada Act for federal bodies; provincial accessibility laws; plans and progress reports |
| First Nations jurisdiction | Labour jurisdiction of each First Nations employer recorded per activity: band governance is usually federal, while some services can be provincial; the determination is documented with counsel |

## How CanDo compares

None of the HRIS platforms reviewed markets accommodation, health and safety, investigations, grievances and an agreement library in the same system; employers typically use spreadsheets or separate EHS and case management tools. UKG, Dayforce and ADP reach unionized and public-sector employers through time, pay and workforce management depth, which CanDo must match in Modules 03 and 06. The library and case management in this module are where CanDo can lead. Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Reporting, implementation and open questions

**Reports:** obligations due and overdue; policy acknowledgement rates; accommodation case volumes, durations and outcomes; return-to-work success; OHS incident rates and corrective action status; claim costs; investigation volumes, timeliness and outcomes (aggregated); grievance volumes by article and step, time limits at risk, arbitration outcomes and costs; equity representation and gaps; privacy request timeliness; breach register; inspection orders.

**Implementation:**

| Step | Activities |
| --- | --- |
| 1. Applicability | Entities, jurisdictions, thresholds, agreements, sectors |
| 2. Obligations | Register generated and reviewed with the customer |
| 3. Policies | Existing policies loaded; gaps against requirements identified |
| 4. Programs | OHS, harassment, accommodation and privacy workflows configured |
| 5. Labour relations | Agreement texts loaded; open grievances migrated with deadlines |
| 6. Launch | Training for HR, managers, investigators and committee members |

**Sources:** compliance content in Recruitment 1.docx, DD Recruitment Module.docx and module 1 final april 19.docx (human rights, privacy, accessibility, Indigenous hiring, unionized hiring); payroll compliance, audit and records sections of the April 16 payroll file; hr-integration-architecture.svg. Pay transparency and Ontario posting rules checked against public sources in October 2026. Everything else is new drafting.

**Open questions:**

- [ ] Who owns the rules repository and legislative monitoring (in-house legal team, a legal content partner, or both) — linked to the statutory table ownership decision in Module 00
- [ ] Jurisdictions supported at launch
- [ ] Third-party hotline partner for the speak-up channel
- [ ] Scope of OHS features at launch versus integrating with dedicated EHS software
- [ ] Indigenous data governance commitments (OCAP®) and advisory process

**October 2026 review:** added the collective agreement library (Negotech and provincial registries), public-sector obligations, First Nations jurisdiction and competitor comparison; scope widened to all employer sizes and public-sector employers.
