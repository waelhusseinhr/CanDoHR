#!/usr/bin/env python3
"""Apply CanDo migrations with GitHub Actions secrets.

Prints only secret names (set or missing), hosts, migration versions, schema
names, and the Hyperdrive id. Never prints a secret value or a connection URL.
"""

from __future__ import annotations

import json
import os
import re
import socket
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import quote

PROJECT_REF = "lasowjpgxlxijpaeezxe"
DIRECT_HOST = f"db.{PROJECT_REF}.supabase.co"
DATABASE = "postgres"
ACCOUNT_ID = "cd54a788a204d1515eb3b3224cd9594a"
HYPERDRIVE_NAME = "candohr"
ROOT = Path(__file__).resolve().parents[2]

POOLER_HOSTS = (
    "aws-1-us-east-1.pooler.supabase.com",
    "aws-0-us-east-1.pooler.supabase.com",
)
EXTRA_SECRETS: list[str] = []
PASSWORD_MISMATCH = (
    "The saved SUPABASE_DB_PASSWORD does not match the CanDo database password. "
    "Update that GitHub Actions secret to the current database password."
)


def redact(text: str) -> str:
    out = text or ""
    for name in (
        "SUPABASE_DB_PASSWORD",
        "SUPABASE_PUBLISHABLE_KEY",
        "CLOUDFLARE_API_TOKEN",
        "SUPABASE_SERVICE_ROLE_KEY",
    ):
        secret = os.environ.get(name) or ""
        if len(secret) >= 6:
            out = out.replace(secret, "***")
            out = out.replace(quote(secret, safe=""), "***")
    for secret in EXTRA_SECRETS:
        if len(secret) >= 6:
            out = out.replace(secret, "***")
            out = out.replace(quote(secret, safe=""), "***")
    out = re.sub(r"(postgres(?:ql)?://)[^:\s/]+:[^@\s]+@", r"\1***:***@", out, flags=re.I)
    # Do not treat the secret name SUPABASE_DB_PASSWORD as a password assignment.
    out = re.sub(
        r"(?i)(?<![A-Za-z0-9_])(password['\"]?\s*[:=]\s*)\S+",
        r"\1***",
        out,
    )
    return out


def say(text: str) -> None:
    print(redact(text), flush=True)


def fail(sentence: str) -> None:
    say(sentence)
    sys.exit(1)


def secret_report() -> None:
    for name in ("SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_DB_PASSWORD", "CLOUDFLARE_API_TOKEN"):
        say(f"{name}={'present' if os.environ.get(name) else 'missing'}")
    url = os.environ.get("SUPABASE_URL") or ""
    if url and PROJECT_REF not in url:
        fail(
            "SUPABASE_URL is set but does not point at the CanDo project lasowjpgxlxijpaeezxe. "
            "Replace that GitHub Actions secret with the CanDo project URL."
        )


def resolves(host: str) -> bool:
    try:
        socket.getaddrinfo(host, 5432)
        return True
    except socket.gaierror:
        return False


def classify(stderr: str) -> str:
    text = stderr.lower()
    if any(
        marker in text
        for marker in (
            "password authentication failed",
            "authentication failed",
            "28p01",
            "password authentication failed for user",
        )
    ):
        return "auth"
    if any(
        marker in text
        for marker in (
            "network is unreachable",
            "no route to host",
            "could not connect",
            "connection timed out",
            "timeout expired",
            "i/o timeout",
            "connection refused",
            "no address associated",
            "name or service not known",
            "could not translate host",
            "network unreachable",
            "temporary failure in name resolution",
        )
    ):
        return "network"
    return "other"


def password_variants() -> list[tuple[str, str]]:
    raw = os.environ["SUPABASE_DB_PASSWORD"]
    variants = [("saved", raw)]
    trimmed = raw.strip()
    if trimmed and trimmed != raw:
        variants.append(("trimmed", trimmed))
    one_line = "".join(trimmed.splitlines()) if trimmed else ""
    if one_line and all(one_line != value for _label, value in variants):
        variants.append(("single-line", one_line))
    for _label, secret in variants:
        if secret and secret not in EXTRA_SECRETS:
            EXTRA_SECRETS.append(secret)
    return variants


def psql(host: str, user: str, sql: str, password: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update(
        {
            "PGHOST": host,
            "PGPORT": "5432",
            "PGUSER": user,
            "PGDATABASE": DATABASE,
            "PGPASSWORD": password,
            "PGSSLMODE": "require",
            "PGCONNECT_TIMEOUT": "20",
        }
    )
    return subprocess.run(
        ["psql", "-v", "ON_ERROR_STOP=1", "-At", "-c", sql],
        env=env,
        capture_output=True,
        text=True,
    )


def db_url(host: str, user: str, password: str) -> str:
    encoded = quote(password, safe="")
    return f"postgresql://{quote(user, safe='')}:***placeholder***@{host}:5432/{DATABASE}?sslmode=require".replace(
        "***placeholder***", encoded
    )


def candidates() -> list[tuple[str, str, str]]:
    found: list[tuple[str, str, str]] = [("direct", DIRECT_HOST, "postgres")]
    pool_user = f"postgres.{PROJECT_REF}"
    for host in POOLER_HOSTS:
        if resolves(host):
            found.append(("pooler", host, pool_user))
        else:
            say(f"pooler host does not resolve: {host}")
    return found


def connect() -> tuple[str, str, str, str]:
    last_kind = "network"
    variants = password_variants()
    for kind, host, user in candidates():
        for label, password in variants:
            say(f"trying {kind} host={host} user={user} password={label}")
            probe = psql(host, user, "SELECT 1", password)
            if probe.returncode == 0:
                say(f"connected via {kind} host={host} user={user} password={label}")
                if label != "saved":
                    say(
                        "The secret matched only after removing a space or blank line around it. "
                        "Replace SUPABASE_DB_PASSWORD with the password alone."
                    )
                return kind, host, user, password
            last_kind = classify(probe.stderr + probe.stdout)
            detail = redact(probe.stderr.strip() or probe.stdout.strip())
            say(f"{kind} failed class={last_kind} password={label}")
            if detail:
                say(detail[:500])
            if last_kind == "auth" and label == variants[-1][0]:
                fail(PASSWORD_MISMATCH)
    fail(
        "GitHub Actions could not open a connection to the CanDo database "
        f"(last error class: {last_kind}). The password was not reported as wrong. "
        "Check that the Supabase database host accepts connections from GitHub."
    )
    return "", "", "", ""


def run_cli(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT,
        capture_output=True,
        text=True,
        input="y\n",
        timeout=600,
    )


def push_command(url: str, yes: list[str], include_all: bool) -> list[str]:
    command = ["supabase", "db", "push", "--db-url", url]
    if include_all:
        command.append("--include-all")
    command.extend(yes)
    return command


def push_migrations(host: str, user: str, password: str) -> None:
    help_text = run_cli(["supabase", "db", "push", "--help"])
    global_help = run_cli(["supabase", "--help"])
    combined = (help_text.stdout or "") + (help_text.stderr or "") + (global_help.stdout or "")
    if "--db-url" not in combined:
        fail("This Supabase CLI does not offer db push --db-url, so the migrations were not applied.")
    yes = ["--yes"] if re.search(r"--yes\b", combined) else []
    url = db_url(host, user, password)

    def attempt(include_all: bool, dry_run: bool) -> subprocess.CompletedProcess[str]:
        command = push_command(url, yes, include_all)
        if dry_run:
            command.append("--dry-run")
        result = run_cli(command)
        label = "dry-run" if dry_run else "push"
        if include_all:
            label += " include-all"
        say(f"{label} exit {result.returncode}")
        say(redact((result.stdout or "") + (result.stderr or ""))[:4000])
        return result

    dry = attempt(False, True)
    include_all = False
    if dry.returncode != 0 and "include-all" in ((dry.stdout or "") + (dry.stderr or "")).lower():
        dry = attempt(True, True)
        include_all = dry.returncode == 0
    if dry.returncode != 0:
        kind = classify((dry.stderr or "") + (dry.stdout or ""))
        if kind == "auth":
            fail(PASSWORD_MISMATCH)
        fail("supabase db push --dry-run failed, so nothing was applied. See the redacted log above.")

    applied = attempt(include_all, False)
    if applied.returncode != 0 and not include_all:
        blob = ((applied.stdout or "") + (applied.stderr or "")).lower()
        if "include-all" in blob:
            applied = attempt(True, False)
    if applied.returncode != 0:
        kind = classify((applied.stderr or "") + (applied.stdout or ""))
        if kind == "auth":
            fail(PASSWORD_MISMATCH)
        fail("supabase db push failed, so the CanDo database may be unchanged. See the redacted log above.")


def report_schema(host: str, user: str, password: str) -> None:
    versions = psql(
        host,
        user,
        "SELECT version FROM supabase_migrations.schema_migrations ORDER BY version",
        password,
    )
    if versions.returncode != 0:
        say("migration history query failed")
        say(redact(versions.stderr)[:500])
        fail("Migrations were pushed but the history table could not be read.")
    rows = [line for line in versions.stdout.splitlines() if line.strip()]
    say(f"migration_count={len(rows)}")
    for row in rows:
        say(f"migration={row}")
    schemas = psql(
        host,
        user,
        """
        SELECT n.nspname || ' tables=' || count(c.oid)
        FROM pg_namespace n
        LEFT JOIN pg_class c ON c.relnamespace = n.oid AND c.relkind = 'r'
        WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
          AND n.nspname NOT LIKE 'pg_temp%'
          AND n.nspname NOT LIKE 'pg_toast_temp%'
        GROUP BY n.nspname
        ORDER BY n.nspname
        """,
        password,
    )
    if schemas.returncode != 0:
        say("schema query failed")
        say(redact(schemas.stderr)[:500])
        return
    say("schemas:")
    for line in schemas.stdout.splitlines():
        if line.strip():
            say(line.strip())


def cf_api(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    token = os.environ.get("CLOUDFLARE_API_TOKEN") or ""
    url = f"https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}{path}"
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            payload = json.loads(response.read().decode() or "{}")
            return response.status, payload
    except urllib.error.HTTPError as error:
        raw = error.read().decode(errors="replace")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"success": False, "errors": [{"message": raw[:300]}]}
        return error.code, payload


def safe_cf_error(payload: dict) -> str:
    errors = payload.get("errors") if isinstance(payload, dict) else None
    if not isinstance(errors, list) or not errors:
        return "unknown"
    first = errors[0] if isinstance(errors[0], dict) else {"message": str(errors[0])}
    code = first.get("code", "")
    message = redact(str(first.get("message", "")))[:240]
    return f"code={code} message={message}"


def origin_body(host: str, user: str, password: str) -> dict:
    return {
        "scheme": "postgres",
        "database": DATABASE,
        "user": user,
        "password": password,
        "host": host,
        "port": 5432,
    }


def describe_config(item: dict) -> None:
    origin = item.get("origin") if isinstance(item.get("origin"), dict) else {}
    caching = item.get("caching") if isinstance(item.get("caching"), dict) else {}
    say(
        "hyperdrive id={id} name={name} caching_disabled={disabled} host={host} user={user} database={database} port={port}".format(
            id=item.get("id"),
            name=item.get("name"),
            disabled=caching.get("disabled"),
            host=origin.get("host"),
            user=origin.get("user"),
            database=origin.get("database"),
            port=origin.get("port"),
        )
    )


def ensure_hyperdrive(host: str, user: str, password: str) -> None:
    if not os.environ.get("CLOUDFLARE_API_TOKEN"):
        say(
            "CLOUDFLARE_API_TOKEN is missing from this job, so Hyperdrive was not created. "
            "The database password itself worked."
        )
        say("HYPERDRIVE_RESULT=skipped")
        return
    status, payload = cf_api("GET", "/hyperdrive/configs?per_page=100")
    if status >= 400 or not payload.get("success", False):
        say(f"HYPERDRIVE_RESULT=failed list_status={status} {safe_cf_error(payload)}")
        say(
            "Migrations were applied. Hyperdrive was not created because the Cloudflare token "
            "could not list Hyperdrive configs. Add Hyperdrive edit permission to CLOUDFLARE_API_TOKEN."
        )
        return
    configs = payload.get("result") or []
    if isinstance(configs, dict):
        configs = configs.get("configs") or configs.get("items") or []
    match = None
    if isinstance(configs, list):
        for item in configs:
            if isinstance(item, dict) and item.get("name") == HYPERDRIVE_NAME:
                match = item
                break
    if match is None:
        create_status, created = cf_api(
            "POST",
            "/hyperdrive/configs",
            {
                "name": HYPERDRIVE_NAME,
                "origin": origin_body(host, user, password),
                "caching": {"disabled": True},
            },
        )
        if create_status >= 400 or not created.get("success", False):
            say(f"HYPERDRIVE_RESULT=failed create_status={create_status} {safe_cf_error(created)}")
            # Direct host can fail from Cloudflare when the project is IPv6-only.
            # Session pooler is the fallback, still with query caching off.
            if host == DIRECT_HOST:
                for pool_host in POOLER_HOSTS:
                    if not resolves(pool_host):
                        continue
                    say(f"retrying Hyperdrive via pooler host={pool_host}")
                    retry_status, retried = cf_api(
                        "POST",
                        "/hyperdrive/configs",
                        {
                            "name": HYPERDRIVE_NAME,
                            "origin": origin_body(pool_host, f"postgres.{PROJECT_REF}", password),
                            "caching": {"disabled": True},
                        },
                    )
                    if retry_status < 400 and retried.get("success", False):
                        result = retried.get("result") if isinstance(retried.get("result"), dict) else {}
                        describe_config(result)
                        say("HYPERDRIVE_RESULT=created")
                        say(f"HYPERDRIVE_ID={result.get('id')}")
                        return
                    say(f"pooler create failed status={retry_status} {safe_cf_error(retried)}")
            say("Migrations were applied. Hyperdrive was not created. See the redacted API error above.")
            return
        result = created.get("result") if isinstance(created.get("result"), dict) else {}
        describe_config(result)
        say("HYPERDRIVE_RESULT=created")
        say(f"HYPERDRIVE_ID={result.get('id')}")
        return
    describe_config(match)
    caching = match.get("caching") if isinstance(match.get("caching"), dict) else {}
    if caching.get("disabled") is True:
        say("HYPERDRIVE_RESULT=exists")
        say(f"HYPERDRIVE_ID={match.get('id')}")
        return
    patch_status, patched = cf_api(
        "PATCH",
        f"/hyperdrive/configs/{match.get('id')}",
        {"caching": {"disabled": True}},
    )
    if patch_status >= 400 or not patched.get("success", False):
        patch_status, patched = cf_api(
            "PUT",
            f"/hyperdrive/configs/{match.get('id')}",
            {
                "name": HYPERDRIVE_NAME,
                "origin": origin_body(host, user, password),
                "caching": {"disabled": True},
            },
        )
    if patch_status >= 400 or not patched.get("success", False):
        say(f"HYPERDRIVE_RESULT=exists_caching_on patch_status={patch_status} {safe_cf_error(patched)}")
        say(f"HYPERDRIVE_ID={match.get('id')}")
        return
    result = patched.get("result") if isinstance(patched.get("result"), dict) else match
    describe_config(result)
    say("HYPERDRIVE_RESULT=caching_disabled")
    say(f"HYPERDRIVE_ID={result.get('id') or match.get('id')}")


def main() -> None:
    os.chdir(ROOT)
    secret_report()
    if not os.environ.get("SUPABASE_DB_PASSWORD"):
        fail(
            "SUPABASE_DB_PASSWORD is missing from GitHub Actions secrets. "
            "Add it under Settings, Secrets and variables, Actions, for waelhusseinhr/CanDoHR."
        )
    _kind, host, user, password = connect()
    push_migrations(host, user, password)
    report_schema(host, user, password)
    ensure_hyperdrive(host, user, password)
    say("DB_PASSWORD_SETUP=works")


if __name__ == "__main__":
    main()
