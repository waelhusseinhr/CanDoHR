# Stories · 11 Offboarding & Separation

Requirements: `requirements/11-offboarding-separation.md`.

**OFF-001 — Separation wizard.** As an HR administrator, I want one guided flow for any separation, so that pay, ROE, benefits and access are all handled.
- AC1: The wizard collects the reason, who initiated it, notice date, last day worked and termination date. It then shows statutory notice, statutory severance where it exists, vacation owing, benefits continuation and final pay deadline, with the rule source for each.
- AC2: Committing the separation creates one `employment.terminate` change set. All assignments end, positions are vacated, future change sets are listed for cancellation, and events go to payroll, benefits, IdP and offboarding tasks.

**OFF-002 — Statutory notice by jurisdiction.** AC: notice weeks come from `rules/employment-standards` bands for the employee's jurisdiction and service, for example Ontario with 6 years of service gives 6 weeks, and BC with 4 years gives 4 weeks. Entries marked `verify_at_load` block activation in production.

**OFF-003 — Ontario and federal severance.** AC: Ontario severance (1 week per year of service, prorated, up to 26 weeks) applies when the employee has 5 or more years and the employer's payroll is at least $2.5 million, or the termination is part of a qualifying group termination. Federal severance is the greater of 2 days' wages per year of service or 5 days, after 12 months of service.

**OFF-004 — Final pay deadline.** AC: the deadline is calculated per jurisdiction and initiator (for example Ontario: the later of 7 days or the next regular pay day; BC: 48 hours when the employer terminates, 6 days when the employee quits). If the next regular run is too late, an off-cycle `final` run is scheduled automatically.

**OFF-005 — Final pay components.** AC: wages to the last day, outstanding overtime and banked time, vacation pay owing, holiday pay, pay in lieu of notice, severance, retiring allowance (with RRSP direct transfer where elected) and lawful recoveries (with written authorization, never below statutory minimums) arrive in payroll as one-time items with their work periods.

**OFF-006 — ROE.** AC: an ROE is created with the reason code mapped from the separation reason, insurable hours and earnings by pay period, and vacation and severance in the right blocks. It is due within Service Canada's deadline, and amended if final amounts change.

**OFF-007 — Group termination thresholds.** AC: the system counts terminations per establishment in rolling windows per jurisdiction, and warns before a group-termination threshold is crossed. Ministry notice forms are prepared.

**OFF-008 — Temporary layoff tracking.** AC: layoffs record expected recall dates. Alerts fire before a layoff becomes a deemed termination under the jurisdiction's limits, and the ROE is issued with the correct code.

**OFF-009 — Layoff by seniority with bumping.** AC: for agreements with bumping, the system lists bumping options per employee by seniority and qualifications, and records offers, responses and recall rights with expiry dates.

**OFF-010 — Access removal.** AC: IdP deactivation happens at the configured time (for example 17:00 on the last day, or immediately for dismissals). Asset recovery tasks are created from the employee's assigned equipment.

**OFF-011 — Death of an employee.** AC: payments go to the estate with the correct slip treatment, benefits claims are triggered, and communications use bereavement templates.

**OFF-012 — Documents in either language.** AC: termination letters, releases and references are generated in English or French. Quebec employees receive French documents.
