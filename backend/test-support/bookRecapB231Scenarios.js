const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { setTimeout: delay } = require('node:timers/promises');
const { createBookRecapSourceResolver, LIMITS } = require('../src/services/bookRecapSourceResolver');
const { createServerBookRecapStorage } = require('../src/services/bookRecapStorage.service');
const { lockSelection } = require('../src/repositories/bookRecapSource.repository');
const { prepareGeneration } = require('../src/services/bookRecapGeneration');
const { validateResult } = require('../src/services/bookRecapContract');
const fixture = require('../../tool/book_recap_eval/fixture.v1.json');

// Only called from the guarded disposable-cluster suite; never loads a DB config.
module.exports = async function scenarios(t, { db, pool, probe, repo, user, generate }) {
  const entries = require('../src/repositories/entry.repository');
  const { permanentlyDeleteBookData } = require('../src/repositories/bookDeletion.repository');
  const origin = 'https://synthetic.invalid';
  const resolver = createBookRecapSourceResolver({ origin });
  const service = createServerBookRecapStorage({ repository: repo, origin, macKey: Buffer.alloc(32, 31) });
  const completed = { completed: true, finishReason: 'stop' };
  async function setup({ owner, bookId = 'same-title-book-a', payload = {} } = {}) {
    const userId = owner || await user();
    const entry = await entries.createEntry(userId, { source: 'ai_question', book_id: bookId,
      book_title: 'Same title', chapter_index: '7', chapter_title: 'Recorded chapter',
      original_text: fixture.excerpt, user_input: fixture.question, ai_explanation: fixture.answer,
      metadata_json: { origin: 'reader', reading_ai_context: { scope: 'selection', selectedText: fixture.excerpt } },
      ...payload });
    const id = randomUUID();
    return { userId, entryId: entry.id, id, body: { recap_id: id, request_id: randomUUID(), book_id: bookId,
      selected_sources: [{ entry_id: entry.id }] } };
  }
  const row = async f => (await db.query('SELECT * FROM reading_recaps WHERE id=$1', [f.id])).rows[0];
  const material = f => repo.transaction(f.userId, async tx => {
    await lockSelection(tx, f.userId, f.body.book_id, f.body.selected_sources);
    return resolver.resolve(tx, f.userId, f.body.book_id, f.body.selected_sources);
  });
  function answer(s) {
    const book = s.evidence.find(e => e.kind === 'book_excerpt');
    const question = s.evidence.find(e => e.kind === 'user_question' && (!book || e.entryId === book.entryId));
    return { schemaVersion: 1, snapshotFingerprint: s.fingerprint,
      knowledge: book ? [{ id: 'k1', kind: 'argument', title: 'A condition', summary: 'A condition is not a guarantee.',
        basis: 'source_supported', evidenceRefs: [book.id], quotes: [] }] : [],
      myThinking: question ? [{ id: 't1', title: 'A question', summary: 'The reader asked about the condition.',
        basis: 'user_explicit', evidenceRefs: [question.id], quotes: [] }] : [],
      relations: [], openQuestions: [], nextQuestions: [] };
  }
  async function running(f) {
    f = f || await setup();
    const prepared = await service.prepare(f.userId, f.body);
    const op = await service.begin(f.userId, f.id, generate(prepared));
    return { ...f, op, result: answer((await material(f)).snapshot) };
  }
  const complete = f => service.complete(f.userId, f.id, f.op.request_id, f.op.generation_id, f.result, completed);
  async function ready(f) { const r = await running(f); await complete(r); return r; }
  const sourceError = { error_code: 'RECAP_SOURCE_UNAVAILABLE' };
  const changed = { error_code: 'RECAP_SOURCE_CHANGED' };
  const tooLarge = { error_code: 'RECAP_SCOPE_TOO_LARGE' };
  async function follow(f, question = 'Why?', response = 'Historical answer') {
    return entries.createFollowUp(f.userId, f.entryId, question, response);
  }

  await t.test('B231 formal resolver classifies owned cloud evidence and integrates prepare/begin/complete/get', async () => {
    const f = await setup(); const fu = await follow(f);
    const before = (await db.query('SELECT * FROM user_entries WHERE id=$1', [f.entryId])).rows;
    const seq = (await db.query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [f.userId])).rows;
    const m = await material(f), s = m.snapshot;
    assert.equal(s.coverage.sourceCompleteness, 'server_selected_records');
    assert.equal(s.coverage.fullBook, false); assert.equal(s.coverage.includedFollowUps, 1);
    assert.equal(s.evidence.find(e => e.followUpId === fu.id && e.sourceField === 'answer').kind, 'historical_ai');
    assert(s.evidence.every(e => !e.pendingUpload));
    assert.equal(s.evidence.find(e => e.kind === 'book_excerpt').provenance, 'reader_context');
    const r = await ready(f); assert.equal((await service.get(r.userId, r.id)).state, 'ready');
    assert.deepEqual((await db.query('SELECT * FROM user_entries WHERE id=$1', [f.entryId])).rows, before);
    assert.deepEqual((await db.query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [f.userId])).rows, seq);
  });
  await t.test('B231 rejects cross-account, wrong book, absent entry and forged client body', async () => {
    const f = await setup();
    await assert.rejects(service.prepare(await user(), f.body), sourceError);
    await assert.rejects(service.prepare(f.userId, { ...f.body, book_id: 'wrong-book' }), sourceError);
    await assert.rejects(service.prepare(f.userId, { ...f.body, selected_sources: [{ entry_id: randomUUID() }] }), sourceError);
    for (const extra of [{ sourceCompleteness: 'server_selected_records' }, { result: {} }, { original_text: 'fake' }]) {
      await assert.rejects(service.prepare(f.userId, { ...f.body, ...extra }));
    }
    assert.equal(await row(f), undefined);
  });
  await t.test('B231 follow-up must belong to both selected parent and authenticated owner', async () => {
    const f = await setup(), g = await setup({ owner: f.userId }); const fu = await follow(g);
    f.body.selected_sources[0].follow_up_ids = [fu.id];
    await assert.rejects(service.prepare(f.userId, f.body), sourceError);
    const other = await user();
    await db.query(`INSERT INTO user_entry_follow_ups(entry_id,user_id,question,answer) VALUES($1,$2,'private','private')`, [f.entryId, other]);
    delete f.body.selected_sources[0].follow_up_ids;
    await assert.rejects(service.prepare(f.userId, f.body), sourceError);
  });
  await t.test('B231 client ID maps only actual column; aliases conflict, legacy metadata never claims identity', async () => {
    const f = await setup(), client = 'synthetic-client';
    await db.query('UPDATE user_entries SET client_entry_id=$2 WHERE id=$1', [f.entryId, client]);
    const a = await material(f);
    f.body.selected_sources = [{ client_entry_id: client }];
    assert.equal((await material(f)).snapshot.fingerprint, a.snapshot.fingerprint);
    f.body.selected_sources.push({ entry_id: f.entryId });
    await assert.rejects(service.prepare(f.userId, f.body), sourceError);
    const legacy = await setup();
    await db.query(`UPDATE user_entries SET metadata_json=metadata_json || '{"local_id":"legacy-only"}'::jsonb WHERE id=$1`, [legacy.entryId]);
    legacy.body.selected_sources = [{ client_entry_id: 'legacy-only' }];
    await assert.rejects(service.prepare(legacy.userId, legacy.body), sourceError);
    legacy.body.selected_sources = [{ entry_id: legacy.entryId }];
    assert.equal((await material(legacy)).snapshot.coverage.includedEntries, 1);
  });
  await t.test('B231 same-title independent imports remain separate; duplicate text histories retain IDs', async () => {
    const a = await setup(), b = await setup({ owner: a.userId, bookId: 'same-title-book-b' });
    a.body.selected_sources.push({ entry_id: b.entryId });
    await assert.rejects(service.prepare(a.userId, a.body), sourceError);
    const c = await setup({ owner: a.userId });
    a.body.selected_sources[1] = { entry_id: c.entryId };
    const m = await material(a);
    assert.equal(m.snapshot.coverage.includedEntries, 2);
    assert.equal(m.snapshot.evidence.filter(e => e.kind === 'book_excerpt').length, 2);
  });
  await t.test('B231 permanent deletion fences old book even if an entry is improperly reinserted; new import independent', async () => {
    const f = await ready(); await permanentlyDeleteBookData(f.userId, f.body.book_id);
    assert.equal((await row(f)).state, 'invalidated');
    await db.query(`INSERT INTO user_entries(id,user_id,source,book_id,user_input) VALUES($1,$2,'thought',$3,'old identity')`,
      [f.entryId, f.userId, f.body.book_id]);
    await assert.rejects(material(f), { statusCode: 410 });
    const fresh = await setup({ owner: f.userId, bookId: 'new-import' });
    assert.equal((await service.prepare(fresh.userId, fresh.body)).state, 'prepared');
  });
  await t.test('B231 highlights are attention, notes are user expression, AI openings and answers never book evidence', async () => {
    for (const [source, originValue, expected] of [
      ['highlight', 'reader', 'highlight'], ['thought', 'reader', 'user_note'],
      ['manual', 'reader', 'user_note'], ['ai_question', 'xiaou_asks', 'ai_prompt'],
    ]) {
      const f = await setup({ payload: { source, metadata_json: { origin: originValue } } });
      const s = (await material(f)).snapshot;
      assert(s.evidence.some(e => e.kind === expected));
      assert(!s.evidence.some(e => e.kind === 'book_excerpt'));
      assert.equal(s.evidence.find(e => e.sourceField === 'ai_explanation').kind, 'historical_ai');
    }
  });
  await t.test('B231 forged metadata cannot certify original_text or supply exact location/current document', async () => {
    const f = await setup({ payload: { metadata_json: { origin: 'reader', provenance: 'current_document',
      verified: true, source_hash: 'a'.repeat(64), sourceCompleteness: 'server_selected_records',
      document_version: 'forged', startOffset: 0, endOffset: 10 } } });
    let m = await material(f);
    assert.equal(m.snapshot.evidence.find(e => e.sourceField === 'original_text').kind, 'unverified_excerpt');
    const request = prepareGeneration(m.snapshot, m.snapshot.scope, { model: 'synthetic' });
    assert(!JSON.parse(request.request.messages[1].content).evidence.some(e => e.kind === 'unverified_excerpt'));
    await db.query(`UPDATE user_entries SET metadata_json=metadata_json || $2::jsonb WHERE id=$1`,
      [f.entryId, JSON.stringify({ reading_ai_context: { scope: 'selection', selectedText: 'Stored context, not book certification' } })]);
    m = await material(f); const excerpt = m.snapshot.evidence.find(e => e.kind === 'book_excerpt');
    assert.equal(excerpt.provenance, 'reader_context'); assert.equal(excerpt.anchor.status, 'fragment_only');
    assert.equal(excerpt.anchor.start, null); assert.equal(excerpt.anchor.documentVersion, null);
    assert.deepEqual(m.snapshot.book, { title: null, author: null, documentVersion: null });
  });
  await t.test('B231 private notes (including nested authorization) and unknown origin are rejected', async () => {
    for (const metadata of [{ origin: 'free_note' }, { origin: 'other' }, { free_note_id: 'n' },
      { origin: 'reader', context: { freeNoteId: 'n' } }, { origin: 'reader', authorized_free_note: {} }]) {
      const f = await setup({ payload: { metadata_json: metadata } });
      await assert.rejects(material(f), sourceError);
      assert.equal(await row(f), undefined);
    }
  });
  await t.test('B231 context book mismatch is rejected; selection/page/chapter retain exact stored range', async () => {
    for (const [scope, field] of [['selection', 'selectedText'], ['page', 'pageText'], ['chapter', 'chapterText']]) {
      const excerpt = '  synthetic range\nwith spacing  ';
      const f = await setup({ payload: { metadata_json: { origin: 'reader', reading_ai_context: { scope, [field]: excerpt } } } });
      const e = (await material(f)).snapshot.evidence.find(e => e.kind === 'book_excerpt');
      assert.equal(e.text, excerpt); assert.equal(e.sourceField, 'reading_ai_context.' + field);
      const snapshot = (await material(f)).snapshot;
      const input = prepareGeneration(snapshot, snapshot.scope, { model: 'synthetic' });
      assert.equal(JSON.parse(input.request.messages[1].content).evidence.find(v => v.id === e.id).sourceField, e.sourceField);
    }
    const f = await setup({ payload: { metadata_json: { reading_ai_context: { scope: 'selection', bookId: 'other', selectedText: 'fake' } } } });
    await assert.rejects(material(f), sourceError);
  });
  await t.test('B231 expected digest is only a veto; owner and stored identity always checked', async () => {
    const f = await setup(), m = await material(f);
    f.body.selected_sources[0].expected_digest = m.dependencies[0].digest;
    await service.prepare(f.userId, f.body);
    await assert.rejects(service.prepare(await user(), f.body), sourceError);
    f.body.recap_id = randomUUID(); f.body.request_id = randomUUID();
    f.body.selected_sources[0].expected_digest = '0'.repeat(64);
    await assert.rejects(service.prepare(f.userId, f.body), { error_code: 'RECAP_SOURCE_VERSION_MISMATCH' });
  });
  for (const change of ['add', 'edit', 'delete']) await t.test(`B231 whole follow-up digest detects out-of-band ${change} even if none selected`, async () => {
    const f = await setup(); const fu = await follow(f); f.body.selected_sources[0].follow_up_ids = [];
    await ready(f);
    if (change === 'add') await db.query(`INSERT INTO user_entry_follow_ups(entry_id,user_id,question,answer) VALUES($1,$2,'new','AI')`, [f.entryId, f.userId]);
    if (change === 'edit') await db.query(`UPDATE user_entry_follow_ups SET answer='different AI' WHERE id=$1`, [fu.id]);
    if (change === 'delete') await db.query('DELETE FROM user_entry_follow_ups WHERE id=$1', [fu.id]);
    await assert.rejects(service.get(f.userId, f.id), changed);
  });
  await t.test('B231 real follow-up create triggers stale and cleans body via B22 hooks', async () => {
    const f = await ready(); await follow(f);
    assert.equal((await row(f)).state, 'stale'); assert.equal((await row(f)).result_json, null);
    await assert.rejects(service.get(f.userId, f.id), changed);
  });
  await t.test('B231 selected follow-up deletion and unreferenced trace deletion cannot preserve results', async () => {
    const f = await setup(), extra = await setup({ owner: f.userId });
    f.body.selected_sources.push({ entry_id: extra.entryId });
    const r = await ready(f);
    assert.equal((await db.query('SELECT count(DISTINCT entry_id) FROM reading_recap_sources WHERE recap_id=$1', [f.id])).rows[0].count, '2');
    const refs = new Set(r.result.knowledge.concat(r.result.myThinking).flatMap(c => c.evidenceRefs));
    const m = await material(f), unused = m.snapshot.evidence.find(e => !refs.has(e.id) &&
      !m.snapshot.evidence.some(s => s.entryId === e.entryId && refs.has(s.id)));
    assert(unused); await entries.deleteEntry(f.userId, unused.entryId);
    assert.equal((await row(f)).state, 'invalidated'); assert.equal((await row(f)).result_json, null);
    const g = await setup(), fu = await follow(g); g.body.selected_sources[0].follow_up_ids = [fu.id]; await ready(g);
    await db.query('DELETE FROM user_entry_follow_ups WHERE id=$1', [fu.id]);
    await assert.rejects(service.get(g.userId, g.id), sourceError);
  });
  await t.test('B231 mutable library headers excluded; chapter, metadata and microsecond edits are versioned', async () => {
    const f = await ready();
    await db.query(`INSERT INTO user_library_books(user_id,book_id,title,author) VALUES($1,$2,'mutable title','mutable author')`, [f.userId, f.body.book_id]);
    await db.query(`UPDATE user_library_books SET title='renamed' WHERE user_id=$1`, [f.userId]);
    assert.equal((await service.get(f.userId, f.id)).state, 'ready');
    await db.query('DELETE FROM user_library_books WHERE user_id=$1', [f.userId]);
    assert.equal((await service.get(f.userId, f.id)).state, 'ready');
    for (const sql of ["chapter_title='edited'", "metadata_json=metadata_json || '{\"document_version\":\"new\"}'::jsonb",
      "updated_at=updated_at+interval '1 microsecond'"]) {
      const g = await ready(); await db.query(`UPDATE user_entries SET ${sql} WHERE id=$1`, [g.entryId]);
      await assert.rejects(service.get(g.userId, g.id), changed);
    }
  });
  await t.test('B231 malformed, empty or unavailable selected material is never silently omitted', async () => {
    const f = await setup({ payload: { user_input: '', ai_explanation: '', metadata_json: {} } });
    await assert.rejects(service.prepare(f.userId, f.body), { error_code: 'RECAP_INSUFFICIENT_EVIDENCE' });
    const g = await setup(); await follow(g, 'question', '');
    await assert.rejects(service.prepare(g.userId, g.body), { error_code: 'RECAP_INCOMPLETE_SOURCE' });
    const h = await setup({ payload: { chapter_title: 'x'.repeat(1001) } });
    await assert.rejects(service.prepare(h.userId, h.body));
    assert.equal(await row(h), undefined);
    const malformed = await setup();
    await db.query(`UPDATE user_entries SET metadata_json='["free_note_id"]'::jsonb WHERE id=$1`, [malformed.entryId]);
    await assert.rejects(service.prepare(malformed.userId, malformed.body), sourceError);
  });
  await t.test('B231 oversized raw bytes, input tokens and full follow-up set reject without saving partial scope', async () => {
    for (const length of [LIMITS.maxSourceBytes + 1, 20000]) {
      const f = await setup({ payload: { user_input: 'x'.repeat(length) } });
      await assert.rejects(service.prepare(f.userId, f.body), tooLarge); assert.equal(await row(f), undefined);
    }
    const f = await setup();
    await db.query(`INSERT INTO user_entry_follow_ups(entry_id,user_id,question,answer)
      SELECT $1,$2,'Q','A' FROM generate_series(1,321)`, [f.entryId, f.userId]);
    f.body.selected_sources[0].follow_up_ids = [];
    await assert.rejects(service.prepare(f.userId, f.body), tooLarge); assert.equal(await row(f), undefined);
  });
  await t.test('B231 more than 320 transmitted evidence records reject whole scope', async () => {
    const f = await setup();
    await db.query(`INSERT INTO user_entry_follow_ups(entry_id,user_id,question,answer)
      SELECT $1,$2,'Q','A' FROM generate_series(1,160)`, [f.entryId, f.userId]);
    await assert.rejects(service.prepare(f.userId, f.body), tooLarge); assert.equal(await row(f), undefined);
  });
  await t.test('B231 upload tombstone or inconsistent book state rejects; no-op revision alone does not stale', async () => {
    const f = await setup();
    await db.query(`UPDATE user_entries SET client_entry_id='client-state' WHERE id=$1`, [f.entryId]);
    await db.query(`INSERT INTO user_entry_upload_states(user_id,client_entry_id,book_id,latest_revision,writer_id)
      VALUES($1,'client-state',$2,1,$3)`, [f.userId, f.body.book_id, randomUUID()]);
    await ready(f);
    await db.query('UPDATE user_entry_upload_states SET latest_revision=2 WHERE user_id=$1', [f.userId]);
    assert.equal((await service.get(f.userId, f.id)).state, 'ready');
    await db.query('UPDATE user_entry_upload_states SET deleted=true WHERE user_id=$1', [f.userId]);
    await assert.rejects(service.get(f.userId, f.id), sourceError);
    await db.query("UPDATE user_entry_upload_states SET deleted=false,book_id='wrong' WHERE user_id=$1", [f.userId]);
    await assert.rejects(service.get(f.userId, f.id), sourceError);
  });
  await t.test('B231 actual Reliable Upload replay and no-op keep formal evidence valid; content edit invalidates', async () => {
    const userId = await user(), writer = randomUUID(), id = randomUUID();
    const payload = { source: 'ai_question', book_id: 'upload-book', original_text: fixture.excerpt,
      user_input: fixture.question, metadata_json: { origin: 'reader',
        reading_ai_context: { scope: 'selection', selectedText: fixture.excerpt } } };
    await entries.upsertEntryByClientId(userId, 'formal-upload', payload, { writer_id: writer, client_revision: 1 });
    const entryId = (await db.query(`SELECT id FROM user_entries WHERE user_id=$1 AND client_entry_id='formal-upload'`, [userId])).rows[0].id;
    const f = { userId, entryId, id, body: { recap_id: id, request_id: randomUUID(), book_id: 'upload-book',
      selected_sources: [{ client_entry_id: 'formal-upload' }] } };
    await ready(f); const before = await row(f);
    for (const revision of [1, 2]) {
      await entries.upsertEntryByClientId(userId, 'formal-upload', payload, { writer_id: writer, client_revision: revision });
      assert.equal((await service.get(userId, id)).revision, before.revision);
    }
    await entries.upsertEntryByClientId(userId, 'formal-upload', { ...payload, user_input: 'A changed question' },
      { writer_id: writer, client_revision: 3 });
    assert.equal((await row(f)).state, 'stale'); assert.equal((await row(f)).result_json, null);
  });
  await t.test('B231 formal resolver protects save/feedback/delete and late completion after cancel', async () => {
    const f = await ready();
    const saved = await service.save(f.userId, f.id, { request_id: randomUUID(), expected_revision: (await row(f)).revision });
    assert(saved.is_saved);
    await service.feedback(f.userId, f.id, { request_id: randomUUID(), expected_revision: saved.revision, category: 'low_value' });
    await service.remove(f.userId, f.id);
    await assert.rejects(service.prepare(f.userId, f.body), { error_code: 'RECAP_REQUEST_RETIRED' });
    for (const table of ['reading_recap_sources', 'reading_recap_feedback', 'xiaou_conversations']) {
      assert.equal((await db.query(`SELECT count(*) FROM ${table} WHERE recap_id=$1`, [f.id])).rows[0].count, '0');
    }
    assert.equal((await db.query('SELECT count(*) FROM user_entries WHERE id=$1', [f.entryId])).rows[0].count, '1');
    const g = await running(); await service.cancel(g.userId, g.id, g.op.request_id);
    await assert.rejects(complete(g), { error_code: 'RECAP_COMPLETION_REJECTED' });
    assert.equal((await row(g)).state, 'cancelled'); assert.equal((await row(g)).result_json, null);
  });
  await t.test('B231 dependency corruption, omitted dependency and legacy coverage cannot bypass revalidation', async () => {
    const f = await ready();
    await db.query("UPDATE reading_recap_sources SET source_digest=repeat('0',64) WHERE recap_id=$1", [f.id]);
    await assert.rejects(service.get(f.userId, f.id), changed);
    const g = await ready();
    await db.query(`DELETE FROM reading_recap_sources WHERE recap_id=$1 AND source_field='ai_explanation'`, [g.id]);
    await assert.rejects(service.get(g.userId, g.id), changed);
    const h = await ready();
    await db.query(`UPDATE reading_recaps SET coverage_json=jsonb_set(coverage_json,'{sourceCompleteness}','"local_and_supplied_cache"') WHERE id=$1`, [h.id]);
    await assert.rejects(service.get(h.userId, h.id), { error_code: 'RECAP_RESOLVER_VERSION_MISMATCH' });
  });
  await t.test('B231 canonical selection order stable; explicitly selected follow-up subsets remain distinct', async () => {
    const f = await setup(), g = await setup({ owner: f.userId }); await follow(f);
    f.body.selected_sources.push({ entry_id: g.entryId });
    const first = await material(f); f.body.selected_sources.reverse(); const second = await material(f);
    assert.equal(first.snapshot.fingerprint, second.snapshot.fingerprint);
    assert.deepEqual(first.dependencies, second.dependencies);
    f.body.selected_sources.find(s => s.entry_id === f.entryId).follow_up_ids = [];
    assert.notEqual((await material(f)).snapshot.fingerprint, first.snapshot.fingerprint);
  });
  await t.test('B231 model material omits owner/raw metadata/book headers and cannot cite historical AI as author', async () => {
    const f = await setup({ payload: { metadata_json: { origin: 'reader', private_debug: 'DO_NOT_TRANSMIT',
      reading_ai_context: { selectedText: fixture.excerpt, scope: 'selection', bookTitle: 'UNTRUSTED_HEADER' } } } });
    const s = (await material(f)).snapshot;
    const request = prepareGeneration(s, s.scope, { model: 'synthetic' }).request;
    assert(!JSON.stringify(request).includes('DO_NOT_TRANSMIT'));
    assert(!JSON.stringify(request).includes('UNTRUSTED_HEADER'));
    assert(!JSON.stringify(request).includes(f.userId));
    const r = answer(s); r.knowledge[0].evidenceRefs = [s.evidence.find(e => e.kind === 'historical_ai').id];
    assert.throws(() => validateResult(r, s, s.scope, completed), { code: 'RECAP_MISSING_BOOK_EVIDENCE' });
  });

  function deferred() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
  async function ordered(first, second) {
    const held = deferred(), release = deferred(), secondPid = deferred(); let firstPid;
    const settle = p => p.then(value => ({ value }), error => ({ error }));
    const a = settle(probe.run({ connected: pid => { firstPid = pid; }, after: async sql => {
      if (sql.startsWith('INSERT INTO sync_user_cursors')) { held.resolve(); await release.promise; }
    } }, first));
    let b;
    try {
      await Promise.race([held.promise, a.then(r => { throw r.error || Error('Missing first lock'); })]);
      b = settle(probe.run({ connected: pid => secondPid.resolve(pid) }, second));
      const pid = await secondPid.promise; let blocked = false;
      for (const until = Date.now() + 2000; Date.now() < until;) {
        if ((await pool.query('SELECT $1::int=ANY(pg_blocking_pids($2)) AS blocked', [firstPid, pid])).rows[0].blocked) { blocked = true; break; }
        await delay(5);
      }
      assert(blocked, 'Second must actually be blocked by first');
    } finally { release.resolve(); await Promise.all([a, b]); }
    return Promise.all([a, b]);
  }
  for (const deletionFirst of [false, true]) {
    await t.test(`B231 barrier prepare/delete: delete first=${deletionFirst}`, async () => {
      const f = await setup();
      const prepare = () => service.prepare(f.userId, f.body), remove = () => entries.deleteEntry(f.userId, f.entryId);
      const outcomes = await ordered(...(deletionFirst ? [remove, prepare] : [prepare, remove]));
      assert(!outcomes[0].error, outcomes[0].error?.stack);
      if (deletionFirst) { assert.equal(outcomes[1].error?.error_code, 'RECAP_SOURCE_UNAVAILABLE'); assert.equal(await row(f), undefined); }
      else { assert(!outcomes[1].error); assert.equal((await row(f)).state, 'invalidated'); }
    });
    await t.test(`B231 barrier complete/delete: delete first=${deletionFirst}`, async () => {
      const f = await running(); const remove = () => entries.deleteEntry(f.userId, f.entryId);
      const outcomes = await ordered(...(deletionFirst ? [remove, () => complete(f)] : [() => complete(f), remove]));
      assert(!outcomes[0].error, outcomes[0].error?.stack);
      if (deletionFirst) assert.equal(outcomes[1].error?.error_code, 'RECAP_UNAVAILABLE'); else assert(!outcomes[1].error);
      assert.equal((await row(f)).state, 'invalidated'); assert.equal((await row(f)).result_json, null);
      assert.equal((await db.query('SELECT count(*) FROM xiaou_conversations WHERE recap_id=$1', [f.id])).rows[0].count, '0');
    });
  }
  await t.test('B231 resolver SQL never locks after recap; rejected prepare rolls back all derived writes', async () => {
    const f = await ready(); const sql = [];
    await probe.run({ after: s => { sql.push(s); } }, () => service.get(f.userId, f.id));
    const recapLock = sql.findIndex(s => s.startsWith('SELECT * FROM reading_recaps'));
    assert(recapLock > 0); assert(!sql.slice(recapLock + 1).some(s => /FOR UPDATE|FOR KEY SHARE/.test(s)));
    assert(!sql.some(s => /FROM (free_notes|xiaou_messages|ai_messages|user_library_books)/.test(s)));
    const g = await setup();
    await assert.rejects(probe.run({ after: s => { if (s.startsWith('INSERT INTO reading_recap_sources')) throw Error('B231 rollback'); } },
      () => service.prepare(g.userId, g.body)), /B231 rollback/);
    assert.equal(await row(g), undefined);
    assert.equal((await db.query('SELECT count(*) FROM user_entries WHERE id=$1', [g.entryId])).rows[0].count, '1');
  });
};
