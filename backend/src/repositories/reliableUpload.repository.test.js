process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';

const test = require('node:test');
const assert = require('node:assert/strict');

const dbModulePath = require.resolve('../config/db');
const version = { writer_id: '11111111-1111-4111-8111-111111111111', client_revision: 1 };

function result(rows = []) {
  return { rows, rowCount: rows.length };
}

function loadRepository(relativePath, responses) {
  const repositoryPath = require.resolve(relativePath);
  const previousDb = require.cache[dbModulePath];
  delete require.cache[repositoryPath];
  const calls = [];
  require.cache[dbModulePath] = {
    id: dbModulePath,
    filename: dbModulePath,
    loaded: true,
    exports: {
      query: async () => { throw new Error('Unexpected query'); },
      withTransaction: async (callback) => callback(async (sql, params = []) => {
        if (/^INSERT INTO sync_user_cursors|FROM permanently_deleted_books|user_entry_upload_states|reading_progress_upload_states/.test(sql)) return result();
        if (/SELECT \* FROM user_entries/.test(sql) && !responses[0]?.sql.test(sql)) return result();
        calls.push({ sql, params });
        const next = responses.shift();
        assert.ok(next, `Unexpected SQL: ${sql}`);
        assert.match(sql, next.sql);
        return next.value;
      }),
    },
    children: [],
    paths: [],
  };
  const repository = require(repositoryPath);
  if (previousDb) require.cache[dbModulePath] = previousDb;
  else delete require.cache[dbModulePath];
  return { repository, calls };
}

test('client entry upsert is idempotent and ledger-backed', async (t) => {
  const userId = '20000000-0000-0000-0000-000000000001';
  const entry = { id: '10000000-0000-0000-0000-000000000001' };

  await t.test('first upload creates one canonical entry and ledger event', async () => {
    const { repository, calls } = loadRepository('./entry.repository', [
      { sql: /INSERT INTO user_entries/, value: result([entry]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 1 }]) },
    ]);
    const saved = await repository.upsertEntryByClientId(userId, 'local-1', {
      source: 'thought', user_input: 'A thought', ...version,
    });
    assert.equal(saved.operation, 'created');
    assert.equal(saved.entry.id, entry.id);
    assert.equal(calls[0].params[1], 'local-1');
  });

  await t.test('identical retry is a no-op without a duplicate ledger event', async () => {
    const { repository, calls } = loadRepository('./entry.repository', [
      { sql: /INSERT INTO user_entries/, value: result() },
      { sql: /UPDATE user_entries/, value: result() },
      { sql: /SELECT \* FROM user_entries/, value: result([entry]) },
    ]);
    const saved = await repository.upsertEntryByClientId(userId, 'local-1', {
      source: 'thought', user_input: 'A thought', ...version,
    });
    assert.equal(saved.operation, null);
    assert.equal(calls.length, 3);
  });

  await t.test('idempotent delete does not emit a false tombstone', async () => {
    const { repository, calls } = loadRepository('./entry.repository', [
      { sql: /DELETE FROM user_entries/, value: result() },
    ]);
    assert.equal(
      await repository.deleteEntryByClientId(userId, 'already-gone', version),
      false,
    );
    assert.equal(calls.length, 1);
  });

  await t.test('legacy server UUID can be deleted when client id was never stored', async () => {
    const legacyId = '10000000-0000-0000-0000-000000000009';
    const { repository, calls } = loadRepository('./entry.repository', [
      { sql: /DELETE FROM user_entries/, value: result([{ id: legacyId }]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 3 }]) },
    ]);
    assert.equal(
      await repository.deleteEntryByClientId(userId, legacyId, version),
      true,
    );
    assert.match(calls[0].sql, /client_entry_id IS NULL AND id::text = \$2/);
    assert.deepEqual(calls[0].params, [userId, legacyId]);
  });
});

test('reading progress retries and deletes are idempotent', async (t) => {
  const userId = '20000000-0000-0000-0000-000000000001';
  const progress = { id: '30000000-0000-0000-0000-000000000001' };

  await t.test('same progress value produces no updated ledger event', async () => {
    const { repository, calls } = loadRepository('./readingProgress.repository', [
      { sql: /INSERT INTO reading_progresses/, value: result() },
      { sql: /UPDATE reading_progresses/, value: result() },
      { sql: /SELECT \* FROM reading_progresses/, value: result([progress]) },
    ]);
    const saved = await repository.upsertReadingProgress(userId, {
      book_id: 'book-1', progress: 0.5, chapter_index: '2', scroll_offset: 10, ...version,
    });
    assert.equal(saved.id, progress.id);
    assert.equal(calls.length, 3);
  });

  await t.test('delete writes one ledger tombstone', async () => {
    const { repository } = loadRepository('./readingProgress.repository', [
      { sql: /DELETE FROM reading_progresses/, value: result([progress]) },
      { sql: /INSERT INTO sync_changes/, value: result([{ user_sequence: 2 }]) },
    ]);
    assert.equal(await repository.deleteReadingProgress(userId, 'book-1', version), true);
  });
});
