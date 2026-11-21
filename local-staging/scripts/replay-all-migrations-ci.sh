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
mkdir -p "$REPLAY_SUPABASE/migrations"
cp "$GITHUB_WORKSPACE/local-staging/supabase/config.toml" "$REPLAY_SUPABASE/config.toml"

# This config is copied to a disposable runner directory, so it cannot link to
# a hosted project. The base migrations run first; a synthetic founder/platform
# fixture then satisfies the explicit historic bootstrap prerequisites.
sed -i 's/^project_id = .*/project_id = "salessetu-local-full-replay"/' "$REPLAY_SUPABASE/config.toml"

for migration in "$GITHUB_WORKSPACE"/supabase/migrations/{001..036}_*.sql; do
  test -f "$migration"
  cp "$migration" "$REPLAY_SUPABASE/migrations/"
done
npx --yes "supabase@$SUPABASE_CLI_VERSION" start --workdir "$REPLAY_ROOT" >/dev/null

set -a
eval "$(npx --yes "supabase@$SUPABASE_CLI_VERSION" status --workdir "$REPLAY_ROOT" --output env)"
set +a

case "$API_URL" in
  http://127.0.0.1:55321|http://localhost:55321) ;;
  *) echo "Refusing non-local Supabase API URL" >&2; exit 1 ;;
esac

# Migrations 037 and 041 intentionally use these historic bootstrap IDs. The
# fixture lives only in this disposable database and contains no production
# password, token, tenant, lead, deal, booking or other customer record.
psql "$DB_URL" --set ON_ERROR_STOP=1 <<'SQL'
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '5eec53aa-d4c3-4baf-b31e-dd4c072dde0b',
  'authenticated', 'authenticated', 'digitalavalokan@gmail.com',
  '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(),
  jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
  '{}'::jsonb, now(), now()
)
on conflict (id) do update set
  email = excluded.email,
  email_confirmed_at = excluded.email_confirmed_at,
  updated_at = now();

insert into public.organizations (
  id, name, slug, organization_type, status, email, settings, metadata, created_by
)
values (
  '955b8449-5c16-4eeb-a778-e2cd95f44ca7',
  'SalesSetu Platform', 'salessetu-platform', 'platform', 'active',
  'digitalavalokan@gmail.com',
  jsonb_build_object('timezone', 'Asia/Kolkata', 'locale', 'en-IN', 'default_currency', 'INR'),
  jsonb_build_object('staging_fixture', true),
  '5eec53aa-d4c3-4baf-b31e-dd4c072dde0b'
)
on conflict (id) do update set
  name = excluded.name,
  status = excluded.status,
  updated_at = now();
SQL

cp -R "$GITHUB_WORKSPACE/supabase/migrations/." "$REPLAY_SUPABASE/migrations/"
npx --yes "supabase@$SUPABASE_CLI_VERSION" migration up --workdir "$REPLAY_ROOT"

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
