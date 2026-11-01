# CanDo HRIS — 00 Master Platform Overview

Oct 17, 2026 · @Wael

CanDo HRIS is a Canadian-first, fully integrated HR platform of 14 modules that share one employee record, one rules engine and one compliance framework. This document is the index to the module specifications and the single source for shared architecture.

## Vision and positioning

CanDo HRIS automates the full employee lifecycle for Canadian organizations while keeping them continuously compliant with federal, provincial, collective-agreement and privacy rules. The name carries the "can do" spirit of Canadian work culture: proactive, solution-oriented, practical.

**Who it serves**

| Segment | Typical profile | What they need most |
| --- | --- | --- |
| Small and mid-sized employers | 25–499 employees, one or several provinces | Fast setup, payroll accuracy, simple self-service |
| Large employers and enterprises | 500 to 50,000+ employees, many entities, all provinces and territories | Scale, configurable workflows, multi-entity payroll, open APIs, enterprise security certifications |
| Municipal governments | Cities, regional districts, towns; CUPE and other locals, fire and police associations, transit, utilities | Several collective agreements at once, platoon and 24/7 scheduling, municipal pension plans, salary disclosure, council reporting, freedom-of-information duties |
| Provincial and territorial public sector | Ministries, agencies, Crown corporations, school boards, health authorities, colleges and universities | Sector-wide agreements, central bargaining, public-sector pension plans, accessibility and official-language obligations, procurement-grade security |
| First Nations governments and Indigenous organizations | Band and tribal councils, self-governing nations, Indigenous service organizations | Indian Act s.87 handling, federal jurisdiction for most band employment, funding-agreement reporting, cultural leave, data governance (OCAP®) |
| Non-profits and grant-funded organizations | Mixed funding, term positions, boards | Grant-funded position tracking, budget control, funder reporting |
| Unionized private-sector employers | Manufacturing, construction, transport, healthcare, retail | Agreement-specific rules engine, seniority, posting and selection compliance, retro pay, grievance tracking |
| Multi-jurisdiction employers | Federal plus all 13 provinces and territories, later European entities | Rules for every Canadian jurisdiction in one product, bilingual EN/FR, multi-currency, data residency |

**Design principles**

- **One employee record.** Every module reads and writes the same effective-dated employee, position and organization data. No re-keying between hiring, payroll and benefits.
- **Compliance by configuration.** Legislation and collective agreements are encoded as versioned, effective-dated rules, not custom code.
- **Rules before people.** Validations, eligibility and calculations run automatically; people handle exceptions, with every override logged.
- **Canada first, built to extend.** Canadian federal and provincial rules are native; US payroll is phased in; further jurisdictions plug into the same framework.
- **Inclusive by default.** WCAG 2.1 AA, English and Canadian French throughout, right-to-left layout support, Indigenous and DEI-aware workflows.
- **Explainable automation.** AI suggestions show their reasoning, are tested for bias, and never make a final employment decision on their own.
- **Modular adoption.** Any module can go live alone on top of Core HR; integrations switch on as more modules are added.

## Module map

Four modules are consolidated from existing specifications; ten are new drafts written from the workflow diagrams and the cross-references in the existing specs. Each module has its own document, numbered as below.

| # | Module | Purpose | Status | Main data it shares |
| --- | --- | --- | --- | --- |
| 00 | Master Platform Overview | Index, shared architecture, roadmap | Consolidated | — |
| 01 | Core HR & Position Management | Employee master record, organization, job architecture, position control, workforce events | New draft | Feeds every module |
| 02 | Recruitment & Onboarding | Requisition to probation completion and status conversion | Consolidated (largest source set) | Positions, offers, new-hire data to Core HR, Payroll, Benefits |
| 03 | Payroll | Gross-to-net, statutory deductions, disbursement, year-end, Canadian and US compliance | Consolidated | Earnings, deductions, GL, tax slips |
| 04 | Compensation Management | Job evaluation, market pricing, pay structures, merit and incentive planning, pay equity | Consolidated (market pricing guide + compensation content from Payroll) | Ranges, rates, increases to Payroll and Recruitment |
| 05 | Benefits Administration | Plans, eligibility, enrolment, life events, carriers, premiums | New draft | Elections and premiums to Payroll |
| 06 | Time, Attendance & Leave | Schedules, time capture, overtime, accruals, statutory and union leave | New draft | Approved time and leave to Payroll |
| 07 | Performance Management | Goals, check-ins, reviews, calibration, PIPs | New draft | Ratings to Compensation, probation results to Recruitment |
| 08 | Learning & Development | Courses, certifications, compliance training, skills | New draft | Completions to Core HR, Performance, Succession |
| 09 | Succession & Workforce Planning | Headcount plans, skills gaps, talent reviews, successor slates | New draft | Plans to Recruitment and Compensation budgets |
| 10 | Employee Engagement & Recognition | Surveys, pulse checks, recognition, employee voice | New draft | Sentiment to Analytics, awards to Payroll |
| 11 | Offboarding & Separation | Resignation to final pay, ROE, access removal, exit insight | New draft | Termination events to Payroll, Benefits, IT |
| 12 | Analytics & Reporting | Cross-module reports, dashboards, predictive models, BI exports | New draft | Reads every module |
| 13 | Compliance, Labour Relations & Privacy | Multi-jurisdiction rules, collective agreements, privacy, accessibility, equity | Consolidated from the compliance sections of 02 and 03 | Rules consumed by every module |

Employee and manager self-service are not separate modules. Each module specifies its own self-service screens, and they appear together in one portal.

## Employee lifecycle coverage

The lifecycle runs as a loop around the Core HRIS record: planning creates positions, positions are filled, people develop and are retained, and departures feed the next plan. Every stage below has an owning module.

| Lifecycle stage | Activities | Owning module | Supporting modules |
| --- | --- | --- | --- |
| Workforce planning | Headcount planning, skills gap analysis, talent forecasting, budget alignment | 09 | 01, 04, 12 |
| Position management | Job descriptions, job classifications, org structure, position control, vacancy management, position budget | 01 | 04, 09 |
| Recruitment | Requisition creation, approval workflow, job posting, screening, interviews, offer | 02 | 01, 04, 13 |
| Onboarding | Pre-boarding, documentation, system access, equipment, orientation, training, probation, status conversion | 02 | 03, 05, 06, 08 |
| Development | Performance reviews, goal setting, career planning, learning, skills assessment, certification tracking | 07, 08 | 09 |
| Retention | Compensation management, benefits administration, recognition programs, engagement surveys | 04, 05, 10 | 03, 12 |
| Succession | Talent assessment, high-potential identification, critical role planning, readiness rating | 09 | 07, 08 |
| Offboarding | Resignation or termination, exit interview, knowledge transfer, asset recovery, system deactivation, final documentation | 11 | 03, 05, 13 |

Status changes inside the lifecycle (probation to regular, temporary to regular, auxiliary to regular, transfers, promotions, leaves and returns) are recorded once in Core HR as effective-dated personnel actions. Each downstream module reacts to the action rather than to a manual update.

## Integration architecture

Core HRIS is the hub: it owns employee records, position management, organization structure and the event stream that every other module subscribes to. All module links are bi-directional except Analytics, which only reads.

**Internal flows**

| From | To | Data | Direction | Timing |
| --- | --- | --- | --- | --- |
| Core HR (01) | All modules | Employee, position, org, status events | Bi-directional | Real-time events |
| Recruitment (02) | Core HR, Payroll, Benefits, Time, Learning | New-hire record, compensation, tax forms, banking, eligibility, schedule, onboarding learning path | Bi-directional | On hire confirmation |
| Compensation (04) | Payroll, Recruitment | Ranges, steps, approved increases, offer guidelines | Bi-directional | Effective-dated |
| Benefits (05) | Payroll | Elections, premiums, employer cost, taxable benefits | Bi-directional | Per pay period and on life events |
| Time & Leave (06) | Payroll | Approved hours, overtime, premiums, leave taken, balances | Bi-directional | Per pay period cut-off |
| Performance (07) | Compensation, Recruitment, Succession | Ratings, goal results, probation outcomes | Bi-directional | Per cycle |
| Learning (08) | Core HR, Performance, Succession, Compliance | Completions, certifications, expiry dates, skills | Bi-directional | Real-time |
| Offboarding (11) | Payroll, Benefits, IT identity | Termination date and reason, payouts, coverage end, deprovisioning | Bi-directional | On termination event |
| Compliance (13) | All modules | Jurisdiction rules, agreement rules, retention schedules | Bi-directional | Effective-dated |
| All modules | Analytics (12) | Transactions and snapshots | Uni-directional | Near-real-time and nightly |

**External systems**

| Category | Examples | Pattern |
| --- | --- | --- |
| Job boards and sourcing | Indeed, LinkedIn, Workopolis, Job Bank, ZipRecruiter, IndigenousWorks, DiverseCity, Google for Jobs | XML feeds and APIs, source tracking |
| Screening and assessment | Background check providers, assessment platforms, reference tools, video interview platforms | API with status webhooks |
| Identity and access | Active Directory or Azure AD, Okta, OneLogin | SAML or OAuth SSO, just-in-time provisioning, automated deactivation |
| Collaboration | Google Workspace, Microsoft Outlook and Teams, Slack, Zoom | Calendar and notification connectors |
| Documents and e-signature | DocuSign, Adobe Sign, HelloSign, SharePoint, Google Drive | API, signed-packet archiving |
| Finance | QuickBooks, SAP, Oracle and other ERPs, banks | GL journals, CPA-005 EFT, NACHA ACH, positive pay |
| Government | CRA (ROE Web, T4/T4A XML, PD7A), Revenu Québec (RL-1), workers' compensation boards, IRS and states | Electronic filing and remittance |
| Benefits and pensions | Insurance carriers, pension and RRSP administrators | Eligibility files, premium and contribution files |
| BI tools | Power BI, Tableau, Looker Studio | Governed data exports and connectors |

The original architecture and lifecycle diagrams (hr-integration-architecture.svg, employee-lifecycle-workflow.svg) remain in the project as visual references.

## Shared platform services

Every module is built on the same eight services, so a capability specified here is not repeated in the module documents.

| Service | What it provides |
| --- | --- |
| Identity and access | SSO (SAML 2.0, OAuth 2.0), MFA by role, role-based access control down to field and document level, record-level scoping (self, team, department, business unit, all), delegation with time limits, timed guest access for agencies and contractors, automatic deactivation of stale accounts |
| Workflow engine | Sequential, parallel and hybrid approvals; conditional routing by amount, percentage, position type, department or jurisdiction; delegation; SLA timers; escalation; mobile approval; self-approval prevention; "if this then that" triggers |
| Rules engine | Effective-dated, versioned rules for legislation, collective agreements and policy; eligibility, calculation, proration, rounding and accumulation rules; scenario testing before activation; parallel rule sets during transitions |
| Audit and evidence | Every create, change, view of sensitive data, approval and export logged with user, timestamp, IP and device, before and after values and reason; non-modifiable history; exportable audit packs; SIEM integration |
| Notifications | In-app, email, SMS and mobile push; templated and bilingual; digest options; escalation chains; calendar invitations |
| Documents | Template library with clause logic and version control; e-signature; encrypted repository; classification labels; retention and legal hold; secure, time-limited sharing links |
| Integration layer | REST API (JSON primary, XML secondary) with URL versioning; OAuth 2.0, API keys, JWT and client certificates; webhooks with signed payloads and retries; bulk and batch endpoints; SFTP with PGP for files; sandbox with sample data; developer portal |
| Localization and accessibility | English and Canadian French throughout; optional Arabic, Indigenous languages and others; left-to-right and right-to-left layouts; regional date, number, address and currency formats; WCAG 2.1 AA, screen reader, keyboard-only and high-contrast modes |

**Security baseline**

- Encryption in transit with TLS 1.2 or higher and at rest with AES-256; field-level encryption for SIN or SSN, banking, salary and health data; managed keys with rotation.
- Masked display by default (for example SIN shown as XXX-XXX-123), with full view only for authorized roles and every full view logged.
- Production data masked in non-production environments; data minimization and purpose limitation enforced in forms.
- Segregation of duties: payroll preparation separate from approval, bank-file release under dual control, master-data changes separate from payment authorization.
- Incident response and breach notification workflow aligned to PIPEDA, provincial and Quebec requirements.

**AI and automation principles**

- Uses: resume parsing, candidate matching, interview question suggestions, task nudging, attrition and early-turnover risk flags, anomaly detection in payroll, forecasting, natural-language queries.
- Guardrails: explainable scores, bias testing on a schedule, optional blind review mode, human approval for any hiring, pay, discipline or termination decision, opt-out where law requires, model retraining reviewed for fairness.

## Technology and deployment

CanDo HRIS is a cloud SaaS platform hosted in Canada by default, with an optional hybrid integration layer for on-premise systems.

| Area | Specification |
| --- | --- |
| Application tiers | Database layer (secure transactional store), business logic layer (calculation and processing services), API layer (integration services), presentation layer (web and mobile) |
| Hosting | Containerized services, geographic redundancy, separate development, test, staging and production environments, secure channels for all traffic |
| Data residency | Canadian tenant data stored and backed up in Canada; region-specific instances for other jurisdictions (EU under GDPR, US states, future Middle East localization); cross-border transfers only with documented authorization |
| Multi-instance options | Region-specific installations with controlled synchronization of master data and cross-instance reporting |
| Mobile | Responsive web plus native-feel mobile app: biometric login, push notifications, offline time capture with sync, approvals on the go |
| Performance | Pagination and indexing on large lists, background processing for payroll runs and bulk jobs, rate limiting on APIs |
| Business continuity | Payroll continuity plan, alternate processing procedure, manual cheque fallback, defined recovery time objectives |

**Build approach in the current files**

The recruitment module also exists as a Bubble.io build guide (enhanced-recruitment-module.js and three Bubble PDFs). It defines eight data types (Job Posting, Candidate, Interview, Requisition, Assessment, Approval Workflow, Offer, Onboarding Plan), seven UI areas, eight workflows and a 14-week, seven-phase build plan. Bubble is well suited to a recruitment and onboarding prototype or first release. The payroll calculation engine, statutory tax tables and bank-file generation need a conventional backend service with automated test suites, because their accuracy is audited and their rules change every year. The detailed data types are carried into Module 02.

## Implementation roadmap

The platform is delivered in six phases, each gated on the previous phase running cleanly in production. Phases 3 and later depend on Core HR and the compliance framework being live.

| Phase | Modules | Gate to move on |
| --- | --- | --- |
| 1. Foundation | 01 Core HR & Position Management, 13 Compliance framework, shared services | Employee, position and org data migrated and reconciled; roles and SSO live |
| 2. Hire | 02 Recruitment & Onboarding (Bubble MVP route possible, about 14 weeks) | First requisitions posted and filled end to end; new-hire data reaching Core HR without re-keying |
| 3. Pay | 03 Payroll (Canada), 06 Time, Attendance & Leave, 05 Benefits, 11 Offboarding | Two to three clean parallel payroll runs against the legacy system; CRA and RQ remittances reconciled |
| 4. Reward and develop | 04 Compensation, 07 Performance, 08 Learning | First merit cycle and first review cycle completed in-system |
| 5. Talent and insight | 09 Succession & Workforce Planning, 10 Engagement & Recognition, 12 advanced analytics | Talent review held in-system; executive dashboards adopted |
| 6. Expansion | US payroll (single state, then multi-state, then all states and local, then cross-border), further jurisdictions | Jurisdiction-by-jurisdiction compliance certification |

**Standard method for every module**

1. Discovery: current-state process maps, stakeholder interviews, compliance requirements by jurisdiction, integration inventory, data readiness assessment, success criteria.
2. Design and configuration: org structure, roles and permissions, workflows, templates, custom fields, notifications, compliance rules, reports.
3. Integration and migration: connectors, field mapping, transformation rules, historical data conversion, balancing routines.
4. Testing: unit, integration, end-to-end scenarios, performance and load, security and penetration, accessibility, mobile, user acceptance, regression; parallel runs for anything that pays people.
5. Training and change management: role-based curriculum, super users and champions, job aids, communication plan, adoption tracking.
6. Go-live and hypercare: cutover plan, go/no-go meeting, daily check-ins, rapid issue resolution for four to six weeks.
7. Post-implementation: 30-day review, lessons learned, KPI measurement against baseline, continuous improvement backlog.

Reference durations from the payroll specification: requirements 4–6 weeks, configuration 8–12 weeks, testing 6–8 weeks, training 3–4 weeks, 2–3 parallel cycles, 2 weeks go-live preparation, 4–6 weeks post-go-live support.

## Commercial packaging (proposed)

These models come from the licensing and support sections in DD Recruitment Module.docx, which were transcribed from a third-party vendor document. They are a starting point for CanDo pricing, not a decision.

| Element | Options |
| --- | --- |
| Licensing model | Per user by type (administrator, recruiter, hiring manager, executive, self-service); tiered by employee count; enterprise agreement with unlimited users |
| Modules | Core HR included; each other module licensed separately or in bundles; add-ons for advanced analytics, multi-language packs, mobile, document management, candidate CRM |
| Services | Discovery, configuration, integration, data migration, testing, training and change management, go-live support, post-implementation review |
| Standard support | Business hours, 24-hour response, knowledge base, monthly updates, community forum |
| Premium support | 24/7, 4-hour response for critical issues, named contacts, quarterly reviews, early feature access |
| Enterprise support | Dedicated technical account manager, 1-hour critical response, proactive monitoring, sandbox refreshes, custom training, release impact assessments |

## Market scope and jurisdiction coverage

CanDo serves employers of every size in Canada, from 25 employees to public-sector organizations with tens of thousands, and must be fully compliant in all 14 Canadian jurisdictions: federal, 10 provinces and 3 territories. Europe is the first international market after Canada.

| Jurisdiction group | What the platform must cover |
| --- | --- |
| Federal (Canada Labour Code) | Banks, telecoms, interprovincial transport, federal Crown corporations and most First Nations band council employment; federal pay equity, employment equity and harassment regulations |
| Atlantic provinces (NL, PE, NS, NB) | Provincial tax via CRA; NL health and post-secondary education tax; PEI pay transparency; mid-year 2026 tax changes in NL and PEI |
| Quebec | Revenu Québec tax and RL slips, QPP, QPIP, reduced EI, HSF, CNESST, the 1% training law, the Charter of the French Language (see Quebec assessment) |
| Ontario, Manitoba, Saskatchewan, Alberta, British Columbia | Provincial tax via CRA; employer health taxes in ON, MB and BC; pay transparency in ON and BC; BC mid-year 2026 tax change |
| Yukon, Northwest Territories, Nunavut | Territorial tax via CRA; 2% employee payroll tax in NT and NU remitted to the territories; northern residents deductions; territorial holidays such as Nunavut Day; WSCC for NT and NU |

The per-jurisdiction detail lives in Module 03 (payroll), Module 06 (hours, holidays and leave), Module 11 (notice and severance) and Module 13 (regulators and statutes).

## Enterprise scale

The same product must run a 25-person non-profit and a 30,000-employee municipality or health authority. These are design targets to be proven in load testing, not measured results.

| Requirement | Design target |
| --- | --- |
| Volume | 100,000 active employee records per tenant; pay runs of 50,000 employees completed within a two-hour window through parallel calculation |
| Structure | Unlimited legal entities, CRA payroll program accounts, Revenu Québec accounts, pay groups and collective agreements per tenant |
| Environments | Production plus sandbox and test tenants with data masking; configuration promoted between them with approval |
| Availability | 99.9% monthly uptime target, recovery point of 15 minutes and recovery time of 4 hours, Canadian primary and backup regions |
| Identity | SAML and OpenID Connect single sign-on, SCIM provisioning, delegated administration by entity |
| Integration | Bulk APIs and event streams with published rate limits; flat-file interfaces for legacy ERPs |
| Assurance | SOC 2 Type II and ISO 27001; alignment with Canadian Centre for Cyber Security cloud guidance for public-sector buyers; WCAG 2.1 AA; English and French |
| Procurement | Standard responses for public-sector RFPs: residency, accessibility, official languages, security, exit and data return |

## Government and public-sector integration

&#91;embedded content: government integration · 9 external bodies, 3 platform services\]

The agreement library is what makes union and public-sector customers workable at scale: collective agreements filed with ESDC's Negotech and the provincial registries are imported, their pay grids, premiums, leave and seniority terms are extracted into rules with human verification, and every module then reads the same terms. Module 13 specifies the library; Modules 03 and 05 specify the filing and pension interfaces.

## Competitive position

The [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0) compares CanDo with Dayforce, ADP, UKG, Workday, Rippling, HiBob, BambooHR, Sparkrock, Humi by Employment Hero, Payworks, Collage, Folks, Nethris and Rise. The enterprise suites cover Canadian rules deeply but are priced and implemented for large employers; the Canadian SMB tools each cover part of the rules. CanDo's position: every Canadian jurisdiction, public-sector and union depth, Indigenous governance and compliance case management in one Canadian-owned, Canadian-hosted product that scales from SME to government.

To filter the vendors by segment, compare up to three side by side against CanDo's target, or look up a module or jurisdiction, open the interactive [CanDo Vendor Explorer](https://claude.ai/artifact/RFLT6phVob9B2BuBotcv3G).

## Quebec: assessment and recommendation

Quebec is the hardest jurisdiction, but excluding it would rule out most national employers, many federally regulated and public-sector buyers, and Canada's second-largest provincial workforce. The recommendation is to design for Quebec from day one and switch on Quebec payroll in phase 2.

**What Quebec adds on top of the rest of Canada:**

| Area | Requirement |
| --- | --- |
| Provincial tax | Revenu Québec's own formulas and employer guide instead of CRA's provincial tables; a second remittance channel |
| Slips and filing | RL-1 slips and the RLZ-1.S summary alongside the T4; online transmission |
| Software certification | Revenu Québec authorization and certification numbers for the product, requested each year by 1 February and tested against their cases |
| Social programs | QPP instead of CPP, QPIP, the reduced Quebec EI rate |
| Employer contributions | Health Services Fund, CNESST (labour standards and health and safety), the 1% workforce skills development rule |
| Language | Charter of the French Language as amended by Bill 96: French work tools, documents, contracts and communications |
| Privacy | Law 25: privacy impact assessments, including before data leaves Quebec |
| Sector rules | CCQ construction payroll and reporting; Quebec pay equity regime |

**Options for your decision:**

| Option | What it means | Trade-off |
| --- | --- | --- |
| A. Exclude Quebec | No Quebec employees supported | Simplest build; loses national employers, many unions and much of the public sector |
| B. Phase 2 (recommended) | French interface and Quebec data model from day one; payroll for the other 12 provinces and territories and federal employers first; Quebec payroll after Revenu Québec certification; in between, HR modules for Quebec staff plus a payroll export to a certified Quebec provider | Keeps national and public-sector deals open without delaying launch |
| C. Quebec at launch | Full Quebec payroll in the first release | Needed only if anchor customers are national or Quebec-based; longest path to launch |

A French interface is required in any of these options for New Brunswick, federal institutions and any Quebec employer using the HR modules, so it is not extra Quebec cost.

## Europe readiness

Europe follows Canada. The Canadian build keeps country logic in the rules repository so a European country can be added as a country pack rather than a rewrite.

| Area | Readiness requirement |
| --- | --- |
| Data model | Country packs for statutory fields, holidays, leave and documents; multi-currency; languages beyond EN and FR |
| Privacy | GDPR: lawful basis per purpose, data protection impact assessments, data subject requests, EU data region, transfer safeguards |
| Pay transparency | The EU Pay Transparency Directive (transposition deadline 7 June 2026): pay ranges before interview, no pay history questions, gender pay gap reporting, employee right to pay information; Module 04 analytics reused |
| AI | The EU AI Act treats employment AI as high-risk; the Digital Omnibus adopted in 2026 moved those obligations to 2 December 2027; CanDo's AI guardrails are designed to meet them |
| Employee representation | Works council information and consultation steps in workflows that change pay, monitoring or organization |
| Payroll | Partner payroll providers per country first; native payroll only for priority countries |

## Source inventory

All 31 project files were opened. Twenty-two had readable text and were merged; nine could not be read as text and are listed so nothing is assumed to be covered by them.

| File | What it is | Readable | Used in |
| --- | --- | --- | --- |
| Recruitment 1.docx | Fullest recruitment and onboarding spec, role matrix, 7-phase implementation checklist | Yes | 02 (base), 12, 13 |
| module 1 final april 19.docx | April 19 recruitment spec with compliance elements; text stops partway through section 3.6 | Yes (partial) | 02, 13 |
| DD Recruitment Module.docx | Design document with AI, Indigenous onboarding tracks, agency portal, roadmap; second half is a transcribed vendor document (case studies, pricing) | Yes | 02, 00, 12, 13 |
| CanDo\_HRIS\_Recruitment\_Onboarding\_Module\_Specification.docx | Executive summary only; rest points to a canvas no longer available | Yes (summary) | 02 |
| CanDo\_HRIS\_Recruitment\_Onboarding\_FULL\_Specification.docx | Section outline only | Yes (outline) | 02 |
| enhanced-recruitment-module.js | Bubble.io build guide: data types, UI, workflows, 14-week plan | Yes | 02, 00 |
| CanDoHRIS\_Payroll\_Module\_Combined\_FULL April 16 2025.docx | Latest payroll superset: summary spec, detailed spec, Canadian implementation guide, appendices | Yes | 03 (base), 04, 06, 13 |
| CanDoHRIS\_Payroll\_Module\_Combined\_FULL.docx, Payroll Module 1.docx, Can Do HRIS Payroll Module 2.docx, CanDoHRIS\_Payroll\_Module\_Full.docx, CanDo\_HRIS\_Payroll\_Module.docx, CanDoHRIS\_Payroll\_Module\_Complete.docx, CanDoHRIS\_Payroll\_Module\_FULL\_REDO.docx | Earlier payroll versions | Yes | Cross-checked against the April 16 file; only difference found is the jurisdiction scope noted in 03 |
| Compensation module 3.docx | Market pricing implementation guide | Yes | 04 (base) |
| Six .svg workflow diagrams | Integration architecture, lifecycle, recruitment, onboarding and probation, status conversion, performance management | Yes | 00, 02, 07 and the new-draft modules |
| CanDo HRIS\_ Recruitment & Onboarding Module C.docx and Module D.docx | Word exports of PDFs | Empty (text sits in drawing objects) | Not used |
| Module C.pdf, Module D.pdf, Module C.xml | PDF and Acrobat XML exports | No (embedded font encoding) | Not used; tables of contents match the readable recruitment files |
| Three Bubble implementation PDFs, Detailed Requisition Management Implementation Guide.pdf, Talent Acquisition System Vendor Comparison.pdf | Build guides and vendor comparison | No (embedded font encoding) | Not used |

Uploading Word or plain-text versions of the five unreadable guides would let them be folded into 02 and 00.

## Open decisions

- [ ] Jurisdiction scope at launch: all 13 provinces and territories plus federally regulated employers; Quebec at launch or in phase 2 (see Quebec assessment); Europe as the first international market; US only if a customer requires it.
- [ ] Build path: Bubble for Recruitment & Onboarding as an MVP, or one stack for every module from the start?
- [ ] Statutory tables now carry the 2026 values from CRA T4127 (122nd and 123rd editions); confirm who owns the January and July updates, Revenu Québec's annual software certification, and provincial and territorial changes.
- [ ] Performance targets in the recruitment specs (40–60% faster time-to-hire, 35% less early turnover, 85% fewer admin tasks) are presented as targets; confirm whether to keep them in customer-facing material without pilot data.
- [ ] Pricing model: per-user, per-employee tier, or enterprise; which modules are bundled with Core HR.
- [ ] Indigenous-specific features (s.87 exemption, ceremonial leave, culturally aligned onboarding, land acknowledgment): confirm the community advisory process for designing them.
- [x] Languages beyond English and French at launch. **Decided 25 Oct 2026:** the database is ready for any language now; screens are in English and French at launch; other languages (Indigenous languages, Arabic and others) are added as data and screen resource files (`docs/22` §4).
