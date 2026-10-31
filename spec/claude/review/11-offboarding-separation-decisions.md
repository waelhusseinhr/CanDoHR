# 11 Offboarding & Separation · Review decisions

Review started 30 Oct 2026 with Wael. Decisions are logged here round by round; the developer pack is updated when the review is complete.

Planned rounds: 1 scope, initiation and confidentiality · 2 notice, severance and legal review · 3 documents and templates · 4 final pay, the ROE and benefits · 5 offboarding tasks, access and assets · 6 layoffs, recall and group terminations · 7 exit feedback, rehire and alumni · 8 retirement, death and public-sector separations.

The principle from Modules 01 to 10 applies: every decision is a default each organization can change at setup or later, except legal floors and safety rules; routes and rules are the organization's, with reminders, cautions and recorded acknowledgements; CanDo pre-fills its suggested numbers at setup and the organization can change them (Q46).

Already decided elsewhere and not asked again: terminations, demotions and leave-linked changes always need HR (`docs/21`); before any ending HR reviews open cases and leave, including cases closed in the last 12 months, and this cannot be switched off (`docs/23` §7.5); rehire eligibility is eligible, check with HR or not eligible, HR-only, with a review date and no protected-ground reasons (`docs/21` §3.4); prior service on rehire is proposed by rule and HR confirms (`docs/21` §3.6); CanDo prepares final pay and the ROE, HR reviews the ROE's reason code and the employer pays and uploads (`docs/24` §7.4); former employees keep a limited login (`docs/24`); money owed is recovered only with written authorization (`docs/21` §7.2, `docs/24`); bonus clawbacks only per a signed agreement (`docs/25`); benefits end per class as the organization sets, never before the law, with a caution outside Ontario about common-law notice (`docs/26` §7.1); tuition repayment only per the organization's rules (`docs/29` §8.3); the exit survey runs automatically with group thresholds (`docs/31` §3.6); unionized reductions are modelled with labour relations review (`docs/30` §9.5); a notice from the incumbent of a position the law requires opens a review of its succession plan (`docs/30` §6.4); statutory values live in the rules files as `verify_at_load` until checked; people decide and AI never decides (AGENTS rule 14).

## Round 1 · Scope, initiation and confidentiality

| # | Decision |
| --- | --- |
| 1 | **Employees submit a written resignation in the app with their last day; the manager and HR are told. Terminations, layoffs and ends of term are started by the manager or HR and go through the organization's route.** |
| 2 | **An involuntary termination is seen only by HR and the named approvers until the meeting;** IT and facilities tasks (account shut-off, badge) are released at the time HR sets. |
| 3 | **A termination for cause always includes a legal review step in its route** (in-house or outside counsel), recorded with who reviewed it. |
| 4 | **Job abandonment: HR records documented contact attempts (pre-filled: 3 attempts over 5 working days, editable), checks for leave or illness and acknowledges a caution before treating it as a resignation.** |

## Round 2 · Notice, severance and legal review

| # | Decision |
| --- | --- |
| 1 | **No common-law notice estimator:** CanDo calculates only the statutory minimums, shows a caution that common law may give more, and HR records the package decided after legal advice (closes the open question). |
| 2 | **Every termination without cause of a non-union employee needs a caution:** statutory amounts are a floor and common law may require more unless the contract has an enforceable termination clause; HR acknowledges it and records whether counsel reviewed it. |
| 3 | **HR chooses working notice, pay in lieu or a mix per case; CanDo checks the statutory minimum is met** and keeps wages and benefits going through the notice period as the law requires. |
| 4 | **Fixed-term contracts: the manager and HR are asked for a renewal decision 60 days before the end; after 2 renewals HR sees a caution that repeated renewals may make the employment indefinite** (both pre-filled, editable). |

## Round 3 · Documents and templates

| # | Decision |
| --- | --- |
| 1 | **CanDo supplies starter templates per jurisdiction in English and French; each organization's counsel or HR approves its own copy before first use, and CanDo records who approved it** (closes the open question). |
| 2 | **A release can be tied only to money above the law:** statutory notice, severance, vacation and wages are paid regardless; the letter suggests independent legal advice and gives time to consider (pre-filled 7 days, editable). |
| 3 | **A factual employment confirmation letter by default** (dates, positions, and pay if the employee asks); opinion references are written by HR or a manager on request, outside the template. |
| 4 | **Separation documents in the employee's preferred language; Quebec employees always get French,** as the Charter of the French Language requires, and English as well only if they ask. |

## Round 4 · Final pay, the ROE and benefits

| # | Decision |
| --- | --- |
| 1 | **CanDo works out the final pay deadline from the jurisdiction and who ended the employment, and when the next regular run is too late it proposes an off-cycle final run in time; payroll approves it through the usual pay-run route.** |
| 2 | **Retiring allowance: CanDo calculates the eligible portion from service before 1996 (CRA's rule) and the employee chooses how much goes directly to their RRSP,** with no tax withheld on the direct transfer. |
| 3 | **CanDo sends benefit conversion notices from each plan's options and carrier deadline** on separation, and reminds the person before the deadline. |
| 4 | **Unreturned equipment or a company card is deducted from final pay only with the employee's written authorization and only where that province allows it, never below the legal minimum;** otherwise finance invoices the person separately. |

## Round 5 · Offboarding tasks, access and assets

| # | Decision |
| --- | --- |
| 1 | **Access is removed at the end of the last scheduled shift (or 17:00 if none) for resignations and ends of term, and at the time HR set for the meeting for involuntary terminations;** each organization can change the times per type. |
| 2 | **Automatic account shut-off through SCIM with Microsoft Entra ID, Okta and Google Workspace at launch;** other organizations get a dated task or an emailed ticket to their IT desk. |
| 3 | **A case closes only once access removal, final pay and the ROE are done;** other tasks (keys, handover, exit interview) can be closed with a reason if they cannot be completed. |
| 4 | **A handover plan for every voluntary departure (resignation, retirement, end of term); for critical roles, the continuity sheet from Module 09 is updated and the emergency successor named.** |
