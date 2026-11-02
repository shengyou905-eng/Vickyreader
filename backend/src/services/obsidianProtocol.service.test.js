const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const p = require('./obsidianProtocol.service');
const config = { nodeEnv: 'test', redirectUris: ['obsidian://zhidu-sync', 'http://127.0.0.1:9876/callback'] };
const request = { response_type: 'code', client_id: p.CLIENT_ID, scope: p.SCOPE,
  redirect_uri: 'obsidian://zhidu-sync', code_challenge_method: 'S256',
  code_challenge: p.challenge('a'.repeat(43)), state: 's'.repeat(43) };

test('PKCE S256 matches RFC 7636 test vector', () => {
  assert.equal(p.challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
    'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
});
test('authorization allowlist, scope and strict input fail closed', () => {
  assert.deepEqual(p.authorizeInput(request, config), request);
  for (const patch of [{ code_challenge_method: 'plain' }, { scope: 'write' },
    { redirect_uri: 'https://attacker.invalid/callback' }, { state: 'short' },
    { user_id: crypto.randomUUID() }, { client_id: 'other' }]) {
    assert.throws(() => p.authorizeInput({ ...request, ...patch }, config), { statusCode: 400 });
  }
  assert.throws(() => p.authorizeInput({ ...request, redirect_uri: config.redirectUris[1] },
    { ...config, nodeEnv: 'production' }), { statusCode: 400 });
  assert.throws(() => p.authorizeInput(request, config, true), { statusCode: 400 });
});
test('signed cursors are grant-bound and preserve BIGINT precision', () => {
  const grant = crypto.randomUUID();
  const secret = crypto.randomBytes(32).toString('hex');
  const data = { v: 1, grant, mode: 'delta', after: '9007199254740993' };
  const cursor = p.signCursor(data, secret);
  assert.deepEqual(p.readCursor(cursor, grant, secret), data);
  for (const [value, owner] of [[cursor + 'x', grant], [cursor, crypto.randomUUID()], ['bad', grant]]) {
    assert.throws(() => p.readCursor(value, owner, secret), { statusCode: 400 });
  }
});
test('sync paging is bounded and rejects client-supplied ownership', () => {
  assert.deepEqual(p.syncInput({}), { limit: 50 });
  assert.equal(p.syncInput({ limit: '100' }).limit, 100);
  for (const query of [{ limit: '101' }, { limit: '0' }, { limit: '1.1' }, { user_id: 'x' }]) {
    assert.throws(() => p.syncInput(query), { statusCode: 400 });
  }
});
