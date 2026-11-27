import assert from 'node:assert/strict';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { TextDecoder } from 'node:util';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server.js';

// Snapshots from Kavyarpit commit 72cc5d4117939e23c8c0377a5ddfe9e21f4c182f.
// Synthetic CI fixture only. Not n8n or a deployable production integration.
function load(file, imports = {}) {
  const exports = {};
  const code = ts.transpileModule(readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, fileName: file,
  }).outputText;
  vm.runInNewContext(code, {
    exports, URL, Headers, process: { env: {} },
    require(name) { if (!Object.hasOwn(imports, name)) throw new Error('Unexpected import: ' + name); return imports[name]; },
    fetch() { throw new Error('Network forbidden within loaded website code'); },
  }, { timeout: 5000 });
  return exports;
}
const base = 'local-staging/fixtures/kavyarpit/';
const contract = load(base + 'contract.ts');
const adapter = load(base + 'consultation-adapter.ts', {
  'server-only': {}, 'node:crypto': { createHmac }, '@/lib/consultation/contract': contract,
});
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
    // Explicitly bind the website route to a separate synthetic tenant in this fixture.
    if (parsed.route_key !== 'kavyarpit-web' || parsed.full_name !== 'Synthetic CI Test'
        || parsed.organization_id !== undefined || !/^[a-f0-9]{64}$/.test(parsed.idempotency_key)) {
      res.writeHead(400).end(); return;
    }
    const payload = { ...parsed, route_key: 'ci-transport-route', metadata: { ...parsed.metadata, synthetic: true } };
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
const url = 'http://127.0.0.1:' + server.address().port + '/test-intake';
const fake = { name: 'Synthetic CI Test', phone: '9999000000', location: 'Noida',
  project: 'undecided', budget: 'Help me decide', configuration: '3 BHK',
  timeline: 'Exploring options', siteVisit: 'Not yet', consent: true, website: '' };
const id = '8ce32db2-5fb4-4c81-8c4f-705b4e155a2f';
const dedupeSecret = 'synthetic-dedupe-only-not-a-production-secret';
const payload = adapter.buildIdempotentConsultationPayload(fake, id, dedupeSecret);
const body = JSON.stringify(payload);
const receipts = [];
async function syntheticSubmit(value) {
  const outbound = JSON.stringify(adapter.buildIdempotentConsultationPayload(value, id, dedupeSecret));
  const response = await fetch(url, { method: 'POST', redirect: 'error',
    headers: { 'Content-Type': 'application/json', 'x-test-signature': sign(outbound) },
    body: outbound, signal: AbortSignal.timeout(10000) });
  const receipt = response.ok ? await response.json() : null;
  receipts.push(receipt);
  return { status: adapter.isConfirmedSavedLeadReceipt(response.status, receipt) ? 'accepted' : 'failed' };
}
const post = load(base + 'route.ts', {
  'next/server': { NextResponse }, 'node:util': { TextDecoder },
  '@/lib/project-discovery': { approvedIds: ['calisto', 'imperia', 'divine', 'atlantis'] },
  '@/lib/consultation/contract': contract, '@/server/consultation-adapter': { submitConsultation: syntheticSubmit },
}).POST;
function request() {
  return new NextRequest('https://example.test/api/consultation', {
    method: 'POST', headers: { host: 'example.test', origin: 'https://example.test', 'content-type': 'application/json' },
    body: JSON.stringify(fake),
  });
}
try {
  const bad = await fetch(url, { method: 'POST', body, headers: { 'x-test-signature': 'invalid' }, signal: AbortSignal.timeout(10000) });
  assert.equal(bad.status, 401);
  assert.equal((await post(request())).status, 200);
  assert.equal((await post(request())).status, 200);
  assert.equal(receipts[0].duplicate, false);
  assert.equal(receipts[1].duplicate, true);
  assert.equal(receipts[0].lead_id, receipts[1].lead_id);
  assert.equal(receipts[0].intake_id, receipts[1].intake_id);
  assert.equal((await adapter.submitConsultation(fake)).status, 'disabled');
  console.log('PASS: website route snapshot, signed local transport and real SalesSetu staging schema');
} finally {
  server.close();
}
