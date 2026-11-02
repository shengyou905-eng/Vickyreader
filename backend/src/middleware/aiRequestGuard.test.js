const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { createAiRequestGuard } = require('./aiRequestGuard');

function call(guard, { user = 'u1', id = 'request-0000000001', body = { message: 'same text' } } = {}) {
  const res = Object.assign(new EventEmitter(), {
    locals: {}, status(n) { this.code = n; return this; }, json(value) { this.body = value; return this; },
  });
  guard({ user: { id: user }, get: () => id, body, path: '/explain' }, res, error => {
    if (error) res.error = error; else res.admitted = true;
  });
  return res;
}

test('user + ID + canonical content, concurrent retries and independent actions', () => {
  const guard = createAiRequestGuard();
  const first = call(guard);
  assert.equal(first.admitted, true);
  const duplicate = call(guard);
  assert.equal(duplicate.code, 409);
  assert.equal(duplicate.body.state, 'running');
  assert.equal(call(guard, { body: { message: 'different' } }).body.code, 'AI_REQUEST_CONFLICT');
  assert.equal(call(guard, { user: 'u2' }).admitted, true);
  assert.equal(call(guard, { id: 'independent-00002' }).admitted, true);
  assert.equal(call(guard, { id: 'canonical-order-01', body: { message: 'q', mode: 'auto' } }).admitted, true);
  assert.equal(call(guard, { id: 'canonical-order-01', body: { mode: 'auto', message: 'q' } }).body.code, 'AI_REQUEST_DUPLICATE');
});

for (const state of ['completed', 'failed', 'timed_out', 'incomplete', 'interrupted']) {
  test(`terminal ${state} prevents re-execution until expiry`, () => {
    let clock = 0;
    const guard = createAiRequestGuard({ ttlMs: 100, maxEntries: 1, now: () => clock });
    const first = call(guard);
    clock = 1000;
    assert.equal(call(guard).body.state, 'running');
    assert.equal(call(guard, { id: 'independent-00002' }).code, 429);
    if (state === 'interrupted') first.emit('close');
    else { first.locals.aiOutcome = state; first.emit('finish'); }
    assert.equal(call(guard).body.state, state);
    clock += 101;
    assert.equal(call(guard).admitted, true);
  });
}

test('legacy requests allowed, invalid input rejected, records do not survive restart', () => {
  const guard = createAiRequestGuard();
  assert.equal(call(guard, { id: null }).admitted, true);
  assert.equal(call(guard, { id: null }).admitted, true);
  assert.equal(call(guard, { id: 'bad' }).code, 400);
  assert.ok(call(guard, { body: { history: [{ role: 'system', content: 'no' }] } }).error);
  assert.equal(call(createAiRequestGuard()).admitted, true);
});
