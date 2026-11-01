"""CanDo reference for people who hold several positions (docs/20).

Specifies, exactly:
  * splitting a leave or time request across a person's assignments, to the minute, from each assignment's
    shifts or weekly pattern, with unpaid breaks prorated (docs/20 §3);
  * routing each assignment's part to its approvers by the position's approval mode: by coverage (the days and
    hours each manager supervises), all managers, or any manager (docs/20 §2);
  * request, component and part statuses;
  * the overall review rating from position sections weighted by FTE x days held (docs/20 §5);
  * allocating a one-time payment across assignments by earnings share, to the cent (docs/20 §4.3);
  * coordination of benefits when a person is in two plans of the same kind: HR decides (docs/26 §5.2);
  * the benefits outcome when one assignment ends: eligibility on what remains, the tenant's rule, the statutory
    floor and the HR decision when no rule applies (docs/20 §6.2).

The TypeScript port must reproduce tests/assignments/several_positions_cases.json exactly.
Times are local wall-clock times of the assignment's location ("YYYY-MM-DDTHH:MM"); the API converts before calling.
Run:  python3 reference/several_positions_reference.py --selftest
      python3 reference/several_positions_reference.py tests/assignments/several_positions_cases.json
"""
from __future__ import annotations

import datetime as dt
import json
import sys
from decimal import Decimal as D, ROUND_HALF_UP
from fractions import Fraction

ONE_MIN = dt.timedelta(minutes=1)


def _t(s: str) -> dt.datetime:
    return dt.datetime.fromisoformat(s)


def _hm(s: str) -> int:
    h, m = s.split(":")
    return int(h) * 60 + int(m)


def _round_frac(x: Fraction) -> int:
    """Half-up rounding of a non-negative fraction to an integer."""
    return int((x * 2 + 1) // 2)


def _hours(minutes: int) -> str:
    return str((D(minutes) / D(60)).quantize(D("0.01"), rounding=ROUND_HALF_UP))


# ---------------------------------------------------------------------------------------------
# Work intervals of an assignment
# ---------------------------------------------------------------------------------------------
def work_shifts(a: dict, start: dt.datetime, end: dt.datetime) -> list:
    """Shifts of the assignment that could touch [start, end): (shift_start, shift_end, break_minutes, work_day)."""
    sch = a["schedule"]
    act_from = dt.date.fromisoformat(a["active"][0])
    act_to = dt.date.fromisoformat(a["active"][1]) if a["active"][1] else dt.date.max
    out = []
    if sch["kind"] == "shifts":
        for s in sch["shifts"]:
            ss, se = _t(s["start"]), _t(s["end"])
            out.append((ss, se, s["breakMinutes"], ss.date()))
    elif sch["kind"] == "pattern":
        day = start.date() - dt.timedelta(days=1)          # a pattern shift may start the evening before
        while day <= end.date():
            for p in sch["weekly"].get(str(day.isoweekday()), []):
                ss = dt.datetime.combine(day, dt.time()) + dt.timedelta(minutes=_hm(p["from"]))
                se = dt.datetime.combine(day, dt.time()) + dt.timedelta(minutes=_hm(p["to"]))
                if se <= ss:                                  # overnight shift
                    se += dt.timedelta(days=1)
                out.append((ss, se, p["breakMinutes"], day))
            day += dt.timedelta(days=1)
    return [x for x in out if act_from <= x[3] < act_to]


def _in_window(clock: int, windows) -> bool:
    for w in windows:
        a, b = _hm(w[0]), _hm(w[1])
        if a < b and a <= clock < b:
            return True
        if a > b and (clock >= a or clock < b):              # window that wraps midnight
            return True
    return False


def _covers(approver: dict, minute: dt.datetime, work_day: dt.date) -> bool:
    cov = approver.get("coverage")
    if not cov:
        return False
    days = cov.get("daysOfWeek")
    if days is not None and work_day.isoweekday() not in days:
        return False
    windows = cov.get("timeWindows")
    if windows is not None and not _in_window(minute.hour * 60 + minute.minute, windows):
        return False
    return True


# ---------------------------------------------------------------------------------------------
# Splitting a request (docs/20 §3) and routing its parts (docs/20 §2)
# ---------------------------------------------------------------------------------------------
def split_request(request: dict, assignments: list) -> dict:
    start, end = _t(request["start"]), _t(request["end"])
    capability = request["capability"]
    covered = request.get("assignments")  # rule: docs/20 §3 - a request that names no positions covers every active one
    components, skipped = [], []
    for a in assignments:
        if covered is not None and a["id"] not in covered:
            continue
        if a["schedule"]["kind"] == "none":
            skipped.append({"assignment": a["id"], "reason": "NOT_SCHEDULED"})
            continue
        eligible = []
        for ap in a["approvers"]:
            if capability not in ap["capabilities"]:
                continue
            if request.get("person") and ap.get("person") == request["person"]:
                # nobody approves their own request (docs/17 §5.2); the part goes to the approver's own approver
                ap = dict(ap, id=ap["escalateTo"], person=None)
            eligible.append(ap)
        line = next((ap for ap in eligible if ap["kind"] == "line"), None)
        policy = a["policy"]  # the position's approval policy, or the organization's approvals.multi_manager_* settings
        parts_exact: dict = {}
        intervals = []
        for ss, se, brk, wday in work_shifts(a, start, end):
            os_, oe = max(ss, start), min(se, end)
            if os_ >= oe:
                continue
            total = int((se - ss).total_seconds() // 60)
            paid = Fraction(total - brk, total)
            intervals.append({"start": os_.isoformat(timespec="minutes"), "end": oe.isoformat(timespec="minutes"), "workDay": wday.isoformat()})
            m = os_
            while m < oe:
                if policy["mode"] in ("all", "any"):
                    key = (tuple(sorted(ap["id"] for ap in eligible)), policy["mode"])
                else:
                    who = sorted(ap["id"] for ap in eligible if _covers(ap, m, wday))
                    if not who:
                        key = ((line["id"],) if (line and policy["uncovered"] == "line") else ("HR",), "any")
                    elif len(who) == 1:
                        key = (tuple(who), "any")
                    else:
                        key = (tuple(who), policy["overlap"])
                parts_exact[key] = parts_exact.get(key, Fraction(0)) + paid  # structural: a part starts with no minutes
                m += ONE_MIN
        if not parts_exact:
            skipped.append({"assignment": a["id"], "reason": "NO_WORK_IN_RANGE"})
            continue
        exact_total = sum(parts_exact.values())
        total_min = _round_frac(exact_total)
        keys = list(parts_exact)                              # first-seen order
        floors = {k: int(parts_exact[k]) for k in keys}
        rest = total_min - sum(floors.values())
        for k in sorted(keys, key=lambda k: (-(parts_exact[k] - floors[k]), keys.index(k)))[:max(rest, 0)]:
            floors[k] += 1
        parts = [{"approvers": list(k[0]), "rule": k[1], "minutes": floors[k], "hours": _hours(floors[k])} for k in keys]
        components.append({"assignment": a["id"], "planCode": a.get("planCode"), "minutes": total_min,
                           "hours": _hours(total_min), "intervals": intervals, "parts": parts})
    return {"components": components, "skipped": skipped,
            "totalHours": _hours(sum(c["minutes"] for c in components))}


def part_status(part: dict, decisions: list) -> str:
    """decisions: [{"approver": "...", "decision": "approve" | "decline"}] in the order made."""
    mine = [d for d in decisions if d["approver"] in part["approvers"]]
    if part["rule"] == "any":
        return "pending" if not mine else ("approved" if mine[0]["decision"] == "approve" else "declined")
    if any(d["decision"] == "decline" for d in mine):
        return "declined"
    return "approved" if {d["approver"] for d in mine} >= set(part["approvers"]) else "pending"


def roll_up(statuses: list) -> str:
    s = set(statuses)
    if s == {"approved"}:
        return "approved"
    if s == {"declined"}:
        return "declined"
    if "pending" in s:
        return "pending"
    return "partially_approved"


# ---------------------------------------------------------------------------------------------
# Review overall rating (docs/20 §5)
# ---------------------------------------------------------------------------------------------
def overall_rating(sections: list, method: str, step: str, min_days: int, manager_rating=None) -> dict:
    """step and min_days are the review's settings (reviews.overall_rounding_step, reviews.min_section_days)."""
    used = [s for s in sections if s["rated"] and s.get("rating") is not None and s["days"] >= min_days]
    if method == "primary_manager":
        return {"overall": None if manager_rating is None else str(manager_rating), "used": [s["assignment"] for s in used]}
    if method == "none" or not used:
        return {"overall": None, "used": [s["assignment"] for s in used]}
    weights = {s["assignment"]: D(str(s["fte"])) * D(s["days"]) for s in used}
    wsum = sum(weights.values())
    score = sum(weights[s["assignment"]] * D(str(s["rating"])) for s in used) / wsum
    st = D(step)
    overall = (score / st).quantize(D(1), rounding=ROUND_HALF_UP) * st
    return {"overall": str(overall), "score": str(score.quantize(D("0.0001"), rounding=ROUND_HALF_UP)),
            "weightsPct": {k: str((v * 100 / wsum).quantize(D("0.01"), rounding=ROUND_HALF_UP)) for k, v in weights.items()},
            "used": [s["assignment"] for s in used]}


# ---------------------------------------------------------------------------------------------
# One-time payment across assignments (docs/20 §4.3)
# ---------------------------------------------------------------------------------------------
def allocate_one_time(amount: str, earnings: list) -> dict:
    """earnings: [{"assignment": ..., "amount": "1800.00"}] in assignment order; largest remainder to the cent."""
    total = sum(D(e["amount"]) for e in earnings)
    if total == 0:
        raise ValueError("NO_EARNINGS_TO_SHARE")
    cents = int((D(amount) * 100).to_integral_value())
    exact = [(e["assignment"], D(cents) * D(e["amount"]) / total) for e in earnings]
    base = {k: int(v) for k, v in exact}
    rest = cents - sum(base.values())
    order = sorted(range(len(exact)), key=lambda i: (-(exact[i][1] - int(exact[i][1])), i))
    for i in order[:rest]:
        base[exact[i][0]] += 1
    return {k: str((D(v) / 100).quantize(D("0.01"))) for k, v in base.items()}


# ---------------------------------------------------------------------------------------------
# Benefits (docs/20 §6)
# ---------------------------------------------------------------------------------------------
def cob_order(enrolments: list) -> dict:
    """Two plans of one kind cover the person: HR decides which pays first and records why (docs/26 §5.2, owner's
    review of 28 Oct 2026). CanDo never orders them itself; it shows HR the facts and any order a plan contract sets
    (contractRank, 1 first), which HR reads beside the decision."""
    if len(enrolments) < 2:
        return {"decision": "none_needed"}
    contract = [e["planId"] for e in sorted((e for e in enrolments if e.get("contractRank") is not None),
                                            key=lambda e: e["contractRank"])]
    return {"decision": "hr_decides", "contractOrder": contract}


def _last_of_month(d: dt.date) -> dt.date:
    nxt = (d.replace(day=28) + dt.timedelta(days=4)).replace(day=1)
    return nxt - dt.timedelta(days=1)


def _until(rule: dict, end: dt.date, notice_weeks: int, severance_weeks):
    u = rule.get("until", {})
    k = u.get("kind")
    if rule["action"] == "end_on_date":
        return end
    if k == "end_of_month":
        return _last_of_month(end)
    if k == "end_of_next_month":
        return _last_of_month(_last_of_month(end) + dt.timedelta(days=1))
    if k == "days":
        return end + dt.timedelta(days=u["n"])
    if k == "weeks":
        return end + dt.timedelta(weeks=u["n"])
    if k == "end_of_notice":
        return end + dt.timedelta(weeks=notice_weeks)
    if k == "end_of_severance":                              # docs/26 §7.1: never assume a severance period
        if severance_weeks is None:
            raise ValueError("INPUT_REQUIRED: the rule continues coverage to the end of severance; give the weeks of severance")
        return end + dt.timedelta(weeks=int(severance_weeks))
    if k == "date":
        return dt.date.fromisoformat(u["date"])
    raise ValueError(f"unknown until kind {k}")


def _matches(rule: dict, enr: dict, ending: dict) -> bool:
    m = rule.get("match", {})
    checks = [
        ("planKinds", enr["kind"]), ("planIds", enr["planId"]), ("scopes", enr["scope"]),
        ("endReasonCategories", ending["reasonCategory"]), ("jurisdictions", ending["jurisdiction"]),
        ("agreementIds", enr.get("agreementId")), ("employmentTypes", ending.get("employmentType")),
    ]
    for key, val in checks:
        if key in m and val not in m[key]:
            return False
    if "employerInitiated" in m and m["employerInitiated"] != ending["employerInitiated"]:
        return False
    if "employmentContinues" in m and m["employmentContinues"] != bool(ending.get("remaining")):
        return False
    return True


def benefit_outcome(enrolment: dict, ending: dict, rules: list, jurisdiction_rules: dict) -> dict:
    end = dt.date.fromisoformat(ending["endDate"])
    remaining = [r for r in ending.get("remaining", []) if r["benefitEligible"]]
    if enrolment["scope"] == "agreement":
        remaining = [r for r in remaining if r.get("agreementId") == enrolment.get("agreementId")]
    fte_after = sum((D(str(r["fte"])) for r in remaining), D(0))
    eligible_after = fte_after >= D(str(enrolment["minFte"]))
    out = {"planId": enrolment["planId"], "fteAfter": str(fte_after), "eligibleAfter": eligible_after}
    if eligible_after:
        out.update({"outcome": "no_change", "reasons": ["STILL_ELIGIBLE"], "warnings": []})
        return out
    weeks = int(ending["noticeOwedWeeks"])
    floor, jur = None, None
    warnings = []
    if ending["employerInitiated"] and weeks > 0:          # the benefits-during-notice rule is needed only here
        if ending["jurisdiction"] not in jurisdiction_rules:
            raise ValueError(f"JURISDICTION_RULE_MISSING: no benefits-during-notice rule for {ending['jurisdiction']}")
        jur = jurisdiction_rules[ending["jurisdiction"]]
        if jur["rule"] == "continue_required":
            floor = end + dt.timedelta(weeks=weeks)
        elif jur["rule"] == "verify_at_load":
            warnings.append("RULE_NOT_VERIFIED")
    rule = next((r for r in sorted(rules, key=lambda r: (r["priority"], r["id"])) if _matches(r, enrolment, ending)), None)
    reasons = []
    if rule is None or rule["action"] == "hr_decides":
        out.update({"outcome": "hr_decides", "ruleId": None if rule is None else rule["id"],
                    "floorUntil": None if floor is None else floor.isoformat(),
                    "reasons": ["NO_MATCHING_RULE" if rule is None else "RULE_REQUIRES_HR"], "warnings": warnings})
        return out
    until = _until(rule, end, weeks, ending.get("severanceWeeks"))
    reasons.append(f"RULE:{rule['id']}")
    if floor is not None and floor > until:
        until = floor
        reasons.append("STATUTORY_FLOOR")
    if jur is not None and jur["rule"] == "not_explicit" and until < end + dt.timedelta(weeks=weeks):
        warnings.append("COMMON_LAW_REVIEW")
    out.update({"outcome": "end_on_date" if until == end else "continue_until", "coverageUntil": until.isoformat(),
                "floorUntil": None if floor is None else floor.isoformat(), "ruleId": rule["id"],
                "offerConversion": bool(rule["offerConversion"]), "reasons": reasons, "warnings": warnings})
    return out


# ---------------------------------------------------------------------------------------------
# Case runner
# ---------------------------------------------------------------------------------------------
def run_case(case: dict) -> dict:
    k, i = case["kind"], case["input"]
    try:
        if k == "split":
            return split_request(i["request"], i["assignments"])
        if k == "status":
            parts = {p["id"]: part_status(p, i["decisions"]) for p in i["parts"]}
            by_comp = {}
            for p in i["parts"]:
                by_comp.setdefault(p["component"], []).append(parts[p["id"]])
            return {"parts": parts, "components": {c: roll_up(v) for c, v in by_comp.items()}, "request": roll_up(list(parts.values()))}
        if k == "rating":
            return overall_rating(i["sections"], i["method"], i["step"], i["minDays"], i.get("managerRating"))
        if k == "allocate":
            return {"allocation": allocate_one_time(i["amount"], i["earnings"])}
        if k == "cob":
            return cob_order(i["enrolments"])
        if k == "benefits":
            return benefit_outcome(i["enrolment"], i["ending"], i["rules"], i["jurisdictionRules"])
    except ValueError as e:
        return {"error": str(e).split(":")[0]}
    raise ValueError(f"unknown case kind {k}")


def _subset(expected, actual, path="") -> list:
    errs = []
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return [f"{path}: expected object, got {actual!r}"]
        for key, val in expected.items():
            errs += _subset(val, actual.get(key), f"{path}.{key}")
    elif isinstance(expected, list):
        if not isinstance(actual, list) or len(actual) != len(expected):
            return [f"{path}: expected list of {len(expected)}, got {actual!r}"]
        for n, (e, a) in enumerate(zip(expected, actual)):
            errs += _subset(e, a, f"{path}[{n}]")
    elif expected != actual:
        errs.append(f"{path}: expected {expected!r}, got {actual!r}")
    return errs


def run_cases(path: str) -> int:
    cases = json.load(open(path, encoding="utf-8"))["cases"]
    failed = 0
    for c in cases:
        errs = _subset(c["expected"], json.loads(json.dumps(run_case(c))))
        failed += bool(errs)
        print(f"{'ok' if not errs else 'FAIL':4} {c['id']}  {c['title']}")
        for e in errs:
            print("      ", e)
    print(f"{len(cases) - failed}/{len(cases)} passed")
    return failed


def selftest() -> None:
    assert _round_frac(Fraction(225, 1)) == 225 and _round_frac(Fraction(5, 2)) == 3
    assert allocate_one_time("100.00", [{"assignment": "A", "amount": "1"}, {"assignment": "B", "amount": "1"},
                                        {"assignment": "C", "amount": "1"}]) == {"A": "33.34", "B": "33.33", "C": "33.33"}
    assert _last_of_month(dt.date(2027, 2, 10)) == dt.date(2027, 2, 28)
    assert part_status({"approvers": ["A", "B"], "rule": "all"}, [{"approver": "A", "decision": "approve"}]) == "pending"
    print("selftest ok")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        selftest()
    elif len(sys.argv) > 1:
        sys.exit(1 if run_cases(sys.argv[1]) else 0)
    else:
        print(__doc__)
