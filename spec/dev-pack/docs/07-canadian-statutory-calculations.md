# 07 · Canadian statutory calculations

The engine implements CRA T4127 **Option 1** for every jurisdiction except Quebec provincial tax (phase 2). The values are data in `rules/statutory/ca-YYYY-MM-DD.json`, and the formulas below are code. `reference/payroll_reference.py` is a line-by-line readable version. The TypeScript engine must produce identical results on every case in `tests/payroll/cases.json`.

**Sources:** [T4127 123rd edition (July 2026)](https://www.canada.ca/en/revenue-agency/services/forms-publications/payroll/t4127-payroll-deductions-formulas/t4127-jul/t4127-jul-payroll-deductions-formulas.html), [T4127 122nd edition (January 2026)](https://www.canada.ca/en/revenue-agency/services/forms-publications/payroll/t4127-payroll-deductions-formulas/t4127-jan/t4127-jan-payroll-deductions-formulas-computer-programs.html), [T4001 Employers' Guide](https://www.canada.ca/en/revenue-agency/services/forms-publications/publications/t4001/employers-guide-payroll-deductions-remittances.html), [Special payments chart](https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/payroll/payroll-deductions-contributions/special-payments/special-payments-chart.html).

## 1. Inputs per employee per pay

| Symbol | Meaning | Where it comes from |
| --- | --- | --- |
| P | Pay periods in the year | Pay group |
| I | Periodic gross taxable remuneration this pay (excluding B) | Earnings lines flagged `taxable`, not `non_periodic` |
| B, B1 | Non-periodic payment this pay; non-periodic YTD before this pay | Lines flagged `non_periodic` |
| PI, IE | Pensionable and insurable earnings this pay | Line flags `cpp_pensionable`, `ei_insurable` |
| F, F2, F3, F4 | RPP/RRSP/PRPP from periodic pay; pre-1997 support; RPP/RRSP from B; from B1 | Deduction codes |
| U1 | Union dues this pay | Deduction code with `u1` flag |
| F1, HD | Annual CRA-authorized deductions; northern residents deduction | Payroll profile (TD1, CRA letter) |
| TC, TCP | Federal and provincial TD1 claim amounts (`null` = basic personal amount) | Payroll profile (TD1 versions are effective-dated) |
| K3, K3P | Other CRA-authorized credits | Payroll profile |
| L | Additional tax per pay | Payroll profile |
| PM | Months CPP applies this year | Derived from date of birth (18 and 70), CPT30 election, death |
| D, D2, D1, PIYTD | YTD CPP, CPP2, EI, pensionable earnings before this pay | YTD accumulators for the tax year of the pay date |
| PR | Pay periods remaining including this one | Pay calendar |

## 2. CPP and CPP2 (T4127 chapter 6)

```
exemption = truncate_to_cents(3500 / P)                         # not applied to a separate non-periodic-only pay
C  = max(0, min(4230.45 × PM/12 − D, round_cents(0.0595 × (PI − exemption))))
W  = max(PIYTD, 74600 × PM/12)
C2 = max(0, min(416.00 × PM/12 − D2, round_cents(max(0, PIYTD + PI − W) × 0.04)))
Employer CPP = C; employer CPP2 = C2
```

Age rules: start with the first pay dated in the month after the 18th birthday; stop after the last pay dated in the month of the 70th birthday; CPT30 elections take effect the first day of the month after the employer receives the form. Disability pension recipients are exempt. The engine derives PM from these dates.

## 3. EI (T4127 chapter 7)

```
EI = max(0, min(1123.07 − D1, round_cents(0.0163 × IE)))        # Quebec: 1.30%, max 895.70 (phase 2)
Employer EI = round_cents(1.4 × EI)                             # or the account's reduced rate
```

If an employee moves between Quebec and another province with the same employer, the maximum is shared across provinces on the first $68,900 (T4127 example: $30,000 in Ontario at 1.63% plus $38,900 in Quebec at 1.30%).

## 4. Income tax, periodic (T4127 chapter 4, Option 1)

```
F5  = round_cents(C × (0.0100/0.0595) + C2)                     # CPP enhancement deduction
F5A = round_cents(F5 × (PI − B)/PI);   F5B = round_cents(F5 × B/PI)
A   = max(0, P × (I − F − F2 − F5A − U1) − HD − F1)             # annual taxable income

Federal:
  R, K  = bracket(A)                                            # federal brackets
  TC    = TD1 claim, or BPAF(NI = A + HD)                       # 16,452 → 14,829 between 181,440 and 258,482
  K1    = 0.14 × TC
  K2    = 0.14 × min(P × C × 0.0495/0.0595, 3519.45 × PM/12) + 0.14 × min(P × EI, 1123.07)
  K4    = min(0.14 × gross annual employment income, 0.14 × 1501)
  T3    = max(0, R × A − K − K1 − K2 − K3 − K4)
  T1    = max(0, T3 − P × LCF)                                  # LCF: 15% of LSVCC shares, max 750/yr

Provincial / territorial (lowest rate v = province's first bracket rate):
  V, KP = bracket(A)
  K1P   = v × TCP
  K2P   = v × min(P × C × 0.0495/0.0595, 3519.45 × PM/12) + v × min(P × EI, 1123.07)
  K4P   = Yukon only: min(0.064 × gross annual employment income, 0.064 × 1501)
  K5P   = Alberta only: max(0, (K1P + K2P − 4896.00) × 0.25)
  T4    = max(0, V × A − KP − K1P − K2P − K3P − K4P − K5P)
  T2    = max(0, T4 + V1 + V2 − S − P × LCP)

T = round_half_up_cents((T1 + T2) / P + L)
```

### Province-specific Step 5 items

| Jurisdiction | Item | Rule (2026) |
| --- | --- | --- |
| ON | Surtax V1 | 20% of T4 over $5,818 plus 36% of T4 over $7,446 |
| ON | Health premium V2 | Bands on A: $0 to $20k nil; then up to $300, $450, $600, $750, $900 (see rule file). Not reduced by S. |
| ON | Tax reduction S | max(0, min(T4 + V1, 2 × (300 + Y) − (T4 + V1))), Y = $554 per dependant under 19 and per dependant with a disability |
| BC | Tax reduction S | Jan to Jun: $575 reduced by 3.56% of A over $25,570, nil above $41,722. Jul to Dec: $805, nil above $44,952. |
| MB | BPA | $15,780, reduced to nil between $200,000 and $400,000 of NI |
| MB, NB, NS, SK | LCP | Labour-sponsored funds credit (15%/$1,800; 20%/$2,000; 20%/$2,000; 17.5%/$875) |
| YT | BPA | Same as federal BPAF |
| AB | K5P | Supplemental credit as above |
| NS | BPA | Fixed $11,932 in 2026 (income-tested formula removed) |
| BC, NL, PE | July edition | Prorated values for July to December 2026 (rule file notes). Never apply them to pay dates before 1 July. |

### Rounding

- CPP exemption per period: truncate to cents (`$3,500 ÷ 26 = $134.61`, not $134.62).
- C, C2, EI, F5, F5A, F5B: round to the nearest cent.
- BPA formulas: do not round the ratio; round the result to the cent.
- Intermediate tax values (A, K1, K2, T3, T4) are carried unrounded, which reproduces CRA's worked example to the cent.
- T: round half up to the cent. CRA allows rounding to $0.05; CanDo uses cents.

> The worked example in `requirements/03-payroll.md` previously showed the bi-weekly exemption as $134.62. It was corrected in October 2026 to $134.61, because CRA truncates. The resulting CPP of $140.74 is unchanged.

## 5. Non-periodic payments: bonus method (T4127 chapter 4)

```
Step 1 (with the payment):    A1 = A_base + max(0, B − F3 − F5B) + max(0, B1 − F4 − F5BYTD)
Step 2 (without):             A2 = A_base + max(0, B1 − F4 − F5BYTD)
  where A_base = A from §4, or, if this pay has no periodic income, P × (I_recent − F − F2 − U1) − HD − F1

CPP/EI credit in both steps uses year-to-date plus remaining periods:
  Step 2: K2 cpp base = min((D + PR × C_regular) × 0.0495/0.0595, max); EI = min(D1 + PR × EI_regular, max)
  Step 1: same plus the CPP and EI deducted on the payment itself
Tax on payment TB = (T1 + T2)(A1) − (T1 + T2)(A2), floored at 0
If A1 ≤ $5,000: withhold 15% of the payment instead (10% in Quebec), as T4127 prints it
```

The K2 rule in the bonus steps is confirmed by CRA's worked example: Step 1 K2 = $491.63, Step 2 K2 = $468.60, T3 = $4,758.06 and $4,434.52. The reference implementation reproduces every figure (test `CRA-T4127-122-bonus-example`).

Payments that use this method: bonuses, retroactive pay increases, vacation pay when vacation is not taken, banked overtime payouts, and off-cycle payments in a period that already had a regular pay.

## 6. Special cases

| Case | Rule |
| --- | --- |
| Indian Act s.87 | Income situated on a reserve, per the connecting-factors evidence on file, is excluded from I (it is paid as `non_taxable_earnings`). CPP is not deducted on exempt income unless the employer has elected coverage (CPT124). EI is deducted. Reported in T4 other-information codes. |
| Commission employees (TD1X) | T4127 commission formula with I1 (annual remuneration) and E (expenses), per TD1X. Implement after periodic and bonus pass. Test fixtures to be added from PDOC. |
| Non-residents working in Canada | Federal tax plus 48% surtax in place of provincial tax when employed outside Canada or beyond provincial limits (T4127). Treaty-based waivers by CRA letter. |
| Northern residents | HD from TD1 annual deduction; northern travel benefits per T4130. |
| NT and NU payroll tax | 2% of gross remuneration for work performed in the territory, withheld from the employee and remitted to the territorial finance department; not on the T4 (`rules/employer-taxes`). |
| Province of employment | The province of the establishment the employee reports to. A mid-year change splits YTD by province, and slips by province where required. |
| Directors' fees, honoraria | T4 or T4A per CRA treatment flags on the earnings code; CPP and EI per the special payments chart. |
| Death | Payments after death go to the estate with the CRA-prescribed treatment (T4 for amounts earned before death and paid in the year; T4A for other amounts). Implement from T4001 with fixtures. |

## 7. Employer contributions and payroll taxes

From `rules/employer-taxes/ca-2026.json`: Ontario EHT, BC EHT, Manitoba levy, NL HAPSET, Quebec HSF (phase 2). These are computed on the legal entity's annual remuneration by jurisdiction, with associated-employer sharing of exemptions, and accrued each pay. Workers' compensation premiums use the customer's account rates by classification, loaded per account and year.

## 8. Remittances

| Remitter type | Due (CRA) |
| --- | --- |
| Quarterly (eligible small employers) | 15th day of the month after the quarter |
| Regular | 15th day of the month after the month of the pay dates |
| Accelerated threshold 1 | Pays dated 1st to 15th: by the 25th of the same month. 16th to end: by the 10th of the next month. |
| Accelerated threshold 2 | Within 3 working days after the end of each period: 1st to 7th, 8th to 14th, 15th to 21st, 22nd to end |

The remitter type is a setting on each payroll account, effective-dated, because CRA reassigns it based on average monthly withholding. The rule data must be checked against T4001 at build time.

## 9. Year-end

- T4 and T4 Summary, T4A and T4A Summary filed electronically in CRA XML by the last day of February (electronic filing is mandatory for more than 5 slips of a type). Schemas are downloaded from CRA's [XML specifications page](https://www.canada.ca/en/revenue-agency/services/e-services/filing-information-returns-electronically-t4-t5-other-types-returns-overview/xml-specs.html) each year, never hand-written.
- PIER review before filing (`requirements/03`).
- RL-1 and RLZ-1.S: phase 2.

## 10. Quebec (phase 2)

Federal tax for Quebec employees uses the federal formula with the 16.5% abatement and Quebec versions of K2 (QPP 6.30% with base 5.30%, max $4,479.30; QPIP employee 0.43% up to $103,000 insurable, max $442.90; EI 1.30%). Provincial tax follows Revenu Québec TP-1015.F, which is loaded as a separate rule family. Quebec payroll cannot be switched on for a tenant until the software has Revenu Québec authorization for the year.

## 11. Annual maintenance (owner: payroll rules lead)

1. In November and December, when CRA publishes the January edition: create `ca-YYYY-01-01.json`, run `reference/payroll_reference.py --selftest`, add PDOC-verified fixtures for every jurisdiction, and activate it before the first January pay date.
2. Watch for a July edition (as in 2026) and repeat.
3. Load employer tax, minimum wage and employment standards changes as they are announced.
4. Revenu Québec certification by 1 February each year (phase 2).
