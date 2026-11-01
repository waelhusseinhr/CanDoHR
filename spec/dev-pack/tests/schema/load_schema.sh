#!/usr/bin/env bash
# Loads the schema into a scratch PostgreSQL 16 database and runs the smoke test.
# Usage: PGHOST=localhost PGPORT=5432 PGUSER=postgres ./tests/schema/load_schema.sh
set -euo pipefail
DB=${DB:-cando_schema_check}
psql -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $DB"
psql -c "DROP ROLE IF EXISTS cando_app" >/dev/null 2>&1 || true
psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE $DB"
psql -v ON_ERROR_STOP=1 -d "$DB" -q -f schema/cando_schema.sql
psql -v ON_ERROR_STOP=1 -d "$DB" -q -f tests/schema/schema_smoke.sql
psql -c "DROP DATABASE IF EXISTS $DB" >/dev/null && psql -c "DROP ROLE IF EXISTS cando_app" >/dev/null 2>&1 || true
echo "Schema loaded and smoke test passed."
