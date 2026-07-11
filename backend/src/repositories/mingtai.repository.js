const { query, withTransaction } = require('../config/db');

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
    authoritative_description: row.authoritative_description || '',
    authoritative_description_source: row.authoritative_description_source || '',
    authoritative_description_url: row.authoritative_description_url || '',
    one_line_summary: row.one_line_summary || '',
    one_line_summary_source: row.one_line_summary_source || '',
    encounter_summary: row.encounter_summary || '',
    expanded_guide: row.expanded_guide || '',
    why_worth_reading: row.why_worth_reading || '',
    reading_themes: normalizeTextArray(row.reading_themes),
    summary_updated_at: row.summary_updated_at || null,
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

function normalizeTextArray(value) {
  if (Array.isArray(value)) {
    return value.map((item) => String(item || '').trim()).filter(Boolean);
  }
  if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value);
      return normalizeTextArray(parsed);
    } catch (_) {
      return value.split(/[、,，/|]/).map((item) => item.trim()).filter(Boolean);
    }
  }
  return [];
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

function nicknameFromEmail(email) {
  return String(email || '').split('@')[0] || '知读读者';
}

function shapeUserProfile(row = {}) {
  return {
    user_id: row.user_id || row.id || '',
    nickname: row.nickname || nicknameFromEmail(row.email),
    avatar_url: row.avatar_url || '',
    bio: row.bio || '',
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
  };
}

function shapeBookReview(row = {}) {
  return {
    id: row.id || '',
    public_book_id: row.public_book_id || '',
    book_title: row.book_title || '',
    book_author: row.book_author || '',
    book_cover: row.book_cover || '',
    user_id: row.user_id || '',
    user: shapeUserProfile({
      user_id: row.user_id,
      email: row.email,
      nickname: row.nickname,
      avatar_url: row.avatar_url,
      bio: row.bio,
    }),
    content: row.content || '',
    resonance_count: Number(row.resonance_count || 0),
    comment_count: Number(row.comment_count || 0),
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

function shapeInteractionComment(row = {}) {
  return {
    id: row.id || '',
    target_id: row.target_id || row.annotation_id || row.review_id || '',
    content: row.content || '',
    user: shapeUserProfile({
      user_id: row.user_id,
      email: row.email,
      nickname: row.nickname,
      avatar_url: row.avatar_url,
      bio: row.bio,
    }),
    created_at: row.created_at,
  };
}

function shapeNotification(row = {}) {
  return {
    id: row.id || '',
    event_type: row.event_type || '',
    target_type: row.target_type || '',
    target_id: row.target_id || '',
    public_book_id: row.public_book_id || '',
    book_title: row.book_title || '',
    book_author: row.book_author || '',
    book_cover: row.book_cover || '',
    preview: row.preview || '',
    actor: shapeUserProfile({
      user_id: row.actor_user_id,
      email: row.actor_email,
      nickname: row.actor_nickname,
      avatar_url: row.actor_avatar_url,
      bio: row.actor_bio,
    }),
    read_at: row.read_at || null,
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

async function upsertPublicBook(userId, payload, queryFn = query) {
  const metadata = normalizeMetadata(payload.metadata_json);
  const title = safeTitle(payload.title);
  const author = safeAuthor(payload.author);
  const result = await queryFn(
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
       authoritative_description,
       authoritative_description_source,
       authoritative_description_url,
       one_line_summary,
       one_line_summary_source,
       encounter_summary,
       expanded_guide,
       why_worth_reading,
       reading_themes,
       summary_updated_at,
       copyright_status,
       metadata_json
     )
     VALUES ($1, $1, $2, $3, $4, $5, $6, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20::jsonb, now(), $21, $22)
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
       authoritative_description = EXCLUDED.authoritative_description,
       authoritative_description_source = EXCLUDED.authoritative_description_source,
       authoritative_description_url = EXCLUDED.authoritative_description_url,
       one_line_summary = EXCLUDED.one_line_summary,
       one_line_summary_source = EXCLUDED.one_line_summary_source,
       encounter_summary = EXCLUDED.encounter_summary,
       expanded_guide = EXCLUDED.expanded_guide,
       why_worth_reading = EXCLUDED.why_worth_reading,
       reading_themes = EXCLUDED.reading_themes,
       summary_updated_at = EXCLUDED.summary_updated_at,
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
       authoritative_description,
       authoritative_description_source,
       authoritative_description_url,
       one_line_summary,
       one_line_summary_source,
       encounter_summary,
       expanded_guide,
       why_worth_reading,
       reading_themes,
       summary_updated_at,
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
      payload.authoritative_description || null,
      payload.authoritative_description_source || null,
      payload.authoritative_description_url || null,
      payload.one_line_summary || null,
      payload.one_line_summary_source || null,
      payload.encounter_summary || null,
      payload.expanded_guide || null,
      payload.why_worth_reading || null,
      JSON.stringify(payload.reading_themes || []),
      payload.copyright_status,
      metadata,
    ],
  );

  const book = shapeBook(result.rows[0]);
  await syncBookPublicationSideTables(userId, payload, book, queryFn);
  return book;
}

async function syncBookPublicationSideTables(
  userId,
  payload,
  publicBook,
  queryFn = query,
) {
  const metadata = normalizeMetadata(payload.metadata_json);
  const title = safeTitle(payload.title);
  const author = safeAuthor(payload.author);
  await queryFn(
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

async function publishBook(userId, payload, chapters = []) {
  return withTransaction(async (queryFn) => {
    const book = await upsertPublicBook(userId, payload, queryFn);
    const cachedBook = await replaceBookChapters(book.id, chapters, queryFn);
    const entryIds = Array.isArray(payload.entry_ids) ? payload.entry_ids : [];
    const annotations = entryIds.length > 0
      ? await publishEntries(userId, entryIds, book.id, queryFn)
      : [];

    return {
      book: {
        ...(cachedBook || book),
        annotation_count: annotations.length,
      },
      annotations,
    };
  });
}

async function replaceBookChapters(publicBookId, chapters, queryFn = query) {
  const normalizedChapters = Array.isArray(chapters) ? chapters : [];

  await queryFn('DELETE FROM book_chapters WHERE public_book_id = $1', [publicBookId]);

  const chapterRows = normalizedChapters.map((chapter) => {
    const index = Number(chapter.chapter_index || 0);
    const chapterTitle = String(chapter.title || chapter.chapter_title || '').trim() ||
      `第${index + 1}章`;
    const contentHtml = String(chapter.content || chapter.content_html || '');
    const contentText = String(chapter.plain_text || chapter.content_text || '');
    return {
      chapter_index: index,
      chapter_title: chapterTitle,
      content_html: contentHtml,
      content_text: contentText,
      word_count: countWords(contentText),
      href: String(chapter.href || ''),
    };
  });

  if (chapterRows.length > 0) {
    await queryFn(
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
       SELECT
         $1,
         $1,
         chapter.chapter_index,
         chapter.chapter_title,
         chapter.chapter_title,
         chapter.content_html,
         chapter.content_html,
         chapter.content_text,
         chapter.content_text,
         chapter.word_count,
         chapter.href
       FROM jsonb_to_recordset($2::jsonb) AS chapter(
         chapter_index INTEGER,
         chapter_title TEXT,
         content_html TEXT,
         content_text TEXT,
         word_count INTEGER,
         href TEXT
       )
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
      [publicBookId, JSON.stringify(chapterRows)],
    );
  }

  const result = await queryFn(
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
       authoritative_description,
       authoritative_description_source,
       authoritative_description_url,
       one_line_summary,
       one_line_summary_source,
       encounter_summary,
       expanded_guide,
       why_worth_reading,
       reading_themes,
       summary_updated_at,
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
       ${includeContent
        ? "COALESCE(content_text, plain_text, '') AS content_text, COALESCE(content_text, plain_text, '') AS plain_text,"
        : "'' AS content_text, '' AS plain_text,"}
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

async function listBookIntroChapters(publicBookId, { limit = 3 } = {}) {
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
     ORDER BY chapter_index ASC
     LIMIT $2`,
    [publicBookId, limit],
  );

  return result.rows.map((row) => shapeChapter(row, { includeContent: true }));
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

async function publishEntries(userId, entryIds, publicBookId = null, queryFn = query) {
  const result = await queryFn(
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
       AND e.source IN ('thought', 'manual')
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
    const qRef = `$${values.length}`;
    where.push(`(
      b.title ILIKE ${qRef}
      OR b.author ILIKE ${qRef}
      OR b.description ILIKE ${qRef}
      OR b.one_line_summary ILIKE ${qRef}
      OR b.expanded_guide ILIKE ${qRef}
      OR EXISTS (
        SELECT 1
        FROM book_chapters c
        WHERE c.public_book_id = b.id
          AND (
            c.chapter_title ILIKE ${qRef}
            OR c.content_text ILIKE ${qRef}
            OR c.content_html ILIKE ${qRef}
          )
      )
      OR EXISTS (
        SELECT 1
        FROM public_annotations pa
        WHERE pa.public_book_id = b.id
          AND (
            pa.original_text ILIKE ${qRef}
            OR pa.annotation_text ILIKE ${qRef}
          )
      )
      OR EXISTS (
        SELECT 1
        FROM book_reviews br
        WHERE br.public_book_id = b.id
          AND br.content ILIKE ${qRef}
      )
    )`);
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
      : section === 'reading'
        ? 'CASE WHEN b.read_count > 0 THEN 0 ELSE 1 END, b.updated_at DESC, b.created_at DESC'
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
       b.authoritative_description,
       b.authoritative_description_source,
       b.authoritative_description_url,
       b.one_line_summary,
       b.one_line_summary_source,
       b.encounter_summary,
       b.expanded_guide,
       b.why_worth_reading,
       b.reading_themes,
       b.summary_updated_at,
       b.copyright_status,
       b.borrow_count,
       b.read_count,
       GREATEST(b.read_count, b.borrow_count) AS reading_count,
       (
         SELECT COUNT(*)
         FROM public_annotations a
         WHERE a.public_book_id = b.id
       ) AS annotation_count,
       GREATEST(
         (
           SELECT COUNT(*)
           FROM resonances r
           INNER JOIN public_annotations a ON a.id = r.annotation_id
           WHERE a.public_book_id = b.id
         ),
         (
           SELECT COUNT(*)
           FROM annotation_resonances ar
           INNER JOIN public_annotations a ON a.id = ar.annotation_id
           WHERE a.public_book_id = b.id
         ),
         (
           SELECT COUNT(*)
           FROM book_discussions d
           WHERE d.public_book_id = b.id
         ),
         (
           SELECT COUNT(*)
           FROM annotation_comments c
           INNER JOIN public_annotations a ON a.id = c.annotation_id
           WHERE a.public_book_id = b.id
         )
       ) AS recent_discussion_count,
       b.created_at,
       b.updated_at
     FROM public_books b
     ${whereSql}
     ORDER BY ${orderSql}
     LIMIT ${limitRef}`,
    values,
  );

  return result.rows.map(shapeBook);
}

async function getHome() {
  const [encounterPool, recentThoughts, latestBooks] = await Promise.all([
    listEncounterMoments({ limit: 12 }),
    listRecentThoughts({ limit: 4 }),
    listBooks({ limit: 6 }),
  ]);

  return {
    today_page: encounterPool[0] || null,
    encounter_pool: encounterPool,
    recent_thoughts: recentThoughts,
    recent_discussions: [],
    reading_now: [],
    latest_books: latestBooks,
  };
}

async function getTodayPage() {
  const annotationResult = await query(
    `SELECT
       a.id,
       a.public_book_id,
       a.source,
       COALESCE(NULLIF(a.annotation_text, ''), NULLIF(a.original_text, '')) AS original_text,
       a.annotation_text,
       a.chapter_index,
       a.chapter_title,
       b.title AS book_title,
       b.author AS book_author,
       b.cover_url AS book_cover,
       b.one_line_summary AS book_one_line_summary,
       a.created_at
     FROM public_annotations a
     INNER JOIN public_books b ON b.id = a.public_book_id
     WHERE COALESCE(NULLIF(a.original_text, ''), NULLIF(a.annotation_text, '')) IS NOT NULL
     ORDER BY md5(a.id::text || CURRENT_DATE::text)
     LIMIT 1`,
  );
  if (annotationResult.rows[0]) {
    return shapePageMoment(annotationResult.rows[0]);
  }

  const chapterResult = await query(
    `SELECT
       c.id,
       c.public_book_id,
       'excerpt' AS source,
       LEFT(COALESCE(NULLIF(c.content_text, ''), NULLIF(c.plain_text, '')), 320) AS original_text,
       '' AS annotation_text,
       c.chapter_index::text,
       COALESCE(c.chapter_title, c.title, '') AS chapter_title,
       b.title AS book_title,
       b.author AS book_author,
       b.cover_url AS book_cover,
       b.one_line_summary AS book_one_line_summary,
       c.created_at
     FROM book_chapters c
     INNER JOIN public_books b ON b.id = c.public_book_id
     WHERE COALESCE(NULLIF(c.content_text, ''), NULLIF(c.plain_text, '')) IS NOT NULL
     ORDER BY md5(c.id::text || CURRENT_DATE::text)
     LIMIT 1`,
  );
  return chapterResult.rows[0] ? shapePageMoment(chapterResult.rows[0]) : null;
}

async function listEncounterMoments({ limit = 12 } = {}) {
  const annotationLimit = Math.max(1, Math.ceil(limit / 2));
  const chapterLimit = Math.max(1, limit - annotationLimit);
  const [annotationResult, chapterResult] = await Promise.all([
    query(
      `SELECT
         a.id,
         a.public_book_id,
         a.source,
         COALESCE(NULLIF(a.annotation_text, ''), NULLIF(a.original_text, '')) AS original_text,
         a.annotation_text,
         a.chapter_index,
         a.chapter_title,
         b.title AS book_title,
         b.author AS book_author,
         b.cover_url AS book_cover,
         b.one_line_summary AS book_one_line_summary,
         a.created_at
       FROM public_annotations a
       INNER JOIN public_books b ON b.id = a.public_book_id
       WHERE a.source IN ('thought', 'manual')
         AND COALESCE(NULLIF(a.annotation_text, ''), NULLIF(a.original_text, '')) IS NOT NULL
       ORDER BY md5(a.id::text || CURRENT_DATE::text)
       LIMIT $1`,
      [annotationLimit],
    ),
    query(
      `SELECT
         c.id,
         c.public_book_id,
         'excerpt' AS source,
         LEFT(COALESCE(NULLIF(c.content_text, ''), NULLIF(c.plain_text, '')), 320) AS original_text,
         '' AS annotation_text,
         c.chapter_index::text,
         COALESCE(c.chapter_title, c.title, '') AS chapter_title,
         b.title AS book_title,
         b.author AS book_author,
         b.cover_url AS book_cover,
         b.one_line_summary AS book_one_line_summary,
         c.created_at
       FROM book_chapters c
       INNER JOIN public_books b ON b.id = c.public_book_id
       WHERE COALESCE(NULLIF(c.content_text, ''), NULLIF(c.plain_text, '')) IS NOT NULL
       ORDER BY md5(c.id::text || CURRENT_DATE::text)
       LIMIT $1`,
      [chapterLimit],
    ),
  ]);

  return [...annotationResult.rows, ...chapterResult.rows]
    .map(shapePageMoment)
    .filter((moment) => moment.public_book_id && moment.text)
    .slice(0, limit);
}

async function listRecentThoughts({ limit = 4 } = {}) {
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
       0 AS resonance_count,
       0 AS comment_count,
       a.created_at
     FROM public_annotations a
     WHERE a.source = 'thought'
       AND NULLIF(a.annotation_text, '') IS NOT NULL
     ORDER BY a.created_at DESC
     LIMIT $1`,
    [limit],
  );
  return result.rows.map(shapeAnnotation);
}

async function listRecentDiscussions({ limit = 4 } = {}) {
  const result = await query(
    `SELECT DISTINCT ON (b.id)
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
       b.authoritative_description,
       b.authoritative_description_source,
       b.authoritative_description_url,
       b.one_line_summary,
       b.one_line_summary_source,
       b.encounter_summary,
       b.expanded_guide,
       b.why_worth_reading,
       b.reading_themes,
       b.summary_updated_at,
       b.copyright_status,
       b.borrow_count,
       b.read_count,
       a.source AS latest_source,
       COALESCE(NULLIF(a.annotation_text, ''), NULLIF(a.original_text, '')) AS latest_excerpt,
       a.created_at AS activity_at,
       b.created_at,
       b.updated_at
     FROM public_books b
     INNER JOIN public_annotations a ON a.public_book_id = b.id
     WHERE a.source IN ('thought', 'manual')
       AND COALESCE(NULLIF(a.annotation_text, ''), NULLIF(a.original_text, '')) IS NOT NULL
     ORDER BY b.id, a.created_at DESC`,
  );

  return result.rows
    .sort((a, b) => new Date(b.activity_at) - new Date(a.activity_at))
    .slice(0, limit)
    .map((row) => ({
      book: shapeBook(row),
      excerpt: row.latest_excerpt || '',
      source: row.latest_source || '',
      activity_at: row.activity_at,
    }));
}

function shapePageMoment(row) {
  return {
    id: row.id,
    public_book_id: row.public_book_id,
    source: row.source || 'excerpt',
    text: row.original_text || row.annotation_text || '',
    annotation_text: row.annotation_text || '',
    chapter_index: row.chapter_index || '',
    chapter_title: row.chapter_title || '',
    book_title: safeTitle(row.book_title),
    book_author: safeAuthor(row.book_author),
    book_cover: row.book_cover || '',
    book_one_line_summary: row.book_one_line_summary || '',
    created_at: row.created_at,
  };
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
       b.authoritative_description,
       b.authoritative_description_source,
       b.authoritative_description_url,
       b.one_line_summary,
       b.one_line_summary_source,
       b.encounter_summary,
       b.expanded_guide,
       b.why_worth_reading,
       b.reading_themes,
       b.summary_updated_at,
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

async function updateBookIntroduction(publicBookId, introduction, queryFn = query) {
  const result = await queryFn(
    `UPDATE public_books
     SET description = COALESCE(NULLIF($2, ''), description),
         authoritative_description = NULLIF($3, ''),
         authoritative_description_source = NULLIF($4, ''),
         authoritative_description_url = NULLIF($5, ''),
         one_line_summary = NULLIF($6, ''),
         one_line_summary_source = NULLIF($7, ''),
         encounter_summary = NULLIF($8, ''),
         expanded_guide = NULLIF($9, ''),
         why_worth_reading = NULLIF($10, ''),
         reading_themes = $11::jsonb,
         summary_updated_at = now(),
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
       authoritative_description,
       authoritative_description_source,
       authoritative_description_url,
       one_line_summary,
       one_line_summary_source,
       encounter_summary,
       expanded_guide,
       why_worth_reading,
       reading_themes,
       summary_updated_at,
       copyright_status,
       borrow_count,
       read_count,
       GREATEST(read_count, borrow_count) AS reading_count,
       0 AS annotation_count,
       0 AS recent_discussion_count,
       created_at,
       updated_at`,
    [
      publicBookId,
      introduction.description || '',
      introduction.authoritative_description || '',
      introduction.authoritative_description_source || '',
      introduction.authoritative_description_url || '',
      introduction.one_line_summary || '',
      introduction.one_line_summary_source || '',
      introduction.encounter_summary || '',
      introduction.expanded_guide || '',
      introduction.why_worth_reading || '',
      JSON.stringify(introduction.reading_themes || []),
    ],
  );

  return result.rows[0] ? shapeBook(result.rows[0]) : null;
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
       SELECT id, public_book_id, original_text, user_id AS recipient_user_id
       FROM public_annotations
       WHERE id = $1
     ),
     created AS (
       INSERT INTO annotation_comments (annotation_id, user_id, content)
       SELECT id, $2, $3
       FROM target
       RETURNING id, annotation_id, user_id, content, created_at
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
     ),
     notification AS (
       INSERT INTO notifications (
         recipient_user_id,
         actor_user_id,
         event_type,
         target_type,
         target_id,
         public_book_id,
         preview
       )
       SELECT
         target.recipient_user_id,
         $2,
         'annotation_comment',
         'annotation',
         target.id,
         target.public_book_id,
         LEFT($3, 180)
       FROM target
       WHERE target.recipient_user_id <> $2
       RETURNING id
     )
     SELECT
       created.id,
       created.annotation_id AS target_id,
       created.user_id,
       u.email,
       p.nickname,
       p.avatar_url,
       p.bio,
       created.content,
       created.created_at
     FROM created
     INNER JOIN users u ON u.id = created.user_id
     LEFT JOIN user_profiles p ON p.user_id = created.user_id`,
    [annotationId, userId, content],
  );

  return result.rows[0] ? shapeInteractionComment(result.rows[0]) : null;
}

async function listAnnotationComments(annotationId, { limit = 50 } = {}) {
  const result = await query(
    `SELECT
       c.id,
       c.annotation_id AS target_id,
       c.user_id,
       u.email,
       p.nickname,
       p.avatar_url,
       p.bio,
       c.content,
       c.created_at
     FROM annotation_comments c
     INNER JOIN users u ON u.id = c.user_id
     LEFT JOIN user_profiles p ON p.user_id = c.user_id
     WHERE c.annotation_id = $1
     ORDER BY c.created_at ASC
     LIMIT $2`,
    [annotationId, limit],
  );

  return result.rows.map(shapeInteractionComment);
}

async function createResonance(userId, annotationId, content = '') {
  const target = await query(
    `SELECT id, user_id AS recipient_user_id, public_book_id
     FROM public_annotations
     WHERE id = $1
     LIMIT 1`,
    [annotationId],
  );
  if (target.rows.length === 0) return null;

  const inserted = await query(
    `INSERT INTO annotation_resonances (annotation_id, user_id)
     VALUES ($1, $2)
     ON CONFLICT (annotation_id, user_id) DO NOTHING
     RETURNING id`,
    [annotationId, userId],
  );

  const targetRow = target.rows[0];
  if (inserted.rowCount > 0 && targetRow.recipient_user_id !== userId) {
    await query(
      `INSERT INTO notifications (
         recipient_user_id,
         actor_user_id,
         event_type,
         target_type,
         target_id,
         public_book_id,
         preview
       )
       VALUES ($1, $2, 'annotation_resonance', 'annotation', $3, $4, '')
       ON CONFLICT DO NOTHING`,
      [targetRow.recipient_user_id, userId, annotationId, targetRow.public_book_id],
    );
  }

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
       authoritative_description,
       authoritative_description_source,
       authoritative_description_url,
       one_line_summary,
       one_line_summary_source,
       encounter_summary,
       expanded_guide,
       why_worth_reading,
       reading_themes,
       summary_updated_at,
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

async function recordBookRead(publicBookId) {
  const result = await query(
    `UPDATE public_books
     SET read_count = read_count + 1,
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
       authoritative_description,
       authoritative_description_source,
       authoritative_description_url,
       one_line_summary,
       one_line_summary_source,
       encounter_summary,
       expanded_guide,
       why_worth_reading,
       reading_themes,
       summary_updated_at,
       copyright_status,
       borrow_count,
       read_count,
       read_count AS reading_count,
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

async function getMyProfile(userId) {
  await query(
    `INSERT INTO user_profiles (user_id, nickname)
     SELECT id, split_part(email, '@', 1)
     FROM users
     WHERE id = $1
     ON CONFLICT (user_id) DO NOTHING`,
    [userId],
  );

  const result = await query(
    `SELECT
       u.id AS user_id,
       u.email,
       p.nickname,
       p.avatar_url,
       p.bio,
       p.created_at,
       p.updated_at
     FROM users u
     LEFT JOIN user_profiles p ON p.user_id = u.id
     WHERE u.id = $1
     LIMIT 1`,
    [userId],
  );
  return result.rows[0] ? shapeUserProfile(result.rows[0]) : null;
}

async function updateMyProfile(userId, payload) {
  const nickname = String(payload.nickname || '').trim().slice(0, 32);
  const avatarUrl = String(payload.avatar_url || '').trim().slice(0, 500);
  const bio = String(payload.bio || '').trim().slice(0, 80);

  const result = await query(
    `INSERT INTO user_profiles (user_id, nickname, avatar_url, bio)
     SELECT $1, COALESCE(NULLIF($2, ''), split_part(email, '@', 1)), $3, $4
     FROM users
     WHERE id = $1
     ON CONFLICT (user_id) DO UPDATE SET
       nickname = COALESCE(NULLIF(EXCLUDED.nickname, ''), user_profiles.nickname),
       avatar_url = EXCLUDED.avatar_url,
       bio = EXCLUDED.bio,
       updated_at = now()
     RETURNING user_id, nickname, avatar_url, bio, created_at, updated_at`,
    [userId, nickname, avatarUrl, bio],
  );

  return result.rows[0] ? shapeUserProfile(result.rows[0]) : null;
}

async function listBookReviews(publicBookId, { limit = 20 } = {}) {
  const result = await query(
    `SELECT
       r.id,
       r.public_book_id,
       b.title AS book_title,
       b.author AS book_author,
       b.cover_url AS book_cover,
       r.user_id,
       u.email,
       p.nickname,
       p.avatar_url,
       p.bio,
       r.content,
       (SELECT COUNT(*) FROM book_review_resonances rr WHERE rr.review_id = r.id) AS resonance_count,
       (SELECT COUNT(*) FROM book_review_comments rc WHERE rc.review_id = r.id) AS comment_count,
       r.created_at,
       r.updated_at
     FROM book_reviews r
     INNER JOIN public_books b ON b.id = r.public_book_id
     INNER JOIN users u ON u.id = r.user_id
     LEFT JOIN user_profiles p ON p.user_id = r.user_id
     WHERE r.public_book_id = $1
     ORDER BY r.created_at DESC
     LIMIT $2`,
    [publicBookId, limit],
  );

  return result.rows.map(shapeBookReview);
}

async function createBookReview(userId, publicBookId, content, clientRequestId = null) {
  const result = await query(
    `WITH book AS (
       SELECT id
       FROM public_books
       WHERE id = $2
     ),
     profile AS (
       INSERT INTO user_profiles (user_id, nickname)
       SELECT id, split_part(email, '@', 1)
       FROM users
       WHERE id = $1
       ON CONFLICT (user_id) DO NOTHING
     ),
     created AS (
       INSERT INTO book_reviews (
         public_book_id,
         user_id,
         client_request_id,
         content
       )
       SELECT book.id, $1, NULLIF($4, ''), $3
       FROM book
       ON CONFLICT (user_id, client_request_id)
       WHERE client_request_id IS NOT NULL
       DO UPDATE SET content = EXCLUDED.content
       RETURNING id
     )
     SELECT
       r.id,
       r.public_book_id,
       b.title AS book_title,
       b.author AS book_author,
       b.cover_url AS book_cover,
       r.user_id,
       u.email,
       p.nickname,
       p.avatar_url,
       p.bio,
       r.content,
       (SELECT COUNT(*) FROM book_review_resonances rr WHERE rr.review_id = r.id) AS resonance_count,
       (SELECT COUNT(*) FROM book_review_comments rc WHERE rc.review_id = r.id) AS comment_count,
       r.created_at,
       r.updated_at
     FROM book_reviews r
     INNER JOIN created c ON c.id = r.id
     INNER JOIN public_books b ON b.id = r.public_book_id
     INNER JOIN users u ON u.id = r.user_id
     LEFT JOIN user_profiles p ON p.user_id = r.user_id`,
    [userId, publicBookId, content, String(clientRequestId || '').trim()],
  );

  return result.rows[0] ? shapeBookReview(result.rows[0]) : null;
}

async function updateBookReview(userId, reviewId, content) {
  const result = await query(
    `WITH updated AS (
       UPDATE book_reviews
       SET content = $3,
           updated_at = now()
       WHERE id = $2 AND user_id = $1
       RETURNING *
     )
     SELECT
       r.id,
       r.public_book_id,
       b.title AS book_title,
       b.author AS book_author,
       b.cover_url AS book_cover,
       r.user_id,
       u.email,
       p.nickname,
       p.avatar_url,
       p.bio,
       r.content,
       (SELECT COUNT(*) FROM book_review_resonances rr WHERE rr.review_id = r.id) AS resonance_count,
       (SELECT COUNT(*) FROM book_review_comments rc WHERE rc.review_id = r.id) AS comment_count,
       r.created_at,
       r.updated_at
     FROM updated r
     INNER JOIN public_books b ON b.id = r.public_book_id
     INNER JOIN users u ON u.id = r.user_id
     LEFT JOIN user_profiles p ON p.user_id = r.user_id`,
    [userId, reviewId, content],
  );

  return result.rows[0] ? shapeBookReview(result.rows[0]) : null;
}

async function deleteBookReview(userId, reviewId) {
  const result = await query(
    `DELETE FROM book_reviews
     WHERE id = $2 AND user_id = $1
     RETURNING id`,
    [userId, reviewId],
  );

  return result.rowCount > 0;
}

async function listBookReviewComments(reviewId, { limit = 50 } = {}) {
  const result = await query(
    `SELECT
       c.id,
       c.review_id AS target_id,
       c.user_id,
       u.email,
       p.nickname,
       p.avatar_url,
       p.bio,
       c.content,
       c.created_at
     FROM book_review_comments c
     INNER JOIN users u ON u.id = c.user_id
     LEFT JOIN user_profiles p ON p.user_id = c.user_id
     WHERE c.review_id = $1
     ORDER BY c.created_at ASC
     LIMIT $2`,
    [reviewId, limit],
  );

  return result.rows.map(shapeInteractionComment);
}

async function createBookReviewComment(userId, reviewId, content) {
  const result = await query(
    `WITH target AS (
       SELECT id, public_book_id, user_id AS recipient_user_id
       FROM book_reviews
       WHERE id = $1
     ),
     created AS (
       INSERT INTO book_review_comments (review_id, user_id, content)
       SELECT target.id, $2, $3
       FROM target
       RETURNING id, review_id, user_id, content, created_at
     ),
     notification AS (
       INSERT INTO notifications (
         recipient_user_id,
         actor_user_id,
         event_type,
         target_type,
         target_id,
         public_book_id,
         preview
       )
       SELECT
         target.recipient_user_id,
         $2,
         'review_comment',
         'review',
         target.id,
         target.public_book_id,
         LEFT($3, 180)
       FROM target
       WHERE target.recipient_user_id <> $2
       RETURNING id
     )
     SELECT
       created.id,
       created.review_id AS target_id,
       created.user_id,
       u.email,
       p.nickname,
       p.avatar_url,
       p.bio,
       created.content,
       created.created_at
     FROM created
     INNER JOIN users u ON u.id = created.user_id
     LEFT JOIN user_profiles p ON p.user_id = created.user_id`,
    [reviewId, userId, content],
  );

  return result.rows[0] ? shapeInteractionComment(result.rows[0]) : null;
}

async function createBookReviewResonance(userId, reviewId) {
  const target = await query(
    `SELECT id, public_book_id, user_id AS recipient_user_id
     FROM book_reviews
     WHERE id = $1
     LIMIT 1`,
    [reviewId],
  );
  if (target.rows.length === 0) return null;

  const inserted = await query(
    `INSERT INTO book_review_resonances (review_id, user_id)
     VALUES ($1, $2)
     ON CONFLICT (review_id, user_id) DO NOTHING
     RETURNING id`,
    [reviewId, userId],
  );

  const targetRow = target.rows[0];
  if (inserted.rowCount > 0 && targetRow.recipient_user_id !== userId) {
    await query(
      `INSERT INTO notifications (
         recipient_user_id,
         actor_user_id,
         event_type,
         target_type,
         target_id,
         public_book_id,
         preview
       )
       VALUES ($1, $2, 'review_resonance', 'review', $3, $4, '')
       ON CONFLICT DO NOTHING`,
      [targetRow.recipient_user_id, userId, reviewId, targetRow.public_book_id],
    );
  }

  const countResult = await query(
    `SELECT COUNT(*) AS resonance_count
     FROM book_review_resonances
     WHERE review_id = $1`,
    [reviewId],
  );

  return {
    review_id: reviewId,
    resonance_count: Number(countResult.rows[0]?.resonance_count || 0),
  };
}

async function listNotifications(userId, { limit = 50 } = {}) {
  const result = await query(
    `SELECT
       n.id,
       n.event_type,
       n.target_type,
       n.target_id,
       n.public_book_id,
       n.preview,
       n.read_at,
       n.created_at,
       actor.id AS actor_user_id,
       actor.email AS actor_email,
       profile.nickname AS actor_nickname,
       profile.avatar_url AS actor_avatar_url,
       profile.bio AS actor_bio,
       book.title AS book_title,
       book.author AS book_author,
       book.cover_url AS book_cover
     FROM notifications n
     INNER JOIN users actor ON actor.id = n.actor_user_id
     LEFT JOIN user_profiles profile ON profile.user_id = actor.id
     LEFT JOIN public_books book ON book.id = n.public_book_id
     WHERE n.recipient_user_id = $1
     ORDER BY n.created_at DESC
     LIMIT $2`,
    [userId, limit],
  );

  return result.rows.map(shapeNotification);
}

async function countUnreadNotifications(userId) {
  const result = await query(
    `SELECT COUNT(*) AS unread_count
     FROM notifications
     WHERE recipient_user_id = $1 AND read_at IS NULL`,
    [userId],
  );
  return Number(result.rows[0]?.unread_count || 0);
}

async function markNotificationRead(userId, notificationId) {
  const result = await query(
    `UPDATE notifications
     SET read_at = COALESCE(read_at, now())
     WHERE id = $2 AND recipient_user_id = $1
     RETURNING id`,
    [userId, notificationId],
  );
  return result.rowCount > 0;
}

async function markAllNotificationsRead(userId) {
  const result = await query(
    `UPDATE notifications
     SET read_at = now()
     WHERE recipient_user_id = $1 AND read_at IS NULL
     RETURNING id`,
    [userId],
  );
  return result.rowCount;
}

async function getPublicProfile(userId) {
  const [profileResult, reviewResult, annotationResult, statsResult, recentBooksResult] =
    await Promise.all([
      query(
        `SELECT
           u.id AS user_id,
           u.email,
           p.nickname,
           p.avatar_url,
           p.bio,
           p.created_at,
           p.updated_at
         FROM users u
         LEFT JOIN user_profiles p ON p.user_id = u.id
         WHERE u.id = $1
         LIMIT 1`,
        [userId],
      ),
      query(
        `SELECT
           r.id,
           r.public_book_id,
           b.title AS book_title,
           b.author AS book_author,
           b.cover_url AS book_cover,
           r.user_id,
           u.email,
           p.nickname,
           p.avatar_url,
           p.bio,
           r.content,
           (SELECT COUNT(*) FROM book_review_resonances rr WHERE rr.review_id = r.id) AS resonance_count,
           (SELECT COUNT(*) FROM book_review_comments rc WHERE rc.review_id = r.id) AS comment_count,
           r.created_at,
           r.updated_at
         FROM book_reviews r
         INNER JOIN public_books b ON b.id = r.public_book_id
         INNER JOIN users u ON u.id = r.user_id
         LEFT JOIN user_profiles p ON p.user_id = r.user_id
         WHERE r.user_id = $1
         ORDER BY r.created_at DESC
         LIMIT 30`,
        [userId],
      ),
      query(
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
           (SELECT COUNT(*) FROM annotation_resonances ar2 WHERE ar2.annotation_id = a.id) AS resonance_count,
           (SELECT COUNT(*) FROM annotation_comments ac WHERE ac.annotation_id = a.id) AS comment_count,
           a.created_at
         FROM public_annotations a
         WHERE a.user_id = $1
           AND a.source IN ('thought', 'manual', 'ai_explanation')
         ORDER BY a.created_at DESC
         LIMIT 30`,
        [userId],
      ),
      query(
        `SELECT
           COUNT(DISTINCT COALESCE(a.public_book_id, r.public_book_id)) AS public_books,
           COUNT(DISTINCT a.id) AS public_thoughts,
           COUNT(DISTINCT r.id) AS public_reviews,
           (
             COUNT(DISTINCT a.id) +
             COUNT(DISTINCT r.id) +
             COUNT(DISTINCT ar.annotation_id) +
             COUNT(DISTINCT br.id)
           ) AS mingtai_stops
         FROM users u
         LEFT JOIN public_annotations a ON a.user_id = u.id
         LEFT JOIN book_reviews r ON r.user_id = u.id
         LEFT JOIN annotation_resonances ar ON ar.user_id = u.id
         LEFT JOIN book_resonance br ON br.user_id = u.id
         WHERE u.id = $1`,
        [userId],
      ),
      query(
        `SELECT DISTINCT ON (b.id)
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
           b.authoritative_description,
           b.authoritative_description_source,
           b.authoritative_description_url,
           b.one_line_summary,
           b.one_line_summary_source,
           b.encounter_summary,
           b.expanded_guide,
           b.why_worth_reading,
           b.reading_themes,
           b.summary_updated_at,
           b.copyright_status,
           b.borrow_count,
           b.read_count,
           GREATEST(b.read_count, b.borrow_count) AS reading_count,
           0 AS annotation_count,
           0 AS recent_discussion_count,
           GREATEST(
             COALESCE(a.created_at, 'epoch'::timestamptz),
             COALESCE(r.created_at, 'epoch'::timestamptz)
           ) AS last_touch,
           b.created_at,
           b.updated_at
         FROM public_books b
         LEFT JOIN public_annotations a ON a.public_book_id = b.id AND a.user_id = $1
         LEFT JOIN book_reviews r ON r.public_book_id = b.id AND r.user_id = $1
         WHERE a.id IS NOT NULL OR r.id IS NOT NULL
         ORDER BY b.id, last_touch DESC
         LIMIT 12`,
        [userId],
      ),
    ]);

  if (profileResult.rows.length === 0) return null;

  return {
    profile: shapeUserProfile(profileResult.rows[0]),
    stats: {
      public_books: Number(statsResult.rows[0]?.public_books || 0),
      public_thoughts: Number(statsResult.rows[0]?.public_thoughts || 0),
      public_reviews: Number(statsResult.rows[0]?.public_reviews || 0),
      mingtai_stops: Number(statsResult.rows[0]?.mingtai_stops || 0),
    },
    recent_books: recentBooksResult.rows.map(shapeBook),
    reviews: reviewResult.rows.map(shapeBookReview),
    annotations: annotationResult.rows.map(shapeAnnotation),
  };
}

async function deletePublishedBooks(userId) {
  const result = await query(
    `DELETE FROM public_books
     WHERE publisher_user_id = $1
     RETURNING id, storage_path, cover_url`,
    [userId],
  );

  return result.rows.map((row) => ({
    id: row.id,
    storage_path: row.storage_path || '',
    cover_url: row.cover_url || '',
  }));
}

async function deletePublishedBook(userId, publicBookId) {
  const result = await query(
    `DELETE FROM public_books
     WHERE id = $2
       AND COALESCE(uploader_user_id, publisher_user_id) = $1
     RETURNING id, storage_path, cover_url`,
    [userId, publicBookId],
  );

  const row = result.rows[0];
  if (!row) return null;
  return {
    id: row.id,
    storage_path: row.storage_path || '',
    cover_url: row.cover_url || '',
  };
}

module.exports = {
  publishBook,
  publishEntries,
  replaceBookChapters,
  listBookChapters,
  listBookIntroChapters,
  getBookChapter,
  listBooks,
  getHome,
  getBook,
  updateBookIntroduction,
  createPublicAnnotation,
  listAnnotationComments,
  createAnnotationComment,
  createResonance,
  borrowBook,
  recordBookRead,
  getMyProfile,
  updateMyProfile,
  getPublicProfile,
  listBookReviews,
  createBookReview,
  updateBookReview,
  deleteBookReview,
  listBookReviewComments,
  createBookReviewComment,
  createBookReviewResonance,
  listNotifications,
  countUnreadNotifications,
  markNotificationRead,
  markAllNotificationsRead,
  deletePublishedBook,
  deletePublishedBooks,
};
