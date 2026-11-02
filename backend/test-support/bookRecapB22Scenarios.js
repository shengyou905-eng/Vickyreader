const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { setTimeout: delay } = require('node:timers/promises');
const { lockUploadUser } = require('../src/repositories/uploadState.repository');
const { invalidateSource, hasRecapSchema } = require('../src/repositories/bookRecapInvalidation.repository');
const { lockSelection } = require('../src/repositories/bookRecapSource.repository');
const { fingerprint } = require('../src/services/bookRecapContract');
const { createBookRecapStorage } = require('../src/services/bookRecapStorage.service');

// Invoked ONLY by the guarded fresh-cluster suite, after its injected DB is installed.
module.exports = async function scenarios(t, ctx) {
  const { db, pool, probe, repo, service, setup, ready, answer, generate, user, conversations, request, server } = ctx;
  const entries = require('../src/repositories/entry.repository');
  const { permanentlyDeleteBookData } = require('../src/repositories/bookDeletion.repository');
  const row = async f => (await db.query('SELECT * FROM reading_recaps WHERE id=$1', [f.id])).rows[0];
  const count = async (table, f) => Number((await db.query(`SELECT count(*) FROM ${table} WHERE recap_id=$1`, [f.id])).rows[0].count);
  const done = { completed: true, finishReason: 'stop' };
  async function running() {
    const f = await setup(), prepared = await service.prepare(f.userId, f.body);
    const op = await service.begin(f.userId, f.id, generate(prepared));
    return { ...f, op, result: await answer(f) };
  }
  const complete = f => service.complete(f.userId, f.id, f.op.request_id, f.op.generation_id, f.result, done);
  const edit = f => entries.updateEntryImportance(f.userId, f.entryId, true);
  const remove = f => entries.deleteEntry(f.userId, f.entryId);
  async function cleared(f, state) {
    const r = await row(f);
    assert.equal(r.state, state); assert.equal(r.result_json, null);
    for (const name of ['reading_recap_feedback', 'xiaou_conversations']) assert.equal(await count(name, f), 0);
    const ops = (await db.query('SELECT * FROM reading_recap_operations WHERE recap_id=$1', [f.id])).rows;
    assert(ops.every(o => o.status === 'revoked' && o.request_mac === null && o.result_id === null));
    if (state === 'invalidated') {
      assert.equal(await count('reading_recap_sources', f), 0);
      for (const name of ['book_id', 'selected_sources_json', 'coverage_json', 'source_fingerprint']) assert.equal(r[name], null);
    } else assert(await count('reading_recap_sources', f) > 0);
  }
  function deferred() {
    let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve };
  }
  async function ordered(first, second) {
    const held = deferred(), release = deferred(), secondPid = deferred();
    let firstPid; const sql = [[], []];
    const a = probe.run({ connected: pid => { firstPid = pid; }, after: async s => {
      sql[0].push(s);
      if (s.startsWith('INSERT INTO sync_user_cursors')) { held.resolve(); await release.promise; }
    } }, first).then(value => ({ status: 'fulfilled', value }), reason => ({ status: 'rejected', reason }));
    let b;
    try {
      await Promise.race([held.promise, a.then(v => { throw v.reason || Error('First missed user lock'); })]);
      b = probe.run({ connected: pid => secondPid.resolve(pid), after: s => { sql[1].push(s); } }, second)
        .then(value => ({ status: 'fulfilled', value }), reason => ({ status: 'rejected', reason }));
      const pid = await secondPid.promise;
      const until = Date.now() + 2000;
      let blocked = false;
      while (Date.now() < until) {
        const r = await pool.query('SELECT $1::int=ANY(pg_blocking_pids($2)) AS blocked', [firstPid, pid]);
        if (r.rows[0].blocked) { blocked = true; break; }
        await delay(5);
      }
      assert(blocked, 'Second transaction must demonstrably wait for the first transaction');
    } finally { release.resolve(); await Promise.all([a, b]); }
    return { outcomes: await Promise.all([a, b]), sql };
  }
  const fulfilled = outcome => assert.equal(outcome.status, 'fulfilled', outcome.reason?.stack);
  function rejected(outcome, code) {
    assert.equal(outcome.status, 'rejected'); assert.equal(outcome.reason.error_code, code);
  }
  await t.test('B22 edit atomically clears body, messages, feedback, operations; preserves ordinary chat and cursor semantics', async () => {
    const f = await ready();
    await service.feedback(f.userId, f.id, { request_id: randomUUID(), expected_revision: f.row.revision, category: 'low_value', comment: 'private' });
    const conv = (await db.query('SELECT id FROM xiaou_conversations WHERE recap_id=$1', [f.id])).rows[0].id;
    await db.query("INSERT INTO xiaou_messages(conversation_id,user_id,role,content) VALUES($1,$2,'assistant','derived')", [conv, f.userId]);
    const ordinary = await conversations.createConversation(f.userId, { kind: 'xiaou_asks' });
    await conversations.appendMessage(f.userId, ordinary.id, { role: 'user', content: 'keep ordinary' });
    await edit(f); await cleared(f, 'stale');
    assert.equal((await db.query('SELECT count(*) FROM xiaou_messages WHERE conversation_id=$1', [conv])).rows[0].count, '0');
    assert.equal((await conversations.getConversation(f.userId, ordinary.id)).messages[0].content, 'keep ordinary');
    assert.equal((await db.query('SELECT count(*) FROM sync_changes WHERE user_id=$1', [f.userId])).rows[0].count, '1');
    const revision = (await row(f)).revision;
    await edit(f); assert.equal((await row(f)).revision, revision);
    await assert.rejects(service.get(f.userId, f.id), { error_code: 'RECAP_SOURCE_CHANGED' });
    await assert.rejects(complete(f), { error_code: 'RECAP_SOURCE_CHANGED' });
  });
  await t.test('B22 deletion after stale removes remaining dependencies; unrelated source survives', async () => {
    const f = await ready();
    const extra = await entries.createEntry(f.userId, { source: 'thought', book_id: f.body.book_id, user_input: 'independent history' });
    assert.equal((await row(f)).state, 'ready');
    await edit(f); await remove(f); await cleared(f, 'invalidated');
    assert.equal((await db.query('SELECT count(*) FROM user_entries WHERE id=$1', [extra.id])).rows[0].count, '1');
    await assert.rejects(service.prepare(f.userId, f.body), { error_code: 'RECAP_REQUEST_RETIRED' });
    await assert.rejects(complete(f), { error_code: 'RECAP_UNAVAILABLE' });
  });
  await t.test('B22 permanent book deletion clears all recaps; repeated deletion does not advance revision', async () => {
    const f = await ready();
    const second = { ...f.body, recap_id: randomUUID(), request_id: randomUUID() };
    await service.prepare(f.userId, second);
    await permanentlyDeleteBookData(f.userId, f.body.book_id); await cleared(f, 'invalidated');
    assert.equal((await db.query('SELECT state FROM reading_recaps WHERE id=$1', [second.recap_id])).rows[0].state, 'invalidated');
    const revision = (await row(f)).revision;
    await permanentlyDeleteBookData(f.userId, f.body.book_id); assert.equal((await row(f)).revision, revision);
    await assert.rejects(service.prepare(f.userId, { ...f.body, request_id: randomUUID(), recap_id: randomUUID() }), { statusCode: 410 });
    const reimport = await entries.createEntry(f.userId, { source: 'thought', book_id: 'new-independent-book', user_input: 'new import' });
    assert(reimport.id); assert.equal((await row(f)).state, 'invalidated');
  });
  await t.test('B22 follow-up additions acquire user lock before parent and invalidate even explicit empty selection', async () => {
    const f = await ready(); const sql = [];
    await probe.run({ after: s => { sql.push(s); } }, () => entries.createFollowUp(f.userId, f.entryId, 'new question', 'historic AI'));
    assert.match(sql[0], /^INSERT INTO sync_user_cursors/); assert.match(sql[1], /FROM user_entries[\s\S]*FOR UPDATE/);
    await cleared(f, 'stale');
    assert.equal((await db.query('SELECT count(*) FROM sync_changes WHERE user_id=$1', [f.userId])).rows[0].count, '0');
    const other = await user(); assert.equal(await entries.createFollowUp(other, f.entryId, 'wrong', 'wrong'), null);
  });
  await t.test('B22 midpoint failure rolls back original edit, cleanup, messages, feedback and ledger', async () => {
    const f = await ready();
    const before = await row(f), original = (await db.query('SELECT * FROM user_entries WHERE id=$1', [f.entryId])).rows[0];
    await assert.rejects(probe.run({ after: s => {
      if (s.startsWith('DELETE FROM reading_recap_feedback')) throw Error('injected-mid-cleanup');
    } }, () => edit(f)), /injected-mid-cleanup/);
    assert.deepEqual(await row(f), before);
    assert.deepEqual((await db.query('SELECT * FROM user_entries WHERE id=$1', [f.entryId])).rows[0], original);
    assert.equal(await count('xiaou_conversations', f), 1);
    assert.equal((await db.query('SELECT count(*) FROM sync_changes WHERE user_id=$1', [f.userId])).rows[0].count, '0');
  });
  for (const firstEdit of [false, true]) await t.test(`B22 barrier save/edit: ${firstEdit ? 'edit' : 'save'} first`, async () => {
    const f = await ready(); const save = () => service.save(f.userId, f.id, { request_id: randomUUID(), expected_revision: f.row.revision });
    const actions = firstEdit ? [() => edit(f), save] : [save, () => edit(f)];
    const { outcomes } = await ordered(...actions);
    fulfilled(outcomes[0]); if (firstEdit) rejected(outcomes[1], 'RECAP_SOURCE_CHANGED'); else fulfilled(outcomes[1]);
    await cleared(f, 'stale'); assert.equal((await row(f)).is_saved, !firstEdit);
  });
  for (const firstDelete of [false, true]) await t.test(`B22 barrier complete/source-delete: ${firstDelete ? 'delete' : 'complete'} first`, async () => {
    const f = await running();
    const { outcomes } = await ordered(...(firstDelete ? [() => remove(f), () => complete(f)] : [() => complete(f), () => remove(f)]));
    fulfilled(outcomes[0]); if (firstDelete) rejected(outcomes[1], 'RECAP_UNAVAILABLE'); else fulfilled(outcomes[1]);
    await cleared(f, 'invalidated');
  });
  for (const firstCancel of [false, true]) await t.test(`B22 barrier cancel/complete: ${firstCancel ? 'cancel' : 'complete'} first`, async () => {
    const f = await running(); const cancel = () => service.cancel(f.userId, f.id, f.op.request_id);
    const { outcomes } = await ordered(...(firstCancel ? [cancel, () => complete(f)] : [() => complete(f), cancel]));
    fulfilled(outcomes[0]); rejected(outcomes[1], firstCancel ? 'RECAP_COMPLETION_REJECTED' : 'RECAP_ALREADY_COMPLETED');
    assert.equal((await row(f)).state, firstCancel ? 'cancelled' : 'ready');
  });
  for (const firstFollow of [false, true]) await t.test(`B22 barrier follow-up/complete: ${firstFollow ? 'follow-up' : 'complete'} first`, async () => {
    const f = await running(); const follow = () => entries.createFollowUp(f.userId, f.entryId, 'new', 'history');
    const { outcomes } = await ordered(...(firstFollow ? [follow, () => complete(f)] : [() => complete(f), follow]));
    fulfilled(outcomes[0]); if (firstFollow) rejected(outcomes[1], 'RECAP_SOURCE_CHANGED'); else fulfilled(outcomes[1]);
    await cleared(f, 'stale');
  });
  await t.test('B22 selected entry/client/follow-up IDs require exact owner, book and parent; duplicate aliases rejected', async () => {
    const f = await setup(), other = await setup();
    await db.query("UPDATE user_entries SET client_entry_id='local-synthetic' WHERE id=$1", [f.entryId]);
    const follow = await entries.createFollowUp(f.userId, f.entryId, 'question', 'answer');
    const resolve = (owner, book, selection) => repo.transaction(owner, tx => lockSelection(tx, owner, book, selection));
    assert.equal((await resolve(f.userId, f.body.book_id, [{ client_entry_id: 'local-synthetic', follow_up_ids: [follow.id] }])).entries[0].id, f.entryId);
    for (const [owner, book, selection] of [
      [other.userId, f.body.book_id, [{ entry_id: f.entryId }]],
      [f.userId, 'same-title-other-import', [{ entry_id: f.entryId }]],
      [f.userId, f.body.book_id, [{ entry_id: randomUUID() }]],
      [f.userId, f.body.book_id, [{ entry_id: f.entryId, follow_up_ids: [randomUUID()] }]],
      [f.userId, f.body.book_id, [{ entry_id: f.entryId }, { client_entry_id: 'local-synthetic' }]],
    ]) await assert.rejects(resolve(owner, book, selection), { error_code: 'RECAP_SOURCE_UNAVAILABLE' });
    const sibling = await entries.createEntry(f.userId, { source: 'thought', book_id: f.body.book_id });
    await assert.rejects(resolve(f.userId, f.body.book_id, [{ entry_id: sibling.id, follow_up_ids: [follow.id] }]), { error_code: 'RECAP_SOURCE_UNAVAILABLE' });
  });
  await t.test('B22 Reliable Upload changed upsert invalidates once; replay/no-change/conflict do not re-invalidate', async () => {
    const f = await setup(), writer = randomUUID();
    await db.query("UPDATE user_entries SET client_entry_id='managed' WHERE id=$1", [f.entryId]);
    const original = (await db.query('SELECT * FROM user_entries WHERE id=$1', [f.entryId])).rows[0];
    const payload = { source: original.source, book_id: original.book_id, original_text: original.original_text, user_input: original.user_input };
    await entries.upsertEntryByClientId(f.userId, 'managed', payload, { writer_id: writer, client_revision: 1 });
    const prepared = await service.prepare(f.userId, f.body), op = await service.begin(f.userId, f.id, generate(prepared));
    await service.complete(f.userId, f.id, op.request_id, op.generation_id, await answer(f), done);
    const before = (await row(f)).revision;
    await entries.upsertEntryByClientId(f.userId, 'managed', payload, { writer_id: writer, client_revision: 1 });
    await entries.upsertEntryByClientId(f.userId, 'managed', payload, { writer_id: writer, client_revision: 2 });
    assert.equal((await row(f)).revision, before);
    const changed = { ...payload, user_input: 'changed synthetic thought' };
    const originalEntry = (await db.query('SELECT * FROM user_entries WHERE id=$1', [f.entryId])).rows[0];
    const uploadState = (await db.query('SELECT * FROM user_entry_upload_states WHERE user_id=$1', [f.userId])).rows;
    const priorRecap = await row(f);
    await assert.rejects(probe.run({ after: s => {
      if (s.startsWith('UPDATE reading_recaps SET state=$3')) throw Error('synthetic-upload-invalidation-failure');
    } }, () => entries.upsertEntryByClientId(f.userId, 'managed', changed, { writer_id: writer, client_revision: 3 })),
    /synthetic-upload-invalidation-failure/);
    assert.deepEqual(await row(f), priorRecap);
    assert.deepEqual((await db.query('SELECT * FROM user_entries WHERE id=$1', [f.entryId])).rows[0], originalEntry);
    assert.deepEqual((await db.query('SELECT * FROM user_entry_upload_states WHERE user_id=$1', [f.userId])).rows, uploadState);
    await entries.upsertEntryByClientId(f.userId, 'managed', changed, { writer_id: writer, client_revision: 3 });
    await cleared(f, 'stale'); const revision = (await row(f)).revision;
    await entries.upsertEntryByClientId(f.userId, 'managed', changed, { writer_id: writer, client_revision: 3 });
    await assert.rejects(entries.upsertEntryByClientId(f.userId, 'managed', payload, { writer_id: writer, client_revision: 3 }), { statusCode: 409 });
    assert.equal((await row(f)).revision, revision);
    await entries.deleteEntryByClientId(f.userId, 'managed', { writer_id: writer, client_revision: 4 });
    await cleared(f, 'invalidated');
    assert.equal(await entries.deleteEntryByClientId(f.userId, 'managed', { writer_id: writer, client_revision: 4 }), false);
  });
  await t.test('B22 deleted recap cannot be restored by old completion or operation replay', async () => {
    const f = await running(); await service.remove(f.userId, f.id);
    await assert.rejects(complete(f), { error_code: 'RECAP_UNAVAILABLE' });
    await assert.rejects(service.prepare(f.userId, f.body), { error_code: 'RECAP_REQUEST_RETIRED' });
    assert.equal((await row(f)).result_json, null);
  });
  await t.test('B22 ordinary HTTP rejects cross-owner guesses and never returns dedicated last_message', async () => {
    const f = await ready(), other = await user();
    const conv = (await db.query('SELECT id FROM xiaou_conversations WHERE recap_id=$1', [f.id])).rows[0].id;
    for (const owner of [f.userId, other]) for (const [method, suffix, body] of [
      ['GET', '', null], ['POST', '/messages', { role: 'assistant', content: 'injection' }], ['DELETE', '', null],
    ]) assert.equal((await request(server, owner, method, '/conversations/' + conv + suffix, body)).status, 404);
    const normal = await conversations.createConversation(f.userId, { kind: 'chat' });
    await conversations.appendMessage(f.userId, normal.id, { role: 'user', content: 'ordinary last message' });
    const list = await conversations.listConversations(f.userId);
    assert.equal(list.length, 1); assert.equal(list[0].id, normal.id);
    await remove(f); assert.equal((await conversations.getConversation(f.userId, normal.id)).messages.length, 1);
  });
  await t.test('B22 partial migration fails source mutation closed and rolls back', async () => {
    const f = await ready();
    await assert.rejects(db.withTransaction(async tx => {
      await tx('ALTER TABLE reading_recap_feedback RENAME TO synthetic_hidden_feedback');
      await lockUploadUser(tx, f.userId);
      await tx('UPDATE user_entries SET is_important=true WHERE id=$1', [f.entryId]);
      await invalidateSource(tx, f.userId, { entryId: f.entryId });
    }), { error_code: 'RECAP_SCHEMA_INCOMPLETE' });
    assert.equal((await row(f)).state, 'ready');
    assert.equal((await db.query('SELECT is_important FROM user_entries WHERE id=$1', [f.entryId])).rows[0].is_important, false);
    assert(await hasRecapSchema(db.query));
  });
  await t.test('B22 deleting an UNREFERENCED but transmitted source invalidates the entire result', async () => {
    const f = await setup();
    const extra = await entries.createEntry(f.userId, { source: 'ai_question', book_id: f.body.book_id,
      original_text: 'Additional synthetic material.', user_input: 'Uncited synthetic question?' });
    f.body.selected_sources.push({ entry_id: extra.id, follow_up_ids: [] });
    const resolver = {
      async resolve(tx, owner, book, selection) {
        const all = [];
        for (const selected of selection) all.push(await ctx.resolver.resolve(tx, owner, book, [selected]));
        const snapshot = { ...all[0].snapshot, evidence: all.flatMap(m => m.snapshot.evidence),
          coverage: { ...all[0].snapshot.coverage, includedEntries: all.length, availableEntries: all.length } };
        delete snapshot.fingerprint; snapshot.fingerprint = fingerprint(snapshot);
        return { snapshot, dependencies: all.flatMap(m => m.dependencies) };
      },
      async revalidate(tx, owner, r) { return (await this.resolve(tx, owner, r.book_id, r.selected_sources_json)).snapshot; },
    };
    const custom = createBookRecapStorage({ repository: repo, resolver, macKey: Buffer.alloc(32, 7),
      origin: 'https://synthetic.invalid', clock: () => new Date('2026-10-21T00:00:00Z') });
    const prepared = await custom.prepare(f.userId, f.body), op = await custom.begin(f.userId, f.id, generate(prepared));
    const result = await answer(f); result.snapshotFingerprint = prepared.source_fingerprint;
    await custom.complete(f.userId, f.id, op.request_id, op.generation_id, result, done);
    assert.equal(await count('reading_recap_sources', f), 4);
    assert(result.knowledge.every(k => k.evidenceRefs.every(ref => ref !== 'e-' + fingerprint([extra.id, null, 'reading_ai_context.selectedText']))));
    await entries.deleteEntry(f.userId, extra.id); await cleared(f, 'invalidated');
    assert.equal((await db.query('SELECT count(*) FROM user_entries WHERE id=$1', [f.entryId])).rows[0].count, '1');
  });
  for (const deleted of [false, true]) await t.test(`B22 internal follow-up ${deleted ? 'deletion' : 'edit'} contract (no public endpoint exists)`, async () => {
    const f = await setup();
    const follow = await entries.createFollowUp(f.userId, f.entryId, 'first', 'historical');
    const prepared = await service.prepare(f.userId, f.body), op = await service.begin(f.userId, f.id, generate(prepared));
    await service.complete(f.userId, f.id, op.request_id, op.generation_id, await answer(f), done);
    await db.withTransaction(async tx => {
      await lockUploadUser(tx, f.userId);
      await tx('SELECT id FROM user_entries WHERE user_id=$1 AND id=$2 FOR UPDATE', [f.userId, f.entryId]);
      await tx(deleted ? 'DELETE FROM user_entry_follow_ups WHERE user_id=$1 AND id=$2' :
        "UPDATE user_entry_follow_ups SET question='changed' WHERE user_id=$1 AND id=$2", [f.userId, follow.id]);
      await invalidateSource(tx, f.userId, { entryId: f.entryId, deleted });
    });
    await cleared(f, deleted ? 'invalidated' : 'stale');
  });
  await t.test('B22 permanent deletion midpoint failure restores book fence, sources, upload state and derived data', async () => {
    const f = await ready(); const before = await row(f);
    const follow = await entries.createFollowUp(f.userId, f.entryId, 'question', 'answer');
    // Use a fresh recap after the deliberate source edit.
    f.id = randomUUID(); f.body = { ...f.body, recap_id: f.id, request_id: randomUUID() };
    const prepared = await service.prepare(f.userId, f.body), op = await service.begin(f.userId, f.id, generate(prepared));
    await service.complete(f.userId, f.id, op.request_id, op.generation_id, await answer(f), done);
    const snapshot = await row(f);
    await assert.rejects(probe.run({ after: s => {
      if (s.startsWith('DELETE FROM reading_progresses')) throw Error('synthetic-purge-failure');
    } }, () => permanentlyDeleteBookData(f.userId, f.body.book_id)), /synthetic-purge-failure/);
    assert.deepEqual(await row(f), snapshot);
    assert.equal((await db.query('SELECT count(*) FROM user_entry_follow_ups WHERE id=$1', [follow.id])).rows[0].count, '1');
    assert.equal((await db.query('SELECT count(*) FROM permanently_deleted_books WHERE user_id=$1', [f.userId])).rows[0].count, '0');
    assert.equal((await db.query('SELECT count(*) FROM sync_changes WHERE user_id=$1', [f.userId])).rows[0].count, '0');
    assert(before.result_json);
  });
  await t.test('B22 ordinary shelf removal, replace-empty sync and missing local file do not delete recap', async () => {
    const f = await ready(), original = await row(f);
    const library = require('../src/repositories/mcp.repository');
    await library.syncLibraryBooks(f.userId, [{ book_id: f.body.book_id, title: 'Synthetic book', format: 'epub' }]);
    assert(await library.deleteLibraryBook(f.userId, f.body.book_id));
    assert.deepEqual(await row(f), original);
    await library.syncLibraryBooks(f.userId, [{ book_id: f.body.book_id, title: 'Synthetic book' }]);
    await library.syncLibraryBooks(f.userId, [], { replace: true });
    assert.deepEqual(await row(f), original);
    // The synthetic resolver has fragments only, no EPUB/TXT file or exact anchor.
    assert((await service.get(f.userId, f.id)).result_json);
    assert.equal((await db.query('SELECT count(*) FROM user_entries WHERE id=$1', [f.entryId])).rows[0].count, '1');
  });
  for (const firstDelete of [false, true]) await t.test(`B22 barrier prepare/source-delete: ${firstDelete ? 'delete' : 'prepare'} first`, async () => {
    const f = await setup(); const prepare = () => service.prepare(f.userId, f.body);
    const { outcomes } = await ordered(...(firstDelete ? [() => remove(f), prepare] : [prepare, () => remove(f)]));
    fulfilled(outcomes[0]);
    if (firstDelete) { rejected(outcomes[1], 'RECAP_SOURCE_UNAVAILABLE'); assert.equal(await row(f), undefined); }
    else { fulfilled(outcomes[1]); await cleared(f, 'invalidated'); }
  });
  await t.test('B22 actual lock order is source, recap, operation, conversation after account lock', async () => {
    const f = await running(); const sql = [];
    await probe.run({ after: s => { sql.push(s); } }, () => complete(f));
    const index = pattern => sql.findIndex(s => pattern.test(s));
    const sequence = [/INSERT INTO sync_user_cursors/, /FROM user_entries e[\s\S]*FOR UPDATE/,
      /SELECT \* FROM reading_recaps[\s\S]*FOR UPDATE/, /SELECT \* FROM reading_recap_operations[\s\S]*FOR UPDATE/,
      /INSERT INTO xiaou_conversations/].map(index);
    assert(sequence.every(i => i >= 0));
    assert.deepEqual(sequence, [...sequence].sort((a, b) => a - b));
  });
};
