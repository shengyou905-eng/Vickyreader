const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createServer } = require('node:http');
const { createAiRequestGuard } = require('../middleware/aiRequestGuard');
process.env.DEEPSEEK_API_KEY = 'synthetic-key-never-sent-to-provider';
process.env.JWT_SECRET = 'synthetic-test-only';
process.env.DATABASE_URL = 'postgresql://unused:unused@127.0.0.1:1/unused';
const controller = require('./ai.controller');

test('HTTP controller sends fixed evidence after 14 rounds and guards duplicate model calls', async t => {
  let mode = 'complete';
  const calls = [];
  const upstream = createServer(async (req, res) => {
    let body = '';
    for await (const chunk of req) body += chunk;
    calls.push(JSON.parse(body));
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write('data: {"choices":[{"delta":{"content":"answer"}}]}\n\n');
    if (mode === 'hang') return;
    if (mode === 'eof') return res.end();
    res.end(`data: {"choices":[{"delta":{},"finish_reason":"${mode === 'length' ? 'length' : 'stop'}"}]}\n\ndata: [DONE]\n\n`);
  });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  const nativeFetch = global.fetch;
  global.fetch = (url, options) => {
    assert.equal(url, 'https://api.deepseek.com/v1/chat/completions');
    return nativeFetch(`http://127.0.0.1:${upstream.address().port}`, options);
  };
  const app = express();
  const closed = new Map();
  app.use(express.json());
  app.use((req, res, next) => {
    req.user = { id: req.get('test-user') || 'one' };
    closed.set(req.get('x-request-id'), new Promise(resolve => res.once('close', resolve)));
    next();
  });
  app.post('/explain', createAiRequestGuard(), controller.explain);
  app.use((error, req, res, next) => res.status(error.status || 500).json({ error: error.message }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => {
    global.fetch = nativeFetch;
    server.closeAllConnections(); server.close();
    upstream.closeAllConnections(); upstream.close();
  });
  const body = {
    selectedText: 'original evidence', paragraph: 'original paragraph',
    bookTitle: 'original book', bookAuthor: 'original author', chapterTitle: 'chapter 3', mode: 'argument',
    initialAnswer: 'first explanation', message: 'followup',
    history: Array.from({ length: 28 }, (_, i) => ({ role: i % 2 ? 'assistant' : 'user', content: `turn ${i}` })),
  };
  const send = (id, data = body, user = 'one', signal) => nativeFetch(`http://127.0.0.1:${server.address().port}/explain`, {
    method: 'POST', body: JSON.stringify(data), headers: { 'content-type': 'application/json', 'x-request-id': id, 'test-user': user }, signal,
  });
  const response = await send('request-initial-001');
  assert.equal(response.headers.get('x-zhidu-ai-protocol'), '2');
  assert.match(await response.text(), /"status":"completed"/);
  assert.equal(calls.length, 1);
  const messages = calls[0].messages;
  assert.doesNotMatch(messages[1].content, /original book|original author/);
  assert.match(messages[1].content, /论证/);
  assert.match(messages[2].content, /original book/);
  assert.match(messages[2].content, /original author/);
  assert.match(messages[2].content, /original evidence/);
  assert.match(messages[2].content, /first explanation/);
  assert.equal((await send('request-initial-001')).status, 409);
  assert.equal((await send('request-initial-001', { ...body, message: 'changed' })).status, 409);
  assert.equal(calls.length, 1);
  assert.match(await (await send('request-independent')).text(), /completed/);
  assert.match(await (await send('request-initial-001', body, 'two')).text(), /completed/);
  assert.equal(calls.length, 3);
  for (const scenario of ['length', 'eof']) {
    mode = scenario;
    const result = await (await send(`request-${scenario}-000001`)).text();
    assert.match(result, /"status":"incomplete"/);
    assert.doesNotMatch(result, /\[DONE\]|"status":"completed"/);
    const duplicate = await send(`request-${scenario}-000001`);
    assert.equal((await duplicate.json()).state, 'incomplete');
  }
  mode = 'hang';
  const admittedCalls = calls.length + 1;
  const abort = new AbortController();
  const hanging = await send('request-hanging-001', body, 'one', abort.signal);
  const reader = hanging.body.getReader();
  await reader.read();
  const connectionClosed = closed.get('request-hanging-001');
  const duplicate = await send('request-hanging-001');
  assert.equal(duplicate.status, 409);
  assert.equal((await duplicate.json()).state, 'running');
  assert.equal(calls.length, admittedCalls);
  abort.abort();
  await reader.cancel().catch(() => {});
  await connectionClosed;
  const cancelledRetry = await send('request-hanging-001');
  assert.equal((await cancelledRetry.json()).state, 'interrupted');
  assert.equal(calls.length, admittedCalls);
});
