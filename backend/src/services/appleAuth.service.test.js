process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';
process.env.APPLE_TEAM_ID ||= 'TEAM123456';
process.env.APPLE_KEY_ID ||= 'KEY1234567';
process.env.APPLE_CLIENT_ID ||= 'com.reader.aiReader';
process.env.APPLE_ALLOWED_AUDIENCES ||= 'com.reader.aiReader';
process.env.APPLE_PRIVATE_KEY ||= 'unused-in-verification-tests';
process.env.APPLE_TOKEN_ENCRYPTION_KEY ||=
  Buffer.alloc(32, 7).toString('base64');

const crypto = require('crypto');
const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const {
  APPLE_ISSUER,
  sha256,
  verifyIdentityToken,
  encryptRefreshToken,
  decryptRefreshToken,
} = require('./appleAuth.service');

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
});

function identityToken({
  nonce = sha256('raw-nonce'),
  audience = 'com.reader.aiReader',
  email = 'private@privaterelay.appleid.com',
} = {}) {
  return jwt.sign(
    {
      sub: 'apple-stable-subject',
      nonce,
      email,
      email_verified: 'true',
      is_private_email: 'true',
    },
    privateKey,
    {
      algorithm: 'RS256',
      keyid: 'test-key',
      issuer: APPLE_ISSUER,
      audience,
      expiresIn: '5m',
    },
  );
}

test('verifies Apple JWT claims, nonce, and Hide My Email address', async () => {
  const payload = await verifyIdentityToken(identityToken(), 'raw-nonce', {
    publicKey,
    audiences: ['com.reader.aiReader'],
  });
  assert.equal(payload.sub, 'apple-stable-subject');
  assert.equal(payload.is_private_email, 'true');
  assert.equal(payload.email, 'private@privaterelay.appleid.com');
});

test('rejects an invalid nonce or audience', async () => {
  await assert.rejects(
    verifyIdentityToken(identityToken(), 'wrong-nonce', {
      publicKey,
      audiences: ['com.reader.aiReader'],
    }),
    /nonce/i,
  );
  await assert.rejects(
    verifyIdentityToken(identityToken(), 'raw-nonce', {
      publicKey,
      audiences: ['another.client'],
    }),
    /audience/i,
  );
});

test('encrypts Apple refresh tokens before persistence', () => {
  const encrypted = encryptRefreshToken('refresh-token-value');
  assert.notEqual(encrypted, 'refresh-token-value');
  assert.equal(decryptRefreshToken(encrypted), 'refresh-token-value');
});
