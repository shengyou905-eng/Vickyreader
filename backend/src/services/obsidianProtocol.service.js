const crypto = require('node:crypto');
const { z } = require('zod');
const httpError = require('../utils/httpError');

const CLIENT_ID = 'zhidu-sync';
const SCOPE = 'obsidian.sync.read';
const TOKEN_TTL_SECONDS = 86400;
const CODE_TTL_SECONDS = 300;
const codePattern = /^zd_oc_[A-Za-z0-9_-]{43}$/;
const tokenPattern = /^zd_os_[A-Za-z0-9_-]{43}$/;
const sequence = z.string().regex(/^(0|[1-9][0-9]{0,18})$/)
  .refine(value => BigInt(value) <= 9223372036854775807n);

function digest(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}
function randomCredential(prefix) {
  return prefix + crypto.randomBytes(32).toString('base64url');
}
function challenge(verifier) {
  return crypto.createHash('sha256').update(verifier).digest('base64url');
}
function parse(schema, value) {
  const result = schema.safeParse(value);
  if (!result.success) throw httpError(400, 'invalid_request');
  return result.data;
}
function redirectAllowed(uri, config) {
  if (!config.redirectUris.includes(uri)) return false;
  try {
    const url = new URL(uri);
    if (url.username || url.password || url.hash || url.search) return false;
    return uri === 'obsidian://zhidu-sync'
      || url.protocol === 'https:'
      || (config.nodeEnv !== 'production' && url.protocol === 'http:'
        && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname));
  } catch (_) { return false; }
}
function authorizeInput(value, config, consent = false) {
  const shape = {
    response_type: z.literal('code'), client_id: z.literal(CLIENT_ID),
    redirect_uri: z.string().max(1000).refine(uri => redirectAllowed(uri, config)),
    scope: z.literal(SCOPE), code_challenge_method: z.literal('S256'),
    code_challenge: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
    state: z.string().regex(/^[A-Za-z0-9_-]{32,128}$/),
  };
  if (consent) shape.allow = z.boolean();
  return parse(z.object(shape).strict(), value);
}
function tokenInput(value, config) {
  return parse(z.object({
    grant_type: z.literal('authorization_code'), client_id: z.literal(CLIENT_ID),
    code: z.string().regex(codePattern),
    redirect_uri: z.string().max(1000).refine(uri => redirectAllowed(uri, config)),
    code_verifier: z.string().regex(/^[A-Za-z0-9._~-]{43,128}$/),
  }).strict(), value);
}
function syncInput(value) {
  return parse(z.object({
    cursor: z.string().min(1).max(2000).optional(),
    limit: z.coerce.number().int().min(1).max(100).default(50),
  }).strict(), value);
}
const cursorSchema = z.discriminatedUnion('mode', [
  z.object({ v: z.literal(1), grant: z.uuid(), mode: z.literal('delta'), after: sequence }).strict(),
  z.object({ v: z.literal(1), grant: z.uuid(), mode: z.literal('page'),
    snapshot: z.uuid(), after: sequence }).strict(),
]);
function signCursor(data, secret) {
  const body = Buffer.from(JSON.stringify(data)).toString('base64url');
  const signature = crypto.createHmac('sha256', secret).update(body).digest('base64url');
  return `${body}.${signature}`;
}
function readCursor(value, grantId, secret) {
  try {
    const parts = value.split('.');
    if (parts.length !== 2 || !/^[A-Za-z0-9_-]{43}$/.test(parts[1])) throw new Error();
    const expected = crypto.createHmac('sha256', secret).update(parts[0]).digest();
    const actual = Buffer.from(parts[1], 'base64url');
    if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) throw new Error();
    const cursor = cursorSchema.parse(JSON.parse(Buffer.from(parts[0], 'base64url').toString()));
    if (cursor.grant !== grantId) throw new Error();
    return cursor;
  } catch (_) { throw httpError(400, 'invalid_cursor'); }
}

module.exports = { CLIENT_ID, SCOPE, TOKEN_TTL_SECONDS, CODE_TTL_SECONDS,
  tokenPattern, digest, randomCredential, challenge, authorizeInput, tokenInput,
  syncInput, signCursor, readCursor };
