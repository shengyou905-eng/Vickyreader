const { query, withTransaction } = require('../config/db');
const httpError = require('../utils/httpError');

async function createConversation(userId, payload = {}) {
  if (Object.hasOwn(payload, 'recap_id') || payload.kind === 'book_recap') {
    throw httpError(400, 'Use the dedicated recap interface');
  }
  const kind = payload.kind === 'xiaou_asks' ? 'xiaou_asks' : 'chat';
  const title = clean(payload.title, 80);
  const bookId = clean(payload.book_id, 300) || null;
  const bookTitle = clean(payload.book_title, 300) || null;
  const result = await query(
     `INSERT INTO xiaou_conversations (
       user_id,
       kind,
       title,
       book_id,
       book_title
     )
     VALUES ($1, $2, $3, $4, $5)
     RETURNING *`,
    [userId, kind, title, bookId, bookTitle],
  );
  return result.rows[0];
}

async function listConversations(userId, filters = {}) {
  const limit = Math.min(Math.max(Number(filters.limit) || 40, 1), 100);
  const result = await query(
    `SELECT
       c.*,
       COUNT(m.id)::int AS message_count,
       (
         SELECT content
         FROM xiaou_messages latest
         WHERE latest.conversation_id = c.id AND latest.user_id = c.user_id
         ORDER BY latest.created_at DESC
         LIMIT 1
       ) AS last_message
     FROM xiaou_conversations c
     LEFT JOIN xiaou_messages m ON m.conversation_id = c.id AND m.user_id = c.user_id
     WHERE c.user_id = $1 AND c.kind <> 'book_recap'
       AND to_jsonb(c)->>'recap_id' IS NULL
     GROUP BY c.id
     ORDER BY c.updated_at DESC
     LIMIT $2`,
    [userId, limit],
  );
  return result.rows;
}

async function getConversation(userId, conversationId) {
  const conversationResult = await query(
    `SELECT *
     FROM xiaou_conversations
     WHERE id = $1 AND user_id = $2 AND kind <> 'book_recap'
       AND to_jsonb(xiaou_conversations)->>'recap_id' IS NULL`,
    [conversationId, userId],
  );
  if (conversationResult.rowCount === 0) return null;

  const messagesResult = await query(
    `SELECT id, role, content, status, created_at
     FROM xiaou_messages
     WHERE conversation_id = $1 AND user_id = $2
     ORDER BY created_at ASC`,
    [conversationId, userId],
  );
  return {
    ...conversationResult.rows[0],
    messages: messagesResult.rows,
  };
}

async function appendMessage(userId, conversationId, payload = {}) {
  const role = String(payload.role || '').trim();
  const content = clean(payload.content, 24000);
  const status = String(payload.status || 'completed').trim();

  return withTransaction(async (txQuery) => {
    const conversation = await txQuery(
      `SELECT id, title
       FROM xiaou_conversations
       WHERE id = $1 AND user_id = $2 AND kind <> 'book_recap'
         AND to_jsonb(xiaou_conversations)->>'recap_id' IS NULL
       FOR UPDATE`,
      [conversationId, userId],
    );
    if (conversation.rowCount === 0) return null;

    const inserted = await txQuery(
      `INSERT INTO xiaou_messages (
         conversation_id,
         user_id,
         role,
         content,
         status
       )
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, role, content, status, created_at`,
      [conversationId, userId, role, content, status],
    );

    const generatedTitle =
      role === 'user' && !String(conversation.rows[0].title || '').trim()
        ? titleFrom(content)
        : null;
    await txQuery(
      `UPDATE xiaou_conversations
       SET
         title = COALESCE($3, title),
         updated_at = now()
       WHERE id = $1 AND user_id = $2`,
      [conversationId, userId, generatedTitle],
    );
    return inserted.rows[0];
  });
}

async function deleteConversation(userId, conversationId) {
  const result = await query(
    `DELETE FROM xiaou_conversations
     WHERE id = $1 AND user_id = $2 AND kind <> 'book_recap'
       AND to_jsonb(xiaou_conversations)->>'recap_id' IS NULL
     RETURNING id`,
    [conversationId, userId],
  );
  return result.rowCount > 0;
}

function titleFrom(content) {
  const firstLine = String(content || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean);
  const title = firstLine || '和小U说话';
  return title.length > 36 ? `${title.slice(0, 36)}…` : title;
}

function clean(value, maxLength) {
  const text = String(value || '').trim();
  if (!maxLength || text.length <= maxLength) return text;
  return text.slice(0, maxLength);
}

module.exports = {
  createConversation,
  listConversations,
  getConversation,
  appendMessage,
  deleteConversation,
};
