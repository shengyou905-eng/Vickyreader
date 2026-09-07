process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { appendSyncChange } = require('./syncChange.repository');

const dbModulePath = require.resolve('../config/db');
const version = { writer_id: '11111111-1111-4111-8111-111111111111', client_revision: 1 };

function loadRepository(relativePath, dbMock) {
  const repositoryPath = require.resolve(relativePath);
  const previousDb = require.cache[dbModulePath];
  delete require.cache[repositoryPath];
  require.cache[dbModulePath] = {
    id: dbModulePath,
    filename: dbModulePath,
    loaded: true,
    exports: dbMock,
    children: [],
    paths: [],
  };
  const repository = require(repositoryPath);
  if (previousDb) {
    require.cache[dbModulePath] = previousDb;
  } else {
    delete require.cache[dbModulePath];
  }
  return repository;
}

function result(rows = []) {
  return { rows, rowCount: rows.length };
}

function scriptedDb(steps, { failLedger = false } = {}) {
  const calls = [];
  const state = {
    committed: false,
    rolledBack: false,
    businessCommitted: false,
  };

  return {
    calls,
    state,
    query: async () => {
      throw new Error('Unexpected non-transactional query');
    },
    withTransaction: async (callback) => {
      let touchedBusiness = false;
      try {
        const value = await callback(async (sql, params = []) => {
          if (/^INSERT INTO sync_user_cursors|FROM permanently_deleted_books|user_entry_upload_states|reading_progress_upload_states/.test(sql)) return result();
          calls.push({ sql, params });
          if (/sync_changes/.test(sql) && failLedger) {
            throw new Error('simulated ledger failure');
          }
          const step = steps.shift();
          assert.ok(step, `Unexpected SQL: ${sql}`);
          assert.match(sql, step.sql);
          if (!/sync_changes/.test(sql)) touchedBusiness = true;
          return step.value;
        });
        assert.equal(steps.length, 0, 'Not all expected SQL statements ran');
        state.committed = true;
        state.businessCommitted = touchedBusiness;
        return value;
      } catch (error) {
        state.rolledBack = true;
        state.businessCommitted = false;
        throw error;
      }
    },
  };
}

test('Phase 1A repositories emit transactional ledger changes', async (t) => {
  await t.test('creates a user entry and its created ledger row together', async () => {
    const entry = {
      id: '10000000-0000-0000-0000-000000000001',
      user_id: '20000000-0000-0000-0000-000000000001',
      source: 'thought',
    };
    const db = scriptedDb([
      { sql: /INSERT INTO user_entries/, value: result([entry]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 1 }]) },
    ]);
    const repository = loadRepository('./entry.repository', db);

    const created = await repository.createEntry(entry.user_id, {
      source: 'thought',
      user_input: 'private test thought',
    });

    assert.equal(created.id, entry.id);
    assert.deepEqual(db.calls[1].params, [entry.user_id, 'trace', entry.id, 'created']);
    assert.equal(db.state.committed, true);
  });

  await t.test('updates user entry updated_at and emits updated', async () => {
    const oldTime = '2026-01-01T00:00:00.000Z';
    const newTime = '2026-01-02T00:00:00.000Z';
    const entry = {
      id: '10000000-0000-0000-0000-000000000002',
      user_id: '20000000-0000-0000-0000-000000000001',
      is_important: true,
      updated_at: newTime,
    };
    const db = scriptedDb([
      { sql: /UPDATE user_entries[\s\S]*updated_at = now\(\)/, value: result([entry]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 2 }]) },
    ]);
    const repository = loadRepository('./entry.repository', db);

    const updated = await repository.updateEntryImportance(entry.user_id, entry.id, true);

    assert.notEqual(updated.updated_at, oldTime);
    assert.equal(updated.updated_at, newTime);
    assert.deepEqual(db.calls[1].params, [entry.user_id, 'trace', entry.id, 'updated']);
  });

  await t.test('hard-deletes a user entry but commits its tombstone', async () => {
    const userId = '20000000-0000-0000-0000-000000000001';
    const entryId = '10000000-0000-0000-0000-000000000003';
    const db = scriptedDb([
      { sql: /DELETE FROM user_entries/, value: result([{ id: entryId }]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 3 }]) },
    ]);
    const repository = loadRepository('./entry.repository', db);

    assert.equal(await repository.deleteEntry(userId, entryId), true);
    assert.deepEqual(db.calls[1].params, [userId, 'trace', entryId, 'deleted']);
    assert.equal(db.state.committed, true);
  });

  await t.test('distinguishes created and updated reading progress', async () => {
    const userId = '20000000-0000-0000-0000-000000000001';
    const createdRow = { id: 'progress-created', book_id: 'book-1' };
    const createdDb = scriptedDb([
      { sql: /INSERT INTO reading_progresses/, value: result([createdRow]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 4 }]) },
    ]);
    const createdRepository = loadRepository('./readingProgress.repository', createdDb);
    await createdRepository.upsertReadingProgress(userId, { book_id: 'book-1', ...version });
    assert.deepEqual(
      createdDb.calls[1].params,
      [userId, 'reading_progress', createdRow.id, 'created'],
    );

    const updatedRow = { id: 'progress-existing', book_id: 'book-1' };
    const updatedDb = scriptedDb([
      { sql: /INSERT INTO reading_progresses/, value: result() },
      { sql: /UPDATE reading_progresses/, value: result([updatedRow]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 5 }]) },
    ]);
    const updatedRepository = loadRepository('./readingProgress.repository', updatedDb);
    await updatedRepository.upsertReadingProgress(userId, { book_id: 'book-1', progress: 0.5, ...version });
    assert.deepEqual(
      updatedDb.calls[2].params,
      [userId, 'reading_progress', updatedRow.id, 'updated'],
    );
  });

  await t.test('distinguishes created and updated library books', async () => {
    const userId = '20000000-0000-0000-0000-000000000001';
    const db = scriptedDb([
      { sql: /INSERT INTO user_library_books/, value: result([{ book_id: 'book-created' }]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 6 }]) },
      { sql: /INSERT INTO user_library_books/, value: result() },
      { sql: /UPDATE user_library_books/, value: result([{ book_id: 'book-existing' }]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 7 }]) },
    ]);
    const repository = loadRepository('./mcp.repository', db);

    await repository.syncLibraryBooks(userId, [
      { book_id: 'book-created', title: 'Created book' },
      { book_id: 'book-existing', title: 'Updated book' },
    ]);

    assert.deepEqual(db.calls[1].params, [userId, 'book', 'book-created', 'created']);
    assert.deepEqual(db.calls[4].params, [userId, 'book', 'book-existing', 'updated']);
  });

  await t.test('hard-deletes a library book and retains its tombstone', async () => {
    const userId = '20000000-0000-0000-0000-000000000001';
    const db = scriptedDb([
      { sql: /DELETE FROM user_library_books/, value: result([{ book_id: 'book-deleted' }]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 8 }]) },
    ]);
    const repository = loadRepository('./mcp.repository', db);

    assert.equal(await repository.deleteLibraryBook(userId, 'book-deleted'), true);
    assert.deepEqual(db.calls[1].params, [userId, 'book', 'book-deleted', 'deleted']);
  });

  await t.test('rolls back the business write when the ledger insert fails', async () => {
    const db = scriptedDb(
      [{
        sql: /INSERT INTO user_entries/,
        value: result([{ id: 'entry-that-must-rollback' }]),
      }],
      { failLedger: true },
    );
    const repository = loadRepository('./entry.repository', db);

    await assert.rejects(
      repository.createEntry('user-a', { source: 'highlight' }),
      /simulated ledger failure/,
    );
    assert.equal(db.state.committed, false);
    assert.equal(db.state.businessCommitted, false);
    assert.equal(db.state.rolledBack, true);
  });

  await t.test('sync sequence values are strictly increasing', async () => {
    let userSequence = 0;
    const txQuery = async (_sql, params) => result([{
      user_sequence: ++userSequence,
      params,
    }]);
    const first = await appendSyncChange(txQuery, {
      userId: 'user-a',
      entityType: 'trace',
      entityId: 'trace-1',
      operation: 'created',
    });
    const second = await appendSyncChange(txQuery, {
      userId: 'user-a',
      entityType: 'trace',
      entityId: 'trace-1',
      operation: 'updated',
    });
    const third = await appendSyncChange(txQuery, {
      userId: 'user-a',
      entityType: 'trace',
      entityId: 'trace-1',
      operation: 'deleted',
    });
    assert.deepEqual(
      [first.user_sequence, second.user_sequence, third.user_sequence],
      [1, 2, 3],
    );
  });

  await t.test('uses the authenticated user for both data and ledger writes', async () => {
    const userId = '20000000-0000-0000-0000-00000000000a';
    const entryId = '10000000-0000-0000-0000-00000000000a';
    const db = scriptedDb([
      { sql: /INSERT INTO user_entries/, value: result([{ id: entryId }]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 9 }]) },
    ]);
    const repository = loadRepository('./entry.repository', db);
    await repository.createEntry(userId, { source: 'ai_question' });

    assert.equal(db.calls[0].params[0], userId);
    assert.equal(db.calls[1].params[0], userId);
    assert.ok(db.calls.every((call) => !call.params.includes('user-b')));
  });

  await t.test('migration backfills timestamps without synthetic history events', () => {
    const migration = fs.readFileSync(
      path.join(__dirname, '../db/migrations/003_sync_changes_ledger.up.sql'),
      'utf8',
    );
    assert.match(migration, /SET updated_at = created_at/);
    assert.match(migration, /CREATE TABLE IF NOT EXISTS sync_changes/);
    assert.match(migration, /CREATE TABLE IF NOT EXISTS sync_user_cursors/);
    assert.match(migration, /ON sync_changes\(user_id, user_sequence\)/);
    assert.doesNotMatch(migration, /INSERT INTO sync_changes/);
  });
});
