# Automatic dispatch pilot — draft, disabled

This draft adds an opt-in scheduler plus dispatch-time database guards. It sends
at most one request per tick for one explicitly configured organization, using
the canonical www host without redirects or request retries. Logs contain only
sanitized outcomes, not provider bodies, phone numbers or secrets.

## Dispatch guarantees and limits

Immediately before the provider request, `authorize_ai_call_dispatch` locks the
attempt and job, rechecks consent, suppression, campaign window, job expiry and
active organization-owned provider/script configuration, and commits a durable
`dispatch_requires_reconciliation` hold. Ineligible calls are blocked with a
reason, and no provider request is sent. The latest expired consent cannot fall
back to an older grant. Existing campaign `consent_required` policy is preserved.

The hold prevents a later claim/start, even if someone resets job status to queued.
A lost authorization response also fails closed without contacting the provider.
Timeouts, malformed responses, explicit provider errors and failed initiation
writes are conservatively held for reconciliation rather than completed as failed
and automatically retried. Preparation errors leave the claimed job dispatching
for review; there is no automatic stale-job recovery in this draft.

Known provider acceptance clears the hold and moves the job to in_progress. A
verified terminal webhook can also clear it using the existing completion policy.
Only the service role can assert initiation/completion. Duplicate terminal events
and late initiation cannot regress a completed attempt or clear a newer hold.
Consent can change after the final database check and before the external request;
a database transaction cannot atomically include a remote provider operation.

## Deployment and activation prerequisites

Keep scheduling disabled and pause other dispatch callers throughout rollout.

1. Review the deployed function definitions against this migration; production
   drift must be resolved before replacing functions.
2. Apply `20261025120000_ai_call_dispatch_guard.sql`, then deploy the application
   changes. Both are required: old dispatch code still has unsafe retry behavior.
   New code fails closed if authorization RPC is missing. Do not roll the app back
   to the old error handler while workers are running.
3. Review existing dispatching/in-progress jobs manually; the new column defaults
   false and does not identify historical ambiguous calls. Do not reset them to
   queued without checking the provider.
4. Verify deployed permissions, RLS, webhook behavior and concurrent workers in a
   non-production integration environment; the isolated SQL tests omit foreign
   keys and do not simulate separate database sessions.
5. Test one consented own-number job, verify its terminal webhook, confirm calling
   hours and capacity/cost limits, then explicitly enable the scheduler.

## Reconciliation

For a held job, inspect its attempt, `dispatch_authorized_attempt_id`, webhook
inbox and provider records. If a call exists, reconcile that same attempt through
the trusted provider-result path; do not create another call. If the provider
cannot establish whether it accepted the request, keep the hold. Clear a hold
for retry only after verified evidence that no call was placed and a fresh
eligibility review. No automatic hold-clearing endpoint is included.

## Configuration after blockers are resolved

Supabase is the production scheduler. Migration
`20261028190000_ai_call_supabase_scheduler.sql` creates a five-minute cron job,
but it starts disabled and without an organization scope. Store the production
dispatch secret only in Supabase Vault as `ai_call_dispatch_secret`; never put it
in a migration, source file, log, or PR. Configure the one approved organization
and calling hours, verify the disabled result, and only then explicitly set
`enabled = true`. The GitHub workflow is retained for a human-triggered fallback,
not scheduled dispatch, so the two schedulers cannot run concurrently.

The Supabase configuration row contains the enable flag, one organization UUID,
an IANA timezone and local start/end hours (start inclusive, end exclusive).
Keep `enabled = false` until the one consented own-number test has been reviewed.
A tick targets one job, not an entire queue. This is a small pilot scheduler, not
a guaranteed low-latency production queue. Review before scaling beyond it.

On any failed or uncertain outcome, set the Supabase setting `enabled = false`,
inspect server/job/provider state and reconcile before re-enabling. There is no
automatic circuit breaker across future scheduled ticks in this draft.

## Validation

Run `npm ci`, `node --test scripts/ai-calling/*.test.mjs`, and `npx tsc --noEmit`.
The service tests execute the real TypeScript with mocked I/O. Database tests run
the actual migration/functions and repository table checks in isolated PGlite;
external foreign keys, RLS and Supabase auth are replaced with test fixtures.
All fixtures are synthetic and no real calls are placed. Coverage includes consent
withdrawal/expiry, suppression, campaign windows, expiry, tenant configuration,
repeated authorization, durable holds, provider/network/DB failures and webhook
ordering. Run a full production build in the deployment environment as well.
