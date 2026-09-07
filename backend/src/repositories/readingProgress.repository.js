const { query, withTransaction } = require('../config/db');
const { appendSyncChange } = require('./syncChange.repository');
const { beginProgressWrite, finishProgressWrite } = require('./uploadState.repository');

async function upsertReadingProgress(userId, payload) {
  return withTransaction(async (txQuery) => {
    const values = [
      userId,
      payload.book_id,
      Number(payload.progress) || 0,
      String(payload.chapter_index ?? '0'),
      Number(payload.scroll_offset) || 0,
      payload.cfi || null,
    ];
    const state = await beginProgressWrite(txQuery, userId, payload.book_id, payload, 'upsert', values.slice(2));
    if (!state.accepted) {
      return (await txQuery(`SELECT * FROM reading_progresses
        WHERE user_id=$1 AND book_id=$2`, [userId, payload.book_id])).rows[0] || null;
    }
    const inserted = await txQuery(
      `INSERT INTO reading_progresses (
         user_id,
         book_id,
         progress,
         chapter_index,
         scroll_offset,
         cfi,
         updated_at
       )
       VALUES ($1, $2, $3, $4, $5, $6, now())
       ON CONFLICT (user_id, book_id) DO NOTHING
       RETURNING *`,
      values,
    );

    let operation = inserted.rowCount > 0 ? 'created' : null;
    const result = inserted.rowCount > 0
      ? inserted
      : await txQuery(
        `UPDATE reading_progresses
         SET progress = $3,
             chapter_index = $4,
             scroll_offset = $5,
             cfi = $6,
             updated_at = now()
         WHERE user_id = $1 AND book_id = $2
           AND (
             progress IS DISTINCT FROM $3 OR
             chapter_index IS DISTINCT FROM $4 OR
             scroll_offset IS DISTINCT FROM $5 OR
             cfi IS DISTINCT FROM $6
           )
         RETURNING *`,
        values,
      );
    if (result.rowCount > 0 && !operation) operation = 'updated';
    const readingProgress = result.rows[0] || (await txQuery(
      `SELECT * FROM reading_progresses
       WHERE user_id = $1 AND book_id = $2`,
      [userId, payload.book_id],
    )).rows[0];
    if (operation) {
      await appendSyncChange(txQuery, {
        userId,
        entityType: 'reading_progress',
        entityId: readingProgress.id,
        operation,
      });
    }
    await finishProgressWrite(txQuery, userId, payload.book_id, state, false);
    return readingProgress;
  });
}

async function deleteReadingProgress(userId, bookId, version) {
  return withTransaction(async (txQuery) => {
    const state = await beginProgressWrite(txQuery, userId, bookId, version, 'delete', null);
    if (!state.accepted) return false;
    const result = await txQuery(
      `DELETE FROM reading_progresses
       WHERE user_id = $1 AND book_id = $2
       RETURNING id`,
      [userId, bookId],
    );
    if (result.rowCount > 0) await appendSyncChange(txQuery, {
      userId,
      entityType: 'reading_progress',
      entityId: result.rows[0].id,
      operation: 'deleted',
    });
    await finishProgressWrite(txQuery, userId, bookId, state, true);
    return result.rowCount > 0;
  });
}

async function getReadingProgress(userId, bookId) {
  const result = await query(
    `SELECT *
     FROM reading_progresses
     WHERE user_id = $1 AND book_id = $2
     LIMIT 1`,
    [userId, bookId],
  );

  return result.rows[0] || null;
}

module.exports = {
  upsertReadingProgress,
  getReadingProgress,
  deleteReadingProgress,
};
