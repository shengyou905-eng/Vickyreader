const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const { randomUUID } = require('node:crypto');
const { AsyncLocalStorage } = require('node:async_hooks');
const { Pool } = require('pg');
const express = require('express');
const { fingerprint } = require('../services/bookRecapContract');
const { createBookRecapRepository } = require('./bookRecap.repository');
const { createBookRecapStorage } = require('../services/bookRecapStorage.service');
const { bookRecapConfig } = require('../config/bookRecap');
const fixture = require('../../../tool/book_recap_eval/fixture.v1.json');
const target = process.env.RECAP_SYNTHETIC_DATABASE_URL;
const data = process.env.RECAP_SYNTHETIC_DATA;

if (!target || !data) {
  test('B2.1 real PostgreSQL', { skip: 'Use test-support/runRecapSynthetic.js; existing databases are forbidden' }, () => {});
} else {
  const url = new URL(target);
  const root = path.dirname(path.resolve(data));
  if (url.hostname !== '127.0.0.1' || url.username !== 'recap_test' ||
      url.pathname !== '/zhidu_recap_b21_synthetic' || url.search || url.password ||
      path.dirname(root) !== path.resolve(os.tmpdir()) || !path.basename(root).startsWith('zhidu-recap-b21-') ||
      !fs.existsSync(path.join(data, 'PG_VERSION'))) throw Error('Refusing non-disposable target');
  const pool = new Pool({ connectionString: target, max: 6, connectionTimeoutMillis: 3000 });
  const probe = new AsyncLocalStorage();
  const db = {
    query: (sql, args) => pool.query(sql, args),
    withTransaction: async action => {
      const c = await pool.connect();
      try {
        await c.query('BEGIN');
        await c.query("SET LOCAL lock_timeout='3s'");
        const observer = probe.getStore();
        if (observer?.connected) observer.connected(c.processID);
        const result = await action(async (s, a) => {
          const value = await c.query(s, a);
          if (observer?.after) await observer.after(s, a, value);
          return value;
        });
        await c.query('COMMIT');
        return result;
      } catch (e) { await c.query('ROLLBACK'); throw e; } finally { c.release(); }
    },
  };
  // Reuse the REAL legacy repository/controllers/router, but never import dotenv/default pool.
  require.cache[require.resolve('../config/db')] = { exports: db };
  const conversations = require('./xiaouConversation.repository');
  require.cache[require.resolve('../middleware/auth')] = { exports: (req, res, next) => {
    req.user = { id: req.get('x-synthetic-owner') }; next();
  } };
  const legacyRoutes = require('../routes/xiaouConversation.routes');
  const repo = createBookRecapRepository(db);
  let now = new Date('2026-10-21T00:00:00Z');
  const config = bookRecapConfig();
  const resolver = {
    async resolve(tx, userId, bookId, selection) {
      const e = selection[0];
      const rows = await tx('SELECT * FROM user_entries WHERE id=$1 AND user_id=$2 AND book_id=$3',
        [e.entry_id, userId, bookId]);
      if (!rows.rowCount) throw Object.assign(new Error('Synthetic source unavailable'), { error_code: 'RECAP_SOURCE_UNAVAILABLE' });
      const row = rows.rows[0];
      const snapshot = {
        schemaVersion: 1, scope: { userId, origin: 'https://synthetic.invalid', bookId },
        book: { title: fixture.bookTitle, author: null, documentVersion: null },
        evidence: [], coverage: { basis: 'reading_traces', fullBook: false,
          sourceCompleteness: 'local_and_supplied_cache', availableEntries: 1, includedEntries: 1,
          includedFollowUps: 0, quarantinedEntries: 0, selectionApplied: true },
      };
      for (const [field, kind, text] of [
        ['reading_ai_context.selectedText', 'book_excerpt', row.original_text],
        ['user_input', 'user_question', row.user_input],
      ]) {
        snapshot.evidence.push({
          id: 'e-' + fingerprint([row.id, null, field]), entryId: row.id, followUpId: null,
          sourceField: field, kind, text, provenance: kind === 'book_excerpt' ? 'reader_context' : 'trace',
          createdAt: row.created_at.toISOString(), updatedAt: row.updated_at.toISOString(), pendingUpload: false,
          anchor: kind === 'book_excerpt' ? {
            chapterIndex: '7', chapterTitle: 'Synthetic', documentVersion: null,
            status: 'fragment_only', start: null, end: null,
          } : null,
        });
      }
      snapshot.fingerprint = fingerprint(snapshot);
      return { snapshot, dependencies: snapshot.evidence.map(e => ({
        evidenceId: e.id, entryId: row.id, sourceField: e.sourceField, kind: e.kind, provenance: e.provenance,
        digest: fingerprint([e.text, e.updatedAt]), followUpSetDigest: fingerprint([]),
      })) };
    },
    async revalidate(tx, userId, row) {
      return (await this.resolve(tx, userId, row.book_id, row.selected_sources_json)).snapshot;
    },
  };
  const service = createBookRecapStorage({ repository: repo, resolver,
    macKey: Buffer.alloc(32, 7), origin: 'https://synthetic.invalid', config, clock: () => now });
  async function user() {
    const id = randomUUID();
    await db.query('INSERT INTO users(id,email,password_hash) VALUES($1,$2,$3)', [id, id + '@example.invalid', 'synthetic']);
    return id;
  }
  async function setup() {
    const userId = await user(), entryId = randomUUID(), id = randomUUID();
    await db.query(`INSERT INTO user_entries(id,user_id,source,book_id,original_text,user_input)
      VALUES($1,$2,'ai_question','synthetic-book',$3,$4)`, [entryId, userId, fixture.excerpt, fixture.question]);
    const body = { recap_id: id, request_id: randomUUID(), book_id: 'synthetic-book',
      selected_sources: [{ entry_id: entryId, follow_up_ids: [] }] };
    return { userId, entryId, id, body };
  }
  function generate(row) {
    return { request_id: randomUUID(), expected_revision: row.revision,
      source_fingerprint: row.source_fingerprint, consent_scope_fingerprint: row.source_fingerprint };
  }
  async function answer(f) {
    const s = (await resolver.resolve(db.query, f.userId, f.body.book_id, f.body.selected_sources)).snapshot;
    return { schemaVersion: 1, snapshotFingerprint: s.fingerprint,
      knowledge: [{ id: 'k1', kind: 'argument', title: 'Necessary condition',
        summary: 'The stated condition is not a guarantee.', basis: 'source_supported',
        evidenceRefs: [s.evidence[0].id], quotes: [{ evidenceId: s.evidence[0].id, text: fixture.excerpt, voice: 'author' }] }],
      relations: [], myThinking: [{ id: 't1', title: 'An open question', summary: 'The reader asked about the condition.',
        basis: 'user_explicit', evidenceRefs: [s.evidence[1].id], quotes: [] }],
      openQuestions: [], nextQuestions: [] };
  }
  async function ready() {
    const f = await setup();
    const row = await service.prepare(f.userId, f.body);
    const input = generate(row);
    const op = await service.begin(f.userId, f.id, input);
    const result = await answer(f);
    const completed = await service.complete(f.userId, f.id, op.request_id, op.generation_id, result,
      { completed: true, finishReason: 'stop' });
    return { ...f, row: completed, op, result };
  }
  const sqlPath = path.join(__dirname, '../db/migrations');
  const up = fs.readFileSync(path.join(sqlPath, '010_reading_recaps.up.sql'), 'utf8');
  const down = fs.readFileSync(path.join(sqlPath, '010_reading_recaps.down.sql'), 'utf8');
  async function migration(sql) {
    const c = await pool.connect();
    try { await c.query(sql); } catch (e) { await c.query('ROLLBACK'); throw e; } finally { c.release(); }
  }
  async function request(server, owner, method, route, body) {
    return new Promise((resolve, reject) => {
      const req = http.request({ hostname: '127.0.0.1', port: server.address().port,
        method, path: '/api/xiaou' + route,
        headers: { 'x-synthetic-owner': owner, 'content-type': 'application/json' } }, res => {
        let raw = ''; res.on('data', b => { raw += b; });
        res.on('end', () => resolve({ status: res.statusCode, raw, json: raw ? JSON.parse(raw) : null }));
      });
      req.on('error', reject); req.end(body ? JSON.stringify(body) : undefined);
    });
  }
  test('B2.1 isolated PostgreSQL and legacy HTTP boundary', async t => {
    t.after(() => pool.end());
    assert.equal(fs.realpathSync((await db.query('SHOW data_directory')).rows[0].data_directory), fs.realpathSync(data));
    assert.equal((await db.query("SELECT count(*) FROM pg_tables WHERE schemaname='public'")).rows[0].count, '0');
    // ONLY this new empty cluster gets full schema; never an existing business DB.
    await db.query(fs.readFileSync(path.join(__dirname, '../db/schema.sql'), 'utf8'));
    const historical = await setup();
    const before = (await db.query('SELECT * FROM user_entries ORDER BY id')).rows;
    const normal = await conversations.createConversation(historical.userId, { title: 'ordinary', kind: 'chat' });
    await conversations.appendMessage(historical.userId, normal.id, { role: 'user', content: 'ordinary content' });
    const app = express(); app.use(express.json()); app.use('/api/xiaou', legacyRoutes);
    app.use((err, _req, res, _next) => res.status(err.statusCode || 500).json({ error: err.message }));
    const server = app.listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    t.after(() => new Promise(resolve => server.close(resolve)));

    await t.test('generic list/get/append/delete operate before 010 (no recap_id column)', async () => {
      assert.equal((await conversations.listConversations(historical.userId))[0].id, normal.id);
      assert.equal((await conversations.getConversation(historical.userId, normal.id)).messages.length, 1);
      const disposable = await conversations.createConversation(historical.userId, { kind: 'xiaou_asks' });
      assert(await conversations.deleteConversation(historical.userId, disposable.id));
      const r = await request(server, historical.userId, 'GET', '/conversations');
      assert.equal(r.status, 200);
      assert.equal(r.json.conversations.length, 1);
      const entries = require('./entry.repository');
      const temporary = await entries.createEntry(historical.userId, { source: 'thought', book_id: 'legacy-synthetic' });
      await entries.updateEntryImportance(historical.userId, temporary.id, true);
      await entries.createFollowUp(historical.userId, temporary.id, 'old schema question', 'old schema answer');
      assert(await entries.deleteEntry(historical.userId, temporary.id));
    });
    await t.test('upgrade, duplicate rejection, empty rollback/reapply preserve original rows', async () => {
      await migration(up);
      assert.deepEqual((await db.query('SELECT * FROM user_entries ORDER BY id')).rows, before);
      await assert.rejects(migration(up), { code: '42P07' });
      await migration(down);
      assert.equal((await conversations.getConversation(historical.userId, normal.id)).messages[0].content, 'ordinary content');
      await migration(up);
      assert.equal((await db.query(`SELECT count(*) FROM information_schema.tables
        WHERE table_schema='public' AND table_name LIKE 'reading_recap%'`)).rows[0].count, '4');
    });
    await t.test('source resolution is scoped; no local draft auto-claim or implicit upload', async () => {
      const f = await setup(), other = await user();
      await assert.rejects(service.prepare(other, f.body), { error_code: 'RECAP_SOURCE_UNAVAILABLE' });
      assert.equal((await db.query('SELECT count(*) FROM reading_recaps')).rows[0].count, '0');
    });
    await t.test('transaction failure after parent insert rolls back parent, dependencies and operation', async () => {
      const f = await setup();
      const bad = createBookRecapStorage({ repository: repo, resolver: { ...resolver,
        async resolve(...args) {
          const m = await resolver.resolve(...args);
          m.dependencies[1].revision = '99999999999999999999999999999';
          return m;
        } }, origin: 'https://synthetic.invalid', macKey: Buffer.alloc(32, 7) });
      await assert.rejects(bad.prepare(f.userId, f.body), { code: '22003' });
      assert.equal((await db.query('SELECT count(*) FROM reading_recaps WHERE id=$1', [f.id])).rows[0].count, '0');
    });
    await t.test('same request concurrent prepare is idempotent; changed payload conflicts', async () => {
      const f = await setup();
      const rows = await Promise.all(Array.from({ length: 5 }, () => service.prepare(f.userId, f.body)));
      assert.equal(new Set(rows.map(r => r.id)).size, 1);
      await assert.rejects(service.prepare(f.userId, { ...f.body, selected_sources: [{ entry_id: f.entryId }] }),
        { error_code: 'RECAP_REQUEST_CONFLICT' });
      assert.equal((await db.query('SELECT count(*) FROM reading_recap_operations WHERE user_id=$1', [f.userId])).rows[0].count, '1');
    });
    await t.test('composite owner/book FKs, state checks, exclusive recap conversation', async () => {
      const f = await ready(), other = await user();
      await assert.rejects(db.query(`INSERT INTO reading_recap_feedback(recap_id,user_id,client_request_id,category)
        VALUES($1,$2,$3,'low_value')`, [f.id, other, randomUUID()]), { code: '23503' });
      await assert.rejects(db.query('UPDATE reading_recap_sources SET book_id=$2 WHERE recap_id=$1', [f.id, 'another-book']), { code: '23503' });
      await assert.rejects(db.query("UPDATE reading_recaps SET state='stale' WHERE id=$1", [f.id]), { code: '23514' });
      await assert.rejects(db.query("UPDATE reading_recaps SET book_id=NULL WHERE id=$1", [f.id]), { code: '23514' });
      await assert.rejects(db.query(`INSERT INTO xiaou_conversations(user_id,kind,recap_id)
        VALUES($1,'book_recap',$2)`, [other, f.id]), e => ['23503','23505'].includes(e.code));
      await assert.rejects(db.query(`INSERT INTO xiaou_conversations(user_id,kind,recap_id)
        VALUES($1,'chat',$2)`, [f.userId, f.id]), { code: '23514' });
    });
    await t.test('REAL legacy list/get/append/delete HTTP routes cannot disclose or change dedicated data', async () => {
      const f = await ready();
      const conv = (await db.query('SELECT id FROM xiaou_conversations WHERE recap_id=$1', [f.id])).rows[0].id;
      await db.query(`INSERT INTO xiaou_messages(conversation_id,user_id,role,content)
        VALUES($1,$2,'assistant','SYNTHETIC_RECAP_PRIVATE')`, [conv, f.userId]);
      const list = await request(server, f.userId, 'GET', '/conversations');
      assert.equal(list.status, 200); assert.deepEqual(list.json.conversations, []);
      for (const [method, suffix, body] of [
        ['GET', '', null], ['POST', '/messages', { role: 'assistant', content: 'injected' }], ['DELETE', '', null],
      ]) {
        const r = await request(server, f.userId, method, '/conversations/' + conv + suffix, body);
        assert.equal(r.status, 404); assert(!r.raw.includes('SYNTHETIC_RECAP_PRIVATE'));
      }
      assert.equal((await request(server, f.userId, 'POST', '/conversations', { kind: 'book_recap' })).status, 400);
      assert.equal((await request(server, f.userId, 'POST', '/conversations', { recap_id: f.id })).status, 400);
      assert.equal((await db.query('SELECT content FROM xiaou_messages WHERE conversation_id=$1', [conv])).rows[0].content,
        'SYNTHETIC_RECAP_PRIVATE');
      assert.equal((await request(server, historical.userId, 'GET', '/conversations/' + normal.id)).status, 200);
    });
    await t.test('begin retries reserve one operation and generation token; distinct attempt conflicts', async () => {
      const f = await setup(), row = await service.prepare(f.userId, f.body), body = generate(row);
      const ops = await Promise.all(Array.from({ length: 4 }, () => service.begin(f.userId, f.id, body)));
      assert.equal(new Set(ops.map(o => o.generation_id)).size, 1);
      assert.equal(ops.filter(o => o.executionClaimed).length, 1);
      await assert.rejects(service.begin(f.userId, f.id, { ...body, request_id: randomUUID() }),
        { error_code: 'RECAP_REVISION_CONFLICT' });
      await assert.rejects(service.complete(f.userId, f.id, body.request_id, ops[0].generation_id, await answer(f)),
        { code: 'RECAP_INCOMPLETE' });
      assert.equal((await repo.transaction(f.userId, tx => repo.find(tx, f.userId, f.id))).result_json, null);
    });
    await t.test('save retries are idempotent and feedback is private; delete cleans derived-only data', async () => {
      const f = await ready(), original = (await db.query('SELECT * FROM user_entries WHERE id=$1', [f.entryId])).rows[0];
      const body = { request_id: randomUUID(), expected_revision: f.row.revision };
      const saved = await Promise.all([service.save(f.userId, f.id, body), service.save(f.userId, f.id, body)]);
      assert(saved.every(r => r.is_saved));
      assert.equal(saved[0].revision, saved[1].revision);
      const fb = { request_id: randomUUID(), expected_revision: saved[0].revision, category: 'inaccurate',
        comment: 'Synthetic private feedback', item_id: 'k1' };
      assert.equal(await service.feedback(f.userId, f.id, fb), await service.feedback(f.userId, f.id, fb));
      await assert.rejects(service.get(await user(), f.id), { error_code: 'RECAP_NOT_FOUND' });
      await service.remove(f.userId, f.id);
      await service.remove(f.userId, f.id);
      const deleted = await repo.transaction(f.userId, tx => repo.find(tx, f.userId, f.id));
      for (const key of ['result_json','coverage_json','selected_sources_json','book_id','source_fingerprint']) assert.equal(deleted[key], null);
      for (const table of ['reading_recap_sources','reading_recap_feedback','xiaou_conversations']) {
        assert.equal((await db.query('SELECT count(*) FROM ' + table + ' WHERE recap_id=$1', [f.id])).rows[0].count, '0');
      }
      assert.equal((await db.query('SELECT count(*) FROM reading_recap_operations WHERE recap_id=$1 AND request_mac IS NOT NULL', [f.id])).rows[0].count, '0');
      assert.deepEqual((await db.query('SELECT * FROM user_entries WHERE id=$1', [f.entryId])).rows[0], original);
      await assert.rejects(service.save(f.userId, f.id, body), { error_code: 'RECAP_UNAVAILABLE' });
    });
    await t.test('deletion BEFORE prepare fences the ID; another account cannot delete it', async () => {
      const f = await setup();
      await service.remove(f.userId, f.id);
      await assert.rejects(service.prepare(f.userId, f.body), { error_code: 'RECAP_UNAVAILABLE' });
      await assert.rejects(service.remove(await user(), f.id), { error_code: 'RECAP_NOT_FOUND' });
    });
    await t.test('cancel and deadline reject late completions; no automatic execution after restart', async () => {
      const f = await setup(), row = await service.prepare(f.userId, f.body), input = generate(row);
      const op = await service.begin(f.userId, f.id, input);
      await service.cancel(f.userId, f.id, op.request_id);
      await service.cancel(f.userId, f.id, op.request_id);
      await assert.rejects(service.complete(f.userId, f.id, op.request_id, op.generation_id, await answer(f),
        { completed: true, finishReason: 'stop' }), { error_code: 'RECAP_COMPLETION_REJECTED' });
      const g = await setup(), prepared = await service.prepare(g.userId, g.body), body = generate(prepared);
      const running = await service.begin(g.userId, g.id, body);
      const previous = now; now = new Date(now.getTime() + 121000);
      try {
        await service.cancel(g.userId, g.id, running.request_id, { expiredOnly: true });
        const restarted = createBookRecapStorage({ repository: repo, resolver, macKey: Buffer.alloc(32, 7),
          origin: 'https://synthetic.invalid', clock: () => now });
        await assert.rejects(restarted.begin(g.userId, g.id, body), { error_code: 'RECAP_REQUEST_RETIRED' });
      } finally { now = previous; }
    });
    await t.test('out-of-band SQL bypassing repositories still fails source revalidation', async () => {
      const f = await ready();
      await db.query("UPDATE user_entries SET user_input='edited synthetic question' WHERE id=$1", [f.entryId]);
      await assert.rejects(service.get(f.userId, f.id), { error_code: 'RECAP_SOURCE_CHANGED' });
      // Maintenance SQL bypasses application hooks; it is NOT an approved source write path.
      assert.equal((await db.query('SELECT state FROM reading_recaps WHERE id=$1', [f.id])).rows[0].state, 'ready');
      await db.query('DELETE FROM user_entries WHERE id=$1', [f.entryId]);
      await assert.rejects(service.get(f.userId, f.id), { error_code: 'RECAP_SOURCE_UNAVAILABLE' });
    });
    await t.test('deletion racing completion cannot resurrect derived text', async () => {
      const f = await setup(), row = await service.prepare(f.userId, f.body), input = generate(row);
      const op = await service.begin(f.userId, f.id, input), result = await answer(f);
      await Promise.allSettled([
        service.remove(f.userId, f.id),
        service.complete(f.userId, f.id, op.request_id, op.generation_id, result, { completed: true, finishReason: 'stop' }),
      ]);
      const final = await repo.transaction(f.userId, tx => repo.find(tx, f.userId, f.id));
      assert.equal(final.state, 'deleted'); assert.equal(final.result_json, null);
    });
    await t.test('account cascade cleans all derived structures and existing dedicated messages', async () => {
      const f = await ready();
      await db.query('DELETE FROM users WHERE id=$1', [f.userId]);
      for (const table of ['reading_recaps','reading_recap_sources','reading_recap_operations',
        'reading_recap_feedback','xiaou_conversations','xiaou_messages']) {
        assert.equal((await db.query('SELECT count(*) FROM ' + table + ' WHERE user_id=$1', [f.userId])).rows[0].count, '0');
      }
    });
    await t.test('dependency identities must match every supplied evidence record', async () => {
      const f = await setup();
      const brokenResolver = { ...resolver, async resolve(...args) {
        const material = await resolver.resolve(...args);
        material.dependencies[0].entryId = randomUUID();
        return material;
      } };
      const broken = createBookRecapStorage({ repository: repo, resolver: brokenResolver,
        macKey: Buffer.alloc(32, 7), origin: 'https://synthetic.invalid' });
      await assert.rejects(broken.prepare(f.userId, f.body), { error_code: 'RECAP_DEPENDENCIES_INCOMPLETE' });
      assert.equal((await db.query('SELECT count(*) FROM reading_recaps WHERE id=$1', [f.id])).rows[0].count, '0');
    });
    await t.test('scope consent, completion token and changed evidence fail closed', async () => {
      const f = await setup(), row = await service.prepare(f.userId, f.body), body = generate(row);
      await assert.rejects(service.begin(f.userId, f.id, { ...body, consent_scope_fingerprint: '0'.repeat(64) }),
        { error_code: 'RECAP_SCOPE_CHANGED' });
      const op = await service.begin(f.userId, f.id, body), result = await answer(f);
      await assert.rejects(service.complete(f.userId, f.id, op.request_id, randomUUID(), result,
        { completed: true, finishReason: 'stop' }), { error_code: 'RECAP_COMPLETION_REJECTED' });
      await db.query("UPDATE user_entries SET user_input='changed before completion' WHERE id=$1", [f.entryId]);
      await assert.rejects(service.complete(f.userId, f.id, op.request_id, op.generation_id, result,
        { completed: true, finishReason: 'stop' }), { error_code: 'RECAP_SOURCE_CHANGED' });
      assert.equal((await repo.transaction(f.userId, tx => repo.find(tx, f.userId, f.id))).result_json, null);
    });
    await t.test('unknown result version and offline revalidation never return cached text', async () => {
      const f = await ready();
      await db.query('UPDATE reading_recaps SET schema_version=2 WHERE id=$1', [f.id]);
      await assert.rejects(service.get(f.userId, f.id), { error_code: 'RECAP_VERSION_UNSUPPORTED' });
      await db.query('UPDATE reading_recaps SET schema_version=1 WHERE id=$1', [f.id]);
      const offline = createBookRecapStorage({ repository: repo, resolver: { ...resolver,
        async revalidate() { throw new Error('Synthetic offline'); } },
        macKey: Buffer.alloc(32, 7), origin: 'https://synthetic.invalid', clock: () => now });
      await assert.rejects(offline.get(f.userId, f.id), /Synthetic offline/);
    });
    await t.test('preview expiry refuses body; timeout cleanup works after prepared expiry', async () => {
      const f = await ready(), previous = now;
      now = new Date(now.getTime() + 86401000);
      try { await assert.rejects(service.get(f.userId, f.id), { error_code: 'RECAP_EXPIRED' }); }
      finally { now = previous; }
      const g = await setup();
      const short = createBookRecapStorage({ repository: repo, resolver, macKey: Buffer.alloc(32, 7),
        origin: 'https://synthetic.invalid', clock: () => now,
        config: bookRecapConfig({ RECAP_TEST_PREPARED_SECONDS: '1', RECAP_TEST_OPERATION_SECONDS: '2' }) });
      const row = await short.prepare(g.userId, g.body), op = await short.begin(g.userId, g.id, generate(row));
      now = new Date(now.getTime() + 3000);
      try {
        await short.cancel(g.userId, g.id, op.request_id, { expiredOnly: true });
        assert.equal((await repo.transaction(g.userId, tx => repo.operation(tx, g.userId, op.request_id))).status, 'interrupted');
      } finally { now = previous; }
    });
    await t.test('request IDs and same-title books remain owner and stable-book scoped', async () => {
      const a = await setup(), b = await setup();
      b.body.request_id = a.body.request_id;
      await service.prepare(a.userId, a.body);
      await service.prepare(b.userId, b.body);
      await assert.rejects(service.prepare(a.userId, { ...a.body, recap_id: randomUUID(), request_id: randomUUID(),
        book_id: 'same-title-different-edition' }), { error_code: 'RECAP_SOURCE_UNAVAILABLE' });
      assert.equal((await db.query('SELECT count(*) FROM reading_recap_operations WHERE request_id=$1',
        [a.body.request_id])).rows[0].count, '2');
    });
    await require('../../test-support/bookRecapB22Scenarios')(t,
      { db, pool, probe, repo, service, resolver, setup, ready, answer, generate, user, conversations, request, server });
    await require('../../test-support/bookRecapB231Scenarios')(t, { db, pool, probe, repo, user, generate });
    await require('../../test-support/bookRecapB232Scenarios')(t, { db, pool, probe, repo, user, generate });
    await require('../../test-support/bookRecapB233Scenarios')(t, { db, pool, probe, repo, user, generate });
    await require('../../test-support/bookRecapB24b1Scenarios')(t, { db, pool, probe, repo, user, generate });
    await t.test('down migration refuses populated data/fences and leaves structure intact', async () => {
      await assert.rejects(migration(down), { code: 'P0001' });
      assert.equal((await db.query("SELECT to_regclass('reading_recaps') AS name")).rows[0].name, 'reading_recaps');
    });
    await t.test('failed migration rolls back all newly created tables and the added column', async () => {
      const c = await pool.connect();
      try {
        await c.query('CREATE SCHEMA recap_migration_failure');
        await c.query('SET search_path=recap_migration_failure,public');
        await c.query('CREATE TABLE users(id UUID PRIMARY KEY)');
        await c.query("CREATE TABLE xiaou_conversations(id UUID PRIMARY KEY,user_id UUID,kind TEXT)");
        await c.query("INSERT INTO xiaou_conversations VALUES($1,$2,'book_recap')", [randomUUID(), randomUUID()]);
        await assert.rejects(c.query(up), { code: '23514' });
        await c.query('ROLLBACK');
        assert.equal((await c.query("SELECT count(*) FROM information_schema.tables WHERE table_schema='recap_migration_failure'")).rows[0].count, '2');
        assert.equal((await c.query("SELECT count(*) FROM information_schema.columns WHERE table_schema='recap_migration_failure' AND column_name='recap_id'")).rows[0].count, '0');
      } finally { await c.query('RESET search_path'); c.release(); }
    });
  });
}
