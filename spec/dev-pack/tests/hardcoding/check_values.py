#!/usr/bin/env python3
"""
CanDo HRIS - hard-coding and fallback check (AGENTS rules 43 and 44, docs/22).

Fails when a business value, a fixed list, a default or a fallback appears anywhere that the register
rules/register/values-and-fallbacks.json does not account for. It never decides whether a value is right: it makes
every value visible, classified and owned, so a pull request cannot add one silently.

  Code (reference/, workers/, apps/, packages/):
    - Python: .get(key, <literal>), parameter defaults and module constants with literal values
    - TypeScript/JavaScript: `?? <literal>`, `|| <literal>` and parameter defaults with literal values
    Each needs a marker on the same line or the line above:
      # rule: <rules file, statute or spec section>    the value is the law's or the method's own definition
      # structural: <why>                             it carries no business meaning (shape, display, absence)
      # fallback: FB-NNN                              a registered fallback (docs/22 §5)
    (// for TypeScript and JavaScript.) A marker naming an unknown FB id fails.

  Database (with --db or CANDO_DB_URL; run after every migration, as the smoke tests are):
    - every fixed value list (CHECK col IN (...)) is in the register with its exact values and a class;
    - every column DEFAULT is in the register with its exact expression, or is technical (now(), ids, empty);
    - every column whose default comes from a setting has no table DEFAULT, and its setting exists;
    - every function parameter default is in the register;
    - every setting is described in a decisions document (docs/21 onward), and every pending setting is listed in docs/16;
    - nothing in the register is missing from the database (no stale entries).

  API contracts (api/*.yaml):
    - every `default:` is in the register (a page size, a format, a display choice); a business value is a setting
      ("When not given, the organization's setting ...") or a required field, never a literal default.

  Register and docs:
    - every fallback has an id, a status (decided | spec | proposed | pending) and appears in docs/22.

Usage:
  python3 tests/hardcoding/check_values.py                        # code and register only
  python3 tests/hardcoding/check_values.py --db "$CANDO_DB_URL"   # also the database catalogue
  python3 tests/hardcoding/check_values.py --db ... --write-db-inventory out.json   # list what is there, to classify
"""
from __future__ import annotations

import ast
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTER = ROOT / "rules" / "register" / "values-and-fallbacks.json"
DOC22 = ROOT / "docs" / "22-values-and-fallbacks.md"
DOC21 = ROOT / "docs" / "21-core-hr-decisions.md"
DECISION_DOCS = sorted(d for d in (ROOT / "docs").glob("[0-9][0-9]-*.md") if int(d.name[:2]) >= 21)
DOC16 = ROOT / "docs" / "16-open-questions.md"
CODE_DIRS = ["reference", "workers", "apps", "packages"]
MARKER = re.compile(r"(#|//)\s*(rule|structural|fallback):\s*(\S.*)")
FB_ID = re.compile(r"FB-\d{3}")
TECHNICAL_DEFAULT = re.compile(
    r"^(now\(\)|CURRENT_DATE|CURRENT_TIMESTAMP|gen_random_uuid\(\)|nextval\(.*\)|tstzrange\(now\(\), NULL::timestamp with time zone\)"
    r"|'\{\}'::jsonb|'\[\]'::jsonb|'\{\}'::[a-z_]+\[\]|ARRAY\[\]::[a-z_]+\[\])$")

problems: list[str] = []


def fail(msg: str) -> None:
    problems.append(msg)


# ---------------------------------------------------------------------------------------------------------------
# Register
# ---------------------------------------------------------------------------------------------------------------
def load_register() -> dict:
    reg = json.loads(REGISTER.read_text(encoding="utf-8"))
    classes = set(reg["classes"])
    doc22 = DOC22.read_text(encoding="utf-8") if DOC22.exists() else ""
    ids = set()
    for fb in reg["fallbacks"]:
        if not FB_ID.fullmatch(fb["id"]):
            fail(f"register: bad fallback id {fb['id']}")
        if fb["id"] in ids:
            fail(f"register: duplicate fallback {fb['id']}")
        ids.add(fb["id"])
        if fb["status"] not in ("decided", "spec", "proposed", "pending"):
            fail(f"register: {fb['id']} has status {fb['status']}")
        for k in ("when", "then", "source"):
            if not fb.get(k):
                fail(f"register: {fb['id']} has no {k}")
        if fb["status"] == "pending" and not re.search(r"Q\d+", fb.get("source", "")):
            fail(f"register: pending {fb['id']} must name its docs/16 question")
        if fb["id"] not in doc22:
            fail(f"docs/22 does not list {fb['id']}")
    for section in ("fixed_lists", "column_defaults", "function_defaults", "api_defaults"):
        for key, e in reg[section].items():
            if e.get("class") not in classes:
                fail(f"register: {section} {key} has class {e.get('class')!r}")
    reg["_fallback_ids"] = ids
    return reg


# ---------------------------------------------------------------------------------------------------------------
# Code
# ---------------------------------------------------------------------------------------------------------------
def marked(lines: list[str], first: int, last: int, ids: set[str], where: str) -> bool:
    for n in [first - 1] + list(range(first, last + 1)):
        if 1 <= n <= len(lines):
            m = MARKER.search(lines[n - 1])
            if m:
                if m.group(2) == "fallback":
                    fb = FB_ID.search(m.group(3))
                    if not fb or fb.group(0) not in ids:
                        fail(f"{where}:{n}: fallback marker names no registered FB id")
                return True
    return False


def literal(node) -> bool:
    if isinstance(node, ast.Constant):
        return node.value is not None and node.value != ""
    if isinstance(node, ast.UnaryOp) and isinstance(node.operand, ast.Constant):
        return True
    if isinstance(node, (ast.List, ast.Tuple, ast.Set)):
        return len(node.elts) > 0 and all(literal(e) or isinstance(e, (ast.Dict, ast.List)) for e in node.elts)
    if isinstance(node, ast.Dict):
        return len(node.keys) > 0
    if isinstance(node, ast.Call) and getattr(node.func, "id", None) in ("D", "Decimal", "Fraction") and node.args:
        return all(literal(a) for a in node.args)
    return False


def scan_python(path: Path, ids: set[str]) -> None:
    src = path.read_text(encoding="utf-8")
    lines = src.splitlines()
    rel = path.relative_to(ROOT)
    tree = ast.parse(src)
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "get" \
                and len(node.args) == 2 and literal(node.args[1]):
            if not marked(lines, node.lineno, node.end_lineno, ids, str(rel)):
                fail(f"{rel}:{node.lineno}: .get() with a literal default: {ast.get_source_segment(src, node)[:90]}")
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for d in node.args.defaults + [d for d in node.args.kw_defaults if d is not None]:
                if literal(d) and not marked(lines, d.lineno, d.end_lineno, ids, str(rel)):
                    fail(f"{rel}:{d.lineno}: parameter default {ast.get_source_segment(src, d)[:60]} in {node.name}()")
    for node in tree.body:
        if isinstance(node, ast.Assign) and literal(node.value) and all(
                isinstance(t, ast.Name) and t.id.isupper() for t in node.targets):
            if not marked(lines, node.lineno, node.end_lineno, ids, str(rel)):
                fail(f"{rel}:{node.lineno}: module constant {node.targets[0].id} holds literal values")


TS_PATTERNS = [
    (re.compile(r"\?\?\s*(-?\d|'|\"|`|true\b|false\b|\[\s*['\"\d]|\{\s*\w)"), "?? with a literal"),
    (re.compile(r"\|\|\s*(-?\d|'[^']|\"[^\"]|`|true\b|\[\s*['\"\d]|\{\s*\w)"), "|| with a literal"),
    (re.compile(r"\(\s*[^)]*\b\w+\s*(?::\s*[\w<>\[\]| ]+)?=\s*(-?\d|'[^']|\"[^\"]|true\b|false\b)"), "parameter default"),
]


def scan_ts(path: Path, ids: set[str]) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    rel = path.relative_to(ROOT)
    for n, line in enumerate(lines, 1):
        code = line.split("//")[0]
        for pat, what in TS_PATTERNS:
            if pat.search(code) and not marked(lines, n, n, ids, str(rel)):
                fail(f"{rel}:{n}: {what}: {line.strip()[:90]}")


def scan_code(ids: set[str]) -> int:
    n = 0
    for d in CODE_DIRS:
        base = ROOT / d
        if not base.exists():
            continue
        for p in sorted(base.rglob("*")):
            if any(part in ("node_modules", "dist", ".wrangler") for part in p.parts) or ".test." in p.name or ".spec." in p.name:
                continue
            if p.suffix == ".py":
                scan_python(p, ids)
                n += 1
            elif p.suffix in (".ts", ".tsx", ".js", ".mjs") and not p.name.endswith(".d.ts"):
                scan_ts(p, ids)
                n += 1
    return n


API_DEFAULT = re.compile(r"default:\s*([^,}\]]+(?:\][^,}]*)?)")


def api_defaults() -> dict[str, str]:
    """Every `default:` in api/*.yaml, keyed by file, property and value."""
    out = {}
    for path in sorted((ROOT / "api").glob("*.yaml")):
        lines = path.read_text(encoding="utf-8").splitlines()
        for n, line in enumerate(lines):
            m = API_DEFAULT.search(line)
            if not m:
                continue
            named = re.search(r"name:\s*([\w-]+)", line)
            prop = re.match(r"^\s*(?:- )?\{?\s*([\w-]+):", line)
            name = named.group(1) if named else (prop.group(1) if prop and prop.group(1) not in ("schema", "type", "in") else None)
            k = n
            while name is None and k > 0:
                k -= 1
                mm = re.search(r"name:\s*([\w-]+)", lines[k])
                if mm:
                    name = mm.group(1)
            value = m.group(1).strip()
            out[f"{path.name}#{name}={value}"] = f"line {n + 1}"
    return out


def check_api(reg: dict) -> None:
    found = api_defaults()
    for key, where in found.items():
        if key not in reg["api_defaults"]:
            fail(f"api: {key.split('#')[0]} {where} has default {key.split('#')[1]} not in the register (a setting, required, or technical?)")
    for key in reg["api_defaults"]:
        if key not in found:
            fail(f"register: api_defaults {key} is not in the API files any more (remove it)")


# ---------------------------------------------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------------------------------------------
def psql(dsn: str, sql: str) -> list[list[str]]:
    out = subprocess.run(["psql", dsn, "-X", "-q", "-tA", "-F", "\x1f", "-v", "ON_ERROR_STOP=1", "-c", sql],
                         check=True, capture_output=True, text=True).stdout
    return [r.split("\x1f") for r in out.splitlines() if r]


APP_SCHEMAS = "('platform','core','payroll','timeleave','finance','comp','talent','benefits','recruit','offboard','compliance','ref')"


def db_inventory(dsn: str) -> dict:
    lists = {}
    for rel, conname, d in psql(dsn, f"""
        SELECT n.nspname||'.'||c.relname, con.conname, pg_get_constraintdef(con.oid)
        FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE con.contype = 'c' AND n.nspname IN {APP_SCHEMAS} AND pg_get_constraintdef(con.oid) ~ 'ANY \\(ARRAY\\['"""):
        for col, vals in re.findall(r"\(\(?([\w>' -]+?)\)?(?:::text)? = ANY \(ARRAY\[(.*?)\]\)", d):
            col = re.sub(r"[ ']", "", col).replace("->>", ".")
            values = sorted(re.findall(r"'([^']*)'::text", vals))
            key = f"{rel}.{col}"
            if key in lists and lists[key] != values:
                key = f"{rel}.{col}#{conname}"
            lists[key] = values
    defaults = {}
    for rel, col, d in psql(dsn, f"""
        SELECT c.table_schema||'.'||c.table_name, c.column_name, c.column_default
        FROM information_schema.columns c JOIN information_schema.tables t USING (table_schema, table_name)
        WHERE t.table_type = 'BASE TABLE' AND c.table_schema IN {APP_SCHEMAS} AND c.column_default IS NOT NULL"""):
        if not TECHNICAL_DEFAULT.match(d):
            defaults[f"{rel}.{col}"] = d
    funcs = {f"{f}": d for f, d in psql(dsn, f"""
        SELECT n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', pg_get_expr(p.proargdefaults, 0)
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE p.pronargdefaults > 0 AND n.nspname IN {APP_SCHEMAS}""")}
    return {"fixed_lists": lists, "column_defaults": defaults, "function_defaults": funcs}


def check_db(dsn: str, reg: dict) -> None:
    inv = db_inventory(dsn)
    for key, values in inv["fixed_lists"].items():
        e = reg["fixed_lists"].get(key)
        if e is None:
            fail(f"database: fixed list {key} {values} is not in the register (an organization list, a setting, or a classified fixed list?)")
        elif sorted(e["values"]) != values:
            fail(f"database: fixed list {key} is {values}; the register says {sorted(e['values'])}")
    for key, d in inv["column_defaults"].items():
        e = reg["column_defaults"].get(key)
        if e is None:
            fail(f"database: column default {key} = {d} is not in the register (a setting, no default, or a classified default?)")
        elif e["default"] != d:
            fail(f"database: column default {key} is {d}; the register says {e['default']}")
    for key, d in inv["function_defaults"].items():
        e = reg["function_defaults"].get(key)
        if e is None:
            fail(f"database: function {key} has parameter defaults {d} not in the register")
        elif e["default"] != d:
            fail(f"database: function {key} defaults are {d}; the register says {e['default']}")
    for section in ("fixed_lists", "column_defaults", "function_defaults"):
        for key in reg[section]:
            if key not in inv[section]:
                fail(f"register: {section} {key} is not in the database any more (remove it)")
    for rel, col, key in psql(dsn, """
        SELECT d.table_schema||'.'||d.table_name, d.column_name, coalesce(d.setting_key, '')
        FROM platform.column_default d JOIN information_schema.columns c USING (table_schema, table_name, column_name)
        WHERE c.column_default IS NOT NULL"""):
        fail(f"database: {rel}.{col} takes its default from {key or 'the main language'} but still has a table DEFAULT")
    docs = "".join(d.read_text(encoding="utf-8") for d in DECISION_DOCS)
    doc16 = DOC16.read_text(encoding="utf-8") if DOC16.exists() else ""
    for key, status in psql(dsn, "SELECT setting_key, decision_status FROM platform.setting_definition"):
        if f"`{key}`" not in docs:
            fail(f"docs: setting {key} is not described in a decisions document (docs/21 onward)")
        if status == "pending" and f"`{key}`" not in doc16:
            fail(f"docs/16: pending setting {key} has no open question")


def main(argv: list[str]) -> int:
    dsn = None
    if "--db" in argv:
        dsn = argv[argv.index("--db") + 1]
    dsn = dsn or os.environ.get("CANDO_DB_URL")
    if "--write-db-inventory" in argv:
        out = Path(argv[argv.index("--write-db-inventory") + 1])
        out.write_text(json.dumps(db_inventory(dsn), indent=1, ensure_ascii=False))
        print(f"inventory written to {out}")
        return 0
    reg = load_register()
    n = scan_code(reg["_fallback_ids"])
    check_api(reg)
    if dsn:
        check_db(dsn, reg)
    for p in problems:
        print("FAIL", p)
    scope = "code, register" + (" and database" if dsn else " (no database: pass --db to check the catalogue)")
    print(f"{'no unregistered values' if not problems else str(len(problems)) + ' problems'} in {n} code files, {scope}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
