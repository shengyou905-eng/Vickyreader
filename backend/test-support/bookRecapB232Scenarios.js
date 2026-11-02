const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const http = require('node:http');
const express = require('express');
const jwt = require('jsonwebtoken');
const { createServerBookRecapStorage } = require('../src/services/bookRecapStorage.service');
const { createBookRecapExecutor } = require('../src/services/bookRecapExecutor');
const { createBookRecapAuthorization } = require('../src/services/bookRecapAuthorization');
const { createBookRecapModelTransport } = require('../src/services/bookRecapModelTransport');
const { createBookRecapHttpAdapter, createServerBookRecapHttpAdapter } = require('../src/routes/bookRecapHttpAdapter');
const fixture = require('../../tool/book_recap_eval/fixture.v1.json');

const gate = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
module.exports = async function scenarios(t, { db, repo, user, generate, probe }) {
  const entries = require('../src/repositories/entry.repository');
  // Real JWT middleware and consent middleware, synthetic secret and isolated DB only.
  const authPath = require.resolve('../src/middleware/auth');
  const oldAuth = require.cache[authPath];
  const envPath = require.resolve('../src/config/env'), oldEnv = require.cache[envPath];
  const secret = 'synthetic-b232-not-a-production-secret';
  require.cache[envPath] = { exports: { jwtSecret: secret } };
  delete require.cache[authPath];
  const auth = require(authPath);
  const consent = require('../src/middleware/requireAiConsent');
  const { AI_CONSENT_VERSION } = require('../src/controllers/auth.controller');
  const authorize = createBookRecapAuthorization(AI_CONSENT_VERSION);
  const storage = createServerBookRecapStorage({ repository: repo, origin: 'https://synthetic.invalid', macKey: Buffer.alloc(32, 32) });
  const principal = f => ({ userId: f.userId, tokenVersion: 0 });
  const read = async f => (await db.query('SELECT * FROM reading_recaps WHERE id=$1', [f.id])).rows[0];
  const operation = async f => (await db.query('SELECT * FROM reading_recap_operations WHERE user_id=$1 AND request_id=$2', [f.userId, f.input.request_id])).rows[0];
  async function setup({ payload = {}, prepare = true } = {}) {
    const userId = await user();
    await db.query('UPDATE users SET ai_consent_version=$2 WHERE id=$1', [userId, AI_CONSENT_VERSION]);
    const bookId = randomUUID();
    const entry = await entries.createEntry(userId, { source: 'ai_question', book_id: bookId,
      original_text: fixture.excerpt, user_input: fixture.question, ai_explanation: fixture.answer,
      metadata_json: { origin: 'reader', reading_ai_context: { scope: 'selection', selectedText: fixture.excerpt } }, ...payload });
    const f = { userId, entryId: entry.id, id: randomUUID(), bookId };
    f.body = { recap_id: f.id, request_id: randomUUID(), book_id: bookId, selected_sources: [{ entry_id: f.entryId }] };
    if (prepare) f.input = generate(await storage.prepare(userId, f.body));
    return f;
  }
  function result(request) {
    const s = JSON.parse(request.messages[1].content), book = s.evidence.find(e => e.kind === 'book_excerpt');
    const q = s.evidence.find(e => e.kind === 'user_question');
    return { schemaVersion: 1, snapshotFingerprint: s.snapshotFingerprint,
      knowledge: book ? [{ id: 'k1', kind: 'argument', title: 'A condition', summary: 'A necessary condition is not a guarantee.',
        basis: 'source_supported', evidenceRefs: [book.id], quotes: [] }] : [],
      myThinking: q ? [{ id: 't1', title: 'A question', summary: 'The reader asked about the condition.',
        basis: 'user_explicit', evidenceRefs: [q.id], quotes: [] }] : [], relations: [], openQuestions: [], nextQuestions: [] };
  }
  const response = request => ({ text: JSON.stringify(result(request)), completed: true, finishReason: 'stop' });
  const make = (transport, extra = {}) => createBookRecapExecutor({ storage, transport, authorize,
    model: 'synthetic-model', ...extra });
  const run = (executor, f, options) => executor.generate(principal(f), f.id, f.input, options);
  async function noBody(f, state) {
    const row = await read(f); assert.equal(row.state, state); assert.equal(row.result_json, null);
    assert.equal((await db.query('SELECT count(*)::int n FROM xiaou_conversations WHERE recap_id=$1', [f.id])).rows[0].n, 0);
  }
  async function paused(f) {
    const entered = gate(), release = gate(); let calls = 0;
    const executor = make(async request => { calls++; entered.resolve(); await release.promise; return response(request); });
    const promise = run(executor, f); const settled = promise.then(value => ({ value }), error => ({ error }));
    await entered.promise;
    return { executor, release, settled, calls: () => calls };
  }

  await t.test('B232 formal resolver to executor complete, safe model input and metrics, save/get/feedback', async () => {
    const f = await setup(); let calls = 0;
    const before = (await db.query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [f.userId])).rows;
    const executor = make(async (req, { observe }) => {
      calls++; const input = JSON.stringify(req);
      assert(!input.includes(f.userId)); assert(!input.includes('synthetic.invalid'));
      assert(!input.includes('metadata_json')); assert(input.includes('historical_ai'));
      assert(input.includes('reader_context')); assert.equal(req.max_tokens, 3000);
      observe({ returnedModel: 'synthetic-model', inputTokens: 100, outputTokens: 20 }); return response(req);
    }, { pricing: { model: 'synthetic-model', currency: 'CNY', inputPerMillion: 1, outputPerMillion: 2, version: 'synthetic-fixed' } });
    assert.equal((await run(executor, f)).status, 'succeeded'); assert.equal(calls, 1);
    const row = await storage.get(f.userId, f.id);
    assert.equal(row.input_tokens, '100'); assert.equal(row.cost_amount, '0.00014000'); assert.equal(row.returned_model, 'synthetic-model');
    assert(Number(row.elapsed_ms) >= 0);
    await storage.save(f.userId, f.id, { request_id: randomUUID(), expected_revision: row.revision });
    const saved = await storage.get(f.userId, f.id); assert.equal(saved.is_saved, true);
    await storage.feedback(f.userId, f.id, { request_id: randomUUID(), expected_revision: saved.revision, category: 'low_value' });
    assert.deepEqual((await db.query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [f.userId])).rows, before);
  });
  await t.test('B232 concurrent retries, altered payload conflict and completed replay never dispatch twice', async () => {
    const f = await setup(), p = await paused(f);
    try {
      assert.deepEqual(await run(p.executor, f), { status: 'running', replay: true });
      await assert.rejects(p.executor.generate(principal(f), f.id, { ...f.input, consent_scope_fingerprint: '0'.repeat(64) }), { error_code: 'RECAP_REQUEST_CONFLICT' });
    } finally { p.release.resolve(); }
    assert.equal((await p.settled).value.status, 'succeeded');
    assert.deepEqual(await run(p.executor, f), { status: 'succeeded', replay: true }); assert.equal(p.calls(), 1);
  });
  for (const [name, mutate] of [
    ['invalid JSON', r => { r.text = '{'; }],
    ['incomplete', r => { r.completed = false; }],
    ['length finish', r => { r.finishReason = 'length'; }],
    ['foreign evidence', r => { const v = JSON.parse(r.text); v.knowledge[0].evidenceRefs = ['forged']; r.text = JSON.stringify(v); }],
    ['AI as book', (r, req) => { const v = JSON.parse(r.text); v.knowledge[0].evidenceRefs = [JSON.parse(req.messages[1].content).evidence.find(e => e.kind === 'historical_ai').id]; r.text = JSON.stringify(v); }],
    ['invented quote', r => { const v = JSON.parse(r.text); v.knowledge[0].quotes = [{ evidenceId: v.knowledge[0].evidenceRefs[0], text: 'Invented quote', voice: 'author' }]; r.text = JSON.stringify(v); }],
  ]) await t.test(`B232 ${name} cannot save partial success; failed replay is fenced`, async () => {
    const f = await setup(); let calls = 0;
    const executor = make(async req => { calls++; const r = response(req); mutate(r, req); return r; });
    await assert.rejects(run(executor, f), { error_code: 'RECAP_INVALID_RESULT' });
    await noBody(f, 'failed'); assert.equal((await operation(f)).status, 'failed');
    assert.equal((await run(executor, f)).status, 'failed'); assert.equal(calls, 1);
  });
  await t.test('B232 output budget rejected with no successful row', async () => {
    const f = await setup();
    await assert.rejects(run(make(async () => ({ text: 'x'.repeat(131073) })), f), { error_code: 'RECAP_OUTPUT_BUDGET' });
    await noBody(f, 'failed');
  });
  await t.test('B232 timeout fences a provider ignoring AbortSignal and its late response', async () => {
    const f = await setup(), release = gate(); let completed = false;
    const executor = make(async req => { await release.promise; completed = true; return response(req); }, { timeoutMs: 30 });
    await assert.rejects(run(executor, f), { error_code: 'RECAP_TIMEOUT' }); await noBody(f, 'failed');
    release.resolve(); await new Promise(resolve => setImmediate(resolve)); assert(completed); await noBody(f, 'failed');
  });
  await t.test('B232 cancel wins while provider waits; no locks held; late completion cannot restore', async () => {
    const f = await setup(), p = await paused(f);
    await p.executor.cancel(f.userId, f.id, f.input.request_id);
    assert.equal((await p.settled).error.error_code, 'RECAP_CANCELLED');
    p.release.resolve(); await noBody(f, 'cancelled');
    assert.equal((await operation(f)).status, 'cancelled'); assert.equal(p.calls(), 1);
  });
  await t.test('B232 completed transaction wins before cancel, no misleading cancellation', async () => {
    const f = await setup(), executor = make(async req => response(req)); await run(executor, f);
    await assert.rejects(executor.cancel(f.userId, f.id, f.input.request_id), { error_code: 'RECAP_ALREADY_COMPLETED' });
    assert.equal((await read(f)).state, 'ready');
  });
  for (const action of ['edit','delete','followup','delete-recap']) await t.test(`B232 model wait then ${action}: late result cannot revive body`, async () => {
    const f = await setup(), p = await paused(f);
    try {
      if (action === 'edit') await entries.updateEntryImportance(f.userId, f.entryId, true);
      if (action === 'delete') await entries.deleteEntry(f.userId, f.entryId);
      if (action === 'followup') await entries.createFollowUp(f.userId, f.entryId, 'New question', 'Old AI');
      if (action === 'delete-recap') await storage.remove(f.userId, f.id);
    } finally { p.release.resolve(); }
    assert((await p.settled).error);
    await noBody(f, action === 'delete' ? 'invalidated' : action === 'delete-recap' ? 'deleted' : 'stale');
    assert.equal((await operation(f)).status, 'revoked');
  });
  await t.test('B232 source changes between claim and dispatch prevent the upstream call', async () => {
    const f = await setup(); let calls = 0;
    const altered = { ...storage, async dispatch(...args) {
      await entries.deleteEntry(f.userId, f.entryId); return storage.dispatch(...args);
    } };
    await assert.rejects(run(make(async req => { calls++; return response(req); }, { storage: altered }), f));
    assert.equal(calls, 0); await noBody(f, 'invalidated');
  });
  for (const action of ['consent','token','ban']) await t.test(`B232 authorization ${action} revoked during model wait rejects completion`, async () => {
    const f = await setup(), p = await paused(f);
    if (action === 'consent') await db.query('UPDATE users SET ai_consent_version=0 WHERE id=$1', [f.userId]);
    if (action === 'token') await db.query('UPDATE users SET token_version=token_version+1 WHERE id=$1', [f.userId]);
    if (action === 'ban') await db.query("UPDATE users SET account_status='banned' WHERE id=$1", [f.userId]);
    p.release.resolve(); assert((await p.settled).error); await noBody(f, 'failed');
  });
  await t.test('B232 authorization rechecked at dispatch prevents revoked consent sending material', async () => {
    const f = await setup(); let calls = 0;
    const changed = { ...storage, async dispatch(...args) {
      await db.query('UPDATE users SET ai_consent_version=0 WHERE id=$1', [f.userId]); return storage.dispatch(...args);
    } };
    await assert.rejects(run(make(async req => { calls++; return response(req); }, { storage: changed }), f), { error_code: 'AI_CONSENT_REQUIRED' });
    assert.equal(calls, 0); await noBody(f, 'failed');
  });
  await t.test('B232 completion transaction injected failure rolls back body/conversation/metrics', async () => {
    const f = await setup(); let failed = false;
    await assert.rejects(probe.run({ after(sql) {
      if (sql.includes('INSERT INTO xiaou_conversations') && !failed) { failed = true; throw Error('injected'); }
    } }, () => run(make(async req => response(req)), f)));
    assert(failed); await noBody(f, 'failed'); assert.equal((await operation(f)).status, 'failed');
  });
  await t.test('B232 disconnect before completion commit rolls back ready body and dedicated conversation', async () => {
    const f = await setup(), written = gate(), release = gate(), controller = new AbortController();
    const pending = probe.run({ async after(sql) {
      if (sql.includes("SET state='ready'")) { written.resolve(); await release.promise; }
    } }, () => run(make(async req => response(req)), f, { signal: controller.signal }));
    const rejected = assert.rejects(pending, { error_code: 'RECAP_CANCELLED' });
    await written.promise; controller.abort(); release.resolve(); await rejected;
    await noBody(f, 'cancelled'); assert.equal((await operation(f)).status, 'cancelled');
  });
  await t.test('B232 cancellation of HTTP work signal, bounded concurrency and unknown usage', async () => {
    const f = await setup(), entered = gate(), release = gate(), controller = new AbortController();
    const executor = make(async req => { entered.resolve(); await release.promise; return response(req); }, { maxConcurrent: 1 });
    const pending = run(executor, f, { signal: controller.signal }); const rejected = assert.rejects(pending, { error_code: 'RECAP_CANCELLED' });
    await entered.promise;
    await assert.rejects(run(executor, await setup()), { error_code: 'RECAP_BUSY' });
    controller.abort(); await rejected; release.resolve(); await noBody(f, 'cancelled');
    const row = await read(f); assert.equal(row.input_tokens, null); assert.equal(row.cost_amount, null);
  });
  await t.test('B232 independent active interpretations keep separate recaps', async () => {
    const f = await setup(), other = { ...f, id: randomUUID() };
    other.body = { ...f.body, recap_id: other.id, request_id: randomUUID() };
    other.input = generate(await storage.prepare(f.userId, other.body)); let calls = 0;
    const executor = make(async req => { calls++; return response(req); });
    await run(executor, f); await run(executor, other); assert.equal(calls, 2);
    assert.equal((await read(f)).state, 'ready'); assert.equal((await read(other)).state, 'ready');
  });
  await t.test('B232 dispatch sees durable cancellation made before local controller registration', async () => {
    const f = await setup(); let calls = 0;
    const changed = { ...storage, async begin(...args) {
      const op = await storage.begin(...args); await storage.cancel(f.userId, f.id, f.input.request_id); return op;
    } };
    await assert.rejects(run(make(async req => { calls++; return response(req); }, { storage: changed }), f));
    assert.equal(calls, 0); await noBody(f, 'cancelled');
  });
  await t.test('B232 cleanup failure cannot retry provider; explicit expired recovery retains durable fence', async () => {
    const f = await setup(); let calls = 0;
    const broken = { ...storage, async fail() { throw Error('synthetic database unavailable'); } };
    const executor = make(async () => { calls++; throw Error('private error must not escape'); }, { storage: broken });
    await assert.rejects(run(executor, f), { error_code: 'RECAP_FINALIZATION_UNAVAILABLE' });
    await noBody(f, 'generating');
    assert.equal((await run(executor, f)).status, 'running'); assert.equal(calls, 1);
    await db.query("UPDATE reading_recap_operations SET deadline_at=now()-interval '1 second' WHERE user_id=$1 AND request_id=$2", [f.userId, f.input.request_id]);
    await storage.cancel(f.userId, f.id, f.input.request_id, { expiredOnly: true });
    await noBody(f, 'failed');
    await assert.rejects(run(executor, f), { error_code: 'RECAP_REQUEST_RETIRED' }); assert.equal(calls, 1);
  });
  await t.test('B232 model alias mismatch prevents unsupported cost calculation, usage remains measured', async () => {
    const f = await setup();
    const executor = make(async (req, { observe }) => {
      observe({ returnedModel: 'different-alias', inputTokens: 80, outputTokens: 21 }); return response(req);
    }, { pricing: { model: 'synthetic-model', currency: 'CNY', inputPerMillion: 1, outputPerMillion: 2, version: 'test' } });
    await run(executor, f); const row = await read(f);
    assert.equal(row.input_tokens, '80'); assert.equal(row.output_tokens, '21'); assert.equal(row.cost_amount, null);
  });
  await t.test('B232 replay after abandoned claim deadline retires it without dispatching', async () => {
    const f = await setup(); await storage.begin(f.userId, f.id, f.input);
    await db.query("UPDATE reading_recap_operations SET deadline_at=now()-interval '1 second' WHERE user_id=$1 AND request_id=$2", [f.userId, f.input.request_id]);
    let calls = 0;
    const executor = make(async req => { calls++; return response(req); });
    assert.deepEqual(await run(executor, f), { status: 'interrupted', replay: true });
    await noBody(f, 'failed'); assert.equal(calls, 0);
  });

  // Actual HTTP on both sides: real auth/consent + adapter + SQL + executor + SSE parser.
  let upstreamCalls = 0, upstreamMode = 'success', upstreamGate;
  const upstream = http.createServer(async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    upstreamCalls++; const value = JSON.parse(body);
    if (upstreamMode === 'error') { res.statusCode = 503; res.end('private provider error'); return; }
    res.setHeader('Content-Type', 'text/event-stream');
    if (upstreamMode === 'hang') { res.write(': waiting\n\n'); upstreamGate.resolve(); return; }
    res.end(`data: ${JSON.stringify({ model: 'synthetic-model', choices: [{ index: 0, delta: { content: JSON.stringify(result(value)) }, finish_reason: null }] })}\n\n` +
      'data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n');
  });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  const executor = make(createBookRecapModelTransport({ endpoint: `http://127.0.0.1:${upstream.address().port}/v1/chat/completions`, apiKey: 'synthetic' }));
  const app = express(); app.use('/recaps', createBookRecapHttpAdapter({ storage, executor, auth, requireAiConsent: consent }));
  app.use('/composed', createServerBookRecapHttpAdapter({ repository: repo, origin: 'https://synthetic.invalid',
    macKey: Buffer.alloc(32, 32), endpoint: `http://127.0.0.1:${upstream.address().port}/v1/chat/completions`,
    apiKey: 'synthetic', model: 'synthetic-model' }));
  const server = app.listen(0, '127.0.0.1'); await new Promise(resolve => server.once('listening', resolve));
  t.after(async () => {
    server.closeAllConnections(); upstream.closeAllConnections();
    await Promise.all([new Promise(resolve => server.close(resolve)), new Promise(resolve => upstream.close(resolve))]);
    require.cache[authPath] = oldAuth;
    if (oldEnv) require.cache[envPath] = oldEnv; else delete require.cache[envPath];
  });
  async function request(f, method, path, body, tokenOverride) {
    const token = tokenOverride === undefined ? jwt.sign({ id: f.userId, tokenVersion: 0 }, secret, { expiresIn: '1h' }) : tokenOverride;
    const res = await fetch(`http://127.0.0.1:${server.address().port}/${f.prefix || 'recaps'}${path}`, { method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    const text = await res.text(); return { status: res.status, body: text ? JSON.parse(text) : null, headers: res.headers };
  }
  await t.test('B232 HTTP real JWT/consent and loopback provider full flow, whitelist response', async () => {
    const f = await setup({ prepare: false }); const before = upstreamCalls;
    const p = await request(f, 'POST', '/prepare', f.body); assert.equal(p.status, 200);
    assert.equal(p.body.local_pending_verified, false); assert.equal(p.body.coverage.fullBook, false);
    assert(!('user_id' in p.body)); assert(!('selected_sources_json' in p.body)); assert(!('request_mac' in p.body));
    f.input = { request_id: randomUUID(), expected_revision: p.body.revision,
      source_fingerprint: p.body.source_fingerprint, consent_scope_fingerprint: p.body.source_fingerprint };
    assert.equal((await request(f, 'POST', `/${f.id}/generate`, f.input)).body.status, 'succeeded');
    assert.equal(upstreamCalls, before + 1);
    const r = await request(f, 'GET', `/${f.id}`); assert.equal(r.status, 200); assert(r.body.result.knowledge.length);
    assert.equal(r.headers.get('cache-control'), 'no-store, private');
    assert.equal((await request(f, 'POST', `/${f.id}/save`, { request_id: randomUUID(), expected_revision: r.body.revision })).body.is_saved, true);
    assert.equal((await request(f, 'DELETE', `/${f.id}`, {})).status, 204);
    assert.equal((await request(f, 'GET', `/${f.id}`)).status, 410);
  });
  await t.test('B232 explicit server composition uses real auth/consent and formal resolver, remains unmounted in app', async () => {
    const f = await setup({ prepare: false }); f.prefix = 'composed'; const before = upstreamCalls;
    const p = await request(f, 'POST', '/prepare', f.body); assert.equal(p.status, 200);
    const body = { request_id: randomUUID(), expected_revision: p.body.revision,
      source_fingerprint: p.body.source_fingerprint, consent_scope_fingerprint: p.body.source_fingerprint };
    assert.equal((await request(f, 'POST', `/${f.id}/generate`, body)).body.status, 'succeeded');
    assert.equal(upstreamCalls, before + 1);
    assert.equal((await read(f)).coverage_json.sourceCompleteness, 'server_selected_records');
    const fs = require('node:fs');
    assert(!fs.readFileSync(require.resolve('../src/app'), 'utf8').includes('bookRecapHttpAdapter'));
  });
  await t.test('B232 HTTP missing/bad/expired token and consent refuse before dispatch', async () => {
    const f = await setup(), before = upstreamCalls;
    for (const token of ['', 'not-jwt', jwt.sign({ id: f.userId }, secret, { expiresIn: -1 }), jwt.sign({ id: f.userId, tokenVersion: 7 }, secret)]) {
      assert.equal((await request(f, 'POST', `/${f.id}/generate`, f.input, token)).status, 401);
    }
    await db.query('UPDATE users SET ai_consent_version=0 WHERE id=$1', [f.userId]);
    assert.equal((await request(f, 'POST', `/${f.id}/generate`, f.input)).status, 428);
    assert.equal((await request(f, 'DELETE', `/${f.id}`, {})).status, 204); assert.equal(upstreamCalls, before);
  });
  await t.test('B232 HTTP foreign IDs/books and forged trust/result rejected, error bodies sanitized', async () => {
    const f = await setup(), g = await setup(), before = upstreamCalls;
    assert.equal((await request(g, 'GET', `/${f.id}`)).status, 404);
    const foreign = await request(g, 'POST', '/prepare', { ...f.body, recap_id: randomUUID(), request_id: randomUUID() });
    assert.equal(foreign.status, 422); assert.equal(foreign.body.error_code, 'RECAP_SOURCE_UNAVAILABLE');
    for (const extra of [{ user_id: g.userId }, { result_json: { private: 'secret' } }, { snapshot: {} }, { sourceCompleteness: 'server_selected_records' }]) {
      const r = await request(f, 'POST', '/prepare', { ...f.body, ...extra }); assert.equal(r.status, 400);
      assert(!JSON.stringify(r.body).includes('secret'));
    }
    assert.equal((await request(f, 'POST', '/prepare', { ...f.body, book_id: 'wrong-book', recap_id: randomUUID(), request_id: randomUUID() })).status, 422);
    assert.equal((await request(f, 'POST', `/${f.id}/generate`, { ...f.input, source_fingerprint: '0'.repeat(64) })).status, 409);
    assert.equal(upstreamCalls, before);
  });
  await t.test('B232 HTTP all/none/subset followups preserve scope, unrelated ordinary chat/free notes excluded', async () => {
    const f = await setup({ prepare: false });
    const fu = await entries.createFollowUp(f.userId, f.entryId, 'Follow up', 'Historical AI');
    const unrelated = await entries.createEntry(f.userId, { source: 'thought', book_id: f.bookId,
      user_input: 'Unselected private material', metadata_json: { origin: 'reader' } });
    for (const ids of [undefined, [], [fu.id]]) {
      const body = { ...f.body, recap_id: randomUUID(), request_id: randomUUID(),
        selected_sources: [{ entry_id: f.entryId, ...(ids === undefined ? {} : { follow_up_ids: ids }) }] };
      const r = await request(f, 'POST', '/prepare', body); assert.equal(r.status, 200);
      assert.equal(r.body.coverage.includedFollowUps, ids?.length === 0 ? 0 : 1);
      const inspected = await storage.inspect(f.userId, body.recap_id);
      assert(!inspected.snapshot.evidence.some(e => e.entryId === unrelated.id));
    }
    const privateF = await setup({ prepare: false, payload: { metadata_json: { origin: 'reader', free_note_id: 'private' } } });
    const excluded = await request(privateF, 'POST', '/prepare', privateF.body);
    assert.equal(excluded.status, 422); assert.equal(excluded.body.error_code, 'RECAP_SOURCE_UNAVAILABLE');
    const conversationId = randomUUID();
    await db.query("INSERT INTO xiaou_conversations(id,user_id,kind) VALUES($1,$2,'chat')", [conversationId, f.userId]);
    assert.equal((await request(f, 'POST', '/prepare', { ...f.body, selected_sources: [{ entry_id: conversationId }] })).status, 422);
  });
  await t.test('B232 HTTP provider failure sanitized and no partial success or automatic retry', async () => {
    const f = await setup(), before = upstreamCalls; upstreamMode = 'error';
    try {
      const r = await request(f, 'POST', `/${f.id}/generate`, f.input);
      assert.equal(r.status, 502); assert.deepEqual(r.body, { error_code: 'RECAP_UPSTREAM_FAILED' });
      await noBody(f, 'failed');
      assert.equal((await request(f, 'POST', `/${f.id}/generate`, f.input)).body.status, 'failed');
      assert.equal(upstreamCalls, before + 1);
    } finally { upstreamMode = 'success'; }
  });
  await t.test('B232 HTTP oversized body and excessive evidence refused without model activity', async () => {
    const f = await setup({ prepare: false }), before = upstreamCalls;
    const huge = await request(f, 'POST', '/prepare', { ...f.body, snapshot: 'x'.repeat(90000) });
    assert.equal(huge.status, 413); assert.equal(huge.body.error_code, 'RECAP_INPUT_BUDGET');
    const tooMany = await request(f, 'POST', '/prepare', { ...f.body,
      selected_sources: Array.from({ length: 81 }, () => ({ entry_id: randomUUID() })) });
    assert.equal(tooMany.status, 400);
    assert.equal(await read(f), undefined); assert.equal(upstreamCalls, before);
  });
  await t.test('B232 HTTP cancel without AI consent aborts real hanging upstream', async () => {
    const f = await setup(); upstreamMode = 'hang'; upstreamGate = gate();
    const pending = request(f, 'POST', `/${f.id}/generate`, f.input);
    await upstreamGate.promise;
    try {
      await db.query('UPDATE users SET ai_consent_version=0 WHERE id=$1', [f.userId]);
      assert.equal((await request(f, 'POST', `/${f.id}/operations/${f.input.request_id}/cancel`, {})).status, 204);
      assert.equal((await pending).body.error_code, 'RECAP_CANCELLED'); await noBody(f, 'cancelled');
    } finally { upstreamMode = 'success'; }
  });
  await t.test('B232 HTTP request disconnect aborts upstream and persists cancellation', async () => {
    const f = await setup(); upstreamMode = 'hang'; upstreamGate = gate();
    const token = jwt.sign({ id: f.userId, tokenVersion: 0 }, secret, { expiresIn: '1h' });
    const req = http.request({ host: '127.0.0.1', port: server.address().port,
      path: `/recaps/${f.id}/generate`, method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` } });
    req.on('error', () => {}); req.end(JSON.stringify(f.input)); await upstreamGate.promise; req.destroy();
    try {
      // Bounded observation, not a scheduling assumption: the handler must settle on disconnect.
      const deadline = Date.now() + 3000;
      while ((await read(f)).state === 'generating' && Date.now() < deadline) await new Promise(r => setTimeout(r, 10));
      await noBody(f, 'cancelled'); assert.equal((await operation(f)).status, 'cancelled');
    } finally { upstreamMode = 'success'; }
  });
};
