const { query, withTransaction } = require('../config/db');

function normalizeBookKey(title, author) {
  return `${clean(title).toLowerCase()}::${clean(author || '佚名').toLowerCase()}`
    .replace(/\s+/g, ' ')
    .slice(0, 600);
}

async function resolveBook(userId, payload) {
  const title = clean(payload.title);
  const author = clean(payload.author) || '佚名';
  const normalizedKey = normalizeBookKey(title, author);
  const result = await query(
    `INSERT INTO community_books (
       normalized_key, title, author, cover_url, description, isbn,
       created_by_user_id, metadata_json
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
     ON CONFLICT (normalized_key) DO UPDATE SET
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
      normalizedKey,
      title,
      author,
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
          WHERE s.book_id = b.id AND s.status = 'reading' AND s.visibility = 'public') AS reading_count,
         (SELECT COUNT(*)::int FROM community_book_states s
          WHERE s.book_id = b.id AND s.status = 'finished' AND s.visibility = 'public') AS finished_count,
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

function postSelect(whereSql) {
  return `SELECT
      p.id, p.user_id, p.book_id, p.post_type, p.content, p.quoted_text,
      p.chapter_label, p.created_at, p.updated_at,
      b.title AS book_title, b.author AS book_author,
      b.cover_url AS book_cover_url,
      COALESCE(NULLIF(up.nickname, ''), split_part(u.email, '@', 1)) AS nickname,
      COALESCE(up.avatar_url, '') AS avatar_url,
      (SELECT COUNT(*)::int FROM community_post_comments c WHERE c.post_id = p.id) AS comment_count,
      (SELECT COUNT(*)::int FROM community_post_resonances r WHERE r.post_id = p.id) AS resonance_count,
      CASE WHEN $1::uuid IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM community_post_resonances r
        WHERE r.post_id = p.id AND r.user_id = $1::uuid
      ) END AS viewer_resonated
    FROM community_posts p
    JOIN community_books b ON b.id = p.book_id
    JOIN users u ON u.id = p.user_id
    LEFT JOIN user_profiles up ON up.user_id = p.user_id
    ${whereSql}
    ORDER BY p.created_at DESC
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
  if (tab === 'following') {
    conditions.push(`$1::uuid IS NOT NULL AND EXISTS (
      SELECT 1 FROM community_follows f
      WHERE f.follower_user_id = $1::uuid
        AND f.followed_user_id = p.user_id
    )`);
  } else if (tab === 'same_book') {
    conditions.push(`$1::uuid IS NOT NULL AND EXISTS (
      SELECT 1 FROM community_book_states s
      WHERE s.user_id = $1::uuid
        AND s.book_id = p.book_id
        AND s.status = 'reading'
    )`);
  }
  if (conditions.length) whereSql = `WHERE ${conditions.join(' AND ')}`;
  const result = await query(postSelect(whereSql), params);
  return result.rows;
}

async function getFeed(viewerId, tab, limit) {
  const posts = await listPosts({ viewerId, tab, limit });
  const booksResult = await query(
    `SELECT b.*,
       EXISTS (
         SELECT 1 FROM community_readable_assets a
         WHERE a.book_id = b.id AND a.active = true
       ) AS can_read,
       (SELECT COUNT(*)::int FROM community_book_states s
        WHERE s.book_id = b.id AND s.status = 'reading' AND s.visibility = 'public') AS reading_count,
       (SELECT COUNT(*)::int FROM community_posts p WHERE p.book_id = b.id) AS post_count
     FROM community_books b
     ORDER BY b.updated_at DESC
     LIMIT 12`,
  );
  return { posts, books: booksResult.rows };
}

async function getBook(bookId, viewerId) {
  const bookResult = await query(
    `SELECT b.*,
       EXISTS (
         SELECT 1 FROM community_readable_assets a
         WHERE a.book_id = b.id AND a.active = true
       ) AS can_read,
       (SELECT COUNT(*)::int FROM community_book_states s
        WHERE s.book_id = b.id AND s.status = 'want_to_read' AND s.visibility = 'public') AS want_count,
       (SELECT COUNT(*)::int FROM community_book_states s
        WHERE s.book_id = b.id AND s.status = 'reading' AND s.visibility = 'public') AS reading_count,
       (SELECT COUNT(*)::int FROM community_book_states s
        WHERE s.book_id = b.id AND s.status = 'finished' AND s.visibility = 'public') AS finished_count,
       (SELECT COUNT(*)::int FROM community_posts p WHERE p.book_id = b.id) AS post_count,
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
       WHERE s.book_id = $1 AND s.visibility = 'public'
       ORDER BY CASE s.status WHEN 'reading' THEN 0 WHEN 'finished' THEN 1 ELSE 2 END,
                s.updated_at DESC
       LIMIT 36`,
      [bookId],
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
       user_id, book_id, post_type, content, quoted_text, chapter_label
     ) VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id`,
    [
      userId,
      payload.book_id,
      payload.post_type,
      payload.content,
      payload.quoted_text,
      payload.chapter_label,
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

async function listComments(postId) {
  const result = await query(
    `SELECT c.id, c.post_id, c.user_id, c.content, c.created_at, c.updated_at,
       COALESCE(NULLIF(up.nickname, ''), split_part(u.email, '@', 1)) AS nickname,
       COALESCE(up.avatar_url, '') AS avatar_url
     FROM community_post_comments c
     JOIN users u ON u.id = c.user_id
     LEFT JOIN user_profiles up ON up.user_id = c.user_id
     WHERE c.post_id = $1
     ORDER BY c.created_at ASC`,
    [postId],
  );
  return result.rows;
}

async function createComment(userId, postId, content) {
  return withTransaction(async (queryFn) => {
    const post = await queryFn(
      'SELECT user_id, book_id FROM community_posts WHERE id = $1',
      [postId],
    );
    if (!post.rows[0]) return null;
    const result = await queryFn(
      `INSERT INTO community_post_comments (post_id, user_id, content)
       VALUES ($1, $2, $3) RETURNING *`,
      [postId, userId, content],
    );
    if (post.rows[0].user_id !== userId) {
      await queryFn(
        `INSERT INTO community_notifications (
           recipient_user_id, actor_user_id, event_type, post_id, book_id, preview
         ) VALUES ($1, $2, 'post_comment', $3, $4, $5)`,
        [post.rows[0].user_id, userId, postId, post.rows[0].book_id, content.slice(0, 120)],
      );
    }
    return result.rows[0];
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

async function getProfile(targetUserId, viewerId) {
  const profileResult = await query(
    `SELECT u.id AS user_id,
       COALESCE(NULLIF(up.nickname, ''), split_part(u.email, '@', 1)) AS nickname,
       COALESCE(up.avatar_url, '') AS avatar_url,
       COALESCE(up.bio, '') AS bio,
       (SELECT COUNT(*)::int FROM community_follows f WHERE f.followed_user_id = u.id) AS follower_count,
       (SELECT COUNT(*)::int FROM community_follows f WHERE f.follower_user_id = u.id) AS following_count,
       CASE WHEN $2::uuid IS NULL THEN false ELSE EXISTS (
         SELECT 1 FROM community_follows f
         WHERE f.follower_user_id = $2::uuid AND f.followed_user_id = u.id
       ) END AS viewer_following
     FROM users u
     LEFT JOIN user_profiles up ON up.user_id = u.id
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
     ORDER BY s.updated_at DESC`,
    [targetUserId, viewerId],
  );
  const posts = await listPosts({ viewerId, userId: targetUserId, limit: 60 });
  return { profile: profileResult.rows[0], books: statesResult.rows, posts };
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
  toggleResonance,
  followUser,
  unfollowUser,
  getProfile,
  listNotifications,
  markNotificationsRead,
};
