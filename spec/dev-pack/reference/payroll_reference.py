#!/usr/bin/env python3
"""
CanDo HRIS - reference implementation of CRA T4127 Option 1 (2026).

Purpose: a small, readable oracle that the production TypeScript engine must
match to the cent. It is NOT the production engine. It covers one pay period
for one employee in any province or territory except Quebec (Quebec is phase 2):

  * CPP (base + first additional) and CPP2
  * EI (employee and employer)
  * Federal and provincial/territorial income tax, Option 1 (T4127 chapter 4)
  * Bonus / retroactive / other non-periodic payments (bonus method)

All money uses Decimal. Rules come from rules/statutory/ca-YYYY-MM-DD.json and
the edition is chosen by PAY DATE (CRA: deductions follow the date paid).

Usage:
  python3 payroll_reference.py case.json          # one case (object) or list of cases
  python3 payroll_reference.py --selftest         # runs tests/payroll/cases.json

Every input field is documented in INPUT_FIELDS below.
"""
from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from decimal import Decimal, ROUND_HALF_UP, ROUND_DOWN, getcontext
from pathlib import Path

getcontext().prec = 28
D = Decimal
# structural: money is in cents
CENT = D("0.01")
RULES_DIR = Path(__file__).resolve().parent.parent / "rules" / "statutory"

# structural: descriptions of the inputs, shown in errors
INPUT_FIELDS = {
    "province": "Province/territory of employment for tax: AB BC MB NB NL NS NT NU ON PE SK YT (QC is phase 2)",
    "pay_date": "ISO date the money is paid. Selects the rule edition and the tax year.",
    "P": "Pay periods in the year for this pay group (1,4,10,12,13,22,24,26,27,52,53,240)",
    "I": "Periodic gross taxable remuneration this period (excludes non-periodic B)",
    "B": "Non-periodic payment this period: bonus, retro pay increase, vacation pay not taken, banked OT payout",
    "B1": "Non-periodic payments already paid earlier this year (YTD, before this period)",
    "PI": "Pensionable earnings this period. T4127 ch. 6: the period's gross income plus taxable benefits, so I + B when not given; give it when some earnings are not pensionable",
    "IE": "Insurable earnings this period. T4127 ch. 7: I + B when not given; give it when some earnings are not insurable",
    "F": "RPP/RRSP/PRPP deductions from periodic pay this period",
    "F2": "Court-ordered pre-1997 support deducted this period",
    "F3": "RPP/RRSP deducted from the non-periodic payment",
    "F4": "RPP/RRSP deducted from earlier non-periodic payments (YTD)",
    "F5BYTD": "CPP additional contributions deducted from earlier non-periodic payments (YTD)",
    "U1": "Union dues this period",
    "F1": "Annual deductions authorized by CRA (childcare, support)",
    "HD": "Annual northern residents deduction (TD1)",
    "TC": "Federal TD1 claim amount; null = basic personal amount (claim code 1)",
    "TCP": "Provincial TD1 claim amount; null = provincial basic personal amount",
    "K3": "Other federal credits authorized by CRA (annual)",
    "K3P": "Other provincial credits authorized by CRA (annual)",
    "L": "Additional tax requested on TD1 per period",
    "Y_dependants_under_19": "Ontario tax reduction: dependants under 19 (TD1ON)",
    "Y_dependants_disabled": "Ontario tax reduction: dependants with a disability (TD1ON)",
    "PM": "Required. Months in the year CPP applies (12 unless turning 18/70, death, CPT30); the engine works it out from the employee's record",
    "D_cpp_ytd": "CPP (base+first additional) deducted YTD with this employer before this period",
    "D2_cpp2_ytd": "CPP2 deducted YTD before this period",
    "D1_ei_ytd": "EI deducted YTD before this period",
    "PIYTD": "Pensionable earnings YTD before this period",
    "PR": "Required when the bonus method runs: pay periods remaining in the year including this one (bonus method K2)",
    "I_recent": "Required for a run with no periodic pay (I = 0) and a non-periodic payment: the employee's most recent periodic I, used to annualize income in the bonus method (T4127: if I = 0, use the most recent I); 0 when the employee has had no periodic pay",
    "non_taxable_earnings": "Earnings paid this period that are not taxable (e.g. s.87 exempt income); included in net pay, excluded from I",
    "cpp_exempt": "true if CPP does not apply (e.g. s.87 exempt income without election, age)",
    "ei_exempt": "true if EI does not apply (e.g. controlling shareholder)",
    "apply_cpp_exemption": "Required. true for a payment in the regular pay run; false for a separate non-periodic-only payment in a period that already had regular pay",
    "gross_employment_annual": "For K4/K4P (CEA). T4127: the annualized employment income, P*I + B + B1, when not given",
}

# Amount and flag variables that T4127 defines as "the amount this period" or "the employee is exempt": not
# reported means none. Every other input is required (INPUT_REQUIRED) - the reference never assumes a value.


def amount(inp: dict, k: str) -> Decimal:
    return D(str(inp.get(k, 0)))  # rule: T4127 amount variable; not reported means none


def exempt(inp: dict, k: str) -> bool:
    return bool(inp.get(k, False))  # rule: CPP and EI apply until an exemption is recorded


def required(inp: dict, k: str):
    if k not in inp or inp[k] is None:
        raise ValueError(f"INPUT_REQUIRED: {k} ({INPUT_FIELDS[k]})")
    return inp[k]


def money(x: Decimal) -> Decimal:
    return x.quantize(CENT, rounding=ROUND_HALF_UP)


def trunc_cents(x: Decimal) -> Decimal:
    return x.quantize(CENT, rounding=ROUND_DOWN)


def load_rules(pay_date: str) -> dict:
    """Pick the edition whose [effective_from, effective_to] contains the pay date."""
    for f in sorted(RULES_DIR.glob("ca-*.json")):
        r = json.loads(f.read_text())
        if r["effective_from"] <= pay_date <= r["effective_to"]:
            return r
    raise ValueError(f"No statutory rule edition loaded for pay date {pay_date}")


def bracket(brackets, A: Decimal):
    chosen = brackets[0]
    for b in brackets:
        if A >= D(str(b["threshold"])):
            chosen = b
    return D(str(chosen["rate"])), D(str(chosen["constant"]))


def income_tested_bpa(spec: dict, NI: Decimal) -> Decimal:
    mx, mn = D(str(spec["max"])), D(str(spec["min"]))
    s, e = D(str(spec["phase_out_start"])), D(str(spec["phase_out_end"]))
    if NI <= s:
        return mx
    if NI >= e:
        return mn
    return money(mx - (NI - s) * ((mx - mn) / (e - s)))


@dataclass
class Trace:
    lines: list = field(default_factory=list)

    def add(self, label, value):
        self.lines.append((label, str(value)))


def annual_tax(r: dict, prov: str, A: Decimal, P: Decimal, inp: dict, cpp_for_credit: Decimal,
               ei_for_credit: Decimal, gross_emp: Decimal, PM: Decimal, tr: Trace | None, tag: str):
    """Return (T1, T2): annual federal and provincial tax for annual taxable income A."""
    fed = r["federal"]
    HD = amount(inp, "HD")
    NI = A + HD
    lowest = D(str(fed["lowest_rate"]))
    base_ratio = D(str(r["cpp"]["base_rate"])) / D(str(r["cpp"]["rate"]))
    max_base = D(str(r["cpp"]["max_base_contribution_for_credit"])) * PM / D(12)
    max_ei = D(str(r["ei"]["max_employee_premium"]))
    cea = D(str(fed["canada_employment_amount"]))

    # Federal
    R, K = bracket(fed["brackets"], A)
    TC = inp.get("TC")  # rule: CRA TD1 - no federal TD1 on file means claim code 1, the basic personal amount
    TC = income_tested_bpa(fed["basic_personal_amount"], NI) if TC is None else D(str(TC))
    K1 = lowest * TC
    cpp_credit_base = min(cpp_for_credit * base_ratio, max_base)
    ei_credit_base = min(ei_for_credit, max_ei)
    K2 = lowest * cpp_credit_base + lowest * ei_credit_base
    K3 = amount(inp, "K3")
    K4 = min(lowest * gross_emp, lowest * cea)
    T3 = max(D(0), R * A - K - K1 - K2 - K3 - K4)
    T1 = T3  # LCF not modelled in the reference (rare); production supports it.

    # Provincial / territorial
    pr = r["provinces"][prov]
    V, KP = bracket(pr["brackets"], A)
    plow = D(str(pr["lowest_rate"]))
    bpa = pr["basic_personal_amount"]
    TCP = inp.get("TCP")  # rule: CRA TD1 - no provincial TD1 on file means the provincial basic personal amount
    if TCP is None:
        if bpa["type"] == "fixed":
            TCP = D(str(bpa["amount"]))
        elif bpa["type"] == "income_tested":
            TCP = income_tested_bpa(bpa, NI)
        elif bpa["type"] == "same_as_federal":
            TCP = income_tested_bpa(fed["basic_personal_amount"], NI)
        else:
            raise ValueError(f"RULE_SHAPE_UNKNOWN: provinces.{prov}.basic_personal_amount.type {bpa['type']}")
    else:
        TCP = D(str(TCP))
    K1P = plow * TCP
    K2P = plow * cpp_credit_base + plow * ei_credit_base
    K3P = amount(inp, "K3P")
    K4P = D(0)
    if "employment_credit_K4P" in pr:
        k4 = pr["employment_credit_K4P"]
        K4P = min(D(str(k4["rate"])) * gross_emp, D(str(k4["rate"])) * D(str(k4["amount"])))
    K5P = D(0)
    if "supplemental_credit_K5P" in pr:
        s = pr["supplemental_credit_K5P"]
        K5P = max(D(0), (K1P + K2P - D(str(s["threshold"]))) * D(str(s["rate"])))
    T4 = max(D(0), V * A - KP - K1P - K2P - K3P - K4P - K5P)

    V1 = D(0)
    V2 = D(0)
    S = D(0)
    if "surtax_V1" in pr:
        for tier in pr["surtax_V1"]["tiers"]:
            over = D(str(tier["over"]))
            if T4 > over:
                V1 += D(str(tier["rate"])) * (T4 - over)
    if "health_premium_V2" in pr:
        V2 = ontario_health_premium(pr["health_premium_V2"], A)
    if prov == "ON":
        y = D(str(pr["tax_reduction_S"]["per_dependant_Y"]))
        Y = y * amount(inp, "Y_dependants_under_19") + y * amount(inp, "Y_dependants_disabled")
        s2 = D(str(pr["tax_reduction_S"]["basic_amount_S2"]))
        S = max(D(0), min(T4 + V1, D(2) * (s2 + Y) - (T4 + V1)))
    elif prov == "BC":
        red = pr["tax_reduction_S"]
        amt, thr = D(str(red["amount"])), D(str(red["income_threshold"]))
        rate, cap = D(str(red["phase_out_rate"])), D(str(red["income_cap"]))
        if A <= thr:
            S = min(T4, amt)
        elif A <= cap:
            S = min(T4, max(D(0), amt - (A - thr) * rate))
    T2 = max(D(0), T4 + V1 + V2 - S)

    if tr is not None:
        for k, v in [("A", A), ("R", R), ("K", K), ("TC", TC), ("K1", K1), ("K2", K2), ("K4", K4),
                     ("T3", T3), ("T1", T1), ("V", V), ("KP", KP), ("TCP", TCP), ("K1P", K1P),
                     ("K2P", K2P), ("K4P", K4P), ("K5P", K5P), ("T4", T4), ("V1", V1), ("V2", V2),
                     ("S", S), ("T2", T2)]:
            tr.add(f"{tag}.{k}", money(v) if isinstance(v, Decimal) and k not in ("R", "V") else v)
    return T1, T2


def ontario_health_premium(spec: dict, A: Decimal) -> Decimal:
    """provinces.ON.health_premium_V2 of the rule edition: the last band whose 'over' is below A (the first band when
    A is 0 or less); premium = min(cap, base + rate * (A - over))."""
    bands = spec["bands"]
    for prev, nxt in zip(bands, bands[1:]):
        if prev["upto"] is None or D(str(prev["upto"])) != D(str(nxt["over"])):
            raise ValueError("RULE_SHAPE_UNKNOWN: health_premium_V2 bands are not contiguous")
    if bands[-1]["upto"] is not None:
        raise ValueError("RULE_SHAPE_UNKNOWN: the last health_premium_V2 band must be open-ended")
    chosen = bands[0]
    for b in bands:
        if A > D(str(b["over"])):
            chosen = b
    return min(D(str(chosen["cap"])), D(str(chosen["base"])) + D(str(chosen["rate"])) * (A - D(str(chosen["over"]))))


def calculate(inp: dict) -> dict:
    prov = inp["province"]
    if prov == "QC":
        raise NotImplementedError("Quebec payroll is phase 2 (Revenu Québec TP-1015.F).")
    r = load_rules(inp["pay_date"])
    tr = Trace()
    tr.add("edition", r["id"])
    P = D(str(inp["P"]))
    I = amount(inp, "I")
    B = amount(inp, "B")
    B1 = amount(inp, "B1")
    PI = D(str(inp["PI"])) if "PI" in inp else I + B  # rule: T4127 ch. 6 - gross income plus taxable benefits
    IE = D(str(inp["IE"])) if "IE" in inp else I + B  # rule: T4127 ch. 7 - insurable earnings of the period
    F, F2, F3, F4 = (amount(inp, k) for k in ("F", "F2", "F3", "F4"))
    F5BYTD = amount(inp, "F5BYTD")
    U1, F1, HD = (amount(inp, k) for k in ("U1", "F1", "HD"))
    L = amount(inp, "L")
    PM = D(str(required(inp, "PM")))
    Dcpp = amount(inp, "D_cpp_ytd")
    D2 = amount(inp, "D2_cpp2_ytd")
    D1 = amount(inp, "D1_ei_ytd")
    PIYTD = amount(inp, "PIYTD")
    cpp = r["cpp"]
    rate = D(str(cpp["rate"]))

    # ---- CPP (chapter 6) ----
    def cpp_on(pi: Decimal, d_ytd: Decimal, apply_ex: bool) -> Decimal:
        if exempt(inp, "cpp_exempt") or pi <= 0:
            return D(0)
        ex = trunc_cents(D(str(cpp["basic_exemption"])) / P) if apply_ex else D(0)
        room = D(str(cpp["max_employee_contribution"])) * PM / D(12) - d_ytd
        return max(D(0), min(room, money(rate * (pi - ex))))

    apply_ex = bool(required(inp, "apply_cpp_exemption"))
    C = cpp_on(PI, Dcpp, apply_ex)
    C_reg = cpp_on(PI - B, Dcpp, apply_ex) if B > 0 else C
    C_bonus = C - C_reg
    tr.add("CPP.exemption_per_period", trunc_cents(D(str(cpp["basic_exemption"])) / P) if apply_ex else D(0))

    C2 = D(0)
    if not exempt(inp, "cpp_exempt"):
        W = max(PIYTD, D(str(cpp["ympe"])) * PM / D(12))
        room2 = D(str(r["cpp2"]["max_employee_contribution"])) * PM / D(12) - D2
        C2 = max(D(0), min(room2, money(max(D(0), PIYTD + PI - W) * D(str(r["cpp2"]["rate"])))))

    # ---- EI (chapter 7) ----
    def ei_on(ie: Decimal) -> Decimal:
        if exempt(inp, "ei_exempt") or ie <= 0:
            return D(0)
        room = D(str(r["ei"]["max_employee_premium"])) - D1
        return max(D(0), min(room, money(D(str(r["ei"]["rate"])) * ie)))

    EI = ei_on(IE)
    EI_reg = ei_on(IE - B) if B > 0 else EI
    EI_bonus = EI - EI_reg

    # ---- F5 split (chapter 4) ----
    # CRA's worked examples carry F5, F5A and F5B rounded to the cent.
    F5 = money(C * (D(str(cpp["first_additional_rate"])) / rate) + C2)
    F5A = money(F5 * ((PI - B) / PI)) if PI > 0 else D(0)
    F5B = money(F5 * (B / PI)) if PI > 0 else D(0)

    # ---- Regular periodic tax (Steps 1-6) ----
    A_reg = max(D(0), P * (I - F - F2 - F5A - U1) - HD - F1)
    # Bonus-only run: annualize the most recent periodic pay instead of zero (T4127 ch. 4).
    I_recent = D(str(required(inp, "I_recent"))) if I == 0 and B > 0 else D(0)
    A_base = A_reg if I > 0 else max(D(0), P * (I_recent - F - F2 - U1) - HD - F1)
    I_ann = I if I > 0 else I_recent
    # rule: T4127 K4 - annualized employment income unless the employer gives it
    gross_emp = D(str(inp["gross_employment_annual"])) if "gross_employment_annual" in inp else P * I_ann + B + B1
    gross_emp_reg = D(str(inp["gross_employment_annual"])) if "gross_employment_annual" in inp else P * I_ann + B1
    T1, T2 = annual_tax(r, prov, A_reg, P, inp, P * C_reg, P * EI_reg, gross_emp_reg, PM, tr, "regular")
    T_reg = (T1 + T2) / P + L if I > 0 else L

    # ---- Non-periodic payment (bonus method) ----
    T_bonus = D(0)
    if B > 0:
        prior = max(D(0), B1 - F4 - F5BYTD)
        A1 = A_base + max(D(0), B - F3 - F5B) + prior
        A2 = A_base + prior
        if A1 <= D(str(r["non_periodic"]["small_payment_rule"]["threshold"])):
            T_bonus = D(str(r["non_periodic"]["small_payment_rule"]["federal_rate"])) * B
            tr.add("bonus.method", "15% small-payment rule")
        else:
            # T4127 worked example (122nd ed., ch. 4): in the bonus steps the CPP/EI credit uses
            # year-to-date contributions plus the remaining periods (PR, including this one),
            # and Step 1 adds the contributions deducted on the payment itself.
            PR = D(str(required(inp, "PR")))
            cpp_ytd_proj = Dcpp + PR * C_reg
            ei_ytd_proj = D1 + PR * EI_reg
            a1, a2 = annual_tax(r, prov, A1, P, inp, cpp_ytd_proj + C_bonus, ei_ytd_proj + EI_bonus,
                                gross_emp, PM, tr, "bonus_step1")
            b1, b2 = annual_tax(r, prov, A2, P, inp, cpp_ytd_proj, ei_ytd_proj, gross_emp_reg, PM, tr,
                                "bonus_step2")
            T_bonus = max(D(0), (a1 + a2) - (b1 + b2))
            tr.add("bonus.method", "annual tax with payment minus annual tax without")

    tax_total = money(T_reg + T_bonus)
    tax_federal_part = None
    result = {
        "edition": r["id"],
        "tax_year": r["tax_year"],
        "cpp_employee": str(money(C)),
        "cpp2_employee": str(money(C2)),
        "ei_employee": str(money(EI)),
        "income_tax": str(tax_total),
        "income_tax_regular": str(money(T_reg)),
        "federal_tax_regular": str(money(T1 / P)) if I > 0 else "0.00",
        "provincial_tax_regular": str(money(T2 / P)) if I > 0 else "0.00",
        "income_tax_non_periodic": str(money(T_bonus)),
        "cpp_employer": str(money(C)),
        "cpp2_employer": str(money(C2)),
        "ei_employer": str(money(EI * D(str(r["ei"]["employer_multiplier"])))),
        "net_pay": str(money(I + B + amount(inp, "non_taxable_earnings")
                             - F - F2 - F3 - U1 - C - C2 - EI - tax_total)),
        "trace": tr.lines,
    }
    del tax_federal_part
    return result


def check_case(c: dict) -> list:
    """Return a list of failure messages for one test case (empty list = pass)."""
    fails = []
    if c.get("expect_error"):
        try:
            calculate(c["input"])
            fails.append("expected an error, got a result")
        except Exception as e:  # noqa: BLE001
            if c["expect_error"] not in str(e):
                fails.append(f"wrong error: {e}")
        return fails
    got = calculate(c["input"])
    trace = dict(got["trace"])
    for k, v in c.get("expected", {}).items():
        if got.get(k) != v:
            fails.append(f"{k}: got {got.get(k)} expected {v}")
    for k, v in c.get("expected_trace", {}).items():
        if trace.get(k) != v:
            fails.append(f"trace {k}: got {trace.get(k)} expected {v}")
    tol = D(str(c.get("tolerance", "0")))  # structural: a test case matches exactly unless it states a tolerance
    for k, v in c.get("expected_within", {}).items():
        if abs(D(got[k]) - D(v)) > tol:
            fails.append(f"{k}: got {got[k]} expected {v} +/- {tol}")
    return fails


def main(argv):
    if len(argv) > 1 and argv[1] == "--selftest":
        path = Path(__file__).resolve().parent.parent / "tests" / "payroll" / "cases.json"
        cases = json.loads(path.read_text())["cases"]
        failed = 0
        for c in cases:
            fails = check_case(c)
            if fails:
                failed += 1
            print(("PASS " if not fails else "FAIL ") + c["id"] + ("" if not fails else "  " + "; ".join(fails)))
        print(f"{len(cases) - failed}/{len(cases)} passed")
        return 1 if failed else 0
    data = json.loads(Path(argv[1]).read_text())
    cases = data if isinstance(data, list) else [data]
    out = [calculate(c.get("input", c)) for c in cases]
    print(json.dumps(out if isinstance(data, list) else out[0], indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
