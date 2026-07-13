const httpError = require('./httpError');

const GUIDELINE_VERSION = 1;
const reportReasons = new Set([
  'spam', 'harassment', 'hate', 'sexual', 'violence', 'copyright', 'privacy', 'other',
]);
const moderationActions = new Set([
  'hide_post', 'remove_post', 'hide_comment', 'remove_comment', 'ban_user', 'unban_user',
]);
const blockedTerms = String(process.env.COMMUNITY_BLOCKED_TERMS || '')
  .split(',')
  .map((item) => item.trim().toLowerCase())
  .filter(Boolean);

function assertSafePublicText(value, { minLength = 2, maxLength = 4000 } = {}) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (text.length < minLength || text.length > maxLength) {
    throw httpError(400, `内容应为 ${minLength} 到 ${maxLength} 个字符`);
  }
  if (/^\d+$/.test(text) || /^(.)\1{3,}$/u.test(text)) {
    throw httpError(400, '请写下一段有完整含义的内容');
  }
  const lowered = text.toLowerCase();
  if (blockedTerms.some((term) => lowered.includes(term))) {
    throw httpError(400, '内容包含不适合公开发布的信息，请修改后重试');
  }
  return text;
}

module.exports = {
  GUIDELINE_VERSION,
  reportReasons,
  moderationActions,
  assertSafePublicText,
};
