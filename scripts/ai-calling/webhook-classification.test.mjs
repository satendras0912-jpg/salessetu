import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
const exports = {};
const source = readFileSync(new URL('../../lib/ai-calling/webhook-classification.ts', import.meta.url), 'utf8');
vm.runInNewContext(ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText, {exports});
const review = exports.needsCallClassificationReview;
test('machine-labelled interactive transcript requires review', () => {
  assert.equal(review({concatenated_transcript:'assistant: Hello\n user: Yes\n assistant: Preference?\n user: Please send details'},'voicemail'),true);
});
test('completion or duration alone never overrides voicemail', () => {
  assert.equal(review({completed:true,call_length:300,concatenated_transcript:'assistant: Hello'},'voicemail'),false);
});
test('single greeting and punctuation do not establish conflicting conversation', () => {
  assert.equal(review({concatenated_transcript:'user: Leave a message\nuser: ...'},'voicemail'),false);
});
test('structured Hindi caller turns are supported without double counting arrays', () => {
  const transcripts=[{user:'user',text:'हाँ'},{user:'user',text:'जानकारी भेजिए'}];
  assert.equal(review({transcripts},'voicemail'),true);
  assert.equal(review({transcripts:transcripts.slice(0,1),corrected_transcript:transcripts.slice(0,1)},'voicemail'),false);
});
test('completed, busy and no-answer outcomes are not changed', () => {
  for(const status of ['completed','busy','no_answer','failed']) assert.equal(review({concatenated_transcript:'user: Yes\nuser: Thanks'},status),false);
});
test('malformed segments are ignored', () => {
  assert.equal(review({transcripts:[null,[],{role:'assistant',text:'Hello'},{role:'user',text:42}]},'voicemail'),false);
});
