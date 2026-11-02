const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { BASE_PROMPT, MODE_PROMPTS, PROMPT_VERSION, buildReadingMessages, verifyDirectQuotes } = require('./readingInterpretation');
const suite = require('../../../tool/xiaou_reading_eval/cases.v1.json');

let networkAttempts = 0;
global.fetch = async () => { networkAttempts++; throw new Error('Offline refinement tests must not call a model'); };

for (const mode of Object.keys(MODE_PROMPTS)) {
  test(`${mode}: necessary and sufficient conditions are common rules, not structure-only guidance`, () => {
    const { messages } = buildReadingMessages({ selectedText: '只有持票才可入馆。', mode });
    const system = messages[0].content;
    assert(system.includes('“只有A才B”表示 B=>A'));
    assert(system.includes('A成立不保证B'));
    assert(system.includes('不能改成“只要A就B”'));
    assert(system.includes('“只要A就B”表示 A=>B，不能反推 B=>A'));
    assert(system.includes('只有原文明示双向成立（如“当且仅当”或分别给出两个方向），才按双向条件理解'));
    assert(system.includes('允许“已预约但仍不可入馆”'));
    assert(system.includes('不允许“未预约却可入馆”'));
    assert(system.includes(MODE_PROMPTS[mode]));
  });
}

// Truth tables validate the counterexamples, not a model's generated interpretation.
for (const example of [
  { source: '只有持票才可入馆。', a: '持票', b: '可入馆', rule: (a, b) => !b || a, witness: [true, false], converse: (a, b) => !a || b },
  { source: '只有目标明确且误差可接受，计算才足以支持选择。', a: '目标明确且误差可接受', b: '计算足以支持选择', rule: (a, b) => !b || a, witness: [true, false], converse: (a, b) => !a || b },
  { source: '只要传感器报警，系统就会留下记录。', a: '传感器报警', b: '系统留下记录', rule: (a, b) => !a || b, witness: [false, true], converse: (a, b) => !b || a },
]) {
  test(`countermodel: ${example.source} does not license its converse`, () => {
    const worlds = [false, true].flatMap(a => [false, true].map(b => [a, b]));
    assert.equal(worlds.filter(([a, b]) => example.rule(a, b)).length, 3);
    assert.equal(example.rule(...example.witness), true);
    assert.equal(example.converse(...example.witness), false);
    const reading = buildReadingMessages({ mode: 'auto', selectedText: example.source });
    assert.equal(reading.material.segments[0].text, example.source);
    assert(reading.messages[0].content.includes('B=>A'));
    assert(!JSON.stringify(reading.messages).includes('witness'));
  });
}

test('AUTO-01 keeps its actual evidence and forbids the sufficient-condition shortcut without gold injection', () => {
  const item = suite.cases.find(row => row.id === 'AUTO-01');
  const reading = buildReadingMessages(item.request);
  assert.equal(reading.material.segments.length, 1);
  assert.equal(reading.material.segments[0].text, item.request.selectedText);
  assert(reading.messages[0].content.includes('A成立不保证B'));
  assert(reading.messages[0].content.includes('没有提供选区前后的原文'));
  assert.doesNotMatch(reading.messages.at(-1).content, /结合|前后文/);
  assert(!JSON.stringify(reading.messages).includes(item.expected.reference_answer));
});

test('scope guidance follows nonempty source segments, not a generic request to use surrounding text', () => {
  for (const [extra, present, absent] of [
    [{}, ['没有提供选区前后的原文'], ['另有选区前的原文', '另有选区后的原文']],
    [{ contextBefore: ' \n ', contextAfter: '\t' }, ['没有提供选区前后的原文'], ['另有选区前的原文']],
    [{ contextBefore: '前段真实原文' }, ['另有选区前的原文'], ['另有选区后的原文']],
    [{ contextAfter: '后段真实原文' }, ['另有选区后的原文'], ['另有选区前的原文']],
    [{ contextBefore: '前段真实原文', contextAfter: '后段真实原文' }, ['另有选区前的原文、选区后的原文'], ['没有提供选区前后的原文']],
    [{ paragraph: '段落中有本次选区原文' }, ['另有所处段落供核对', '没有单独提供选区前后的原文'], ['另有选区前的原文']],
  ]) {
    const reading = buildReadingMessages({ selectedText: '本次选区原文', ...extra });
    for (const text of present) assert(reading.messages[0].content.includes(text));
    for (const text of absent) assert(!reading.messages[0].content.includes(text));
    for (const segment of reading.material.segments) {
      const source = segment.id === 'selectedText' ? '本次选区原文' : extra[segment.id];
      assert.equal(segment.text, source.slice(segment.range.start, segment.range.end));
      assert(!reading.messages[0].content.includes(segment.text));
    }
    assert.doesNotMatch(reading.messages.at(-1).content, /结合|前后文/);
  }
});

test('page, chapter, and missing legacy evidence do not claim an entire chapter or invent source', () => {
  for (const [scope, marker] of [['page', '只提供当前页面片段'], ['chapter', '提供章节片段，不保证整章']]) {
    const question = '这句话是什么意思？';
    const reading = buildReadingMessages({ scope, pageText: '页面原文', chapterText: '章节原文', message: question }, true);
    assert(reading.messages[0].content.includes(marker));
    assert(!reading.messages[0].content.includes('另有选区前的原文'));
    assert.equal(reading.messages.at(-1).content, question);
  }
  const legacy = buildReadingMessages({ message: '请纠正之前的解释', initialAnswer: '旧AI断言', bookTitle: '标题不作原文' });
  assert(legacy.messages[0].content.includes('没有提供可核对的书籍原文'));
  assert.equal(legacy.material.segments.length, 0);
  assert.throws(() => verifyDirectQuotes('原文：“旧AI断言”', legacy.material));
});

test('internal evidence labels stay in the input but must not be narrated or stripped out of actual source', () => {
  assert.match(BASE_PROMPT, /证据分层只供内部识别，不向读者展示 book_text/);
  assert.match(BASE_PROMPT, /不清点空字段、空历史或材料封装/);
  assert.match(BASE_PROMPT, /若原文本身讨论这些技术概念，仍可正常解释和逐字引用，不删改原文/);
  const source = 'JSON 中的 book_text 是字段名，UTF-16 是字符编码方式。';
  const { material, messages } = buildReadingMessages({ selectedText: source, mode: 'plain', initialAnswer: '旧AI不是原文' });
  assert.equal(material.segments[0].kind, 'book_text');
  assert.equal(material.book.kind, 'catalog_metadata');
  assert.equal(material.discussion.initial_ai_answer.kind, 'ai_answer_not_source');
  assert(messages[1].content.includes(source));
  verifyDirectQuotes(`原文：“${source}”`, material);
});

test('natural output and numeric analysis are conditional, not compulsory mode checklists', () => {
  assert(BASE_PROMPT.includes('简单问题直接用自然段回答；复杂问题才按需要分层'));
  assert(BASE_PROMPT.includes('不要求逐项填写任何模式的栏目'));
  assert(BASE_PROMPT.includes('不凑固定字数'));
  assert(BASE_PROMPT.includes('没有相邻原文时，不要声称“结合前后文”'));
  assert(MODE_PROMPTS.argument.includes('仅在材料或问题确有比例、百分比或数值比较时核对分母'));
  assert(MODE_PROMPTS.argument.includes('不要因为出现“全部改善”就机械讨论分母'));
  assert(MODE_PROMPTS.structure.includes('不要把整句抄作主干'));
  assert(MODE_PROMPTS.concept.includes('不必填写定义、关系、混淆、改写等固定栏目'));
});

test('unknown identities and definitions stay unknown; old AI is still correctable after 14 turns', () => {
  assert(BASE_PROMPT.includes('代词身份未提供时保留未知'));
  assert(BASE_PROMPT.includes('未给定义不等于已经排除某种可能含义'));
  assert(BASE_PROMPT.includes('此前AI有错应明确更正，不用旧回答证明旧回答'));
  const item = suite.cases.find(row => row.id === 'ARGUMENT-04');
  const history = [{ role: 'user', content: '初次解读' }, { role: 'assistant', content: item.seed_answer }];
  for (let turn = 0; turn < 14; turn++) {
    const question = turn === 1 ? '纠正：只有A才B不能反推A保证B' : `请解释第${turn + 1}个疑问`;
    const reading = buildReadingMessages({ ...item.request, history, initialAnswer: item.seed_answer, message: question });
    assert(reading.messages[0].content.includes('若需纠错，先明确更正并给原文依据'));
    assert.equal(reading.material.discussion.initial_ai_answer.text, item.seed_answer);
    assert.equal(reading.material.discussion.initial_ai_answer.kind, 'ai_answer_not_source');
    assert.equal(reading.material.segments[0].text, item.request.selectedText);
    assert.equal(reading.messages.at(-1).content, question);
    assert.equal(reading.messages.slice(2, -1).length % 2, 0);
    if (turn === 13) assert(reading.messages.some(message => message.content === '纠正：只有A才B不能反推A保证B'));
    history.push({ role: 'user', content: question }, { role: 'assistant', content: '合成历史回答，不代表模型输出。' });
  }
});

test('fixed evaluation answers and rubric are immutable; no network is used', () => {
  const files = {
    '../../../tool/xiaou_reading_eval/cases.v1.json': '61c6c0c84146fa9102bd5db223161059d3ee9df251b056858b7126d86e34b0d9',
    '../../../tool/xiaou_reading_eval/rubric.v1.json': '45da3f3c2d8969ca2a643a42c058fdadfddd89b88a41ed053b5d089c5884e776',
  };
  for (const [file, expected] of Object.entries(files)) {
    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.resolve(__dirname, file))).digest('hex'), expected);
  }
  assert.equal(PROMPT_VERSION, 'xiaou-reading-v4.20261020');
  assert.equal(networkAttempts, 0);
});
