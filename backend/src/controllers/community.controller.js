const communityRepository = require('../repositories/community.repository');
const httpError = require('../utils/httpError');
const { supportEmail } = require('../config/env');
const {
  GUIDELINE_VERSION,
  reportReasons,
  moderationActions,
  assertSafePublicText,
} = require('../utils/communityPolicy');

const bookStates = new Set(['want_to_read', 'reading', 'finished', 'none']);
const postTypes = new Set([
  'reading_update',
  'thought',
  'question',
  'excerpt',
  'review',
]);

async function resolveBook(req, res, next) {
  try {
    const title = text(req.body.title);
    if (!title) throw httpError(400, 'title is required');
    if (title.length > 240) throw httpError(400, 'title is too long');
    const book = await communityRepository.resolveBook(req.user.id, {
      title,
      author: text(req.body.author) || '佚名',
      work_title: text(req.body.work_title),
      original_author: text(req.body.original_author),
      original_language: text(req.body.original_language),
      translator: text(req.body.translator),
      publisher: text(req.body.publisher),
      publication_year: text(req.body.publication_year),
      language: text(req.body.language),
      edition_label: text(req.body.edition_label),
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
    const aliases = {
      recommend: 'discover',
      discover: 'discover',
      following: 'following',
      same_read: 'same_book',
      same_book: 'same_book',
    };
    const tab = aliases[req.query.tab] || 'discover';
    const result = await communityRepository.getFeed(
      req.user?.id || null,
      tab,
      limit(req.query.limit, 30),
    );
    return res.json({
      ...result,
      requires_auth: (tab === 'following' || tab === 'same_book') && !req.user?.id,
    });
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
    const visibility = req.body.visibility === 'public' ? 'public' : 'private';
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
    await assertGuidelinesAccepted(req.user.id);
    const bookId = text(req.body.book_id);
    assertUuid(bookId, 'book id');
    const postType = postTypes.has(req.body.post_type)
      ? req.body.post_type
      : 'thought';
    const content = assertSafePublicText(req.body.content, {
      minLength: postType === 'review' ? 10 : 5,
      maxLength: 4000,
    });
    const quotedText = text(req.body.quoted_text);
    if (postType === 'excerpt' && !quotedText) {
      throw httpError(400, '公开划线需要包含一段短摘录');
    }
    if (quotedText.length > 240) {
      throw httpError(400, '公开摘录不能超过 240 个字符');
    }
    if (quotedText) assertSafePublicText(quotedText, { minLength: 2, maxLength: 240 });
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
    const comments = await communityRepository.listComments(
      req.params.id,
      req.user?.id || null,
    );
    return res.json({ comments });
  } catch (error) {
    return next(error);
  }
}

async function createComment(req, res, next) {
  try {
    await assertGuidelinesAccepted(req.user.id);
    assertUuid(req.params.id, 'post id');
    const content = assertSafePublicText(req.body.content, { minLength: 2, maxLength: 1200 });
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

async function getGuidelines(req, res, next) {
  try {
    const accepted = req.user?.id
      ? await communityRepository.hasGuidelineAcceptance(req.user.id, GUIDELINE_VERSION)
      : false;
    return res.json({
      version: GUIDELINE_VERSION,
      accepted,
      support_email: supportEmail,
      principles: [
        '只发布你有权公开的原创内容和必要短摘录。',
        '尊重其他读者，不骚扰、不歧视、不泄露隐私。',
        '不发布违法、色情、暴力、仇恨、垃圾或广告内容。',
        '发现问题可举报；违规内容会被隐藏或删除，账号可能被封禁。',
      ],
    });
  } catch (error) {
    return next(error);
  }
}

async function acceptGuidelines(req, res, next) {
  try {
    if (Number(req.body?.version) !== GUIDELINE_VERSION || req.body?.accepted !== true) {
      throw httpError(400, '请阅读并明确同意当前社区规范');
    }
    await communityRepository.acceptGuidelines(req.user.id, GUIDELINE_VERSION);
    return res.json({ accepted: true, version: GUIDELINE_VERSION });
  } catch (error) {
    return next(error);
  }
}

async function getPrivacy(req, res, next) {
  try {
    const settings = await communityRepository.getPrivacySettings(req.user.id);
    return res.json({ settings });
  } catch (error) {
    return next(error);
  }
}

async function updatePrivacy(req, res, next) {
  try {
    const bool = (key, fallback) => typeof req.body?.[key] === 'boolean'
      ? req.body[key]
      : fallback;
    const current = await communityRepository.getPrivacySettings(req.user.id);
    const settings = await communityRepository.updatePrivacySettings(req.user.id, {
      show_reading_status: bool('show_reading_status', current.show_reading_status),
      show_reading_progress: bool('show_reading_progress', current.show_reading_progress),
      allow_follows: bool('allow_follows', current.allow_follows),
      appear_in_same_book: bool('appear_in_same_book', current.appear_in_same_book),
    });
    return res.json({ settings });
  } catch (error) {
    return next(error);
  }
}

async function block(req, res, next) {
  try {
    assertUuid(req.params.userId, 'user id');
    if (req.params.userId === req.user.id) throw httpError(400, '不能拉黑自己');
    return res.json(await communityRepository.blockUser(req.user.id, req.params.userId));
  } catch (error) {
    return next(error);
  }
}

async function unblock(req, res, next) {
  try {
    assertUuid(req.params.userId, 'user id');
    return res.json(await communityRepository.unblockUser(req.user.id, req.params.userId));
  } catch (error) {
    return next(error);
  }
}

async function blockedUsers(req, res, next) {
  try {
    const users = await communityRepository.listBlockedUsers(req.user.id);
    return res.json({ users });
  } catch (error) {
    return next(error);
  }
}

async function report(req, res, next) {
  try {
    const targetType = text(req.body?.target_type);
    const targetId = text(req.body?.target_id);
    const reason = text(req.body?.reason);
    if (!['post', 'comment', 'user'].includes(targetType)) throw httpError(400, 'Invalid report target');
    assertUuid(targetId, 'report target id');
    if (!reportReasons.has(reason)) throw httpError(400, 'Invalid report reason');
    const item = await communityRepository.createReport(req.user.id, {
      target_type: targetType,
      target_id: targetId,
      reason,
      details: text(req.body?.details).slice(0, 1200),
    });
    if (!item) throw httpError(404, 'Report target not found');
    return res.status(201).json({ report: item });
  } catch (error) {
    return next(error);
  }
}

async function adminReports(req, res, next) {
  try {
    const reports = await communityRepository.listReports(limit(req.query.limit, 100));
    return res.json({ reports });
  } catch (error) {
    return next(error);
  }
}

async function adminResolveReport(req, res, next) {
  try {
    assertUuid(req.params.id, 'report id');
    const status = text(req.body?.status);
    if (!['reviewing', 'actioned', 'dismissed'].includes(status)) {
      throw httpError(400, 'Invalid report status');
    }
    const report = await communityRepository.resolveReport(req.user.id, req.params.id, {
      status,
      resolution_note: text(req.body?.resolution_note).slice(0, 1200),
    });
    if (!report) throw httpError(404, 'Report not found');
    return res.json({ report });
  } catch (error) {
    return next(error);
  }
}

async function adminModerate(req, res, next) {
  try {
    const actionType = text(req.body?.action_type);
    const targetType = text(req.body?.target_type);
    const targetId = text(req.body?.target_id);
    if (!moderationActions.has(actionType)) throw httpError(400, 'Invalid moderation action');
    if (!['post', 'comment', 'user'].includes(targetType)) throw httpError(400, 'Invalid moderation target');
    const expectedTarget = actionType.endsWith('_post')
      ? 'post'
      : actionType.endsWith('_comment')
        ? 'comment'
        : 'user';
    if (targetType !== expectedTarget) throw httpError(400, 'Moderation action does not match target type');
    assertUuid(targetId, 'moderation target id');
    const result = await communityRepository.moderateTarget(req.user.id, {
      action_type: actionType,
      target_type: targetType,
      target_id: targetId,
      reason: text(req.body?.reason).slice(0, 1200),
    });
    return res.json(result);
  } catch (error) {
    return next(error);
  }
}

async function assertGuidelinesAccepted(userId) {
  if (!(await communityRepository.hasGuidelineAcceptance(userId, GUIDELINE_VERSION))) {
    throw httpError(428, '发布前请先阅读并同意社区规范');
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
  getGuidelines,
  acceptGuidelines,
  getPrivacy,
  updatePrivacy,
  block,
  unblock,
  blockedUsers,
  report,
  adminReports,
  adminResolveReport,
  adminModerate,
};
