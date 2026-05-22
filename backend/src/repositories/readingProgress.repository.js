const { query } = require('../config/db');

async function upsertReadingProgress(userId, payload) {
  const result = await query(
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
     ON CONFLICT (user_id, book_id)
     DO UPDATE SET
       progress = EXCLUDED.progress,
       chapter_index = EXCLUDED.chapter_index,
       scroll_offset = EXCLUDED.scroll_offset,
       cfi = EXCLUDED.cfi,
       updated_at = now()
     RETURNING *`,
    [
      userId,
      payload.book_id,
      Number(payload.progress) || 0,
      String(payload.chapter_index ?? '0'),
      Number(payload.scroll_offset) || 0,
      payload.cfi || null,
    ],
  );

  return result.rows[0];
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
};
