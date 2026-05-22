const { query } = require('../config/db');

function shapeAnnotation(row) {
  return {
    id: row.id,
    entry_id: row.entry_id,
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
    created_at: row.created_at,
  };
}

async function publishEntries(userId, entryIds) {
  const result = await query(
    `INSERT INTO public_annotations (
       entry_id,
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
       e.user_id,
       e.source,
       e.book_id,
       e.book_title,
       COALESCE(
         NULLIF(e.metadata_json->>'book_author', ''),
         NULLIF(e.metadata_json->>'author', ''),
         '未知作者'
       ) AS book_author,
       COALESCE(
         NULLIF(e.metadata_json->>'book_cover', ''),
         NULLIF(e.metadata_json->>'cover_path', ''),
         NULLIF(e.metadata_json->>'coverPath', ''),
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
     WHERE e.user_id = $1
       AND e.id = ANY($2::uuid[])
     ON CONFLICT (entry_id) DO UPDATE SET
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
       created_at`,
    [userId, entryIds],
  );

  return result.rows.map(shapeAnnotation);
}

async function listFeed({ limit = 50 } = {}) {
  const result = await query(
    `SELECT
       id,
       entry_id,
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
       created_at
     FROM public_annotations
     ORDER BY created_at DESC
     LIMIT $1`,
    [limit],
  );

  return result.rows.map(shapeAnnotation);
}

module.exports = {
  publishEntries,
  listFeed,
};
