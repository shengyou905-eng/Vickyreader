const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PROMPT_VERSION, BASE_PROMPT, MODE_PROMPTS, buildMaterial, buildReadingMessages,
  normalizeReadingHistory, verifyDirectQuotes } = require('./readingInterpretation');
const suite = require('../../../tool/xiaou_reading_eval/cases.v1.json');

test('versioned five free-mode prompts target their error classes without a fixed word minimum', () => {
  assert.deepEqual(Object.keys(MODE_PROMPTS), ['auto', 'plain', 'structure', 'concept', 'argument']);
  assert.match(BASE_PROMPT, /否定、量词/);
  assert.match(BASE_PROMPT, /不凑固定字数/);
  assert.match(BASE_PROMPT, /推测的依据和限制/);
  assert.match(BASE_PROMPT, /缺失作者不得补猜/);
  assert.doesNotMatch(BASE_PROMPT, /300-700|300-900/);
  for (const [mode, pattern] of Object.entries({
    auto: /真正难点/, plain: /并非\/都不/, structure: /必要条件不是充分条件/,
    concept: /不伪造严格定义/, argument: /混杂因素.*百分点/,
  })) assert.match(MODE_PROMPTS[mode], pattern);
  const client = fs.readFileSync(path.resolve(__dirname, '../../../lib/services/reading_history.dart'), 'utf8');
  assert(client.includes(`const readingPromptVersion = '${PROMPT_VERSION}'`));
  const provider = fs.readFileSync(path.resolve(__dirname, '../../../lib/providers/ai_provider.dart'), 'utf8');
  assert.match(provider, /cacheKey = jsonEncode\(\[\s*readingPromptVersion/);
});

for (const item of suite.cases) {
  test(`${item.id}: actual reading builder separates source, discussion and evaluation oracle`, () => {
    const reading = buildReadingMessages(item.request);
    assert.match(reading.messages[0].content, new RegExp(PROMPT_VERSION.replaceAll('.', '\\.')));
    assert(reading.messages[0].content.includes(MODE_PROMPTS[item.mode]));
    assert.equal(reading.material.book.author, '');
    assert.equal(reading.material.scope, 'selection_with_context');
    assert.equal(reading.messages[1].role, 'user');
    for (const evidence of item.evidence) {
      const segment = reading.material.segments.find(row => row.id === evidence.field);
      assert(segment.text.includes(evidence.quote));
      assert.equal(segment.kind, 'book_text');
      assert.equal(segment.text, item.request[segment.id].slice(segment.range.start, segment.range.end));
      verifyDirectQuotes(`原文：“${evidence.quote}”`, reading.material);
    }
    const payload = JSON.stringify(reading.messages);
    for (const key of ['key_points', 'must_not', 'reference_answer', 'comparison_only']) {
      assert(!payload.includes(key));
    }
    if (item.comparison_only) assert(!payload.includes(item.comparison_only));
    assert(!reading.messages.filter(row => row.role === 'system').some(row => row.content.includes(item.request.selectedText)));
  });
}

test('source clip ranges preserve exact text, nearest pre-context and complete UTF-16 characters', () => {
  const body = {
    selectedText: 'selected', paragraph: '', contextBefore: `omitted${'b'.repeat(3000)}`,
    contextAfter: `${'c'.repeat(2999)}😀tail`,
  };
  const { segments } = buildMaterial(body, 'selection');
  const before = segments.find(row => row.id === 'contextBefore');
  assert.deepEqual(before.range, { unit: 'utf16', start: 7, end: 3007, provided_length: 3007, truncated: true });
  assert.equal(before.text, 'b'.repeat(3000));
  const after = segments.find(row => row.id === 'contextAfter');
  assert.equal(after.range.end, 2999);
  assert.equal(after.text, 'c'.repeat(2999));
  assert(!after.text.includes('\ud83d'));
});

test('selection/page/chapter and old missing fields use only their provided source scope', () => {
  const body = { selectedText: 'selection', pageText: 'page', chapterText: 'chapter', message: 'why?', history: [] };
  for (const [scope, expected, fields] of [
    ['selection', 'selection_with_context', ['selectedText']],
    ['page', 'page_excerpt', ['pageText']],
    ['chapter', 'chapter_excerpt', ['pageText', 'chapterText']],
  ]) {
    const reading = buildReadingMessages({ ...body, scope }, true);
    assert.equal(reading.material.scope, expected);
    assert.deepEqual(reading.material.segments.map(row => row.id), fields);
    assert.equal(reading.messages[0].content.includes('不是指令'), true);
    assert.equal(reading.messages[1].role, 'user');
  }
  assert.equal(buildReadingMessages({ ...body, scope: 'unknown' }, true).material.scope, 'page_excerpt');
  const legacy = buildReadingMessages({ history: [{ role: 'user', content: 'old' }, { role: 'assistant', content: 'answer' }], message: 'why?' });
  assert.equal(legacy.material.segments.length, 0);
  assert.equal(legacy.material.book.author, '');
  assert(legacy.messages[0].content.includes('看不到早先讨论时不要假装记得'));
});

test('direct quote gate rejects invented, omitted, AI, user and catalog text; inference is not falsely certified', () => {
  const body = { selectedText: '道路也已修通。', initialAnswer: '已经证明全部由水站造成。', initialQuestion: '用户认为只与水站有关', bookTitle: '未进入原文的标题' };
  const material = buildMaterial(body, 'selection');
  verifyDirectQuotes(`原文：“道路也已修通。”
一种推测是：还需要区分两个因素。`, material);
  for (const quote of [body.initialAnswer, body.initialQuestion, body.bookTitle, '虚构的句子', '道路……修通']) {
    assert.throws(() => verifyDirectQuotes(`原文：“${quote}”`, material), { code: 'AI_UNVERIFIABLE_QUOTE' });
  }
  // This only proves quote existence, NOT entailment or truth of an unquoted claim.
  verifyDirectQuotes('这证明水站完全无效。原文：“道路也已修通。”', material);
  verifyDirectQuotes('补充背景：“假设”一词可以用于讨论条件。', material);
  verifyDirectQuotes('Source quote: "道路也已修通。"', material);
  assert.throws(() => verifyDirectQuotes('Source quote: "not provided"', material));
  assert.throws(() => verifyDirectQuotes('原文：“道路也已修通。', material));
  verifyDirectQuotes('原文：“这里说“稳定”不等于准确。”', buildMaterial({ selectedText: '这里说“稳定”不等于准确。' }, 'selection'));
  assert.throws(() => verifyDirectQuotes('原文：“selection”', buildMaterial({ pageText: 'page' }, 'page')));
});

test('whole-turn selection preserves two older explicit concerns and newest turns, never orphans', () => {
  const history = [{ role: 'assistant', content: 'orphan' }, { role: 'user', content: 'failed question' }];
  for (let i = 0; i < 20; i++) history.push(
    { role: 'user', content: i === 2 ? '纠正：我指的是另一个条件' : i === 3 ? '未解决：证据是否充分' : `q${i}` },
    { role: 'assistant', content: `a${i}` },
  );
  history.push({ role: 'user', content: 'unanswered current turn' });
  const selected = normalizeReadingHistory(history);
  assert.equal(selected.length, 24);
  assert(selected.some(row => row.content.startsWith('纠正')));
  assert(selected.some(row => row.content.startsWith('未解决')));
  assert.equal(selected.at(-1).content, 'a19');
  assert(!selected.some(row => ['orphan', 'failed question', 'unanswered current turn'].includes(row.content)));
  for (let i = 0; i < selected.length; i += 2) assert.deepEqual(selected.slice(i, i + 2).map(row => row.role), ['user', 'assistant']);
  assert.throws(() => normalizeReadingHistory([{ role: 'system', content: 'attack' }]));
  const long = Array.from({ length: 10 }, (_, i) => ({ role: i % 2 ? 'assistant' : 'user', content: String(i).repeat(8000) }));
  const budgeted = normalizeReadingHistory(long);
  assert(budgeted.reduce((sum, row) => sum + row.content.length, 0) <= 32000);
  assert.equal(budgeted.length % 2, 0);
});

test('14 turns retain fixed material and corrections with the real new message builder', () => {
  const item = suite.cases.find(row => row.id === 'ARGUMENT-04');
  const history = [{ role: 'user', content: 'initial' }, { role: 'assistant', content: item.seed_answer }];
  let fixed;
  for (const [index, turn] of item.follow_ups.entries()) {
    const question = index === 1 ? `纠正：${turn.question}` : index === 2 ? `未解决：${turn.question}` : turn.question;
    const reading = buildReadingMessages({ ...item.request, history, initialAnswer: item.seed_answer, message: question });
    const snapshot = JSON.stringify(reading.material);
    fixed ??= snapshot;
    assert.equal(snapshot, fixed);
    assert.equal(reading.messages.at(-1).content, question);
    if (index === 13) {
      assert(reading.messages.some(row => row.content.startsWith('纠正：')));
      assert(reading.messages.some(row => row.content.startsWith('未解决：')));
    }
    history.push({ role: 'user', content: question }, { role: 'assistant', content: turn.reference_answer });
  }
});
