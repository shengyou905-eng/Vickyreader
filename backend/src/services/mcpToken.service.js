const crypto = require('crypto');
const { mcpTokenHashSecret, mcpTokenTtlDays } = require('../config/env');
const httpError = require('../utils/httpError');

const TOKEN_PREFIX = 'zd_mcp_';

function getHashSecret() {
  if (!mcpTokenHashSecret) {
    throw httpError(
      503,
      'MCP token generation is not configured. Set MCP_TOKEN_HASH_SECRET on the server.',
    );
  }
  return mcpTokenHashSecret;
}

function createRawToken() {
  return `${TOKEN_PREFIX}${crypto.randomBytes(32).toString('base64url')}`;
}

function hashToken(token) {
  return crypto
    .createHmac('sha256', getHashSecret())
    .update(token)
    .digest();
}

function getTokenPrefix(token) {
  return token.slice(0, TOKEN_PREFIX.length + 8);
}

function getExpiryDate(now = new Date()) {
  const expiresAt = new Date(now);
  expiresAt.setUTCDate(expiresAt.getUTCDate() + mcpTokenTtlDays);
  return expiresAt;
}

function isMcpToken(token) {
  return typeof token === 'string' && token.startsWith(TOKEN_PREFIX) && token.length > TOKEN_PREFIX.length + 20;
}

module.exports = {
  TOKEN_PREFIX,
  createRawToken,
  hashToken,
  getTokenPrefix,
  getExpiryDate,
  isMcpToken,
};
