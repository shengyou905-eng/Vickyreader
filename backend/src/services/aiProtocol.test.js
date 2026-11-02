const test = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('node:http');
const { validateAiInput, normalizeHistory, explanationEvidence, readCompletion } = require('./aiProtocol');

test('history role allowlist and type/length budgets reject before model invocation', () => {
  for (const role of ['system', 'developer', 'tool', '', null]) {
    assert.throws(() => validateAiInput({ history: [{ role, content: 'attack' }] }));
  }
  for (const body of [{ history: {} }, { message: {} }, { message: 'a'.repeat(8001) },
    { selectedText: 'a'.repeat(12001) }, { history: [{ role: 'user', content: 'x'.repeat(16001) }] }]) {
    assert.throws(() => validateAiInput(body));
  }
  validateAiInput({ selectedText: 'legacy', history: [] });
});

test('12+ rounds retain fixed evidence independently of bounded history', () => {
  const fixed = { selectedText: 'Original evidence', initialAnswer: 'First AI inference', paragraph: 'Original paragraph' };
  const history = [];
  for (let round = 0; round < 15; round++) {
    history.push({ role: 'user', content: `q${round}` }, { role: 'assistant', content: `a${round}` });
    const body = { ...fixed, history };
    validateAiInput(body);
    assert.match(explanationEvidence(body), /Original evidence/);
    assert.match(explanationEvidence(body), /不是原文证据/);
    assert.ok(normalizeHistory(history).length <= 24);
  }
  assert.equal(normalizeHistory(history)[0].content, 'q3');
});

const delta = content => `data: ${JSON.stringify({ choices: [{ delta: { content } }] })}\n\n`;
const finish = reason => `data: ${JSON.stringify({ choices: [{ delta: {}, finish_reason: reason }] })}\n\n`;

test('real HTTP upstream: completion, truncation, EOF, malformed, cancellation', async t => {
  const server = createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(delta('原文'));
    if (req.url === '/complete') res.end(finish('stop') + 'data:[DONE]\n\n');
    else if (req.url === '/length') res.end(finish('length') + 'data: [DONE]\n\n');
    else if (req.url === '/missing-stop') res.end('data: [DONE]\n\n');
    else if (req.url === '/malformed') res.end('data: {broken}\n\n');
    else if (req.url === '/eof') res.end(finish('stop'));
    else if (req.url === '/cancel') { /* caller cancels this live connection */ }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const read = async path => {
    const response = await fetch(base + path);
    const result = [];
    for await (const content of readCompletion(response.body)) result.push(content);
    return result;
  };
  assert.deepEqual(await read('/complete'), ['原文']);
  for (const path of ['/length', '/missing-stop', '/malformed', '/eof']) await assert.rejects(read(path));
  const response = await fetch(base + '/cancel');
  const iterator = readCompletion(response.body);
  assert.equal((await iterator.next()).value, '原文');
  await iterator.return();
});
