const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const express = require('express');
const http = require('node:http');
const { createServerBookRecapStorage } = require('../src/services/bookRecapStorage.service');
const { createBookRecapExecutor } = require('../src/services/bookRecapExecutor');
const { createBookRecapFollowUpExecutor } = require('../src/services/bookRecapFollowUpExecutor');
const { createBookRecapAuthorization } = require('../src/services/bookRecapAuthorization');
const { createBookRecapModelTransport } = require('../src/services/bookRecapModelTransport');
const { prepareFollowUp } = require('../src/services/bookRecapFollowUpContract');
const { createBookRecapHttpAdapter } = require('../src/routes/bookRecapHttpAdapter');
const fixture = require('../../tool/book_recap_eval/fixture.v1.json');
const gate = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };

module.exports = async function scenarios(t, { db, pool, repo, user, generate, probe }) {
  const entries = require('../src/repositories/entry.repository');
  const conversations = require('../src/repositories/xiaouConversation.repository');
  const storage = createServerBookRecapStorage({ repository: repo, origin: 'https://synthetic.invalid', macKey: Buffer.alloc(32, 33) });
  const authorize = createBookRecapAuthorization(1);
  const principal = f => ({ userId: f.userId, tokenVersion: 0 });
  const make = (transport = async req => response(req), extra = {}) => createBookRecapFollowUpExecutor({ storage,
    authorize, transport, model: 'synthetic-model', ...extra });
  const run = (executor, f, options) => executor.ask(principal(f), f.id, f.input, options);
  const read = async f => (await db.query('SELECT * FROM reading_recaps WHERE id=$1', [f.id])).rows[0];
  const op = async f => (await db.query('SELECT * FROM reading_recap_operations WHERE user_id=$1 AND request_id=$2', [f.userId, f.input.request_id])).rows[0];
  const messages = async f => (await db.query(`SELECT m.* FROM xiaou_messages m JOIN xiaou_conversations c
    ON c.id=m.conversation_id WHERE c.recap_id=$1 ORDER BY m.role`, [f.id])).rows;
  async function setup({ saved = false, userId = null } = {}) {
    userId ||= await user();
    await db.query('UPDATE users SET ai_consent_version=1 WHERE id=$1', [userId]);
    const bookId = randomUUID(), id = randomUUID();
    const entry = await entries.createEntry(userId, { source: 'ai_question', book_id: bookId,
      original_text: fixture.excerpt, user_input: fixture.question, ai_explanation: fixture.answer,
      metadata_json: { origin: 'reader', reading_ai_context: { scope: 'selection', selectedText: fixture.excerpt } } });
    const f = { userId, id, bookId, entryId: entry.id };
    const row = await storage.prepare(userId, { recap_id: id, request_id: randomUUID(), book_id: bookId,
      selected_sources: [{ entry_id: entry.id }] });
    const generator = createBookRecapExecutor({ storage, authorize, model: 'synthetic-model', transport: async req => {
      const s = JSON.parse(req.messages[1].content);
      return { completed: true, finishReason: 'stop', text: JSON.stringify({ schemaVersion: 1,
        snapshotFingerprint: s.snapshotFingerprint, knowledge: [{ id: 'k1', kind: 'argument', title: 'Condition',
          summary: 'A condition is not a guarantee.', basis: 'source_supported',
          evidenceRefs: [s.evidence.find(e => e.kind === 'book_excerpt').id], quotes: [] }],
        relations: [], myThinking: [], openQuestions: [], nextQuestions: [] }) };
    } });
    await generator.generate(principal(f), id, generate(row));
    if (saved) await storage.save(userId, id, { request_id: randomUUID(), expected_revision: (await read(f)).revision });
    await next(f);
    return f;
  }
  async function next(f, question = 'Is this condition sufficient?') {
    f.input = { request_id: randomUUID(), expected_revision: (await read(f)).revision, question };
  }
  function response(req) {
    const s = JSON.parse(req.messages[1].content);
    return { completed: true, finishReason: 'stop', text: JSON.stringify({ schemaVersion: 1,
      snapshotFingerprint: s.snapshotFingerprint, parts: [{ text: 'It is necessary, not sufficient.',
        basis: 'source_supported', evidenceRefs: [s.evidence.find(e => e.kind === 'book_excerpt').id], quotes: [] }] }) };
  }
  async function paused(f, extra = {}) {
    const entered = gate(), release = gate(); let calls = 0;
    const executor = make(async req => { calls++; entered.resolve(); await release.promise; return response(req); }, extra);
    const settled = run(executor, f).then(value => ({ value }), error => ({ error }));
    await entered.promise;
    return { executor, release, settled, calls: () => calls };
  }
  async function unchanged(f, status, count = 0) {
    assert.equal((await read(f)).state, 'ready');
    assert((await read(f)).result_json);
    assert.equal((await messages(f)).length, count);
    assert.equal((await op(f)).status, status);
  }

  for (const saved of [false, true]) await t.test(`B233 ${saved ? 'saved' : 'temporary ready'} pair and replay, no upload cursor changes`, async () => {
    const f = await setup({ saved }); let calls = 0;
    const before = (await db.query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [f.userId])).rows;
    const executor = make(async req => { calls++; return response(req); });
    assert.equal((await run(executor, f)).status, 'succeeded');
    assert.equal((await run(executor, f)).replay, true); assert.equal(calls, 1);
    const history = await executor.list(principal(f), f.id);
    assert.equal(history.turns.length, 1); assert.equal(history.turns[0].question, f.input.question);
    assert.equal(history.local_pending_verified, false); assert.equal(history.coverage.fullBook, false);
    assert.equal((await read(f)).is_saved, saved);
    assert.equal(BigInt(history.revision), BigInt(f.input.expected_revision) + 1n);
    await unchanged(f, 'succeeded', 2);
    assert.deepEqual((await db.query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [f.userId])).rows, before);
  });
  await t.test('B233 14 complete turns preserve initial evidence, corrections and source classification', async () => {
    const f = await setup(); let calls = 0, original;
    const executor = make(async req => {
      const s = JSON.parse(req.messages[1].content);
      original ||= s.evidence; assert.deepEqual(s.evidence, original);
      assert(s.evidence.some(e => e.kind === 'historical_ai')); assert.equal(s.derivedRecap.kind, 'historical_ai');
      assert.equal(req.messages.length, 3 + calls * 2);
      if (calls > 0) assert.equal(req.messages[2].content, 'Correction: necessary is not sufficient.');
      assert(!JSON.stringify(req).includes(f.userId)); assert(!JSON.stringify(req).includes('metadata_json'));
      calls++; return response(req);
    });
    for (let i = 0; i < 14; i++) {
      await next(f, i ? `Follow up ${i}` : 'Correction: necessary is not sufficient.');
      await run(executor, f);
    }
    const turns = (await executor.list(principal(f), f.id)).turns;
    assert.equal(turns.length, 14); assert.deepEqual(turns.map(v => v.turn), Array.from({ length: 14 }, (_, i) => i + 1));
  });
  await t.test('B233 history budget rejects before dispatch without silently trimming pairs', async () => {
    const f = await setup(); const executor = make(); let succeeded = 0;
    for (let i = 0; i < 10; i++) {
      await next(f, 'Long question '.repeat(250));
      try { await run(executor, f); succeeded++; }
      catch (error) { assert.equal(error.error_code, 'RECAP_HISTORY_BUDGET'); break; }
    }
    assert(succeeded > 0 && succeeded < 10);
    assert.equal((await messages(f)).length, succeeded * 2);
    assert.equal(await op(f), undefined); // budget failure rolls back the new claim
  });
  await t.test('B233 same request concurrent replay, altered question and second operation rejected', async () => {
    const f = await setup(), p = await paused(f);
    try {
      assert.deepEqual(await run(p.executor, f), { status: 'running', replay: true });
      await assert.rejects(p.executor.ask(principal(f), f.id, { ...f.input, question: 'Changed' }), { error_code: 'RECAP_REQUEST_CONFLICT' });
      await assert.rejects(p.executor.ask(principal(f), f.id, { ...f.input, request_id: randomUUID() }), { error_code: 'RECAP_BUSY' });
    } finally { p.release.resolve(); }
    assert.equal((await p.settled).value.status, 'succeeded'); assert.equal(p.calls(), 1);
    await unchanged(f, 'succeeded', 2);
  });
  await t.test('B233 same question as new deliberate request retains independent pair', async () => {
    const f = await setup(), executor = make(); await run(executor, f); await next(f); await run(executor, f);
    assert.equal((await messages(f)).length, 4);
  });
  for (const [name, mutate, code] of [
    ['invalid JSON', r => { r.text = '{'; }, 'RECAP_INVALID_RESULT'],
    ['incomplete', r => { r.completed = false; }, 'RECAP_INVALID_RESULT'],
    ['truncated', r => { r.finishReason = 'length'; }, 'RECAP_INVALID_RESULT'],
    ['foreign reference', r => { const a = JSON.parse(r.text); a.parts[0].evidenceRefs = ['foreign']; r.text = JSON.stringify(a); }, 'RECAP_INVALID_RESULT'],
    ['AI as primary', (r, req) => { const a = JSON.parse(r.text); a.parts[0].evidenceRefs = [JSON.parse(req.messages[1].content).evidence.find(e => e.kind === 'historical_ai').id]; r.text = JSON.stringify(a); }, 'RECAP_INVALID_RESULT'],
    ['invented quote', r => { const a = JSON.parse(r.text); a.parts[0].quotes = [{ evidenceId: a.parts[0].evidenceRefs[0], text: 'invented', voice: 'author' }]; r.text = JSON.stringify(a); }, 'RECAP_INVALID_RESULT'],
    ['output budget', r => { r.text = 'x'.repeat(131073); }, 'RECAP_OUTPUT_BUDGET'],
  ]) await t.test(`B233 ${name} no half pair and failed replay never dispatches`, async () => {
    const f = await setup(); let calls = 0;
    const executor = make(async req => { calls++; const r = response(req); mutate(r, req); return r; });
    await assert.rejects(run(executor, f), { error_code: code });
    await unchanged(f, 'failed'); assert.equal((await run(executor, f)).status, 'failed'); assert.equal(calls, 1);
  });
  await t.test('B233 provider failure sanitized and valid older pair survives', async () => {
    const f = await setup(); await run(make(), f); await next(f);
    await assert.rejects(run(make(async () => { throw Error('private provider text'); }), f), { message: 'RECAP_UPSTREAM_FAILED' });
    await unchanged(f, 'failed', 2);
  });
  await t.test('B233 timeout ignores late provider without losing recap', async () => {
    const f = await setup(), release = gate();
    const executor = make(async req => { await release.promise; return response(req); }, { timeoutMs: 20 });
    await assert.rejects(run(executor, f), { error_code: 'RECAP_TIMEOUT' }); release.resolve();
    await unchanged(f, 'failed');
  });
  await t.test('B233 explicit cancel wins, preserves previous pair, late result cannot append', async () => {
    const f = await setup(); await run(make(), f); await next(f); const p = await paused(f);
    await p.executor.cancel(f.userId, f.id, f.input.request_id);
    p.release.resolve(); assert.equal((await p.settled).error.error_code, 'RECAP_CANCELLED');
    await unchanged(f, 'cancelled', 2);
    await next(f); await run(make(), f); assert.equal((await messages(f)).length, 4);
  });
  await t.test('B233 completion wins before cancel', async () => {
    const f = await setup(), executor = make(); await run(executor, f);
    await assert.rejects(executor.cancel(f.userId, f.id, f.input.request_id), { error_code: 'RECAP_ALREADY_COMPLETED' });
    await unchanged(f, 'succeeded', 2);
  });
  for (const action of ['edit', 'delete', 'followup', 'delete-recap']) await t.test(`B233 ${action} during model wait invalidates all derived history`, async () => {
    const f = await setup(); await run(make(), f); await next(f); const p = await paused(f);
    try {
      if (action === 'edit') await entries.updateEntryImportance(f.userId, f.entryId, true);
      if (action === 'delete') await entries.deleteEntry(f.userId, f.entryId);
      if (action === 'followup') await entries.createFollowUp(f.userId, f.entryId, 'New original discussion', 'AI');
      if (action === 'delete-recap') await storage.remove(f.userId, f.id);
    } finally { p.release.resolve(); }
    assert((await p.settled).error);
    assert.equal((await messages(f)).length, 0); assert.equal((await read(f)).result_json, null);
    await assert.rejects(p.executor.list(principal(f), f.id));
    await assert.rejects(run(p.executor, f)); assert.equal(p.calls(), 1);
  });
  for (const action of ['consent', 'token', 'account']) await t.test(`B233 revoked ${action} cannot commit or read`, async () => {
    const f = await setup(), p = await paused(f);
    try {
      const sql = { consent: 'ai_consent_version=0', token: 'token_version=1', account: "account_status='banned'" }[action];
      await db.query(`UPDATE users SET ${sql} WHERE id=$1`, [f.userId]);
    } finally { p.release.resolve(); }
    assert((await p.settled).error); await unchanged(f, 'failed');
    await assert.rejects(p.executor.list(principal(f), f.id));
  });
  await t.test('B233 token expiration during model call prevents saving', async () => {
    const f = await setup(), value = { ...principal(f), expiresAt: Math.floor(Date.now() / 1000) + 2 };
    const executor = make(async req => { value.expiresAt = 1; return response(req); }, {
      authorize: (tx, uid, p) => authorize(tx, uid, { ...p, expiresAt: value.expiresAt }),
    });
    await assert.rejects(executor.ask(value, f.id, f.input), { error_code: 'RECAP_AUTH_REQUIRED' });
    await unchanged(f, 'failed');
  });
  await t.test('B233 cross user/recap and client history or model result cannot enter request', async () => {
    const f = await setup(), other = await setup(), executor = make();
    await assert.rejects(executor.ask(principal(other), f.id, f.input), { error_code: 'RECAP_NOT_FOUND' });
    await assert.rejects(executor.list(principal(other), f.id), { error_code: 'RECAP_NOT_FOUND' });
    for (const field of ['user_id', 'history', 'snapshot', 'result_json', 'book_id', 'source_fingerprint']) {
      await assert.rejects(executor.ask(principal(f), f.id, { ...f.input, [field]: 'forged' }), { name: 'ZodError' });
    }
    await run(executor, f);
    const sameOwner = await setup({ userId: f.userId });
    await assert.rejects(executor.ask(principal(f), sameOwner.id, { ...sameOwner.input, request_id: f.input.request_id }), { error_code: 'RECAP_REQUEST_CONFLICT' });
  });
  for (const damage of ['question', 'answer', 'one-deleted', 'pair-deleted', 'wrong-owner', 'foreign-conversation']) {
    await t.test(`B233 ${damage} in dedicated history is rejected before model dispatch`, async () => {
      const f = await setup(); await run(make(), f); const rows = await messages(f);
      if (damage === 'question' || damage === 'answer') {
        const row = rows.find(m => m.role === (damage === 'question' ? 'user' : 'assistant'));
        const v = JSON.parse(row.content);
        if (damage === 'question') v.body.question = 'Tampered question'; else v.answer.parts[0].text = 'Tampered conclusion';
        await db.query('UPDATE xiaou_messages SET content=$2 WHERE id=$1', [row.id, JSON.stringify(v)]);
      }
      if (damage === 'one-deleted') await db.query('DELETE FROM xiaou_messages WHERE id=$1', [rows[0].id]);
      if (damage === 'pair-deleted') await db.query('DELETE FROM xiaou_messages WHERE conversation_id=$1', [rows[0].conversation_id]);
      if (damage === 'wrong-owner') await db.query('UPDATE xiaou_messages SET user_id=$2 WHERE id=$1', [rows[0].id, await user()]);
      if (damage === 'foreign-conversation') {
        const other = await setup({ userId: f.userId }); await run(make(), other);
        const foreign = (await messages(other))[0];
        await db.query('UPDATE xiaou_messages SET content=$2 WHERE id=$1', [rows[0].id, foreign.content]);
      }
      await next(f); let calls = 0; const executor = make(async req => { calls++; return response(req); });
      await assert.rejects(run(executor, f), { error_code: 'RECAP_HISTORY_INVALID' });
      await assert.rejects(executor.list(principal(f), f.id), { error_code: 'RECAP_HISTORY_INVALID' }); assert.equal(calls, 0);
    });
  }
  await t.test('B233 history deletion during generation prevents late append', async () => {
    const f = await setup(); await run(make(), f); await next(f); const p = await paused(f);
    try { await db.query('DELETE FROM xiaou_messages WHERE conversation_id=$1', [(await messages(f))[0].conversation_id]); }
    finally { p.release.resolve(); }
    assert.equal((await p.settled).error.error_code, 'RECAP_HISTORY_INVALID');
    await unchanged(f, 'failed');
  });
  await t.test('B233 transaction failure after user insert rolls back both pair and revision', async () => {
    const f = await setup(), before = await read(f); let faulted = false;
    await assert.rejects(probe.run({ after(sql) {
      if (sql.includes('INSERT INTO xiaou_messages') && !faulted) { faulted = true; throw Error('synthetic rollback'); }
    } }, () => run(make(), f)), { error_code: 'RECAP_UPSTREAM_FAILED' });
    assert(faulted); await unchanged(f, 'failed'); assert.equal((await read(f)).revision, before.revision);
  });
  await t.test('B233 disconnect after pair SQL but before commit rolls back successful operation', async () => {
    const f = await setup(), entered = gate(), release = gate(), controller = new AbortController();
    const settled = probe.run({ async after(sql, args) {
      if (sql.includes('UPDATE reading_recap_operations SET status=') && args[2] === 'succeeded') {
        entered.resolve(); await release.promise;
      }
    } }, () => run(make(), f, { signal: controller.signal })).then(value => ({ value }), error => ({ error }));
    await entered.promise; controller.abort(); release.resolve();
    assert.equal((await settled).error.error_code, 'RECAP_CANCELLED'); await unchanged(f, 'cancelled');
  });
  for (const order of ['save-first', 'follow-first']) await t.test(`B233 ${order} consistent revision, no pair loss`, async () => {
    const f = await setup();
    if (order === 'save-first') {
      const p = await paused(f);
      await storage.save(f.userId, f.id, { request_id: randomUUID(), expected_revision: f.input.expected_revision });
      p.release.resolve(); assert.equal((await p.settled).error.error_code, 'RECAP_COMPLETION_REJECTED');
      await unchanged(f, 'failed');
    } else {
      await run(make(), f);
      await assert.rejects(storage.save(f.userId, f.id, { request_id: randomUUID(), expected_revision: f.input.expected_revision }), { error_code: 'RECAP_REVISION_CONFLICT' });
      await unchanged(f, 'succeeded', 2);
    }
  });
  await t.test('B233 expired claim cannot be replayed to a second model call', async () => {
    const f = await setup();
    await storage.beginFollowUp(f.userId, f.id, f.input, { authorize: (tx, uid) => authorize(tx, uid, principal(f)) });
    await db.query("UPDATE reading_recap_operations SET deadline_at=now()-interval '1 second' WHERE user_id=$1 AND request_id=$2", [f.userId, f.input.request_id]);
    let calls = 0;
    assert.equal((await run(make(async req => { calls++; return response(req); }), f)).status, 'interrupted');
    assert.equal(calls, 0); await unchanged(f, 'interrupted');
  });
  await t.test('B233 expired preview and unknown card cannot start followup', async () => {
    const f = await setup(), executor = make();
    await assert.rejects(executor.ask(principal(f), f.id, { ...f.input, item_id: 'not-a-card' }), { error_code: 'RECAP_ITEM_NOT_FOUND' });
    await db.query("UPDATE reading_recaps SET expires_at=now()-interval '1 second' WHERE id=$1", [f.id]);
    await assert.rejects(run(executor, f), { error_code: 'RECAP_EXPIRED' });
    await assert.rejects(executor.list(principal(f), f.id), { error_code: 'RECAP_EXPIRED' });
  });
  await t.test('B233 ordinary conversations cannot access populated dedicated messages', async () => {
    const f = await setup(); await run(make(), f); const id = (await messages(f))[0].conversation_id;
    assert.equal(await conversations.getConversation(f.userId, id), null);
    assert.equal(await conversations.appendMessage(f.userId, id, { role: 'assistant', content: 'injected' }), null);
    assert.equal(await conversations.deleteConversation(f.userId, id), false);
    assert(!(await conversations.listConversations(f.userId)).some(c => c.id === id));
    await assert.rejects(conversations.createConversation(f.userId, { kind: 'book_recap' }));
    const normal = await conversations.createConversation(f.userId, { kind: 'chat' });
    await conversations.appendMessage(f.userId, normal.id, { role: 'user', content: 'ordinary private material' });
    await next(f); await run(make(async req => { assert(!JSON.stringify(req).includes('ordinary private material')); return response(req); }), f);
    assert.equal((await conversations.getConversation(f.userId, normal.id)).messages.length, 1);
  });
  for (const firstAction of ['complete', 'delete']) await t.test(`B233 actual transaction barrier ${firstAction} first, no resurrection or deadlock`, async () => {
    const f = await setup(), check = (tx, uid) => authorize(tx, uid, principal(f));
    const claim = await storage.beginFollowUp(f.userId, f.id, f.input, { authorize: check });
    const context = await storage.dispatchFollowUp(f.userId, f.id, f.input.request_id, claim.generation_id, check);
    const result = JSON.parse(response(prepareFollowUp(context, f.input, { model: 'synthetic' }).request).text);
    const complete = () => storage.completeFollowUp(f.userId, f.id, f.input.request_id, claim.generation_id,
      result, { completed: true, finishReason: 'stop' }, { authorize: check, context, body: f.input });
    const remove = () => entries.deleteEntry(f.userId, f.entryId);
    const entered = gate(), release = gate(), secondPid = gate(); let firstPid, held = false, b;
    const settle = promise => promise.then(value => ({ value }), error => ({ error }));
    const a = settle(probe.run({ connected: pid => { firstPid = pid; }, async after(sql) {
      if (!held && sql.includes('INSERT INTO sync_user_cursors')) { held = true; entered.resolve(); await release.promise; }
    } }, firstAction === 'complete' ? complete : remove));
    try {
      await entered.promise;
      b = settle(probe.run({ connected: pid => secondPid.resolve(pid) }, firstAction === 'complete' ? remove : complete));
      const pid = await secondPid.promise; let blocked = false;
      for (const until = Date.now() + 2000; Date.now() < until;) {
        if ((await pool.query('SELECT $1::int=ANY(pg_blocking_pids($2)) blocked', [firstPid, pid])).rows[0].blocked) { blocked = true; break; }
        await new Promise(r => setTimeout(r, 5));
      }
      assert(blocked, 'second transaction must actually wait on first');
    } finally { release.resolve(); await Promise.all([a, b]); }
    const [one, two] = await Promise.all([a, b]); assert(!one.error, one.error?.stack);
    if (firstAction === 'delete') assert.equal(two.error?.error_code, 'RECAP_UNAVAILABLE'); else assert(!two.error);
    assert.equal((await read(f)).state, 'invalidated'); assert.equal((await messages(f)).length, 0);
  });
  await t.test('B233 dispatch repeats authorization and source checks before sending', async () => {
    const f = await setup(); let calls = 0;
    const wrapped = { ...storage, async dispatchFollowUp(...args) {
      await entries.deleteEntry(f.userId, f.entryId); return storage.dispatchFollowUp(...args);
    } };
    await assert.rejects(run(make(async req => { calls++; return response(req); }, { storage: wrapped }), f), { error_code: 'RECAP_UNAVAILABLE' });
    assert.equal(calls, 0); assert.equal((await messages(f)).length, 0);
  });
  await t.test('B233 two devices different recaps of one account do not mix histories', async () => {
    const a = await setup(), b = await setup({ userId: a.userId });
    await next(a, 'Device A'); await next(b, 'Device B'); const executor = make();
    await Promise.all([run(executor, a), run(executor, b)]);
    assert.equal((await executor.list(principal(a), a.id)).turns[0].question, 'Device A');
    assert.equal((await executor.list(principal(b), b.id)).turns[0].question, 'Device B');
  });
  for (const mode of ['success', 'disconnect', 'hang']) await t.test(`B233 real loopback SSE ${mode} through follow-up transport`, async () => {
    const f = await setup(); let calls = 0;
    const upstream = http.createServer(async (req, res) => {
      let raw = ''; for await (const chunk of req) raw += chunk;
      calls++; const request = JSON.parse(raw);
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      if (mode === 'hang') { res.write(': waiting\n\n'); return; }
      const text = response(request).text;
      res.write(`data: ${JSON.stringify({ model: 'synthetic-model', choices: [{ index: 0, delta: { content: text }, finish_reason: null }] })}\n\n`);
      if (mode === 'disconnect') { res.end(); return; }
      res.end(`data: ${JSON.stringify({ choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] })}\n\ndata: [DONE]\n\n`);
    });
    await new Promise(r => upstream.listen(0, '127.0.0.1', r));
    try {
      const executor = make(createBookRecapModelTransport({ endpoint: `http://127.0.0.1:${upstream.address().port}/chat`,
        apiKey: 'synthetic-not-a-real-key' }), { timeoutMs: mode === 'hang' ? 150 : 3000 });
      if (mode === 'success') { await run(executor, f); await unchanged(f, 'succeeded', 2); }
      else {
        await assert.rejects(run(executor, f), { error_code: mode === 'hang' ? 'RECAP_TIMEOUT' : 'RECAP_STREAM_INCOMPLETE' });
        await unchanged(f, 'failed');
      }
      assert.equal(calls, 1);
    } finally { upstream.closeAllConnections(); await new Promise(r => upstream.close(r)); }
  });
  await t.test('B233 unmounted adapter followup post/get/cancel DTO and auth scopes', async () => {
    const f = await setup(), entered = gate(), release = gate(); let hold = false;
    const executor = make(async req => { if (hold) { entered.resolve(); await release.promise; } return response(req); });
    const auth = (req, res, next) => { if (req.get('x-test-user') !== f.userId) return res.sendStatus(401);
      req.user = { id: f.userId, tokenVersion: 0 }; req.authUser = { id: f.userId }; next(); };
    const app = express(); app.use('/recaps', createBookRecapHttpAdapter({ storage,
      executor: { cancel: storage.cancel }, followUpExecutor: executor, auth,
      requireAiConsent: (_req, _res, next) => next() }));
    const server = http.createServer(app); await new Promise(r => server.listen(0, '127.0.0.1', r));
    try {
      const url = `http://127.0.0.1:${server.address().port}/recaps/${f.id}/follow-ups`;
      assert.equal((await fetch(url)).status, 401);
      const headers = { 'x-test-user': f.userId, 'content-type': 'application/json' };
      assert.equal((await fetch(url, { method: 'POST', headers, body: JSON.stringify({ ...f.input, history: [] }) })).status, 400);
      const success = await fetch(url, { method: 'POST', headers, body: JSON.stringify(f.input) });
      assert.equal(success.status, 200); assert.equal((await success.json()).status, 'succeeded');
      const history = await fetch(url, { headers }); assert.match(history.headers.get('cache-control'), /no-store/);
      const body = await history.json(); assert.equal(body.turns.length, 1);
      assert(!JSON.stringify(body).includes('generationId')); assert(!JSON.stringify(body).includes('seal'));
      await next(f); hold = true;
      const pending = fetch(url, { method: 'POST', headers, body: JSON.stringify(f.input) });
      await entered.promise;
      await db.query('UPDATE users SET ai_consent_version=0 WHERE id=$1', [f.userId]);
      assert.equal((await fetch(url, { headers })).status, 428);
      const cancelled = await fetch(url.replace('/follow-ups', `/operations/${f.input.request_id}/cancel`),
        { method: 'POST', headers, body: '{}' });
      assert.equal(cancelled.status, 204); assert.equal((await pending).status, 409);
      release.resolve(); await unchanged(f, 'cancelled', 2);
    } finally { release.resolve(); server.closeAllConnections(); await new Promise(r => server.close(r)); }
  });
};
