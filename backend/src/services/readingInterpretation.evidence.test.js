const test = require('node:test');
const assert = require('node:assert/strict');
const { MODE_PROMPTS, buildReadingMessages, verifyDirectQuotes } = require('./readingInterpretation');
const suite = require('../../../tool/xiaou_reading_eval/cases.v1.json');

let networkAttempts = 0;
global.fetch = async () => { networkAttempts++; throw Error('Offline evidence tests forbid model calls'); };

for (const mode of Object.keys(MODE_PROMPTS)) {
  test(`${mode}: source absence, contrary evidence and author denial remain distinct common constraints`, () => {
    const { messages } = buildReadingMessages({ mode, selectedText: '现有资料尚不能确定路灯是否降低事故率。' });
    const system = messages[0].content;
    for (const clause of [
      '本次材料不足以确认A，不据此确认非A',
      '须有实际支持相反判断的证据，结论限于该证据范围',
      '作者的断言本身不等于已经独立证实非A',
      '不能因为A尚未证实，就说A已被证伪、排除或原文明示为假',
      '不能把原文确有的反证或明确否定一律弱化成未知',
      '撤回“已经证明”的断言',
      '不能借纠错断言A或相关因果关系已经被排除',
      '不新增分类栏目、不要求复述固定话术',
    ]) assert(system.includes(clause));
    assert(system.includes(MODE_PROMPTS[mode]));
  });
}

// Original synthetic regression pairs. Expected readings are review notes, never model input.
const examples = [
  { name: 'causal evidence missing', source: '增设路灯后事故减少，但同期也降低了限速；尚不能确定路灯单独造成改善。',
    expected: '不能确认单独归因，也未证明路灯无作用。', wrong: '已经排除路灯造成改善。' },
  { name: 'not detected is not absent', source: '本次没有检测到该信号，但仪器可能漏检，不能断定信号不存在。',
    expected: '未检出不能推出不存在。', wrong: '测量已经证明信号不存在。' },
  { name: 'actual counterexample, bounded claim', source: '命题是这批零件全部为铜；检验确认这批中的7号零件为铁而非铜，因此该全称命题不成立。',
    expected: '反例否定全部为铜，不能扩大为全部不是铜。', wrong: '仍不能判断这批是否全部为铜。' },
  { name: 'author denial without independent proof', source: '作者明确写道：我否认这个传闻；此段未给出查证材料。',
    expected: '可以确认作者否认传闻，不能因此确认传闻已被事实证伪。', wrong: '作者的否认已经证明传闻虚假。' },
  { name: 'necessary condition unknown', source: '只有通过验收才可开放。此处未提供是否通过验收的记录。',
    expected: '验收情况未知，不能推出已通过、未通过或不可开放。', wrong: '没有记录就说明没通过，必须不可开放。' },
  { name: 'necessary condition explicitly false', source: '只有通过验收才可开放。记录确认该场馆未通过验收。',
    expected: '按该规则，该场馆不可开放。', wrong: '即使确认未通过，也只能说不知道是否可开放。' },
  { name: 'necessary condition true, sufficiency unproven', source: '只有通过验收才可开放。记录确认通过验收，但未说明其他要求。',
    expected: '通过必要条件既不保证可开放，也不证明不可开放。', wrong: '没有充分性证明就已经证明不可开放。' },
];

for (const example of examples) {
  test(`${example.name}: exact source, wrong AI and reader question stay separate`, () => {
    const body = { mode: 'argument', selectedText: example.source, initialAnswer: example.wrong,
      history: [{ role: 'user', content: '请解释材料' }, { role: 'assistant', content: example.wrong }],
      message: '请核对刚才的结论是否超出了原文依据。' };
    const reading = buildReadingMessages(body);
    const source = reading.material.segments[0];
    assert.equal(source.text, example.source);
    assert.equal(source.kind, 'book_text');
    assert.equal(reading.material.discussion.initial_ai_answer.text, example.wrong);
    assert.equal(reading.material.discussion.initial_ai_answer.kind, 'ai_answer_not_source');
    assert.equal(reading.messages.at(-1).content, body.message);
    assert(!JSON.stringify(reading.messages).includes(example.expected));
    verifyDirectQuotes(`原文：“${example.source}”`, reading.material);
    assert.throws(() => verifyDirectQuotes(`原文：“${example.wrong}”`, reading.material));
  });
}

test('countermodels distinguish unknown from false and retain valid contraposition', () => {
  // These finite logical models validate fixtures, not natural-language model answers.
  const worlds = [false, true].flatMap(a => [false, true].map(b => ({ a, b })));
  const necessary = worlds.filter(w => !w.b || w.a); // B implies A.
  assert.deepEqual(new Set(necessary.map(w => w.b)), new Set([false, true]));
  assert(necessary.filter(w => !w.a).every(w => !w.b));
  assert.deepEqual(new Set(necessary.filter(w => w.a).map(w => w.b)), new Set([false, true]));
  const unproven = [{ claim: true }, { claim: false }];
  assert.equal(unproven.every(w => !w.claim), false);
  const withCounterexample = unproven.filter(w => !w.claim);
  assert(withCounterexample.every(w => !w.claim));
  const authorDenies = unproven.map(w => ({ ...w, authorDenies: true }));
  assert.equal(authorDenies.every(w => !w.claim), false);
  const system = buildReadingMessages({ selectedText: examples[4].source }).messages[0].content;
  assert(system.includes('必要条件是否满足尚未知时，不能当成已经不满足'));
  assert(system.includes('必要条件未满足时，可依原文条件推出相应结论不成立'));
  assert(system.includes('缺少充分性的证明不等于已有不充分的证明'));
});

test('PLAIN-02 and ARGUMENT-04 receive new correction constraints without changing fixed evidence', () => {
  for (const id of ['PLAIN-02', 'ARGUMENT-04']) {
    const item = suite.cases.find(row => row.id === id);
    const wrong = item.seed_answer || '原文明确否定了读书角导致迟到下降。';
    const reading = buildReadingMessages({ ...item.request, initialAnswer: wrong,
      message: item.follow_ups?.[0].question || '尚不能确认，能说成已经排除吗？' });
    assert.equal(reading.material.segments[0].text, item.request.selectedText);
    assert(!JSON.stringify(reading.messages).includes(item.expected.reference_answer));
    assert(reading.messages[0].content.includes('若旧AI声称“已经证明A”，而原文只说“尚不能确定A”'));
    assert(reading.messages[0].content.includes('若需纠错，先明确更正并给原文依据'));
    assert(reading.messages[0].content.includes('不要用“原文明确否定了这个结论”'));
  }
  assert.equal(networkAttempts, 0);
});
