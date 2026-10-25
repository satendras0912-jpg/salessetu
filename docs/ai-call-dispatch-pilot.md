# Automatic dispatch pilot — draft, disabled

This change adds a scheduler client for the existing POST endpoint. It does not
change the application, mutate the database, register consent, or create jobs.
It sends at most one request per tick for one explicitly configured organization.
It uses the canonical www host without redirects and never retries a request.
Only a sanitized outcome is logged; no response bodies, contact data or secrets.

## Activation blockers

Do not enable scheduling yet. Repository inspection shows that the current
claim/start functions do not re-evaluate consent and suppression immediately
before dispatch. The dispatch service also marks uncertain provider outcomes as
failed, which may schedule another attempt even if a provider accepted the call.
Before activation:

1. Add and test dispatch-time eligibility checks (withdrawn/expired consent,
   suppression, organization/provider configuration and expiry).
2. Reconcile provider-accepted or timed-out dispatches before allowing retries.
   Do not blindly reset a dispatching job or retry an uncertain HTTP outcome.
3. Verify deployed database functions match the reviewed migrations.
4. Review pending jobs and test with one consented own-number job.
5. Confirm the calling hours, capacity and cost limit for this pilot.

## Configuration after blockers are resolved

GitHub repository Actions variables:
- AI_CALL_AUTO_DISPATCH_ENABLED: leave unset or false until approved for activation.
- AI_CALL_DISPATCH_ORGANIZATION_ID: one organization UUID, never blank.
- AI_CALL_TIMEZONE: e.g. Asia/Kolkata.
- AI_CALL_WINDOW_START_HOUR and AI_CALL_WINDOW_END_HOUR: integer local hours,
  start inclusive, end exclusive; same-day windows only, no overnight window.

Actions secret AI_CALL_DISPATCH_SECRET must match the production dispatch secret.
Never paste its value into a PR, source file or chat. This draft does not create,
read or modify repository secrets or variables.

After merge and configuration, manual and scheduled runs share the same enable
switch and concurrency group. A tick targets one job, not an entire queue. The
nominal schedule is every five minutes; GitHub may delay/drop scheduled runs and
public-repository inactivity can disable them. This is a small pilot scheduler,
not a guaranteed low-latency production queue. Review before scaling beyond it.
Other callers of the endpoint are not covered by workflow concurrency.

On any failed/uncertain run, set AI_CALL_AUTO_DISPATCH_ENABLED=false, inspect
server/job/provider state and reconcile before re-enabling. There is no automatic
circuit breaker across future scheduled ticks in this draft.

## Validation

Run `node --test scripts/ai-calling/dispatch-once.test.mjs`.
The tests use mocked fetch; no real calls are placed. Cover disabled mode, required
configuration, local calling-window boundary, scoped request, redirect refusal,
empty queue, accepted request, HTTP/transport failures without retry or secret
output, and malformed success responses. Full Next build is not required for these
standalone Node scripts; production endpoint integration still needs verification.

Sources:
- https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule
- https://docs.github.com/en/actions/how-tos/troubleshoot-workflows
