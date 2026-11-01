# CanDo HRIS — 09 Succession & Workforce Planning

Oct 17, 2026 · @Wael

> **Owner's review (29 October 2026):** the decisions are in `docs/30-succession-workforce-planning-decisions.md`, which wins where this file differs. Changed here: one module for every organization, with talent reviews, the nine-box and workforce planning switched on by each organization (no size rule); flight risk is the manager's assessment only, with no prediction model; successors and openings suggested by rule with their reasons, no AI; succession data seen only by the people named on a review or plan, and HR, with every view logged; leaders score roles on five weighted criteria and HR confirms; positions the law requires always have a plan with an emergency successor; retirement from pension eligibility and what the employee shares, age only in totals; a work permit's end shown to HR only, as a date the role may become vacant; potential on the organization's criteria with the employee's aspiration beside it; placements hidden from employees by default; bias prompts for groups of 10 or more; plans through the organization's route, development only for unionized roles, reviewed yearly; continuity sheets with no secrets; pools by nomination or application; career paths from the job architecture and real moves; stretch assignments through positions; supply from the organization's history (uploaded history, the next level up when thin), demand from its own drivers; versioned scenarios; gap strategies that only draft; labour relations before a unionized reduction; the position plan through finance, HR and the executive; generic exports. The open questions are closed, except Indigenous leadership development (`docs/16` Q51).

## Overview and scope

> **Draft status:** new specification. Drafted from the employee lifecycle diagram (development and advancement stages), the performance workflow's promotion assessment, and the position and vacancy data in Modules 01 and 02.

Succession & Workforce Planning helps an organization keep the right people in the right roles over time: who could step into a critical role if its incumbent left, and how many people with which skills the organization will need in one to five years.

**In scope:** critical role identification and risk; talent reviews and potential assessment; succession plans and talent pools; internal mobility and career paths; strategic workforce planning (supply, demand, gaps, scenarios); headcount and position budget planning.

**Out of scope:** performance ratings (07); learning delivery (08); requisitions and hiring (02); compensation budgets (04, which receives cost assumptions).

**Scale:** every organization gets key roles, named backups and succession plans; each organization switches on talent reviews, the nine-box and workforce planning when it wants them, whatever its size (`docs/30` §3.1).

## Critical roles and risk assessment

**Critical role criteria** (scored by leaders 1 to 5, weights configurable, equal weights pre-filled; HR confirms the list): impact on strategy or operations; difficulty to replace (scarce skills, licensing, long time to proficiency); single point of failure (only one person can do it); external market scarcity; regulatory necessity (for example a designated safety officer or a licensed professional the organization must have). A position the law requires is always critical (`docs/30` §4.1–§4.2).

**Risk factors for each incumbent:**

| Factor | Source |
| --- | --- |
| Retirement eligibility | The eligibility date from the pension plan, agreement or policy, and the intentions the employee chooses to share; age shown to planners only in totals, never per person, and never used to pressure anyone to retire (`docs/30` §4.4) |
| Flight risk | The manager's assessment (low, medium or high, with a note); no prediction model. Engagement signals (Module 10) and the market ratio (Module 04) are shown only in aggregate (`docs/30` §4.3) |
| Impact of loss | From the critical role score |
| Bench strength | Number of ready-now and ready-soon successors |

**Risk matrix:** probability of vacancy against impact of loss, with bench strength overlaid, so leaders see which roles need succession plans first.

## Talent review

**Inputs gathered before the meeting:** performance ratings history (Module 07); potential assessment by the manager using the organization's criteria (starter: learning agility, leadership behaviours, aspiration, engagement); employee's own career aspirations and mobility (from their profile, always shown); skills and credentials (Module 08); time in role.

**Nine-box grid:** optional, off until the organization switches it on (`docs/30` §5.3). Performance (low, moderate, high) against potential (low, moderate, high), with box definitions and suggested actions per box that the organization edits; drag-and-drop placement during the review meeting with notes; changes recorded with reason.

**Readiness ratings for specific roles:** the organization's readiness list, starting with ready now, ready in 1 to 2 years and ready in 3 years or more (`docs/22` §3.4); someone who is not a fit is simply not named. Readiness is per target role, not a general label.

**Review meeting tools:** live talent cards (photo, role, tenure, ratings, aspirations, key strengths, development needs); filters; side-by-side comparison; calibration of potential across teams; bias prompts (for example when part-time employees, employees returning from parental leave or members of equity groups are consistently placed lower), shown only for groups of 10 or more.

**Transparency:** employees see their career aspirations, development plan and readiness feedback their manager chooses to share; potential and nine-box placements are confidential by default, with an employer option to share.

## Succession plans, talent pools and internal mobility

**Succession plan per critical position:** incumbent and risk; named successors with readiness, proposed by the plan owner and approved through the organization's route (starter: HR); the person's stated interest shown beside the nomination, with a mismatch flagged; emergency (interim) successor; development actions for each successor linked to their IDP in Module 08; external hiring as an explicit option where no internal bench exists; review date (yearly, reminder 30 days before) and owner. A plan for a unionized role is a development pipeline, not an appointment (`docs/30` §6).

**Talent pools:** groups such as high-potential leaders, future managers, technical experts or Indigenous leadership development cohorts; nominations by managers and applications by employees, approved by the pool owner through the route; pool-level development programs; movement tracking.

**Career paths:** typical moves between jobs (vertical, lateral, cross-functional) built from job architecture in Module 01 and historical moves; skills and credential requirements for each next step; employees explore paths and see gaps against their profile; pay ranges shown where the employer's transparency settings allow.

**Internal mobility:** internal job board fed by Module 02 postings, with rule-based recommended openings for employees based on skills and aspirations, only for employees who opt in to be visible; gigs, stretch assignments and secondments done through positions (a second position or an acting assignment); internal candidate rules from collective agreements (posting periods, seniority consideration) enforced by Module 02.

**Emergency coverage:** for every critical role, a one-page continuity sheet (key contacts, systems, delegations) the incumbent maintains, seen by the interim successor, the manager and HR; no passwords or secrets are stored in CanDo (`docs/30` §6.5).

## Workforce planning

**Supply model:** current headcount and FTE by job family, level, location and skill; projected attrition by segment using the organization's own turnover history (Module 12, plus history uploaded from a previous system) and retirement eligibility; internal movement rates; the result is projected supply for each future period if nothing changes. Where a segment's history is thin (under 10 people or 2 years), CanDo suggests the next level up and the planner accepts it or enters a rate with a reason (`docs/30` §9.2).

**Demand model:** business drivers entered by planners (revenue, service volumes, client caseloads, beds, students, projects, funded programs) with ratios to roles (for example one supervisor per 12 staff, one nurse per 6 beds); new capabilities required; roles to be automated or reduced. CanDo pre-fills no drivers or ratios.

**Gap analysis:** demand minus supply by segment and period, in headcount and skills; gap strategies recorded per segment, each drafting an action that people approve in its own module:

| Strategy | Feeds |
| --- | --- |
| Build (train internally) | Module 08 programs |
| Buy (hire externally) | Module 02 requisition forecast |
| Borrow (contractors, agencies, secondments) | Contingent workforce budget |
| Bind (retain) | Module 04 and 10 retention actions |
| Bot (automate) | Process change plans |
| Redeploy or reduce | Module 11 and collective agreement processes; in a unionized group, modelled only, with labour relations review and a caution before any real step |

**Scenarios:** base, growth and contraction scenarios with different driver assumptions; side-by-side comparison of headcount, skills gaps and cost; sensitivity to attrition and hiring lead times; scenarios unlimited, saved and versioned for board or funder presentations.

## Headcount and budget planning

**Annual position plan:** start from current positions (Module 01); add, eliminate or change positions with effective dates; each change carries cost (salary from Module 04 ranges or actuals, plus benefits and statutory burden rates from Modules 03 and 05); department leaders submit, finance and HR review, executives approve, through the organization's route, with a council or board step where needed.

**Cost model:** base pay, planned increases (merit and collective agreement), overtime and premium assumptions, benefits, CPP/QPP, EI, employer health tax, workers' compensation and pension costs by entity and province; vacancy factor; funding sources for grant-funded roles with end dates. Assumptions come from actuals and the planner edits them with a reason.

**Approved plan:** becomes position budgets that position control enforces in Module 01 and requisition approvals check in Module 02.

**Tracking:** budget versus actual headcount and cost by month; open positions and time to fill; forecast to year-end; variance explanations.

**Export:** plan and forecast as generic CSV and Excel files and in the payroll journal file profiles; links to named finance and ERP planning tools as customers need them.

## Canadian considerations

**Employment equity:** representation of designated groups in succession slates and talent pools compared with workforce and labour market availability, for HR and named reviewers, from consented self-identification only; federally regulated employers can use this for their employment equity plans (Module 13); goals and progress tracked, never shown for a group under 10.

**Indigenous organizations and Indigenous employment:** planning for community-member hiring and Indigenous leadership development, designed with Indigenous advisers (`docs/16` Q51); partnerships with Indigenous training organizations; community governance (for example council approval of senior appointments) as a step the organization adds to its own route; data governance per Module 01.

**Unionized workforces:** succession and internal mobility respect posting and seniority rules; layoffs from workforce reductions follow bumping and recall rules; planning scenarios can model the cost and timing of agreement-driven processes.

**Retirement:** Canada has no mandatory retirement age in most cases, so retirement risk is estimated from eligibility and stated intentions only, and voluntary phased retirement and knowledge-transfer arrangements are supported; age is shown to planners only in totals.

**Bilingual roles:** language requirements tracked so successors for bilingual positions are assessed for language proficiency; a gap shows in readiness and can feed a development plan.

**Immigration:** a work permit's end is shown to HR only, as a date the role may become vacant; planners see the date, never immigration details.

## Data model, integrations and security

| Entity | Key fields |
| --- | --- |
| Critical Role | Position, criteria scores, risk rating, owner |
| Talent Assessment | Employee, period, performance, potential, nine-box, notes, assessor |
| Career Aspiration | Employee, target roles, mobility, timeframe, visibility settings |
| Succession Plan | Position, successors with readiness, emergency successor, actions, review date |
| Talent Pool | Name, criteria, members, programs |
| Career Path | From job, to job, move type, requirements |
| Workforce Plan | Scenario, horizon, segments, drivers, ratios |
| Supply / Demand Projection | Segment, period, values |
| Gap Strategy | Segment, gap, strategy, actions, owner |
| Position Plan | Year, position changes, cost, approval status |

The tables are in `schema/0016_succession_workforce_decisions.sql` (`docs/30` §12).

**Integrations:** Core HR (positions, org, demographics, vacancies); Performance (ratings, promotion readiness); Learning (skills, IDPs, credentials); Recruitment (requisition forecasts, internal postings); Compensation (cost and ranges); Payroll and Benefits (burden rates); Analytics (turnover, retirement and movement history).

**Security:** talent assessments, potential and succession plans are among the most sensitive data in the system; access is limited to the people named on each talent review or plan and HR; employees are never shown other employees' placements; every view of succession data is logged.

## Public-sector and large-employer planning

| Area | Requirement |
| --- | --- |
| Statutory positions | Positions required by law (for example a municipal clerk or treasurer) flagged as critical with mandatory succession plans and emergency successors |
| Retirement waves | Pension eligibility from public-sector plans used, in aggregate, to project retirement exposure by department and occupation |
| Approved complement | Multi-year complement and budget plans aligned with council, board or ministry budget cycles |
| Bargaining scenarios | Workforce cost under settlement scenarios, shared with Module 13 costing |
| Service levels | Demand drivers for public services (population, caseloads, beds, students, transit hours) feeding headcount models |
| Scale | Planning across tens of thousands of positions with scenario versions for council or board presentations |

## How CanDo compares

Workforce planning and succession are strong in Workday and Dayforce and nearly absent below enterprise level; HiBob and BambooHR offer people analytics but no workforce planning. CanDo brings a lightweight version to mid-sized employers and full scenario planning to public-sector and large employers. Detail: [Competitive Analysis](https://claude.ai/code/artifact/8431bba2-ae2a-4b20-b7d2-6f89d632c2c0).

## Reporting, implementation and open questions

**Reports:** critical role coverage (percentage with at least one ready-now successor); bench strength by function; nine-box distribution; talent pool movement and promotion rates; internal fill rate; retirement eligibility exposure (aggregated); workforce gap by segment and period; scenario comparisons; position plan versus actual; equity representation in pools and slates.

**Implementation:**

| Step | Activities |
| --- | --- |
| 1. Critical roles | Leaders identify and score critical roles |
| 2. First talent review | Potential criteria agreed; managers assess; review meetings held |
| 3. Succession plans | Plans created for critical roles; development actions linked |
| 4. Workforce plan | Segments and drivers defined with finance; first supply and demand model |
| 5. Annual rhythm | Talent review and position planning aligned with the budget calendar |

**Sources:** employee-lifecycle-workflow.svg (development and advancement); performance-management-workflow.svg (promotion assessment); Modules 01 and 02 (positions, vacancies, requisitions). Everything else is new drafting.

**Open questions:**

- [x] Should flight-risk prediction be offered at all, given privacy and fairness concerns, or limited to manager assessment? Manager assessment only, with no prediction model (`docs/30` §4.3)
- [x] Minimum customer size for full workforce planning features: none; each organization switches the parts on (`docs/30` §3.1)
- [x] Integration targets for finance planning tools: generic CSV and Excel files and the payroll journal profiles; named tools as customers need them (`docs/30` §10.5)
- [ ] Indigenous leadership development features: designed with Indigenous advisers (`docs/16` Q51)

**October 2026 review:** added public-sector planning (statutory positions, retirement waves, complement, bargaining scenarios) and competitor comparison.

**29 October 2026 (owner's review):** the decisions in `docs/30`.
