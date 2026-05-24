const { query } = require('../config/db');

function shapeBook(row) {
  return {
    id: row.id,
    source_book_id: row.source_book_id || '',
    title: safeTitle(row.title),
    author: safeAuthor(row.author),
    cover_url: row.cover_url || '',
    file_url: row.file_url || '',
    storage_path: row.storage_path || '',
    file_type: row.file_type || '',
    file_size: Number(row.file_size || 0),
    description: row.description || '',
    copyright_status: row.copyright_status || '',
    borrow_count: Number(row.borrow_count || 0),
    reading_count: Number(row.reading_count || row.borrow_count || 0),
    annotation_count: Number(row.annotation_count || 0),
    recent_discussion_count: Number(row.recent_discussion_count || 0),
    created_at: row.created_at,
  };
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

function shapeAnnotation(row) {
  return {
    id: row.id,
    entry_id: row.entry_id,
    public_book_id: row.public_book_id || '',
    source: row.source,
    book_id: row.book_id || '',
    book_title: row.book_title || '',
    book_author: row.book_author || '',
    book_cover: row.book_cover || '',
    chapter_index: row.chapter_index || '',
    chapter_title: row.chapter_title || '',
    original_text: row.original_text || '',
    annotation_text: row.annotation_text || '',
    auto_tags: row.auto_tags || [],
    metadata_json: row.metadata_json || {},
    resonance_count: Number(row.resonance_count || 0),
    created_at: row.created_at,
  };
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

async function upsertPublicBook(userId, payload) {
  const metadata = normalizeMetadata(payload.metadata_json);
  const title = safeTitle(payload.title);
  const author = safeAuthor(payload.author);
  const result = await query(
    `INSERT INTO public_books (
       publisher_user_id,
       source_book_id,
       title,
       author,
       cover_url,
       file_url,
       storage_path,
       file_type,
       file_size,
       description,
       copyright_status,
       metadata_json
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
     ON CONFLICT (publisher_user_id, source_book_id) DO UPDATE SET
       title = EXCLUDED.title,
       author = EXCLUDED.author,
       cover_url = EXCLUDED.cover_url,
       file_url = EXCLUDED.file_url,
       storage_path = EXCLUDED.storage_path,
       file_type = EXCLUDED.file_type,
       file_size = EXCLUDED.file_size,
       description = EXCLUDED.description,
       copyright_status = EXCLUDED.copyright_status,
       metadata_json = EXCLUDED.metadata_json,
       updated_at = now()
     RETURNING
       id,
       source_book_id,
       title,
       author,
       cover_url,
       file_url,
       storage_path,
       file_type,
       file_size,
       description,
       copyright_status,
       borrow_count,
       0 AS annotation_count,
       created_at`,
    [
      userId,
      payload.source_book_id,
      title,
      author,
      payload.cover_url || null,
      payload.file_url || null,
      payload.storage_path || null,
      payload.file_type || null,
      Number(payload.file_size || 0),
      payload.description || null,
      payload.copyright_status,
      metadata,
    ],
  );

  const book = shapeBook(result.rows[0]);
  await syncBookPublicationSideTables(userId, payload, book);
  return book;
}

async function syncBookPublicationSideTables(userId, payload, publicBook) {
  const metadata = normalizeMetadata(payload.metadata_json);
  const title = safeTitle(payload.title);
  const author = safeAuthor(payload.author);
  await query(
    `WITH source_book AS (
       INSERT INTO books (
         source_book_id,
         title,
         author,
         cover_url,
         description,
         metadata_json
       )
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (source_book_id, title) DO UPDATE SET
         author = EXCLUDED.author,
         cover_url = EXCLUDED.cover_url,
         description = EXCLUDED.description,
         metadata_json = EXCLUDED.metadata_json,
         updated_at = now()
       RETURNING id
     )
     INSERT INTO book_publications (
       book_id,
       public_book_id,
       publisher_user_id,
       source_book_id,
       copyright_status,
       reading_count,
       metadata_json
     )
     SELECT id, $7, $8, $1, $9, $10, $6
     FROM source_book
     ON CONFLICT (publisher_user_id, source_book_id) DO UPDATE SET
       book_id = EXCLUDED.book_id,
       public_book_id = EXCLUDED.public_book_id,
       copyright_status = EXCLUDED.copyright_status,
       metadata_json = EXCLUDED.metadata_json,
       updated_at = now()`,
    [
      payload.source_book_id,
      title,
      author,
      payload.cover_url || null,
      payload.description || null,
      metadata,
      publicBook.id,
      userId,
      payload.copyright_status,
      publicBook.borrow_count,
    ],
  );
}

async function publishBook(userId, payload) {
  const book = await upsertPublicBook(userId, payload);
  const entryIds = Array.isArray(payload.entry_ids) ? payload.entry_ids : [];
  const annotations = entryIds.length > 0
    ? await publishEntries(userId, entryIds, book.id)
    : [];

  return {
    book: {
      ...book,
      annotation_count: annotations.length,
    },
    annotations,
  };
}

async function publishEntries(userId, entryIds, publicBookId = null) {
  const result = await query(
    `INSERT INTO public_annotations (
       entry_id,
       public_book_id,
       user_id,
       source,
       book_id,
       book_title,
       book_author,
       book_cover,
       chapter_index,
       chapter_title,
       original_text,
       annotation_text,
       auto_tags,
       metadata_json
     )
     SELECT
       e.id,
       COALESCE($3::uuid, pb.id),
       e.user_id,
       e.source,
       e.book_id,
       e.book_title,
       COALESCE(
         NULLIF(e.metadata_json->>'book_author', ''),
         NULLIF(e.metadata_json->>'author', ''),
         pb.author,
         '佚名'
       ) AS book_author,
       COALESCE(
         NULLIF(e.metadata_json->>'book_cover', ''),
         NULLIF(e.metadata_json->>'cover_path', ''),
         NULLIF(e.metadata_json->>'coverPath', ''),
         pb.cover_url,
         ''
       ) AS book_cover,
       e.chapter_index,
       e.chapter_title,
       e.original_text,
       COALESCE(
         NULLIF(e.user_input, ''),
         NULLIF(e.auto_summary, ''),
         CASE WHEN e.source = 'ai_explanation' THEN NULLIF(e.ai_explanation, '') END,
         ''
       ) AS annotation_text,
       e.auto_tags,
       e.metadata_json || jsonb_build_object('published_from_entry_id', e.id::text)
     FROM user_entries e
     LEFT JOIN public_books pb
       ON pb.publisher_user_id = e.user_id
      AND pb.source_book_id = e.book_id
     WHERE e.user_id = $1
       AND e.id = ANY($2::uuid[])
     ON CONFLICT (entry_id) DO UPDATE SET
       public_book_id = COALESCE(EXCLUDED.public_book_id, public_annotations.public_book_id),
       source = EXCLUDED.source,
       book_id = EXCLUDED.book_id,
       book_title = EXCLUDED.book_title,
       book_author = EXCLUDED.book_author,
       book_cover = EXCLUDED.book_cover,
       chapter_index = EXCLUDED.chapter_index,
       chapter_title = EXCLUDED.chapter_title,
       original_text = EXCLUDED.original_text,
       annotation_text = EXCLUDED.annotation_text,
       auto_tags = EXCLUDED.auto_tags,
       metadata_json = EXCLUDED.metadata_json,
       updated_at = now()
     RETURNING
       id,
       entry_id,
       public_book_id,
       source,
       book_id,
       book_title,
       book_author,
       book_cover,
       chapter_index,
       chapter_title,
       original_text,
       annotation_text,
       auto_tags,
       metadata_json,
       0 AS resonance_count,
       created_at`,
    [userId, entryIds, publicBookId],
  );

  return result.rows.map(shapeAnnotation);
}

async function listBooks({ limit = 50 } = {}) {
  const result = await query(
    `SELECT
       b.id,
       b.source_book_id,
       b.title,
       b.author,
       b.cover_url,
       b.file_url,
       b.storage_path,
       b.file_type,
       b.file_size,
       b.description,
       b.copyright_status,
       b.borrow_count,
       b.borrow_count AS reading_count,
       COUNT(DISTINCT a.id) AS annotation_count,
       GREATEST(COUNT(DISTINCT r.id), COUNT(DISTINCT d.id)) AS recent_discussion_count,
       b.created_at
     FROM public_books b
     LEFT JOIN public_annotations a ON a.public_book_id = b.id
     LEFT JOIN resonances r ON r.annotation_id = a.id
     LEFT JOIN book_discussions d ON d.public_book_id = b.id
     GROUP BY b.id
     ORDER BY b.created_at DESC
     LIMIT $1`,
    [limit],
  );

  return result.rows.map(shapeBook);
}

async function getBook(publicBookId) {
  const bookResult = await query(
    `SELECT
       b.id,
       b.source_book_id,
       b.title,
       b.author,
       b.cover_url,
       b.file_url,
       b.storage_path,
       b.file_type,
       b.file_size,
       b.description,
       b.copyright_status,
       b.borrow_count,
       b.borrow_count AS reading_count,
       COUNT(DISTINCT a.id) AS annotation_count,
       GREATEST(COUNT(DISTINCT r.id), COUNT(DISTINCT d.id)) AS recent_discussion_count,
       b.created_at
     FROM public_books b
     LEFT JOIN public_annotations a ON a.public_book_id = b.id
     LEFT JOIN resonances r ON r.annotation_id = a.id
     LEFT JOIN book_discussions d ON d.public_book_id = b.id
     WHERE b.id = $1
     GROUP BY b.id`,
    [publicBookId],
  );

  if (bookResult.rows.length === 0) return null;

  const annotations = await listAnnotationsByBook(publicBookId);
  return {
    book: shapeBook(bookResult.rows[0]),
    annotations,
  };
}

async function listAnnotationsByBook(publicBookId) {
  const result = await query(
    `SELECT
       a.id,
       a.entry_id,
       a.public_book_id,
       a.source,
       a.book_id,
       a.book_title,
       a.book_author,
       a.book_cover,
       a.chapter_index,
       a.chapter_title,
       a.original_text,
       a.annotation_text,
       a.auto_tags,
       a.metadata_json,
       COUNT(r.id) AS resonance_count,
       a.created_at
     FROM public_annotations a
     LEFT JOIN resonances r ON r.annotation_id = a.id
     WHERE a.public_book_id = $1
     GROUP BY a.id
     ORDER BY a.created_at DESC`,
    [publicBookId],
  );

  return result.rows.map(shapeAnnotation);
}

async function listFeed({ limit = 50 } = {}) {
  const result = await query(
    `SELECT
       a.id,
       a.entry_id,
       a.public_book_id,
       a.source,
       a.book_id,
       a.book_title,
       a.book_author,
       a.book_cover,
       a.chapter_index,
       a.chapter_title,
       a.original_text,
       a.annotation_text,
       a.auto_tags,
       a.metadata_json,
       COUNT(r.id) AS resonance_count,
       a.created_at
     FROM public_annotations a
     LEFT JOIN resonances r ON r.annotation_id = a.id
     GROUP BY a.id
     ORDER BY a.created_at DESC
     LIMIT $1`,
    [limit],
  );

  return result.rows.map(shapeAnnotation);
}

async function createResonance(userId, annotationId, content) {
  const result = await query(
    `WITH target AS (
       SELECT id, public_book_id, original_text
       FROM public_annotations
       WHERE id = $1
     ),
     created AS (
       INSERT INTO resonances (annotation_id, user_id, content)
       SELECT id, $2, $3
       FROM target
       RETURNING id, annotation_id, content, created_at
     ),
     public_resonance AS (
       INSERT INTO book_resonance (
         public_book_id,
         annotation_id,
         user_id,
         content
       )
       SELECT target.public_book_id, target.id, $2, $3
       FROM target
       RETURNING id
     ),
     discussion AS (
       INSERT INTO book_discussions (
         public_book_id,
         annotation_id,
         user_id,
         discussion_type,
         anchor_text,
         content
       )
       SELECT
         target.public_book_id,
         target.id,
         $2,
         'resonance',
         target.original_text,
         $3
       FROM target
       RETURNING id
     )
     SELECT id, annotation_id, content, created_at
     FROM created`,
    [annotationId, userId, content],
  );

  return result.rows[0] || null;
}

async function borrowBook(publicBookId) {
  const result = await query(
    `UPDATE public_books
     SET borrow_count = borrow_count + 1,
         updated_at = now()
     WHERE id = $1
     RETURNING
       id,
       source_book_id,
       title,
       author,
       cover_url,
       file_url,
       storage_path,
       file_type,
       file_size,
       description,
       copyright_status,
       borrow_count,
       borrow_count AS reading_count,
       0 AS annotation_count,
       0 AS recent_discussion_count,
       created_at`,
    [publicBookId],
  );

  if (result.rows.length === 0) return null;

  await query(
    `UPDATE book_publications
     SET reading_count = reading_count + 1,
         updated_at = now()
     WHERE public_book_id = $1`,
    [publicBookId],
  );

  return shapeBook(result.rows[0]);
}

module.exports = {
  publishBook,
  publishEntries,
  listBooks,
  getBook,
  listFeed,
  createResonance,
  borrowBook,
};
