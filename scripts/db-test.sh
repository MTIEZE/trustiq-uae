#!/usr/bin/env bash
#
# Apply every migration to a throwaway Postgres and run the schema test suite.
#
# Needs Docker. Nothing else: no Supabase CLI, no local Postgres. The container
# is removed on exit, pass or fail.
#
#   ./scripts/db-test.sh
#
set -euo pipefail

CONTAINER="trustiq-schema-test-$$"
IMAGE="postgres:16-alpine"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting $IMAGE as $CONTAINER"
docker run -d --rm \
  --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=trustiq \
  "$IMAGE" >/dev/null

printf 'Waiting for Postgres'
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready -U postgres -d trustiq >/dev/null 2>&1; then
    echo " ready"
    break
  fi
  printf '.'
  sleep 1
done

if ! docker exec "$CONTAINER" pg_isready -U postgres -d trustiq >/dev/null 2>&1; then
  echo " timed out" >&2
  exit 1
fi

run_sql_file() {
  local file="$1"
  docker exec -i "$CONTAINER" \
    psql -v ON_ERROR_STOP=1 -q -U postgres -d trustiq < "$file"
}

echo
echo "Applying Supabase stubs"
run_sql_file "$ROOT/supabase/tests/00_supabase_stubs.sql"

echo "Applying migrations"
for migration in "$ROOT"/supabase/migrations/*.sql; do
  echo "  $(basename "$migration")"
  run_sql_file "$migration"
done

echo
echo "Running schema tests"
run_sql_file "$ROOT/supabase/tests/schema.test.sql"
