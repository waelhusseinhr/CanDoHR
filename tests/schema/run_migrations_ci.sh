#!/usr/bin/env bash
# Run after `supabase db reset` in CI (or any local stack with migrations applied).
# Each smoke file expects an empty database, so the second one is rebuilt first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if ! command -v supabase >/dev/null 2>&1; then
  echo "run_migrations_ci: supabase CLI required" >&2
  exit 1
fi

db_url() {
  supabase status -o json | python3 -c "import json,sys; print(json.load(sys.stdin)['DB_URL'])"
}

# The local login is not a superuser. The smokes switch to cando_app with SET ROLE,
# which needs membership in that role.
allow_set_role() {
  local url="$1"
  psql "$url" -v ON_ERROR_STOP=1 -c "GRANT cando_app TO postgres; GRANT cando_sealer TO postgres;"
}

echo "run_migrations_ci: schema smoke (0001 baseline)"
DB_URL="$(db_url)"
allow_set_role "$DB_URL"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f tests/schema/schema_smoke.sql

echo "run_migrations_ci: rebuild for migration 0003 smoke"
supabase db reset --local --no-seed
DB_URL="$(db_url)"
allow_set_role "$DB_URL"

echo "run_migrations_ci: migration 0003 smoke (enterprise structures)"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f tests/schema/schema_0003_smoke.sql

echo "run_migrations_ci: ok"
