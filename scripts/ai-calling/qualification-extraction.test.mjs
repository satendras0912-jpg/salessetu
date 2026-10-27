import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
const exports = {};
const source = readFileSync(new URL('../../lib/ai-calling/qualification-extraction.ts', import.meta.url), 'utf8');
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText, { exports });
const { normalizeAnswer, buildExtractionQuestion } = exports;
const question = (code, extra = {}) => ({ question_code: code, question_text: 'Question?', question_type: 'single_choice', extraction_instructions: null, options: [], validation_rules: {}, ...extra });
test('missing and whitespace-only responses stay missing', () => {
  for (const answer of [null, '', '  ', '\n\t']) assert.equal(normalizeAnswer(answer), null);
});
test('negative and zero responses are not erased or guessed', () => {
  assert.equal(normalizeAnswer(false), false);
  assert.equal(normalizeAnswer(0), 0);
  assert.equal(normalizeAnswer(' send_details '), 'send_details');
  assert.equal(normalizeAnswer('Greater Northern West'), 'Greater Northern West');
});
test('configured codes and extraction guidance remain in the analysis request', () => {
  const prompt = buildExtractionQuestion(question('purchase_timeline', { validation_rules: { allowed_values: ['within_3_months'] }, extraction_instructions: 'Use months.' }));
  assert.match(prompt, /within_3_months/);
  assert.match(prompt, /Use months/);
  assert.match(prompt, /two to three months/);
  assert.match(prompt, /Never fill missing answers from previous calls/);
});
test('budget prompt distinguishes total price from down payment and converts units', () => {
  const prompt = buildExtractionQuestion(question('budget_range'));
  assert.match(prompt, /1 crore = 10000000 INR/);
  assert.match(prompt, /only a down payment is stated, leave total budget unknown/);
});
test('details-first and unanswered BHK do not become visit agreement or inferred BHK', () => {
  assert.match(buildExtractionQuestion(question('site_visit_interest')), /return send_details/);
  assert.match(buildExtractionQuestion(question('unit_preference')), /Do not infer BHK/);
});
