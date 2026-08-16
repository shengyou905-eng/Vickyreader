process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';
process.env.PASSWORD_RESET_PUBLIC_URL ||=
  'https://api.youxugarden.com/auth/reset-password';

const test = require('node:test');
const assert = require('node:assert/strict');
const { resetLink } = require('./email.service');

test('password reset link is HTTPS and keeps the token out of server requests', () => {
  const link = resetLink('one-time-token');
  assert.equal(
    link,
    'https://api.youxugarden.com/auth/reset-password#token=one-time-token',
  );
  const parsed = new URL(link);
  assert.equal(parsed.protocol, 'https:');
  assert.equal(parsed.search, '');
  assert.equal(parsed.hash, '#token=one-time-token');
});
