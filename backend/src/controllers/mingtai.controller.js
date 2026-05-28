const mingtaiRepository = require('../repositories/mingtai.repository');
const crypto = require('crypto');
const fs = require('fs/promises');
const { publicBaseUrl } = require('../config/env');
const httpError = require('../utils/httpError');
const { absoluteStoragePath, savePublicBookFile } = require('../utils/publicBookStorage');
const { parsePublicBookChapters } = require('../utils/publicBookParser');

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const allowedCopyrightStatuses = new Set(['public_domain', 'original', 'authorized']);

function normalizeEntryIds(body) {
  const entryIds = body.entry_ids;
  const raw = Array.isArray(entryIds)
    ? body.entry_ids
    : typeof entryIds === 'string'
      ? entryIds.split(',')
    : body.entry_id
      ? [body.entry_id]
      : [];

  return [...new Set(raw.map((id) => String(id).trim()).filter(Boolean))];
}

function requestField(req, key, fallback = '') {
  const headerKey = `x-${key.replace(/_/g, '-')}`;
  const values = [
    req.mingtaiFields?.[key],
    Buffer.isBuffer(req.body) ? undefined : req.body?.[key],
    req.query?.[key],
    req.headers[headerKey],
  ];

  for (const value of values) {
    if (value === undefined || value === null) continue;
    const text = String(value).trim();
    if (text.length > 0) return value;
  }

  return fallback;
}

function parseMultipartBody(req) {
  const contentType = String(req.headers['content-type'] || '');
  if (!contentType.toLowerCase().startsWith('multipart/form-data')) {
    return { fields: {}, file: null };
  }

  const boundaryMatch = contentType.match(/boundary=(?:"([^"]+)"|([^;]+))/i);
  const boundary = boundaryMatch?.[1] || boundaryMatch?.[2];
  if (!boundary || !Buffer.isBuffer(req.body)) {
    return { fields: {}, file: null };
  }

  const fields = {};
  let file = null;
  const body = req.body.toString('latin1');
  const parts = body.split(`--${boundary}`);

  for (const rawPart of parts) {
    let part = rawPart;
    if (!part || part === '--\r\n' || part === '--') continue;
    if (part.startsWith('\r\n')) part = part.slice(2);
    if (part.endsWith('\r\n')) part = part.slice(0, -2);
    if (part.endsWith('--')) part = part.slice(0, -2);

    const splitIndex = part.indexOf('\r\n\r\n');
    if (splitIndex < 0) continue;

    const rawHeaders = part.slice(0, splitIndex);
    let rawValue = part.slice(splitIndex + 4);
    if (rawValue.endsWith('\r\n')) rawValue = rawValue.slice(0, -2);

    const disposition = rawHeaders
      .split('\r\n')
      .find((line) => line.toLowerCase().startsWith('content-disposition'));
    if (!disposition) continue;

    const name = disposition.match(/name="([^"]+)"/)?.[1];
    const filename = disposition.match(/filename="([^"]*)"/)?.[1];
    if (!name) continue;

    const valueBuffer = Buffer.from(rawValue, 'latin1');
    if (filename !== undefined) {
      file = {
        fieldName: name,
        filename,
        buffer: valueBuffer,
      };
    } else {
      fields[name] = valueBuffer.toString('utf8');
    }
  }

  return { fields, file };
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

function safeTitle(value) {
  const title = String(value || '').trim();
  if (!title || title.toLowerCase() === 'unknown title' || title === '未知书名') {
    return '未命名文档';
  }
  return title;
}

function safeAuthor(value) {
  const author = String(value || '').trim();
  if (!author || author.toLowerCase() === 'unknown author' || author === '未知作者') {
    return '佚名';
  }
  return author;
}

function publicUrlFor(req, publicPath) {
  const origin = String(publicBaseUrl || '').trim().replace(/\/+$/, '') ||
    `${req.protocol}://${req.get('host')}`;
  return `${origin}${publicPath}`;
}

function requireFields(fields) {
  const missing = Object.entries(fields)
    .filter(([, value]) => String(value || '').trim().length === 0)
    .map(([key]) => key);
  if (missing.length > 0) {
    throw httpError(400, `Missing required fields: ${missing.join(', ')}`, {
      missing_fields: missing,
    });
  }
}

function fallbackSourceBookId(req, { rawTitle, fileType }) {
  const fileName = String(
    requestField(req, 'file_name') ||
      requestField(req, 'filename') ||
      req.headers['x-file-name'] ||
      '',
  ).trim();

  if (Buffer.isBuffer(req.body) && req.body.length > 0) {
    return `upload_${crypto.createHash('sha256').update(req.body).digest('hex').slice(0, 32)}`;
  }

  const seed = [req.user?.id || '', rawTitle, fileName, fileType]
    .map((value) => String(value || '').trim())
    .join(':');
  return `upload_${crypto.createHash('sha256').update(seed).digest('hex').slice(0, 32)}`;
}

function sanitizedPublishBookBody(req) {
  if (Buffer.isBuffer(req.body)) {
    return {
      type: 'Buffer',
      bytes: req.body.length,
      content_type: req.headers['content-type'],
    };
  }

  const body = { ...(req.body || {}) };
  if (typeof body.file_base64 === 'string') {
    body.file_base64 = `<${body.file_base64.length} chars>`;
  }
  return body;
}

async function parseAndSaveBookChapters(publicBookId, buffer, { fileType, title }) {
  const type = String(fileType || '').toLowerCase().replace('.', '').trim();
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) return [];
  if (type !== 'epub' && type !== 'txt') return [];

  const chapters = parsePublicBookChapters(buffer, { fileType: type, title });
  if (chapters.length === 0) {
    throw httpError(400, 'No readable chapters found in public book file');
  }
  await mingtaiRepository.replaceBookChapters(publicBookId, chapters);
  return chapters;
}

async function ensureBookChapters(publicBookId) {
  let chapters = await mingtaiRepository.listBookChapters(publicBookId);
  if (chapters.length > 0) return chapters;

  const book = await mingtaiRepository.getBookStorageInfo(publicBookId);
  if (!book) throw httpError(404, 'Public book not found');

  const type = String(book.file_type || '').toLowerCase().replace('.', '').trim();
  if (type !== 'epub' && type !== 'txt') return [];
  if (!book.storage_path) return [];

  const absolutePath = absoluteStoragePath(book.storage_path);
  const buffer = await fs.readFile(absolutePath);
  await parseAndSaveBookChapters(publicBookId, buffer, {
    fileType: type,
    title: book.title,
  });
  chapters = await mingtaiRepository.listBookChapters(publicBookId);
  return chapters;
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
    const multipart = parseMultipartBody(req);
    req.mingtaiFields = multipart.fields;
    let fileBufferForParsing = null;

    console.log('[MingtaiPublishBook] req.body=', sanitizedPublishBookBody(req));
    console.log('[MingtaiPublishBook] parsed fields=', multipart.fields);

    let sourceBookId = String(
      requestField(req, 'source_book_id') || '',
    ).trim();
    const title = safeTitle(requestField(req, 'title'));
    const rawTitle = String(requestField(req, 'title')).trim();
    const fileType = String(requestField(req, 'file_type')).trim();
    const copyrightStatus = String(requestField(req, 'copyright_status')).trim();
    const entryIds = normalizeEntryIds(Buffer.isBuffer(req.body) ? req.query : req.body);

    if (!sourceBookId) {
      sourceBookId = fallbackSourceBookId(req, { rawTitle, fileType });
      console.log('[MingtaiPublishBook] source_book_id missing, fallback=', sourceBookId);
    }

    requireFields({
      title: rawTitle,
      file_type: fileType,
      copyright_status: copyrightStatus,
    });
    if (!allowedCopyrightStatuses.has(copyrightStatus)) {
      throw httpError(400, 'Invalid copyright_status');
    }
    validateEntryIds(entryIds);

    let storedFile = null;
    if (multipart.file?.buffer?.length > 0) {
      fileBufferForParsing = multipart.file.buffer;
      storedFile = await savePublicBookFile(multipart.file.buffer, {
        fileName: requestField(req, 'file_name') ||
          multipart.file.filename ||
          requestField(req, 'filename'),
        fileType,
        mimeType: req.headers['content-type'],
      });
    } else if (!Buffer.isBuffer(req.body) && typeof req.body?.file_base64 === 'string') {
      const normalizedBase64 = req.body.file_base64.includes(',')
        ? req.body.file_base64.split(',').pop()
        : req.body.file_base64;
      const fileBuffer = Buffer.from(normalizedBase64, 'base64');
      if (fileBuffer.length > 0) {
        fileBufferForParsing = fileBuffer;
        storedFile = await savePublicBookFile(fileBuffer, {
          fileName: requestField(req, 'file_name') || requestField(req, 'filename'),
          fileType,
          mimeType: req.headers['content-type'],
        });
      }
    } else if (
      Buffer.isBuffer(req.body) &&
      req.body.length > 0 &&
      !String(req.headers['content-type'] || '')
        .toLowerCase()
        .startsWith('multipart/form-data')
    ) {
      fileBufferForParsing = req.body;
      storedFile = await savePublicBookFile(req.body, {
        fileName: requestField(req, 'file_name') || requestField(req, 'filename'),
        fileType,
        mimeType: req.headers['content-type'],
      });
    }

    const providedFileUrl = String(requestField(req, 'file_url')).trim();
    if (!storedFile && !providedFileUrl) {
      throw httpError(400, 'book file is required');
    }

    const result = await mingtaiRepository.publishBook(req.user.id, {
      source_book_id: sourceBookId,
      title,
      author: safeAuthor(requestField(req, 'author')),
      cover_url: requestField(req, 'cover_url'),
      description: requestField(req, 'description'),
      copyright_status: copyrightStatus,
      metadata_json: Buffer.isBuffer(req.body) ? {} : req.body.metadata_json,
      file_url: storedFile ? publicUrlFor(req, storedFile.public_path) : providedFileUrl,
      storage_path: storedFile?.storage_path || requestField(req, 'storage_path'),
      file_type: storedFile?.file_type || fileType,
      file_size: storedFile?.file_size || Number(requestField(req, 'file_size')) || 0,
      entry_ids: entryIds,
    });
    const chapters = await parseAndSaveBookChapters(result.book.id, fileBufferForParsing, {
      fileType: result.book.file_type || fileType,
      title,
    });
    if (chapters.length > 0) {
      result.book.chapter_count = chapters.length;
    }

    return res.status(201).json({
      ...result,
      public_book_id: result.book.id,
    });
  } catch (error) {
    return next(error);
  }
}

async function listBookChapters(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    const includeContent = String(req.query.include_content || '').toLowerCase() === 'true';
    const repair = String(req.query.repair || '').toLowerCase() === 'true';
    const chapters = repair
      ? await ensureBookChapters(req.params.id)
      : await mingtaiRepository.listBookChapters(req.params.id, { includeContent });
    return res.json({ chapters });
  } catch (error) {
    return next(error);
  }
}

async function getBookChapter(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    const chapterIndex = Number(req.params.chapterIndex);
    if (!Number.isInteger(chapterIndex) || chapterIndex < 0) {
      throw httpError(400, 'Invalid chapter index');
    }

    let chapter = await mingtaiRepository.getBookChapter(req.params.id, chapterIndex);
    const repair = String(req.query.repair || '').toLowerCase() === 'true';
    if (!chapter && repair) {
      await ensureBookChapters(req.params.id);
      chapter = await mingtaiRepository.getBookChapter(req.params.id, chapterIndex);
    }
    if (!chapter) throw httpError(404, 'Book chapter not found');

    return res.json({ chapter });
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
  listBookChapters,
  getBookChapter,
  listBooks,
  getBook,
  borrowBook,
  createResonance,
  feed,
};
