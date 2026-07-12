const communityRepository = require('../repositories/community.repository');
const httpError = require('../utils/httpError');

const bookStates = new Set(['want_to_read', 'reading', 'finished', 'none']);
const postTypes = new Set(['reading_update', 'thought', 'question', 'excerpt']);

async function resolveBook(req, res, next) {
  try {
    const title = text(req.body.title);
    if (!title) throw httpError(400, 'title is required');
    if (title.length > 240) throw httpError(400, 'title is too long');
    const book = await communityRepository.resolveBook(req.user.id, {
      title,
      author: text(req.body.author) || '佚名',
      cover_url: safePublicUrl(req.body.cover_url),
      description: text(req.body.description).slice(0, 4000),
      isbn: text(req.body.isbn).slice(0, 40),
      metadata_json: object(req.body.metadata_json),
    });
    return res.status(201).json({ book });
  } catch (error) {
    return next(error);
  }
}

async function search(req, res, next) {
  try {
    const q = text(req.query.q);
    if (!q) return res.json({ books: [], posts: [] });
    const result = await communityRepository.searchCommunity(
      q.slice(0, 120),
      req.user?.id || null,
      limit(req.query.limit, 24),
    );
    return res.json(result);
  } catch (error) {
    return next(error);
  }
}

async function feed(req, res, next) {
  try {
    const tab = ['following', 'discover', 'same_book'].includes(req.query.tab)
      ? req.query.tab
      : 'discover';
    if ((tab === 'following' || tab === 'same_book') && !req.user?.id) {
      return res.json({ posts: [], books: [], requires_auth: true });
    }
    const result = await communityRepository.getFeed(
      req.user?.id || null,
      tab,
      limit(req.query.limit, 30),
    );
    return res.json(result);
  } catch (error) {
    return next(error);
  }
}

async function getBook(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    const result = await communityRepository.getBook(
      req.params.id,
      req.user?.id || null,
    );
    if (!result) throw httpError(404, 'Book not found');
    return res.json(result);
  } catch (error) {
    return next(error);
  }
}

async function setBookState(req, res, next) {
  try {
    assertUuid(req.params.id, 'book id');
    const status = text(req.body.status);
    if (!bookStates.has(status)) throw httpError(400, 'Invalid reading status');
    const visibility = req.body.visibility === 'private' ? 'private' : 'public';
    const state = await communityRepository.setBookState(
      req.user.id,
      req.params.id,
      status,
      visibility,
    );
    return res.json({ state });
  } catch (error) {
    return next(error);
  }
}

async function createPost(req, res, next) {
  try {
    const bookId = text(req.body.book_id);
    assertUuid(bookId, 'book id');
    const postType = postTypes.has(req.body.post_type)
      ? req.body.post_type
      : 'thought';
    const content = text(req.body.content);
    assertMeaningfulPublicText(content);
    const quotedText = text(req.body.quoted_text);
    if (quotedText.length > 240) {
      throw httpError(400, '公开摘录不能超过 240 个字符');
    }
    const post = await communityRepository.createPost(req.user.id, {
      book_id: bookId,
      post_type: postType,
      content: content.slice(0, 4000),
      quoted_text: quotedText,
      chapter_label: text(req.body.chapter_label).slice(0, 160),
    });
    return res.status(201).json({ post });
  } catch (error) {
    return next(error);
  }
}

async function deletePost(req, res, next) {
  try {
    assertUuid(req.params.id, 'post id');
    const deleted = await communityRepository.deletePost(
      req.user.id,
      req.params.id,
    );
    if (!deleted) throw httpError(404, 'Post not found');
    return res.json({ deleted: true });
  } catch (error) {
    return next(error);
  }
}

async function listComments(req, res, next) {
  try {
    assertUuid(req.params.id, 'post id');
    const comments = await communityRepository.listComments(req.params.id);
    return res.json({ comments });
  } catch (error) {
    return next(error);
  }
}

async function createComment(req, res, next) {
  try {
    assertUuid(req.params.id, 'post id');
    const content = text(req.body.content);
    if (content.length < 2 || content.length > 1200) {
      throw httpError(400, '评论应为 2 到 1200 个字符');
    }
    const comment = await communityRepository.createComment(
      req.user.id,
      req.params.id,
      content,
    );
    if (!comment) throw httpError(404, 'Post not found');
    return res.status(201).json({ comment });
  } catch (error) {
    return next(error);
  }
}

async function toggleResonance(req, res, next) {
  try {
    assertUuid(req.params.id, 'post id');
    const result = await communityRepository.toggleResonance(
      req.user.id,
      req.params.id,
    );
    if (!result) throw httpError(404, 'Post not found');
    return res.json(result);
  } catch (error) {
    return next(error);
  }
}

async function getProfile(req, res, next) {
  try {
    const targetUserId = req.params.userId === 'me'
      ? req.user?.id
      : req.params.userId;
    if (!targetUserId) throw httpError(401, 'Unauthorized');
    assertUuid(targetUserId, 'user id');
    const result = await communityRepository.getProfile(
      targetUserId,
      req.user?.id || null,
    );
    if (!result) throw httpError(404, 'Profile not found');
    return res.json(result);
  } catch (error) {
    return next(error);
  }
}

async function follow(req, res, next) {
  try {
    assertUuid(req.params.userId, 'user id');
    if (req.params.userId === req.user.id) {
      throw httpError(400, '不能关注自己');
    }
    const result = await communityRepository.followUser(
      req.user.id,
      req.params.userId,
    );
    return res.json(result);
  } catch (error) {
    return next(error);
  }
}

async function unfollow(req, res, next) {
  try {
    assertUuid(req.params.userId, 'user id');
    const result = await communityRepository.unfollowUser(
      req.user.id,
      req.params.userId,
    );
    return res.json(result);
  } catch (error) {
    return next(error);
  }
}

async function notifications(req, res, next) {
  try {
    const items = await communityRepository.listNotifications(
      req.user.id,
      limit(req.query.limit, 50),
    );
    return res.json({ notifications: items });
  } catch (error) {
    return next(error);
  }
}

async function markNotificationsRead(req, res, next) {
  try {
    const updated = await communityRepository.markNotificationsRead(req.user.id);
    return res.json({ updated });
  } catch (error) {
    return next(error);
  }
}

function assertMeaningfulPublicText(value) {
  if (value.length < 5) throw httpError(400, '公开内容至少需要 5 个字符');
  if (value.length > 4000) throw httpError(400, '公开内容不能超过 4000 个字符');
  if (/^\d+$/.test(value) || /^(.)\1{3,}$/u.test(value)) {
    throw httpError(400, '请写下一段有完整含义的内容');
  }
}

function safePublicUrl(value) {
  const candidate = text(value);
  if (!candidate) return '';
  try {
    const url = new URL(candidate);
    return ['http:', 'https:'].includes(url.protocol) ? url.toString() : '';
  } catch (_) {
    return '';
  }
}

function assertUuid(value, label) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || ''))) {
    throw httpError(400, `Invalid ${label}`);
  }
}

function text(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function object(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function limit(value, fallback) {
  return Math.min(Math.max(Number(value) || fallback, 1), 100);
}

module.exports = {
  resolveBook,
  search,
  feed,
  getBook,
  setBookState,
  createPost,
  deletePost,
  listComments,
  createComment,
  toggleResonance,
  getProfile,
  follow,
  unfollow,
  notifications,
  markNotificationsRead,
};
