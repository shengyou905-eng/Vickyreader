const { createHash } = require('node:crypto');
const httpError = require('../utils/httpError');

// Acquire the same per-user row before business locks in every ledger writer.
async function lockUploadUser(tx, userId) {
  await tx(`INSERT INTO sync_user_cursors (user_id, last_sequence) VALUES ($1, 0)
    ON CONFLICT (user_id) DO UPDATE
    SET last_sequence = sync_user_cursors.last_sequence RETURNING user_id`, [userId]);
}

async function assertBookWritable(tx, userId, bookId) {
  if (!bookId) return;
  if (typeof bookId !== 'string' || bookId.length > 200 || bookId.trim() !== bookId) {
    throw httpError(400, 'Invalid book id');
  }
  const result = await tx(`SELECT book_id FROM permanently_deleted_books
    WHERE user_id = $1 AND book_id = $2`, [userId, bookId]);
  if (result.rowCount) throw httpError(410, 'Book data was permanently deleted');
}

function validateVersion(input = {}) {
  const revision = input.client_revision;
  const writerId = input.writer_id;
  if (!Number.isSafeInteger(revision) || revision < 1
      || typeof writerId !== 'string'
      || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(writerId)) {
    throw httpError(428, 'A persistent writer_id and positive client_revision are required');
  }
  return { revision, writerId: writerId.toLowerCase() };
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])]));
  }
  return value;
}

async function beginEntryWrite(tx, userId, clientId, version, operation, payload) {
  const { revision, writerId } = validateVersion(version);
  await lockUploadUser(tx, userId);
  const found = await tx(`SELECT * FROM user_entry_upload_states
    WHERE user_id = $1 AND client_entry_id = $2`, [userId, clientId]);
  const current = found.rows[0];
  const state = compareRevision(current, { revision, writerId }, operation, payload);
  if (!state.accepted) return state;
  if (current?.book_id && payload?.book_id && current.book_id !== payload.book_id) {
    throw httpError(409, 'A client entry identity cannot move between books');
  }
  const bookId = payload?.book_id || current?.book_id || null;
  await assertBookWritable(tx, userId, bookId);
  return { ...state, bookId };
}

function compareRevision(current, { revision, writerId }, operation, payload) {
  const hash = createHash('sha256').update(JSON.stringify(stable({ operation, payload }))).digest('hex');
  if (current?.writer_id && current.writer_id !== writerId) {
    throw httpError(409, 'Entity belongs to a different upload writer; reconnect does not reset revisions');
  }
  if (current && revision < Number(current.latest_revision)) {
    throw httpError(409, 'Stale upload revision');
  }
  if (current && revision === Number(current.latest_revision)) {
    if (current.request_hash !== hash) throw httpError(409, 'Revision was reused for a different request');
    return { accepted: false, status: 'replayed' };
  }
  return { accepted: true, revision, writerId, hash };
}

async function beginProgressWrite(tx, userId, bookId, version, operation, payload) {
  const validated = validateVersion(version);
  if (typeof bookId !== 'string' || !bookId.trim() || bookId.length > 200 || bookId.trim() !== bookId) {
    throw httpError(400, 'Invalid book id');
  }
  await lockUploadUser(tx, userId);
  await assertBookWritable(tx, userId, bookId);
  const found = await tx(`SELECT * FROM reading_progress_upload_states
    WHERE user_id=$1 AND book_id=$2`, [userId, bookId]);
  return compareRevision(found.rows[0], validated, operation, payload);
}

async function finishProgressWrite(tx, userId, bookId, state, deleted) {
  await tx(`INSERT INTO reading_progress_upload_states
    (user_id, book_id, writer_id, latest_revision, deleted, request_hash)
    VALUES ($1,$2,$3,$4,$5,$6)
    ON CONFLICT (user_id, book_id) DO UPDATE SET
      writer_id=EXCLUDED.writer_id, latest_revision=EXCLUDED.latest_revision,
      deleted=EXCLUDED.deleted, request_hash=EXCLUDED.request_hash, updated_at=now()`,
  [userId, bookId, state.writerId, state.revision, deleted, state.hash]);
}

async function finishEntryWrite(tx, userId, clientId, state, deleted, bookId) {
  await tx(`INSERT INTO user_entry_upload_states
    (user_id, client_entry_id, writer_id, latest_revision, deleted, book_id, request_hash)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
    ON CONFLICT (user_id, client_entry_id) DO UPDATE SET
      writer_id = EXCLUDED.writer_id, latest_revision = EXCLUDED.latest_revision,
      deleted = EXCLUDED.deleted, book_id = EXCLUDED.book_id,
      request_hash = EXCLUDED.request_hash, updated_at = now()`,
  [userId, clientId, state.writerId, state.revision, deleted, bookId || state.bookId, state.hash]);
}

async function assertLegacyEntryWritable(tx, userId, entryId) {
  const managed = await tx(`SELECT e.id FROM user_entries e
    WHERE e.user_id=$1 AND e.id=$2 AND (
      e.client_entry_id IS NOT NULL OR NULLIF(e.metadata_json->>'local_id', '') IS NOT NULL
      OR EXISTS (SELECT 1 FROM user_entry_upload_states s
        WHERE s.user_id=e.user_id AND s.client_entry_id=e.id::text))`, [userId, entryId]);
  if (managed.rowCount) throw httpError(428, 'Use the revision-aware client entry endpoint');
}

module.exports = { lockUploadUser, assertBookWritable, validateVersion,
  beginEntryWrite, finishEntryWrite, assertLegacyEntryWritable,
  beginProgressWrite, finishProgressWrite };
