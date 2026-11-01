"""CanDo market pricing, pay structure, job evaluation and practice benchmarking reference (docs/19).

The TypeScript implementation in workers/ must give the same results as this file for every case in
tests/compensation/market_pricing_cases.json. Arithmetic is decimal (34 significant digits); nothing uses
binary floating point. Rounding is half-up and happens only where this file rounds.

Run:  python3 reference/market_pricing_reference.py --selftest
      python3 reference/market_pricing_reference.py tests/compensation/market_pricing_cases.json
"""
from __future__ import annotations

import datetime as _dt
import json
import sys
from decimal import Decimal as D, ROUND_HALF_UP, getcontext

getcontext().prec = 34

ZERO, ONE, HUNDRED, TWELVE = D(0), D(1), D(100), D(12)
# structural: the statistics a survey or market definition can name (comp.market_definition.statistic)
STATS = ("mean", "p10", "p25", "p50", "p75", "p90")


def need(d: dict, k: str, what: str):
    """A value the definition, edition or plan must state; missing is an error, never a default."""
    if k not in d or d[k] is None:
        raise ValueError(f"{what}_INCOMPLETE: {k} is not set")
    return d[k]


# structural: money rounds to the cent unless a caller asks for other places
def q(x: D, places: str = "0.01") -> D:
    return x.quantize(D(places), rounding=ROUND_HALF_UP)


def round_to_unit(x: D, unit: D) -> D:
    return (x / unit).quantize(ONE, rounding=ROUND_HALF_UP) * unit


def _date(s) -> _dt.date:
    return s if isinstance(s, _dt.date) else _dt.date.fromisoformat(s)


def _dec(v):
    return None if v is None else D(str(v))


# ---------------------------------------------------------------------------------------------
# Ageing (docs/19 §7.3)
# ---------------------------------------------------------------------------------------------
def months_between(from_date, to_date) -> D:
    """Whole calendar months, plus the difference in day of month as a fraction of 30; 2 decimals."""
    a, b = _date(from_date), _date(to_date)
    whole = (b.year - a.year) * 12 + (b.month - a.month)
    return q(D(whole) + D(b.day - a.day) / D(30), "0.01")  # rule: docs/19 §7.3 - the method counts a part month in 30ths


def ageing_factor(months: D, annual_rate: D, method: str) -> D:
    if method == "none" or annual_rate == ZERO or months == ZERO:
        return ONE
    if method == "simple":
        return ONE + annual_rate * months / TWELVE
    if method == "compound":
        return (ONE + annual_rate) ** (months / TWELVE)
    raise ValueError(f"unknown ageing method {method}")


# ---------------------------------------------------------------------------------------------
# Usability of a published value (docs/19 §7.2)
# ---------------------------------------------------------------------------------------------
def usable(row: dict, stat: str, minimum: dict) -> tuple[bool, str | None]:
    if row is None:
        return False, "NOT_IN_EDITION"
    if row.get(stat) is None:
        return False, "MASKED"
    # structural: a value published without its organization count cannot show that it meets the minimum
    if row.get("n_orgs", 0) < need(minimum, "nOrgs", "DEFINITION"):
        return False, "BELOW_MINIMUM_ORGS"
    min_inc = minimum.get("nIncumbents")                      # optional: no incumbent minimum unless the definition sets one
    if min_inc is not None and (row.get("n_incumbents") or 0) < min_inc:
        return False, "BELOW_MINIMUM_INCUMBENTS"
    return True, None


def _survey_value(source: dict, edition: dict, matches: list[dict], stat: str, target_stat: str, minimum: dict):
    """Pick the first cut in the chain where every matched survey job is usable for the target statistic."""
    rows = edition["rows"]
    key = lambda code, cut: (code, cut, source["weighting"], source["element"])
    index = {(r["job_code"], r["cut"], r["weighting"], r["element"]): r for r in rows}
    reasons = []
    for cut in source["cutChain"]:
        comps, ok = [], True
        for m in matches:
            row = index.get(key(m["code"], cut))
            good, why = usable(row, target_stat, minimum)
            if not good:
                ok = False
                reasons.append({"cut": cut, "code": m["code"], "reason": why})
                break
            comps.append((m, row))
        if not ok:
            continue
        if any(row.get(stat) is None for _, row in comps):
            return None, {"cut": cut, "reason": "STAT_NOT_PUBLISHED", "tried": reasons}
        value = sum((D(str(m["share"])) / HUNDRED) * D(str(row[stat])) for m, row in comps)
        return value, {"cut": cut, "components": [{"code": m["code"], "share": m["share"], "nOrgs": row["n_orgs"],
                                                   "value": str(row[stat])} for m, row in comps], "tried": reasons}
    return None, {"reason": "NO_USABLE_CUT", "tried": reasons}


def _public_value(source: dict, edition: dict, noc: str | None, stat: str):
    if noc is None:
        return None, {"reason": "NO_NOC_CODE"}
    col = need(edition, "statisticColumns", "EDITION").get(stat)   # docs/19 §6.5: which statistic each published column is
    if col is None:
        return None, {"reason": "STAT_NOT_PUBLISHED"}
    index = {(r["noc"], r["geo"]): r for r in edition["rows"]}
    for geo in source["geoChain"]:
        row = index.get((noc, geo))
        if row is None or row.get(col) is None:
            continue
        v = D(str(row[col]))
        if row["basis"] == "hourly":
            v = v * D(str(source["hoursBasis"]))
        return v, {"geo": geo, "basis": row["basis"], "value": str(row[col])}
    return None, {"reason": "NO_USABLE_GEOGRAPHY"}


# ---------------------------------------------------------------------------------------------
# Market price of one job under one market definition (docs/19 §7)
# ---------------------------------------------------------------------------------------------
def price_job(job: dict, definition: dict, editions: dict, as_of) -> dict:
    target_stat = definition["statistic"]
    stats = list(dict.fromkeys(need(definition, "statistics", "DEFINITION") + [target_stat]))
    minimum = need(definition, "minimum", "DEFINITION")
    ageing = need(definition, "ageing", "DEFINITION")
    method = need(ageing, "method", "DEFINITION")
    rate = ZERO if method == "none" else D(str(need(ageing, "annualRate", "DEFINITION")))
    lineage, per_stat = [], {s: [] for s in stats}
    for src in definition["sources"]:
        ed = editions[src["code"]]
        entry = {"source": src["code"], "weight": src["weight"], "used": False}
        if src["kind"] == "survey":
            matches = job.get("matches", {}).get(src["code"])
            if not matches:
                entry["reason"] = "NOT_MATCHED"
                lineage.append(entry)
                continue
            total_share = sum(D(str(m["share"])) for m in matches)
            if total_share != HUNDRED:
                raise ValueError(f"match shares for {job['jobId']} in {src['code']} total {total_share}, not 100")
            base, info = _survey_value(src, ed, matches, target_stat, target_stat, minimum)
        else:
            base, info = _public_value(src, ed, job.get("noc"), target_stat)
        entry.update(info)
        if base is None:
            lineage.append(entry)
            continue
        months = months_between(ed["effectiveDate"], as_of)
        factor = ageing_factor(months, rate, method)
        geo = ONE + D(str(src.get("geoDifferentialPct", 0))) / HUNDRED  # structural: no geographic differential unless the source has one
        entry.update({"used": True, "months": str(months), "ageingFactor": str(q(factor, "0.000001")),
                      "geoFactor": str(geo)})
        for s in stats:
            if src["kind"] == "survey":
                v, _ = _survey_value(src, ed, job["matches"][src["code"]], s, target_stat, minimum) if s != target_stat else (base, None)
            else:
                v, _ = _public_value(src, ed, job.get("noc"), s) if s != target_stat else (base, None)
            if v is not None:
                per_stat[s].append((D(str(src["weight"])), v * factor * geo))
        entry["agedTarget"] = str(q(base * factor * geo))
        lineage.append(entry)
    used = [e for e in lineage if e["used"]]
    result = {"jobId": job["jobId"], "lineage": lineage}
    if len(used) < need(definition, "minSources", "DEFINITION"):
        result["status"] = "insufficient_data"
        return result
    market = {}
    for s in stats:
        vals = per_stat[s]
        if not vals:
            market[s] = None
            continue
        wsum = sum(w for w, _ in vals)
        market[s] = q(sum(w * v for w, v in vals) / wsum)
    adj = ONE + D(str(need(definition, "adjustPct", "DEFINITION"))) / HUNDRED
    result["status"] = "priced"
    result["market"] = {k: (None if v is None else str(v)) for k, v in market.items()}
    result["target"] = str(q(market[target_stat] * adj))
    wsum_used = sum(D(str(e["weight"])) for e in used)
    for e in used:
        e["effectiveWeightPct"] = str(q(D(str(e["weight"])) * HUNDRED / wsum_used))
    return result


# ---------------------------------------------------------------------------------------------
# Market line, grades and ranges (docs/19 §7.6, §7.7)
# ---------------------------------------------------------------------------------------------
def fit_market_line(points: list, values: list, outlier_pct: D) -> dict:
    """Least squares fit of ln(value) = a + b * points over benchmark jobs. outlier_pct is the setting
    market.line_outlier_pct as a fraction (docs/19 §7.6)."""
    if len(points) < 3:  # rule: docs/19 §7.6 - a least-squares line needs at least three jobs
        raise ValueError("a market line needs at least 3 benchmark jobs")
    xs = [D(str(p)) for p in points]
    ys = [D(str(v)).ln() for v in values]
    n = D(len(xs))
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    b = sxy / sxx
    a = my - b * mx
    a, b = q(a, "0.0000000001"), q(b, "0.0000000001")
    ss_res = sum((y - (a + b * x)) ** 2 for x, y in zip(xs, ys))
    ss_tot = sum((y - my) ** 2 for y in ys)
    r2 = ONE - ss_res / ss_tot
    residuals = []
    for x, v in zip(xs, values):
        pred = (a + b * x).exp()
        pct = D(str(v)) / pred - ONE
        residuals.append({"points": int(x), "value": str(v), "predicted": str(q(pred)), "residualPct": str(q(pct * HUNDRED, "0.1")),
                          "outlier": abs(pct) > outlier_pct})
    return {"a": str(a), "b": str(b), "r2": str(q(r2, "0.0001")), "progressionPer100Points": str(q(((b * 100).exp() - ONE) * HUNDRED, "0.01")),
            "residuals": residuals}


def predict(line: dict, points) -> D:
    return (D(line["a"]) + D(line["b"]) * D(str(points))).exp()


def build_grades(line: dict, bands: list, spreads: dict, rounding: D) -> list:
    """Midpoint from the line at each band's middle; minimum and maximum from the spread (requirements/04)."""
    out, prev_mid = [], None
    for band in bands:
        mid_points = (D(band["min"]) + D(band["max"])) / 2
        mid = round_to_unit(predict(line, mid_points), rounding)
        spread = D(str(spreads[band["grade"]])) / HUNDRED
        min_raw = mid / (ONE + spread / 2)
        max_raw = min_raw * (ONE + spread)
        g = {"grade": band["grade"], "pointsMid": str(mid_points), "minimum": str(round_to_unit(min_raw, rounding)),
             "midpoint": str(mid), "maximum": str(round_to_unit(max_raw, rounding)), "spreadPct": str(spreads[band["grade"]])}
        g["progressionPct"] = None if prev_mid is None else str(q((mid / prev_mid - ONE) * HUNDRED, "0.1"))
        out.append(g)
        prev_mid = mid
    for lower, upper in zip(out, out[1:]):
        lo_max, up_min = D(lower["maximum"]), D(upper["minimum"])
        upper["overlapWithLowerPct"] = str(q(max(ZERO, lo_max - up_min) / (D(upper["maximum"]) - up_min) * HUNDRED, "0.1"))
    return out


# ---------------------------------------------------------------------------------------------
# Position in range (requirements/04 Pay administration)
# ---------------------------------------------------------------------------------------------
def pay_metrics(rate, rng: dict, market_rate=None) -> dict:
    rate = D(str(rate))
    mn, mid, mx = D(str(rng["minimum"])), D(str(rng["midpoint"])), D(str(rng["maximum"]))
    pen = (rate - mn) / (mx - mn)
    if rate < mn:
        quart = "below_minimum"
    elif rate > mx:
        quart = "above_maximum"
    else:
        quart = "Q1" if pen < D("0.25") else "Q2" if pen < D("0.5") else "Q3" if pen < D("0.75") else "Q4"
    out = {"compaRatio": str(q(rate / mid, "0.001")), "penetration": str(q(pen, "0.001")), "quartile": quart}
    if market_rate is not None:
        out["marketRatio"] = str(q(rate / D(str(market_rate)), "0.001"))
    return out


def cost_to_minimum(people: list, rng: dict) -> str:
    mn = D(str(rng["minimum"]))
    return str(q(sum(max(ZERO, mn - D(str(p["rate"]))) * D(str(p["fte"])) for p in people)))


def annualize(hourly, hours) -> str:
    return str(q(D(str(hourly)) * D(str(hours))))


# ---------------------------------------------------------------------------------------------
# Job evaluation (docs/19 §5)
# ---------------------------------------------------------------------------------------------
def evaluate(plan: dict, ratings: dict) -> dict:
    factors = {f["code"]: f for f in plan["factors"]}
    missing = sorted(set(factors) - set(ratings))
    if missing:
        raise ValueError(f"EVALUATION_INCOMPLETE: {missing}")
    total, detail = 0, {}
    for code, degree in ratings.items():
        pts = {d["degree"]: d["points"] for d in factors[code]["degrees"]}[degree]
        detail[code] = pts
        total += pts
    grade = next((b["grade"] for b in plan["grade_bands"] if b["min"] <= total <= b["max"]), None)
    return {"points": total, "grade": grade, "byFactor": detail}


def suggest_degrees(plan: dict, evidence: dict) -> dict:
    """Degree ranges suggested by the evidence (competency targets, NOC TEER, career level). Proposals only."""
    out = {}
    for f in plan["factors"]:
        ev = f.get("evidence", {})
        src, sug = ev.get("source"), ev.get("suggest")
        if not sug:
            continue
        if src == "competency_targets":
            levels = [evidence.get("competencyTargets", {}).get(c) for c in ev["competencies"]]
            levels = [l for l in levels if l is not None]
            key = str(max(levels)) if levels else ("none" if "none" in sug else None)
        elif src == "noc_teer":
            key = None if evidence.get("teer") is None else str(evidence["teer"])
        elif src == "career_level":
            key = evidence.get("careerLevel")
        else:
            key = None
        if key is not None and key in sug:
            out[f["code"]] = sug[key]
    return out


# ---------------------------------------------------------------------------------------------
# Practice benchmarking (docs/19 §8)
# ---------------------------------------------------------------------------------------------
def compare_practice(practice: dict, own, market: dict, comparison: dict) -> str:
    rw, vt = practice["richer_when"], practice["value_type"]
    if rw == "none" or vt == "text" or own is None:
        return "not_compared"
    if vt == "boolean":
        common = D(str(market["prevalence_pct"])) >= D(str(need(comparison, "boolean_common_at_pct", "COMPARISON")))
        if bool(own) == common:
            return "at_market"
        return "richer" if bool(own) else "leaner"
    if vt == "enum":
        order = practice["enum_values"]
        o, m = order.index(own), order.index(market["mode"])
        return "at_market" if o == m else ("richer" if o > m else "leaner")
    own_d, med = D(str(own)), D(str(market["p50"]))
    tol = D(str(need(need(comparison, "tolerance", "COMPARISON"), vt, "TOLERANCE")))
    if abs(own_d - med) <= tol * abs(med):
        return "at_market"
    higher = own_d > med
    return "richer" if higher == (rw == "higher") else "leaner"


# ---------------------------------------------------------------------------------------------
# Case runner
# ---------------------------------------------------------------------------------------------
def run_case(case: dict, files: dict) -> dict:
    k, i = case["kind"], case["input"]
    if k == "ageing":
        m = months_between(i["from"], i["to"])
        f = ageing_factor(m, D(str(i["annualRate"])), i["method"])
        return {"months": str(m), "factor": str(q(f, "0.000001")), "aged": str(q(D(str(i["amount"])) * f))}
    if k == "price":
        return price_job(i["job"], i["definition"], i["editions"], i["asOf"])
    if k == "market_line":
        return fit_market_line(i["points"], i["values"], D(str(i["outlierPct"])))
    if k == "structure":
        return {"grades": build_grades(i["line"], i["bands"], i["spreads"], D(str(i["rounding"])))}
    if k == "pay_metrics":
        return {"people": [dict(id=p["id"], **pay_metrics(p["rate"], i["range"], i.get("marketRate"))) for p in i["people"]],
                "costToMinimum": cost_to_minimum(i["people"], i["range"])}
    if k == "annualize":
        return {"annual": annualize(i["hourly"], i["hours"])}
    if k == "job_evaluation":
        plan = files["plan"]
        out = evaluate(plan, i["ratings"])
        if "evidence" in i:
            out["suggestions"] = suggest_degrees(plan, i["evidence"])
        return out
    if k == "practice":
        cat = {p["code"]: p for p in files["practices"]["practices"]}
        comparison = files["practices"]["comparison"]
        return {"results": {c["practice"]: compare_practice(cat[c["practice"]], c["own"], c["market"], comparison) for c in i["comparisons"]}}
    raise ValueError(f"unknown case kind {k}")


def _subset(expected, actual, path="") -> list:
    """Every key in expected must match actual; actual may carry more keys."""
    errs = []
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return [f"{path}: expected object"]
        for key, val in expected.items():
            errs += _subset(val, actual.get(key), f"{path}.{key}")
    elif isinstance(expected, list):
        if not isinstance(actual, list) or len(actual) != len(expected):
            return [f"{path}: expected list of {len(expected)}"]
        for n, (e, a) in enumerate(zip(expected, actual)):
            errs += _subset(e, a, f"{path}[{n}]")
    elif expected != actual:
        errs.append(f"{path}: expected {expected!r}, got {actual!r}")
    return errs


def load_files(root: str) -> dict:
    return {"plan": json.load(open(f"{root}/rules/job-evaluation/sample-point-factor-plan.json", encoding="utf-8")),
            "practices": json.load(open(f"{root}/rules/total-rewards/benefit-practices.json", encoding="utf-8"))}


def run_case_safe(case: dict, files: dict) -> dict:
    try:
        return json.loads(json.dumps(run_case(case, files)))
    except ValueError as e:
        return {"error": str(e).split(":")[0]}


# structural: files are read from the repository root unless another is given
def run_cases(path: str, root: str = ".") -> int:
    files, cases = load_files(root), json.load(open(path, encoding="utf-8"))["cases"]
    failed = 0
    for case in cases:
        errs = _subset(case["expected"], run_case_safe(case, files))
        status = "ok" if not errs else "FAIL"
        failed += bool(errs)
        print(f"{status:4} {case['id']}  {case['title']}")
        for e in errs:
            print("      ", e)
    print(f"{len(cases) - failed}/{len(cases)} passed")
    return failed


def selftest() -> None:
    assert months_between("2025-04-01", "2026-01-01") == D("9.00")
    assert months_between("2025-04-01", "2026-01-15") == D("9.47")
    assert q(ageing_factor(D(9), D("0.03"), "simple"), "0.0001") == D("1.0225")
    assert round_to_unit(D("64949.99"), D(100)) == D(64900) and round_to_unit(D("64950"), D(100)) == D(65000)
    m = pay_metrics(60000, {"minimum": 50000, "midpoint": 60000, "maximum": 70000})
    assert m == {"compaRatio": "1.000", "penetration": "0.500", "quartile": "Q3"}
    try:                                                      # a definition that leaves out a value is refused
        price_job({"jobId": "X"}, {"statistic": "p50", "sources": []}, {}, "2026-01-01")
        raise AssertionError("an incomplete market definition was priced")
    except ValueError as e:
        assert str(e).startswith("DEFINITION_INCOMPLETE"), e
    print("selftest ok")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        selftest()
    elif len(sys.argv) > 1:
        sys.exit(1 if run_cases(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else ".") else 0)
    else:
        print(__doc__)
