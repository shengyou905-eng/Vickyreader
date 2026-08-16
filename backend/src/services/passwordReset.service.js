const crypto = require('crypto');

const TOKEN_TTL_MINUTES = 30;

function createPasswordResetToken() {
  return crypto.randomBytes(32).toString('base64url');
}

function hashPasswordResetToken(token) {
  return crypto
    .createHash('sha256')
    .update(String(token || ''), 'utf8')
    .digest('hex');
}

function passwordResetExpiry(now = new Date()) {
  return new Date(now.getTime() + TOKEN_TTL_MINUTES * 60 * 1000);
}

function hashRateLimitKey(value, secret) {
  return crypto
    .createHmac('sha256', secret)
    .update(String(value || ''), 'utf8')
    .digest('hex');
}

module.exports = {
  TOKEN_TTL_MINUTES,
  createPasswordResetToken,
  hashPasswordResetToken,
  passwordResetExpiry,
  hashRateLimitKey,
};
