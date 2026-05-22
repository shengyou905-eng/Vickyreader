const mingtaiRepository = require('../repositories/mingtai.repository');
const httpError = require('../utils/httpError');

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const allowedCopyrightStatuses = new Set(['public_domain', 'original', 'authorized']);

function normalizeEntryIds(body) {
  const raw = Array.isArray(body.entry_ids)
    ? body.entry_ids
    : body.entry_id
      ? [body.entry_id]
      : [];

  return [...new Set(raw.map((id) => String(id).trim()).filter(Boolean))];
}

function assertUuid(id, label) {
  if (!uuidPattern.test(String(id))) {
    throw httpError(400, `Invalid ${label}`);
  }
}

function validateEntryIds(entryIds) {
  const invalidId = entryIds.find((id) => !uuidPattern.test(id));
  if (invalidId) {
    throw httpError(400, `Invalid entry id: ${invalidId}`);
  }
}

async function publish(req, res, next) {
  try {
    const entryIds = normalizeEntryIds(req.body);
    if (entryIds.length === 0) {
      throw httpError(400, 'entry_ids is required');
    }
    validateEntryIds(entryIds);

    const annotations = await mingtaiRepository.publishEntries(req.user.id, entryIds);
    if (annotations.length === 0) {
      throw httpError(404, 'No owned entries found to publish');
    }

    return res.status(201).json({
      annotations,
      count: annotations.length,
    });
  } catch (error) {
    return next(error);
  }
}

async function publishBook(req, res, next) {
  try {
    const sourceBookId = String(req.body.source_book_id || req.body.book_id || '').trim();
    const title = String(req.body.title || '').trim();
    const copyrightStatus = String(req.body.copyright_status || '').trim();
    const entryIds = normalizeEntryIds(req.body);

    if (!sourceBookId) throw httpError(400, 'source_book_id is required');
    if (!title) throw httpError(400, 'title is required');
    if (!allowedCopyrightStatuses.has(copyrightStatus)) {
      throw httpError(400, 'Invalid copyright_status');
    }
    validateEntryIds(entryIds);

    const result = await mingtaiRepository.publishBook(req.user.id, {
      source_book_id: sourceBookId,
      title,
      author: req.body.author,
      cover_url: req.body.cover_url,
      description: req.body.description,
      copyright_status: copyrightStatus,
      metadata_json: req.body.metadata_json,
      entry_ids: entryIds,
    });

    return res.status(201).json(result);
  } catch (error) {
    return next(error);
  }
}

async function listBooks(req, res, next) {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
    const books = await mingtaiRepository.listBooks({ limit });
    return res.json({ books });
  } catch (error) {
    return next(error);
  }
}

async function getBook(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    const detail = await mingtaiRepository.getBook(req.params.id);
    if (!detail) throw httpError(404, 'Public book not found');
    return res.json(detail);
  } catch (error) {
    return next(error);
  }
}

async function borrowBook(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    const book = await mingtaiRepository.borrowBook(req.params.id);
    if (!book) throw httpError(404, 'Public book not found');
    return res.json({ book });
  } catch (error) {
    return next(error);
  }
}

async function createResonance(req, res, next) {
  try {
    assertUuid(req.params.id, 'annotation id');
    const content = String(req.body.content || '').trim();
    if (!content) {
      throw httpError(400, 'content is required');
    }
    if (content.length > 280) {
      throw httpError(400, 'content is too long');
    }

    const resonance = await mingtaiRepository.createResonance(
      req.user.id,
      req.params.id,
      content,
    );
    if (!resonance) throw httpError(404, 'Annotation not found');
    return res.status(201).json({ resonance });
  } catch (error) {
    return next(error);
  }
}

async function feed(req, res, next) {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
    const annotations = await mingtaiRepository.listFeed({ limit });
    return res.json({ annotations });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  publish,
  publishBook,
  listBooks,
  getBook,
  borrowBook,
  createResonance,
  feed,
};
