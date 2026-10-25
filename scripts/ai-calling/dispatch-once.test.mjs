import test from 'node:test';
import assert from 'node:assert/strict';
import { dispatchOnce } from './dispatch-once.mjs';
const env = {
  AI_CALL_AUTO_DISPATCH_ENABLED: 'true',
  AI_CALL_DISPATCH_ORGANIZATION_ID: '00000000-0000-4000-8000-000000000001',
  AI_CALL_DISPATCH_SECRET: 'test-only-secret-'.repeat(4),
  AI_CALL_WINDOW_START_HOUR: '10', AI_CALL_WINDOW_END_HOUR: '18', AI_CALL_TIMEZONE: 'Asia/Kolkata',
};
const noon = new Date('2026-10-25T06:30:00Z');
const noRequest = () => assert.fail('Network must not be called');
test('disabled by default', async () => {
  assert.deepEqual(await dispatchOnce({}, noRequest), { status: 'disabled' });
});
test('requires organization, secret and calling window', async () => {
  for (const key of ['AI_CALL_DISPATCH_ORGANIZATION_ID', 'AI_CALL_DISPATCH_SECRET', 'AI_CALL_WINDOW_START_HOUR', 'AI_CALL_TIMEZONE']) {
    await assert.rejects(dispatchOnce({ ...env, [key]: '' }, noRequest, noon));
  }
});
test('respects end-exclusive local calling window', async () => {
  assert.deepEqual(await dispatchOnce(env, noRequest, new Date('2026-10-25T12:30:00Z')), { status: 'outside_calling_window' });
});
test('sends exactly one scoped POST and refuses redirects', async () => {
  let calls = 0;
  const result = await dispatchOnce(env, async (url, options) => {
    calls++;
    assert.equal(url, 'https://www.salessetu.in/api/ai-calling/dispatch');
    assert.equal(options.redirect, 'error');
    assert.equal(options.method, 'POST');
    assert.equal(JSON.parse(options.body).organizationId, env.AI_CALL_DISPATCH_ORGANIZATION_ID);
    return { status: 202, json: async () => ({ ok: true, result: { status: 'initiated', providerCallId: 'not-logged' } }) };
  }, noon);
  assert.equal(calls, 1);
  assert.deepEqual(result, { status: 'initiated' });
});
test('empty queue is successful', async () => {
  assert.deepEqual(await dispatchOnce(env, async () => ({ status: 200, json: async () => ({ ok: true, result: { status: 'empty' } }) }), noon), { status: 'empty' });
});
test('no retry or sensitive output on timeout or HTTP rejection', async () => {
  for (const status of [401, 500, 302, null]) {
    let calls = 0;
    await assert.rejects(dispatchOnce(env, async () => {
      calls++;
      if (status === null) throw new Error(env.AI_CALL_DISPATCH_SECRET);
      return { status };
    }, noon), error => !error.message.includes(env.AI_CALL_DISPATCH_SECRET));
    assert.equal(calls, 1);
  }
});
test('rejects misleading success payloads', async () => {
  await assert.rejects(dispatchOnce(env, async () => ({ status: 200, json: async () => ({ ok: false, result: { status: 'initiated' } }) }), noon));
});
