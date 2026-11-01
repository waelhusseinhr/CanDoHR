# Stories · 03 Payroll

Requirements: `requirements/03-payroll.md`. Design: `docs/06`, `docs/07`. Oracle: `reference/payroll_reference.py` and `tests/payroll/cases.json`.

The owner's Module 03 review (`docs/24`) wins where these stories differ. Its scenarios PAY-060 to PAY-086 are listed at the end.

## Statutory engine

**PAY-001 — Pass the fixture suite.** As the payroll rules lead, I want the TypeScript engine to reproduce every fixture, so that accuracy is proven.
- AC1: Every case in `tests/payroll/cases.json` passes in CI. `official` cases match exactly, `official-table` cases fall within the tolerance, `reference-only` cases match exactly, and `no-edition-2027` raises `NO_RULE_EDITION`.
- AC2: For 10,000 random inputs across all non-Quebec jurisdictions (property test), the TypeScript and Python engines agree to the cent.

**PAY-002 — Edition by pay date.** AC: given BC pays dated 30 June and 2 July for the same work, then the results use editions `CA-2026-01-01` and `CA-2026-07-01` respectively (fixtures `edition-switch-*`).

**PAY-003 — Explain any amount.** As an employee, I want to understand my deductions, so that I trust my pay.
- AC1: Each pay result stores a trace. `GET /payroll/results/{id}/explanation` returns every step with a plain-language sentence in English or French.
- AC2: The numbers in the explanation equal the stored amounts.

## Flexible runs

**PAY-010 — Regular run.** As a payroll processor, I want to run a pay group's regular period end to end.
- AC1: The run moves through draft → inputs_locked → calculated → reviewed → approved → finalized. Approval comes only through the organization's `pay_run` route, and the run's creator cannot approve any step of it (`docs/24` §4.1).
- AC2: Control totals (employees, gross, net) shown at review equal the sums of the results.

**PAY-011 — One person, one day.** AC: `docs/06` §10 test 1.

**PAY-012 — Mid-period raise.** AC: `docs/06` §10 test 2.

**PAY-013 — December work paid in January.** AC: `docs/06` §10 test 3.

**PAY-014 — Fiscal year split.** AC: `docs/06` §10 test 4.

**PAY-015 — Off-cycle in a period that already had pay.** As a payroll processor, I want missed amounts paid off-cycle and taxed correctly.
- AC1: Given a regular pay already finalized for the period, when I pay $5,000 off-cycle, then the bonus method applies, no second CPP exemption is taken, and income is annualized from the last regular pay (fixture `bonus-only-offcycle-AB`).

**PAY-016 — Simulation.** As an employee or HR, I want to preview pay under a proposed change. AC: `docs/06` §10 test 8.

**PAY-017 — 27 pay periods.** AC: `docs/06` §10 test 10.

**PAY-018 — Partitioned calculation is deterministic.** As a payroll lead, I want large runs split across workers without changing a cent, so that a 20,000-employee run finishes fast and the same way every time.
- AC1: `docs/06` §10 test 13: B = 1 and B = 100 give identical `result_sha256` for every subject, and identical control totals.
- AC2: Given a worker killed mid-bucket, then the bucket's transaction rolls back, the bucket is claimed again (`attempts` = 2), and no subject has two results.
- AC3: YTD accumulators change only at finalization, per bucket, in one transaction each; a run cancelled after calculation leaves YTD untouched.
- AC4: Statement numbers are allocated from per-bucket ranges and are unique within the tenant.

**PAY-019 — One open run per person.** As a payroll processor, I want the system to stop two open runs from paying the same person at once, so that YTD and maximums are never double-counted.
- AC1: `docs/06` §10 test 14: `lock_inputs` on a second run that includes a leased subject returns `409 SUBJECT_IN_OPEN_RUN` with the number of the run holding the lease. Creating that run in draft succeeds and lists the subjects already in open runs as a warning.
- AC2: The lease belongs to (payroll account, person), so a person with two employments under the same account is one subject; under two different accounts they are two subjects.
- AC3: Simulations never take leases. Finalizing or cancelling a run releases all its leases.

## Retro

**PAY-020 — Back-dated rate correction.** AC: `docs/06` §10 test 5.

**PAY-021 — Agreement ratified with retro.** As a payroll administrator, I want retro for thousands of employees calculated in batches with a cost preview.
- AC1: Given an agreement version with `retro_from` 15 months ago covering 8,000 employees, when it is activated, then retro requests are created in batches, a progress view shows done, total and cost, and nothing is paid until a retro run is approved.
- AC2: Prior-year amounts are paid and taxed in the current year and appear on the current-year T4 (`docs/06` §10 test 6).
- AC3: Employees terminated after `retro_from` are included when the agreement's `eligible_population` says so.

**PAY-022 — Reversal.** AC: `docs/06` §10 test 7.

## Deductions, disbursement, remittance

**PAY-030 — Deduction priority.** As a payroll administrator, I want deductions taken in a legal priority order, so that court orders are honoured and minimum pay is protected.
- AC1: Given net pay insufficient for all deductions, then statutory deductions are taken first, then family support orders, then other garnishments, then the organization's order for the rest. Each shortfall becomes arrears recovered as its deduction code says (next pay, spread, HR decides or not recovered), never below the protected minimum (`docs/24` §6.3).

**PAY-031 — Direct deposit file.** AC: given an approved run, when two different users release the file, then a CPA 005 (or the bank's ISO 20022) file is produced whose control totals match the run, matching the golden file for each bank profile (all major banks at launch, `docs/24` §7.3).

**PAY-032 — Remittance due dates.** AC: given a payroll account with remitter type `accelerated_1`, then pays dated 1 to 15 November are due 25 November, and pays dated 16 to 30 November are due 10 December.

**PAY-033 — Territorial payroll tax.** AC: given an employee working in Nunavut, then 2% of gross remuneration is withheld as `NU_PAYROLL_TAX` and excluded from T4 boxes.

**PAY-034 — s.87 exempt income.** AC: fixture `s87-cpp-exempt-MB`; the T4 shows exempt income in the correct other-information code; the evidence document is required before the status is `exempt_full`.

## Year-end and filings

**PAY-040 — T4 XML.** AC: given the tax-year results, then T4 XML validates against CRA's downloaded schema for the year, with one return type per submission, and empty optional tags removed.

**PAY-041 — PIER review.** AC: given an employee whose CPP or EI deducted differs from the calculated amount on pensionable or insurable earnings, then they appear on the PIER report before filing.

**PAY-042 — ROE.** AC: given a termination, then an ROE draft is created with insurable hours and earnings by pay period, the reason code mapped from the separation reason, and a due date per Service Canada's deadline. HR reviews the reason code and comments before the file is built (`ROE_NOT_REVIEWED`, `docs/24` §7.4); the employer uploads it to ROE Web.

## Controls

**PAY-050 — Segregation of duties.** AC: the same user cannot both change an employee's bank account and release a payment containing that employee within 30 days without a second approver.

**PAY-051 — Pre-run validation.** AC: missing bank details, rate below minimum wage, negative net and terminated-with-pay each produce an exception. As the organization chose (`payroll.failed_check_handling`), the affected employee is held with the check and a reason and paid off-cycle once fixed, or the run cannot be approved until every exception is fixed (`docs/24` §4.2). A missing TD1 follows FB-028 instead. A check that guards the law, such as a rate below minimum wage, is fixed, never overridden.

**PAY-052 — Pinned inputs and rules.** As a payroll approver, I want a locked run to stay exactly as reviewed, even when HR or the rules team keep working, so that what I approve is what gets paid.
- AC1: `docs/06` §10 tests 11 and 12. At `inputs_locked`, `inputs_known_at` and one `pay_run_rule_pin` row per rule source (statutory, employment standards, employer taxes, each agreement version, engine) are written.
- AC2: A worker that loads a rule whose hash differs from the pin stops the bucket with `RULE_HASH_MISMATCH`.
- AC3: Editing the content of a tested, active or retired edition, or of a verified, active or superseded agreement version, fails with `RULE_EDITION_IMMUTABLE` or `AGREEMENT_VERSION_IMMUTABLE`. A correction is a new edition with `supersedes` set.
- AC4: The run's explanation screen lists the pinned editions and agreement versions with their hashes.

**PAY-053 — Nightly replay.** As a payroll lead, I want finalized results recalculated every night from their pins, so that drift in code or data is caught before it reaches anyone's pay.
- AC1: Each night, a random sample of at least 0.5% of the previous day's finalized results, plus every result whose rules were affected by an activation, is recalculated with the pinned rules, the pinned engine version and `knownAt = inputs_known_at`, and the new `result_sha256` is compared with the stored one.
- AC2: `docs/06` §10 test 15: a tampered result line raises a severity-1 mismatch alert naming the result, and the engine version is blocked from new runs until it is cleared; nothing is changed automatically.

## Decisions from the owner's review

The scenarios below come from `docs/24` §13, which gives the expected result, the check and the build step for each.

| ID | Story |
| --- | --- |
| PAY-060 | Pay run approved only through its route, never by its preparer |
| PAY-061, PAY-062 | Failed checks hold the affected employees, or stop the run as the organization chose |
| PAY-063 | Pay dates on weekends and bank holidays move to the previous banking day |
| PAY-064 | A parallel run accepted before the first live run |
| PAY-065 | Outside payroll providers act only with the client's approval |
| PAY-066 to PAY-068 | Vacation pay per group of employees; proration chosen per pay group |
| PAY-069 | Banked time per group, mixing carry-over and payout, payout requests through the route |
| PAY-070 | Starter earnings codes copied only once verified |
| PAY-071 | Undefined premium combinations stop the line and go to labour relations |
| PAY-072 to PAY-076 | Garnishments confirmed first; voluntary deductions in self-service; a shortfall rule per deduction; recoveries only with written authorization |
| PAY-077 to PAY-079 | Delivery by CRA's rule; former employees' access; HR reviews every ROE |
| PAY-080 | One-time payments name their position |
| PAY-081 | One T4 for the year after a mid-year move |
| PAY-082 to PAY-085 | Remittance reminders; journal files; suspense; funding caps |
| PAY-086 | Statutory tables loaded centrally, never changed by an organization |
