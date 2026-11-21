#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_ACTIONS:?This replay is restricted to an isolated GitHub Actions runner.}"
: "${GITHUB_WORKSPACE:?}"
: "${RUNNER_TEMP:?}"

readonly SUPABASE_CLI_VERSION="3.2.0"
readonly REPLAY_ROOT="$RUNNER_TEMP/salessetu-full-migration-replay"
readonly REPLAY_SUPABASE="$REPLAY_ROOT/supabase"

cleanup() {
  npx --yes "supabase@$SUPABASE_CLI_VERSION" stop --workdir "$REPLAY_ROOT" --no-backup >/dev/null 2>&1 || true
  rm -rf "$REPLAY_ROOT"
}
trap cleanup EXIT

rm -rf "$REPLAY_ROOT"
mkdir -p "$REPLAY_SUPABASE"
cp "$GITHUB_WORKSPACE/local-staging/supabase/config.toml" "$REPLAY_SUPABASE/config.toml"
cp -R "$GITHUB_WORKSPACE/supabase/migrations" "$REPLAY_SUPABASE/migrations"

# This config is copied to a disposable runner directory, so it cannot link to
# a hosted project. The original migration directory remains read-only.
sed -i 's/^project_id = .*/project_id = "salessetu-local-full-replay"/' "$REPLAY_SUPABASE/config.toml"

npx --yes "supabase@$SUPABASE_CLI_VERSION" start --workdir "$REPLAY_ROOT"
npx --yes "supabase@$SUPABASE_CLI_VERSION" db reset --workdir "$REPLAY_ROOT" --no-seed

set -a
eval "$(npx --yes "supabase@$SUPABASE_CLI_VERSION" status --workdir "$REPLAY_ROOT" --output env)"
set +a

applied_count="$(psql "$DB_URL" --tuples-only --no-align --command 'select count(*) from supabase_migrations.schema_migrations')"
test "$applied_count" = "103"

# The replay must retain the repo's intended service-role-only capture RPCs.
psql "$DB_URL" --set ON_ERROR_STOP=1 --command "
  do \$\$
  begin
    if has_function_privilege('anon', 'public.ingest_lead_capture_intake(jsonb)', 'EXECUTE')
      or has_function_privilege('authenticated', 'public.ingest_lead_capture_intake(jsonb)', 'EXECUTE')
      or not has_function_privilege('service_role', 'public.ingest_lead_capture_intake(jsonb)', 'EXECUTE') then
      raise exception 'unexpected ingest_lead_capture_intake privileges after local replay';
    end if;
  end
  \$\$;"

printf 'PASS: isolated full migration replay applied %s migrations with capture RPC privileges checked\n' "$applied_count"
