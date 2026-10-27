import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
function load(path, require = () => ({})) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(readFileSync(new URL(path, import.meta.url), 'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText, {exports,require,URLSearchParams});
  return exports;
}
const routing = load('../../lib/auth/recovery-routing.ts');
test('expired error takes precedence over code and discards untrusted error text', () => {
  assert.equal(routing.recoveryLandingDestination(new URLSearchParams('error_code=otp_expired&code=secret&error_description=unsafe')), routing.RECOVERY_ERROR_PATH);
});
test('normal homepage remains normal; fallback code only targets local password callback', () => {
  assert.equal(routing.recoveryLandingDestination(new URLSearchParams('utm_source=email')), null);
  const path = routing.recoveryLandingDestination(new URLSearchParams('code=a%26b&next=https://evil.example'));
  assert.equal(path, '/auth/callback?code=a%26b&next=%2Fupdate-password');
});
function setup(result, fails = false) {
  const calls=[];
  const action=load('../../app/auth/recovery/actions.ts', name => {
    if (name.includes('recovery-routing')) return routing;
    if (name==='next/navigation') return {redirect:path=>{throw new Error(`REDIRECT:${path}`);}};
    if (name.includes('supabase/server')) return {createClient:async()=>({auth:{verifyOtp:async input=>{calls.push(input);if(fails) throw new Error('network');return result;}}})};
    throw new Error(name);
  });
  return {...action,calls};
}
test('malformed and missing token never reach provider', async () => {
  for(const token of [null,'', 'bad token', 'https://evil.example']) {
    const s=setup({});const form=new FormData();if(token!==null)form.set('token_hash',token);
    await assert.rejects(s.confirmPasswordRecovery(form), /recovery-link-invalid/);assert.equal(s.calls.length,0);
  }
});
test('successful verification uses recovery type only and a fixed password destination', async () => {
  const s=setup({data:{user:{id:'test'},session:{access_token:'synthetic'}},error:null});
  const form=new FormData();form.set('token_hash','a'.repeat(64));form.set('type','signup');form.set('next','https://evil.example');
  await assert.rejects(s.confirmPasswordRecovery(form), /REDIRECT:\/update-password$/);
  assert.equal(s.calls[0].type,'recovery');assert.equal(s.calls.length,1);
});
test('expired, consumed, sessionless and network failures cannot open password form', async () => {
  for(const [result,fails] of [[{data:{},error:{code:'otp_expired'}},false],[{data:{user:{id:'test'},session:null},error:null},false],[null,true]]) {
    const s=setup(result,fails);const form=new FormData();form.set('token_hash','b'.repeat(64));
    await assert.rejects(s.confirmPasswordRecovery(form), /recovery-link-invalid/);
  }
});
