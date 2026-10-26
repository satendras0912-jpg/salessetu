import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import test from 'node:test';
import assert from 'node:assert/strict';

const base = readFileSync(new URL('../../supabase/migrations/010_ai_calling_engine.sql', import.meta.url), 'utf8');
const migration = readFileSync(new URL('../../supabase/migrations/20261025120000_ai_call_dispatch_guard.sql', import.meta.url), 'utf8');
const org = '00000000-0000-4000-8000-000000000001';
const otherOrg = '00000000-0000-4000-8000-000000000002';
const phone = '+12025550123'; // Reserved fictional NANP number; never called.
let db;
const query = async (sql, params = []) => (await db.query(sql, params)).rows;
const one = async (sql, params = []) => (await query(sql, params))[0];
const extractFunction = name => base.slice(base.indexOf(`create or replace function public.${name}(`)).split('$$;')[0] + '$$;';

test('database dispatch guards (real PL/pgSQL, isolated in-memory PostgreSQL)', async t => {
  db = new PGlite();
  try {
    await db.exec(`create role authenticated; create role service_role; create schema auth;
      create function auth.role() returns text language sql as $$ select current_setting('test.auth_role', true) $$;
      create function public.has_organization_permission(uuid,text) returns boolean language sql as $$ select false $$;
      set test.auth_role = 'service_role';`);
    // Use repository table definitions/check constraints. External foreign keys
    // are removed only in this fixture; RLS/deployed schema need integration QA.
    for (const match of base.matchAll(/create table if not exists public\.ai_call_\w+ \([\s\S]*?\n\);/g)) {
      await db.exec(match[0].replace(/ references [\w.]+\([\w]+\) on delete (?:set null|cascade|restrict)/g, ''));
    }
    await db.exec(extractFunction('normalize_ai_call_phone'));
    await db.exec(migration);
    await db.exec(readFileSync(new URL('../../supabase/migrations/20261026180000_ai_call_classification_review.sql', import.meta.url), 'utf8'));
    const provider = await one("insert into ai_call_providers(provider_code,provider_name) values ('test','Test') returning id");
    const connection = await one('insert into ai_call_provider_connections(organization_id,provider_id,connection_name) values ($1,$2,\'Test\') returning id', [org, provider.id]);
    const script = await one("insert into ai_call_script_templates(organization_id,template_code,template_name,opening_message,system_prompt,status) values ($1,'test','Test','Test','Test','active') returning id", [org]);
    async function setup() {
      await db.exec('truncate ai_call_jobs, ai_call_attempts, ai_call_attempt_events, ai_call_consents, ai_call_suppression_list');
      const job = await one("insert into ai_call_jobs(organization_id,provider_connection_id,script_template_id,phone_number,status) values ($1,$2,$3,$4,'queued') returning id", [org, connection.id, script.id, phone]);
      await query("insert into ai_call_consents(organization_id,phone_number,consent_status,created_at) values ($1,$2,'granted',now()-interval '1 day')", [org, phone]);
      await query('select public.claim_ai_call_job(\'test\',$1)', [org]);
      const attempt = await one('select (public.start_ai_call_attempt($1)).id', [job.id]);
      return { job: job.id, attempt: attempt.id };
    }
    async function authorize(attempt) {
      return (await one('select public.authorize_ai_call_dispatch($1) as result', [attempt])).result;
    }
    for (const status of ['withdrawn','denied','unknown']) await t.test(`${status} after queue blocks dispatch`, async () => {
      const { job, attempt } = await setup();
      await query('insert into ai_call_consents(organization_id,phone_number,consent_status) values ($1,$2,$3)', [org,phone,status]);
      assert.equal((await authorize(attempt)).authorized, false);
      assert.equal((await one('select status from ai_call_jobs where id=$1',[job])).status,'blocked');
    });
    await t.test('expired latest grant cannot fall back to an older unexpired grant', async () => {
      const { attempt } = await setup();
      await query("insert into ai_call_consents(organization_id,phone_number,consent_status,expires_at) values ($1,$2,'granted',now()-interval '1 minute')",[org,phone]);
      assert.equal((await authorize(attempt)).authorized,false);
    });
    await t.test('suppression after queue blocks dispatch', async () => {
      const { attempt } = await setup();
      await query("insert into ai_call_suppression_list(organization_id,phone_number,suppression_type) values ($1,$2,'do_not_call')",[org,phone]);
      assert.equal((await authorize(attempt)).authorized,false);
    });
    await t.test('expired job blocks dispatch', async () => {
      const { job, attempt } = await setup();
      await query("update ai_call_jobs set expires_at=now()-interval '1 second' where id=$1",[job]);
      assert.equal((await authorize(attempt)).authorized,false);
    });
    await t.test('inactive provider blocks dispatch', async () => {
      const { attempt } = await setup();
      await query("update ai_call_providers set status='inactive' where id=$1",[provider.id]);
      assert.equal((await authorize(attempt)).authorized,false);
      await query("update ai_call_providers set status='active' where id=$1",[provider.id]);
    });
    await t.test('campaign calling window is rechecked after queue', async () => {
      const { job, attempt } = await setup();
      const campaign = await one("insert into ai_call_campaigns(organization_id,campaign_code,campaign_name,provider_connection_id,script_template_id,status,timezone,calling_window_start,calling_window_end,allowed_weekdays) values ($1,'test','Test',$2,$3,'active','UTC','00:00','00:00',array[1,2,3,4,5,6,7]::smallint[]) returning id",[org,connection.id,script.id]);
      await query('update ai_call_jobs set campaign_id=$1 where id=$2',[campaign.id,job]);
      assert.equal((await authorize(attempt)).authorized,false);
    });
    await t.test('conflicting voicemail is held atomically and duplicates cannot release it', async () => {
      const { job, attempt } = await setup();
      await query("select public.complete_ai_call_attempt($1,'voicemail',requested_result_data => '{\"classification_review_required\":true}'::jsonb)", [attempt]);
      assert.deepEqual(await one('select status, next_attempt_at, dispatch_requires_reconciliation, qualification_status from ai_call_jobs where id=$1',[job]), {status:'blocked',next_attempt_at:null,dispatch_requires_reconciliation:true,qualification_status:'manual_review'});
      await query("select public.complete_ai_call_attempt($1,'completed')", [attempt]);
      assert.equal((await one('select status from ai_call_jobs where id=$1',[job])).status,'blocked');
      assert.equal((await one("select (public.claim_ai_call_job('test',$1)).id",[org])).id,null);
    });
    await t.test('ordinary voicemail keeps the existing retry policy', async () => {
      const { job, attempt } = await setup();
      await query("select public.complete_ai_call_attempt($1,'voicemail')", [attempt]);
      const row = await one('select status, next_attempt_at, dispatch_requires_reconciliation from ai_call_jobs where id=$1',[job]);
      assert.equal(row.status,'scheduled');
      assert.ok(row.next_attempt_at);
      assert.equal(row.dispatch_requires_reconciliation,false);
    });
    await t.test('known acceptance releases hold and keeps job out of queue', async () => {
      const { job, attempt } = await setup();
      await authorize(attempt);
      await query("select public.mark_ai_call_initiated($1,'synthetic-call')",[attempt]);
      assert.deepEqual(await one('select status, dispatch_requires_reconciliation from ai_call_jobs where id=$1',[job]), {status:'in_progress',dispatch_requires_reconciliation:false});
      assert.equal((await one("select (public.claim_ai_call_job('test',$1)).id",[org])).id,null);
    });
    await t.test('cross-organization connection blocks dispatch', async () => {
      const { attempt } = await setup();
      await query('update ai_call_provider_connections set organization_id=$1 where id=$2',[otherOrg,connection.id]);
      assert.equal((await authorize(attempt)).authorized,false);
      await query('update ai_call_provider_connections set organization_id=$1 where id=$2',[org,connection.id]);
    });
    await t.test('durable hold survives requeue; repeat authorization and start are refused', async () => {
      const { job, attempt } = await setup();
      assert.equal((await authorize(attempt)).authorized,true);
      assert.equal((await authorize(attempt)).authorized,false);
      await assert.rejects(query('select public.start_ai_call_attempt($1)',[job]), /reconciled/);
      await query("update ai_call_jobs set status='queued' where id=$1",[job]);
      assert.equal((await one("select (public.claim_ai_call_job('test',$1)).id",[org])).id,null);
      assert.equal((await one('select dispatch_requires_reconciliation from ai_call_jobs where id=$1',[job])).dispatch_requires_reconciliation,true);
    });
    await t.test('terminal webhook clears hold; late initiation and duplicate completion do not regress it', async () => {
      const { job, attempt } = await setup();
      await authorize(attempt);
      await query("select public.complete_ai_call_attempt($1,'completed')",[attempt]);
      await query("select public.mark_ai_call_initiated($1,'synthetic-call')",[attempt]);
      await query("select public.complete_ai_call_attempt($1,'failed')",[attempt]);
      const row = await one('select status, dispatch_requires_reconciliation from ai_call_jobs where id=$1',[job]);
      assert.deepEqual(row,{status:'completed',dispatch_requires_reconciliation:false});
    });
    await t.test('duplicate old webhook cannot clear next attempt hold', async () => {
      const { job, attempt } = await setup();
      await authorize(attempt);
      await query("select public.complete_ai_call_attempt($1,'no_answer')",[attempt]);
      const next = await one('select (public.start_ai_call_attempt($1)).id',[job]);
      await authorize(next.id);
      await query("select public.complete_ai_call_attempt($1,'no_answer')",[attempt]);
      assert.equal((await one('select dispatch_requires_reconciliation from ai_call_jobs where id=$1',[job])).dispatch_requires_reconciliation,true);
    });
    await t.test('authenticated clients cannot authorize or assert provider completion', async () => {
      const { attempt } = await setup();
      await db.exec("set test.auth_role='authenticated'");
      await assert.rejects(authorize(attempt), /Permission denied/);
      await assert.rejects(query("select public.complete_ai_call_attempt($1,'completed')",[attempt]), /Permission denied/);
      await assert.rejects(query("select public.mark_ai_call_initiated($1,'fake')",[attempt]), /Permission denied/);
      await db.exec("set test.auth_role='service_role'");
    });
  } finally { await db.close(); }
});
