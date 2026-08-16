const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const {
  appleTeamId,
  appleKeyId,
  appleClientId,
  appleAllowedAudiences,
  applePrivateKey,
  appleTokenEncryptionKey,
} = require('../config/env');

const APPLE_ISSUER = 'https://appleid.apple.com';
const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';
const APPLE_TOKEN_URL = 'https://appleid.apple.com/auth/token';
const APPLE_REVOKE_URL = 'https://appleid.apple.com/auth/revoke';
const JWKS_TTL_MS = 6 * 60 * 60 * 1000;
let jwksCache = { expiresAt: 0, keys: [] };

function sha256(value) {
  return crypto.createHash('sha256').update(String(value), 'utf8').digest('hex');
}

function safeEqual(left, right) {
  const a = Buffer.from(String(left || ''), 'utf8');
  const b = Buffer.from(String(right || ''), 'utf8');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function ensureAppleConfigured() {
  const missing = [];
  if (!appleTeamId) missing.push('APPLE_TEAM_ID');
  if (!appleKeyId) missing.push('APPLE_KEY_ID');
  if (!appleClientId) missing.push('APPLE_CLIENT_ID');
  if (!applePrivateKey) missing.push('APPLE_PRIVATE_KEY');
  if (!appleTokenEncryptionKey) missing.push('APPLE_TOKEN_ENCRYPTION_KEY');
  if (missing.length > 0) {
    throw new Error(
      `Apple authentication is not configured: ${missing.join(', ')}`,
    );
  }
}

async function fetchAppleKeys() {
  if (jwksCache.expiresAt > Date.now() && jwksCache.keys.length > 0) {
    return jwksCache.keys;
  }
  const response = await fetch(APPLE_KEYS_URL, {
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error('Unable to fetch Apple public keys');
  const data = await response.json();
  const keys = Array.isArray(data.keys) ? data.keys : [];
  if (keys.length === 0) throw new Error('Apple public key set is empty');
  jwksCache = { keys, expiresAt: Date.now() + JWKS_TTL_MS };
  return keys;
}

async function verifyIdentityToken(identityToken, rawNonce, options = {}) {
  if (!identityToken || !rawNonce) throw new Error('Missing Apple credential');
  const decoded = jwt.decode(identityToken, { complete: true });
  if (!decoded?.header || decoded.header.alg !== 'RS256' || !decoded.header.kid) {
    throw new Error('Invalid Apple identity token header');
  }

  let publicKey = options.publicKey;
  if (!publicKey) {
    const keys = await fetchAppleKeys();
    const jwk = keys.find(
      (item) => item.kid === decoded.header.kid && item.alg === 'RS256',
    );
    if (!jwk) throw new Error('Apple signing key was not found');
    publicKey = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  }

  const audiences = options.audiences || appleAllowedAudiences;
  if (!Array.isArray(audiences) || audiences.length === 0) {
    throw new Error('Apple audience is not configured');
  }
  const payload = jwt.verify(identityToken, publicKey, {
    algorithms: ['RS256'],
    issuer: APPLE_ISSUER,
    audience: audiences,
    clockTolerance: 5,
  });
  if (!payload.sub) throw new Error('Apple subject is missing');
  if (!safeEqual(payload.nonce, sha256(rawNonce))) {
    throw new Error('Apple nonce does not match');
  }
  return payload;
}

function createClientSecret(now = Math.floor(Date.now() / 1000)) {
  ensureAppleConfigured();
  return jwt.sign({}, applePrivateKey, {
    algorithm: 'ES256',
    keyid: appleKeyId,
    issuer: appleTeamId,
    audience: APPLE_ISSUER,
    subject: appleClientId,
    expiresIn: 300,
    notBefore: 0,
  });
}

async function postAppleForm(url, form) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(form),
    signal: AbortSignal.timeout(12000),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || data.error) {
    throw new Error(
      `Apple token endpoint rejected the request: ${data.error || response.status}`,
    );
  }
  return data;
}

async function exchangeAuthorizationCode(authorizationCode) {
  ensureAppleConfigured();
  return postAppleForm(APPLE_TOKEN_URL, {
    client_id: appleClientId,
    client_secret: createClientSecret(),
    code: authorizationCode,
    grant_type: 'authorization_code',
  });
}

async function revokeRefreshToken(refreshToken) {
  if (!refreshToken) return;
  ensureAppleConfigured();
  await postAppleForm(APPLE_REVOKE_URL, {
    client_id: appleClientId,
    client_secret: createClientSecret(),
    token: refreshToken,
    token_type_hint: 'refresh_token',
  });
}

function encryptionKey() {
  const key = Buffer.from(appleTokenEncryptionKey, 'base64');
  if (key.length !== 32) {
    throw new Error('APPLE_TOKEN_ENCRYPTION_KEY must be 32 bytes in base64');
  }
  return key;
}

function encryptRefreshToken(value) {
  if (!value) return '';
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const encrypted = Buffer.concat([
    cipher.update(String(value), 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return [iv, tag, encrypted].map((item) => item.toString('base64url')).join('.');
}

function decryptRefreshToken(value) {
  if (!value) return '';
  const [ivValue, tagValue, encryptedValue] = String(value).split('.');
  if (!ivValue || !tagValue || !encryptedValue) {
    throw new Error('Stored Apple refresh token is invalid');
  }
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    encryptionKey(),
    Buffer.from(ivValue, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(tagValue, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedValue, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}

module.exports = {
  APPLE_ISSUER,
  sha256,
  verifyIdentityToken,
  exchangeAuthorizationCode,
  revokeRefreshToken,
  encryptRefreshToken,
  decryptRefreshToken,
};
