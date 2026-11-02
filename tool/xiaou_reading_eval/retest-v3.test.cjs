const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { makePlan, runBatch } = require('./retest-v3.cjs');
const KEY = 'synthetic-only-not-real-secret';
const good = () => ({ answer: 'synthetic answer', status: 'completed', returnedModel: 'deepseek-flash',
  usage: { prompt_tokens: 100, prompt_cache_hit_tokens: 0, prompt_cache_miss_tokens: 100, completion_tokens: 50 },
  done: true, finishReason: 'stop', unexpectedReasoning: false });
function dir(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'zhidu-v3-retest-'));
  t.after(() => {
    if (!path.resolve(directory).startsWith(path.resolve(os.tmpdir()) + path.sep)) throw Error('Invalid cleanup path');
    fs.rmSync(directory, { recursive: true, force: true });
  });
  return directory;
}
test('three fixed v3 requests, unchanged v2 parameters and fixed correction seed, under budget', () => {
  const plan = makePlan();
  assert.equal(plan.tasks.length, 3);
  assert(plan.reservedCny < 0.5);
  assert.deepEqual(plan.tasks.map(t => t.caseId), ['AUTO-01', 'PLAIN-02', 'ARGUMENT-04']);
  const correction = plan.tasks[2];
  assert.equal(correction.body.initialAnswer, '这里已经证明，全部改善都是水站单独造成的。');
  assert.equal(correction.body.message, '你刚才说已证明全部由水站造成，原文真这样说吗？');
  for (const task of plan.tasks) {
    assert(task.payload.messages.some(m => m.content.includes('xiaou-reading-v3.20261019')));
    assert.equal(task.payload.model, task.baseline.requestedModel);
    assert.equal(task.payload.temperature, 0.3);
    assert.equal(task.payload.thinking.type, 'disabled');
    assert(!JSON.stringify(task.payload).includes('reference_answer'));
    assert(!JSON.stringify(task.payload).includes('key_points'));
    assert.equal(task.inputReservation, Buffer.byteLength(JSON.stringify(task.payload.messages)) + 8192);
    assert.equal(task.reserveCny, (task.inputReservation * 2 + task.payload.max_tokens * 8) / 1e6);
  }
});
test('reserve before transport, exactly three calls, retained lock forbids repeat', async t => {
  const directory = dir(t);
  let calls = 0;
  const transport = async () => {
    calls++;
    assert(fs.existsSync(path.join(directory, `attempt-${calls}.reserved.json`)));
    return good();
  };
  const result = await runBatch(makePlan(), KEY, directory, transport);
  assert.equal(result.completed, 3);
  assert.equal(calls, 3);
  await assert.rejects(runBatch(makePlan(), KEY, directory, transport), { code: 'EEXIST' });
  assert.equal(calls, 3);
});
test('reject tampered count, cost, token caps and body before any request', async t => {
  for (const change of [p => p.tasks.push(p.tasks[0]), p => p.reservedCny = 0,
    p => p.tasks[0].payload.max_tokens = 999999, p => p.tasks[0].body.selectedText = 'changed']) {
    const plan = makePlan(); change(plan);
    await assert.rejects(runBatch(plan, KEY, dir(t), async () => assert.fail('No request allowed')), { code: 'PLAN_CHANGED' });
  }
});
for (const [name, response, reason] of [
  ['unknown usage', { ...good(), usage: null }, 'UNKNOWN_USAGE'],
  ['incomplete', { ...good(), status: 'incomplete' }, 'UPSTREAM_NOT_COMPLETED'],
  ['secret echo', { ...good(), answer: KEY }, 'SECRET_ECHO_REDACTED'],
  ['unexpected model', { ...good(), returnedModel: 'different' }, 'UNEXPECTED_MODEL'],
  ['thinking', { ...good(), unexpectedReasoning: true }, 'UNEXPECTED_THINKING'],
  ['tokens exceeded', { ...good(), usage: { ...good().usage, completion_tokens: 9999 } }, 'RESERVATION_MISMATCH'],
]) test(`${name}: stop after one attempt, no retries or secret persisted`, async t => {
  const directory = dir(t);
  let calls = 0;
  const result = await runBatch(makePlan(), KEY, directory, async () => { calls++; return response; });
  assert.equal(calls, 1);
  assert.equal(result.stopReason, reason);
  for (const file of fs.readdirSync(directory)) assert(!fs.readFileSync(path.join(directory, file), 'utf8').includes(KEY));
});
test('transport throws: one failed attempt, unknown spend, no retry', async t => {
  let calls = 0;
  const result = await runBatch(makePlan(), KEY, dir(t), async () => { calls++; throw Error(KEY); });
  assert.equal(calls, 1);
  assert.equal(result.stopReason, 'UPSTREAM_NOT_COMPLETED');
  assert.equal(result.calculatedPeakTotalCny, null);
});
