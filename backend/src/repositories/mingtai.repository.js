const { query } = require('../config/db');

function shapeBook(row) {
  return {
    id: row.id,
    uploader_user_id: row.uploader_user_id || row.publisher_user_id || '',
    publisher_user_id: row.publisher_user_id || row.uploader_user_id || '',
    source_book_id: row.source_book_id || '',
    title: safeTitle(row.title),
    author: safeAuthor(row.author),
    cover_url: row.cover_url || '',
    file_url: row.file_url || '',
    original_file_url: row.original_file_url || row.file_url || '',
    storage_path: row.storage_path || '',
    file_type: row.file_type || '',
    file_size: Number(row.file_size || 0),
    chapter_count: Number(row.chapter_count || 0),
    description: row.description || '',
    copyright_status: row.copyright_status || '',
    borrow_count: Number(row.borrow_count || 0),
    read_count: Number(row.read_count || row.reading_count || row.borrow_count || 0),
    reading_count: Number(row.reading_count || row.read_count || row.borrow_count || 0),
    annotation_count: Number(row.annotation_count || 0),
    recent_discussion_count: Number(row.recent_discussion_count || 0),
    created_at: row.created_at,
    updated_at: row.updated_at,
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
  const publicBookId = row.public_book_id || row.book_id_uuid || '';
  return {
    id: row.id,
    entry_id: row.entry_id || '',
    public_book_id: publicBookId,
    source: row.source,
    book_id: publicBookId || row.book_id || '',
    book_title: row.book_title || '',
    book_author: row.book_author || '',
    book_cover: row.book_cover || '',
    chapter_index: row.chapter_index || '',
    chapter_title: row.chapter_title || '',
    original_text: row.original_text || '',
    annotation_text: row.annotation_text || '',
    auto_tags: row.auto_tags || [],
    metadata_json: row.metadata_json || {},
    position_json: row.position_json || {},
    resonance_count: Number(row.resonance_count || 0),
    comment_count: Number(row.comment_count || 0),
    created_at: row.created_at,
  };
}

function shapeChapter(row, { includeContent = false } = {}) {
  const chapterTitle = row.chapter_title || row.title || `第${Number(row.chapter_index || 0) + 1}章`;
  const contentHtml = row.content_html || row.content || '';
  const contentText = row.content_text || row.plain_text || '';
  return {
    id: row.id,
    book_id: row.book_id || row.public_book_id,
    public_book_id: row.public_book_id,
    chapter_index: Number(row.chapter_index || 0),
    chapter_title: chapterTitle,
    title: chapterTitle,
    href: row.href || '',
    content_text: contentText,
    plain_text: contentText,
    word_count: Number(row.word_count || countWords(contentText)),
    preview: String(contentText || '').slice(0, 180),
    ...(includeContent ? { content_html: contentHtml, content: contentHtml } : {}),
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

function countWords(text) {
  const value = String(text || '').trim();
  if (!value) return 0;
  const cjk = value.match(/[\u4e00-\u9fff]/g)?.length || 0;
  const latin = value.replace(/[\u4e00-\u9fff]/g, ' ')
    .split(/\s+/)
    .filter(Boolean)
    .length;
  return cjk + latin;
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
       uploader_user_id,
       source_book_id,
       title,
       author,
       cover_url,
       file_url,
       original_file_url,
       storage_path,
       file_type,
       file_size,
       chapter_count,
       description,
       copyright_status,
       metadata_json
     )
     VALUES ($1, $1, $2, $3, $4, $5, $6, $6, $7, $8, $9, $10, $11, $12, $13)
     ON CONFLICT (publisher_user_id, source_book_id) DO UPDATE SET
       uploader_user_id = EXCLUDED.uploader_user_id,
       title = EXCLUDED.title,
       author = EXCLUDED.author,
       cover_url = EXCLUDED.cover_url,
       file_url = EXCLUDED.file_url,
       original_file_url = EXCLUDED.original_file_url,
       storage_path = EXCLUDED.storage_path,
       file_type = EXCLUDED.file_type,
       file_size = EXCLUDED.file_size,
       chapter_count = EXCLUDED.chapter_count,
       description = EXCLUDED.description,
       copyright_status = EXCLUDED.copyright_status,
       metadata_json = EXCLUDED.metadata_json,
       updated_at = now()
     RETURNING
       id,
       publisher_user_id,
       uploader_user_id,
       source_book_id,
       title,
       author,
       cover_url,
       file_url,
       original_file_url,
       storage_path,
       file_type,
       file_size,
       chapter_count,
       description,
       copyright_status,
       borrow_count,
       read_count,
       0 AS annotation_count,
       created_at,
       updated_at`,
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
      Number(payload.chapter_count || 0),
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

async function replaceBookChapters(publicBookId, chapters) {
  const normalizedChapters = Array.isArray(chapters) ? chapters : [];

  await query('DELETE FROM book_chapters WHERE public_book_id = $1', [publicBookId]);

  for (const chapter of normalizedChapters) {
    const index = Number(chapter.chapter_index || 0);
    const chapterTitle = String(chapter.title || chapter.chapter_title || '').trim() ||
      `第${index + 1}章`;
    const contentHtml = String(chapter.content || chapter.content_html || '');
    const contentText = String(chapter.plain_text || chapter.content_text || '');
    await query(
      `INSERT INTO book_chapters (
         public_book_id,
         book_id,
         chapter_index,
         title,
         chapter_title,
         content,
         content_html,
         plain_text,
         content_text,
         word_count,
         href
       )
       VALUES ($1, $1, $2, $3, $3, $4, $4, $5, $5, $6, $7)
       ON CONFLICT (public_book_id, chapter_index) DO UPDATE SET
         book_id = EXCLUDED.book_id,
         title = EXCLUDED.title,
         chapter_title = EXCLUDED.chapter_title,
         content = EXCLUDED.content,
         content_html = EXCLUDED.content_html,
         plain_text = EXCLUDED.plain_text,
         content_text = EXCLUDED.content_text,
         word_count = EXCLUDED.word_count,
         href = EXCLUDED.href,
         updated_at = now()`,
      [
        publicBookId,
        index,
        chapterTitle,
        contentHtml,
        contentText,
        countWords(contentText),
        String(chapter.href || ''),
      ],
    );
  }

  const result = await query(
    `UPDATE public_books
     SET chapter_count = $2,
         updated_at = now()
     WHERE id = $1
     RETURNING
       id,
       publisher_user_id,
       uploader_user_id,
       source_book_id,
       title,
       author,
       cover_url,
       file_url,
       original_file_url,
       storage_path,
       file_type,
       file_size,
       chapter_count,
       description,
       copyright_status,
       borrow_count,
       read_count,
       borrow_count AS reading_count,
       0 AS annotation_count,
       0 AS recent_discussion_count,
       created_at,
       updated_at`,
    [publicBookId, normalizedChapters.length],
  );

  return result.rows[0] ? shapeBook(result.rows[0]) : null;
}

async function listBookChapters(publicBookId, { includeContent = false } = {}) {
  const result = await query(
    `SELECT
       id,
       public_book_id,
       COALESCE(book_id, public_book_id) AS book_id,
       chapter_index,
       COALESCE(chapter_title, title, '') AS chapter_title,
       COALESCE(chapter_title, title, '') AS title,
       ${includeContent
        ? 'COALESCE(content_html, content, \'\') AS content_html, COALESCE(content_html, content, \'\') AS content,'
        : "'' AS content_html, '' AS content,"}
       COALESCE(content_text, plain_text, '') AS content_text,
       COALESCE(content_text, plain_text, '') AS plain_text,
       word_count,
       href,
       created_at,
       updated_at
     FROM book_chapters
     WHERE public_book_id = $1
     ORDER BY chapter_index ASC`,
    [publicBookId],
  );

  return result.rows.map((row) => shapeChapter(row, { includeContent }));
}

async function getBookChapter(publicBookId, chapterIndex) {
  const result = await query(
    `SELECT
       id,
       public_book_id,
       COALESCE(book_id, public_book_id) AS book_id,
       chapter_index,
       COALESCE(chapter_title, title, '') AS chapter_title,
       COALESCE(chapter_title, title, '') AS title,
       COALESCE(content_html, content, '') AS content_html,
       COALESCE(content_html, content, '') AS content,
       COALESCE(content_text, plain_text, '') AS content_text,
       COALESCE(content_text, plain_text, '') AS plain_text,
       word_count,
       href,
       created_at,
       updated_at
     FROM book_chapters
     WHERE public_book_id = $1
       AND chapter_index = $2
     LIMIT 1`,
    [publicBookId, chapterIndex],
  );

  return result.rows[0]
    ? shapeChapter(result.rows[0], { includeContent: true })
    : null;
}

async function getBookStorageInfo(publicBookId) {
  const result = await query(
    `SELECT
       id,
       storage_path,
       file_type,
       title,
       chapter_count
     FROM public_books
     WHERE id = $1
     LIMIT 1`,
    [publicBookId],
  );

  return result.rows[0] || null;
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
       metadata_json,
       position_json
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
       e.metadata_json || jsonb_build_object('published_from_entry_id', e.id::text),
       COALESCE(e.metadata_json->'position_json', '{}'::jsonb)
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
       position_json = EXCLUDED.position_json,
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
       position_json,
       0 AS resonance_count,
       0 AS comment_count,
       created_at`,
    [userId, entryIds, publicBookId],
  );

  return result.rows.map(shapeAnnotation);
}

async function listBooks({ limit = 50, search = '', section = '' } = {}) {
  const values = [];
  const where = [];
  const q = String(search || '').trim();
  if (q) {
    values.push(`%${q}%`);
    where.push(`(b.title ILIKE $${values.length} OR b.author ILIKE $${values.length})`);
  }
  if (section === 'public_domain') {
    where.push("b.copyright_status = 'public_domain'");
  }
  values.push(limit);
  const limitRef = `$${values.length}`;
  const whereSql = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';
  const orderSql = section === 'annotated'
    ? 'annotation_count DESC, b.updated_at DESC, b.created_at DESC'
    : section === 'popular'
      ? 'reading_count DESC, b.updated_at DESC, b.created_at DESC'
      : 'b.updated_at DESC, b.created_at DESC';

  const result = await query(
    `SELECT
       b.id,
       b.publisher_user_id,
       b.uploader_user_id,
       b.source_book_id,
       b.title,
       b.author,
       b.cover_url,
       b.file_url,
       b.original_file_url,
       b.storage_path,
       b.file_type,
       b.file_size,
       b.chapter_count,
       b.description,
       b.copyright_status,
       b.borrow_count,
       b.read_count,
       GREATEST(b.read_count, b.borrow_count) AS reading_count,
       COUNT(DISTINCT a.id) AS annotation_count,
       GREATEST(
         COUNT(DISTINCT r.id),
         COUNT(DISTINCT ar.id),
         COUNT(DISTINCT d.id),
         COUNT(DISTINCT c.id)
       ) AS recent_discussion_count,
       b.created_at,
       b.updated_at
     FROM public_books b
     LEFT JOIN public_annotations a ON a.public_book_id = b.id
     LEFT JOIN resonances r ON r.annotation_id = a.id
     LEFT JOIN annotation_resonances ar ON ar.annotation_id = a.id
     LEFT JOIN annotation_comments c ON c.annotation_id = a.id
     LEFT JOIN book_discussions d ON d.public_book_id = b.id
     ${whereSql}
     GROUP BY b.id
     ORDER BY ${orderSql}
     LIMIT ${limitRef}`,
    values,
  );

  return result.rows.map(shapeBook);
}

async function getBook(publicBookId) {
  const bookResult = await query(
    `SELECT
       b.id,
       b.publisher_user_id,
       b.uploader_user_id,
       b.source_book_id,
       b.title,
       b.author,
       b.cover_url,
       b.file_url,
       b.original_file_url,
       b.storage_path,
       b.file_type,
       b.file_size,
       b.chapter_count,
       b.description,
       b.copyright_status,
       b.borrow_count,
       b.read_count,
       GREATEST(b.read_count, b.borrow_count) AS reading_count,
       COUNT(DISTINCT a.id) AS annotation_count,
       GREATEST(
         COUNT(DISTINCT r.id),
         COUNT(DISTINCT ar.id),
         COUNT(DISTINCT d.id),
         COUNT(DISTINCT c.id)
       ) AS recent_discussion_count,
       b.created_at,
       b.updated_at
     FROM public_books b
     LEFT JOIN public_annotations a ON a.public_book_id = b.id
     LEFT JOIN resonances r ON r.annotation_id = a.id
     LEFT JOIN annotation_resonances ar ON ar.annotation_id = a.id
     LEFT JOIN annotation_comments c ON c.annotation_id = a.id
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
       a.position_json,
       GREATEST(COUNT(DISTINCT r.id), COUNT(DISTINCT ar.id)) AS resonance_count,
       COUNT(DISTINCT c.id) AS comment_count,
       a.created_at
     FROM public_annotations a
     LEFT JOIN resonances r ON r.annotation_id = a.id
     LEFT JOIN annotation_resonances ar ON ar.annotation_id = a.id
     LEFT JOIN annotation_comments c ON c.annotation_id = a.id
     WHERE a.public_book_id = $1
     GROUP BY a.id
     ORDER BY a.created_at DESC`,
    [publicBookId],
  );

  return result.rows.map(shapeAnnotation);
}

async function createPublicAnnotation(userId, publicBookId, payload) {
  const source = String(payload.source || '').trim();
  const chapterIndex = String(payload.chapter_index ?? '0');
  const metadata = normalizeMetadata(payload.metadata_json);
  const positionJson = normalizeMetadata(payload.position_json);
  const autoTags = Array.isArray(payload.auto_tags)
    ? payload.auto_tags.map((tag) => String(tag).trim()).filter(Boolean)
    : [];

  const result = await query(
    `WITH book AS (
       SELECT id, title, author, cover_url
       FROM public_books
       WHERE id = $2
     ),
     created AS (
       INSERT INTO public_annotations (
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
         metadata_json,
         position_json
       )
       SELECT
         book.id,
         $1,
         $3,
         book.id::text,
         book.title,
         COALESCE(book.author, '佚名'),
         COALESCE(book.cover_url, ''),
         $4,
         $5,
         $6,
         $7,
         $8,
         $9,
         $10
       FROM book
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
         position_json,
         0 AS resonance_count,
         0 AS comment_count,
         created_at
     )
     SELECT * FROM created`,
    [
      userId,
      publicBookId,
      source,
      chapterIndex,
      String(payload.chapter_title || ''),
      String(payload.original_text || ''),
      String(payload.annotation_text || ''),
      autoTags,
      metadata,
      positionJson,
    ],
  );

  return result.rows[0] ? shapeAnnotation(result.rows[0]) : null;
}

async function createAnnotationComment(userId, annotationId, content) {
  const result = await query(
    `WITH target AS (
       SELECT id, public_book_id, original_text
       FROM public_annotations
       WHERE id = $1
     ),
     created AS (
       INSERT INTO annotation_comments (annotation_id, user_id, content)
       SELECT id, $2, $3
       FROM target
       RETURNING id, annotation_id, content, created_at
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
         'thought',
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

async function createResonance(userId, annotationId, content = '') {
  const target = await query(
    `SELECT id
     FROM public_annotations
     WHERE id = $1
     LIMIT 1`,
    [annotationId],
  );
  if (target.rows.length === 0) return null;

  await query(
    `INSERT INTO annotation_resonances (annotation_id, user_id)
     VALUES ($1, $2)
     ON CONFLICT (annotation_id, user_id) DO NOTHING`,
    [annotationId, userId],
  );

  const text = String(content || '').trim();
  if (text) {
    await query(
      `WITH target AS (
         SELECT id, public_book_id, original_text
         FROM public_annotations
         WHERE id = $1
       ),
       created AS (
         INSERT INTO resonances (annotation_id, user_id, content)
         SELECT id, $2, $3
         FROM target
         RETURNING id
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
       )
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
       FROM target`,
      [annotationId, userId, text],
    );
  }

  const countResult = await query(
    `SELECT
       GREATEST(
         COUNT(DISTINCT r.id),
         COUNT(DISTINCT ar.id)
       ) AS resonance_count
     FROM public_annotations a
     LEFT JOIN resonances r ON r.annotation_id = a.id
     LEFT JOIN annotation_resonances ar ON ar.annotation_id = a.id
     WHERE a.id = $1
     GROUP BY a.id`,
    [annotationId],
  );

  return {
    annotation_id: annotationId,
    content: text,
    resonance_count: Number(countResult.rows[0]?.resonance_count || 0),
    created_at: new Date().toISOString(),
  };
}

async function borrowBook(publicBookId) {
  const result = await query(
    `UPDATE public_books
     SET borrow_count = borrow_count + 1,
         read_count = read_count + 1,
         updated_at = now()
     WHERE id = $1
     RETURNING
       id,
       publisher_user_id,
       uploader_user_id,
       source_book_id,
       title,
       author,
       cover_url,
       file_url,
       original_file_url,
       storage_path,
       file_type,
       file_size,
       chapter_count,
       description,
       copyright_status,
       borrow_count,
       read_count,
       GREATEST(read_count, borrow_count) AS reading_count,
       0 AS annotation_count,
       0 AS recent_discussion_count,
       created_at,
       updated_at`,
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
  replaceBookChapters,
  listBookChapters,
  getBookChapter,
  getBookStorageInfo,
  listBooks,
  getBook,
  createPublicAnnotation,
  createAnnotationComment,
  createResonance,
  borrowBook,
};
