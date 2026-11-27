import assert from 'node:assert/strict';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { once } from 'node:events';

// This process is a test fixture, not production transport or n8n.
const root = new URL(process.env.API_URL || '');
assert.equal(root.protocol, 'http:');
assert.ok(['127.0.0.1', 'localhost'].includes(root.hostname));
assert.equal(root.port, '55321');
assert.ok(!root.username && !root.password && !root.search && !root.hash);
assert.ok(root.pathname === '/' || root.pathname === '');
const serviceKey = process.env.SERVICE_ROLE_KEY;
assert.ok(serviceKey, 'Missing local service key');
const transportKey = randomBytes(32);
const sign = body => createHmac('sha256', transportKey).update(body).digest('hex');
const server = createServer(async (req, res) => {
  try {
    if (req.method !== 'POST' || req.url !== '/test-intake') { res.writeHead(404).end(); return; }
    const parts = []; let size = 0;
    for await (const part of req) {
      size += part.length;
      if (size > 4096) { res.writeHead(413).end(); return; }
      parts.push(part);
    }
    const body = Buffer.concat(parts);
    const signature = req.headers['x-test-signature'];
    const received = typeof signature === 'string' && /^[a-f0-9]{64}$/.test(signature)
      ? Buffer.from(signature, 'hex') : Buffer.alloc(0);
    const expected = Buffer.from(sign(body), 'hex');
    if (received.length !== expected.length || !timingSafeEqual(received, expected)) {
      res.writeHead(401).end(); return;
    }
    const parsed = JSON.parse(body.toString('utf8'));
    if (parsed.synthetic !== true || parsed.idempotency_key !== 'ci-only-transport-test') {
      res.writeHead(400).end(); return;
    }
    const payload = { route_key: 'ci-transport-route', full_name: 'Synthetic CI Test',
      phone: '9999000000', idempotency_key: parsed.idempotency_key,
      metadata: { synthetic: true } };
    const response = await fetch(new URL('/rest/v1/rpc/ingest_lead_capture_intake', root), {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
      headers: { 'Content-Type': 'application/json', apikey: serviceKey, Authorization: 'Bearer ' + serviceKey },
      body: JSON.stringify({ p_payload: payload }),
    });
    const receipt = await response.json();
    if (!response.ok || receipt.status !== 'processed' || !receipt.intake_id || !receipt.lead_id
        || typeof receipt.duplicate !== 'boolean') { res.writeHead(502).end(); return; }
    res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(receipt));
  } catch { res.writeHead(500).end(); }
});
server.listen(0, '127.0.0.1');
await once(server, 'listening');
const port = server.address().port;
const url = 'http://127.0.0.1:' + port + '/test-intake';
const body = JSON.stringify({ synthetic: true, idempotency_key: 'ci-only-transport-test' });
async function send(signature) {
  const response = await fetch(url, { method: 'POST', redirect: 'error',
    headers: { 'Content-Type': 'application/json', 'x-test-signature': signature },
    body, signal: AbortSignal.timeout(10000) });
  return { status: response.status, body: response.ok ? await response.json() : null };
}
try {
  assert.equal((await send('invalid')).status, 401);
  const first = await send(sign(body));
  const duplicate = await send(sign(body));
  assert.equal(first.status, 200);
  assert.equal(first.body.duplicate, false);
  assert.equal(duplicate.status, 200);
  assert.equal(duplicate.body.duplicate, true);
  assert.equal(first.body.lead_id, duplicate.body.lead_id);
  assert.equal(first.body.intake_id, duplicate.body.intake_id);
  console.log('PASS: loopback authenticated fixture, saved receipt and retry deduplication');
} finally {
  server.close();
}
