# SalesSetu — isolated local Supabase contract harness

**Not a production database replica.** Synthetic-only receipt and duplicate-handling fixture.

## Boundaries

- Open terminal within local-staging directory. This has its own Supabase configuration and ONE local migration.
- The 103 SQL migrations stored in the parent supabase/migrations folder are not executed here.
- Never use database link, db push, db pull or migration repair against production as part of this procedure.
- Never use actual customer data or production service keys, n8n endpoints or website routes.
- Never expose this local development stack to external traffic. Use trusted/private networking and loopback bindings.

## Migration filename preflight (repo root)

    node scripts/migrations/preflight.mjs
    node --test scripts/migrations/preflight.test.mjs

This checks 103 migration filenames for duplicate versions; it is NOT a schema replay test.

## Windows prerequisites

Docker Desktop with WSL2 backend running, Node.js 20+, Supabase CLI via npx. If Docker is not installed, this local stack cannot start.

## Start local isolated environment

From repository root:

    cd local-staging
    npx supabase --version
    npx supabase start
    npx supabase status

Expected local addresses: API 127.0.0.1:55321, database 127.0.0.1:55322, Studio 127.0.0.1:55323.

## Synthetic receipt test

In the same PowerShell terminal, use the LOCAL SERVICE ROLE KEY shown by npx supabase status. Never share or upload that key:

    $env:LOCAL_SUPABASE_URL = "http://127.0.0.1:55321"
    $env:LOCAL_SUPABASE_SERVICE_ROLE_KEY = "<LOCAL-ONLY-KEY>"
    node ./scripts/test-local-receipt.mjs
    Remove-Item Env:LOCAL_SUPABASE_SERVICE_ROLE_KEY
    node --test ./scripts/test-local-receipt.test.mjs

Checks saved lead ID, duplicate receipt stability and rejection of wrong tenant route.
The smoke script rejects non-loopback hosts, wrong ports, HTTPS and URL redirects.

Stop:

    npx supabase stop

## Important limitations

This fixture does not duplicate the operational SalesSetu RPC, tenant permissions, triggers, booking flows, n8n authentication, or actual production schema. Docker-backed run and real PostgreSQL contract test are pending on a machine with Docker.
The unrecorded migrations must be reconciled before attempting a complete schema replay.

Supabase guidance:
https://supabase.com/docs/guides/local-development
https://supabase.com/docs/guides/local-development/cli-workflows
