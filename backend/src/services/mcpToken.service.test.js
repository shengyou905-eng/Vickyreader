process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';
process.env.MCP_TOKEN_HASH_SECRET ||= 'test-mcp-token-hash-secret';
process.env.MCP_TOKEN_TTL_DAYS ||= '90';

const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeMcpTokenTtlDays } = require('../config/env');
const {
  TOKEN_PREFIX,
  createRawToken,
  getExpiryDate,
  getTokenPrefix,
  hashToken,
  isMcpToken,
} = require('./mcpToken.service');

test('creates a distinct custom MCP token and stores only a stable keyed hash', () => {
  const first = createRawToken();
  const second = createRawToken();
  assert.ok(first.startsWith(TOKEN_PREFIX));
  assert.ok(isMcpToken(first));
  assert.notEqual(first, second);
  assert.deepEqual(hashToken(first), hashToken(first));
  assert.notDeepEqual(hashToken(first), hashToken(second));
  assert.equal(getTokenPrefix(first), first.slice(0, TOKEN_PREFIX.length + 8));
});

test('uses a bounded expiry for MCP tokens', () => {
  const now = new Date('2026-08-21T00:00:00.000Z');
  assert.equal(getExpiryDate(now).toISOString(), '2026-11-19T00:00:00.000Z');
});

test('invalid MCP token TTL configuration safely falls back to 90 days', () => {
  assert.equal(normalizeMcpTokenTtlDays('not-a-number'), 90);
  assert.equal(normalizeMcpTokenTtlDays(''), 90);
  assert.equal(normalizeMcpTokenTtlDays('0'), 1);
  assert.equal(normalizeMcpTokenTtlDays('999'), 365);
});
