const mcpRepository = require('../repositories/mcp.repository');
const httpError = require('../utils/httpError');

function normalizeBookPayload(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const bookId = String(raw.book_id || '').trim();
  const title = String(raw.title || '').trim();
  if (!bookId || !title) return null;
  return {
    book_id: bookId,
    title,
    author: String(raw.author || '').trim(),
    format: String(raw.format || '').trim(),
    added_at: raw.added_at || null,
    last_opened_at: raw.last_opened_at || null,
  };
}

async function syncLibraryBooks(req, res, next) {
  try {
    const rawBooks = Array.isArray(req.body?.books) ? req.body.books : [];
    if (rawBooks.length > mcpRepository.MAX_SYNC_BOOKS) {
      throw httpError(400, `A maximum of ${mcpRepository.MAX_SYNC_BOOKS} books may be synced at once`);
    }
    const books = rawBooks.map(normalizeBookPayload).filter(Boolean);
    if (books.length !== rawBooks.length) {
      throw httpError(400, 'Each book requires book_id and title');
    }
    const replace = req.body?.replace === true;
    const synced = await mcpRepository.syncLibraryBooks(req.user.id, books, { replace });
    return res.json({ synced });
  } catch (error) {
    return next(error);
  }
}

async function deleteLibraryBook(req, res, next) {
  try {
    const bookId = String(req.params.bookId || '').trim();
    if (!bookId) throw httpError(400, 'book_id is required');
    await mcpRepository.deleteLibraryBook(req.user.id, bookId);
    return res.status(204).send();
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  syncLibraryBooks,
  deleteLibraryBook,
};
