# 06 · Payroll engine: flexible runs, year boundaries and retro pay

**Requirement from the owner:** "You can run payroll for one day or for one person or for whatever you want, within a fiscal year, between two fiscal years, etc., and it renders all the information."

**How CanDo meets it:** a pay run is defined by four independent choices (who, which days of work, which pay date, which run type), and not by a fixed calendar. The engine resolves every day of the work period against the records in force on that day, and applies CRA's rule that deductions and slips follow the **pay date**.

Statutory formulas are in `07-canadian-statutory-calculations.md`. The reference implementation is `reference/payroll_reference.py`, and `tests/payroll/cases.json` is the acceptance suite.

> **Owner's review (27 October 2026).** `docs/24-payroll-decisions.md` adds pay run approval through the organization's route, holds for failed checks, the parallel run before going live, outside payroll providers, and the payroll rules each organization sets per group of employees. It wins where this document differs.

## 1. Concepts

| Concept | Definition |
| --- | --- |
| Pay group | Employees paid together: legal entity, payroll account, frequency (P), calendar, currency CAD |
| Pay calendar | Generated periods for a pay group: work period start and end, cut-off, pay date. Pay dates move to the previous banking day when they fall on a weekend or bank holiday (decided in the owner's review, `docs/24` §4.3). |
| Work period | The days being paid for. Any range: one day, part of a period, a full period, or several periods. |
| Pay date | When money is paid. Selects the statutory edition, the tax year and the YTD bucket. |
| Run type | `regular`, `off_cycle`, `bonus`, `retro`, `final`, `adjustment`, `reversal`, `manual_payment_record`, `simulation` |
| Population | `pay_group`, an explicit list of employees, a saved query (unit, agreement, location), or "everyone affected by change set X" |
| Tax year | Calendar year of the pay date. Always. |
| Fiscal year | The legal entity's accounting year (for example 1 April to 31 March). Used only for GL, budgets and reports, never for statutory deductions. |

## 2. Creating a run

```http
POST /v1/payroll/runs
{
  "type": "off_cycle",
  "legalEntityId": "…",
  "payGroupId": "…",                     // optional for ad-hoc populations
  "population": { "mode": "employees", "employmentIds": ["…"] },
  "workPeriod": { "start": "2026-11-03", "end": "2026-11-03" },
  "payDate": "2026-11-05",
  "include": { "salaryAndHourly": true, "approvedTime": true, "leave": true,
               "benefits": false, "recurringDeductions": false, "oneTimes": ["…"] },
  "taxMethod": "auto",                    // auto | periodic | non_periodic
  "simulate": false,
  "reason": "Missed shift for 3 Nov"
}
```

The run moves through `draft → inputs_locked → calculated → reviewed → approved → finalized → paid`. Each step is audited. Approval goes through the organization's `pay_run` route, and the person who created the run can approve no step of it (`docs/24` §4.1). A `simulation` run never finalizes and never touches YTD. It produces the same full results and explanations, so users can preview any scenario.

### Examples the engine must support

| Scenario | Request |
| --- | --- |
| Normal bi-weekly payroll | `regular`, pay group, its calendar period |
| One person, one day | `off_cycle`, one employee, `workPeriod` of one day |
| Several people, last week only | `off_cycle`, list, seven-day work period |
| New hire missed the cut-off | `off_cycle`, one employee, hire date to period end |
| Final pay | `final`, one employee, period start to termination date, plus payouts from Module 11 |
| Bonus for a department | `bonus`, query population, no work period, one-time earnings |
| Retro after ratification | `retro`, change set population, work period = `retro_from` to last finalized period |
| Work in December, paid in January | `regular`; work period in 2026, pay date in 2027: 2027 edition, 2027 YTD, 2027 T4 |
| Work spanning 31 March (fiscal year end) | Any run; GL lines split by fiscal period of each work day |
| What-if before a raise | `simulation`, one employee, proposed change set applied in memory |

## 3. Resolving the work period day by day

For each employee in the population:

1. **Collect day slices.** For each date in the work period, read (as of that date, with current knowledge) the assignment(s), pay rate, FTE, schedule, agreement version, location and province, leave and approved time.
2. **Merge into segments.** Consecutive days with identical inputs become one segment. A two-week period with a raise on day 6 and a transfer on day 9 produces three segments.
3. **Generate earnings per segment.**
   - Salaried: period amount × (segment working days ÷ period working days), using the proration method configured for the pay group (calendar days, working days, scheduled hours; each pay group chooses it at setup, `docs/24` §5.2). For a work period that is not a standard period, prorate from the annual salary: annual × (segment working days ÷ annual working days).
   - Hourly: approved hours by pay code × rate in force on the work date.
   - Time and leave: approved time and leave from Module 06, already split into pay codes (regular, overtime, premiums, holiday, leave).
   - Agreement premiums: from the agreement version in force on the work date.
4. **Add one-time items** with their own dates: bonuses, allowances, payouts, retro lines.
5. **Tag each line** with its work date range, pay code, GL distribution (from the segment's org unit, cost centre and funding lines), and fiscal period (from the work date).

Earnings follow the **work date**: the rate, agreement and cost centre in force when the work was done. Deductions follow the **pay date**: edition, tax year and YTD.

## 4. Choosing the tax method and P

| Situation | Method | P |
| --- | --- | --- |
| Regular run, employee's normal period | Periodic (T4127 Option 1) | Pay group P |
| Regular run, partial period (hire, termination, unpaid leave) | Periodic on the partial earnings. The CPP per-period exemption stays the same (T4001). | Pay group P |
| Off-cycle run covering missed regular earnings, no regular pay for that period yet | Periodic, as if it were the regular pay | Pay group P |
| Off-cycle run in a period that already had a regular pay | Non-periodic (bonus method), no second CPP exemption | Pay group P; `I_recent` = last periodic gross |
| Bonus, retro lump sum, vacation pay not taken, banked overtime payout | Non-periodic (bonus method) | Pay group P |
| Casual or day workers paid per day | Periodic with a daily pay group | 240 |
| Employee with no pay group (one-time honorarium to an employee) | Non-periodic with `I_recent = 0`. The $5,000 rule may apply. | 1 |
| Pay group with 27 bi-weekly or 53 weekly pay dates in the year | Periodic | 27 or 53, set at the start of the year (T4127) |

`taxMethod: auto` applies this table. An override needs a reason and is audited. P never changes in the middle of a year for a pay group. Changing frequency means moving employees to a new pay group from a date.

## 5. Year and edition boundaries

- **Edition:** `ref.rule_edition` whose `[effective_from, effective_to]` contains the pay date. If no edition covers the pay date, the run stops with `NO_RULE_EDITION`. It never falls back to an older year. Test: `no-edition-2027`.
- **Mid-year editions:** a pay dated 30 June 2026 uses the January edition; a pay dated 2 July 2026 uses the July edition, even when both pay for June work (tests `edition-switch-BC-jun30` and `edition-switch-BC-jul02`).
- **YTD:** accumulators keyed by `(person, payroll account, tax year of pay date, province, code)`, so a person rehired under a new employment in the same year, or holding two employments with one employer, shares one set of CPP, CPP2 and EI maximums. The maximums use the tax year of the pay date.
- **Slips:** T4 boxes accumulate by pay date year. December work paid in January is on next year's T4.
- **Fiscal year:** GL lines carry the fiscal period of each work day. With accrual accounting on, the engine also produces the accrual and reversal journals for work days that fall in a closed or different fiscal period. Budgets in Module 09 use the work-date fiscal year.
- **Closed tax year:** once the year's slips are filed, results with pay dates in that year are locked. Changes create amendment records (T4 amended) through a prior-year adjustment with its own permission.

## 6. Retro pay engine

**Triggers:** a change set with a past effective date that touches rates, agreements, assignments, time, leave, benefits deductions or payroll profile, for a period that is already finalized.

**Algorithm (per employee and finalized period affected):**

1. *Was paid:* load the stored result for the original run (immutable).
2. *Should have been paid:* recalculate the earnings for the same work period, using records as currently known (bi-temporal: valid time = the work dates, system time = now). Use the same statutory edition as the original pay date for comparison only.
3. *Difference by pay code:* should minus was, per earnings code, plus differences in pensionable earnings, insurable earnings, pension contributions and employer costs.
4. *Payable now:* the earnings differences become retro lines in the next run (or a `retro` run), dated with their original work period and tagged `retro_of = original_result_id`.

**Deductions on retro lines:** treated as non-periodic payments in the run where they are paid. Tax uses the bonus method, and CPP and EI use the pay-date year's rates and maximums. This follows CRA's guidance for retroactive pay increases. Amounts for prior years are taxed and reported in the year paid. If a payment qualifies as a retroactive lump-sum payment (for example an arbitration award of $3,000 or more covering prior years), CanDo produces Form T1198 or the equivalent letter.

**Negative differences** (overpayments) follow the recovery rules in Module 03 and T4001: written consent where employment standards require it, per-period limits, and prior-year treatment.

**Scale:** a ratified agreement for 8,000 employees over 18 months creates retro requests in batches of 500. Workers process them in parallel. A progress view shows employees done, total cost and exceptions, and nothing is paid until the retro run is approved.

**Who is eligible:** follows the agreement's `retro.eligible_population` (for example, active on ratification plus those terminated after `retro_from`).

**Other outputs:** pension contribution differences go to the pension remittance file. ROE insurable earnings and hours for affected pay periods are recalculated, and amended ROEs are issued where Service Canada requires it. GL differences post to the current period, or to the original fiscal periods, per entity setting.

## 7. Gross-to-net order

1. Earnings lines (by segment and code)
2. Pre-tax deductions: RPP, RRSP at source, union dues (union dues reduce taxable income: T4127 factor U1)
3. Taxable benefits added (they affect tax, and CPP or EI per CRA treatment)
4. Pensionable earnings (PI) and insurable earnings (IE) per code flags
5. CPP, CPP2, EI (QPP and QPIP in phase 2), with YTD and maximums
6. Income tax: periodic plus non-periodic, by method
7. Territorial payroll tax (NT, NU) where the work is performed there
8. Post-tax deductions in priority order: court-ordered support, other garnishments, then the organization's order (benefits, voluntary and the rest)
9. Net pay, protected minimums, arrears (recovered as each deduction code says, `docs/24` §6.3)
10. Employer costs: CPP, CPP2, EI (1.4 or reduced rate), EHT and levies, WCB, benefits, pension
11. Payment split (bank accounts by amount or percentage)

Each step writes trace entries (`label`, value, formula reference), so any number on a pay statement can be explained (`12-smart-assistant.md` §3).

## 8. Determinism: pinned inputs and pinned rules

A finalized result must be reproducible to the cent at any time in the future. Two things are frozen when a run moves to `inputs_locked`:

1. **Inputs, by system time.** The run records `inputs_known_at` (the lock timestamp). Every read the calculation makes uses `knownAt = inputs_known_at`. Because all business data is bi-temporal (`03` §1), nothing needs copying: HR can keep committing change sets while the run calculates, and the run still sees exactly what was known at the lock. Changes committed after the lock that affect the run's work period become retro requests after finalization (§6).
2. **Rules, by content hash.** The run writes one `payroll.pay_run_rule_pin` row for each rule source it may use: the statutory edition for the pay date, the employment standards and employer-tax editions, and every agreement version in force for any subject during the work period. Each row records the ID and the `content_sha256`, plus the engine version (the build's git commit). Workers load rules **by hash**, verify the hash after loading, and keep caches keyed by hash. A new edition or agreement activated mid-week can therefore never leak into a locked run.

Rules that make the pins trustworthy:

- **Active rule content cannot change.** Database triggers reject any update to `content`, `content_sha256` or effective dates of a `ref.rule_edition` row once it is `tested`, `active` or `retired`, and the same for `core.agreement_version` once it is `verified`, `active` or `superseded`. Status may only move forward. A correction is a new edition (for example `CA-2026-07-01.r2`) that names the edition it supersedes.
- **Activation while runs are locked.** Activating a new edition or agreement version lists the open runs it would have affected. Those runs finish on their pins. After they are finalized, the retro engine compares the pinned rules with the new ones and creates retro requests where the result differs. Before approval, a payroll administrator may instead cancel the run and lock it again to adopt the new rules. The choice is audited.
- **Pure engine.** `calculate(inputs, pinnedRules, engineVersion) → result + trace` does no I/O.
- **Stored with every result:** input snapshot hash, the run's pins, engine version, and a `result_sha256` over the canonical result and lines. The finalization audit entry carries `result_sha256`, so the anchored audit batches (`10` §5) also prove the result has not changed.
- **Nightly replay.** A job re-runs a random sample of finalized results (at least 0.5% of the previous day's results and every result of any rule change) with their pins and `inputs_known_at`, and requires an identical `result_sha256`. A mismatch is a severity-1 incident, and the affected engine version is blocked from new runs until it is explained.
- **Simulations** of a past period offer two modes: "as paid" (the original pins and known-at, which reproduces the stored result) and "as it should be now" (current rules and current knowledge, which is what the retro engine uses).

## 9. Partitioning and concurrency

Calculation takes milliseconds per person. The time goes into loading inputs and writing results, so the design batches I/O and makes sure no two workers ever touch the same person's rows.

**The unit of isolation is the pay subject:** one person within one payroll account. That is where CPP and EI maximums, earnings combined across several jobs, garnishment priority and arrears all live. Partitioning by pay group or cost centre is not used: a person with two jobs in two cost centres would be split across workers, and one pay group of 40,000 people would land on one worker.

| Phase | What happens | Contention |
| --- | --- | --- |
| 1. Lock inputs | Resolve the population to pay subjects. Take a **subject lease** for each (`payroll.pay_run_subject`, unique for open runs). Write the rule pins and `inputs_known_at`. | A subject already leased by another open run blocks this run with `SUBJECT_IN_OPEN_RUN`, which names the blocking run (see below) |
| 2. Partition | Assign each subject to bucket `hash(payroll_account_id, person_id) mod B`, where B = ceil(subjects / 500), between 1 and 256. Write one `payroll.pay_run_partition` row per bucket. | None |
| 3. Calculate | A worker claims a bucket (`FOR UPDATE SKIP LOCKED` on its partition row), bulk-loads the inputs of all its subjects as of `inputs_known_at`, runs the pure engine for each, and writes all the bucket's results in **one transaction**. It then marks the bucket done with a checksum over its sorted `result_sha256` values. | None: buckets hold disjoint subjects. Reference data (grids, editions) is read-only. |
| 4. Retry | A failed or timed-out bucket is claimed again. The retry deletes only that bucket's `calculated` results and writes them again, so the step is idempotent. | None |
| 5. Finalize | One transaction per bucket marks the results finalized and updates `payroll.ytd_accumulator` for its subjects. The run is finalized when every bucket is. | None: YTD rows are keyed by subject, and only finalization writes them |

Rules:

- **YTD changes only at finalization.** During calculation, a subject's YTD is the finalized YTD. The subject lease guarantees that no earlier unfinalized run exists for the same subject.
- **Subject leases order the runs.** A lease is taken at `inputs_locked` and released at `finalized` or `cancelled`. Two runs that include the same person, such as a regular run and an off-cycle run with the same pay date, therefore calculate and finalize one after the other, in lock order. The UI offers to add the person to the open run instead of waiting. Simulation runs take no lease and never block.
- **Partitioning never changes results.** A test runs the same population with B = 1 and with B = 100 and requires identical `result_sha256` values.
- **Lock ordering.** A transaction only touches rows of its own bucket and takes row locks in subject order, so deadlocks cannot form.
- **Numbering without hot spots.** Pay statement numbers are allocated as ranges per bucket at finalization, not from one shared sequence.
- **Change sets are never blocked by a run.** With `inputs_known_at`, HR edits commit normally. Edits that affect a locked run's period become retro after finalization, and the run screen shows "changes since lock: n".
- **Sizing.** 50,000 subjects make 100 buckets. With 16 workers, each takes about 6 buckets. The target is under 15 minutes for calculation (`02`).
- Bank files are generated only from `approved` runs, under dual control, with control totals.
- **Held employees.** An employee held for a failed pre-run check (`payroll.pay_run_hold`) is left out of the run and paid in an off-cycle run once the problem is fixed; where the organization chose to stop the run instead, the run cannot be approved while a hold is open (`docs/24` §4.2).
- **Going live.** A payroll account's first live run cannot be finalized until its parallel run is accepted (`payroll.parallel_run_periods`, `docs/24` §4.4).

## 10. Acceptance tests (in addition to `tests/payroll/cases.json`)

1. One employee, one day: an hourly employee with 8 approved hours on 3 Nov, an off-cycle run for 3 Nov paid 5 Nov. Earnings are 8 × the rate in force on 3 Nov, deductions follow the November edition, and YTD updates.
2. A raise effective day 6 of a 14-day period: two segments, correct proration, both visible on the statement.
3. Work 20 Dec 2026 to 2 Jan 2027, paid 8 Jan 2027: 2027 edition (stop with `NO_RULE_EDITION` if not loaded), 2027 YTD, 2027 T4; GL lines split between December and January fiscal periods.
4. A fiscal year ending 31 March, with the period from 25 March to 7 April: GL lines carry two fiscal years; budgets show each year's share.
5. A rate correction back-dated three periods: a retro request for three periods, differences per period, paid as non-periodic in the next run.
6. Agreement ratified with `retro_from` 15 months back, crossing a calendar year: prior-year differences are paid and taxed in the current year and shown on the current T4; a T1198 letter is created when rules qualify.
7. Reversal of a finalized off-cycle payment: a negating result is created, YTD restored, and the GL reversed.
8. Simulation of a proposed transfer to Manitoba: the result shows Manitoba tax and the difference from the current net pay, and nothing is stored in YTD.
9. Final pay on termination effective mid-period: partial salary, vacation payout, statutory notice pay from Module 11 rules, and the ROE triggered.
10. A pay group with 27 bi-weekly pay dates: P = 27 for the whole year and the CPP exemption is $129.62.
11. Inputs pinned by system time: lock a run, then commit a raise back-dated into its period → the run's results are unchanged; after finalization, a retro request exists for the raise.
12. Rules pinned by hash: lock a run, then activate a new agreement version covering its period → the run finishes on the pinned version, the pins show the old hash, and retro requests follow finalization. An attempt to edit an active edition's content fails with the trigger error.
13. Partitioning: calculate the same 2,000-person population with B = 1 and B = 100 → identical `result_sha256` for every subject; kill a worker mid-bucket → the bucket is retried with no duplicate results.
14. Subject leases: with a regular run locked for a person, locking an off-cycle run that includes the same person returns `SUBJECT_IN_OPEN_RUN` naming the regular run (creating it in draft works and shows a warning); a simulation for that person still works.
15. Nightly replay: tamper with a stored result line in a test database → the replay job raises a mismatch for that result.
