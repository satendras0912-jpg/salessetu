import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
function load(path, require = () => ({})) {
  const exports = {};
  const source = readFileSync(new URL(path, import.meta.url), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText, { exports, require, URLSearchParams });
  return exports;
}
const contract = load('../../lib/follow-ups/worklist-contract.ts');
test('India midnight and month rollover use IST, not server date', () => {
  assert.equal(contract.indiaDayBounds(new Date('2026-10-31T18:29:59Z')).start, '2026-10-30T18:30:00.000Z');
  assert.equal(contract.indiaDayBounds(new Date('2026-10-31T18:30:00Z')).start, '2026-10-31T18:30:00.000Z');
  assert.equal(contract.indiaDayBounds(new Date('2026-10-31T18:30:00Z')).end, '2026-11-01T18:30:00.000Z');
});
test('invalid filters and pagination cannot broaden to arbitrary statuses or unbounded ranges', () => {
  for (const page of ['-1', '2junk', '1.5', 'Infinity', '999999999999999999']) {
    const f = contract.parseWorklistFilters({ view: 'deleted', owner: 'other-user', page });
    assert.equal(f.page, 1); assert.equal(f.view, 'open'); assert.equal(f.owner, 'all');
  }
  assert.equal(contract.parseWorklistFilters({ page: ['2', '4'] }).page, 2);
  assert.equal(contract.worklistHref({view:'today',owner:'mine',page:2},3), '/dashboard/follow-ups?view=today&owner=mine&page=3');
});
function service({ denied = false, error = null } = {}) {
  const calls = [];
  const query = new Proxy({}, { get: (_, method) => (...args) => {
    calls.push([method, ...args]);
    return method === 'range' ? Promise.resolve({data:[],count:0,error}) : query;
  }});
  const module = load('../../lib/follow-ups/worklist-service.ts', name => {
    if (name === './worklist-contract') return contract;
    if (name.includes('access-control')) return { requirePermissionAccess: async options => {
      calls.push(['authorize', options]);
      if (denied) throw new Error('denied');
      return {context:{organization:{id:'org-a'},user:{id:'user-a'}}};
    }};
    if (name.includes('supabase/server')) return {createClient:async () => ({from: (...args) => {calls.push(['from',...args]);return query;}})};
    if (name === 'server-only') return {};
    throw new Error(`Unexpected import ${name}`);
  });
  return { ...module, calls };
}
test('denied access never reaches database', async () => {
  const s = service({denied:true});
  await assert.rejects(s.getFollowUpWorklist({view:'open',owner:'all',page:1}), /denied/);
  assert.equal(s.calls.some(c=>c[0]==='from'), false);
});
test('worklist scopes both task and lead, excludes deleted rows, applies mine and bounded pagination', async () => {
  const s = service();
  await s.getFollowUpWorklist({view:'today',owner:'mine',page:2});
  const has = (...args) => s.calls.some(c=>JSON.stringify(c)===JSON.stringify(args));
  assert.ok(has('eq','organization_id','org-a'));
  assert.ok(has('eq','leads.organization_id','org-a'));
  assert.ok(has('is','deleted_at',null)); assert.ok(has('is','leads.deleted_at',null));
  assert.ok(has('eq','assigned_to','user-a')); assert.ok(has('range',25,49));
  assert.ok(s.calls.some(c=>c[0]==='select' && c[1].includes('leads!inner')));
  assert.ok(s.calls.some(c=>c[0]==='gte' && c[1]==='due_at'));
  assert.ok(s.calls.some(c=>c[0]==='lt' && c[1]==='due_at'));
  assert.deepEqual(Array.from(s.calls[0][1].allOf), ['leads.view','followups.view']);
});
test('completed view does not apply active status predicate; unassigned is explicit', async () => {
  const s = service();
  await s.getFollowUpWorklist({view:'completed',owner:'unassigned',page:1});
  assert.ok(s.calls.some(c=>c[0]==='eq' && c[1]==='status' && c[2]==='completed'));
  assert.ok(s.calls.some(c=>c[0]==='is' && c[1]==='assigned_to' && c[2]===null));
  assert.equal(s.calls.some(c=>c[0]==='in'),false);
});
test('database failure is not presented as an empty queue', async () => {
  const s = service({error:{message:'failure'}});
  await assert.rejects(s.getFollowUpWorklist({view:'open',owner:'all',page:1}), /Unable to load follow-ups/);
});

test('worklist shows selected filters and links directly to a task action card', () => {
  const worklistPage = readFileSync(new URL('../../app/dashboard/follow-ups/page.tsx', import.meta.url), 'utf8');
  const operationalOverview = readFileSync(new URL('../../components/leads/LeadOperationalOverview.tsx', import.meta.url), 'utf8');
  assert.match(worklistPage, /aria-label="Selected filters"/);
  assert.match(worklistPage, /bg-cyan-400\/15/);
  assert.match(worklistPage, /#follow-up-task-\$\{task\.id\}/);
  assert.match(operationalOverview, /id=\{`follow-up-task-\$\{task\.id\}`\}/);
});
