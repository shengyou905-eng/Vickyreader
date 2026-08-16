process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  TOKEN_TTL_MINUTES,
  createPasswordResetToken,
  hashPasswordResetToken,
  passwordResetExpiry,
  hashRateLimitKey,
} = require('./passwordReset.service');

test('password reset tokens are random and only their hash is stable', () => {
  const first = createPasswordResetToken();
  const second = createPasswordResetToken();
  assert.notEqual(first, second);
  assert.ok(first.length >= 40);
  assert.equal(hashPasswordResetToken(first), hashPasswordResetToken(first));
  assert.notEqual(hashPasswordResetToken(first), first);
});

test('password reset expiry is exactly thirty minutes', () => {
  const now = new Date('2026-08-15T00:00:00.000Z');
  const expiresAt = passwordResetExpiry(now);
  assert.equal(TOKEN_TTL_MINUTES, 30);
  assert.equal(expiresAt.toISOString(), '2026-08-15T00:30:00.000Z');
});

test('rate-limit keys do not store raw identifiers', () => {
  const email = 'reader@example.com';
  const key = hashRateLimitKey(email, 'independent-secret');
  assert.equal(key.length, 64);
  assert.equal(key.includes(email), false);
});
