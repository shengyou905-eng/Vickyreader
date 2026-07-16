const { query, withTransaction } = require('../config/db');

const allowedSources = new Set(['highlight', 'thought', 'ai_explanation', 'manual']);

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

  const result = await query(
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

  return result.rows[0];
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
  const result = await query(
    `DELETE FROM user_entries
     WHERE id = $1 AND user_id = $2
     RETURNING id`,
    [entryId, userId],
  );

  return result.rowCount > 0;
}

async function updateEntryImportance(userId, entryId, isImportant) {
  const result = await query(
    `UPDATE user_entries
     SET is_important = $3
     WHERE id = $1 AND user_id = $2
     RETURNING *`,
    [entryId, userId, isImportant],
  );

  return result.rows[0] || null;
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
  listEntries,
  deleteEntry,
  updateEntryImportance,
  listFollowUps,
  createFollowUp,
  normalizeTags,
};
