import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';

// Execute the real TypeScript service with only its I/O dependencies replaced.
const source = readFileSync(new URL('../../lib/ai-calling/dispatch-service.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
function harness({ authorization = { authorized: true }, authorizeError, providerError, markError, preparationError, startError } = {}) {
  const operations = [];
  const providerRequests = [];
  const admin = {
    async rpc(name) {
      operations.push(name);
      if (name === 'claim_ai_call_job') return { data: { id: 'job', organization_id: 'org', script_variables: {}, call_context: {}, metadata: {} } };
      if (name === 'start_ai_call_attempt') return { data: { id: 'attempt' }, error: startError };
      if (name === 'authorize_ai_call_dispatch') return { data: authorization, error: authorizeError };
      if (name === 'mark_ai_call_initiated') return { data: {}, error: markError };
      throw new Error(`Unexpected mutation ${name}`);
    },
    from(table) {
      const query = { select: () => query, eq: () => query, single: async () => ({
        data: table === 'ai_call_script_templates'
          ? { status: 'active', system_prompt: 'Ask about {{contact_name}} requirements.', opening_message: 'Test', closing_prompt: 'Template closing.', maximum_call_duration_seconds: 60 }
          : { status: 'active', provider_code: 'bland_ai', default_language_code: 'hi-IN' },
        error: preparationError,
      }) };
      return query;
    },
  };
  const exports = {};
  vm.runInNewContext(compiled, { exports, URL, require(name) {
    if (name === 'server-only') return {};
    if (name.includes('supabase/admin')) return { createAdminClient: () => admin };
    if (name.includes('webhook-signature')) return { createBlandWebhookToken: () => 'synthetic-token' };
    if (name.includes('providers/factory')) return {
      resolveAiCallSecret: () => 'synthetic-secret',
      createAiCallProvider: () => ({ async dispatchCall(input) {
        operations.push('provider');
        providerRequests.push(input);
        if (providerError) throw providerError;
        return { providerCallId: 'synthetic-call', providerResponse: {} };
      } }),
    };
    throw new Error(`Unexpected import ${name}`);
  } });
  return { operations, providerRequests, run: () => exports.dispatchNextAiCall({ workerId: 'test', webhookBaseUrl: 'https://example.test' }) };
}
test('outgoing task preserves template and appends clarification rules after closing', async () => {
  const h = harness();
  assert.equal((await h.run()).status, 'initiated');
  const request = h.providerRequests[0];
  assert.ok(request.task.includes('Ask about  requirements.'));
  assert.ok(!request.task.includes('{{contact_name}}'));
  assert.ok(request.task.indexOf('Conversation clarification and closing rules:') > request.task.indexOf('Template closing.'));
  assert.match(request.task, /Always respect an explicit refusal/);
  assert.match(request.task, /leave that answer unknown/);
  assert.equal(request.maximumDurationSeconds, 60);
});
test('provider request follows durable authorization; accepted call is recorded', async () => {
  const h = harness();
  assert.equal((await h.run()).status, 'initiated');
  assert.deepEqual(h.operations, ['claim_ai_call_job','start_ai_call_attempt','authorize_ai_call_dispatch','provider','mark_ai_call_initiated']);
});
for (const reason of ['INELIGIBLE','RECONCILIATION_REQUIRED']) test(`authorization ${reason} sends no call`, async () => {
  const h = harness({ authorization: { authorized: false, reason } });
  assert.equal((await h.run()).status, reason === 'INELIGIBLE' ? 'blocked' : 'reconciliation_required');
  assert.ok(!h.operations.includes('provider'));
});
test('lost authorization response fails closed', async () => {
  const h = harness({ authorizeError: { message: 'timeout' } });
  assert.equal((await h.run()).status, 'reconciliation_required');
  assert.ok(!h.operations.includes('provider'));
});
for (const providerError of [new Error('timeout'), new Error('HTTP 500'), new Error('malformed success')]) test(`uncertain ${providerError.message} never completes or retries`, async () => {
  const h = harness({ providerError });
  assert.equal((await h.run()).status, 'reconciliation_required');
  assert.equal(h.operations.filter(x => x === 'provider').length, 1);
  assert.ok(!h.operations.includes('complete_ai_call_attempt'));
});
test('provider acceptance followed by DB failure never schedules a retry', async () => {
  const h = harness({ markError: { message: 'database unavailable' } });
  assert.equal((await h.run()).status, 'reconciliation_required');
  assert.ok(!h.operations.includes('complete_ai_call_attempt'));
});
for (const options of [{ preparationError: { message: 'unavailable' } }, { startError: { message: 'active attempt exists' } }]) test('preparation failure does not recover somebody else’s attempt', async () => {
  const h = harness(options);
  assert.equal((await h.run()).status, 'failed');
  assert.ok(!h.operations.includes('provider'));
  assert.ok(!h.operations.includes('complete_ai_call_attempt'));
  assert.ok(h.operations.filter(x => x === 'start_ai_call_attempt').length <= 1);
});


test('AI dispatch supplies a neutral project fallback when no project is known', () => {
  const source = readFileSync(new URL('../../lib/ai-calling/dispatch-service.ts', import.meta.url), 'utf8');
  assert.match(source, /project_name: "your property enquiry"/);
  assert.match(source, /templateFallbacks\[key\] \?\? match/);
});
