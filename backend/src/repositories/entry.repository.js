const { query, withTransaction } = require('../config/db');
const { appendSyncChange } = require('./syncChange.repository');
const { lockUploadUser, assertBookWritable, beginEntryWrite, finishEntryWrite,
  assertLegacyEntryWritable } = require('./uploadState.repository');
const httpError = require('../utils/httpError');

const allowedSources = new Set([
  'highlight',
  'thought',
  'ai_explanation',
  'ai_question',
  'manual',
]);

function normalizeTags(tags) {
  if (Array.isArray(tags)) {
    return [...new Set(tags.map((tag) => String(tag).trim()).filter(Boolean))];
  }

  if (typeof tags === 'string' && tags.trim()) {
    return [...new Set(tags.split(',').map((tag) => tag.trim()).filter(Boolean))];
  }

  return [];
}

function normalizeMetadata(metadata) {
  if (!metadata) return {};
  if (typeof metadata === 'object' && !Array.isArray(metadata)) return metadata;
  if (typeof metadata === 'string') {
    try {
      const parsed = JSON.parse(metadata);
      return typeof parsed === 'object' && parsed && !Array.isArray(parsed)
        ? parsed
        : {};
    } catch (_) {
      return {};
    }
  }
  return {};
}

async function createEntry(userId, payload) {
  const source = allowedSources.has(payload.source) ? payload.source : null;
  const tags = normalizeTags(payload.auto_tags);
  const metadata = normalizeMetadata(payload.metadata_json);
  if (metadata.local_id) throw httpError(428, 'Use the revision-aware client entry endpoint');

  return withTransaction(async (txQuery) => {
    await lockUploadUser(txQuery, userId);
    await assertBookWritable(txQuery, userId, payload.book_id);
    const result = await txQuery(
      `INSERT INTO user_entries (
         user_id,
         source,
         book_id,
         book_title,
         chapter_index,
         chapter_title,
         original_text,
         user_input,
         ai_explanation,
         auto_tags,
         auto_summary,
         metadata_json
       )
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
       RETURNING *`,
      [
        userId,
        source,
        payload.book_id || null,
        payload.book_title || null,
        payload.chapter_index || null,
        payload.chapter_title || null,
        payload.original_text || null,
        payload.user_input || null,
        payload.ai_explanation || null,
        tags,
        payload.auto_summary || null,
        metadata,
      ],
    );
    const entry = result.rows[0];
    await appendSyncChange(txQuery, {
      userId,
      entityType: 'trace',
      entityId: entry.id,
      operation: 'created',
    });
    return entry;
  });
}

async function upsertEntryByClientId(userId, clientEntryId, payload, version = payload) {
  const source = allowedSources.has(payload.source) ? payload.source : null;
  const tags = normalizeTags(payload.auto_tags);
  const metadata = normalizeMetadata(payload.metadata_json);
  metadata.local_id = clientEntryId;
  const values = [
    userId, clientEntryId, source, payload.book_id || null,
    payload.book_title || null, payload.chapter_index || null,
    payload.chapter_title || null, payload.original_text || null,
    payload.user_input || null, payload.ai_explanation || null, tags,
    payload.auto_summary || null, metadata, payload.is_important === true,
    payload.created_at || null,
  ];

  return withTransaction(async (txQuery) => {
    const state = await beginEntryWrite(txQuery, userId, clientEntryId,
      version, 'upsert', { values: values.slice(2), book_id: payload.book_id || null });
    // The immutable book association is also checked for migrated legacy rows.
    const existing = await txQuery(`SELECT * FROM user_entries
      WHERE user_id = $1 AND client_entry_id = $2`, [userId, clientEntryId]);
    if (!state.accepted) return { entry: existing.rows[0] || null, operation: null, upload_status: state.status };
    if (existing.rows[0]?.book_id && existing.rows[0].book_id !== (payload.book_id || null)) {
      throw httpError(409, 'A client entry identity cannot move between books');
    }
    await assertBookWritable(txQuery, userId, payload.book_id);
    const inserted = await txQuery(
      `INSERT INTO user_entries (
         user_id, client_entry_id, source, book_id, book_title,
         chapter_index, chapter_title, original_text, user_input,
         ai_explanation, auto_tags, auto_summary, metadata_json,
         is_important, created_at, updated_at
       ) VALUES (
         $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
         $14, COALESCE($15::timestamptz, now()), now()
       )
       ON CONFLICT (user_id, client_entry_id) DO NOTHING
       RETURNING *`,
      values,
    );
    let operation = inserted.rowCount > 0 ? 'created' : null;
    let result = inserted;
    if (inserted.rowCount === 0) {
      result = await txQuery(
        `UPDATE user_entries
         SET source = $3, book_id = $4, book_title = $5,
             chapter_index = $6, chapter_title = $7, original_text = $8,
             user_input = $9, ai_explanation = $10, auto_tags = $11,
             auto_summary = $12, metadata_json = $13, is_important = $14,
             updated_at = now()
         WHERE user_id = $1 AND client_entry_id = $2
           AND (
             source IS DISTINCT FROM $3 OR book_id IS DISTINCT FROM $4 OR
             book_title IS DISTINCT FROM $5 OR chapter_index IS DISTINCT FROM $6 OR
             chapter_title IS DISTINCT FROM $7 OR original_text IS DISTINCT FROM $8 OR
             user_input IS DISTINCT FROM $9 OR ai_explanation IS DISTINCT FROM $10 OR
             auto_tags IS DISTINCT FROM $11 OR auto_summary IS DISTINCT FROM $12 OR
             metadata_json IS DISTINCT FROM $13 OR is_important IS DISTINCT FROM $14
           )
         RETURNING *`,
        values.slice(0, 14),
      );
      if (result.rowCount > 0) operation = 'updated';
    }
    if (result.rowCount === 0) {
      result = await txQuery(
        `SELECT * FROM user_entries
         WHERE user_id = $1 AND client_entry_id = $2`,
        [userId, clientEntryId],
      );
    }
    const entry = result.rows[0] || null;
    if (entry && operation) {
      await appendSyncChange(txQuery, {
        userId, entityType: 'trace', entityId: entry.id, operation,
      });
    }
    await finishEntryWrite(txQuery, userId, clientEntryId, state, false, payload.book_id);
    return { entry, operation, upload_status: 'accepted' };
  });
}

async function deleteEntryByClientId(userId, clientEntryId, version) {
  return withTransaction(async (txQuery) => {
    const state = await beginEntryWrite(txQuery, userId, clientEntryId, version, 'delete', null);
    if (!state.accepted) return false;
    const result = await txQuery(
      `DELETE FROM user_entries
       WHERE user_id = $1
         AND (
           client_entry_id = $2
           OR (client_entry_id IS NULL AND id::text = $2)
         )
       RETURNING id, book_id`,
      [userId, clientEntryId],
    );
    await finishEntryWrite(txQuery, userId, clientEntryId, state, true, result.rows[0]?.book_id);
    if (result.rowCount === 0) return false;
    await appendSyncChange(txQuery, {
      userId, entityType: 'trace', entityId: result.rows[0].id,
      operation: 'deleted',
    });
    return true;
  });
}

async function listEntries(userId, filters) {
  const where = ['user_id = $1'];
  const values = [userId];

  if (filters.book_id) {
    values.push(filters.book_id);
    where.push(`book_id = $${values.length}`);
  }

  if (filters.source) {
    values.push(filters.source);
    where.push(`source = $${values.length}`);
  }

  if (filters.tag) {
    values.push(filters.tag);
    where.push(`$${values.length} = ANY(auto_tags)`);
  }

  if (filters.created_at_from) {
    values.push(filters.created_at_from);
    where.push(`created_at >= $${values.length}`);
  }

  if (filters.created_at_to) {
    values.push(filters.created_at_to);
    where.push(`created_at <= $${values.length}`);
  }

  if (filters.created_at) {
    values.push(`${filters.created_at}%`);
    where.push(`created_at::text LIKE $${values.length}`);
  }

  const limit = Math.min(Math.max(Number(filters.limit) || 100, 1), 500);
  values.push(limit);

  const result = await query(
    `SELECT e.*,
            COALESCE(f.follow_up_count, 0)::INTEGER AS follow_up_count,
            COALESCE(f.latest_follow_up_question, '') AS latest_follow_up_question
     FROM user_entries e
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::INTEGER AS follow_up_count,
              (ARRAY_AGG(question ORDER BY created_at DESC))[1]
                AS latest_follow_up_question
       FROM user_entry_follow_ups
       WHERE entry_id = e.id AND user_id = e.user_id
     ) f ON TRUE
     WHERE ${where.join(' AND ')}
     ORDER BY e.created_at DESC
     LIMIT $${values.length}`,
    values,
  );

  return result.rows;
}

async function deleteEntry(userId, entryId) {
  return withTransaction(async (txQuery) => {
    await lockUploadUser(txQuery, userId);
    await assertLegacyEntryWritable(txQuery, userId, entryId);
    const result = await txQuery(
      `DELETE FROM user_entries
       WHERE id = $1 AND user_id = $2
       RETURNING id`,
      [entryId, userId],
    );
    if (result.rowCount === 0) return false;

    await appendSyncChange(txQuery, {
      userId,
      entityType: 'trace',
      entityId: result.rows[0].id,
      operation: 'deleted',
    });
    return true;
  });
}

async function updateEntryImportance(userId, entryId, isImportant) {
  return withTransaction(async (txQuery) => {
    await lockUploadUser(txQuery, userId);
    await assertLegacyEntryWritable(txQuery, userId, entryId);
    const result = await txQuery(
      `UPDATE user_entries
       SET is_important = $3,
           updated_at = now()
       WHERE id = $1 AND user_id = $2
         AND is_important IS DISTINCT FROM $3
       RETURNING *`,
      [entryId, userId, isImportant],
    );

    if (result.rowCount > 0) {
      const entry = result.rows[0];
      await appendSyncChange(txQuery, {
        userId,
        entityType: 'trace',
        entityId: entry.id,
        operation: 'updated',
      });
      return entry;
    }

    const existing = await txQuery(
      `SELECT * FROM user_entries
       WHERE id = $1 AND user_id = $2`,
      [entryId, userId],
    );
    return existing.rows[0] || null;
  });
}

async function listFollowUps(userId, entryId) {
  const result = await query(
    `SELECT f.id, f.entry_id, f.question, f.answer, f.created_at
     FROM user_entry_follow_ups f
     INNER JOIN user_entries e ON e.id = f.entry_id
     WHERE f.entry_id = $1 AND f.user_id = $2 AND e.user_id = $2
     ORDER BY f.created_at ASC`,
    [entryId, userId],
  );
  return result.rows;
}

async function createFollowUp(userId, entryId, question, answer) {
  return withTransaction(async (txQuery) => {
    const owned = await txQuery(
      `SELECT id
       FROM user_entries
       WHERE id = $1 AND user_id = $2
       FOR UPDATE`,
      [entryId, userId],
    );
    if (owned.rowCount === 0) return null;

    const result = await txQuery(
      `INSERT INTO user_entry_follow_ups (
         entry_id,
         user_id,
         question,
         answer
       )
       VALUES ($1, $2, $3, $4)
       RETURNING id, entry_id, question, answer, created_at`,
      [entryId, userId, question, answer],
    );
    return result.rows[0];
  });
}

module.exports = {
  createEntry,
  upsertEntryByClientId,
  deleteEntryByClientId,
  listEntries,
  deleteEntry,
  updateEntryImportance,
  listFollowUps,
  createFollowUp,
  normalizeTags,
};
