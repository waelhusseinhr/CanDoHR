#!/usr/bin/env bash
# Run after `supabase db reset` in CI (or any local stack with migrations applied).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if ! command -v supabase >/dev/null 2>&1; then
  echo "run_migrations_ci: supabase CLI required" >&2
  exit 1
fi

DB_URL="$(supabase status -o json | python3 -c "import json,sys; print(json.load(sys.stdin)['DB_URL'])")"

echo "run_migrations_ci: schema smoke (0001 baseline)"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f tests/schema/schema_smoke.sql

echo "run_migrations_ci: migration 0003 smoke (enterprise structures)"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f tests/schema/schema_0003_smoke.sql

echo "run_migrations_ci: ok"
