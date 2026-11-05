# CanDo HRIS — 13 Compliance, Labour Relations & Privacy

Oct 17, 2026 · @Wael

> **Reviewed 3 Nov 2026.** Decisions in `docs/34-compliance-labour-relations-privacy-decisions.md`, applied in migration `schema/0020_compliance_labour_relations_privacy_decisions.sql`. This is the last of the thirteen module reviews. Inline notes below point to the relevant docs/34 section; the five open questions this module could close are closed at the bottom, and the sixth (Indigenous data governance / OCAP) stays open.

## Overview and scope

> **Draft status:** new specification. Brings together the compliance content spread through the recruitment files (human rights, privacy, accessibility, Indigenous hiring, collective agreement hiring rules) and the payroll files (statutory compliance, audit, records), and adds the programs that had no source.

Compliance, Labour Relations & Privacy is where an organization manages its legal obligations as programs: knowing what applies, doing it on time, handling cases fairly and proving it. Other modules enforce rules in their own transactions; this module owns the rules repository, the obligations calendar and the case management for accommodation, health and safety, harassment and labour relations.

**In scope:** regulatory rules repository and change monitoring; compliance calendar; human rights accommodation and return to work; occupational health and safety; workplace harassment and violence programs and investigations; confidential speak-up channel; labour relations (agreements, grievances, bargaining support, arbitration); employment equity, pay equity program administration and accessibility; privacy program; immigration and hiring compliance support.

**Not legal advice:** the module tracks and applies rules and records decisions. Customers remain responsible for legal interpretation, and content is reviewed by Canadian employment counsel before release. *(docs/34 §1: this is why `compliance.rule_ai_interpretation_enabled` is locked off forever — no AI feature interprets, summarizes or drafts an opinion on what a law requires.)*

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

> **Decided (docs/34 §3):** CanDo seeds a starter/reference copy by jurisdiction (`ref.rule_starter`, CanDo-verified before loading); **the organization owns keeping its own copy current** from there (`compliance.rule`). A seeded rule starts as a draft and can go active only once the organization records an owner and its own review — CanDo never silently re-syncs a live tenant's rules. This is distinct from the statutory-tables precedent (payroll tax tables, employment standards), which CanDo does own and maintain centrally; the rules repository here covers far more fact-specific, jurisdiction-specific ground than a single verifiable number.

**Change monitoring:** legislative and regulatory changes tracked from government sources; each change logged with impact assessment (which rules, modules and customers), target date and status; customers notified in plain language before effective dates. *(`compliance.legislative_change`, docs/34 §3.)*

## Compliance calendar and obligations tracking

**Obligations register:** every recurring obligation for the customer, generated from their entities, jurisdictions, size thresholds and agreements: filings, remittances, postings (for example employment standards posters, pay equity results), policy reviews (for example annual workplace violence and harassment policy review in Ontario), training renewals, committee meetings and inspections, privacy reviews, agreement expiry and bargaining notice windows. *(`compliance.obligation`, docs/34 §4; COMPL-001.)*

**Calendar:** due dates with owners; reminders ahead of deadlines (`compliance.obligation_reminder_days`, default 30); evidence upload when done; overdue escalation; view by month, by entity and by law area.

**Policy library:** required policies per jurisdiction with templates, versions, approval, distribution and employee acknowledgement tracked (shared document service); policies due for review flagged. *(`compliance.policy` / `compliance.policy_acknowledgement`, docs/34 §5.)*

**Self-assessments:** periodic checklists by law area (for example an employment standards self-audit) with findings and remediation actions. *(Scope cut: not built — no story AC covers a self-assessment checklist; a future addition on top of the obligations register.)*

**Inspections and audits:** visits from labour inspectors, health and safety officers, CRA payroll audits or privacy regulators logged with requests, documents provided, orders received, compliance dates and closure. *(`compliance.inspection`, docs/34 §6.)*

## Human rights, accommodation and return to work

**Accommodation cases:** request from the employee, a manager, a candidate (from Module 02) or a disability claim (Module 05); grounds category (disability, religion, family status, sex including pregnancy, and other protected grounds) recorded without diagnosis; functional limitations and restrictions from medical providers (not medical details); options considered with reasons; agreed accommodations (modified duties, schedules, equipment, leave, alternate role); undue hardship assessment documented where accommodation is refused; review dates; outcome. *(`compliance.accommodation_case`, docs/34 §7; EQ-002. The outcome goes through the new `accommodation_outcome` route; neither the case owner nor the employee can approve it.)*

**Return to work:** graduated return plans with hours and duties by week; coordination with STD or LTD carriers and workers' compensation boards; check-ins; adjustments; schedule and pay changes pushed to Modules 06 and 03. *(`compliance.rtw_plan`, docs/34 §7 — deliberately linked to either an accommodation case or a WCB claim, since the law requires RTW planning for a workplace injury either way.)*

**Duty to accommodate safeguards:** prompts when the system sees signals that may trigger the duty (repeated absences, performance concerns after a leave, requests mentioning a protected ground) so managers involve HR; attendance and performance processes in Modules 06 and 07 pause or exclude protected absences.

**Confidentiality:** case files restricted to the accommodation coordinator and HR; managers see only the agreed accommodations they must implement; medical documents, if received, stored in a sealed section with separate access logging and retention. *(Every view is logged — `compliance.case_view_log`, docs/34 §13.)*

**Human rights complaints:** complaints to a tribunal or commission tracked with deadlines, representatives, documents and outcomes. *(Scope cut: not a separate table — tracked as an `compliance.investigation` of category `discrimination` or as `compliance.legal_hold`/document attachments against the accommodation case; no story AC calls for a dedicated tribunal-complaint entity.)*

## Occupational health and safety

> **Decided (docs/34 §8):** full in-house case management, not integration with a separate EHS product — CanDo's stated differentiator (see "How CanDo compares" below).

| Capability | Detail |
| --- | --- |
| Incident reporting | Mobile reporting of injuries, illnesses, near misses and hazards, with photos and witnesses; anonymous hazard reports allowed *(`compliance.incident`, `kind` distinguishes a hazard observation from an injury)* |
| Regulator notifications | Critical or serious injury and fatality notifications flagged as immediate; jurisdiction deadlines tracked *(`compliance.incident.is_critical_injury`, `regulator_notified_at`)* |
| Workers' compensation claims | Employer reports to the provincial board (for example the employer's report of injury within the board's deadline, often three days); claim number, status, lost time, modified work, costs; experience rating impact *(`compliance.wcb_claim`)* |
| Investigation | Root cause analysis; corrective actions with owners and due dates; verification of completion *(`compliance.incident.corrective_actions`)* |
| Hazard and risk assessment | Hazard register by site and job; controls; review dates; link to training requirements in Module 08 *(folded into `compliance.incident` with `kind = 'hazard_observation'` rather than a separate table)* |
| Committees and representatives | Joint health and safety committees or representatives where thresholds require; members, certification, meeting minutes, recommendations and employer responses with legislated response times *(`compliance.ohs_committee`, meetings kept inline)* |
| Inspections | Workplace inspection schedules, checklists, findings and actions *(`compliance.inspection`)* |
| WHMIS | Safety data sheet library by site; worker education records *(`compliance.sds_document`; worker education tracked as training in Module 08, not duplicated here)* |
| Work refusals | Right-to-refuse process with each stage recorded, as legislated *(`compliance.work_refusal`)* |
| Psychological safety | Optional program aligned with the CSA Z1003 standard *(scope cut: not built — no story AC covers a dedicated psychological-safety program beyond the harassment/violence policy and incident tracking already built)* |

**Metrics:** lost time injury frequency and severity, total recordable incident rate, days lost, claim costs, overdue corrective actions, committee recommendation response times. *(Fed by `compliance.incident`/`compliance.wcb_claim` into Module 12's reporting layer.)*

## Harassment, violence, investigations and speak-up

**Prevention program:** policies and programs required by jurisdiction (for example Ontario's workplace violence and harassment policies and program with annual review; federal workplace harassment and violence prevention regulations with workplace assessment, prevention policy, designated recipient and training); risk assessments for workplace violence; training assignments through Module 08. *(`compliance.policy`, category `harassment_violence`.)*

**Speak-up channel:** confidential intake by web, mobile and phone (third-party hotline option); anonymous reporting with two-way anonymous messaging; categories (harassment, discrimination, violence, safety, fraud, ethics, privacy); acknowledgment within a set time; protection against reprisal stated and monitored.

> **Decided (docs/34 §9):** built in-house — `compliance.speakup_report` / `compliance.speakup_message` — not a third-party hotline partner, so case management stays in one system. A named report must name a reporter (`speakup_identity_consistent`); an anonymous reporter checks back in with a rotating case token. `compliance.speakup_ack_hours` (default 48) is the first-acknowledgement SLA.

**Investigation case management:**

| Step | System support |
| --- | --- |
| Intake and triage | Category, severity, interim measures (separation of parties, leave with pay), conflict check on investigator |
| Investigation plan | Scope, allegations, investigator (internal or external), timelines per policy or regulation |
| Evidence | Interviews with notes and signed statements, documents, chain of custody |
| Findings | Each allegation substantiated or not, with reasons |
| Outcome | Corrective actions, discipline (through Core HR transactions with HR approval), communication of results to the parties as required (for example Ontario requires written results to the complainant and the alleged harasser) |
| Follow-up | Reprisal monitoring, climate actions, policy changes |

*(`compliance.investigation`, docs/34 §9. "Evidence" and "chain of custody" detail live as `platform.document` attachments rather than a separate evidence-pack table — scope cut, no story AC calls for a dedicated chain-of-custody ledger.)*

**Discipline records:** conduct-related discipline (as distinct from performance in Module 07) with progressive steps, union representation, and sunset clause enforcement from collective agreements. *(`compliance.discipline_record`, docs/34 §9 — never shared with a performance review, the same separation `docs/28` already keeps.)*

**Access:** investigation files are visible only to assigned investigators and designated HR; parties never see each other's identities through the system beyond what the process requires.

## Labour relations

**Agreement administration:** agreement records and terms live in Core HR (Module 01); this module adds the full agreement text with article-level search, letters of understanding, memoranda of settlement, side agreements and interpretation notes, so managers can find the article that applies. *(Already built — `core.agreement`/`core.agreement_version`, migration 0003, `docs/08`.)*

**Grievances:**

| Step | Detail |
| --- | --- |
| Filing | Grievor(s), union, article(s) cited, type (individual, group, policy), remedy sought, date filed |
| Steps | Configurable steps per agreement with time limits calculated automatically (including business-day rules) and reminders before they expire |
| Meetings | Dates, attendees, positions, notes |
| Responses | Written responses generated from templates and stored |
| Resolution | Settled, withdrawn, denied, referred to arbitration; settlement terms and any pay or record changes routed to the right module |
| Arbitration | Arbitrator, hearing dates, counsel, costs, award and implementation tracking |

*(`compliance.grievance`, docs/34 §10; LR-010. Steps and arbitration detail kept as structured fields on the one row, read as a case file, not joined across a steps table. A settlement goes through the new `grievance_settlement` route; the officer who proposed it cannot approve it herself.)*

**Bargaining support:** costing of union proposals using real payroll, benefits and schedule data (for example the cost of a 2% increase, an extra holiday or a premium change over the agreement term); proposal tracking by article and status; comparisons with other agreements; scenarios shared with Module 09 and Module 04. *(`compliance.bargaining_proposal`, docs/34 §10 — tracking and a non-binding cost estimate only; like `comp.bargaining_scenario`, a proposal never changes pay or terms by itself.)*

**Union relations:** union contacts and stewards; joint committees; labour-management meeting minutes; information requests from the union with response dates; union leave tracking (Module 06); dues remittances (Module 03). *(Scope cut: contacts, joint-committee minutes beyond OHS, and labour-management meeting minutes are not built — no story AC covers them; union leave and dues remittance are already handled in Modules 06 and 03.)*

**Certification proceedings:** the system records only official proceedings (board applications, hearing dates, certificates issued) for legal follow-up. It never records or infers any individual employee's union support or activity, since that information is protected and collecting it could amount to interference. *(Scope cut: not built as a dedicated table — no story AC calls for it; the non-negotiable privacy constraint stated here still applies to anything built later.)*

## Employment equity, pay equity and accessibility

**Employment equity (federally regulated employers with 100 or more employees, and federal contractors):** workforce survey with voluntary self-identification; workforce analysis comparing representation of designated groups with labour market availability by occupational group; employment systems review; employment equity plan with goals and measures; annual report data including salary information; small-group suppression in every output. Provincially regulated employers can use the same tools voluntarily. *(`compliance.employment_equity_report`, docs/34 §11; EQ-001. Suppression reuses `privacy.min_group_size_self_id` (10) directly — no third suppression mechanism alongside `analytics.min_group_size` and engagement's own floor.)*

**Pay equity program administration:** committees, job class determination, gender predominance, evaluation, comparisons, required adjustments, postings and maintenance reviews, for the federal Pay Equity Act, Ontario and Quebec regimes and public-sector statutes; analytics come from Module 04. *(Scope cut: committee/job-class/posting detail not built — tracked only at the filing level via `compliance.employment_equity_report.program = 'pay_equity'`; no story AC covers the committee workflow itself.)*

**Accessibility:** organizational accessibility plans and progress reports where legislation requires them (for example federal entities under the Accessible Canada Act, Ontario AODA compliance reports); feedback process for accessibility barriers; accessible formats for employee documents on request; accommodation in recruitment (Module 02) and employment (accommodation cases above). *(Scope cut: the plan/report is tracked at the filing level via `compliance.employment_equity_report.program = 'accessibility_plan'`; the feedback process itself is not built — no story AC covers it.)*

**Indigenous employment:** Indigenous hiring commitments, impact benefit agreement employment obligations, and reporting to communities or funders; s.87 tax exemption documentation (with Module 03); support for Indigenous organizations' own governance of HR data. *(See the open question below — OCAP stays open.)*

## Privacy and data protection program

The platform's technical controls are specified in Module 00 and each module; this section covers the customer's privacy program and the platform's own obligations as a service provider.

| Component | Capability |
| --- | --- |
| Accountability | Privacy officer designation (required in Quebec, with the title and contact published); privacy policies and notices by purpose; governance records *(`compliance.privacy_officer`)* |
| Inventory | Register of personal information held: categories, purposes, legal basis, retention, location, recipients *(`compliance.retention_schedule` covers the retention side; the fuller inventory register is a scope cut — no story AC covers it)* |
| Privacy impact assessments | Templates and workflow for new systems, monitoring, AI features and cross-border transfers (Quebec Law 25 requires assessments before transferring personal information outside Quebec) *(`compliance.pia`; a cross-border feature cannot go live without an approved PIA — `cross_border_needs_approved_pia`)* |
| Consent and notices | Recorded consents for optional data (self-identification, biometrics, location, marketing to alumni), withdrawal handled *(already handled where the consenting data lives — e.g. self-identification consent in Core HR)* |
| Access and correction requests | Request intake, identity verification, statutory response deadlines (for example 30 days), redaction support, response tracking *(`compliance.access_request`, docs/34 §12; PRIV-001. The deadline is law content read from `compliance.rule`, never a hard-coded default.)* |
| Retention and destruction | Retention schedules per data class and jurisdiction with legal holds; automated destruction or anonymisation with logs *(`compliance.retention_schedule` / `compliance.legal_hold` / `compliance.destruction_log`, docs/34 §12; PRIV-002)* |
| Breach management | Incident intake, risk-of-significant-harm assessment, notification to regulators and individuals where required, breach register kept for the legislated period *(`compliance.breach`, docs/34 §12 — covers both the Law 25 confidentiality-incident register and the general PIPEDA breach flow)* |
| Vendors | Service provider register, data processing agreements, sub-processor list, transfer assessments *(scope cut: not built as a dedicated register — no story AC covers it; a cross-border vendor still needs `compliance.cross_border_feature` and its PIA gate)* |
| Automated decisions | Notices and review requests where decisions rely on automated processing (Law 25), supported by the AI guardrails *(no automated HR decision is built anywhere in the pack — rule 14 — so this has no live case yet)* |

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

*(All rows above are already enforced in Module 02's recruitment workflow, per `docs/23`; this module is their rules/evidence home, not a new schema. A dedicated immigration-case record and evidence-pack assembly are scope cuts — no story AC covers either.)*

**Evidence pack:** for any hire, the system can assemble the posting, candidate communications, assessments, approvals and consents for an audit or complaint. *(Scope cut: not built as a one-click assembly — the underlying records all exist and are retrievable individually.)*

## Data model, integrations and security

| Entity | Key fields | Built as |
| --- | --- | --- |
| Rule | Jurisdiction, law area, citation, conditions, parameters, effective dates, status, owner | `ref.rule_starter` + `compliance.rule` |
| Legislative Change | Source, summary, affected rules and customers, effective date, status | `compliance.legislative_change` |
| Obligation | Customer entity, type, frequency, due dates, owner, evidence | `compliance.obligation` |
| Policy | Jurisdiction, version, approval, distribution, acknowledgements | `compliance.policy` / `compliance.policy_acknowledgement` |
| Accommodation Case | Employee or candidate, ground category, limitations, options, accommodations, reviews, outcome | `compliance.accommodation_case` |
| RTW Plan | Case, weekly hours and duties, check-ins | `compliance.rtw_plan` |
| Incident | Type, date, site, people, description, severity, notifications, actions | `compliance.incident` |
| WCB Claim | Board, claim number, status, lost time, costs | `compliance.wcb_claim` |
| Investigation | Category, parties (restricted), investigator, evidence, findings, outcome | `compliance.investigation` |
| Speak-up Report | Channel, category, anonymity, messages, status | `compliance.speakup_report` / `compliance.speakup_message` |
| Grievance | Agreement, articles, grievors, steps, deadlines, outcome, arbitration | `compliance.grievance` |
| Bargaining Proposal | Article, party, costing, status | `compliance.bargaining_proposal` |
| Privacy Request / Breach | Type, dates, deadlines, actions, notifications | `compliance.access_request` / `compliance.breach` |
| Inspection | Regulator, dates, orders, compliance dates | `compliance.inspection` |

**Integrations:** every module reads rules from the repository and writes compliance events (for example a missed final pay deadline or an overdue training) to the obligations register; external integrations with workers' compensation board portals, hotline providers, and legal research or legislative update services where available. *(No third-party hotline — docs/34 §9.)*

**Security:** separate access roles for accommodation coordinators, OHS staff, investigators, labour relations and privacy office; strictest default access in the platform; every view logged (`compliance.case_view_log`); legal privilege marking on documents prepared with counsel, with restricted sharing.

## Collective agreement library

> **Already built** (migration 0003, `docs/08`) before any module review began. The paragraphs below describe design intent that is already satisfied; nothing in this section needed new schema in migration 0020.

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

*(Essential-services designation is built — `compliance.essential_position`, LR-011. Interest arbitration timelines/awards, central bargaining and the FOI request flow itself are scope cuts beyond salary disclosure, which is already built in Module 04.)*

## How CanDo compares

None of the HRIS platforms reviewed markets accommodation, health and safety, investigations, grievances and an agreement library in the same system; employers typically use spreadsheets or separate EHS and case management tools. UKG, Dayforce and ADP reach unionized and public-sector employers through time, pay and workforce management depth, which CanDo must match in Modules 03 and 06. The library and case management in this module are where CanDo can lead. Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

> **This is why OHS and the speak-up channel are built in-house rather than integrated with a third-party product (docs/34 §8, §9) — it is the stated differentiator, not an incidental choice.**

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

- [x] Who owns the rules repository and legislative monitoring (in-house legal team, a legal content partner, or both) — linked to the statutory table ownership decision in Module 00. **Resolved (docs/34 §3, §16):** CanDo seeds a starter/reference copy by jurisdiction; the organization owns keeping it current from there.
- [x] Jurisdictions supported at launch. **Resolved (docs/34 §16):** the same federal/provincial/territorial set CanDo already supports for payroll and employment standards; no new jurisdiction added for this module alone.
- [x] Third-party hotline partner for the speak-up channel. **Resolved (docs/34 §9, §16):** built in-house, never a third-party hotline.
- [x] Scope of OHS features at launch versus integrating with dedicated EHS software. **Resolved (docs/34 §8, §16):** full in-house case management.
- [ ] Indigenous data governance commitments (OCAP®) and advisory process. **Still open (docs/34 §16):** pending the owner's advisers; CanDo's existing OCAP-aligned data residency option in Core HR (migration 0008, PRIV-004) is unaffected and is not extended in this module.

**October 2026 review:** added the collective agreement library (Negotech and provincial registries), public-sector obligations, First Nations jurisdiction and competitor comparison; scope widened to all employer sizes and public-sector employers.
