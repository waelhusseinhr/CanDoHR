# 01 · Product scope and decisions

CanDo HRIS is a Canadian-first HR and payroll platform: 14 modules sharing one employee record, one rules engine and one audit trail. This file is the short version of what to build and the decisions already made. The full functional requirements are in `requirements/00` to `requirements/13`.

## Who it is for

| Segment | Size | Must-haves |
| --- | --- | --- |
| Small and mid-sized employers, non-profits | 25 to 499 employees | Fast setup, payroll accuracy, simple self-service, grant-funded positions |
| Large employers | 500 to 50,000+ employees, many legal entities | Scale, multi-entity payroll, SSO/SCIM, open APIs, SOC 2 |
| Municipal governments | Cities, regions, towns | Many collective agreements at once, platoon and 24/7 schedules, municipal pensions, salary disclosure |
| Provincial and territorial public sector | Ministries, agencies, school boards, health authorities | Central bargaining, public pension plans, official languages, accessibility |
| First Nations governments, Indigenous organizations | Any size | Indian Act s.87 tax exemption, federal jurisdiction for band employment, funding-agreement cost tracking, OCAP® data governance options |
| Unionized private employers | Any size | Agreement rules engine, seniority, retro pay after ratification, grievance history |

## Jurisdictions

All 14 Canadian jurisdictions: federal (Canada Labour Code), 10 provinces, 3 territories.

| Area | Launch | Phase 2 |
| --- | --- | --- |
| HR modules (all 14) | All jurisdictions including Quebec, English and French | |
| Payroll | Federal + 9 provinces + 3 territories (everything except Quebec provincial tax) | Quebec payroll after Revenu Québec certification |
| Quebec data model | Built at launch: QPP, QPIP, RL-1 fields, Revenu Québec accounts, HSF, CNESST | Calculation switched on |
| Interim for Quebec staff | Export to a certified Quebec payroll provider | Replaced by native payroll |
| Europe | Data model ready for country packs (no country logic) | First country pack after Canada |

## Decisions already made

| Decision | Choice | Why |
| --- | --- | --- |
| Stack | TypeScript end to end; Hono on Cloudflare Workers; Supabase PostgreSQL 16, Auth and Storage; React 18 | One language end to end; Postgres gives range types, exclusion constraints and row-level security, which effective dating and multi-tenancy need; managed services keep operations small |
| Platform | Supabase (database, authentication, file storage), Cloudflare (Workers, Hyperdrive, Queues, Durable Objects, Workflows, DNS and WAF), GitHub (code, reviews, CI/CD), a small AWS footprint for KMS keys and write-once audit anchors | Owner's choice (October 2026); see `02` |
| Architecture | Modular monolith with an event outbox, deployed as a few Workers sharing packages | One transaction can update HR, positions and payroll inputs together, which is what keeps every screen in sync |
| Hosting | Canada by default: Supabase `ca-central-1` for all personal data; Workers placed next to it; keys in AWS `ca-central-1`; audit anchors and the nightly recovery backup in AWS `ca-west-1` | Data residency for public-sector and Indigenous customers; Canadian resources where possible, with performance as the priority |
| Money | `NUMERIC(14,2)` in the database, decimal library in code, never floating point | Payroll must match CRA to the cent |
| Dates | Every business fact is effective-dated; corrections keep history (bi-temporal) | Retro pay, audits, "as of" reporting, future-dated reorganizations |
| Rules | Statutory values and collective agreements are data files with effective dates, never code constants | Two CRA editions a year, agreement renewals, provincial changes |
| Builder | AI coding agents in Cursor (any model) and other agents, step by step, using `15-build-plan.md`, with every change reviewed through GitHub pull requests | Owner's choice |
| Quebec | Design now, payroll in phase 2 | Owner's choice (see `requirements/00`) |
| US payroll | Not planned unless a customer requires it | Owner's direction: Canada first, Europe second |

## The integration promise

The owner's core requirement is that CanDo behaves like one system, not 14 connected ones:

1. **One write path.** Every change, whether it comes from the org chart, an employee profile, a mass update, an import, an API call or an approved request, becomes a change set (`03-data-model-and-effective-dating.md`). There is no second way to change data, so screens cannot disagree.
2. **Every view is a projection.** The org chart, employee profile, position list, budget, payroll inputs and analytics all read the same effective-dated records. Moving someone on the org chart changes their employee record. Editing their employee record moves them on the chart (`04-org-chart-two-way-sync.md`).
3. **Consequences are computed, not remembered.** When a change lands, the cascade rules (`05-integration-and-events.md`) work out what else changes: tax province, holiday calendar, agreement, approver, cost centre, funding, benefits eligibility, accruals, and retro pay if the date is in the past. The user sees these consequences before approving.
4. **Payroll runs on anything.** One employee, one day, a list of people, a whole entity, any date range, inside one fiscal year or across two, and inside one tax year or across two. The payroll engine (`06-payroll-engine.md`) resolves every day of the period against the data in force that day, and applies CRA's rule that deductions follow the pay date.
5. **People with several jobs are normal.** Several employments, assignments, rates, supervisors, funders and end dates per person are the design, not an exception (`17-enterprise-structures-and-integration.md`).
6. **The system helps.** It explains every number, warns before mistakes, suggests next steps and answers questions in plain language, within the user's permissions (`12-smart-assistant.md`).

## Out of scope for the first release

- Quebec provincial tax calculation and RL slips (phase 2)
- Native payroll outside Canada
- Native benefits carrier or pension administration (CanDo sends files to carriers and plans)
- Building a general ledger. CanDo exports journals to the customer's ERP.

## Glossary

| Term | Meaning |
| --- | --- |
| Effective date (valid time) | When a fact is true in the real world, for example a raise effective 1 April |
| Recorded time (system time) | When CanDo learned the fact. Corrections close the old row in system time and keep it. |
| Change set | One unit of change: one or more operations, one effective date, one approval, one audit entry, one batch of events |
| Projection | A read model built from records, for example the org chart as of a date |
| Pay date | The date money is paid. It selects the CRA edition and the tax year. |
| Work period | The days being paid for. It may cross months, fiscal years or calendar years. |
| Rule edition | A versioned file of statutory values, for example `ca-2026-07-01.json` |
| Agreement version | A versioned rule set for one collective agreement, with `effective_from` and an optional `retro_from` |
| PDOC | CRA's Payroll Deductions Online Calculator, the acceptance oracle for payroll tests |
| BN / RP account | CRA business number and payroll program account. CanDo tracks CPP and EI year-to-date per employer and payroll account. How several accounts under one BN interact follows T4001 and is a configuration flag per legal entity. |
| Worker | A Cloudflare Workers deployment: `api`, `jobs`, `realtime`, `identity` or `web` |
| Hyperdrive | Cloudflare's connection pool between Workers and the Supabase database |
