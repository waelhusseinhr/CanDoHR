# Stories · 05 Benefits Administration

Requirements: `requirements/05-benefits.md`. The owner's decisions are in `docs/26-benefits-decisions.md`, which wins where a story differs; its scenarios BEN-020 to BEN-040 (`docs/26` §13) are acceptance tests for these stories.

**BEN-001 — Eligibility from Core HR events.** As a benefits administrator, I want eligibility evaluated automatically when hires, status, FTE or agreement change, so that nobody is missed.
- AC1: Given a plan requiring FTE ≥ 0.6 and 3 months of service, when an employee hired at 0.8 FTE reaches 3 months, then an enrolment task opens with a deadline.
- AC2: Given an FTE change to 0.5, then coverage end is proposed per plan rules and the employee is notified.
- AC3: A plan cannot be saved without its waiting period; variable-hour re-tests are proposed to HR, never applied without HR (`docs/26` §4.1, §4.7).

**BEN-002 — Enrolment with life events.** AC: marriage, birth, adoption and loss of other coverage open a life-event window: the plan's own, or the organization's, chosen at setup (`SETTING_NOT_SET` until then). Changes are effective per plan rules and require documents where configured. Late enrolment follows each plan's rule (`docs/26` §4.2, §4.3).

**BEN-003 — Payroll deductions and taxable benefits.** AC: elections produce per-pay employee deductions (pre-tax or post-tax per plan) and employer costs. Employer-paid life insurance premiums produce a taxable benefit (and in Quebec, employer-paid health premiums, phase 2), using the plan's `taxable_benefit_rule`.

**BEN-004 — Arrears when pay is insufficient.** AC: when net pay cannot cover a premium, an arrears balance is created and recovered per the configured rule. Coverage is not cancelled automatically.

**BEN-005 — Leave continuation.** AC: on a statutory leave, benefits continue per statute and agreement. The employee chooses how to pay their share among the ways the organization offers (prepay, arrears on return, or through payroll), or the employer pays it where the organization does (`LEAVE_CONTRIBUTION_METHOD_NOT_ALLOWED` otherwise). On other unpaid leaves, the organization's rule for the leave type and class applies (`LEAVE_BENEFIT_RULE_MISSING` when there is none) (`docs/26` §6).

**BEN-006 — Carrier files.** AC: eligibility files are generated per carrier specification on a schedule, starting from the generic file. The changes since the last file are validated, and the golden file test passes for the test carrier profile. A person with two plans of one kind is left out with `COB_ORDER_NOT_SET` until HR sets the order (`docs/26` §3.2, §5.2).

**BEN-007 — Pension plans.** As a pension administrator, I want contributions calculated per plan rules (for example different rates below and above the YMPE), so that remittance files are right.
- AC1: Given a plan with 9.0% up to the YMPE and 14.6% above it, then contributions on each pay split correctly using the YTD pensionable earnings.
- AC2: The pension adjustment (T4 box 52) is calculated per plan type.
- AC3: Where membership is mandatory, the employee is enrolled automatically on the eligibility date, told, and HR confirms; files for the BC Municipal Pension Plan, OMERS, HOOPP and LAPP pass their golden files (`docs/26` §9).

**BEN-008 — Spending accounts.** AC: health and wellness spending account balances, with carry-forward and run-out periods, imported from the partner that administers them; no claim details stored. Taxable wellness reimbursements flow to payroll as taxable benefits (`docs/26` §3.1).

**BEN-009 — Decision support.** AC: during enrolment, employees see the per-pay cost of each option and a plain-language comparison in English or French. The AI assistant is not part of this story: it comes with the platform assistant and is off until the organization switches it on (`docs/26` §3.4).

**BEN-041 — Coverage when employment ends.** As a benefits administrator, I want coverage to end as our rule for each class says, so that terminations are consistent and lawful.
- AC1: The organization's rule for the class gives the termination date, the end of the month, or the end of notice or severance; the statutory floor raises an earlier date (cases BEN-011 to BEN-013 in `tests/assignments/several_positions_cases.json`).
- AC2: Outside Ontario, a decision with notice owed waits until HR acknowledges the caution `benefits.common_law_notice` and writes a reason (`docs/26` §7).

**BEN-042 — Carrier invoices.** As a benefits administrator, I want each carrier invoice reconciled to our enrolment by employee and approved through our route, so that we pay only what we owe.
- AC1: An invoice is not reconciled without its list of differences, and not approved without the route's approvals; its preparer cannot approve it (`docs/26` §8.2).
- AC2: Premium adjustments older than the organization's months go to HR (`docs/26` §8.1).

**BEN-043 — Two agreements, two plans.** As HR, I want to decide which agreement governs a person's benefits and which of two plans pays first, with my reason kept, so that no rule guesses for us (`docs/26` §5).
