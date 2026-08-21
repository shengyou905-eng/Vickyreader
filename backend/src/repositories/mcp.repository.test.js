process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  DEFAULT_PAGE_SIZE,
  MAX_PAGE_SIZE,
  decodeCursor,
  encodeCursor,
  normalizeLimit,
} = require('./mcp.repository');

test('keeps MCP cursors opaque and bounded', () => {
  const cursor = encodeCursor(40);
  assert.equal(decodeCursor(cursor), 40);
  assert.equal(decodeCursor('invalid'), 0);
  assert.equal(decodeCursor(encodeCursor(10001)), 0);
});

test('caps MCP pagination between one and fifty items', () => {
  assert.equal(normalizeLimit(), DEFAULT_PAGE_SIZE);
  assert.equal(normalizeLimit(0), 1);
  assert.equal(normalizeLimit(999), MAX_PAGE_SIZE);
  assert.equal(normalizeLimit(27.8), 27);
});
