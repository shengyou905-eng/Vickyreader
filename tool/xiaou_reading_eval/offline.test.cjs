const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

let networkAttempts = 0;
global.fetch = async () => {
  networkAttempts++;
  throw new Error('Network is forbidden in the offline reading evaluation');
};

const { validateAiInput, normalizeHistory, explanationEvidence } =
  require('../../backend/src/services/aiProtocol');
const load = name => JSON.parse(fs.readFileSync(path.join(__dirname, name), 'utf8'));
const suite = load('cases.v1.json');
const rubric = load('rubric.v1.json');
const modes = ['auto', 'plain', 'structure', 'concept', 'argument'];
const sourceFields = new Set(['selectedText', 'paragraph', 'contextBefore', 'contextAfter']);

// Quote existence is a mechanical check, never a semantic support verdict.
function checkQuoteBindings(item, bindings) {
  return bindings.map(binding => {
    const evidence = item.evidence.find(row => row.id === binding.evidence_id);
    return Boolean(evidence && binding.field === evidence.field &&
      binding.quote === evidence.quote && item.request[evidence.field].includes(binding.quote));
  });
}

test('suite is exactly 20 original synthetic cases, four per free mode', () => {
  assert.equal(suite.schema_version, 1);
  assert.equal(suite.text_origin, 'original_synthetic');
  assert.equal(suite.network_policy, 'offline_only');
  assert.equal(suite.cases.length, 20);
  assert.equal(new Set(suite.cases.map(item => item.id)).size, 20);
  for (const mode of modes) assert.equal(suite.cases.filter(item => item.mode === mode).length, 4);
});

for (const item of suite.cases) {
  test(`${item.id}: fixture, source quotes and review expectations are coherent`, () => {
    assert(modes.includes(item.mode));
    assert.equal(item.request.mode, item.mode);
    assert(item.title && item.request.selectedText && item.request.bookTitle);
    assert.equal(item.request.bookAuthor, '');
    assert.deepEqual(item.request.history, []);
    assert.equal(item.request.initialAnswer, undefined);
    assert.equal(item.request.message, undefined);
    assert(item.tags.length >= 2);
    assert(item.expected.reference_answer.length > 20);
    assert(item.expected.key_points.length > 0);
    assert(item.expected.must_not.length > 0);
    assert(['required', 'conditional', 'not_required'].includes(item.expected.uncertainty));
    validateAiInput(item.request);
    const ids = new Set(item.evidence.map(row => row.id));
    assert.equal(ids.size, item.evidence.length);
    for (const evidence of item.evidence) {
      assert(sourceFields.has(evidence.field), 'AI/history/gold answers are not book evidence');
      assert(evidence.quote.length > 0);
      assert(item.request[evidence.field].includes(evidence.quote), `${item.id}/${evidence.id}: invalid source quote`);
    }
    for (const point of item.expected.key_points) {
      assert(point.text && point.evidence_ids.length > 0);
      for (const id of point.evidence_ids) assert(ids.has(id));
    }
    // Send only request. Evaluator expectations and comparison passages stay outside it.
    for (const forbidden of ['expected', 'evidence', 'reference_answer', 'comparison_only', 'seed_answer']) {
      assert.equal(Object.hasOwn(item.request, forbidden), false);
    }
  });
}

test('coverage includes argument, concept, exact quotes, 14 turns, uncertainty and source instructions', () => {
  const tags = new Set(suite.cases.flatMap(item => item.tags));
  for (const tag of ['complex_argument', 'concept_distinction', 'quotation', 'follow_up_14',
    'insufficient_evidence', 'instruction_in_source', 'implicit_premise', 'necessary_sufficient']) {
    assert(tags.has(tag), `missing ${tag}`);
  }
  assert(suite.cases.filter(item => item.expected.uncertainty === 'required').length >= 6);
});

test('rubric totals 100 and requires human review, semantic support and critical gates', () => {
  assert.equal(rubric.dimensions.reduce((sum, dimension) => sum + dimension.weight, 0), 100);
  assert.equal(new Set(rubric.dimensions.map(row => row.id)).size, 5);
  for (const dimension of rubric.dimensions) {
    for (const rating of rubric.rating_scale) assert(dimension.anchors[rating]);
  }
  assert.equal(rubric.proposed_gates.allowed_critical_failures, 0);
  assert.equal(rubric.review_policy.reviewers, 2);
  assert.equal(rubric.review_policy.no_keyword_only_semantic_scoring, true);
});

test('mock quote bindings reject invented quotes and wrong evidence identity', () => {
  const item = suite.cases.find(row => row.id === 'ARGUMENT-02');
  assert.deepEqual(checkQuoteBindings(item, [
    { evidence_id: 'E1', field: 'selectedText', quote: item.evidence[0].quote },
    { evidence_id: 'E1', field: 'selectedText', quote: '随机试验证明新教材完全无效' },
    { evidence_id: 'E99', field: 'selectedText', quote: item.evidence[0].quote },
    { evidence_id: 'E1', field: 'initialAnswer', quote: item.evidence[0].quote },
  ]), [true, false, false, false]);
});

test('a genuine quote does not automatically validate a false attached claim', () => {
  const item = suite.cases.find(row => row.id === 'ARGUMENT-02');
  const mock = {
    claim: '这些证据已经证明新教材完全无效。',
    evidence_id: 'E1', field: 'selectedText', quote: item.evidence[0].quote,
    semantic_review_required: true,
  };
  assert.deepEqual(checkQuoteBindings(item, [mock]), [true]);
  assert.equal(mock.semantic_review_required, true);
  assert(item.expected.must_not.includes('断言新教材无效。'));
});

test('14 mock turns keep fixed source and mode under the current backend history contract', () => {
  const item = suite.cases.find(row => row.id === 'ARGUMENT-04');
  assert.equal(item.follow_ups.length, 14);
  assert.equal(item.seed_answer_status, 'deliberately_incorrect_ai_output_for_mock_replay_only');
  const fixed = { ...item.request, initialAnswer: item.seed_answer };
  const frozenSource = explanationEvidence(fixed);
  const history = [
    { role: 'user', content: '请按论证模式解读所选文字。' },
    { role: 'assistant', content: item.seed_answer },
  ];
  let trimmed = false;
  for (const turn of item.follow_ups) {
    // Reference replies simulate transport history only, not actual model performance.
    const body = { ...fixed, history: history.slice(-24), message: turn.question };
    validateAiInput(body);
    const normalized = normalizeHistory(body.history);
    assert(normalized.length <= 24);
    trimmed ||= normalized.length < history.length;
    assert.equal(explanationEvidence(body), frozenSource);
    assert.equal(body.mode, 'argument');
    assert.equal(body.bookTitle, item.request.bookTitle);
    assert.equal(body.chapterTitle, item.request.chapterTitle);
    assert(explanationEvidence(body).includes('首轮AI解释，不是原文证据'));
    assert(turn.checks.length > 0);
    assert.equal(Object.hasOwn(body, 'expected'), false);
    history.push({ role: 'user', content: turn.question });
    history.push({ role: 'assistant', content: turn.reference_answer });
  }
  assert.equal(trimmed, true);
  assert(history.at(-1).content.includes(item.evidence[1].quote));
});

test('quote/protocol checks run with zero fetch attempts; provenance is reproducible', () => {
  assert.equal(networkAttempts, 0);
  for (const file of ['cases.v1.json', 'rubric.v1.json', '../../backend/src/services/aiProtocol.js',
    '../../backend/src/controllers/ai.controller.js', '../../backend/src/services/readingInterpretation.js']) {
    const hash = crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname, file))).digest('hex');
    assert.equal(hash.length, 64);
    console.log(`SHA256 ${file} ${hash}`);
  }
});
