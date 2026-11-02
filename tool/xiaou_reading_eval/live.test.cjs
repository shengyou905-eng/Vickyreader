const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createServer } = require('node:http');
const { makePlan, assertPlan, usageCost, sendSse, runBatch } = require('./live.cjs');
const KEY = 'synthetic-test-key-not-a-real-credential';
const good = () => ({ answer: 'synthetic answer', status: 'completed', requestedModel: 'deepseek-v4-flash',
  returnedModel: 'synthetic-loopback', finishReason: 'stop', done: true, elapsedMs: 1, ttftMs: 1,
  usage: { prompt_tokens: 100, prompt_cache_hit_tokens: 20, prompt_cache_miss_tokens: 80, completion_tokens: 50, total_tokens: 150 }, unexpectedReasoning: false });

function directory(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'zhidu-live-eval-test-'));
  t.after(() => {
    if (!path.resolve(dir).startsWith(path.resolve(os.tmpdir()) + path.sep)) throw new Error('Unexpected cleanup path');
    fs.rmSync(dir, { recursive: true, force: true });
  });
  return dir;
}

test('plan has only the five authorized cases, twelve equal-parameter samples and fixed correction seed', () => {
  const plan = makePlan();
  assert.equal(plan.tasks.length, 12);
  // Prompt bytes can change; independently check the same conservative rates and allowance.
  const expectedNanoyuan = plan.tasks.reduce((sum, task) => {
    const inputAllowance = Buffer.byteLength(JSON.stringify(task.payload.messages), 'utf8') + 8192;
    assert.equal(task.inputReservation, inputAllowance);
    return sum + inputAllowance * 2000 + task.payload.max_tokens * 8000;
  }, 0);
  assert.equal(plan.reservedCny, expectedNanoyuan / 1e9);
  assert(plan.reservedCny < 2);
  assert.equal(plan.noRetries, true);
  assert.deepEqual([...new Set(plan.tasks.map(row => row.caseId))], ['AUTO-01', 'PLAIN-02', 'STRUCTURE-02', 'CONCEPT-04', 'ARGUMENT-04']);
  for (let i = 0; i < 12; i += 2) {
    const [a, b] = plan.tasks.slice(i, i + 2);
    assert.deepEqual(a.body, b.body);
    for (const field of ['model', 'temperature', 'thinking', 'max_tokens', 'stream', 'stream_options']) {
      assert.deepEqual(a.payload[field], b.payload[field]);
    }
    assert(!JSON.stringify(a.payload).includes('reference_answer'));
    assert(!JSON.stringify(b.payload).includes('key_points'));
  }
  const correction = plan.tasks.filter(row => row.turn !== 'initial');
  assert.equal(correction.length, 2);
  assert(correction.every(row => row.body.history[1].content === '这里已经证明，全部改善都是水站单独造成的。'));
});

test('preflight rejects excess calls, spend and model changes before any transport', () => {
  const { tasks } = makePlan();
  assert.throws(() => assertPlan([...tasks, tasks[0]]), { code: 'CALL_LIMIT' });
  assert.throws(() => assertPlan(tasks.map(row => ({ ...row, reserveCny: 1 }))), { code: 'BUDGET_LIMIT' });
  assert.throws(() => assertPlan(tasks.map(row => ({ ...row, payload: { ...row.payload, model: 'different' } }))), { code: 'PARAMETER_MISMATCH' });
});

test('usage cost uses cache split once; missing usage is unknown, not zero', () => {
  assert.equal(usageCost(good().usage), 0.0005608);
  assert.equal(usageCost(null), null);
  assert.equal(usageCost({ ...good().usage, prompt_cache_hit_tokens: null }), null);
  assert.equal(usageCost({ ...good().usage, prompt_tokens: 999 }), null);
  assert.equal(usageCost({ ...good().usage, reasoning_tokens: 50 }), usageCost(good().usage));
});

test('real loopback HTTP streaming reads UTF-8 answers, last-frame usage and TTFT without leaking error bodies', async t => {
  let calls = 0;
  let error = false;
  const server = createServer(async (req, res) => {
    calls++;
    let body = '';
    for await (const chunk of req) body += chunk;
    assert.equal(JSON.parse(body).model, 'deepseek-v4-flash');
    if (error) { res.writeHead(401); res.end(`must not store ${KEY}`); return; }
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    const frame = `data: ${JSON.stringify({ model: 'synthetic-loopback', choices: [{ delta: { content: '原文：水站' } }] })}\n\n`;
    const bytes = Buffer.from(frame);
    res.write(bytes.subarray(0, 63)); res.write(bytes.subarray(63));
    res.end(`data: ${JSON.stringify({ choices: [{ delta: {}, finish_reason: 'stop' }], usage: good().usage })}\n\ndata: [DONE]\n\n`);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const endpoint = `http://127.0.0.1:${server.address().port}/`;
  const payload = { model: 'deepseek-v4-flash' };
  const result = await sendSse(payload, KEY, endpoint);
  assert.equal(result.status, 'completed');
  assert.equal(result.answer, '原文：水站');
  assert.deepEqual(result.usage, { ...good().usage, reasoning_tokens: null });
  assert(result.ttftMs >= 0 && result.elapsedMs >= result.ttftMs);
  error = true;
  const rejected = await sendSse(payload, KEY, endpoint);
  assert.equal(calls, 2);
  assert.equal(rejected.httpStatus, 401);
  assert.equal(rejected.status, 'incomplete');
  assert(!JSON.stringify(rejected).includes(KEY));
  await assert.rejects(sendSse(payload, KEY, 'https://unapproved.example/'), { code: 'ENDPOINT_NOT_ALLOWED' });
});

test('successful batch admits twelve once, reserves before transport, and cannot rerun', async t => {
  const dir = directory(t);
  const plan = makePlan();
  let calls = 0;
  const transport = async () => {
    calls++;
    assert(fs.existsSync(path.join(dir, `attempt-${String(calls).padStart(2, '0')}.reserved.json`)));
    return good();
  };
  const summary = await runBatch(plan, KEY, dir, transport);
  assert.equal(summary.callsAttempted, 12);
  assert.equal(calls, 12);
  assert.equal(summary.stopReason, null);
  assert.equal(summary.actualAccountDebitCny, null);
  const blind = fs.readFileSync(path.join(dir, 'blind-review.md'), 'utf8');
  assert(!blind.includes('variant'));
  assert(!blind.includes(KEY));
  await assert.rejects(runBatch(plan, KEY, dir, transport), { code: 'EEXIST' });
  assert.equal(calls, 12);
});

for (const [name, value, reason] of [
  ['unknown usage', { ...good(), usage: null }, 'USAGE_OR_CACHE_BREAKDOWN_UNKNOWN'],
  ['incomplete', { ...good(), status: 'incomplete' }, 'UPSTREAM_NOT_COMPLETED'],
  ['thinking unexpectedly enabled', { ...good(), unexpectedReasoning: true }, 'UNEXPECTED_THINKING_MODE'],
  ['token cap exceeded', { ...good(), usage: { ...good().usage, completion_tokens: 9999 } }, 'RESERVATION_MISMATCH'],
  ['secret echo', { ...good(), answer: KEY }, 'SECRET_ECHO_REDACTED'],
]) {
  test(`${name}: one call, no retry and no next request`, async t => {
    const dir = directory(t);
    let calls = 0;
    const result = await runBatch(makePlan(), KEY, dir, async () => { calls++; return value; });
    assert.equal(calls, 1);
    assert.equal(result.stopReason, reason);
    for (const file of fs.readdirSync(dir)) assert(!fs.readFileSync(path.join(dir, file), 'utf8').includes(KEY));
  });
}

test('thrown transport failure is recorded as one incomplete attempt, without retry', async t => {
  let calls = 0;
  const result = await runBatch(makePlan(), KEY, directory(t), async () => { calls++; throw new Error(KEY); });
  assert.equal(calls, 1);
  assert.equal(result.callsAttempted, 1);
  assert.equal(result.stopReason, 'UPSTREAM_NOT_COMPLETED');
  assert.equal(result.calculatedPeakTotalCny, null);
});
