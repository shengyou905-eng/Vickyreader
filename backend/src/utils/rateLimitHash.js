const crypto = require('crypto');

// HMAC-SHA256 of a rate-limit key, so raw identifiers (IPs, emails) are never
// stored in plain text in the rate-limit table.
function hashRateLimitKey(value, secret) {
  return crypto
    .createHmac('sha256', secret)
    .update(String(value || ''), 'utf8')
    .digest('hex');
}

module.exports = { hashRateLimitKey };
