const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { Client } = require('pg');

const databaseUrl = process.env.TEST_DATABASE_URL;

if (!databaseUrl) {
  test('Phase 1A.1 PostgreSQL concurrency tests', { skip: 'TEST_DATABASE_URL is not set' }, () => {});
} else {
  const testUrl = new URL(databaseUrl);
  if (!['localhost', '127.0.0.1'].includes(testUrl.hostname)
      || !testUrl.pathname.endsWith('_test')) {
    throw new Error('Destructive fixtures require a localhost database ending in _test');
  }
  process.env.DATABASE_URL = databaseUrl;
  process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';

  const { query, closePool } = require('../config/db');
  const { appendSyncChange } = require('./syncChange.repository');
  const mcpRepository = require('./mcp.repository');

  const ids = {
    unsafe: '00000000-0000-0000-0000-000000000001',
    serialized: '00000000-0000-0000-0000-000000000002',
    rollback: '00000000-0000-0000-0000-000000000003',
    parallelA: '00000000-0000-0000-0000-000000000004',
    parallelB: '00000000-0000-0000-0000-000000000005',
    snapshot: '00000000-0000-0000-0000-000000000006',
    replace: '00000000-0000-0000-0000-000000000007',
    revisions: '00000000-0000-0000-0000-000000000008',
    purge: '00000000-0000-0000-0000-000000000009',
    failure: '00000000-0000-0000-0000-000000000010',
  };
  const version = (revision, writer = '11111111-1111-4111-8111-111111111111') => ({
    client_revision: revision, writer_id: writer,
  });

  const delay = (milliseconds) => new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });

  async function connect() {
    const client = new Client({ connectionString: databaseUrl });
    await client.connect();
    await client.query(`SET statement_timeout = '10s'`);
    return client;
  }

  async function appendWithClient(client, change) {
    return appendSyncChange(
      (sql, params) => client.query(sql, params),
      change,
    );
  }

  test('Phase 1A.1 uses commit-safe per-user cursors', async (t) => {
    t.after(async () => {
      await closePool();
    });

    await query('DROP SCHEMA public CASCADE; CREATE SCHEMA public');
    await query('CREATE EXTENSION IF NOT EXISTS pgcrypto');
    await query(`
      CREATE TABLE users (
        id UUID PRIMARY KEY
      );

      CREATE TABLE user_entries (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        source TEXT NOT NULL,
        book_id TEXT,
        book_title TEXT,
        chapter_index TEXT,
        chapter_title TEXT,
        original_text TEXT,
        user_input TEXT,
        ai_explanation TEXT,
        auto_tags TEXT[] NOT NULL DEFAULT '{}',
        auto_summary TEXT,
        metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
        is_important BOOLEAN NOT NULL DEFAULT false,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );

      CREATE TABLE reading_progresses (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        book_id TEXT NOT NULL,
        progress DOUBLE PRECISION NOT NULL DEFAULT 0,
        chapter_index TEXT NOT NULL DEFAULT '0',
        scroll_offset DOUBLE PRECISION NOT NULL DEFAULT 0,
        cfi TEXT,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        UNIQUE(user_id, book_id)
      );

      CREATE TABLE user_library_books (
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        book_id TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        format TEXT NOT NULL DEFAULT '',
        added_at TIMESTAMPTZ,
        last_opened_at TIMESTAMPTZ,
        synced_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (user_id, book_id)
      );
    `);
    await query(
      'INSERT INTO users (id) SELECT unnest($1::uuid[])',
      [Object.values(ids)],
    );
    const migration = fs.readFileSync(
      path.join(__dirname, '../db/migrations/003_sync_changes_ledger.up.sql'),
      'utf8',
    );
    await query(migration);
    await query(migration);

    await t.test('004 preserves historical data, skips ambiguous IDs and is safely repeatable', async () => {
      await query(`INSERT INTO user_entries (user_id, source, metadata_json, created_at)
        VALUES ($1, 'thought', '{"local_id":"unique"}', '2020-01-01'),
          ($1, 'thought', '{"local_id":"ambiguous"}', '2020-01-01'),
          ($1, 'thought', '{"local_id":"ambiguous"}', '2020-01-01'),
          ($1, 'thought', '{}', '2020-01-01')`, [ids.unsafe]);
      const sql = fs.readFileSync(path.join(__dirname,
        '../db/migrations/004_reliable_upload_idempotency.up.sql'), 'utf8');
      await query(sql);
      const initial = await query('SELECT * FROM user_entries WHERE user_id = $1 ORDER BY id', [ids.unsafe]);
      assert.equal(initial.rowCount, 4);
      assert.equal(initial.rows.filter(row => row.client_entry_id === 'unique').length, 1);
      assert.equal(initial.rows.filter(row => row.client_entry_id === null).length, 3);
      await query(`INSERT INTO user_entries (user_id, source, client_entry_id)
        VALUES ($1, 'thought', 'already-bound')`, [ids.unsafe]);
      await query(`INSERT INTO user_entries (user_id, source, metadata_json)
        VALUES ($1, 'thought', '{"local_id":"already-bound"}')`, [ids.unsafe]);
      await query(sql);
      await query(sql);
      const after = await query('SELECT * FROM user_entries WHERE user_id = $1 ORDER BY id', [ids.unsafe]);
      assert.equal(after.rowCount, 6);
      for (const row of initial.rows) {
        assert.deepEqual(after.rows.find(candidate => candidate.id === row.id), row);
      }
      assert.equal(after.rows.filter(row => row.client_entry_id === 'already-bound').length, 1);
      await assert.rejects(query(`INSERT INTO user_entries (user_id, source, client_entry_id)
        VALUES ($1, 'thought', 'unique')`, [ids.unsafe]), { code: '23505' });
      await query(`INSERT INTO user_entries (user_id, source, client_entry_id)
        VALUES ($1, 'thought', 'unique')`, [ids.rollback]);
    });

    await t.test('004 aborts and rolls back backfill on a conflicting named index', async () => {
      const client = await connect();
      try {
        await client.query('ALTER INDEX idx_user_entries_user_client_entry RENAME TO saved_client_entry_index');
        await client.query('CREATE INDEX idx_user_entries_user_client_entry ON user_entries(user_id)');
        const inserted = await client.query(`INSERT INTO user_entries (user_id, source, metadata_json)
          VALUES ($1, 'thought', '{"local_id":"rollback-backfill"}') RETURNING id`, [ids.unsafe]);
        const sql = fs.readFileSync(path.join(__dirname,
          '../db/migrations/004_reliable_upload_idempotency.up.sql'), 'utf8');
        await assert.rejects(client.query(sql), /conflicting client-entry index/);
        await client.query('ROLLBACK');
        const unchanged = await client.query('SELECT client_entry_id FROM user_entries WHERE id=$1', [inserted.rows[0].id]);
        assert.equal(unchanged.rows[0].client_entry_id, null);
      } finally {
        await client.query('ROLLBACK');
        await client.query('DROP INDEX IF EXISTS idx_user_entries_user_client_entry');
        await client.query('ALTER INDEX saved_client_entry_index RENAME TO idx_user_entries_user_client_entry');
        await client.end();
      }
    });

    await t.test('remove-from-library keeps history queryable by MCP; only explicit deletes remove it', async () => {
      const migration005 = fs.readFileSync(path.join(__dirname, '../db/migrations/005_upload_revisions.up.sql'), 'utf8');
      const before005 = await query('SELECT * FROM user_entries ORDER BY id');
      await query(migration005);
      await query(migration005);
      assert.deepEqual((await query('SELECT * FROM user_entries ORDER BY id')).rows, before005.rows);
      const migration006 = fs.readFileSync(path.join(__dirname, '../db/migrations/006_progress_upload_revisions.up.sql'), 'utf8');
      await query(`INSERT INTO reading_progresses(user_id,book_id,progress,updated_at)
        VALUES($1,'baseline-progress',0.3,'2020-01-01')`, [ids.unsafe]);
      const before006 = await query('SELECT * FROM reading_progresses ORDER BY id');
      await query(migration006);
      await query(migration006);
      assert.deepEqual((await query('SELECT * FROM reading_progresses ORDER BY id')).rows, before006.rows);
      const baseline = (await query('SELECT * FROM reading_progress_upload_states WHERE user_id=$1', [ids.unsafe])).rows[0];
      assert.equal(baseline.latest_revision, '0');
      assert.equal(baseline.writer_id, null);
      const entries = require('./entry.repository');
      const progresses = require('./readingProgress.repository');
      const user = ids.parallelA;
      const payload = { source: 'thought', book_id: 'history-book', user_input: 'test-only', ...version(1) };
      const first = await entries.upsertEntryByClientId(user, 'history-trace', payload);
      const retry = await entries.upsertEntryByClientId(user, 'history-trace', payload);
      assert.equal(first.entry.id, retry.entry.id);
      assert.equal(retry.operation, null);
      await progresses.upsertReadingProgress(user, { book_id: 'history-book', progress: 0.5, ...version(1) });
      await mcpRepository.syncLibraryBooks(user, [{ book_id: 'history-book', title: 'History' }], { replace: true });
      const before = await query('SELECT last_sequence FROM sync_user_cursors WHERE user_id = $1', [user]);
      await mcpRepository.syncLibraryBooks(user, [], { replace: true });
      await mcpRepository.syncLibraryBooks(user, [], { replace: true });
      const traces = await mcpRepository.listTraces(user, { bookId: 'history-book' });
      assert.equal(traces.items.length, 1);
      assert.equal((await mcpRepository.getTraceById(user, first.entry.id)).id, first.entry.id);
      assert.deepEqual((await mcpRepository.listTraces(ids.parallelB, { bookId: 'history-book' })).items, []);
      assert.equal((await query('SELECT * FROM reading_progresses WHERE user_id=$1 AND book_id=$2', [user, 'history-book'])).rowCount, 1);
      const removal = await query('SELECT entity_type, operation FROM sync_changes WHERE user_id=$1 AND user_sequence>$2', [user, before.rows[0].last_sequence]);
      assert.deepEqual(removal.rows, [{ entity_type: 'book', operation: 'deleted' }]);
      await entries.deleteEntryByClientId(user, 'history-trace', version(2));
      await entries.deleteEntryByClientId(user, 'history-trace', version(2));
      await progresses.deleteReadingProgress(user, 'history-book', version(2));
      assert.deepEqual((await mcpRepository.listTraces(user, { bookId: 'history-book' })).items, []);
      assert.equal((await query('SELECT * FROM reading_progresses WHERE user_id=$1 AND book_id=$2', [user, 'history-book'])).rowCount, 0);
      const final = await query('SELECT entity_type, operation FROM sync_changes WHERE user_id=$1 AND user_sequence>$2 ORDER BY user_sequence', [user, before.rows[0].last_sequence]);
      assert.deepEqual(final.rows, [
        { entity_type: 'book', operation: 'deleted' },
        { entity_type: 'trace', operation: 'deleted' },
        { entity_type: 'reading_progress', operation: 'deleted' },
      ]);
    });

    await t.test('late DELETE cannot remove revision 3 recreate', async () => {
      const entries = require('./entry.repository');
      const user = ids.unsafe;
      await entries.upsertEntryByClientId(user, 'late-delete', { source: 'thought', user_input: 'old' }, version(1));
      await entries.deleteEntryByClientId(user, 'late-delete', version(2));
      const recreated = await entries.upsertEntryByClientId(user, 'late-delete', { source: 'thought', user_input: 'new' }, version(3));
      // A timed-out/retried old DELETE can reach PostgreSQL after the new PUT.
      await assert.rejects(entries.deleteEntryByClientId(user, 'late-delete', version(2)), { statusCode: 409 });
      const remaining = await mcpRepository.getTraceById(user, recreated.entry.id);
      assert.equal(remaining.note, 'new');
    });

    await t.test('entry tombstones fence old updates, repeated deletes, and conflicting writers', async () => {
      const entries = require('./entry.repository');
      const user = ids.revisions;
      const payload = { source: 'thought', book_id: 'revision-book', user_input: 'v1' };
      await entries.upsertEntryByClientId(user, 'r1', payload, version(1));
      await entries.deleteEntryByClientId(user, 'r1', version(3));
      await assert.rejects(entries.upsertEntryByClientId(user, 'r1', { ...payload, user_input: 'v2' }, version(2)), { statusCode: 409 });
      await entries.deleteEntryByClientId(user, 'r1', version(3));
      await entries.deleteEntryByClientId(user, 'r1', version(3));
      const deleted = await query('SELECT * FROM user_entry_upload_states WHERE user_id=$1 AND client_entry_id=$2', [user, 'r1']);
      assert.equal(deleted.rows[0].latest_revision, '3');
      assert.equal(deleted.rows[0].deleted, true);
      assert.equal((await mcpRepository.listTraces(user)).items.length, 0);
      assert.equal((await query('SELECT * FROM sync_changes WHERE user_id=$1', [user])).rowCount, 2);

      const first = await entries.upsertEntryByClientId(user, 'r2', payload, version(1));
      await entries.upsertEntryByClientId(user, 'r2', { ...payload, user_input: 'v2' }, version(2));
      await assert.rejects(entries.upsertEntryByClientId(user, 'r2', { ...payload, user_input: 'late' }, version(1)), { statusCode: 409 });
      await assert.rejects(entries.upsertEntryByClientId(user, 'r2', { ...payload, user_input: 'reused' }, version(2)), { statusCode: 409 });
      await assert.rejects(entries.deleteEntryByClientId(user, 'r2', version(99, '22222222-2222-4222-8222-222222222222')), { statusCode: 409 });
      await assert.rejects(entries.deleteEntryByClientId(user, 'r2'), { statusCode: 428 });
      await assert.rejects(entries.deleteEntry(user, first.entry.id), { statusCode: 428 });
      assert.equal((await mcpRepository.getTraceById(user, first.entry.id)).note, 'v2');
      const all = await query('SELECT user_sequence, operation FROM sync_changes WHERE user_id=$1 ORDER BY user_sequence', [user]);
      assert.deepEqual(all.rows.map(row => Number(row.user_sequence)), [1, 2, 3, 4]);
    });

    await t.test('permanent deletion removes cloud-only traces, is idempotent, and blocks offline resurrection', async () => {
      const entries = require('./entry.repository');
      const progress = require('./readingProgress.repository');
      const { permanentlyDeleteBookData } = require('./bookDeletion.repository');
      const user = ids.purge;
      const book = 'cloud-only-book';
      await query(`CREATE TABLE user_entry_follow_ups (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(), entry_id UUID REFERENCES user_entries(id) ON DELETE CASCADE,
        user_id UUID REFERENCES users(id), question TEXT, answer TEXT)`);
      const cloud = [];
      for (const source of ['highlight', 'thought', 'ai_explanation', 'ai_question']) {
        cloud.push(await entries.upsertEntryByClientId(user, source, { source, book_id: book }, version(1)));
      }
      await query('INSERT INTO user_entry_follow_ups(entry_id,user_id,question,answer) VALUES($1,$2,$3,$4)',
        [cloud[0].entry.id, user, 'test', 'test']);
      await entries.upsertEntryByClientId(ids.revisions, 'foreign', { source: 'thought', book_id: book }, version(1));
      await progress.upsertReadingProgress(user, { book_id: book, progress: 0.6, ...version(1) });
      await mcpRepository.syncLibraryBooks(user, [{ book_id: book, title: 'Test' }], { replace: true });
      const before = await query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [user]);
      const purged = await permanentlyDeleteBookData(user, book);
      assert.deepEqual(purged, { traces: 4, progresses: 1, books: 1 });
      assert.deepEqual(await permanentlyDeleteBookData(user, book), { traces: 0, progresses: 0, books: 0 });
      assert.equal((await mcpRepository.listTraces(user, { bookId: book })).items.length, 0);
      assert.equal(await mcpRepository.getTraceById(user, cloud[0].entry.id), null);
      assert.equal((await mcpRepository.listTraces(ids.revisions, { bookId: book })).items.length, 1);
      assert.equal((await query('SELECT * FROM user_entry_follow_ups WHERE user_id=$1', [user])).rowCount, 0);
      await assert.rejects(entries.upsertEntryByClientId(user, 'thought', { source: 'thought', book_id: book }, version(2)), { statusCode: 410 });
      await assert.rejects(entries.upsertEntryByClientId(user, 'not-yet-uploaded', { source: 'thought', book_id: book }, version(1)), { statusCode: 410 });
      await assert.rejects(entries.createEntry(user, { source: 'thought', book_id: book }), { statusCode: 410 });
      for (const revision of [1, 2, 99]) {
        await assert.rejects(progress.upsertReadingProgress(user, { book_id: book, progress: 0.6, ...version(revision) }), { statusCode: 410 });
      }
      await assert.rejects(progress.deleteReadingProgress(user, book, version(2)), { statusCode: 410 });
      const progressState = (await query('SELECT * FROM reading_progress_upload_states WHERE user_id=$1 AND book_id=$2', [user, book])).rows[0];
      assert.equal(progressState.deleted, true);
      assert.equal(progressState.latest_revision, '1');
      await mcpRepository.syncLibraryBooks(user, [{ book_id: book, title: 'Stale' }], { replace: true });
      assert.equal((await mcpRepository.listLibraryBooks(user)).items.length, 0);
      const changes = await query('SELECT * FROM sync_changes WHERE user_id=$1 AND user_sequence>$2', [user, before.rows[0].last_sequence]);
      assert.equal(changes.rowCount, 6);
      assert.ok(changes.rows.every(row => row.operation === 'deleted'));
      const stateBefore = await query('SELECT * FROM user_entry_upload_states WHERE user_id=$1 ORDER BY client_entry_id', [user]);
      const fenceBefore = await query('SELECT * FROM permanently_deleted_books WHERE user_id=$1', [user]);
      await query(fs.readFileSync(path.join(__dirname, '../db/migrations/005_upload_revisions.up.sql'), 'utf8'));
      assert.deepEqual((await query('SELECT * FROM user_entry_upload_states WHERE user_id=$1 ORDER BY client_entry_id', [user])).rows, stateBefore.rows);
      assert.deepEqual((await query('SELECT * FROM permanently_deleted_books WHERE user_id=$1', [user])).rows, fenceBefore.rows);
      await entries.upsertEntryByClientId(user, 'new-import', { source: 'thought', book_id: 'new-book-id' }, version(1));
    });

    await t.test('ledger failure rolls back entry revision and permanent book fences with all data', async () => {
      const entries = require('./entry.repository');
      const { permanentlyDeleteBookData } = require('./bookDeletion.repository');
      const user = ids.failure;
      const payload = { source: 'thought', book_id: 'rollback-book', user_input: 'before' };
      const initial = await entries.upsertEntryByClientId(user, 'rollback', payload, version(1));
      await query(`CREATE FUNCTION reject_test_ledger() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN RAISE EXCEPTION 'test ledger failure'; END $$;
        CREATE TRIGGER reject_test_ledger BEFORE INSERT ON sync_changes
        FOR EACH ROW WHEN (NEW.user_id = '${user}'::uuid) EXECUTE FUNCTION reject_test_ledger()`);
      try {
        await assert.rejects(entries.upsertEntryByClientId(user, 'rollback', { ...payload, user_input: 'after' }, version(2)), /test ledger failure/);
        await assert.rejects(permanentlyDeleteBookData(user, 'rollback-book'), /test ledger failure/);
        assert.equal((await mcpRepository.getTraceById(user, initial.entry.id)).note, 'before');
        const state = (await query('SELECT * FROM user_entry_upload_states WHERE user_id=$1', [user])).rows[0];
        assert.equal(state.latest_revision, '1');
        assert.equal(state.deleted, false);
        assert.equal((await query('SELECT * FROM permanently_deleted_books WHERE user_id=$1', [user])).rowCount, 0);
        assert.equal((await query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [user])).rows[0].last_sequence, '1');
      } finally {
        await query('DROP TRIGGER reject_test_ledger ON sync_changes; DROP FUNCTION reject_test_ledger()');
      }
      await query(`CREATE FUNCTION reject_test_revision() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN RAISE EXCEPTION 'test revision failure'; END $$;
        CREATE TRIGGER reject_test_revision BEFORE INSERT OR UPDATE ON user_entry_upload_states
        FOR EACH ROW WHEN (NEW.user_id = '${user}'::uuid) EXECUTE FUNCTION reject_test_revision()`);
      try {
        await assert.rejects(entries.upsertEntryByClientId(user, 'state-failure', payload, version(1)), /test revision failure/);
        assert.equal((await query('SELECT * FROM user_entries WHERE user_id=$1 AND client_entry_id=$2', [user, 'state-failure'])).rowCount, 0);
        assert.equal((await query('SELECT * FROM user_entry_upload_states WHERE user_id=$1 AND client_entry_id=$2', [user, 'state-failure'])).rowCount, 0);
        assert.equal((await query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [user])).rows[0].last_sequence, '1');
      } finally {
        await query('DROP TRIGGER reject_test_revision ON user_entry_upload_states; DROP FUNCTION reject_test_revision()');
      }
    });

    await t.test('permanent purge and concurrent new upload serialize before book/entry locks', async () => {
      const { lockUploadUser } = require('./uploadState.repository');
      const { permanentlyDeleteBookData } = require('./bookDeletion.repository');
      const entries = require('./entry.repository');
      const client = await connect();
      let purge;
      try {
        await client.query('BEGIN');
        await lockUploadUser((sql, params) => client.query(sql, params), ids.failure);
        let completed = false;
        purge = permanentlyDeleteBookData(ids.failure, 'concurrent-book').then(result => { completed = true; return result; });
        await delay(100);
        assert.equal(completed, false);
        const writer = entries.upsertEntryByClientId(ids.failure, 'late-new', { source: 'thought', book_id: 'concurrent-book' }, version(1));
        const rejected = assert.rejects(writer, { statusCode: 410 });
        await client.query('COMMIT');
        await purge;
        await rejected;
        assert.equal((await mcpRepository.listTraces(ids.failure, { bookId: 'concurrent-book' })).items.length, 0);
      } finally {
        await client.query('ROLLBACK');
        await client.end();
        if (purge) await purge;
      }
    });

    await t.test('progress revisions reject stale writes and accept a newer lower reading position', async () => {
      const progress = require('./readingProgress.repository');
      const user = ids.failure;
      const book = 'progress-order';
      const save = (revision, value, writer) => progress.upsertReadingProgress(user,
        { book_id: book, progress: value, chapter_index: String(value), ...version(revision, writer) });
      const watermark = () => query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [user]);
      await save(1, 0.2);
      const latest = await save(2, 0.8);
      const before = await watermark();
      await assert.rejects(save(1, 0.2), { statusCode: 409 });
      await assert.rejects(save(1, 0.9), { statusCode: 409 });
      await assert.rejects(save(2, 0.1), { statusCode: 409 });
      await assert.rejects(save(3, 0.1, '22222222-2222-4222-8222-222222222222'), { statusCode: 409 });
      await assert.rejects(progress.upsertReadingProgress(user, { book_id: book, progress: 0.1 }), { statusCode: 428 });
      await assert.rejects(progress.deleteReadingProgress(user, book), { statusCode: 428 });
      assert.deepEqual(await save(2, 0.8), latest);
      assert.deepEqual((await watermark()).rows, before.rows);
      assert.equal((await progress.getReadingProgress(user, book)).progress, 0.8);
      assert.equal((await save(3, 0.2)).progress, 0.2);
      const afterLower = await watermark();
      await save(4, 0.2);
      assert.deepEqual((await watermark()).rows, afterLower.rows, 'revision-only change emits no fake ledger');
      const other = await progress.upsertReadingProgress(ids.purge, { book_id: book, progress: 0.9, ...version(1) });
      assert.equal(other.progress, 0.9);
      assert.equal((await progress.getReadingProgress(user, book)).progress, 0.2);
    });

    await t.test('progress delete retries retain tombstones and recreate cannot be removed by old DELETE', async () => {
      const progress = require('./readingProgress.repository');
      const user = ids.failure;
      const book = 'progress-delete';
      const save = revision => progress.upsertReadingProgress(user, { book_id: book, progress: 0.4, ...version(revision) });
      const first = await save(1);
      assert.equal(await progress.deleteReadingProgress(user, book, version(2)), true);
      for (let i = 0; i < 3; i++) assert.equal(await progress.deleteReadingProgress(user, book, version(2)), false);
      await assert.rejects(save(1), { statusCode: 409 });
      assert.equal(await progress.getReadingProgress(user, book), null);
      const migration006 = fs.readFileSync(path.join(__dirname, '../db/migrations/006_progress_upload_revisions.up.sql'), 'utf8');
      const state = (await query('SELECT * FROM reading_progress_upload_states WHERE user_id=$1 AND book_id=$2', [user, book])).rows[0];
      assert.equal(state.deleted, true);
      assert.equal(state.latest_revision, '2');
      await query(migration006);
      await query(migration006);
      assert.deepEqual((await query('SELECT * FROM reading_progress_upload_states WHERE user_id=$1 AND book_id=$2', [user, book])).rows[0], state);
      const recreated = await save(3);
      await assert.rejects(progress.deleteReadingProgress(user, book, version(2)), { statusCode: 409 });
      assert.deepEqual(await progress.getReadingProgress(user, book), recreated);
      const changes = await query(`SELECT operation FROM sync_changes WHERE user_id=$1
        AND entity_type='reading_progress' AND entity_id=ANY($2::text[]) ORDER BY user_sequence`, [user, [first.id, recreated.id]]);
      assert.deepEqual(changes.rows.map(row => row.operation), ['created', 'deleted', 'created']);
      await progress.deleteReadingProgress(user, 'never-uploaded-progress', version(5));
      await assert.rejects(progress.upsertReadingProgress(user, { book_id: 'never-uploaded-progress', progress: 0.1, ...version(4) }), { statusCode: 409 });
    });

    await t.test('progress state and ledger failures roll back data, tombstone and cursor together', async () => {
      const progress = require('./readingProgress.repository');
      const { permanentlyDeleteBookData } = require('./bookDeletion.repository');
      const user = ids.failure;
      const book = 'progress-rollback';
      const initial = await progress.upsertReadingProgress(user, { book_id: book, progress: 0.8, ...version(1) });
      const beforeState = await query('SELECT * FROM reading_progress_upload_states WHERE user_id=$1 AND book_id=$2', [user, book]);
      const beforeCursor = await query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [user]);
      for (const table of ['sync_changes', 'reading_progress_upload_states']) {
        await query(`CREATE FUNCTION reject_progress_test() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN RAISE EXCEPTION 'progress transaction failure'; END $$;
          CREATE TRIGGER reject_progress_test BEFORE INSERT OR UPDATE ON ${table}
          FOR EACH ROW WHEN (NEW.user_id='${user}'::uuid) EXECUTE FUNCTION reject_progress_test()`);
        try {
          await assert.rejects(progress.upsertReadingProgress(user, { book_id: book, progress: 0.2, ...version(2) }), /progress transaction failure/);
          await assert.rejects(progress.deleteReadingProgress(user, book, version(2)), /progress transaction failure/);
          await assert.rejects(permanentlyDeleteBookData(user, book), /progress transaction failure/);
          assert.deepEqual(await progress.getReadingProgress(user, book), initial);
          assert.deepEqual((await query('SELECT * FROM reading_progress_upload_states WHERE user_id=$1 AND book_id=$2', [user, book])).rows, beforeState.rows);
          assert.deepEqual((await query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1', [user])).rows, beforeCursor.rows);
          assert.equal((await query('SELECT * FROM permanently_deleted_books WHERE user_id=$1 AND book_id=$2', [user, book])).rowCount, 0);
        } finally {
          await query(`DROP TRIGGER reject_progress_test ON ${table}; DROP FUNCTION reject_progress_test()`);
        }
      }
    });

    await t.test('concurrent delayed progress cannot bypass the per-user transaction lock', async () => {
      const progress = require('./readingProgress.repository');
      const { lockUploadUser } = require('./uploadState.repository');
      const client = await connect();
      const user = ids.failure;
      const book = 'progress-concurrent';
      let newer;
      let older;
      try {
        await client.query('BEGIN');
        await lockUploadUser((sql, params) => client.query(sql, params), user);
        let done = false;
        newer = progress.upsertReadingProgress(user, { book_id: book, progress: 0.8, ...version(2) })
          .then(row => { done = true; return { row }; }, error => ({ error }));
        await delay(100);
        assert.equal(done, false);
        older = progress.upsertReadingProgress(user, { book_id: book, progress: 0.2, ...version(1) })
          .then(row => ({ row }), error => ({ error }));
        await client.query('COMMIT');
        assert.equal((await newer).error, undefined);
        // Lock waiters need not be FIFO: rev1 may commit first, but never after rev2.
        const oldResult = await older;
        if (oldResult.error) assert.equal(oldResult.error.statusCode, 409);
        assert.equal((await progress.getReadingProgress(user, book)).progress, 0.8);
        assert.equal((await query('SELECT latest_revision FROM reading_progress_upload_states WHERE user_id=$1 AND book_id=$2', [user, book])).rows[0].latest_revision, '2');
      } finally {
        await client.query('ROLLBACK');
        await client.end();
        await Promise.allSettled([newer, older].filter(Boolean));
      }
    });

    await t.test('reproduces the unsafe BIGSERIAL commit-order gap', async () => {
      await query(`
        CREATE TABLE unsafe_sync_changes (
          sequence BIGSERIAL PRIMARY KEY,
          user_id UUID NOT NULL,
          entity_id TEXT NOT NULL
        )
      `);
      const firstClient = await connect();
      const secondClient = await connect();
      try {
        await firstClient.query('BEGIN');
        const first = await firstClient.query(
          `INSERT INTO unsafe_sync_changes (user_id, entity_id)
           VALUES ($1, 'T1') RETURNING sequence`,
          [ids.unsafe],
        );
        await secondClient.query('BEGIN');
        const second = await secondClient.query(
          `INSERT INTO unsafe_sync_changes (user_id, entity_id)
           VALUES ($1, 'T2') RETURNING sequence`,
          [ids.unsafe],
        );
        await secondClient.query('COMMIT');
        const savedCursor = second.rows[0].sequence;
        await firstClient.query('COMMIT');
        const incremental = await query(
          `SELECT entity_id FROM unsafe_sync_changes
           WHERE sequence > $1 ORDER BY sequence`,
          [savedCursor],
        );

        assert.equal(Number(first.rows[0].sequence), 1);
        assert.equal(Number(savedCursor), 2);
        assert.deepEqual(incremental.rows, []);
      } finally {
        await Promise.all([firstClient.end(), secondClient.end()]);
      }
    });

    await t.test('serializes sequence allocation for the same user', async () => {
      const firstClient = await connect();
      const secondClient = await connect();
      try {
        await firstClient.query('BEGIN');
        const first = await appendWithClient(firstClient, {
          userId: ids.serialized,
          entityType: 'trace',
          entityId: 'T1',
          operation: 'created',
        });

        await secondClient.query('BEGIN');
        let secondSettled = false;
        const secondPromise = appendWithClient(secondClient, {
          userId: ids.serialized,
          entityType: 'trace',
          entityId: 'T2',
          operation: 'created',
        }).then((value) => {
          secondSettled = true;
          return value;
        });

        await delay(200);
        assert.equal(secondSettled, false, 'T2 must wait for the same-user cursor row');
        await firstClient.query('COMMIT');
        const second = await secondPromise;
        await secondClient.query('COMMIT');

        assert.equal(Number(first.user_sequence), 1);
        assert.equal(Number(second.user_sequence), 2);
        const rows = await query(
          `SELECT user_sequence, entity_id
           FROM sync_changes
           WHERE user_id = $1
           ORDER BY user_sequence`,
          [ids.serialized],
        );
        assert.deepEqual(rows.rows.map((row) => ({
          user_sequence: Number(row.user_sequence),
          entity_id: row.entity_id,
        })), [
          { user_sequence: 1, entity_id: 'T1' },
          { user_sequence: 2, entity_id: 'T2' },
        ]);
      } finally {
        await Promise.allSettled([
          firstClient.query('ROLLBACK'),
          secondClient.query('ROLLBACK'),
        ]);
        await Promise.all([firstClient.end(), secondClient.end()]);
      }
    });

    await t.test('rolls back both the cursor increment and ledger row', async () => {
      const client = await connect();
      try {
        await client.query('BEGIN');
        const rolledBack = await appendWithClient(client, {
          userId: ids.rollback,
          entityType: 'trace',
          entityId: 'rolled-back',
          operation: 'created',
        });
        assert.equal(Number(rolledBack.user_sequence), 1);
        await client.query('ROLLBACK');

        const visible = await query(
          'SELECT * FROM sync_changes WHERE user_id = $1',
          [ids.rollback],
        );
        assert.equal(visible.rowCount, 0);

        await client.query('BEGIN');
        const committed = await appendWithClient(client, {
          userId: ids.rollback,
          entityType: 'trace',
          entityId: 'committed',
          operation: 'created',
        });
        await client.query('COMMIT');
        assert.equal(Number(committed.user_sequence), 1);
      } finally {
        await client.query('ROLLBACK').catch(() => {});
        await client.end();
      }
    });

    await t.test('allows different users to allocate cursors concurrently', async () => {
      const firstClient = await connect();
      const secondClient = await connect();
      try {
        await firstClient.query('BEGIN');
        await appendWithClient(firstClient, {
          userId: ids.parallelA,
          entityType: 'trace',
          entityId: 'A1',
          operation: 'created',
        });

        await secondClient.query('BEGIN');
        const second = await Promise.race([
          appendWithClient(secondClient, {
            userId: ids.parallelB,
            entityType: 'trace',
            entityId: 'B1',
            operation: 'created',
          }),
          delay(1000).then(() => {
            throw new Error('Different users unexpectedly blocked each other');
          }),
        ]);
        await secondClient.query('COMMIT');
        await firstClient.query('ROLLBACK');

        assert.equal(Number(second.user_sequence), 1);
        const visible = await query(
          'SELECT entity_id FROM sync_changes WHERE user_id = $1',
          [ids.parallelB],
        );
        assert.deepEqual(visible.rows, [{ entity_id: 'B1' }]);
      } finally {
        await Promise.allSettled([
          firstClient.query('ROLLBACK'),
          secondClient.query('ROLLBACK'),
        ]);
        await Promise.all([firstClient.end(), secondClient.end()]);
      }
    });

    await t.test('keeps snapshot watermark and later incrementals contiguous', async () => {
      const initialClient = await connect();
      await initialClient.query('BEGIN');
      const initialEntry = await initialClient.query(
        `INSERT INTO user_entries (user_id, source, original_text)
         VALUES ($1, 'highlight', 'first') RETURNING id`,
        [ids.snapshot],
      );
      await appendWithClient(initialClient, {
        userId: ids.snapshot,
        entityType: 'trace',
        entityId: initialEntry.rows[0].id,
        operation: 'created',
      });
      await initialClient.query('COMMIT');
      await initialClient.end();

      const snapshotClient = await connect();
      const writerClient = await connect();
      try {
        await snapshotClient.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
        const snapshotRows = await snapshotClient.query(
          'SELECT id FROM user_entries WHERE user_id = $1 ORDER BY created_at, id',
          [ids.snapshot],
        );
        const watermarkResult = await snapshotClient.query(
          `SELECT COALESCE(last_sequence, 0) AS watermark
           FROM sync_user_cursors WHERE user_id = $1`,
          [ids.snapshot],
        );
        const watermark = Number(watermarkResult.rows[0].watermark);

        await writerClient.query('BEGIN');
        const laterEntry = await writerClient.query(
          `INSERT INTO user_entries (user_id, source, original_text)
           VALUES ($1, 'highlight', 'second') RETURNING id`,
          [ids.snapshot],
        );
        await appendWithClient(writerClient, {
          userId: ids.snapshot,
          entityType: 'trace',
          entityId: laterEntry.rows[0].id,
          operation: 'created',
        });
        await writerClient.query('COMMIT');

        const stableSnapshotRows = await snapshotClient.query(
          'SELECT id FROM user_entries WHERE user_id = $1 ORDER BY created_at, id',
          [ids.snapshot],
        );
        assert.equal(snapshotRows.rowCount, 1);
        assert.equal(stableSnapshotRows.rowCount, 1);
        await snapshotClient.query('COMMIT');

        const incremental = await query(
          `SELECT entity_id, user_sequence
           FROM sync_changes
           WHERE user_id = $1 AND user_sequence > $2
           ORDER BY user_sequence`,
          [ids.snapshot, watermark],
        );
        assert.deepEqual(incremental.rows.map((row) => ({
          entity_id: row.entity_id,
          user_sequence: Number(row.user_sequence),
        })), [{
          entity_id: laterEntry.rows[0].id,
          user_sequence: watermark + 1,
        }]);
      } finally {
        await Promise.allSettled([
          snapshotClient.query('ROLLBACK'),
          writerClient.query('ROLLBACK'),
        ]);
        await Promise.all([snapshotClient.end(), writerClient.end()]);
      }
    });

    await t.test('replace emits only C deleted and D created for A,B,C -> A,B,D', async () => {
      await query(
        `INSERT INTO user_library_books (
           user_id, book_id, title, author, format
         ) VALUES
           ($1, 'A', 'Book A', 'Author', 'epub'),
           ($1, 'B', 'Book B', 'Author', 'epub'),
           ($1, 'C', 'Book C', 'Author', 'epub')`,
        [ids.replace],
      );

      await mcpRepository.syncLibraryBooks(ids.replace, [
        { book_id: 'A', title: 'Book A', author: 'Author', format: 'epub' },
        { book_id: 'B', title: 'Book B', author: 'Author', format: 'epub' },
        { book_id: 'D', title: 'Book D', author: 'Author', format: 'epub' },
      ], { replace: true });

      const changes = await query(
        `SELECT entity_id, operation
         FROM sync_changes
         WHERE user_id = $1
         ORDER BY user_sequence`,
        [ids.replace],
      );
      assert.deepEqual(changes.rows, [
        { entity_id: 'C', operation: 'deleted' },
        { entity_id: 'D', operation: 'created' },
      ]);
      const books = await query(
        `SELECT book_id FROM user_library_books
         WHERE user_id = $1 ORDER BY book_id`,
        [ids.replace],
      );
      assert.deepEqual(books.rows, [
        { book_id: 'A' },
        { book_id: 'B' },
        { book_id: 'D' },
      ]);
    });
  });
}
