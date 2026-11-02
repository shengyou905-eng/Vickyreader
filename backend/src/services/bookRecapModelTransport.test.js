const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createBookRecapModelTransport, OUTPUT_BYTES } = require('./bookRecapModelTransport');
const frame = value => `data: ${JSON.stringify(value)}\n\n`;
const content = text => frame({ model: 'synthetic-model', choices: [{ index: 0, delta: { content: text }, finish_reason: null }] });
const stop = frame({ choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] });
const usage = frame({ choices: [], usage: { prompt_tokens: 100, completion_tokens: 20 } });
const done = 'data: [DONE]\n\n';

async function mock(t, handler) {
  const requests = [];
  const server = http.createServer(async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    requests.push(JSON.parse(body)); handler(req, res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); });
  return { requests, transport: createBookRecapModelTransport({
    endpoint: `http://127.0.0.1:${server.address().port}/v1/chat/completions`, apiKey: 'synthetic-not-a-key' }) };
}
const request = { model: 'synthetic-model', messages: [{ role: 'user', content: 'synthetic material' }], temperature: 0.3, max_tokens: 3000 };

test('B232 real loopback transport: one call, bounded request, usage, UTF8 and complete stop/DONE', async t => {
  const m = await mock(t, (_req, res) => { res.setHeader('Content-Type', 'text/event-stream');
    const bytes = Buffer.from(content('{"text":"合成"}') + stop + usage + done);
    for (let i = 0; i < bytes.length; i += 7) res.write(bytes.subarray(i, i + 7)); res.end(); });
  let observed;
  const result = await m.transport(request, { signal: new AbortController().signal, observe: v => { observed = v; } });
  assert.equal(result.text, '{"text":"合成"}'); assert.equal(result.completed, true);
  assert.deepEqual(observed, { returnedModel: 'synthetic-model', inputTokens: 100, outputTokens: 20 });
  assert.equal(m.requests.length, 1); assert.equal(m.requests[0].max_tokens, 3000);
  assert.equal(m.requests[0].stream_options.include_usage, true);
});
for (const [name, wire, code] of [
  ['missing DONE', content('{}') + stop, 'RECAP_STREAM_INCOMPLETE'],
  ['missing stop', content('{}') + done, 'RECAP_STREAM_INCOMPLETE'],
  ['length', content('{}') + frame({ choices: [{ index: 0, delta: {}, finish_reason: 'length' }] }) + done, 'RECAP_STREAM_INCOMPLETE'],
  ['empty', stop + done, 'RECAP_STREAM_INCOMPLETE'],
  ['invalid frame', 'data: private broken JSON\n\n', 'RECAP_STREAM_INVALID'],
  ['upstream error', frame({ error: { secret: 'not logged' } }), 'RECAP_UPSTREAM_FAILED'],
  ['tool calls', frame({ choices: [{ index: 0, delta: { tool_calls: [] } }] }), 'RECAP_STREAM_INVALID'],
  ['thinking', frame({ choices: [{ index: 0, delta: { reasoning_content: 'hidden' } }] }), 'RECAP_STREAM_INVALID'],
  ['after stop', content('{}') + stop + content('more') + done, 'RECAP_STREAM_INVALID'],
  ['output bytes', content('x'.repeat(OUTPUT_BYTES + 1)) + stop + done, 'RECAP_OUTPUT_BUDGET'],
  ['output tokens', content('{}') + stop + frame({ choices: [], usage: { prompt_tokens: 10, completion_tokens: 3001 } }) + done, 'RECAP_OUTPUT_BUDGET'],
  ['model changed', content('{}') + frame({ model: 'another', choices: [] }) + stop + done, 'RECAP_STREAM_INVALID'],
]) test(`B232 loopback rejects ${name}, no automatic retry`, async t => {
  const m = await mock(t, (_req, res) => { res.setHeader('Content-Type', 'text/event-stream'); res.end(wire); });
  await assert.rejects(m.transport(request, { signal: new AbortController().signal, observe() {} }), { error_code: code });
  assert.equal(m.requests.length, 1);
});
test('B232 usage missing stays unknown; usage may arrive after stop', async t => {
  const m = await mock(t, (_req, res) => { res.setHeader('Content-Type', 'text/event-stream'); res.end(content('{}') + stop + done); });
  let observed; await m.transport(request, { signal: new AbortController().signal, observe: v => { observed = v; } });
  assert.equal(observed.inputTokens, null); assert.equal(observed.outputTokens, null);
});
test('B232 upstream 500 HTML never exposes body or retries', async t => {
  const m = await mock(t, (_req, res) => { res.statusCode = 500; res.end('secret upstream body'); });
  await assert.rejects(m.transport(request, { signal: new AbortController().signal, observe() {} }), { message: 'RECAP_UPSTREAM_FAILED' });
  assert.equal(m.requests.length, 1);
});
test('B232 hanging response can be aborted without retry', async t => {
  let called; const entered = new Promise(resolve => { called = resolve; });
  const m = await mock(t, (_req, res) => { res.setHeader('Content-Type', 'text/event-stream'); res.write(content('{')); called(); });
  const controller = new AbortController();
  const promise = m.transport(request, { signal: controller.signal, observe() {} });
  const rejected = assert.rejects(promise); await entered; controller.abort(); await rejected;
  assert.equal(m.requests.length, 1);
});
test('B232 peer closes mid stream, cannot complete', async t => {
  const m = await mock(t, (_req, res) => { res.setHeader('Content-Type', 'text/event-stream'); res.write(content('{')); setImmediate(() => res.destroy()); });
  await assert.rejects(m.transport(request, { signal: new AbortController().signal, observe() {} }));
  assert.equal(m.requests.length, 1);
});
