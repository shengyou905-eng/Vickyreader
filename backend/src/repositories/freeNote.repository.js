const { query } = require('../config/db');

function normalizeDate(value) {
  const text = String(value || '').trim();
  if (!text) return null;
  const time = new Date(text);
  return Number.isNaN(time.getTime()) ? null : time.toISOString();
}

function normalizeId(value) {
  return String(value || '').trim();
}

async function upsertFreeNote(userId, payload) {
  const id = normalizeId(payload.id);
  const content = String(payload.content || '').trim();
  const createdAt = normalizeDate(payload.created_at);
  const updatedAt = normalizeDate(payload.updated_at);

  const result = await query(
    `INSERT INTO free_notes (
       id,
       user_id,
       content,
       created_at,
       updated_at
     )
     VALUES (
       $1,
       $2,
       $3,
       COALESCE($4::timestamptz, now()),
       COALESCE($5::timestamptz, now())
     )
     ON CONFLICT (user_id, id) DO UPDATE SET
       content = EXCLUDED.content,
       updated_at = EXCLUDED.updated_at
     RETURNING *`,
    [id, userId, content, createdAt, updatedAt],
  );

  return result.rows[0];
}

async function listFreeNotes(userId, filters = {}) {
  const where = ['user_id = $1'];
  const values = [userId];

  const search = String(filters.query || '').trim();
  if (search) {
    values.push(`%${search}%`);
    where.push(`content ILIKE $${values.length}`);
  }

  const limit = Math.min(Math.max(Number(filters.limit) || 500, 1), 1000);
  values.push(limit);

  const result = await query(
    `SELECT *
     FROM free_notes
     WHERE ${where.join(' AND ')}
     ORDER BY updated_at DESC, created_at DESC
     LIMIT $${values.length}`,
    values,
  );

  return result.rows;
}

async function deleteFreeNote(userId, id) {
  const result = await query(
    `DELETE FROM free_notes
     WHERE user_id = $1 AND id = $2
     RETURNING id`,
    [userId, normalizeId(id)],
  );

  return result.rowCount > 0;
}

module.exports = {
  upsertFreeNote,
  listFreeNotes,
  deleteFreeNote,
};
