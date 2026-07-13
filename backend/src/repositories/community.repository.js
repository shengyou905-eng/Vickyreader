const { query, withTransaction } = require('../config/db');

function normalizeWorkKey(title, author) {
  return `${clean(title).toLowerCase()}::${clean(author || '佚名').toLowerCase()}`
    .replace(/\s+/g, ' ')
    .slice(0, 600);
}

function normalizeEditionKey(payload) {
  const isbn = clean(payload.isbn).replace(/[-\s]/g, '');
  if (isbn) return `isbn::${isbn.toLowerCase()}`;
  return [
    clean(payload.title),
    clean(payload.author || '佚名'),
    clean(payload.translator),
    clean(payload.publisher),
    clean(payload.edition_label),
    clean(payload.language),
  ].map((item) => item.toLowerCase()).join('::').slice(0, 900);
}

async function resolveBook(userId, payload) {
  const title = clean(payload.title);
  const author = clean(payload.author) || '佚名';
  const workKey = normalizeWorkKey(payload.work_title || title, payload.original_author || author);
  const normalizedKey = normalizeEditionKey({ ...payload, title, author });
  const workResult = await query(
    `INSERT INTO community_book_works (
       normalized_key, title, original_author, original_language, description
     ) VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (normalized_key) DO UPDATE SET
       description = CASE
         WHEN community_book_works.description = '' THEN EXCLUDED.description
         ELSE community_book_works.description
       END,
       updated_at = now()
     RETURNING id`,
    [
      workKey,
      clean(payload.work_title) || title,
      clean(payload.original_author) || author,
      clean(payload.original_language),
      clean(payload.description),
    ],
  );
  const result = await query(
    `INSERT INTO community_books (
       work_id, normalized_key, title, author, translator, publisher,
       publication_year, language, edition_label, cover_url, description, isbn,
       created_by_user_id, metadata_json
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14::jsonb)
     ON CONFLICT (normalized_key) DO UPDATE SET
       work_id = COALESCE(community_books.work_id, EXCLUDED.work_id),
       cover_url = CASE
         WHEN EXCLUDED.cover_url <> '' THEN EXCLUDED.cover_url
         ELSE community_books.cover_url
       END,
       description = CASE
         WHEN community_books.description = '' THEN EXCLUDED.description
         ELSE community_books.description
       END,
       isbn = CASE
         WHEN community_books.isbn = '' THEN EXCLUDED.isbn
         ELSE community_books.isbn
       END,
       metadata_json = community_books.metadata_json || EXCLUDED.metadata_json,
       updated_at = now()
     RETURNING *`,
    [
      workResult.rows[0].id,
      normalizedKey,
      title,
      author,
      clean(payload.translator),
      clean(payload.publisher),
      clean(payload.publication_year),
      clean(payload.language),
      clean(payload.edition_label),
      clean(payload.cover_url),
      clean(payload.description),
      clean(payload.isbn),
      userId,
      JSON.stringify(payload.metadata_json || {}),
    ],
  );
  return result.rows[0];
}

async function searchCommunity(search, viewerId, limit = 24) {
  const pattern = `%${clean(search)}%`;
  const [books, posts] = await Promise.all([
    query(
      `SELECT b.*,
         EXISTS (
           SELECT 1 FROM community_readable_assets a
           WHERE a.book_id = b.id AND a.active = true
         ) AS can_read,
         (SELECT COUNT(*)::int FROM community_book_states s
          WHERE s.book_id = b.id AND s.status = 'reading' AND s.visibility = 'public'
            AND COALESCE((SELECT show_reading_status FROM community_privacy_settings ps
                          WHERE ps.user_id = s.user_id), false) = true) AS reading_count,
         (SELECT COUNT(*)::int FROM community_book_states s
          WHERE s.book_id = b.id AND s.status = 'finished' AND s.visibility = 'public'
            AND COALESCE((SELECT show_reading_status FROM community_privacy_settings ps
                          WHERE ps.user_id = s.user_id), false) = true) AS finished_count,
         (SELECT COUNT(*)::int FROM community_posts p WHERE p.book_id = b.id) AS post_count
       FROM community_books b
       WHERE b.title ILIKE $1
          OR b.author ILIKE $1
          OR b.description ILIKE $1
          OR EXISTS (
            SELECT 1 FROM community_posts p
            WHERE p.book_id = b.id
              AND (p.content ILIKE $1 OR p.quoted_text ILIKE $1)
          )
       ORDER BY b.updated_at DESC
       LIMIT $2`,
      [pattern, limit],
    ),
    listPosts({ viewerId, search: clean(search), limit }),
  ]);
  return { books: books.rows, posts };
}

function postSelect(whereSql, orderSql = 'p.created_at DESC') {
  return `SELECT
      p.id, p.user_id, p.book_id, p.post_type, p.content, p.quoted_text,
      p.chapter_label, p.reading_position, p.reading_progress, p.visibility,
      p.source, p.source_entry_id, p.topic_tags, p.created_at, p.updated_at,
      b.title AS book_title, b.author AS book_author,
      b.cover_url AS book_cover_url,
      COALESCE(NULLIF(up.nickname, ''), split_part(u.email, '@', 1)) AS nickname,
      COALESCE(up.avatar_url, '') AS avatar_url,
      (SELECT COUNT(*)::int FROM community_post_comments c
       WHERE c.post_id = p.id AND c.moderation_status = 'published') AS comment_count,
      (SELECT COUNT(*)::int FROM community_post_resonances r WHERE r.post_id = p.id) AS resonance_count,
      (SELECT COUNT(*)::int FROM community_post_favorites f WHERE f.post_id = p.id) AS favorite_count,
      CASE WHEN $1::uuid IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM community_post_resonances r
        WHERE r.post_id = p.id AND r.user_id = $1::uuid
      ) END AS viewer_resonated
      ,CASE WHEN $1::uuid IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM community_post_favorites f
        WHERE f.post_id = p.id AND f.user_id = $1::uuid
      ) END AS viewer_favorited
    FROM community_posts p
    JOIN community_books b ON b.id = p.book_id
    JOIN users u ON u.id = p.user_id
    LEFT JOIN user_profiles up ON up.user_id = p.user_id
    ${whereSql}
    ORDER BY ${orderSql}
    LIMIT $2`;
}

async function listPosts({
  viewerId = null,
  tab = 'discover',
  bookId = null,
  postId = null,
  userId = null,
  search = '',
  limit = 30,
} = {}) {
  let whereSql = '';
  const conditions = [];
  const params = [viewerId, limit];
  const parameter = (value) => {
    params.push(value);
    return `$${params.length}`;
  };
  conditions.push("p.moderation_status = 'published'");
  conditions.push("p.visibility = 'public'");
  conditions.push(`NOT EXISTS (
    SELECT 1 FROM community_blocks cb
    WHERE $1::uuid IS NOT NULL
      AND ((cb.blocker_user_id = $1::uuid AND cb.blocked_user_id = p.user_id)
        OR (cb.blocked_user_id = $1::uuid AND cb.blocker_user_id = p.user_id))
  )`);
  if (postId) conditions.push(`p.id = ${parameter(postId)}::uuid`);
  if (bookId) conditions.push(`p.book_id = ${parameter(bookId)}::uuid`);
  if (userId) conditions.push(`p.user_id = ${parameter(userId)}::uuid`);
  if (search) {
    const searchParameter = parameter(`%${search}%`);
    conditions.push(`(
      p.content ILIKE ${searchParameter}
      OR p.quoted_text ILIKE ${searchParameter}
      OR b.title ILIKE ${searchParameter}
      OR b.author ILIKE ${searchParameter}
    )`);
  }
  let orderSql = 'p.created_at DESC';
  if (tab === 'discover' && !bookId && !postId && !userId && !search) {
    conditions.push("char_length(trim(p.content)) >= 8 AND trim(p.content) !~ '^[0-9]+$'");
    orderSql = `(
      CASE WHEN $1::uuid IS NOT NULL AND EXISTS (
        SELECT 1 FROM community_book_states s
        WHERE s.user_id = $1::uuid AND s.book_id = p.book_id
          AND s.status = 'reading'
      ) THEN 600 ELSE 0 END
      + CASE WHEN $1::uuid IS NOT NULL AND EXISTS (
        SELECT 1 FROM user_entries e
        WHERE e.user_id = $1::uuid
          AND lower(trim(e.book_title)) = lower(trim(b.title))
      ) THEN 360 ELSE 0 END
      + CASE WHEN $1::uuid IS NOT NULL AND EXISTS (
        SELECT 1 FROM community_post_favorites own_favorite
        JOIN community_posts related ON related.id = own_favorite.post_id
        WHERE own_favorite.user_id = $1::uuid AND related.book_id = p.book_id
      ) THEN 180 ELSE 0 END
      + CASE WHEN $1::uuid IS NOT NULL AND EXISTS (
        SELECT 1 FROM community_follows f
        WHERE f.follower_user_id = $1::uuid AND f.followed_user_id = p.user_id
      ) THEN 120 ELSE 0 END
      + LEAST(char_length(p.content), 300) / 15.0
      + (SELECT COUNT(*) FROM community_post_comments c
         WHERE c.post_id = p.id AND c.moderation_status = 'published') * 12
      + (SELECT COUNT(*) FROM community_post_favorites pf
         WHERE pf.post_id = p.id) * 10
    ) DESC, p.created_at DESC`;
  }
  if (tab === 'following') {
    conditions.push(`$1::uuid IS NOT NULL AND EXISTS (
      SELECT 1 FROM community_follows f
      WHERE f.follower_user_id = $1::uuid
        AND f.followed_user_id = p.user_id
    )`);
  } else if (tab === 'same_book') {
    conditions.push(`$1::uuid IS NOT NULL AND (
      EXISTS (
        SELECT 1 FROM community_book_states s
        WHERE s.user_id = $1::uuid
          AND s.book_id = p.book_id
          AND s.status IN ('reading', 'finished', 'want_to_read')
      )
      OR EXISTS (
        SELECT 1 FROM user_entries e
        WHERE e.user_id = $1::uuid
          AND e.book_title IS NOT NULL
          AND lower(trim(e.book_title)) = lower(trim(b.title))
      )
      OR EXISTS (
        SELECT 1 FROM community_posts interacted
        WHERE interacted.book_id = p.book_id
          AND (
            interacted.user_id = $1::uuid
            OR EXISTS (
              SELECT 1 FROM community_post_comments c
              WHERE c.post_id = interacted.id AND c.user_id = $1::uuid
            )
            OR EXISTS (
              SELECT 1 FROM community_post_resonances r
              WHERE r.post_id = interacted.id AND r.user_id = $1::uuid
            )
          )
      )
    )`);
  }
  if (conditions.length) whereSql = `WHERE ${conditions.join(' AND ')}`;
  const result = await query(postSelect(whereSql, orderSql), params);
  return result.rows;
}

async function listSuggestedReaders(viewerId, limit = 6) {
  const result = await query(
    `SELECT u.id AS user_id,
       COALESCE(NULLIF(up.nickname, ''), split_part(u.email, '@', 1)) AS nickname,
       COALESCE(up.avatar_url, '') AS avatar_url,
       COALESCE(up.bio, '') AS bio,
       COUNT(p.id)::text || ' 条公开阅读' AS status
     FROM users u
     LEFT JOIN user_profiles up ON up.user_id = u.id
     JOIN community_posts p
       ON p.user_id = u.id AND p.moderation_status = 'published'
     WHERE u.account_status = 'active'
       AND ($1::uuid IS NULL OR u.id <> $1::uuid)
       AND NOT EXISTS (
         SELECT 1 FROM community_follows f
         WHERE $1::uuid IS NOT NULL
           AND f.follower_user_id = $1::uuid
           AND f.followed_user_id = u.id
       )
       AND NOT EXISTS (
         SELECT 1 FROM community_blocks cb
         WHERE $1::uuid IS NOT NULL
           AND ((cb.blocker_user_id = $1::uuid AND cb.blocked_user_id = u.id)
             OR (cb.blocked_user_id = $1::uuid AND cb.blocker_user_id = u.id))
       )
     GROUP BY u.id, up.nickname, up.avatar_url, up.bio
     ORDER BY MAX(p.created_at) DESC, COUNT(p.id) DESC
     LIMIT $2`,
    [viewerId, limit],
  );
  return result.rows;
}

async function getFeed(viewerId, tab, limit) {
  let posts = await listPosts({ viewerId, tab, limit });
  let isFallback = false;
  if (tab !== 'discover' && posts.length === 0) {
    posts = await listPosts({ viewerId, tab: 'discover', limit });
    isFallback = posts.length > 0;
  }
  const suggestedReaders = tab === 'following'
    ? await listSuggestedReaders(viewerId, 6)
    : [];
  const booksResult = await query(
    `SELECT b.*,
       EXISTS (
         SELECT 1 FROM community_readable_assets a
         WHERE a.book_id = b.id AND a.active = true
       ) AS can_read,
       (SELECT COUNT(*)::int FROM community_book_states s
        WHERE s.book_id = b.id AND s.status = 'reading' AND s.visibility = 'public'
          AND COALESCE((SELECT show_reading_status FROM community_privacy_settings ps
                        WHERE ps.user_id = s.user_id), false) = true) AS reading_count,
       (SELECT COUNT(*)::int FROM community_posts p
        WHERE p.book_id = b.id AND p.moderation_status = 'published') AS post_count
     FROM community_books b
     ORDER BY b.updated_at DESC
     LIMIT 12`,
  );
  return {
    posts,
    books: booksResult.rows,
    fallback: isFallback,
    suggested_readers: suggestedReaders,
  };
}

async function getBook(bookId, viewerId) {
  const bookResult = await query(
    `SELECT b.*,
       EXISTS (
         SELECT 1 FROM community_readable_assets a
         WHERE a.book_id = b.id AND a.active = true
       ) AS can_read,
       (SELECT COUNT(*)::int FROM community_book_states s
        WHERE s.book_id = b.id AND s.status = 'want_to_read' AND s.visibility = 'public'
          AND COALESCE((SELECT show_reading_status FROM community_privacy_settings ps
                        WHERE ps.user_id = s.user_id), false) = true) AS want_count,
       (SELECT COUNT(*)::int FROM community_book_states s
        WHERE s.book_id = b.id AND s.status = 'reading' AND s.visibility = 'public'
          AND COALESCE((SELECT show_reading_status FROM community_privacy_settings ps
                        WHERE ps.user_id = s.user_id), false) = true) AS reading_count,
       (SELECT COUNT(*)::int FROM community_book_states s
        WHERE s.book_id = b.id AND s.status = 'finished' AND s.visibility = 'public'
          AND COALESCE((SELECT show_reading_status FROM community_privacy_settings ps
                        WHERE ps.user_id = s.user_id), false) = true) AS finished_count,
       (SELECT COUNT(*)::int FROM community_posts p
        WHERE p.book_id = b.id AND p.moderation_status = 'published') AS post_count,
       (SELECT status FROM community_book_states s
        WHERE s.book_id = b.id AND s.user_id = $2::uuid) AS viewer_status
     FROM community_books b
     WHERE b.id = $1`,
    [bookId, viewerId],
  );
  if (!bookResult.rows[0]) return null;
  const [posts, readers] = await Promise.all([
    listPosts({ viewerId, bookId, limit: 40 }),
    query(
      `SELECT s.user_id, s.status, s.updated_at,
         COALESCE(NULLIF(up.nickname, ''), split_part(u.email, '@', 1)) AS nickname,
         COALESCE(up.avatar_url, '') AS avatar_url,
         COALESCE(up.bio, '') AS bio
       FROM community_book_states s
       JOIN users u ON u.id = s.user_id
       LEFT JOIN user_profiles up ON up.user_id = s.user_id
       LEFT JOIN community_privacy_settings ps ON ps.user_id = s.user_id
       WHERE s.book_id = $1 AND s.visibility = 'public'
         AND COALESCE(ps.show_reading_status, false) = true
         AND COALESCE(ps.appear_in_same_book, false) = true
         AND NOT EXISTS (
           SELECT 1 FROM community_blocks cb
           WHERE $2::uuid IS NOT NULL
             AND ((cb.blocker_user_id = $2::uuid AND cb.blocked_user_id = s.user_id)
               OR (cb.blocked_user_id = $2::uuid AND cb.blocker_user_id = s.user_id))
         )
       ORDER BY CASE s.status WHEN 'reading' THEN 0 WHEN 'finished' THEN 1 ELSE 2 END,
                s.updated_at DESC
       LIMIT 36`,
      [bookId, viewerId],
    ),
  ]);
  return { book: bookResult.rows[0], posts, readers: readers.rows };
}

async function setBookState(userId, bookId, status, visibility) {
  if (status === 'none') {
    await query(
      'DELETE FROM community_book_states WHERE user_id = $1 AND book_id = $2',
      [userId, bookId],
    );
    return null;
  }
  const result = await query(
    `INSERT INTO community_book_states (
       user_id, book_id, status, visibility, started_at, finished_at
     ) VALUES (
       $1, $2, $3, $4,
       CASE WHEN $3 = 'reading' THEN now() ELSE NULL END,
       CASE WHEN $3 = 'finished' THEN now() ELSE NULL END
     )
     ON CONFLICT (user_id, book_id) DO UPDATE SET
       status = EXCLUDED.status,
       visibility = EXCLUDED.visibility,
       started_at = CASE
         WHEN EXCLUDED.status = 'reading' THEN COALESCE(community_book_states.started_at, now())
         ELSE community_book_states.started_at
       END,
       finished_at = CASE WHEN EXCLUDED.status = 'finished' THEN now() ELSE NULL END,
       updated_at = now()
     RETURNING *`,
    [userId, bookId, status, visibility],
  );
  return result.rows[0];
}

async function createPost(userId, payload) {
  const result = await query(
    `INSERT INTO community_posts (
       user_id, book_id, post_type, content, quoted_text, chapter_label,
       reading_position, reading_progress, source, source_entry_id, topic_tags
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
     RETURNING id`,
    [
      userId,
      payload.book_id,
      payload.post_type,
      payload.content,
      payload.quoted_text,
      payload.chapter_label,
      payload.reading_position,
      payload.reading_progress,
      payload.source,
      payload.source_entry_id,
      payload.topic_tags,
    ],
  );
  const posts = await listPosts({
    viewerId: userId,
    postId: result.rows[0].id,
    limit: 1,
  });
  return posts[0] || result.rows[0];
}

async function deletePost(userId, postId) {
  const result = await query(
    'DELETE FROM community_posts WHERE id = $1 AND user_id = $2 RETURNING id',
    [postId, userId],
  );
  return result.rowCount > 0;
}

async function listComments(postId, viewerId = null) {
  const result = await query(
    `SELECT c.id, c.post_id, c.user_id, c.content, c.quoted_text,
       c.parent_reply_id, c.created_at, c.updated_at,
       COALESCE(NULLIF(up.nickname, ''), split_part(u.email, '@', 1)) AS nickname,
       COALESCE(up.avatar_url, '') AS avatar_url
     FROM community_post_comments c
     JOIN users u ON u.id = c.user_id
     LEFT JOIN user_profiles up ON up.user_id = c.user_id
     WHERE c.post_id = $1
       AND c.moderation_status = 'published'
       AND NOT EXISTS (
         SELECT 1 FROM community_blocks cb
         WHERE $2::uuid IS NOT NULL
           AND ((cb.blocker_user_id = $2::uuid AND cb.blocked_user_id = c.user_id)
             OR (cb.blocked_user_id = $2::uuid AND cb.blocker_user_id = c.user_id))
       )
     ORDER BY c.created_at ASC`,
    [postId, viewerId],
  );
  return result.rows;
}

async function createComment(userId, postId, payload) {
  return withTransaction(async (queryFn) => {
    const post = await queryFn(
      'SELECT user_id, book_id FROM community_posts WHERE id = $1',
      [postId],
    );
    if (!post.rows[0]) return null;
    const blocked = await queryFn(
      `SELECT 1 FROM community_blocks
       WHERE (blocker_user_id = $1 AND blocked_user_id = $2)
          OR (blocker_user_id = $2 AND blocked_user_id = $1)`,
      [userId, post.rows[0].user_id],
    );
    if (blocked.rowCount) return null;
    let parentUserId = null;
    if (payload.parent_reply_id) {
      const parent = await queryFn(
        'SELECT user_id FROM community_post_comments WHERE id = $1 AND post_id = $2',
        [payload.parent_reply_id, postId],
      );
      if (!parent.rowCount) return null;
      parentUserId = parent.rows[0].user_id;
    }
    const result = await queryFn(
      `INSERT INTO community_post_comments (
         post_id, user_id, content, quoted_text, parent_reply_id
       ) VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [
        postId,
        userId,
        payload.content,
        payload.quoted_text,
        payload.parent_reply_id,
      ],
    );
    if (post.rows[0].user_id !== userId) {
      await queryFn(
        `INSERT INTO community_notifications (
           recipient_user_id, actor_user_id, event_type, post_id, book_id, preview
         ) VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          post.rows[0].user_id,
          userId,
          payload.quoted_text ? 'post_quote_reply' : 'post_comment',
          postId,
          post.rows[0].book_id,
          payload.content.slice(0, 120),
        ],
      );
    }
    if (
      parentUserId &&
      parentUserId !== userId &&
      parentUserId !== post.rows[0].user_id
    ) {
      await queryFn(
        `INSERT INTO community_notifications (
           recipient_user_id, actor_user_id, event_type, post_id, book_id, preview
         ) VALUES ($1, $2, 'post_quote_reply', $3, $4, $5)`,
        [
          parentUserId,
          userId,
          postId,
          post.rows[0].book_id,
          payload.content.slice(0, 120),
        ],
      );
    }
    return result.rows[0];
  });
}

async function toggleFavorite(userId, postId) {
  return withTransaction(async (queryFn) => {
    const post = await queryFn(
      `SELECT p.id
       FROM community_posts p
       WHERE p.id = $1 AND p.moderation_status = 'published'`,
      [postId],
    );
    if (!post.rows[0]) return null;
    const existing = await queryFn(
      'SELECT 1 FROM community_post_favorites WHERE post_id = $1 AND user_id = $2',
      [postId, userId],
    );
    if (existing.rowCount) {
      await queryFn(
        'DELETE FROM community_post_favorites WHERE post_id = $1 AND user_id = $2',
        [postId, userId],
      );
      return { favorited: false };
    }
    await queryFn(
      'INSERT INTO community_post_favorites (post_id, user_id) VALUES ($1, $2)',
      [postId, userId],
    );
    return { favorited: true };
  });
}

async function toggleResonance(userId, postId) {
  return withTransaction(async (queryFn) => {
    const existing = await queryFn(
      'SELECT 1 FROM community_post_resonances WHERE post_id = $1 AND user_id = $2',
      [postId, userId],
    );
    if (existing.rowCount) {
      await queryFn(
        'DELETE FROM community_post_resonances WHERE post_id = $1 AND user_id = $2',
        [postId, userId],
      );
      return { resonated: false };
    }
    const post = await queryFn(
      'SELECT user_id, book_id FROM community_posts WHERE id = $1',
      [postId],
    );
    if (!post.rows[0]) return null;
    const blocked = await queryFn(
      `SELECT 1 FROM community_blocks
       WHERE (blocker_user_id = $1 AND blocked_user_id = $2)
          OR (blocker_user_id = $2 AND blocked_user_id = $1)`,
      [userId, post.rows[0].user_id],
    );
    if (blocked.rowCount) return null;
    await queryFn(
      'INSERT INTO community_post_resonances (post_id, user_id) VALUES ($1, $2)',
      [postId, userId],
    );
    if (post.rows[0].user_id !== userId) {
      await queryFn(
        `INSERT INTO community_notifications (
           recipient_user_id, actor_user_id, event_type, post_id, book_id
         ) VALUES ($1, $2, 'post_resonance', $3, $4)
         ON CONFLICT DO NOTHING`,
        [post.rows[0].user_id, userId, postId, post.rows[0].book_id],
      );
    }
    return { resonated: true };
  });
}

async function followUser(viewerId, targetUserId) {
  return withTransaction(async (queryFn) => {
    const privacy = await queryFn(
      `SELECT COALESCE(allow_follows, true) AS allow_follows
       FROM community_privacy_settings WHERE user_id = $1`,
      [targetUserId],
    );
    if (privacy.rows[0]?.allow_follows === false) return { following: false, disallowed: true };
    const blocked = await queryFn(
      `SELECT 1 FROM community_blocks
       WHERE (blocker_user_id = $1 AND blocked_user_id = $2)
          OR (blocker_user_id = $2 AND blocked_user_id = $1)`,
      [viewerId, targetUserId],
    );
    if (blocked.rowCount) return { following: false, blocked: true };
    const result = await queryFn(
      `INSERT INTO community_follows (follower_user_id, followed_user_id)
       VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING followed_user_id`,
      [viewerId, targetUserId],
    );
    if (result.rowCount) {
      await queryFn(
        `INSERT INTO community_notifications (
           recipient_user_id, actor_user_id, event_type
         ) VALUES ($1, $2, 'follow')`,
        [targetUserId, viewerId],
      );
    }
    return { following: true };
  });
}

async function unfollowUser(viewerId, targetUserId) {
  await query(
    'DELETE FROM community_follows WHERE follower_user_id = $1 AND followed_user_id = $2',
    [viewerId, targetUserId],
  );
  return { following: false };
}

async function listFavoritePosts(userId, limit = 60) {
  const whereSql = `WHERE p.moderation_status = 'published'
    AND p.visibility = 'public'
    AND EXISTS (
      SELECT 1 FROM community_post_favorites favorite
      WHERE favorite.post_id = p.id AND favorite.user_id = $1::uuid
    )`;
  const result = await query(postSelect(whereSql), [userId, limit]);
  return result.rows;
}

async function getProfile(targetUserId, viewerId) {
  if (viewerId && viewerId !== targetUserId) {
    const blocked = await query(
      `SELECT 1 FROM community_blocks
       WHERE (blocker_user_id = $1 AND blocked_user_id = $2)
          OR (blocker_user_id = $2 AND blocked_user_id = $1)`,
      [viewerId, targetUserId],
    );
    if (blocked.rowCount) return null;
  }
  const profileResult = await query(
    `SELECT u.id AS user_id,
       COALESCE(NULLIF(up.nickname, ''), split_part(u.email, '@', 1)) AS nickname,
       COALESCE(up.avatar_url, '') AS avatar_url,
       COALESCE(up.bio, '') AS bio,
       COALESCE(ps.allow_follows, true) AS allow_follows,
       COALESCE(ps.appear_in_same_book, false) AS appear_in_same_book,
       (SELECT COUNT(*)::int FROM community_follows f WHERE f.followed_user_id = u.id) AS follower_count,
       (SELECT COUNT(*)::int FROM community_follows f WHERE f.follower_user_id = u.id) AS following_count,
       CASE WHEN $2::uuid IS NULL THEN false ELSE EXISTS (
         SELECT 1 FROM community_follows f
         WHERE f.follower_user_id = $2::uuid AND f.followed_user_id = u.id
       ) END AS viewer_following
     FROM users u
     LEFT JOIN user_profiles up ON up.user_id = u.id
     LEFT JOIN community_privacy_settings ps ON ps.user_id = u.id
     WHERE u.id = $1`,
    [targetUserId, viewerId],
  );
  if (!profileResult.rows[0]) return null;
  const statesResult = await query(
    `SELECT s.status, s.updated_at, b.*
     FROM community_book_states s
     JOIN community_books b ON b.id = s.book_id
     WHERE s.user_id = $1
       AND (s.visibility = 'public' OR $1 = $2::uuid)
       AND (COALESCE((SELECT show_reading_status FROM community_privacy_settings
                      WHERE user_id = $1), false) = true OR $1 = $2::uuid)
     ORDER BY s.updated_at DESC`,
    [targetUserId, viewerId],
  );
  const posts = await listPosts({ viewerId, userId: targetUserId, limit: 60 });
  const favorites = viewerId === targetUserId
    ? await listFavoritePosts(targetUserId, 60)
    : [];
  return {
    profile: profileResult.rows[0],
    books: statesResult.rows,
    posts,
    favorites,
  };
}

async function listNotifications(userId, limit = 50) {
  const result = await query(
    `SELECT n.*,
       COALESCE(NULLIF(up.nickname, ''), split_part(u.email, '@', 1)) AS actor_nickname,
       COALESCE(up.avatar_url, '') AS actor_avatar_url,
       b.title AS book_title
     FROM community_notifications n
     JOIN users u ON u.id = n.actor_user_id
     LEFT JOIN user_profiles up ON up.user_id = n.actor_user_id
     LEFT JOIN community_books b ON b.id = n.book_id
     WHERE n.recipient_user_id = $1
       AND NOT EXISTS (
         SELECT 1 FROM community_blocks cb
         WHERE (cb.blocker_user_id = $1 AND cb.blocked_user_id = n.actor_user_id)
            OR (cb.blocked_user_id = $1 AND cb.blocker_user_id = n.actor_user_id)
       )
     ORDER BY n.created_at DESC
     LIMIT $2`,
    [userId, limit],
  );
  return result.rows;
}

async function markNotificationsRead(userId) {
  const result = await query(
    `UPDATE community_notifications SET read_at = now()
     WHERE recipient_user_id = $1 AND read_at IS NULL`,
    [userId],
  );
  return result.rowCount;
}

async function getPrivacySettings(userId) {
  const result = await query(
    `INSERT INTO community_privacy_settings (user_id)
     VALUES ($1) ON CONFLICT (user_id) DO UPDATE SET user_id = EXCLUDED.user_id
     RETURNING *`,
    [userId],
  );
  return result.rows[0];
}

async function updatePrivacySettings(userId, payload) {
  const result = await query(
    `INSERT INTO community_privacy_settings (
       user_id, show_reading_status, show_reading_progress, allow_follows,
       appear_in_same_book
     ) VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (user_id) DO UPDATE SET
       show_reading_status = EXCLUDED.show_reading_status,
       show_reading_progress = EXCLUDED.show_reading_progress,
       allow_follows = EXCLUDED.allow_follows,
       appear_in_same_book = EXCLUDED.appear_in_same_book,
       updated_at = now()
     RETURNING *`,
    [
      userId,
      payload.show_reading_status,
      payload.show_reading_progress,
      payload.allow_follows,
      payload.appear_in_same_book,
    ],
  );
  return result.rows[0];
}

async function hasGuidelineAcceptance(userId, version) {
  const result = await query(
    `SELECT 1 FROM community_guideline_acceptances
     WHERE user_id = $1 AND guideline_version = $2`,
    [userId, version],
  );
  return result.rowCount > 0;
}

async function acceptGuidelines(userId, version) {
  await query(
    `INSERT INTO community_guideline_acceptances (user_id, guideline_version)
     VALUES ($1, $2) ON CONFLICT DO NOTHING`,
    [userId, version],
  );
  return true;
}

async function blockUser(userId, targetUserId) {
  return withTransaction(async (queryFn) => {
    await queryFn(
      `INSERT INTO community_blocks (blocker_user_id, blocked_user_id)
       VALUES ($1, $2) ON CONFLICT DO NOTHING`,
      [userId, targetUserId],
    );
    await queryFn(
      `DELETE FROM community_follows
       WHERE (follower_user_id = $1 AND followed_user_id = $2)
          OR (follower_user_id = $2 AND followed_user_id = $1)`,
      [userId, targetUserId],
    );
    await queryFn(
      `DELETE FROM community_notifications
       WHERE (recipient_user_id = $1 AND actor_user_id = $2)
          OR (recipient_user_id = $2 AND actor_user_id = $1)`,
      [userId, targetUserId],
    );
    return { blocked: true };
  });
}

async function unblockUser(userId, targetUserId) {
  await query(
    'DELETE FROM community_blocks WHERE blocker_user_id = $1 AND blocked_user_id = $2',
    [userId, targetUserId],
  );
  return { blocked: false };
}

async function listBlockedUsers(userId) {
  const result = await query(
    `SELECT b.blocked_user_id AS user_id, b.created_at,
       COALESCE(NULLIF(up.nickname, ''), split_part(u.email, '@', 1)) AS nickname,
       COALESCE(up.avatar_url, '') AS avatar_url
     FROM community_blocks b
     JOIN users u ON u.id = b.blocked_user_id
     LEFT JOIN user_profiles up ON up.user_id = u.id
     WHERE b.blocker_user_id = $1
     ORDER BY b.created_at DESC`,
    [userId],
  );
  return result.rows;
}

async function createReport(userId, payload) {
  const tables = { post: 'community_posts', comment: 'community_post_comments', user: 'users' };
  const table = tables[payload.target_type];
  const target = await query(`SELECT id FROM ${table} WHERE id = $1`, [payload.target_id]);
  if (!target.rowCount) return null;
  const result = await query(
    `INSERT INTO community_reports (
       reporter_user_id, target_type, target_id, reason, details
     ) VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (reporter_user_id, target_type, target_id) DO UPDATE SET
       reason = EXCLUDED.reason, details = EXCLUDED.details,
       status = 'pending', created_at = now()
     RETURNING *`,
    [userId, payload.target_type, payload.target_id, payload.reason, payload.details],
  );
  return result.rows[0];
}

async function listReports(limit = 100) {
  const result = await query(
    `SELECT r.*, reporter.email AS reporter_email, reviewer.email AS reviewer_email
     FROM community_reports r
     JOIN users reporter ON reporter.id = r.reporter_user_id
     LEFT JOIN users reviewer ON reviewer.id = r.reviewed_by_user_id
     ORDER BY CASE r.status WHEN 'pending' THEN 0 WHEN 'reviewing' THEN 1 ELSE 2 END,
       r.created_at DESC LIMIT $1`,
    [limit],
  );
  return result.rows;
}

async function resolveReport(adminUserId, reportId, payload) {
  const result = await query(
    `UPDATE community_reports SET status = $2, resolution_note = $3,
       reviewed_by_user_id = $4, reviewed_at = now()
     WHERE id = $1 RETURNING *`,
    [reportId, payload.status, payload.resolution_note, adminUserId],
  );
  return result.rows[0] || null;
}

async function moderateTarget(adminUserId, payload) {
  return withTransaction(async (queryFn) => {
    if (payload.action_type === 'hide_post' || payload.action_type === 'remove_post') {
      await queryFn(
        `UPDATE community_posts SET moderation_status = $2, updated_at = now() WHERE id = $1`,
        [payload.target_id, payload.action_type === 'hide_post' ? 'hidden' : 'removed'],
      );
    } else if (payload.action_type === 'hide_comment' || payload.action_type === 'remove_comment') {
      await queryFn(
        `UPDATE community_post_comments SET moderation_status = $2, updated_at = now() WHERE id = $1`,
        [payload.target_id, payload.action_type === 'hide_comment' ? 'hidden' : 'removed'],
      );
    } else if (payload.action_type === 'ban_user' || payload.action_type === 'unban_user') {
      await queryFn(
        `UPDATE users SET account_status = $2, ban_reason = $3,
           token_version = token_version + 1, updated_at = now()
         WHERE id = $1`,
        [payload.target_id, payload.action_type === 'ban_user' ? 'banned' : 'active', payload.reason],
      );
    }
    await queryFn(
      `INSERT INTO community_moderation_actions (
         admin_user_id, action_type, target_type, target_id, reason
       ) VALUES ($1, $2, $3, $4, $5)`,
      [adminUserId, payload.action_type, payload.target_type, payload.target_id, payload.reason],
    );
    return { actioned: true };
  });
}

function clean(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

module.exports = {
  resolveBook,
  searchCommunity,
  getFeed,
  getBook,
  setBookState,
  createPost,
  deletePost,
  listComments,
  createComment,
  toggleFavorite,
  toggleResonance,
  followUser,
  unfollowUser,
  getProfile,
  listNotifications,
  markNotificationsRead,
  getPrivacySettings,
  updatePrivacySettings,
  hasGuidelineAcceptance,
  acceptGuidelines,
  blockUser,
  unblockUser,
  listBlockedUsers,
  createReport,
  listReports,
  resolveReport,
  moderateTarget,
};
