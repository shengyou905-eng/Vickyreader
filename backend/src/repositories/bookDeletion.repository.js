const { withTransaction } = require('../config/db');
const { appendSyncChange } = require('./syncChange.repository');
const { lockUploadUser } = require('./uploadState.repository');
const httpError = require('../utils/httpError');

async function permanentlyDeleteBookData(userId, bookId) {
  if (typeof bookId !== 'string' || !bookId.trim() || bookId.length > 200) {
    throw httpError(400, 'Invalid book id');
  }
  return withTransaction(async tx => {
    await lockUploadUser(tx, userId);
    await tx(`INSERT INTO permanently_deleted_books (user_id, book_id)
      VALUES ($1, $2) ON CONFLICT (user_id, book_id) DO NOTHING`, [userId, bookId]);
    // Retain version fences, not personal reading text. FK cascades remove
    // canonical entry follow-ups; separate private chats are not touched.
    await tx(`UPDATE user_entry_upload_states SET deleted=true, updated_at=now()
      WHERE user_id=$1 AND book_id=$2 AND deleted=false`, [userId, bookId]);
    await tx(`UPDATE reading_progress_upload_states SET deleted=true, updated_at=now()
      WHERE user_id=$1 AND book_id=$2 AND deleted=false`, [userId, bookId]);
    const traces = await tx(`DELETE FROM user_entries WHERE user_id=$1 AND book_id=$2 RETURNING id`, [userId, bookId]);
    const progress = await tx(`DELETE FROM reading_progresses WHERE user_id=$1 AND book_id=$2 RETURNING id`, [userId, bookId]);
    const books = await tx(`DELETE FROM user_library_books WHERE user_id=$1 AND book_id=$2 RETURNING book_id`, [userId, bookId]);
    for (const [entityType, result, key] of [
      ['trace', traces, 'id'], ['reading_progress', progress, 'id'], ['book', books, 'book_id'],
    ]) {
      for (const row of result.rows) {
        await appendSyncChange(tx, { userId, entityType, entityId: row[key], operation: 'deleted' });
      }
    }
    return { traces: traces.rowCount, progresses: progress.rowCount, books: books.rowCount };
  });
}

module.exports = { permanentlyDeleteBookData };
