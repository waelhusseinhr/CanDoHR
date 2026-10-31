# 04 Compensation Management · Review decisions

Review started 27 Oct 2026 with Wael. Decisions are logged here round by round; the developer pack is updated when the review is complete.

**Status: applied 28 Oct 2026.** The decisions are in `dev-pack/docs/25-compensation-decisions.md`, migration `dev-pack/schema/0011_compensation_decisions.sql` and its smoke test, the register, `rules/compensation/salary-disclosure.json`, `rules/competencies/unified-competency-model.json` (version 1.0, accepted), and the updates listed in docs/25 §14. Numbers CanDo pre-fills at setup, each organization's to change (the Q46 principle): spreads 30/40/50/60% by track; catch-up within 12 months; promotion at least 5%; cycles exclude hires from the last 3 months. Chosen at setup with no CanDo default: acting pay. Fixed floor: pay gap and other self-identification results never show a group under 10.

Planned rounds: 1 scope, philosophy and survey data · 2 structures and ranges · 3 pay administration · 4 planning cycles · 5 variable pay · 6 pay equity, transparency and total rewards · 7 public sector and special cases.

The principle from Modules 01 to 03 applies: every decision is a default each organization can change at setup or later, except legal floors and safety rules; routes and rules are the organization's, with reminders, cautions and recorded acknowledgements; CanDo pre-fills its suggested numbers at setup and the organization can change them (Q46).

Already decided elsewhere and not asked again: job, market and person kept separate (`docs/19` §2.1, AGENTS rule 34); survey data belongs to its publisher and licensee, masked values never estimated (AGENTS rule 35); market pricing arithmetic per the reference calculator (AGENTS rule 36); grade from the job evaluation only, never from the person (`docs/21`); job descriptions never written by AI (`docs/21` §6.3); pay shown on postings within the law and the incumbents' average only from 3 incumbents (`docs/23` §4.2); one-time payments name their position (`docs/24` §8.2).

## Round 1 · Scope, philosophy and survey data

| # | Decision |
| --- | --- |
| 1 | **The compensation philosophy is pre-filled at setup ("match the market median") and the organization edits it;** executive approval is needed only when a market-based pay structure is published. |
| 2 | **Survey imports: generic CSV and Excel import profiles at launch; a publisher's own template is added when a customer sends a sample file and the publisher allows it** (closes docs/16 Q31). |
| 3 | **Managers do not see their team's market ratios until the organization switches it on, and never where a survey's licence restricts derived results** (closes docs/16 Q32). |
| 4 | **Long-term incentives: basic tracking at launch:** grants and vesting dates recorded, and the taxable benefit sent to payroll; no valuations. Bonus, commission, spot awards, retention bonuses and profit sharing are at launch. |

## Round 2 · Structures and ranges

| # | Decision |
| --- | --- |
| 1 | **Range spreads are pre-filled by track and editable for each grade:** support 30%, professional 40%, management 50%, executive 60%. |
| 2 | **A new pay structure version is approved through the organization's own route;** the starter copy is HR, then finance, then an executive. |
| 3 | **Pay below the range minimum is flagged with a catch-up plan to reach the minimum within a period the organization sets (12 months pre-filled),** and the catch-up is included in cycle budgets. |
| 4 | **Location pay: both methods are available and each structure says which:** separate ranges per location group, or one range plus a location premium for the person. |

## Round 3 · Pay administration

| # | Decision |
| --- | --- |
| 1 | **Pay above the range maximum has no CanDo rule: the manager proposes, and the organization's route approves** (lump sum, base increase or none). The red circle is flagged. |
| 2 | **A promotion pays at least the new range minimum and at least a minimum percentage increase the organization sets (5% pre-filled).** |
| 3 | **A demotion or a job reclassified down keeps the person's pay, red-circled (no base increases until the range catches up);** anyone reducing it sees a caution (constructive dismissal risk) and records why. Collective agreements keep their own rules. |
| 4 | **Acting pay for non-union staff has no CanDo starting rule: the setup wizard asks each organization** (chosen at setup). Collective agreements keep their own rules. |

## Round 4 · Planning cycles

| # | Decision |
| --- | --- |
| 1 | **Cycle eligibility starts from pre-filled rules the organization edits for each cycle:** union groups on negotiated increases excluded; people hired in the last 3 months excluded; people on unpaid leave get their increase when they return. |
| 2 | **Merit guidelines start from a matrix of performance rating and position in range, with percentages set each cycle against the budget;** organizations without ratings use range position only. Across-the-board and manager-discretion cycles are also available. |
| 3 | **A recommendation outside the guideline needs a written reason and HR's approval,** as well as the organization's route. |
| 4 | **Employee letters are generated from the organization's templates in the employee's language; HR reviews them and releases them to self-service.** |

## Round 5 · Variable pay

| # | Decision |
| --- | --- |
| 1 | **Bonus and incentive payouts are approved through the organization's own route before they go to payroll;** the starter copy is the manager, then HR, then finance. No one approves their own payout. |
| 2 | **A signing or retention bonus clawback is recovered only as the signed bonus agreement allows, from the final pay within the law's limits** (as decided for payroll, `docs/24` §6.4); otherwise HR follows up. |
| 3 | **Bonuses are prorated by the days in the plan year the person was eligible;** each plan can change it, and statutory leaves are treated as the law requires. |
| 4 | **Sales commissions at launch are basic:** plan rates, tiers and caps, results imported by file, statements and payout to payroll. Draws, recoverable advances and CRM connections come later. |

## Round 6 · Pay equity, transparency and total rewards

| # | Decision |
| --- | --- |
| 1 | **Employees see a moderate level of pay information by default:** a summary of the pay philosophy, their own range and which quarter of it they are in; managers see their team's ranges. Each organization changes it item by item. |
| 2 | **Pay gap analysis at launch covers gender and the voluntary self-identification groups (Indigenous, racialized, disability),** only with consent and hidden below 10 people. |
| 3 | **Compliance reports at launch: both the BC pay transparency report (employers with 50+ employees, due each 1 November from 2026) and the federal reports** (pay equity and employment equity). Ontario and Quebec pay equity follow. |
| 4 | **Total rewards statements are produced on request,** by HR or the employee; the organization picks which items appear. |

## Round 7 · Public sector and special cases

| # | Decision |
| --- | --- |
| 1 | **Public salary disclosure lists are drafted by CanDo from amounts paid, by the statute's rules; HR and finance review them, and the organization's route approves them before they are published.** |
| 2 | **CanDo's gender-neutral job evaluation plan stays a sample until a pay equity adviser reviews it;** each organization records its own gender-neutral review before using it for pay equity (closes docs/16 Q29 for now). |
| 3 | **Costing bargaining proposals is at launch:** cost models over the agreement term from live pay, benefits and schedule data, shared with labour relations; nothing changes pay until the agreement is ratified. |
| 4 | **The competency model's level indicators and the starting competency targets by career level are accepted as written** and published as CanDo's starting framework, which each organization can edit (closes docs/16 Q27). |
