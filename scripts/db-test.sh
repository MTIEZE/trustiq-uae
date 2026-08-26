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
DOCKER_ERR="$(mktemp)"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -f "$DOCKER_ERR"
}
trap cleanup EXIT

# Reports why this failed somewhere a person can actually read it.
#
# GitHub renders `::error::` as a job annotation, and annotations are readable
# without a token. Job logs are not. Without this, a CI failure here tells
# anyone who cannot sign in to the repository only "Process completed with exit
# code 1", which is how a container that never started spent two runs looking
# like a broken test suite.
fatal() {
  echo "$1" >&2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error::$1"
  fi
  exit 1
}

# Trims the registry's message onto one line so it survives as an annotation.
reason() {
  tr '\r\n' '  ' < "$DOCKER_ERR"
}

# Pulled as its own step, with retries. Docker Hub rate limits anonymous pulls
# per IP address, and CI runners share addresses, so this fails on a busy
# runner and not at all on a quiet one. Retrying is the fix; failing with the
# registry's own words is what makes the next failure diagnosable.
echo "Pulling $IMAGE"
pulled=""
for attempt in 1 2 3; do
  if docker pull -q "$IMAGE" >/dev/null 2>"$DOCKER_ERR"; then
    pulled="yes"
    break
  fi
  echo "  attempt $attempt failed: $(reason)"
  sleep $((attempt * 5))
done
[ -n "$pulled" ] || fatal "could not pull $IMAGE after 3 attempts: $(reason)"

echo "Starting $IMAGE as $CONTAINER"
if ! docker run -d --rm \
  --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=trustiq \
  "$IMAGE" >/dev/null 2>"$DOCKER_ERR"
then
  fatal "could not start $CONTAINER: $(reason)"
fi

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
  echo " timed out"
  fatal "Postgres in $CONTAINER never became ready"
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
