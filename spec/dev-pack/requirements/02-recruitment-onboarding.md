# CanDo HRIS — 02 Recruitment & Onboarding

Oct 17, 2026 · @Wael

The Recruitment & Onboarding module runs the hiring lifecycle from an approved requisition to a confirmed regular employee, with Canadian employment standards, collective agreements and privacy rules enforced at each step. This is the consolidated specification; it supersedes the six recruitment files and the Bubble build guide in the project.

> **Owner's review, 25 October 2026.** `docs/23-recruitment-onboarding-decisions.md` records the review of this module and wins wherever this document differs. In short: every route, rule and message is the organization's, from starter copies it can change at any time; a user who goes past a caution acknowledges it and the reason is recorded; hiring without a requisition or without a posting follows the organization's own rules; people make every decision, and AI match suggestions are off until switched on; the employee record is created when the offer is accepted **and** the contract signed; background and criminal record checks happen only after a conditional offer; pre-boarding uses the employee's own login; probation check-ins and reminders are on the organization's days, a probation whose end date passes with no decision is passed, and there are no probation risk scores; HR reviews any open case before probation is failed or employment ends; conversion to regular starts when a manager asks. The Bubble build plan is withdrawn: recruitment is built on the same stack as every module.

## Overview and scope

The module covers eight stages: requisition, candidate acquisition, applicant evaluation, offer, pre-boarding, onboarding coordination, probation, and status conversion. It serves Canadian organizations with multi-regional and international operations, unionized and non-union staff, and diverse employment types.

**Objectives**

- Digitize and automate the hiring lifecycle end to end.
- Give candidates, hiring managers and HR a consistent, mobile-first experience.
- Enforce employment standards, collective agreements, privacy and accessibility rules automatically.
- Support data-driven hiring decisions and continuous improvement.
- Foster cultural alignment and inclusion from first contact, including Indigenous and DEI-inclusive onboarding.

**Employment types supported**

Regular full-time and part-time; temporary full-time and part-time with term limits; auxiliary and seasonal; contract and project-based; grant-funded positions with funding expiry tracking; student and intern positions; multi-incumbent positions (several hires into one role).

**Audiences**

| Audience | Primary use |
| --- | --- |
| HR and talent acquisition | Configure and run requisitions, sourcing, screening, offers, onboarding |
| Hiring managers | Request positions, interview, evaluate, select, onboard, run probation reviews |
| Candidates and new hires | Apply, schedule, sign, complete pre-boarding and onboarding tasks |
| IT, facilities, finance, security | Complete provisioning tasks assigned by onboarding workflows |
| System administrators | Roles, integrations, data migration, configuration |
| Executives | Approvals and hiring analytics |
| Union representatives (read-only outputs) | Receive notifications and competition documentation |

## Benefits and target outcomes

The source specifications state the targets below. They are design targets to be validated in pilots, not guaranteed results.

| Dimension | Target outcomes |
| --- | --- |
| Speed | Time-to-hire down 40–60%; time-to-offer halved through parallel approvals; interview rescheduling down 75% through self-scheduling and reminders |
| Efficiency | 85% of requisition and candidate admin automated; manual data entry down 90% through parsing and pre-population; paperless end to end |
| Quality | Better quality of hire through structured, evidence-based selection; consistent evaluation across departments |
| Retention and productivity | Early turnover down 35%; time to productivity 45% faster through structured onboarding |
| Experience | Hiring manager satisfaction up 65%; candidate experience metrics up 45%; transparent status at every stage |
| Cost | Recruitment costs down 30–50% through direct sourcing, fewer agencies and ad-spend analytics |
| Diversity | Bias-reducing tools, blind screening, representation tracked through the funnel, wider sourcing channels |
| Compliance | Zero findings against employment legislation and collective agreements; complete audit trail of every decision; one-click compliance reports |

## End-to-end workflow

The process has twelve stages and three decision gates; a "no" at any gate loops back rather than ending the record. The recruitment-workflow.svg and onboarding-workflow.svg diagrams in the project show the same flow.

1. **Requisition creation.** Hiring manager or HRBP completes a guided form linked to an approved job description and position number.
2. **Multi-level approval.** Routed by position type, department, budget and hierarchy. *Gate: approved?* No → returns to the requester with comments.
3. **Job posting.** Internal posting first where agreements require it, then external; union notified; equity, accessibility and pay-range statements inserted.
4. **Active sourcing.** Job boards, social media, referrals, talent pools, agencies, campus and diversity channels.
5. **Application and screening.** Parsing, knockout questions, qualification checks, seniority and lateral-transfer rules, shortlist.
6. **Interview and selection.** Structured interviews, assessments, panel scoring, selection approval, competition documentation.
7. **Selection checks.** References where the organization checks them before an offer.
8. **Offer management.** Package built within ranges, approved through the organization's route, sent for e-signature; a conditional offer lists its conditions. Background, criminal record, credential, licence and medical checks start only after the conditional offer, with consent (`docs/23` §5.3). *Gate: accepted and contract signed?* No → back to the shortlist or sourcing; silver medalists offered first.
9. **Pre-boarding.** Documents, tax forms, banking, benefits, equipment and access requests, welcome communications, pre-start learning.
10. **Onboarding coordination and first day.** Cross-department tasks, first-day schedule, orientation, training assignment, initial goals.
11. **Probation.** Check-ins the organization sets (starting 30 days, 60 days and 2 weeks before the end), with reminders before the end on its own days (`docs/23` §7). *Gate: passed?* No → extension told to the employee before the end date, with union notice where required, then re-evaluation; or documented release after HR reviews any open case. No decision by the end date → passed, and HR told.
12. **Status conversion and integration measurement.** Probationary to regular; records updated across systems; onboarding effectiveness and early-retention measured.

## Requisition management

Every hire starts from a requisition that is validated against position control, budget and job architecture before anyone can post it.

| Capability | Specification |
| --- | --- |
| Requisition creation | Guided form: title, department, employment type, location, union applicability, compensation range, justification, business case upload; requisition types Replacement, Additional headcount, New position; mass requisitions for several openings at once |
| Approval workflows | Chains by position type, department, budget threshold and hierarchy (for example Department head → HR → Finance → Executive); parallel, sequential or hybrid routing; conditional executive review for senior or over-budget roles; SLA timers with escalation; delegation during absence; mobile approval; bypass for urgent hires with documented justification and audit trail; approval analytics to find bottlenecks |
| Position types and terms | All classifications above; term start and end with extension options; term-limit rules; alerts before contract end; renewal approvals; replacement versus new position handling |
| Position control | Approved headcount versus filled; vacancy reasons (retirement, resignation, growth); vacancy forecasting; FTE tracking and allocation by department; split and shared positions; position freeze with exception workflow; moves between departments; effective-dated changes with audit trail; prevents hiring outside approved headcount |
| Budget verification | Validates funding with the finance system; grant-funded positions track funding expiry; budget impact forecast for new positions; variance between budgeted and actual pay; salary range enforcement by classification |
| Job description library | Central templates by job family; version control and change comparison; approval workflow for edits; cloning; standard sections (duties, qualifications, working conditions, physical demands); skills and competency frameworks; multilingual versions; compliance check before publishing |
| Custom fields | Unlimited fields with field-level security, dependencies and conditional logic; department-specific attributes, screening questions and security clearance requirements; hiring manager preferences (panel, assessments, timeline) |
| Position classification validation | Real-time check of position codes so HRIS, payroll and budget stay aligned; grade assignment validation; Schedule A/B/C verification for positions under specific agreements; market-rate check for non-union positions |
| Competition documentation | Standard posting templates, exams and questionnaires; weighted qualification frameworks; minimum qualification validators; pre-approved screening questions; HR and Finance validation of position details |
| Notifications | Automated alerts to stakeholders at each stage, including union representatives for new positions |
| Canadian field rules | The project's Bubble requisition guides use US defaults; CanDo replaces them. Education list uses Canadian credentials (secondary school diploma, DEP, college diploma, CEGEP DEC, apprenticeship and Red Seal, bachelor's, master's, doctorate) with foreign-credential equivalence; no "Canadian experience" requirement field for Ontario postings; the salary range is checked against the posting jurisdiction's pay-transparency rules (Ontario range no wider than $50,000, BC and PEI range required); budget impact adds employer CPP or QPP, EI at 1.4 times (or the reduced rate), provincial payroll levies (EHT, HSF, Manitoba and NL levies), workers' compensation and benefits cost for the work location |

## Job posting and candidate acquisition

Postings are distributed from one record to every channel, with posting rules enforced before anything goes external.

| Capability | Specification |
| --- | --- |
| Posting rules | Posting durations by position type (for example 14, 21 or 30 days) and by agreement; calendar-aware counting (working versus calendar days); internal-first sequencing with lead time; reposting with approval; time-based publish and expiry; featured postings; visibility by role, location, language and eligibility |
| Distribution channels | Branded career portal; Canadian boards (Indeed, Workopolis, Job Bank, ZipRecruiter); LinkedIn, Facebook, X; international boards with geographic targeting; industry and professional associations; campus career centres; diversity and Indigenous boards (IndigenousWorks, DiverseCity); Google for Jobs; one-submission multi-posting with tracking links |
| Career portal | Mobile-responsive, branded, personalized content, job recommendations, saved searches and job alerts, single sign-on for returning applicants, progress saving, apply with LinkedIn or resume autofill |
| Job alerts | Preference-based matching, configurable frequency and channel, engagement analytics, A/B testing, automated unsubscribe |
| Search optimization | Structured data markup, keyword tools for descriptions, location-based enhancement, visibility analytics |
| Talent communities | Skill-based pools, candidate opt-in with preferences, segmentation, nurture campaigns and drip sequences, engagement scoring, recruitment events with attendee tracking and ROI, re-engagement of previous applicants, interaction history |
| Employee referrals | Portal or mobile submission, end-to-end tracking, status visible to the referrer, configurable rewards paid through payroll, social sharing, gamification, referral quality and conversion analytics |
| Third-party agencies | Secure agency portal to view assigned requisitions and submit candidates; access limited by role, geography or function; time-limited accounts; performance dashboard (submissions, interview-to-hire ratio); contract-based billing triggers |
| Application intake | Configurable forms by position; duplicate detection against prior applications; automated acknowledgement; consent capture before submission; self-identification data collected separately and anonymized |

## Applicant evaluation and selection

Selection is structured and evidence-based: every candidate is assessed against the posted qualifications with the same criteria, and every decision carries its justification.

| Capability | Specification |
| --- | --- |
| Multi-stage screening | Configurable stages with gate criteria, owners and sequential or parallel paths; knockout questions (multiple choice, yes/no, open) with weighted scoring; minimum thresholds for advancement; automated communication to unsuccessful applicants |
| Resume parsing | PDF, DOCX, HTML and text; section recognition and field mapping (target 95%+ accuracy); multilingual parsing with language detection; skills, education and certification extraction with expiry tracking; name, address and phone normalization; candidate confirmation of parsed data; manual correction with change log |
| Matching and search | Requirement-to-qualification mapping with critical versus preferred weighting; gap analysis for near matches; semantic and natural-language search; Boolean search; saved searches; tagging; candidate-to-many-jobs matching; explainable match scores; configurable algorithms by position type |
| Qualification verification | Systematic checks of claimed credentials, licences and certifications; documentation requests; licensing-body integration where available; audit trail |
| Assessments | Technical, cognitive, behavioural, situational judgement, language proficiency and custom tests; secure, timed delivery with anti-cheating and remote proctoring; automatic scoring and import from third-party providers; benchmarking against successful hires; competency heat maps |
| Interview management | Calendar integration and availability checks; candidate self-scheduling; panel assembly with roles; room and virtual meeting booking; interview kits from approved question banks; competency-based and behavioural questions with rating scales; question rotation; legal review of questions; compliant note-taking; reminders |
| Video interviews | Live and asynchronous recorded responses; response windows and time limits; time-zone aware scheduling; panel coordination; mobile support; blind rating option; inter-rater reliability metrics |
| Collaborative evaluation | Real-time feedback; weighted multi-evaluator scoring; calibration for evaluator tendencies; side-by-side comparison; discussion threads; consensus tools; selection approval workflow |
| Reference checks | Digital requests with position-specific questionnaires; automated follow-up; response tracking; red-flag detection; authenticity checks; consent management; compliant storage |
| Talent pools | Silver-medalist tracking for quick fills; pipeline views by department and skill; profile refresh; recommendations for future roles; engagement campaigns |
| Selection documentation | Structured rating against posted qualifications with evidence; interview and assessment results weighted per plan; panel composition records; multi-level approval of the final selection; complete history for audits, appeals and grievances |

## Offer management

Offers are generated from approved templates, priced inside the Compensation module's ranges, and approved by a matrix keyed to position and pay level before they reach the candidate.

| Capability | Specification |
| --- | --- |
| Compensation package builder | Total compensation model (base, variable, allowances, benefits value); min/mid/max guidance and compa-ratio; internal equity comparison; market benchmarking; benefits cost estimate; one-time and recurring allowances; proration for partial periods; signing bonus and relocation options; multiple scenarios for negotiation |
| Templates and documents | Templates by department, position, jurisdiction and union or non-union; clause library with conditional content; English and French; legal-approved, version-controlled language; personalization tokens; attachments (agreements, policies); preview and edit before sending |
| Terms construction | Start-date logic and validation; probation period calculated per policy, agreement and province; conditions (background check, licence, pre-employment medical); restrictive covenants scoped appropriately; required disclosures |
| Approvals | Matrix by position and compensation level; parallel or sequential; exception routing with justification for out-of-guideline offers; delegation; reminders and escalation; executive threshold routing; mobile approval; risk assessment of exceptions |
| E-signature | Built-in or DocuSign, Adobe Sign, HelloSign; signer authentication; sequential signing; tamper-evident documents; full audit trail; mobile signing |
| Tracking and communication | Real-time status (sent, viewed, accepted, declined); time-to-decision metrics; reminders; expiry and renewal; secure Q&A channel and FAQ; decline-reason capture; acceptance analytics by position and department |
| Negotiation | Counter-offer records; version control with redline comparison; approvals for revised terms; impact analysis; justification capture; final terms stored permanently |
| Analytics and planning | Acceptance trends, competitive offer intelligence, equity analysis across demographic groups, what-if scenarios and budget impact |
| Hand-off | When the offer is accepted and the contract signed, the employee record is created through the hire change set, pre-boarding opens, and compensation, start date and probation terms go to Core HR and Payroll (`docs/23` §5.5). Before the contract is signed the person is still a candidate |

## Pre-boarding

Pre-boarding closes every administrative requirement between acceptance and day one, so the first day is spent on people and work rather than forms.

| Capability | Specification |
| --- | --- |
| New hire portal | The CanDo login the person keeps as an employee, limited to pre-boarding screens until the start date (`docs/23` §6.1); personalized dashboard with progress; company, culture and values introduction; leadership and team welcome videos; team profiles and org chart; location maps, parking and transit; dress code; FAQ; direct HR channel; timeline of pre-boarding and first weeks |
| Document collection | Checklists by position type and jurisdiction; guided mobile upload with camera capture; document-type recognition; completeness and quality checks; encrypted storage filed to the employee record; expiry tracking with renewal workflows; automated reminders and escalation |
| Electronic forms | Smart forms pre-filled from the application; field validation and help; progressive disclosure; conditional logic; save and resume; jurisdiction-specific sets; e-signature; multilingual |
| Tax and eligibility forms | Canada: federal and provincial TD1; Quebec: TP-1015.3; US: W-4, state withholding forms and I-9; treaty and exemption handling including Indian Act s.87 status; version control as forms change |
| Employment verification | SIN validation; work permit and visa capture with expiry tracking; foreign worker documentation; background checks (criminal, education, licence, employment history) with consent and status dashboard; security clearance; complete verification records |
| Benefits enrolment | Eligibility by position; plan comparison and cost calculator; dependants and beneficiaries; evidence of insurability; alternative coverage declarations; deadline tracking; confirmation workflow |
| Payment setup | Direct deposit with bank validation; split deposits; pay frequency confirmation; secure handling of financial data |
| Equipment and access | Role-based equipment packages; accommodation requests; software licences; security access levels; building access; business cards and ID badge; mobile device enrolment; asset assignment tracking |
| Welcome communications | Scheduled messages by email, SMS and portal; personalized content from leaders and team; first-day logistics; relocation and travel help |
| Data verification | Cross-checks of contact, emergency contact, banking, credentials and prior employment; identity authentication; error correction workflow |
| Pre-start learning | Orientation modules, role basics, compliance training head start, systems familiarization, pre-reading, knowledge checks |
| Accommodation and culture | Confidential accommodation requests; religious and cultural observances; Indigenous ceremonial leave provisions; scheduling and workspace adaptations; dietary preferences for events |
| Collective agreement orientation | Correct agreement provided; job-specific provisions highlighted; probation terms; union representative introduction; dues; grievance procedure; seniority calculation; benefits under the agreement |

## Onboarding coordination

Onboarding is a set of templated, dependent tasks across eight departments, tracked on one dashboard until the new hire is fully integrated.

**Departmental responsibilities**

| Department | Tasks |
| --- | --- |
| HR | Documentation, benefits enrolment and verification, personnel file, policy acknowledgments, orientation scheduling |
| IT | Accounts across systems, equipment, system access, SSO, technical orientation |
| Facilities | Workspace and seating, access cards, building orientation, supplies |
| Finance | Payroll setup and validation, expense system, corporate card, cost centre |
| Hiring department | Team introductions, job orientation, first projects, buddy or mentor, role training |
| Learning | Required training, certifications, development plan |
| Security | Clearances, access levels, NDAs and confidentiality |
| Communications | Announcements, directory updates |

**Capabilities**

| Capability | Specification |
| --- | --- |
| Task management | Role-specific templates for new hires, rehires, transfers, contractors and interns; varied by level, employment type, department, union and location; automatic assignment and routing; due dates with dependencies; priorities; recurring tasks for extended onboarding; embedded instructions and links; completion evidence; escalation of overdue critical items; mobile updates; ticketing integration for IT, security and facilities |
| Progress dashboards | Role-based views; completion percentage; colour-coded status; department comparison; bottleneck and critical-path flags; milestone timeline; drill-down; provisioning status (laptop shipped, desk assigned, badge issued) |
| First day and week | Templated itineraries by department; adjusts to start day of week; calendar invites; orientation enrolment; stakeholder meetings; recurring manager check-ins |
| Buddy and mentor programs | Auto-matching by department, location or interests; meeting schedules and guides; secure chat and intro templates; engagement and sentiment tracking; mentor feedback |
| Milestones | Week 1–4 and 30-60-90 day plan; SMART goals linked to Performance; manager prompts for check-ins; celebration of completed milestones |
| Indigenous and culturally aligned tracks | Optional tracks with land acknowledgment practices, mentorship pairing, culturally relevant guidance, participation of local Elders and Indigenous liaisons, language elements; assignable by cohort or location |
| Regulated industries | Custom fields and multi-level sign-off for healthcare, aviation, government and similar; licence and certification checks; flags for gaps or expired credentials |
| Remote onboarding | Virtual orientation and tours, digital document processing, home office setup coordination, virtual team introductions |
| Feedback | Pulse surveys at 7, 30, 60 and 90 days; sentiment alerts for low satisfaction or stalled progress; orientation effectiveness |

## Probation and trial period management

Probation runs on a configured clock per position, agreement and province, with scheduled reviews, documented decisions, and analytics that feed back into selection.

| Capability | Specification |
| --- | --- |
| Period configuration | Duration by position type, collective agreement and jurisdiction; distinction between employer probation and union trial periods; effective-date calculation; extension rules with approvals and maximums |
| Review schedule | 30-day check-in, 60-day review, 90-day evaluation by default; calendar invitations for manager and employee; preparation material for both |
| Templates and criteria | Evaluation templates by stage; position-specific success metrics; competency frameworks; progressive expectations across the period; department customization |
| Manager guidance | Structured criteria, coaching guidance for performance issues, decision support comparing results with the original hiring criteria |
| Notifications | Reminders before each review; escalation of missed reviews; alerts as the end date approaches; stakeholder milestone notices |
| Decision documentation | Rating frameworks with evidence; approval of formal documentation; three outcomes: confirm, extend, or end employment |
| Extension | Justification required; revised timeline and milestones; notification of affected parties including the union where required; re-evaluation loop |
| Open cases | No warning signs or risk scores during probation. Before probation is failed or employment ends, HR reviews any open case or leave and acknowledges it (`docs/23` §7.5) |
| Analytics | Completion rates by department; manager review compliance; extension frequency and reasons; success after extension; termination reasons correlated with hiring source to improve selection |

## Status conversion management

Status conversion moves employees between classifications (probationary to regular, temporary or auxiliary to regular, several part-time roles into one) under configurable eligibility rules and collective agreement terms.

**Conversion workflow** (status-conversion-workflow.svg)

1. Review started when a manager asks; organizations can add time or hour thresholds that flag people; a conversion an agreement requires is always flagged to HR (`docs/23` §8).
2. Eligibility verification against configured rules. *Not eligible* → contract extension and documented reason.
3. Manager recommendation with attestation.
4. HR review for policy and agreement compliance.
5. Budget approval. *Not approved* → returned to the manager to revise.
6. Position creation or reclassification in Core HR.
7. Contract or letter generated from templates.
8. Signatures captured electronically.
9. System updates: Payroll, Benefits eligibility, Time and Leave rules, seniority.
10. Notifications to employee, manager, union where required, and payroll.

| Capability | Specification |
| --- | --- |
| Eligibility rules | Time- and hour-based thresholds by position type and agreement; service calculation; proactive alerts as thresholds approach; overrides with approval |
| Auxiliary and seasonal tracking | Cumulative hours across assignments using agreement-specific counting; rehire eligibility; performance linkage; skills and certification status |
| Multi-position management | Employees holding several positions; FTE across positions; primary position; cross-department hours; position limits; consolidation of part-time positions with impact analysis, budget recalculation and tiered approvals |
| Seniority calculation | Company, department and classification seniority; rules per agreement; breaks in service and bridging; leave impacts; prorated credit for part-time; credit for temporary service on conversion; tie-breaking; manual adjustments with approval and full documentation |
| Documentation and compliance | Required forms and justifications; validation before processing; permanent record and audit trail; union notification and reporting |
| Communication | Formal confirmation to the employee; system-wide updates; optional recognition of successful conversion |

## AI and automation

AI assists every stage but never makes the final hiring decision; scores are explainable, logged and tested for bias (Master Overview, shared services).

| Area | Feature |
| --- | --- |
| Recruitment | NLP resume parsing and profile building in several languages; explainable candidate matching, off until the organization switches it on, with criteria and weights the employer sets (`docs/23` §4.6) that can prioritize under-represented candidates where configured; interview question suggestions by role, seniority and competency with DEI-sensitive filters; job description writing analysis and inclusive language checks; predicted time-to-fill |
| Communications | Stage-triggered emails and SMS (application received, interview scheduled, offer sent); personalized templates; internal updates to Slack and Microsoft Teams; optional recruiter chatbot for candidate questions |
| Onboarding | Predictive task nudges timed to past completion behaviour; escalation to HRBP or manager for at-risk tasks; personalized journeys and microlearning by role, location, language and persona |
| Retention | Early attrition risk model using engagement, survey sentiment and task delays, with context for HRBP intervention; never for probationary employees, and never part of a probation or termination decision (`docs/23` §7.5) |
| Workflow automation | Event triggers for offers, tasks, provisioning and document requests; "if this then that" rules; paths by job level, region (for example Quebec versus Alberta) and department; fallback when automation fails or is overridden; webhooks and APIs; Zapier and Make for no-code links |
| Ethics | Scheduled bias testing of screening, scoring and matching; blind review mode that anonymizes resumes and evaluations; explanation of every score; full decision logs |

## Recruitment compliance controls

The controls below are specific to hiring. The legislative map, privacy framework, collective agreement engine and multi-jurisdiction rules they rely on are specified once in Module 13.

| Stage | Control |
| --- | --- |
| Requisition | Posting duration enforced per agreement with calendar-aware counting; internal posting before external; automated union notification with content per agreement and timing recorded; Schedule A/B/C and grade validation; competition records structured to meet municipal agreement disclosure requirements (for example Burnaby) |
| Posting | Required elements validated (minimum qualifications, working conditions, physical demands, certifications); pay range shown where law requires (pay transparency); equity statement by jurisdiction with Employment Equity Act support and reconciliation commitment language; WCAG 2.1 AA application flow with screen reader and keyboard support, reading-level check, alternative application methods |
| Privacy | Multi-stage consent for different data uses; location-based consent rules; PIPEDA, BC and Alberta PIPA, Quebec Law 25, GDPR and US state laws; retention schedules and profile expiry; access and erasure workflows |
| Screening and selection | Seniority applied per agreement and verified against HR data; lateral transfer preferences applied in the right sequence and communicated; selection rated against posted criteria with evidence; competition results report with panel composition, methodology, qualified applicant list and union notification of the decision |
| Equity | Voluntary, anonymous self-identification; aggregate stage-by-stage representation; adverse impact analysis; benchmark comparison; privacy-protected reporting |
| Offer | Correct salary step placement with documented rationale; validation against agreement terms; provincial employment standards terms; probation terms aligned to law and agreement; lawful termination provisions; restrictive covenants appropriately scoped |
| Pre-boarding | SIN and work permit verification (I-9 only for any US entity); foreign worker documentation; background check consent; tax forms by jurisdiction; confidential accommodation process; agreement orientation |
| Records | Complete, immutable audit trail of postings, evaluations, offers and onboarding tasks with user and IP; exportable for audits, grievances and legal inquiries |

## Integrations

Onboarding data populates the employee master record without re-entry; every downstream module is provisioned from the accepted offer.

| System | Data | Direction and method |
| --- | --- | --- |
| Core HR (01) | Employee record creation, positions, org hierarchy, compensation structure, status, multi-position, reporting lines, legal entities, probation terms | Bi-directional; real-time events and batch; full profile and history sync |
| Compensation (04) | Job families, levels, bands, union rates, pay equity checks | Bi-directional; validation of job code, FTE and union affiliation |
| Payroll (03) | Compensation, start and end dates, tax forms, direct deposit, allowances, deductions, pay group, pay calendar, union dues | Export with pre-payroll validation, scheduled or on demand, error resolution workflow |
| Benefits (05) | Eligibility, waiting periods, elections, dependants, beneficiaries, life events, coverage dates, evidence of insurability | Bi-directional; event-triggered; carrier files (for example HIPAA 834 for US carriers) |
| Learning (08) | Onboarding learning paths, compliance courses, certifications, assessments, completions, transcripts | Bi-directional; SSO and user sync |
| Time and Leave (06) | Schedules, time policies, leave balance initialization, shift patterns, overtime eligibility, collection method, approval hierarchy, holiday calendar | Export; template application |
| Performance (07) | 30-60-90 goals, probation reviews, buddy feedback | Bi-directional |
| Document management | Offers, contracts, onboarding documents, acknowledgments, ID, work authorization | Bi-directional; metadata and version control |
| Identity and IT | User provisioning, security groups, application access, directory; deprovisioning on termination | Export; just-in-time provisioning via Azure AD, Okta, OneLogin; ticketing for devices and badges |
| Job boards and ATS tools | Postings, applications, screening questions, status | Bi-directional; XML or JSON feeds and APIs |
| Calendar and collaboration | Availability, interviews, orientation sessions | Google Workspace, Outlook and Teams, Slack, Zoom |
| Screening providers | Background checks, assessments, references, video interviews | API with status webhooks |
| E-signature and storage | Offer and onboarding packets | DocuSign, Adobe Sign, HelloSign; SharePoint, Google Drive |

**API and events:** REST endpoints for postings, candidates, offers, tasks and onboarding status; webhooks for status change, form submitted, feedback received and candidate hired; daily, hourly or real-time sync; field mapping, conflict rules and sync logs for administrators; developer portal with sandbox.

## Data model

Eight core entities, taken from the Bubble build guide and extended with the fields the consolidated spec requires. Status values are configurable option sets.

| Entity | Key fields | Status values |
| --- | --- | --- |
| Requisition | Requisition ID, title, department, type (replacement, additional headcount, new position), justification, business case file, requested by and date, approval workflow and current stage, budget impact, position control number, funding source and expiry, related posting | Draft, Pending approval, Approved, Rejected, Cancelled |
| Job Posting | Job ID, title, department, position type, classification, description, requirements, responsibilities, salary min and max, location, remote option, posting and closing dates, openings, hiring manager, required certifications and skills, compliance elements, custom fields, approval history, diversity source tracking, competition documentation | Draft, Open, Closed, Cancelled |
| Candidate | Candidate ID, names, email, phone, location, applied position, application date, source, resume, cover letter, portfolio, notes, rating (1–5), tags, skills, education, experience, references, assessment scores, background check status, compliance documents, internal flag, previous applications, consent records, custom fields | New, Screening, Interview, Assessment, Reference check, Offer, Hired, Rejected |
| Interview | Interview ID, candidate, job, type (phone, video, in-person, group, technical, assessment), date and time, interviewers, location or meeting link, template, questions, ratings, feedback, next steps, recording link, technical results | Scheduled, Completed, Cancelled, Rescheduled |
| Assessment | Title, description, type (skills, personality, technical, culture fit), questions, scoring method (points, percentage, pass/fail), passing threshold, time limit, active flag | Active, Inactive |
| Approval Workflow | Name, type (sequential, parallel, hybrid), stages, department, budget threshold, active flag | Active, Inactive |
| Offer | Offer ID, candidate, posting, salary and package lines, benefits, start date, expiry date, approval workflow, current approver, offer letter file, versions, custom fields | Draft, Pending approval, Approved, Sent, Accepted, Declined, Expired |
| Onboarding Plan and Task | Plan: title, department, position type, duration, tasks, active flag. Task: owner, department, due date, dependencies, evidence required, status | Not started, In progress, Completed |

Supporting entities: Department, Skill, Education, Experience, Reference, Assessment Score, Interview Rating, Interview Template, Approval Stage, Approval History, Benefit, Probation Review, Status Conversion Request, Seniority Record.

## Reporting, analytics and dashboards

Standard reports ship configured; advanced analytics and dashboards draw on the cross-module layer in Module 12.

**Standard reports**

| Group | Reports |
| --- | --- |
| Requisitions | Status by department, open position aging, time-to-fill by position type, approval cycle time, pipeline forecast, headcount, budget variance |
| Sources | Effectiveness by position, recruitment marketing ROI, social and job board performance, referral analytics, agency comparison, cost per source |
| Diversity and compliance | Employment equity and (US) EEO/OFCCP reports, diversity pipeline, adverse impact, veteran and disability hiring, pay equity, audit preparation, multi-jurisdiction compliance |
| Candidate experience | Application completion, satisfaction surveys, time in stage, dropout, mobile usage, career site traffic, communication effectiveness |
| Selection process | Assessment completion, interview scheduling efficiency, reference and background turnaround, video adoption, tool effectiveness |
| Hiring managers | Satisfaction surveys, candidate quality ratings, SLA compliance, tool adoption |
| Funnel conversion | Application to interview, interview to offer, offer to acceptance, acceptance to start, withdrawals, stage fallout |
| Onboarding | Progress by cohort, tasks complete, documents signed, equipment provisioned, compliance steps, 7/30/60/90-day sentiment, buddy interaction |
| Time to productivity | Ramp-up, training timing, early performance, first-year retention |
| Collective agreements | Posting compliance, internal candidate consideration, seniority application, recall rights, grievance prevention |

**Advanced analytics:** predictive time-to-fill with seasonality; candidate success and retention risk; bottleneck and stage-duration optimization; cost per stage; source mix recommendations; recruiter productivity and capacity; first-year attrition patterns; quality of hire against performance ratings and promotion velocity; assessment and interview predictive validity; compliance risk prediction.

**Dashboards:** executive (KPIs, budget, critical positions, diversity goals, ROI), hiring manager (requisitions, pipeline, interviews, offers, onboarding), recruiter (daily priorities, SLAs, follow-ups), candidate (status, documents, assessments, schedule), compliance (requirements, documentation, postings, audit trail), operational efficiency (cycle times, automation, cost per hire), and mobile (alerts, approvals, key metrics).

**Exports:** CSV, Excel, PDF and JSON; scheduled distribution; connectors to Power BI, Tableau and Looker Studio.

## User experience and portals

Five interfaces share one design system; all meet WCAG 2.1 AA and run in English and Canadian French, with right-to-left support for Arabic and other languages.

| Interface | Main functions |
| --- | --- |
| Candidate portal | Branded, responsive; simple application with progress saving and autofill; document upload; self-scheduling; assessments; status tracking with estimated timelines; offer review and acceptance; pre-boarding tasks; communication history; feedback surveys; text scaling, screen reader and keyboard support |
| Hiring manager portal | Requisition creation and tracking; candidate review and comparison; interview scheduling and one-click scoring; team feedback; offer approval; onboarding progress; team composition view; alerts for missed feedback, overdue decisions and expiring offers; mobile actions |
| Recruiter workbench | Unified candidate management; pipeline board; communication templates and history; interview coordination; task priorities; documents; sourcing channel management; compliance verification tools; analytics |
| HR administrator console | Configuration of workflows, forms, fields, templates, notifications and automations; roles and permissions; compliance rules; integration monitoring; audit logs; inclusive language and anonymized screening settings; Indigenous and DEI tracks by cohort or location |
| Process configuration tools | Drag-and-drop workflow designer; form builder; email and document template editors; rule and condition builder; SLA and reminder setup; integration mapping; report and dashboard builders; mobile experience designer |

**Adaptive and localized experience:** role-based simplification; progressive disclosure; context-aware help; saved preferences; regional formats for dates, numbers, addresses and currency; time-zone awareness; country-specific fields and templates; cultural calendars; translation management with terminology consistency; alternate document formats (audio, plain text, large print).

## Roles and permissions

Nine roles are pre-defined; organizations can clone and adjust them. Access levels: Full, Create, Edit, Approve, Limited, View, None.

| Function | System admin | TA admin | Recruiter | Hiring manager | Interview team | HRBP | Executive | Candidate | New hire |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| System settings, security, users | Full | View/Limited | None | None | None | None | None | None | None |
| Workflows, forms, templates, career site | Full | Full | Limited | None | None | Limited | None | None | None |
| Create requisition | Full | Full | Create | Create | None | Create | Limited | None | None |
| Approve requisition | Full | Full | None | Approve | None | Approve | Approve | None | None |
| Job posting management | Full | Full | Full | View | None | View | View | None | None |
| Source and search candidates, talent pools | Full | Full | Full | Limited | None | Limited | None | None | None |
| Review, advance or reject applicants | Full | Full | Full | Full | Limited | Full/Limited | Limited | None | None |
| Schedule interviews, assessments | Full | Full | Full | Limited | Limited | Limited | None | Limited | None |
| Interview feedback | Full | Full | Full | Full | Full | Full | Limited | None | None |
| Background and reference checks | Full | Full | Full | View | None | Limited | None | None | None |
| Create and edit offers | Full | Full | Create/Edit | Limited | None | Create/Edit | None | None | None |
| Approve offers | Full | Full | None | Approve | None | Approve | Approve | None | None |
| Onboarding plans and tasks | Full | Full | Full | Limited | None | Full | None | None | View/Limited |
| Probation check-ins and status conversion | Full | Full/View | View/Limited | Full/Approve | None | Full/Approve | None | None | View |
| Reports and dashboards | Full | Full | Limited | Limited | None | Full | Full (executive) | None | None |
| Own profile, documents, forms | Full | Full | View | None | None | View | None | Full | Full |

**Data visibility:** recruiters see assigned and department records; hiring managers see their own requisitions and candidates; interview teams see assigned interviews only; HRBPs see assigned business units; executives see summaries and exceptions; candidates and new hires see only their own records.

**Approval authority:** department-level approvals for TA admins; own-department approvals for authorized hiring managers with limited budget override; business-unit approvals for HRBPs; division and company approvals and compensation exceptions for executives; system administrators hold all levels for emergencies, with every use logged.

**Mobile:** full for administrators; candidate review and feedback for recruiters and interview teams; approvals for hiring managers, HRBPs and executives; task views for candidates and new hires.

## Implementation

The module follows the seven-step method in the Master Overview. Deployment can be phased (recruitment first, then onboarding), full, or piloted in one department or location.

**Implementation checklist**

| Phase | Key deliverables |
| --- | --- |
| 1. Discovery and planning | Stakeholder interviews; current process maps; compliance requirements by jurisdiction and agreement; integration map; KPIs; governance; change strategy; data readiness |
| 2. Design and configuration | Org structure; roles; approval workflows by position type; requisition templates; custom fields and forms; career site branding; email templates; compliance rules; dashboards |
| 3. Integration | Core HR, Payroll, Benefits, Learning, Time, document management, identity, job boards, assessment and background check providers |
| 4. Testing | Scenarios and scripts; unit, integration, user acceptance, compliance, performance, mobile, accessibility, security penetration and regression testing |
| 5. Training and change | Role-based materials; administrator, recruiter and hiring manager training; knowledge base; super users; go-live communications; executive briefings |
| 6. Deployment | Final data migration (candidates, open requisitions, onboarding records); pre-production validation; sign-off; cutover; go/no-go; hypercare |
| 7. Post-implementation | 30-day review; user feedback; KPIs against baseline; lessons learned; continuous improvement plan |

**Configuration tiers:** Basic (standard workflows, templates, notifications, reports, out-of-box roles); Advanced (custom approval matrices, conditional workflows, department-specific setup, custom fields and reports); Enterprise (multiple business units and entities, advanced security model, global and local settings, cross-entity workflows, executive dashboards, performance tuning).

**Configurable by customer:** requisition and approval routing; interview and evaluation templates; offer formats by location and agreement; onboarding task lists by job type, geography and hire category; languages and layouts; accessibility modes.

**Bubble build plan (withdrawn 25 October 2026, `docs/23` R1.1):** weeks 1–2 data types, roles, dashboard; 3–4 requisitions, postings, candidate acquisition; 5–6 interviews, assessments, offers; 7–8 Core HR, calendar and e-signature integrations; 9–10 reports and dashboards; 11–12 testing and training; 13–14 launch and tuning. Build notes: privacy rules per data type, field-level security, audit logging, indexed searches and pagination, backend workflows for heavy jobs, API Connector with retries and logging, reusable UI elements, state machines for complex processes.

**Change management:** executive sponsorship; stakeholder mapping and impact assessment; department champions; communication cadence; role-based and blended training with practice environments; job aids, quick reference cards, videos and FAQs; adoption and satisfaction tracking; success stories.

## Extensions and roadmap

Six add-ons extend the core module; the roadmap is grouped by time horizon from the design document.

| Extension | Scope |
| --- | --- |
| Passive candidate CRM | Talent communities, nurture campaigns, newsletters, events, market intelligence, conversion tracking |
| Interview intelligence | Optional transcription, question effectiveness, bias alerts, interviewer coaching, structured comparison |
| Contingent workforce | Vendors, statements of work, timesheets, rate cards, term limits, co-employment risk, conversion to employee |
| Diversity and inclusion platform | Anonymized screening, inclusive language analysis, diverse slate enforcement, goals and benchmarks, hiring team training |
| Campus and early talent | University relationships, events, internships, graduate programs, cohorts, mentor matching, conversion analytics |
| Internal mobility | Opportunity marketplace, career paths, skills gaps, gigs and projects, succession integration |

| Horizon | Planned capabilities |
| --- | --- |
| 0–6 months | Interview intelligence; smart offer generator (package suggested from similar roles and negotiation history, live pay equity and band check, alerts for outliers and union mismatches); redesigned candidate portal with status widget and chat |
| 6–12 months | Adaptive onboarding journeys; Indigenous experience expansion (community-specific content, visual themes, land acknowledgment by hire location); DEI compliance toolkit (dashboard, bias flags, regional inclusive-hiring checklists) |
| 12+ months | Predictive hiring recommender (forecast postings before attrition, skills-based clustering, labour-market signals); voice-enabled onboarding assistant; blockchain credential validation for regulated industries; conversational requisition creation; skills-based hiring framework; VR onboarding and simulations |

Roadmap governance: quarterly review of customer feedback; user advisory panel of HR, IT, hiring managers and employees; periodic retraining and fairness review of AI models.

## Canadian hiring rules by jurisdiction (2026)

Posting and candidate rules now differ by province; the posting validator applies the rules of the job's location and blocks publication until they are met.

| Jurisdiction | Rule in force | CanDo control |
| --- | --- | --- |
| Ontario (employers with 25+ employees, public postings from 1 January 2026) | Expected pay or a range no wider than $50,000; a statement if AI screens, assesses or selects applicants; whether the posting is for an existing vacancy; no Canadian experience requirement; tell interviewed applicants whether a decision has been made within 45 days; keep postings and related records for three years | Validator blocks non-compliant postings; AI disclosure inserted automatically when AI features are on; 45-day follow-up task with timer; three-year retention class |
| British Columbia | Expected pay or range in public postings; no questions about pay history; pay transparency reports by employer size | Validator; pay history fields removed for BC roles; report from Module 04 |
| Prince Edward Island | Expected pay or range in public postings | Validator |
| Newfoundland and Labrador | Pay transparency provisions passed but not yet proclaimed | Rule loaded as inactive |
| Quebec | French postings, offers and communications under the Charter of the French Language | French versions required before publication |
| Federal | Employment Equity Act for federally regulated employers; official languages for federal institutions | Equity data and bilingual postings |

Sources: [Teamed on Ontario and BC posting rules](https://www.teamed.global/ca-employment-law/pay-transparency-job-postings), [Agendrix 2026 summary](https://www.agendrix.com/?p=76901).

## Public-sector and high-volume hiring

| Area | Requirement |
| --- | --- |
| Competitions and eligibility lists | Rated competitions against posted criteria; qualified lists valid for a set period; appointments made from lists; complaint and appeal windows where the employer's rules provide them |
| Union posting and seniority | Agreement terms from the Module 13 library: internal posting periods, seniority and lateral transfer order, union notice of results; links to recall lists in Module 11 |
| Language and security | Second-language testing for bilingual positions; police, vulnerable sector and security clearance checks with renewal dates |
| Seasonal and mass hiring | Summer students, lifeguards, election workers and seasonal crews: bulk offers, group onboarding and one-click rehire of returning staff |
| Indigenous hiring | Community hiring commitments and preference programs documented with their legal basis |
| Volume | Postings with 1,000+ applicants; AI-assisted screening always with human review and the disclosure required by Ontario |

## How CanDo compares

| Vendor | Recruiting position | CanDo response |
| --- | --- | --- |
| Dayforce | Recruiting plus talent intelligence from its 2023 acquisition of Ideal | Match AI matching with Canadian disclosure and bias controls |
| Humi by Employment Hero | AI first-round video screening agent for Canada since March 2026 | Offer AI assistance with human approval and Ontario disclosure built in |
| BambooHR, Rippling, Collage, Folks | Built-in ATS for SMBs | Match for SMBs; lead on union, public-sector and jurisdiction rules |

Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Source reconciliation

This document merges six readable recruitment sources and three workflow diagrams; overlapping content was combined once, and conflicts were resolved as below.

| Topic | Sources disagreed on | Resolution |
| --- | --- | --- |
| Section 3.2 name | "Candidate Acquisition", "Candidate Pipeline", "Candidate Qualification" | Split into Job posting and candidate acquisition, and Applicant evaluation |
| Probation versus status conversion | One source repeated the same feature list under both 3.7 and 3.8 | Probation holds review and decision features; status conversion holds eligibility, seniority and multi-position features |
| Performance claims | Stated as facts ("ensure 100% compliance") | Restated as targets to validate |
| Vendor material | DD Recruitment Module.docx includes a transcribed third-party document with case studies (healthcare network, provincial agency, multi-industry corporation) and pricing | Case studies excluded because they describe another product's results; pricing moved to the Master Overview as a proposal |
| Client-specific references | Burnaby agreement disclosure, Schedule A/B/C | Kept as examples of configurable rules |
| Missing content | module 1 final april 19.docx stops in 3.6; the two specification files point to an unavailable canvas | Sections 11.1–11.10 rebuilt from the workflow diagrams and Recruitment 1.docx |
| Unreadable files | Module C and D (docx, PDF, XML), three Bubble PDFs, requisition guide, vendor comparison | Not used; their tables of contents match the readable sources |

**October 2026 review:** added 2026 hiring rules by jurisdiction (Ontario, BC, PEI, NL, Quebec, federal), public-sector and high-volume hiring, and competitor comparison.
