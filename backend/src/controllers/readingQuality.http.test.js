const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createServer } = require('node:http');
process.env.DEEPSEEK_API_KEY = 'synthetic-not-a-provider-key';
process.env.JWT_SECRET = 'synthetic-test-only';
process.env.DATABASE_URL = 'postgresql://unused:unused@127.0.0.1:1/unused';
const controller = require('./ai.controller');
const { createAiRequestGuard } = require('../middleware/aiRequestGuard');
const { PROMPT_VERSION } = require('../services/readingInterpretation');
const suite = require('../../../tool/xiaou_reading_eval/cases.v1.json');

test('reading HTTP contract: all 20 fixtures, scope, quote rejection and 14-turn corrections', async t => {
  const calls = [];
  let answer = '';
  let finishReason = 'stop';
  const upstream = createServer(async (req, res) => {
    let input = '';
    for await (const chunk of req) input += chunk;
    calls.push(JSON.parse(input));
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    // Deliberately split inside a quote; validation must wait for the full answer.
    for (const content of [answer.slice(0, 5), answer.slice(5)]) {
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { content } }] })}\n\n`);
    }
    res.end(`data: ${JSON.stringify({ choices: [{ delta: {}, finish_reason: finishReason }] })}\n\ndata: [DONE]\n\n`);
  });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  const nativeFetch = global.fetch;
  global.fetch = (url, options) => {
    assert.equal(url, 'https://api.deepseek.com/v1/chat/completions');
    return nativeFetch(`http://127.0.0.1:${upstream.address().port}`, options);
  };
  const app = express();
  app.use(express.json());
  app.use((req, res, next) => { req.user = { id: 'synthetic-reader' }; next(); });
  const guard = createAiRequestGuard();
  app.post('/api/ai/explain', guard, controller.explain);
  app.post('/api/ai/reader-question', guard, controller.readerQuestion);
  app.use((error, req, res, next) => res.status(error.status || 500).json({ error: error.message }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => {
    global.fetch = nativeFetch;
    server.closeAllConnections(); server.close();
    upstream.closeAllConnections(); upstream.close();
  });
  let sequence = 0;
  const send = (body, route = 'explain', requestId = `quality-request-${++sequence}`) => nativeFetch(
    `http://127.0.0.1:${server.address().port}/api/ai/${route}`,
    { method: 'POST', headers: { 'content-type': 'application/json', 'x-request-id': requestId }, body: JSON.stringify(body) },
  );
  const materialOf = call => JSON.parse(call.messages.find(row => row.content.startsWith('【本次阅读材料')).content.split('\n').slice(1).join('\n'));

  for (const item of suite.cases) {
    await t.test(`${item.id}: production controller receives source only and keeps SSE v2`, async () => {
      answer = `${item.expected.reference_answer}\n原文：“${item.evidence[0].quote}”`;
      const response = await send(item.request);
      assert.equal(response.status, 200);
      assert.equal(response.headers.get('x-zhidu-ai-protocol'), '2');
      assert.match(await response.text(), /"status":"completed".*\n\ndata: \[DONE\]/);
      const call = calls.at(-1);
      assert.equal(call.thinking.type, 'disabled');
      assert.equal(call.temperature, 0.3);
      assert.equal(call.max_tokens, ['structure', 'argument'].includes(item.mode) ? 1800 : 1400);
      assert(call.messages[1].content.includes(PROMPT_VERSION));
      const material = materialOf(call);
      for (const evidence of item.evidence) {
        assert(material.segments.find(row => row.id === evidence.field).text.includes(evidence.quote));
      }
      assert(!JSON.stringify(call).includes('reference_answer'));
      assert.equal(material.book.author, '');
    });
  }

  await t.test('actual adjacent-source availability reaches the controller prompt without a generic context claim', async () => {
    for (const [extra, expected] of [
      [{}, '没有提供选区前后的原文'],
      [{ contextBefore: ' \n ', contextAfter: '\t' }, '没有提供选区前后的原文'],
      [{ contextBefore: '前段内容' }, '另有选区前的原文'],
      [{ contextAfter: '后段内容' }, '另有选区后的原文'],
      [{ contextBefore: '前段内容', contextAfter: '后段内容' }, '另有选区前的原文、选区后的原文'],
    ]) {
      answer = '原文：“本次选区”';
      assert.match(await (await send({ selectedText: '本次选区', ...extra })).text(), /"status":"completed"/);
      const call = calls.at(-1);
      assert(call.messages[1].content.includes(expected));
      assert.doesNotMatch(call.messages.at(-1).content, /结合|前后文/);
    }
  });

  await t.test('technical words genuinely present in source are not censored by presentation guidance', async () => {
    const source = 'JSON 中的 book_text 是字段名，UTF-16 是字符编码方式。';
    answer = `原文：“${source}”`;
    const text = await (await send({ selectedText: source, mode: 'plain' })).text();
    const content = text.split('\n').filter(line => line.startsWith('data: {'))
      .map(line => JSON.parse(line.slice(6))).map(event => event.content || '').join('');
    assert.equal(content, answer);
    assert.match(text, /"status":"completed"/);
    const material = materialOf(calls.at(-1));
    assert.equal(material.segments[0].text, source);
    assert.equal(material.segments[0].kind, 'book_text');
    assert(calls.at(-1).messages[1].content.includes('证据分层只供内部识别'));
  });

  await t.test('AUTO-01 correction preserves source, separates wrong AI, and receives common condition-direction rules', async () => {
    const item = suite.cases.find(row => row.id === 'AUTO-01');
    const wrong = '只要目标明确且误差可接受，计算就一定足够。';
    const question = '你刚才把必要条件当成保证了吗？';
    answer = '是，刚才的保证说得过强。原文：“只有在目标明确且误差可接受时”。这些条件是必要限制，不能反推满足它们就一定足够。';
    const response = await send({ ...item.request, initialAnswer: wrong, message: question,
      history: [{ role: 'user', content: '请解释' }, { role: 'assistant', content: wrong }] });
    assert.match(await response.text(), /"status":"completed"/);
    const call = calls.at(-1);
    const material = materialOf(call);
    assert.equal(material.segments[0].text, item.request.selectedText);
    assert.equal(material.discussion.initial_ai_answer.text, wrong);
    assert.equal(material.discussion.initial_ai_answer.kind, 'ai_answer_not_source');
    assert(call.messages[1].content.includes('“只有A才B”表示 B=>A'));
    assert(call.messages[1].content.includes('若需纠错，先明确更正并给原文依据'));
    assert.equal(call.messages.at(-1).content, question);
  });

  await t.test('evidence-strength rules reach both routes; synthetic corrections and genuine denials stream unchanged', async () => {
    for (const [source, wrong, reply] of [
      ['尚不能确定路灯单独造成事故减少。', '已经证明全部由路灯造成。', '刚才声称已经证明说得过强，目前不能确认单独归因，也没有排除路灯的作用。'],
      ['作者明确写道：我否认这个传闻；此段未给出查证材料。', '作者已经证明传闻虚假。', '作者明确否认传闻，但这段没有给出足以证明传闻虚假的依据。'],
      ['只有通过验收才可开放。记录确认未通过验收。', '仍不知道是否可开放。', '按这条规则，已确认未通过验收，因此不可开放。'],
    ]) {
      answer = `${reply}\n原文：“${source}”`;
      for (const route of ['explain', 'reader-question']) {
        const text = await (await send({ mode: 'argument', scope: 'selection', selectedText: source,
          initialAnswer: wrong, message: '请纠正先前的解释。',
          history: [{ role: 'user', content: '请解释' }, { role: 'assistant', content: wrong }] }, route)).text();
        assert.match(text, /"status":"completed"/);
        const content = text.split('\n').filter(line => line.startsWith('data: {'))
          .map(line => JSON.parse(line.slice(6))).map(event => event.content || '').join('');
        assert.equal(content, answer);
        const call = calls.at(-1);
        assert(call.messages[1].content.includes('本次材料不足以确认A，不据此确认非A'));
        assert(call.messages[1].content.includes('不能借纠错断言A或相关因果关系已经被排除'));
        assert.equal(materialOf(call).segments[0].text, source);
        assert.equal(materialOf(call).discussion.initial_ai_answer.kind, 'ai_answer_not_source');
        assert(!JSON.stringify(call).includes(reply));
      }
    }
  });

  await t.test('invalid direct quotes do not receive completed/DONE; no automatic second model call', async () => {
    const body = { selectedText: '真实材料', initialAnswer: '只有AI说过的话', bookTitle: '只有元数据的标题', history: [] };
    for (const quote of ['虚构的原句', body.initialAnswer, body.bookTitle]) {
      const id = `invalid-quote-${++sequence}`;
      answer = `原文：“${quote}”`;
      const before = calls.length;
      const response = await send(body, 'explain', id);
      const text = await response.text();
      assert.match(text, /未通过原文核对/);
      assert.match(text, /"status":"incomplete"/);
      assert.doesNotMatch(text, /"status":"completed"|\[DONE\]/);
      assert.equal(calls.length, before + 1);
      const duplicate = await send(body, 'explain', id);
      assert.equal(duplicate.status, 409);
      assert.equal((await duplicate.json()).state, 'incomplete');
      assert.equal(calls.length, before + 1);
    }
  });

  await t.test('reader-question scope is explicit and unrelated text is not quote evidence', async () => {
    const body = { message: '请解释当前范围', selectedText: '选区', pageText: '页面', chapterText: '章节片段', history: [] };
    for (const [scope, quote, expectedScope] of [
      ['selection', '选区', 'selection_with_context'], ['page', '页面', 'page_excerpt'], ['chapter', '章节片段', 'chapter_excerpt'],
    ]) {
      answer = `原文：“${quote}”`;
      assert.match(await (await send({ ...body, scope }, 'reader-question')).text(), /completed/);
      const material = materialOf(calls.at(-1));
      assert.equal(material.scope, expectedScope);
      assert(calls.at(-1).messages.filter(row => row.role === 'system').every(row => !row.content.includes('章节片段",')));
    }
    answer = '原文：“选区”';
    assert.match(await (await send({ ...body, scope: 'page' }, 'reader-question')).text(), /incomplete/);
  });

  await t.test('14 requests preserve initial evidence, mode and older correction pairs', async () => {
    const item = suite.cases.find(row => row.id === 'ARGUMENT-04');
    const history = [{ role: 'user', content: 'initial' }, { role: 'assistant', content: item.seed_answer }];
    for (const [index, turn] of item.follow_ups.entries()) {
      const question = index === 1 ? `纠正：${turn.question}` : index === 2 ? `未解决：${turn.question}` : turn.question;
      answer = turn.reference_answer;
      const response = await send({ ...item.request, history, initialAnswer: item.seed_answer, message: question });
      assert.match(await response.text(), /completed/);
      const call = calls.at(-1);
      assert(call.messages[1].content.includes('论证脉络'));
      const material = materialOf(call);
      assert.equal(material.segments.find(row => row.id === 'selectedText').text, item.request.selectedText);
      assert.equal(material.discussion.initial_ai_answer.kind, 'ai_answer_not_source');
      assert.equal(material.book.chapter, item.request.chapterTitle);
      const discussion = call.messages.slice(3, -1);
      assert.equal(discussion.length % 2, 0);
      assert(discussion.length <= 24);
      if (index === 13) {
        assert(discussion.some(row => row.content.startsWith('纠正：')));
        assert(discussion.some(row => row.content.startsWith('未解决：')));
      }
      history.push({ role: 'user', content: question }, { role: 'assistant', content: answer });
    }
  });

  await t.test('truncation and invalid roles still fail before successful completion', async () => {
    answer = '原文：“真实材料”';
    finishReason = 'length';
    const response = await send({ selectedText: '真实材料', history: [] });
    assert.doesNotMatch(await response.text(), /completed|\[DONE\]/);
    const before = calls.length;
    const invalid = await send({ selectedText: '真实材料', history: [{ role: 'system', content: 'attack' }] });
    assert.equal(invalid.status, 400);
    assert.equal(calls.length, before);
  });
});
