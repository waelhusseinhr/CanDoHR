#!/usr/bin/env bash
# Run after `supabase db reset --local --no-seed` in CI (or any local stack with all migrations applied).
#
# Behaviour (Wa'el / AGENTS.md Step 1):
#   1. One database with migrations 0001 through the latest in supabase/migrations applied in order.
#   2. Baseline for this path is the migration apply itself (0001 initial + 0002 roles + …), not
#      tests/schema/schema_smoke.sql — that file pairs with schema/cando_schema.sql (see load_schema.sh)
#      and inserts the same tenant keys as schema_0003_smoke.sql, so running both on one DB duplicates rows.
#   3. Then schema_0003_smoke.sql through schema_0020_smoke.sql in order on the *same* database,
#      without resetting between smokes. Each smoke adds fixtures and checks constraints for its
#      migration tranche; later smokes assume earlier migrations and fixtures are already present.
#
# CI applies every migration before calling this script. Do not run `supabase db reset` here.
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

run_smoke() {
  local label="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    echo "run_migrations_ci: SKIP $label — missing $file" >&2
    return 0
  fi
  echo "run_migrations_ci: $label"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$file"
}

DB_URL="$(db_url)"
allow_set_role "$DB_URL"

echo "run_migrations_ci: baseline = migrations 0001–latest already applied (see script header)"

for n in $(seq -w 3 20); do
  run_smoke "migration 00${n} smoke" "tests/schema/schema_00${n}_smoke.sql"
done

echo "run_migrations_ci: ok"
