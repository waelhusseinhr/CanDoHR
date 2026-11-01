#!/usr/bin/env python3
"""
CanDo HRIS - reference scorer for "find the most similar position" (docs/18 §7).

Given a query (a position, a job, a NOC code, a title, optionally the person who would move) and candidate
positions, it scores each candidate from 0 to 100 and explains the score with reason codes. It never decides:
the result is a ranked list of proposals for a person to review (AGENTS rule 14).

Components (weights, proximity values, strength weights and internal schemes all come from the similarity
profile, which must be complete - the starter profiles are in rules/classifications/schemes.json; components that
cannot be computed for a pair are left out and the remaining weights are renormalized):

  occupation    NOC proximity: depth of the deepest common ancestor in the hierarchy
                (unit group 1.00, minor group 0.75, sub-major group 0.55, major group 0.40, broad category 0.15),
                or 0.60 when one unit group names the other in its exclusions (NOC's own "functionally similar"
                cross-reference), whichever is higher. A candidate coded in another version or scheme is first
                mapped through the correspondence table; a split mapping is the share-weighted average.
  teer          1 - |TEER(query) - TEER(candidate)| / 5
  requirements  weighted Jaccard over requirement match keys; required 1.0, preferred 0.5, asset 0.25
  internal      tenant schemes named in the profile: equal codes score 1, ranked codes 1 - |rank difference| / range
  title         pg_trgm similarity() of the two titles, implemented exactly as PostgreSQL computes it

total = 100 x sum(weight x value) / sum(weight), over the components present with weight > 0,
rounded half up to one decimal. Ties: higher occupation value, then candidate id in natural order.

Filters (applied before scoring): only_available, exclude_self, must_meet_required (the person's credential
keys must include every 'required' key of the candidate).

The production TypeScript implementation must reproduce tests/classifications/similarity_cases.json exactly.

Usage:
  python3 reference/position_similarity_reference.py --selftest
"""
from __future__ import annotations

import json
import re
import sys
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STRUCTURE = ROOT / "rules" / "classifications" / "noc-2021-v1.0-structure.json"
CASES = ROOT / "tests" / "classifications" / "similarity_cases.json"
# structural: the catalogue version extracted into rules/classifications
NOC_2021 = "NOC-2021-1.0"

SCHEMES = ROOT / "rules" / "classifications" / "schemes.json"
# structural: the parts every similarity profile states; the scorer has no values of its own
PROFILE_KEYS = {
    "weights": ("occupation", "teer", "requirements", "internal", "title"),
    "proximity": ("0", "1", "2", "3", "4", "5", "related"),
    "strength_weights": ("required", "preferred", "asset"),
    "filters": ("only_available", "exclude_self"),
}
# structural: reason codes for each depth of the NOC hierarchy
DEPTH_REASON = {5: "SAME_UNIT_GROUP", 4: "SAME_MINOR_GROUP", 3: "SAME_SUB_MAJOR_GROUP", 2: "SAME_MAJOR_GROUP",
                1: "SAME_BROAD_CATEGORY", 0: "DIFFERENT_OCCUPATION"}
# structural: arithmetic constant
ONE = Decimal(1)


def D(x) -> Decimal:
    return x if isinstance(x, Decimal) else Decimal(str(x))


def q4(x: Decimal) -> str:
    return str(x.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))


# ---------------------------------------------------------------------------------------------
# Classification catalogue (any hierarchical scheme; NOC 2021 V1.0 by default)
# ---------------------------------------------------------------------------------------------
class Catalogue:
    def __init__(self, versions: dict[str, dict[str, dict]], mappings: list[dict] | None = None):
        self.versions = versions          # version_id -> code -> {"parent", "depth", "teer", "related"}
        self.mappings = mappings or []    # [{"from_version","from_code","to_version","to_code","share"}]

    @classmethod
    def load(cls, path: Path = STRUCTURE, mappings: list[dict] | None = None) -> "Catalogue":
        data = json.loads(path.read_text(encoding="utf-8"))
        items = {i["code"]: i for i in data["items"]}
        return cls({NOC_2021: items}, mappings)

    def path(self, version: str, code: str) -> list[str]:
        items = self.versions[version]
        if code not in items:
            raise KeyError(f"CODE_UNKNOWN: {code} in {version}")
        out = []
        while code is not None:
            out.append(code)
            code = items[code]["parent"]
        return list(reversed(out))

    def common_depth(self, version: str, a: str, b: str) -> int:
        n = 0
        for x, y in zip(self.path(version, a), self.path(version, b)):
            if x != y:
                break
            n += 1
        return n

    def related(self, version: str, a: str, b: str) -> bool:
        items = self.versions[version]
        return b in items[a].get("related", []) or a in items[b].get("related", [])

    def teer(self, version: str, code: str):
        return self.versions[version][code].get("teer")

    def to_version(self, code: dict, version: str) -> list[tuple[str, Decimal]]:
        """Map {"version", "code"} into `version`. Returns [(code, share)], shares adding to 1."""
        if code["version"] == version:
            return [(code["code"], ONE)]
        rows = [m for m in self.mappings
                if m["from_version"] == code["version"] and m["from_code"] == code["code"] and m["to_version"] == version]
        if not rows:
            return []
        given = [D(m["share"]) for m in rows if m.get("share") is not None]
        if len(given) == len(rows):
            total = sum(given)
            return [(m["to_code"], D(m["share"]) / total) for m in rows]
        return [(m["to_code"], ONE / len(rows)) for m in rows]   # shares not published: equal parts


# ---------------------------------------------------------------------------------------------
# pg_trgm similarity(), as PostgreSQL computes it (lower case, alphanumeric words, "  word " padding)
# ---------------------------------------------------------------------------------------------
def trigrams(s: str) -> set[str]:
    out: set[str] = set()
    for w in re.findall(r"[^\W_]+", s.lower()):
        p = "  " + w + " "
        for i in range(len(p) - 2):
            out.add(p[i:i + 3])
    return out


def trgm_similarity(a: str, b: str) -> Decimal:
    ta, tb = trigrams(a), trigrams(b)
    if not ta or not tb:
        return Decimal(0)
    common = len(ta & tb)
    return D(common) / D(len(ta) + len(tb) - common)


# ---------------------------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------------------------
def occupation(cat: Catalogue, profile: dict, q: dict, c: dict):
    if not q.get("noc") or not c.get("noc"):
        return None, None, []
    version = q["noc"]["version"]
    parts = cat.to_version(c["noc"], version)
    if not parts:
        return None, None, [{"code": "NO_CORRESPONDENCE", "params": {"fromVersion": c["noc"]["version"], "toVersion": version}}]
    prox = profile["proximity"]
    value, teer_value = Decimal(0), Decimal(0)
    reasons, best = [], None
    tq = cat.teer(version, q["noc"]["code"])
    teer_known = tq is not None
    for code, share in parts:
        depth = cat.common_depth(version, q["noc"]["code"], code)
        v = D(prox[str(depth)])
        rel = cat.related(version, q["noc"]["code"], code) and depth < 5
        if rel and D(prox["related"]) > v:
            v = D(prox["related"])
        value += share * v
        tc = cat.teer(version, code)
        if tq is None or tc is None:
            teer_known = False
        else:
            teer_value += share * (ONE - D(abs(tq - tc)) / D(5))
        cand = (v, depth, rel, code, tc)
        if best is None or cand[0] > best[0]:
            best = cand
    v, depth, rel, code, tc = best
    anc = cat.path(version, q["noc"]["code"])[depth - 1] if depth else None
    if depth == 5:
        reasons.append({"code": "SAME_UNIT_GROUP", "params": {"code": code}})
    elif rel and D(prox["related"]) >= D(prox[str(depth)]):
        reasons.append({"code": "NOC_CROSS_REFERENCE", "params": {"from": q["noc"]["code"], "to": code}})
    else:
        reasons.append({"code": DEPTH_REASON[depth], "params": {"code": anc} if anc else {}})
    if c["noc"]["version"] != version:
        reasons.append({"code": "VIA_CORRESPONDENCE", "params": {"fromVersion": c["noc"]["version"], "toVersion": version,
                                                                "parts": [[k, q4(s)] for k, s in parts]}})
    if teer_known:
        reasons.append({"code": "TEER_SAME" if tq == tc and len(parts) == 1 else "TEER_DIFFERENT",
                        "params": {"query": tq, "candidate": tc}})
    return value, (teer_value if teer_known else None), reasons


def requirements(profile: dict, q: dict, c: dict):
    rq, rc = q.get("requirements", []), c.get("requirements", [])
    if not rq and not rc:
        return None, []
    sw = {k: D(v) for k, v in profile["strength_weights"].items()}
    wq: dict[str, Decimal] = {}
    wc: dict[str, Decimal] = {}
    for r in rq:
        wq[r["key"]] = max(wq.get(r["key"], Decimal(0)), sw[r["strength"]])  # structural: a key the query does not hold weighs nothing
    for r in rc:
        wc[r["key"]] = max(wc.get(r["key"], Decimal(0)), sw[r["strength"]])  # structural: a key the candidate does not hold weighs nothing
    keys = set(wq) | set(wc)
    num = sum(min(wq.get(k, Decimal(0)), wc.get(k, Decimal(0))) for k in keys)  # structural: a key one side lacks weighs nothing
    den = sum(max(wq.get(k, Decimal(0)), wc.get(k, Decimal(0))) for k in keys)  # structural: a key one side lacks weighs nothing
    shared = sorted(set(wq) & set(wc))
    return (num / den if den else Decimal(0)), [{"code": "REQUIREMENTS_SHARED", "params": {"shared": len(shared), "total": len(keys), "keys": shared}}]


def internal(profile: dict, q: dict, c: dict):
    total_w, acc, reasons = Decimal(0), Decimal(0), []
    for s in profile["internal_schemes"]:
        a, b = q.get("codes", {}).get(s["scheme"]), c.get("codes", {}).get(s["scheme"])
        if a is None or b is None:
            continue
        w = D(s["weight"])
        if s["kind"] == "equal":
            v = ONE if a["code"] == b["code"] else Decimal(0)
        else:  # rank
            rng = D(s["range"])
            v = ONE - min(D(abs(a["rank"] - b["rank"])), rng) / rng
        total_w += w
        acc += w * v
        reasons.append({"code": "INTERNAL_MATCH" if v == ONE else "INTERNAL_DIFFERENT",
                        "params": {"scheme": s["scheme"], "query": a["code"], "candidate": b["code"]}})
    if total_w == 0:
        return None, []
    return acc / total_w, reasons


# ---------------------------------------------------------------------------------------------
# Scoring and ranking
# ---------------------------------------------------------------------------------------------
def check_profile(p: dict | None) -> dict:
    """The profile in force (core.similarity_profile). A missing part is an error, never filled in."""
    if p is None:
        raise ValueError("PROFILE_REQUIRED: the scorer needs the similarity profile in force")
    missing = [k for k in ("internal_schemes", "must_meet_required") if k not in p]
    missing += [f"{k}.{x}" for k, xs in PROFILE_KEYS.items() for x in xs if x not in p.get(k, {})]
    missing += [f"internal_schemes[{i}].{x}" for i, sch in enumerate(p.get("internal_schemes", []))
                for x in ("scheme", "kind", "weight") + (("range",) if sch.get("kind") == "rank" else ()) if x not in sch]
    if missing:
        raise ValueError(f"PROFILE_INCOMPLETE: {p.get('code')} lacks {', '.join(missing)}")
    return p


def starter_profile(code: str) -> dict:
    """A starter profile from rules/classifications/schemes.json (what a new tenant's core.similarity_profile holds)."""
    for pr in json.loads(SCHEMES.read_text(encoding="utf-8"))["similarity_profiles"]:
        if pr["code"] == code:
            return pr
    raise ValueError(f"PROFILE_UNKNOWN: {code}")


def score(cat: Catalogue, q: dict, c: dict, profile: dict) -> dict:
    p = check_profile(profile)
    w = {k: D(v) for k, v in p["weights"].items()}
    comps: dict[str, Decimal] = {}
    reasons: list[dict] = []
    occ, teer, r = occupation(cat, p, q, c)
    reasons += r
    if occ is not None:
        comps["occupation"] = occ
    if teer is not None:
        comps["teer"] = teer
    req, r = requirements(p, q, c)
    if req is not None:
        comps["requirements"] = req
        reasons += r
    itn, r = internal(p, q, c)
    if itn is not None:
        comps["internal"] = itn
        reasons += r
    if w["title"] > 0 and q.get("title") and c.get("title"):
        comps["title"] = trgm_similarity(q["title"], c["title"])
        reasons.append({"code": "TITLE_SIMILAR", "params": {"value": q4(comps["title"])}})
    used = {k: v for k, v in comps.items() if w[k] > 0}
    den = sum(w[k] for k in used)
    total = None
    if den > 0:
        total = (D(100) * sum(w[k] * v for k, v in used.items()) / den).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
    return {"id": c["id"], "total": None if total is None else str(total),
            "components": {k: q4(v) for k, v in sorted(comps.items())}, "reasons": reasons}


def natural_key(s: str):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


def rank(cat: Catalogue, q: dict, candidates: list[dict], profile: dict) -> dict:
    p = check_profile(profile)
    f = p["filters"]
    results, excluded = [], []
    for c in candidates:
        if f["exclude_self"] and c["id"] == q.get("id"):
            continue
        if f["only_available"] and not c["available"]:
            excluded.append({"id": c["id"], "reason": "NOT_AVAILABLE"})
            continue
        if p["must_meet_required"] and q.get("person") is not None:
            have = set(q["person"].get("credential_keys", []))
            missing = sorted(r["key"] for r in c.get("requirements", []) if r["strength"] == "required" and r["key"] not in have)
            if missing:
                excluded.append({"id": c["id"], "reason": "MISSING_REQUIRED", "keys": missing})
                continue
        s = score(cat, q, c, p)
        if s["total"] is None:
            excluded.append({"id": c["id"], "reason": "NOTHING_TO_COMPARE"})
            continue
        results.append(s)
    results.sort(key=lambda s: (-D(s["total"]), -D(s["components"].get("occupation", "0")), natural_key(s["id"])))  # structural: no occupation value sorts last among ties
    return {"ranked": results, "excluded": excluded}


# ---------------------------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------------------------
def run_cases(path: Path = CASES) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    failures = 0
    for case in data["cases"]:
        cat = Catalogue.load(STRUCTURE, case.get("mappings"))
        if case["kind"] == "rank":
            got = rank(cat, case["query"], case["candidates"], case["profile"])
            exp = case["expect"]
            ok = [s["id"] for s in got["ranked"]] == [e["id"] for e in exp["ranked"]]
            for g, e in zip(got["ranked"], exp["ranked"]):
                ok &= g["total"] == e["total"] and g["components"] == e["components"]
                if "reason_codes" in e:
                    ok &= [r["code"] for r in g["reasons"]] == e["reason_codes"]
            ok &= [x["id"] for x in got["excluded"]] == [x["id"] for x in exp.get("excluded", [])]
            for g, e in zip(got["excluded"], exp.get("excluded", [])):
                ok &= g["reason"] == e["reason"]
        elif case["kind"] == "trgm":
            got = q4(trgm_similarity(case["a"], case["b"]))
            ok = got == case["expect"]
        elif case["kind"] == "common_depth":
            got = cat.common_depth(NOC_2021, case["a"], case["b"])
            ok = got == case["expect"]
        else:
            raise ValueError(case["kind"])
        print(("PASS " if ok else "FAIL ") + case["id"] + ": " + case["title"])
        if not ok:
            failures += 1
            print("  got:", json.dumps(got, indent=1)[:3000])
    return failures


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        cat = Catalogue.load()
        n = {lv: sum(1 for i in cat.versions[NOC_2021].values() if i["level"] == lv)
             for lv in ("broad_category", "major_group", "sub_major_group", "minor_group", "unit_group")}
        assert n == {"broad_category": 10, "major_group": 45, "sub_major_group": 89, "minor_group": 162, "unit_group": 516}, n
        for code, it in cat.versions[NOC_2021].items():          # the 2nd digit of every code is its TEER
            if len(code) >= 2:
                assert it["teer"] == int(code[1]), code
        assert cat.common_depth(NOC_2021, "42201", "42202") == 4
        assert cat.related(NOC_2021, "42201", "41300")
        for pr in json.loads(SCHEMES.read_text(encoding="utf-8"))["similarity_profiles"]:
            check_profile(pr)                                     # every starter profile is complete
        try:
            check_profile({"code": "partial", "weights": starter_profile("default")["weights"]})
            raise AssertionError("an incomplete profile was accepted")
        except ValueError as e:
            assert str(e).startswith("PROFILE_INCOMPLETE"), e
        failures = run_cases()
        print("ALL PASS" if failures == 0 else f"{failures} FAILED")
        return 1 if failures else 0
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
