#!/usr/bin/env bash
# LOCAL-TEST-ONLY. Validates supabase/migrations on a DISPOSABLE local PostgreSQL.
#
# Usage:
#   PGHOST=localhost PGPORT=55433 PGUSER=postgres ./supabase/tests/local/run_local_db_tests.sh
#
# Safety:
#   * creates and drops ONLY the database named in $TEST_DB (default itsr_local_validation)
#   * refuses to run against a database name that does not start with "itsr_local_"
#   * refuses hosts other than localhost/127.0.0.1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PSQL="${PSQL:-psql}"
TEST_DB="${TEST_DB:-itsr_local_validation}"
export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-55433}" PGUSER="${PGUSER:-postgres}"

case "$PGHOST" in localhost|127.0.0.1) ;; *) echo "Refusing non-local host $PGHOST"; exit 2;; esac
case "$TEST_DB" in itsr_local_*) ;; *) echo "Refusing DB name $TEST_DB (must start with itsr_local_)"; exit 2;; esac

echo "== Static checks on supabase/migrations"
fail=0
if grep -inE 'create\s+schema\s+(if\s+not\s+exists\s+)?auth\b|function\s+auth\.|create\s+table\s+(if\s+not\s+exists\s+)?auth\.' "$ROOT"/supabase/migrations/*.sql; then
  echo "FAIL: migrations must not create/override Supabase auth objects"; fail=1; fi
if grep -inE 'disable\s+row\s+level\s+security' "$ROOT"/supabase/migrations/*.sql; then
  echo "FAIL: migrations must not disable RLS"; fail=1; fi
if grep -inE 'grant\s+execute\s+on\s+all\s+functions' "$ROOT"/supabase/migrations/*.sql; then
  echo "FAIL: blanket GRANT EXECUTE ON ALL FUNCTIONS found"; fail=1; fi
[ $fail -eq 0 ] && echo "PASS static checks"

echo "== Fresh database $TEST_DB on $PGHOST:$PGPORT"
"$PSQL" -q -d postgres -c "drop database if exists $TEST_DB" -c "create database $TEST_DB"

run() { "$PSQL" -q -d "$TEST_DB" -v ON_ERROR_STOP=1 -f "$1"; }
run "$ROOT/supabase/tests/local/00_supabase_shim.sql"
for m in "$ROOT"/supabase/migrations/*.sql; do echo "-- applying $(basename "$m")"; run "$m"; done
run "$ROOT/supabase/tests/local/10_test_harness.sql"

echo "== Running acceptance tests"
OUT="$("$PSQL" -d "$TEST_DB" -X -f "$ROOT/supabase/tests/local/20_security_and_workflow_tests.sql" 2>&1)"
echo "$OUT" | grep -E 'NOTICE:  (PASS|FAIL)|ERROR' | sed 's/^psql:[^:]*:[0-9]*: //'
echo "$OUT" | sed -n '/passed | failed | total/,/^$/p'
FAILED=$("$PSQL" -d "$TEST_DB" -tAc "select count(*) from test.results where not passed")
ERRORS=$(echo "$OUT" | grep -c 'ERROR' || true)
TOTAL=$("$PSQL" -d "$TEST_DB" -tAc "select count(*) from test.results")
echo "== RESULT: total=$TOTAL failed=$FAILED unexpected_errors=$ERRORS static_fail=$fail"
[ "$FAILED" = "0" ] && [ "$ERRORS" = "0" ] && [ $fail -eq 0 ]
