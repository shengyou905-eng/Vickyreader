const mingtaiRepository = require('../repositories/mingtai.repository');
const crypto = require('crypto');
const { publicBaseUrl } = require('../config/env');
const httpError = require('../utils/httpError');
const {
  deletePublicBookFile,
  savePublicBookCover,
  savePublicBookFile,
  saveProfileAvatar,
} = require('../utils/publicBookStorage');
const { parsePublicBookChapters } = require('../utils/publicBookParser');
const { buildBookIntroduction } = require('../services/bookIntroduction.service');

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const allowedCopyrightStatuses = new Set(['public_domain', 'original', 'authorized']);
const allowedAnnotationSources = new Set(['thought']);

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
    return { fields: {}, file: null, files: {} };
  }

  const boundaryMatch = contentType.match(/boundary=(?:"([^"]+)"|([^;]+))/i);
  const boundary = (boundaryMatch?.[1] || boundaryMatch?.[2] || '').trim();
  if (!boundary || !Buffer.isBuffer(req.body)) {
    return { fields: {}, file: null, files: {} };
  }

  const fields = {};
  const files = {};
  let file = null;
  const delimiter = Buffer.from(`--${boundary}`);
  const headerSeparator = Buffer.from('\r\n\r\n');
  let boundaryOffset = req.body.indexOf(delimiter);

  while (boundaryOffset >= 0) {
    let partStart = boundaryOffset + delimiter.length;
    if (req.body.subarray(partStart, partStart + 2).equals(Buffer.from('--'))) {
      break;
    }
    if (req.body.subarray(partStart, partStart + 2).equals(Buffer.from('\r\n'))) {
      partStart += 2;
    }

    const nextBoundary = req.body.indexOf(delimiter, partStart);
    if (nextBoundary < 0) break;
    boundaryOffset = nextBoundary;
    let partEnd = nextBoundary;
    if (req.body.subarray(partEnd - 2, partEnd).equals(Buffer.from('\r\n'))) {
      partEnd -= 2;
    }

    const part = req.body.subarray(partStart, partEnd);
    const splitIndex = part.indexOf(headerSeparator);
    if (splitIndex < 0) continue;

    const rawHeaders = part.subarray(0, splitIndex).toString('utf8');
    const valueBuffer = part.subarray(splitIndex + headerSeparator.length);

    const disposition = rawHeaders
      .split('\r\n')
      .find((line) => line.toLowerCase().startsWith('content-disposition'));
    if (!disposition) continue;

    const name = disposition.match(/name="([^"]+)"/)?.[1];
    const filename = disposition.match(/filename="([^"]*)"/)?.[1];
    if (!name) continue;

    if (filename !== undefined) {
      const partContentType = rawHeaders
        .split('\r\n')
        .find((line) => line.toLowerCase().startsWith('content-type'))
        ?.split(':')
        .slice(1)
        .join(':')
        .trim();
      const uploadedFile = {
        fieldName: name,
        filename,
        contentType: partContentType,
        buffer: valueBuffer,
      };
      files[name] = uploadedFile;
      if (name === 'file' || !file) file = uploadedFile;
    } else {
      fields[name] = valueBuffer.toString('utf8');
    }
  }

  return { fields, file, files };
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

function storagePathFromPublicUrl(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  try {
    return new URL(raw).pathname;
  } catch (_) {
    return raw;
  }
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

function isWeakBookIntroduction(book) {
  return (
    isWeakIntroText(book?.one_line_summary) ||
    isWeakIntroText(book?.expanded_guide)
  );
}

function isWeakIntroText(value) {
  const text = String(value || '').trim();
  return !text ||
    text.includes('围绕自身核心问题') ||
    text.includes('从正文和读者痕迹') ||
    text.includes('等待有人从第一页') ||
    text.includes('暂无可靠简介') ||
    text.includes('这本书刚来到明台');
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

function parseBookChapters(buffer, { fileType, title }) {
  const type = String(fileType || '').toLowerCase().replace('.', '').trim();
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) return [];
  if (type !== 'epub' && type !== 'txt') return [];

  const chapters = parsePublicBookChapters(buffer, { fileType: type, title });
  if (chapters.length === 0) {
    throw httpError(400, 'No readable chapters found in public book file');
  }
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
    const entryIds = normalizeEntryIds({
      ...(Buffer.isBuffer(req.body) ? {} : req.body),
      ...req.query,
      ...multipart.fields,
    });

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

    if (!storedFile) {
      throw httpError(400, 'uploaded book file is required');
    }

    let storedCover = null;
    try {
      if (multipart.files.cover?.buffer?.length > 0) {
        storedCover = await savePublicBookCover(multipart.files.cover.buffer, {
          fileName: multipart.files.cover.filename,
          mimeType: multipart.files.cover.contentType,
        });
      }
    } catch (error) {
      await deletePublicBookFile(storedFile.storage_path);
      throw error;
    }

    let chapters = [];
    try {
      chapters = parseBookChapters(fileBufferForParsing, {
        fileType: storedFile.file_type,
        title,
      });
    } catch (error) {
      await deletePublicBookFile(storedFile.storage_path);
      await deletePublicBookFile(storedCover?.storage_path);
      throw error;
    }

    const author = safeAuthor(requestField(req, 'author'));
    const uploadedDescription = requestField(req, 'description');
    const introduction = await buildBookIntroduction({
      title,
      author,
      description: uploadedDescription,
      chapters,
    });

    let result;
    try {
      result = await mingtaiRepository.publishBook(req.user.id, {
        source_book_id: sourceBookId,
        title,
        author,
        cover_url: storedCover
          ? publicUrlFor(req, storedCover.public_path)
          : requestField(req, 'cover_url'),
        description: introduction.description || uploadedDescription,
        authoritative_description: introduction.authoritative_description,
        authoritative_description_source: introduction.authoritative_description_source,
        authoritative_description_url: introduction.authoritative_description_url,
        one_line_summary: introduction.one_line_summary,
        one_line_summary_source: introduction.one_line_summary_source,
        encounter_summary: introduction.encounter_summary,
        expanded_guide: introduction.expanded_guide,
        why_worth_reading: introduction.why_worth_reading,
        reading_themes: introduction.reading_themes,
        copyright_status: copyrightStatus,
        metadata_json: Buffer.isBuffer(req.body) ? {} : req.body.metadata_json,
        file_url: publicUrlFor(req, storedFile.public_path),
        storage_path: storedFile.storage_path,
        file_type: storedFile.file_type,
        file_size: storedFile.file_size,
        chapter_count: chapters.length,
        entry_ids: entryIds,
      }, chapters);
    } catch (error) {
      await deletePublicBookFile(storedFile.storage_path);
      await deletePublicBookFile(storedCover?.storage_path);
      throw error;
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
    const chapters = await mingtaiRepository.listBookChapters(req.params.id, {
      includeContent,
    });
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

    const chapter = await mingtaiRepository.getBookChapter(req.params.id, chapterIndex);
    if (!chapter) throw httpError(404, 'Book chapter not found');

    return res.json({ chapter });
  } catch (error) {
    return next(error);
  }
}

async function listBooks(req, res, next) {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
    const books = await mingtaiRepository.listBooks({
      limit,
      search: req.query.q,
      section: req.query.section,
    });
    return res.json({ books });
  } catch (error) {
    return next(error);
  }
}

async function getHome(req, res, next) {
  try {
    const home = await mingtaiRepository.getHome();
    return res.json(home);
  } catch (error) {
    return next(error);
  }
}

async function getBook(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    let detail = await mingtaiRepository.getBook(req.params.id);
    if (!detail) throw httpError(404, 'Public book not found');
    if (isWeakBookIntroduction(detail.book)) {
      const chapters = await mingtaiRepository.listBookIntroChapters(req.params.id);
      const introduction = await buildBookIntroduction({
        title: detail.book.title,
        author: detail.book.author,
        description: detail.book.description,
        chapters,
      });
      if (
        introduction.one_line_summary ||
        introduction.expanded_guide ||
        introduction.description
      ) {
        const refreshedBook = await mingtaiRepository.updateBookIntroduction(
          req.params.id,
          introduction,
        );
        if (refreshedBook) {
          detail = {
            ...detail,
            book: {
              ...detail.book,
              ...refreshedBook,
            },
          };
        }
      }
    }
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

async function deleteMyBooks(req, res, next) {
  try {
    const deletedBooks = await mingtaiRepository.deletePublishedBooks(req.user.id);
    for (const book of deletedBooks) {
      await deletePublicBookFile(book.storage_path);
      await deletePublicBookFile(storagePathFromPublicUrl(book.cover_url));
    }
    return res.json({
      deleted_count: deletedBooks.length,
      deleted_ids: deletedBooks.map((book) => book.id),
    });
  } catch (error) {
    return next(error);
  }
}

async function recordBookRead(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    const book = await mingtaiRepository.recordBookRead(req.params.id);
    if (!book) throw httpError(404, 'Public book not found');
    return res.json({ book });
  } catch (error) {
    return next(error);
  }
}

async function getMyProfile(req, res, next) {
  try {
    await mingtaiRepository.getMyProfile(req.user.id);
    const profile = await mingtaiRepository.getPublicProfile(req.user.id);
    if (!profile) throw httpError(404, 'Profile not found');
    return res.json(profile);
  } catch (error) {
    return next(error);
  }
}

async function updateMyProfile(req, res, next) {
  try {
    const profile = await mingtaiRepository.updateMyProfile(req.user.id, {
      nickname: req.body?.nickname,
      avatar_url: req.body?.avatar_url,
      bio: req.body?.bio,
    });
    if (!profile) throw httpError(404, 'Profile not found');
    return res.json({ profile });
  } catch (error) {
    return next(error);
  }
}

async function uploadMyProfileAvatar(req, res, next) {
  try {
    const mimeType = String(req.body?.mime_type || '').trim().toLowerCase();
    if (!allowedAvatarMimeTypes.has(mimeType)) {
      throw httpError(400, 'Unsupported avatar image type');
    }

    const rawBase64 = String(req.body?.image_base64 || '').trim();
    if (!rawBase64) {
      throw httpError(400, 'image_base64 is required');
    }

    const normalizedBase64 = rawBase64.includes(',')
      ? rawBase64.split(',').pop()
      : rawBase64;
    const imageBuffer = Buffer.from(normalizedBase64, 'base64');
    if (!imageBuffer.length) {
      throw httpError(400, 'avatar image is empty');
    }
    if (imageBuffer.length > 2 * 1024 * 1024) {
      throw httpError(400, 'avatar image is too large');
    }

    const saved = await saveProfileAvatar(imageBuffer, {
      fileName: req.body?.file_name || 'avatar.jpg',
      mimeType,
    });
    const avatarUrl = publicUrlFor(req, saved.public_path);
    const profile = await mingtaiRepository.updateMyProfile(req.user.id, {
      nickname: req.body?.nickname,
      avatar_url: avatarUrl,
      bio: req.body?.bio,
    });
    if (!profile) throw httpError(404, 'Profile not found');
    return res.status(201).json({ profile });
  } catch (error) {
    return next(error);
  }
}

async function getPublicProfile(req, res, next) {
  try {
    assertUuid(req.params.userId, 'user id');
    const profile = await mingtaiRepository.getPublicProfile(req.params.userId);
    if (!profile) throw httpError(404, 'Profile not found');
    return res.json(profile);
  } catch (error) {
    return next(error);
  }
}

async function listBookReviews(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    const limit = Math.min(50, Math.max(1, Number(req.query.limit || 20)));
    const reviews = await mingtaiRepository.listBookReviews(req.params.id, { limit });
    return res.json({ reviews });
  } catch (error) {
    return next(error);
  }
}

async function createBookReview(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    const content = String(req.body?.content || '').trim();
    if (!isMeaningfulPublicText(content, { minLength: 10 })) {
      throw httpError(400, '短评至少需要 10 个字，并且不能是测试或无意义内容');
    }
    const review = await mingtaiRepository.createBookReview(
      req.user.id,
      req.params.id,
      content,
    );
    if (!review) throw httpError(404, 'Public book not found');
    return res.status(201).json({ review });
  } catch (error) {
    return next(error);
  }
}

async function updateBookReview(req, res, next) {
  try {
    assertUuid(req.params.id, 'review id');
    const content = String(req.body?.content || '').trim();
    if (!isMeaningfulPublicText(content, { minLength: 10 })) {
      throw httpError(400, '短评至少需要 10 个字，并且不能是测试或无意义内容');
    }
    const review = await mingtaiRepository.updateBookReview(
      req.user.id,
      req.params.id,
      content,
    );
    if (!review) throw httpError(404, 'Review not found');
    return res.json({ review });
  } catch (error) {
    return next(error);
  }
}

async function deleteBookReview(req, res, next) {
  try {
    assertUuid(req.params.id, 'review id');
    const deleted = await mingtaiRepository.deleteBookReview(
      req.user.id,
      req.params.id,
    );
    if (!deleted) throw httpError(404, 'Review not found');
    return res.json({ deleted: true });
  } catch (error) {
    return next(error);
  }
}

async function createBookAnnotation(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    const source = String(req.body.source || '').trim();
    if (!allowedAnnotationSources.has(source)) {
      throw httpError(400, 'Invalid source');
    }

    const originalText = String(req.body.original_text || '').trim();
    const annotationText = String(req.body.annotation_text || '').trim();
    if (!originalText && !annotationText) {
      throw httpError(400, 'original_text or annotation_text is required');
    }

    const annotation = await mingtaiRepository.createPublicAnnotation(
      req.user.id,
      req.params.id,
      {
        source,
        chapter_index: req.body.chapter_index,
        chapter_title: req.body.chapter_title,
        original_text: originalText,
        annotation_text: annotationText,
        auto_tags: req.body.auto_tags,
        metadata_json: req.body.metadata_json,
        position_json: req.body.position_json,
      },
    );
    if (!annotation) throw httpError(404, 'Public book not found');
    return res.status(201).json({ annotation });
  } catch (error) {
    return next(error);
  }
}

async function createAnnotationComment(req, res, next) {
  try {
    assertUuid(req.params.id, 'annotation id');
    const content = String(req.body.content || '').trim();
    if (!content) {
      throw httpError(400, 'content is required');
    }
    if (content.length > 1000) {
      throw httpError(400, 'content is too long');
    }

    const comment = await mingtaiRepository.createAnnotationComment(
      req.user.id,
      req.params.id,
      content,
    );
    if (!comment) throw httpError(404, 'Annotation not found');
    return res.status(201).json({ comment });
  } catch (error) {
    return next(error);
  }
}

async function createResonance(req, res, next) {
  try {
    assertUuid(req.params.id, 'annotation id');
    const content = String(req.body.content || '').trim();
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

module.exports = {
  _parseMultipartBody: parseMultipartBody,
  publish,
  publishBook,
  listBookChapters,
  getBookChapter,
  listBooks,
  getHome,
  getBook,
  deleteMyBooks,
  borrowBook,
  recordBookRead,
  getMyProfile,
  updateMyProfile,
  uploadMyProfileAvatar,
  getPublicProfile,
  listBookReviews,
  createBookReview,
  updateBookReview,
  deleteBookReview,
  createBookAnnotation,
  createAnnotationComment,
  createResonance,
};
