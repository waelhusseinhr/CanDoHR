#!/usr/bin/env python3
"""
CanDo HRIS - reference evaluator for agreement pay composition (docs/08 §5).

The time engine (docs/09 §1) classifies hours into blocks: for each block it knows which multiplier sources apply
(daily or weekly overtime tier, rest day, second rest day, holiday) and which premiums' conditions are met.
This module decides, exactly and with citations, what those hours pay:

  1. the multiplier of each source, from the agreement;
  2. the combined multiplier when several sources apply (pay_composition.multiplier_conflicts), then the cap;
  3. the statutory floor (never below the employment standards minimum for those hours);
  4. which premiums are paid when several apply (exclusive_groups, premium_stacking);
  5. the regular rate (base + premiums marked in_regular_rate);
  6. how each other premium meets the multiplier (overtime_interaction / holiday_interaction).

It also validates an agreement version before activation: every combination of sources that can occur on the same
hours must have an explicit answer, or the version is rejected with UNRESOLVED_INTERACTION.

The production TypeScript engine must reproduce tests/agreements/stacking_cases.json exactly.

Block:
  {"hours": "2", "base_rate": "30.85",
   "sources": [{"basis": "daily", "after_hours": 7}],      # after_hours picks the tier when a basis has several
   "premiums": ["SHIFT_NIGHT"],
   "statutory_minimum_multiplier": "1.5"}                   # optional; from the ES rule set for these hours
Result:
  {"multiplier": "1.5", "regular_rate": "30.85", "lines": [...], "total": "96.05", "rule_path": [...]}

Money is Decimal; each line is rounded half up to the cent once, with no intermediate rounding.

Usage:
  python3 premium_stacking_reference.py --selftest
"""
from __future__ import annotations

import copy
import itertools
import json
import sys
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES = ROOT / "tests" / "agreements" / "stacking_cases.json"
EXAMPLE = ROOT / "rules" / "agreements" / "example-municipal-agreement.json"

# structural: the overtime source codes the agreement schema defines
SOURCES = ("daily", "weekly", "consecutive_days", "rest_day", "second_rest_day", "holiday")
# structural: the order sources are listed on a pay line and in messages (most specific first); it never decides pay
LINE_ORDER = ["holiday", "second_rest_day", "rest_day", "daily", "consecutive_days", "weekly"]
# structural: money is in cents
CENT = Decimal("0.01")
# structural: arithmetic constant
ONE = Decimal(1)


class RuleError(Exception):
    def __init__(self, code: str, detail: str):
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


def D(x) -> Decimal:
    return Decimal(str(x))


def money(x: Decimal) -> Decimal:
    return x.quantize(CENT, rounding=ROUND_HALF_UP)


def fmt(x: Decimal) -> str:
    """Plain decimal string without exponent or trailing zeros (multipliers, rates)."""
    s = format(x.normalize(), "f")
    return s


def art(obj) -> str | None:
    c = (obj or {}).get("cite")
    return c.get("article") if c else None


# ---------------------------------------------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------------------------------------------
def holiday_multiplier(rules: dict) -> tuple[Decimal | None, str | None]:
    ot = rules.get("overtime", {})
    from_thr = [t for t in ot.get("thresholds", []) if t["basis"] == "holiday"]
    from_hol = rules.get("holidays", {}).get("worked_multiplier")
    if from_thr and from_hol is not None and any(D(t["multiplier"]) != D(from_hol) for t in from_thr):
        raise RuleError("AMBIGUOUS_HOLIDAY_MULTIPLIER",
                        "overtime.thresholds[holiday] and holidays.worked_multiplier disagree")
    if from_thr:
        return D(from_thr[0]["multiplier"]), art(ot)
    if from_hol is not None:
        return D(from_hol), art(rules.get("holidays"))
    return None, None


def defined_sources(rules: dict) -> list[str]:
    bases = {t["basis"] for t in rules.get("overtime", {}).get("thresholds", [])}
    if holiday_multiplier(rules)[0] is not None:
        bases.add("holiday")
    return [s for s in SOURCES if s in bases]


def source_multiplier(rules: dict, src: dict) -> tuple[Decimal, str]:
    basis = src["basis"]
    if basis not in SOURCES:
        raise RuleError("UNKNOWN_SOURCE", basis)
    if basis == "holiday":
        m, cite = holiday_multiplier(rules)
        if m is None:
            raise RuleError("UNKNOWN_SOURCE", "holiday: the agreement defines no holiday multiplier")
        return m, f"holiday ×{fmt(m)}" + (f" (art. {cite})" if cite else "")
    ot = rules.get("overtime", {})
    tiers = [t for t in ot.get("thresholds", []) if t["basis"] == basis]
    if not tiers:
        raise RuleError("UNKNOWN_SOURCE", f"{basis}: no such threshold in the agreement")
    if "after_hours" in src:
        tiers = [t for t in tiers if D(t["after_hours"]) == D(src["after_hours"])]
        if not tiers:
            raise RuleError("UNKNOWN_SOURCE", f"{basis} after {src['after_hours']} h: no such tier")
    elif len(tiers) > 1:
        raise RuleError("AMBIGUOUS_TIER", f"{basis} has {len(tiers)} tiers; the block must give after_hours")
    t = tiers[0]
    cite = art(ot)
    return D(t["multiplier"]), f"overtime {basis} after {fmt(D(t['after_hours']))} h ×{fmt(D(t['multiplier']))}" + (
        f" (art. {cite})" if cite else "")


def premium_by_code(rules: dict, code: str) -> dict:
    for p in rules.get("premiums", []):
        if p["code"] == code:
            return p
    raise RuleError("UNKNOWN_PREMIUM", code)


def hourly_rate(p: dict, base: Decimal) -> Decimal:
    a = p.get("amount", {})
    if "per_hour" in a:
        return D(a["per_hour"])
    if "percent_of_rate" in a:
        return base * D(a["percent_of_rate"]) / Decimal(100)
    raise RuleError("NOT_AN_HOURLY_PREMIUM", f"{p['code']} is paid per shift or by its own formula, not per hour")


def is_hourly(p: dict) -> bool:
    a = p.get("amount", {})
    return "per_hour" in a or "percent_of_rate" in a


# ---------------------------------------------------------------------------------------------------------------
# Combining multipliers
# ---------------------------------------------------------------------------------------------------------------
def resolve(method: str, ms: dict[str, Decimal], order: list[str] | None) -> Decimal:
    if method == "greater_of":
        return max(ms.values())
    if method == "sum_premiums":
        return ONE + sum((m - ONE for m in ms.values()), Decimal(0))
    if method == "multiply":
        r = ONE
        for m in ms.values():
            r *= m
        return r
    if method == "first_in_order":
        if order is None:
            raise RuleError("UNRESOLVED_INTERACTION", "first_in_order needs pay_composition.evaluation_order")
        for s in order:
            if s in ms:
                return ms[s]
        raise RuleError("UNRESOLVED_INTERACTION", f"first_in_order: none of {sorted(ms)} is in evaluation_order")
    raise RuleError("UNKNOWN_RESOLUTION", method)


def find_conflict_rule(comp: dict, bases: set[str]):
    for i, r in enumerate(comp.get("multiplier_conflicts", {}).get("rules", [])):
        if set(r["when"]) == bases:
            return i, r
    return None, None


# ---------------------------------------------------------------------------------------------------------------
# Compose one block
# ---------------------------------------------------------------------------------------------------------------
def compose(block: dict, rules: dict) -> dict:
    comp = rules.get("pay_composition")
    if comp is None and (block.get("sources") or len(block.get("premiums", [])) > 1):
        raise RuleError("UNRESOLVED_INTERACTION", "the agreement version has no pay_composition")
    comp = comp or {}
    order = comp.get("evaluation_order")  # None: first_in_order cannot be used (UNRESOLVED_INTERACTION)
    shown = order or LINE_ORDER
    hours = D(block["hours"])
    base = D(block["base_rate"])
    path: list[dict] = []

    # 1. multipliers per source
    ms: dict[str, Decimal] = {}
    for src in block.get("sources", []):
        if src["basis"] in ms:
            raise RuleError("DUPLICATE_SOURCE", src["basis"])
        m, why = source_multiplier(rules, src)
        ms[src["basis"]] = m
        path.append({"step": "source", "rule": why})

    # 2. combine, then cap
    if not ms:
        mult = ONE
    elif len(ms) == 1:
        mult = next(iter(ms.values()))
    else:
        bases = set(ms)
        i, r = find_conflict_rule(comp, bases)
        mc = comp.get("multiplier_conflicts", {})
        if r is not None:
            mult = resolve(r["resolution"], ms, order)
            cap = r.get("multiplier_cap")
            where = f"pay_composition.multiplier_conflicts.rules[{i}]"
            cite = art(r)
        elif mc.get("default_resolution"):
            mult = resolve(mc["default_resolution"], ms, order)
            cap = mc.get("default_cap")
            where = "pay_composition.multiplier_conflicts.default_resolution"
            cite = (mc.get("default_cite") or {}).get("article")
            r = {"resolution": mc["default_resolution"]}
        else:
            raise RuleError("UNRESOLVED_INTERACTION",
                            f"no rule for {'+'.join(s for s in shown if s in bases)} and no default_resolution")
        path.append({"step": "combine", "rule": f"{where}: {r['resolution']} → ×{fmt(mult)}" +
                     (f" (art. {cite})" if cite else "")})
        if cap is not None and mult > D(cap):
            mult = D(cap)
            path.append({"step": "cap", "rule": f"multiplier_cap ×{fmt(mult)}"})

    # 3. statutory floor
    floor = block.get("statutory_minimum_multiplier")
    if floor is not None and mult < D(floor):
        mult = D(floor)
        path.append({"step": "statute_floor", "rule": f"employment standards minimum ×{fmt(mult)}"})

    # 4. which premiums are paid
    listed = [p["code"] for p in rules.get("premiums", [])]
    prem = []
    for code in block.get("premiums", []):
        p = premium_by_code(rules, code)
        prem.append((code, p, hourly_rate(p, base)))
    prem.sort(key=lambda x: listed.index(x[0]))
    dropped: set[str] = set()
    for g in comp.get("exclusive_groups", []):
        inside = [x for x in prem if x[0] in g["codes"]]
        if len(inside) > 1:
            keep = max(inside, key=lambda x: (x[2], -g["codes"].index(x[0])))
            for x in inside:
                if x[0] != keep[0]:
                    dropped.add(x[0])
                    path.append({"step": "stacking", "rule": f"{x[0]} not paid: exclusive group with {keep[0]}" +
                                 (f" (art. {art(g)})" if art(g) else "")})
    prem = [x for x in prem if x[0] not in dropped]
    if len(prem) > 1 and comp.get("premium_stacking") == "highest_only":
        keep = max(prem, key=lambda x: (x[2], -listed.index(x[0])))
        for x in prem:
            if x[0] != keep[0]:
                path.append({"step": "stacking", "rule": f"{x[0]} not paid: premium_stacking highest_only"})
        prem = [keep]
    elif len(prem) > 1 and "premium_stacking" not in comp:
        raise RuleError("UNRESOLVED_INTERACTION", "several premiums apply and premium_stacking is not set")

    # 5. regular rate
    rr = base
    for code, p, rate in prem:
        if p.get("in_regular_rate"):
            rr += rate
            path.append({"step": "regular_rate", "rule": f"{code} +{fmt(rate)} included in the regular rate" +
                         (f" (art. {art(p)})" if art(p) else "")})

    lines = [{"kind": "time", "sources": [s for s in shown if s in ms], "hours": fmt(hours),
              "rate": fmt(rr), "multiplier": fmt(mult), "amount": str(money(hours * rr * mult))}]

    # 6. other premiums against the multiplier
    governing = "holiday_interaction" if "holiday" in ms else "overtime_interaction"
    for code, p, rate in prem:
        if p.get("in_regular_rate"):
            continue
        if mult == ONE:
            factor, how = ONE, "straight time"
        else:
            how = p.get(governing)
            if how is None:
                raise RuleError("MISSING_INTERACTION", f"{code}.{governing} is not set")
            factor = {"multiplied": mult, "flat": ONE, "excluded": Decimal(0)}[how]
            path.append({"step": "premium", "rule": f"{code}.{governing} = {how}" +
                         (f" (art. {art(p)})" if art(p) else "")})
        if factor == 0:
            continue
        lines.append({"kind": "premium", "code": code, "hours": fmt(hours), "rate": fmt(rate),
                      "multiplier": fmt(factor), "amount": str(money(hours * rate * factor))})

    total = sum((D(l["amount"]) for l in lines), Decimal(0))
    return {"multiplier": fmt(mult), "regular_rate": fmt(rr), "lines": lines, "total": str(money(total)),
            "rule_path": path}


# ---------------------------------------------------------------------------------------------------------------
# Validate a version before verification and activation
# ---------------------------------------------------------------------------------------------------------------
def exclusive_pairs(rules: dict) -> set[frozenset]:
    ex = {frozenset({"rest_day", "second_rest_day"})}  # structural: the first and second rest day are different days
    hc = rules.get("pay_composition", {}).get("hours_counting", {})
    if hc.get("daily_overtime_counts_toward_weekly") is False:
        ex.add(frozenset({"daily", "weekly"}))
    return ex


def possible_combinations(rules: dict) -> list[tuple[str, ...]]:
    """Every set of two or more defined sources that can apply to the same hours."""
    srcs = defined_sources(rules)
    ex = exclusive_pairs(rules)
    out = []
    for n in range(2, len(srcs) + 1):
        for combo in itertools.combinations(srcs, n):
            if not any(frozenset(pair) in ex for pair in itertools.combinations(combo, 2)):
                out.append(combo)
    return out


def validate(rules: dict) -> list[dict]:
    problems: list[dict] = []
    try:
        srcs = defined_sources(rules)
    except RuleError as e:
        return [{"code": e.code, "detail": e.detail}]
    comp = rules.get("pay_composition")
    hourly = [p for p in rules.get("premiums", []) if is_hourly(p)]
    if comp is None:
        if srcs or len(hourly) > 1:
            problems.append({"code": "UNRESOLVED_INTERACTION", "detail": "pay_composition is missing"})
        return problems
    for p in hourly:
        for k in ("in_regular_rate", "overtime_interaction", "holiday_interaction"):
            if k not in p:
                problems.append({"code": "MISSING_INTERACTION", "detail": f"{p['code']}.{k}"})
        if p.get("in_regular_rate") and (p.get("overtime_interaction") != "multiplied"
                                         or p.get("holiday_interaction") != "multiplied"):
            problems.append({"code": "INCONSISTENT_INTERACTION",
                             "detail": f"{p['code']} is in the regular rate, so it is always multiplied"})
    codes = {p["code"] for p in rules.get("premiums", [])}
    for g in comp.get("exclusive_groups", []):
        for c in g["codes"]:
            if c not in codes:
                problems.append({"code": "UNKNOWN_PREMIUM", "detail": f"exclusive group names {c}"})
    mc = comp.get("multiplier_conflicts", {})
    seen = set()
    order = comp.get("evaluation_order") or []
    for i, r in enumerate(mc.get("rules", [])):
        key = frozenset(r["when"])
        if key in seen:
            problems.append({"code": "DUPLICATE_CONFLICT_RULE", "detail": f"rules[{i}] {sorted(key)}"})
        seen.add(key)
        for s in r["when"]:
            if s not in srcs:
                problems.append({"code": "UNKNOWN_SOURCE", "detail": f"rules[{i}] names {s}, which this version does not define"})
        if r["resolution"] == "first_in_order" and not all(s in order for s in r["when"]):
            problems.append({"code": "UNRESOLVED_INTERACTION", "detail": f"rules[{i}] first_in_order without an order for all its sources"})
    if mc.get("default_resolution") == "first_in_order" and not all(s in order for s in srcs):
        problems.append({"code": "UNRESOLVED_INTERACTION", "detail": "default first_in_order without an order for every source"})
    if not mc.get("default_resolution"):
        for combo in possible_combinations(rules):
            if frozenset(combo) not in seen:
                problems.append({"code": "UNRESOLVED_INTERACTION", "detail": "+".join(combo)})
    return problems


# ---------------------------------------------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------------------------------------------
def deep_merge(base: dict, over: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in over.items():
        if v is None:
            out.pop(k, None)
        elif isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def case_rules(base_rules: dict, case: dict) -> dict:
    rules = deep_merge(base_rules, case.get("rules_override", {}))
    for code, over in case.get("premium_override", {}).items():
        rules["premiums"] = [deep_merge(p, over) if p["code"] == code else p for p in rules["premiums"]]
    for p in case.get("premium_add", []):
        rules["premiums"] = rules["premiums"] + [p]
    return rules


def selftest() -> int:
    data = json.loads(CASES.read_text())
    example = json.loads(EXAMPLE.read_text())
    base_rules = example["versions"][0]["rules"]
    fails = 0
    for c in data["cases"]:
        rules = case_rules(base_rules, c)
        exp = c["expected"]
        try:
            got = compose(c["block"], rules)
            if "error" in exp:
                ok, msg = False, f"expected {exp['error']}, got total {got['total']}"
            else:
                ok = got["total"] == exp["total"] and got["multiplier"] == exp["multiplier"]
                if "lines" in exp:
                    ok &= [(l.get("code", "time"), l["amount"]) for l in got["lines"]] == [tuple(x) for x in exp["lines"]]  # structural: test harness: the time line has no premium code
                msg = f"total {got['total']} ×{got['multiplier']}"
                if not ok:
                    msg += f" (expected {exp['total']} ×{exp['multiplier']}; lines {[(l.get('code','time'), l['amount']) for l in got['lines']]})"  # structural: test harness message
        except RuleError as e:
            ok = exp.get("error") == e.code
            msg = e.code
        print(("PASS" if ok else "FAIL"), c["id"], "-", msg)
        fails += 0 if ok else 1
    for v in data["validation_cases"]:
        rules = case_rules(base_rules, v)
        got = sorted({(p["code"], p["detail"]) for p in validate(rules)})
        exp = sorted({tuple(x) for x in v["expected_problems"]})
        ok = got == exp
        print(("PASS" if ok else "FAIL"), "validate", v["id"], "-", got if got else "no problems")
        if not ok:
            print("      expected", exp)
        fails += 0 if ok else 1
    print("all passed" if not fails else f"{fails} failed")
    return 1 if fails else 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    print(__doc__)
