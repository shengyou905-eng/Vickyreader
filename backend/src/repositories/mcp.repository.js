const { query, withTransaction } = require('../config/db');

const MAX_SYNC_BOOKS = 200;
const MAX_PAGE_SIZE = 50;
const DEFAULT_PAGE_SIZE = 20;

function normalizeText(value, maxLength = 500) {
  return String(value || '').trim().slice(0, maxLength);
}

function normalizeDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function encodeCursor(offset) {
  return Buffer.from(JSON.stringify({ offset }), 'utf8').toString('base64url');
}

function decodeCursor(cursor) {
  if (!cursor) return 0;
  try {
    const parsed = JSON.parse(Buffer.from(String(cursor), 'base64url').toString('utf8'));
    const offset = Number(parsed.offset);
    if (!Number.isInteger(offset) || offset < 0 || offset > 10000) return 0;
    return offset;
  } catch (_) {
    return 0;
  }
}

function normalizeLimit(value) {
  const candidate = Number(value);
  if (!Number.isFinite(candidate)) return DEFAULT_PAGE_SIZE;
  return Math.min(Math.max(Math.floor(candidate), 1), MAX_PAGE_SIZE);
}

function toLibraryBook(row) {
  return {
    book_id: row.book_id,
    title: row.title,
    author: row.author || '',
    format: row.format || '',
    added_at: row.added_at,
    last_opened_at: row.last_opened_at,
    reading_progress: Number(row.reading_progress || 0),
    reading_updated_at: row.reading_updated_at || null,
  };
}

function toTrace(row) {
  return {
    id: row.id,
    type: row.source,
    book_id: row.book_id || '',
    book_title: row.book_title || '',
    chapter_index: row.chapter_index || '',
    chapter_title: row.chapter_title || '',
    excerpt: row.original_text || '',
    note: row.user_input || '',
    explanation: row.ai_explanation || '',
    tags: Array.isArray(row.auto_tags) ? row.auto_tags : [],
    is_important: row.is_important === true,
    created_at: row.created_at,
  };
}

async function syncLibraryBooks(userId, books, { replace = false } = {}) {
  const normalized = (Array.isArray(books) ? books : [])
    .slice(0, MAX_SYNC_BOOKS)
    .map((book) => ({
      bookId: normalizeText(book?.book_id, 200),
      title: normalizeText(book?.title, 500),
      author: normalizeText(book?.author, 300),
      format: normalizeText(book?.format, 32).toLowerCase(),
      addedAt: normalizeDate(book?.added_at),
      lastOpenedAt: normalizeDate(book?.last_opened_at),
    }))
    .filter((book) => book.bookId && book.title);

  await withTransaction(async (txQuery) => {
    if (replace) {
      if (normalized.length === 0) {
        await txQuery('DELETE FROM user_library_books WHERE user_id = $1', [userId]);
      } else {
        await txQuery(
          `DELETE FROM user_library_books
           WHERE user_id = $1 AND NOT (book_id = ANY($2::text[]))`,
          [userId, normalized.map((book) => book.bookId)],
        );
      }
    }

    for (const book of normalized) {
      await txQuery(
        `INSERT INTO user_library_books (
           user_id, book_id, title, author, format, added_at, last_opened_at, synced_at, updated_at
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, now(), now())
         ON CONFLICT (user_id, book_id) DO UPDATE SET
           title = EXCLUDED.title,
           author = EXCLUDED.author,
           format = EXCLUDED.format,
           added_at = EXCLUDED.added_at,
           last_opened_at = EXCLUDED.last_opened_at,
           synced_at = now(),
           updated_at = now()`,
        [
          userId,
          book.bookId,
          book.title,
          book.author,
          book.format,
          book.addedAt,
          book.lastOpenedAt,
        ],
      );
    }
  });
  return normalized.length;
}

async function deleteLibraryBook(userId, bookId) {
  const result = await query(
    `DELETE FROM user_library_books WHERE user_id = $1 AND book_id = $2`,
    [userId, bookId],
  );
  return result.rowCount > 0;
}

async function listLibraryBooks(userId, { queryText = '', cursor, limit } = {}) {
  const text = normalizeText(queryText, 200);
  const pageSize = normalizeLimit(limit);
  const offset = decodeCursor(cursor);
  const pattern = `%${text.replace(/[\\%_]/g, '\\$&')}%`;
  const result = await query(
    `SELECT b.book_id, b.title, b.author, b.format, b.added_at, b.last_opened_at,
            COALESCE(p.progress, 0) AS reading_progress,
            p.updated_at AS reading_updated_at
     FROM user_library_books b
     LEFT JOIN reading_progresses p
       ON p.user_id = b.user_id AND p.book_id = b.book_id
     WHERE b.user_id = $1
       AND ($2 = '' OR b.title ILIKE $3 ESCAPE '\\' OR b.author ILIKE $3 ESCAPE '\\')
     ORDER BY b.last_opened_at DESC NULLS LAST, b.added_at DESC NULLS LAST, b.book_id ASC
     LIMIT $4 OFFSET $5`,
    [userId, text, pattern, pageSize + 1, offset],
  );
  const hasMore = result.rows.length > pageSize;
  const rows = result.rows.slice(0, pageSize);
  return {
    items: rows.map(toLibraryBook),
    next_cursor: hasMore ? encodeCursor(offset + pageSize) : null,
  };
}

async function listTraces(userId, {
  bookId,
  queryText = '',
  tag = '',
  type = '',
  cursor,
  limit,
} = {}) {
  const pageSize = normalizeLimit(limit);
  const offset = decodeCursor(cursor);
  const text = normalizeText(queryText, 300);
  const safeBookId = normalizeText(bookId, 200);
  const safeTag = normalizeText(tag, 120);
  const safeType = normalizeText(type, 64);
  const pattern = `%${text.replace(/[\\%_]/g, '\\$&')}%`;
  const result = await query(
    `SELECT id, source, book_id, book_title, chapter_index, chapter_title,
            original_text, user_input, ai_explanation, auto_tags, is_important, created_at
     FROM user_entries
     WHERE user_id = $1
       AND ($2 = '' OR book_id = $2)
       AND ($3 = '' OR source = $3)
       AND ($4 = '' OR $4 = ANY(auto_tags))
       AND ($5 = '' OR original_text ILIKE $6 ESCAPE '\\'
            OR user_input ILIKE $6 ESCAPE '\\'
            OR ai_explanation ILIKE $6 ESCAPE '\\'
            OR EXISTS (
              SELECT 1 FROM unnest(auto_tags) AS trace_tag
              WHERE trace_tag ILIKE $6 ESCAPE '\\'
            ))
     ORDER BY created_at DESC, id DESC
     LIMIT $7 OFFSET $8`,
    [userId, safeBookId, safeType, safeTag, text, pattern, pageSize + 1, offset],
  );
  const hasMore = result.rows.length > pageSize;
  const rows = result.rows.slice(0, pageSize);
  return {
    items: rows.map(toTrace),
    next_cursor: hasMore ? encodeCursor(offset + pageSize) : null,
  };
}

async function getTraceById(userId, traceId) {
  const result = await query(
    `SELECT id, source, book_id, book_title, chapter_index, chapter_title,
            original_text, user_input, ai_explanation, auto_tags, is_important, created_at
     FROM user_entries
     WHERE id = $1 AND user_id = $2`,
    [traceId, userId],
  );
  return result.rows[0] ? toTrace(result.rows[0]) : null;
}

async function createMcpAccessToken(userId, {
  tokenHash,
  tokenPrefix,
  label,
  expiresAt,
}) {
  return withTransaction(async (txQuery) => {
    await txQuery(
      `UPDATE mcp_access_tokens
       SET revoked_at = now()
       WHERE user_id = $1 AND revoked_at IS NULL`,
      [userId],
    );
    const result = await txQuery(
      `INSERT INTO mcp_access_tokens (
         user_id, token_hash, token_prefix, label, expires_at
       ) VALUES ($1, $2, $3, $4, $5)
       RETURNING id, token_prefix, label, expires_at, created_at`,
      [userId, tokenHash, tokenPrefix, label, expiresAt],
    );
    return result.rows[0];
  });
}

async function getActiveMcpTokenForUser(userId) {
  const result = await query(
    `SELECT id, token_prefix, label, expires_at, last_used_at, created_at
     FROM mcp_access_tokens
     WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > now()
     ORDER BY created_at DESC
     LIMIT 1`,
    [userId],
  );
  return result.rows[0] || null;
}

async function revokeMcpTokensForUser(userId) {
  const result = await query(
    `UPDATE mcp_access_tokens
     SET revoked_at = now()
     WHERE user_id = $1 AND revoked_at IS NULL`,
    [userId],
  );
  return result.rowCount;
}

async function findActiveMcpTokenByHash(tokenHash) {
  const result = await query(
    `SELECT t.id, t.user_id, t.expires_at, u.account_status
     FROM mcp_access_tokens t
     INNER JOIN users u ON u.id = t.user_id
     WHERE t.token_hash = $1 AND t.revoked_at IS NULL AND t.expires_at > now()
     LIMIT 1`,
    [tokenHash],
  );
  return result.rows[0] || null;
}

async function touchMcpAccessToken(tokenId) {
  await query(
    `UPDATE mcp_access_tokens SET last_used_at = now() WHERE id = $1`,
    [tokenId],
  );
}

module.exports = {
  MAX_SYNC_BOOKS,
  DEFAULT_PAGE_SIZE,
  MAX_PAGE_SIZE,
  encodeCursor,
  decodeCursor,
  normalizeLimit,
  syncLibraryBooks,
  deleteLibraryBook,
  listLibraryBooks,
  listTraces,
  getTraceById,
  createMcpAccessToken,
  getActiveMcpTokenForUser,
  revokeMcpTokensForUser,
  findActiveMcpTokenByHash,
  touchMcpAccessToken,
};
