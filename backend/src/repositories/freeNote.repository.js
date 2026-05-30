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
  const title = String(payload.title || '').trim();
  const content = String(payload.content || '').trim();
  const createdAt = normalizeDate(payload.created_at);
  const updatedAt = normalizeDate(payload.updated_at);

  const result = await query(
    `INSERT INTO free_notes (
       id,
       user_id,
       title,
       content,
       created_at,
       updated_at
     )
     VALUES (
       $1,
       $2,
       $3,
       $4,
       COALESCE($5::timestamptz, now()),
       COALESCE($6::timestamptz, now())
     )
     ON CONFLICT (user_id, id) DO UPDATE SET
       title = EXCLUDED.title,
       content = EXCLUDED.content,
       updated_at = EXCLUDED.updated_at
     RETURNING *`,
    [id, userId, title, content, createdAt, updatedAt],
  );

  const authorization = await query(
    `SELECT EXISTS (
       SELECT 1
       FROM xiaou_free_note_grants
       WHERE user_id = $1 AND free_note_id = $2
     ) AS xiaou_authorized`,
    [userId, id],
  );
  return withAuthorization(
    result.rows[0],
    authorization.rows[0]?.xiaou_authorized === true,
  );
}

async function listFreeNotes(userId, filters = {}) {
  const where = ['n.user_id = $1'];
  const values = [userId];

  const search = String(filters.query || '').trim();
  if (search) {
    values.push(`%${search}%`);
    where.push(`(n.title ILIKE $${values.length} OR n.content ILIKE $${values.length})`);
  }

  const limit = Math.min(Math.max(Number(filters.limit) || 500, 1), 1000);
  values.push(limit);

  const result = await query(
    `SELECT
       n.*,
       (g.free_note_id IS NOT NULL) AS xiaou_authorized
     FROM free_notes n
     LEFT JOIN xiaou_free_note_grants g
       ON g.user_id = n.user_id AND g.free_note_id = n.id
     WHERE ${where.join(' AND ')}
     ORDER BY n.updated_at DESC, n.created_at DESC
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

async function authorizeForXiaou(userId, id) {
  const result = await query(
    `INSERT INTO xiaou_free_note_grants (user_id, free_note_id)
     SELECT user_id, id
     FROM free_notes
     WHERE user_id = $1 AND id = $2
     ON CONFLICT (user_id, free_note_id) DO UPDATE SET
       granted_at = now()
     RETURNING free_note_id`,
    [userId, normalizeId(id)],
  );
  return result.rowCount > 0;
}

async function revokeXiaouAuthorization(userId, id) {
  const result = await query(
    `DELETE FROM xiaou_free_note_grants
     WHERE user_id = $1 AND free_note_id = $2
     RETURNING free_note_id`,
    [userId, normalizeId(id)],
  );
  return result.rowCount > 0;
}

async function listAuthorizedForXiaou(userId, { limit = 100 } = {}) {
  const safeLimit = Math.min(Math.max(Number(limit) || 100, 1), 200);
  const result = await query(
    `SELECT n.id, n.title, n.content, n.created_at, n.updated_at, g.granted_at
     FROM xiaou_free_note_grants g
     INNER JOIN free_notes n
       ON n.user_id = g.user_id AND n.id = g.free_note_id
     WHERE g.user_id = $1
     ORDER BY g.granted_at DESC
     LIMIT $2`,
    [userId, safeLimit],
  );
  return result.rows;
}

function withAuthorization(note, authorized) {
  return {
    ...note,
    xiaou_authorized: authorized,
  };
}

module.exports = {
  upsertFreeNote,
  listFreeNotes,
  deleteFreeNote,
  authorizeForXiaou,
  revokeXiaouAuthorization,
  listAuthorizedForXiaou,
};
