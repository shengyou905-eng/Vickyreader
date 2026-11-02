process.env.JWT_SECRET ||= 'unit-test-not-production-jwt-secret';
process.env.DATABASE_URL ||= 'postgres://localhost/unused_test';
const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const crypto = require('node:crypto');
const { createObsidianRouter } = require('./obsidian.routes');
const p = require('../services/obsidianProtocol.service');

test('HTTP boundary: separate tokens, consent, strict queries, safe errors, revocation', async () => {
  const calls = [];
  const grant = { id: crypto.randomUUID(), user_id: crypto.randomUUID(), scope: p.SCOPE, expires_at: new Date() };
  const bearer = p.randomCredential('zd_os_');
  let revoked = false;
  let failure = false;
  const app = express();
  app.use(express.json());
  app.use('/api/integrations/obsidian', createObsidianRouter({
    config: { enabled: true, cursorSecret: 'test-cursor-secret'.repeat(3), nodeEnv: 'test', redirectUris: ['obsidian://zhidu-sync'] },
    consumeRateLimit: async () => true,
    sessionAuth: (req, res, next) => {
      if (req.headers.authorization !== 'Bearer app-test-session') return res.sendStatus(401);
      req.user = { id: grant.user_id }; req.authUser = { token_version: 0 }; next();
    },
    accounts: {
      createCode: async (...args) => calls.push(args),
      exchangeCode: async () => {},
      authenticate: async token => token === bearer && !revoked ? grant : null,
      revoke: async token => { if (token === bearer) revoked = true; },
    },
    exports: { sync: async (owner, input) => {
      assert.equal(owner.user_id, grant.user_id);
      if (failure) throw new Error('private-reading-body-must-not-leak');
      return { schema_version: 1, next_cursor: 'synthetic', has_more: false, changes: [], limit: input.limit };
    } },
  }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/api/integrations/obsidian`;
  const get = (route, token) => fetch(base + route, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  const post = (route, body, token) => fetch(base + route, { method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
  try {
    for (const token of [undefined, 'app-test-session', p.randomCredential('zd_mcp_'), p.randomCredential('zd_os_')]) {
      assert.equal((await get('/sync', token)).status, 401);
    }
    const input = { response_type: 'code', client_id: p.CLIENT_ID, scope: p.SCOPE,
      redirect_uri: 'obsidian://zhidu-sync', code_challenge_method: 'S256',
      code_challenge: p.challenge('a'.repeat(43)), state: 's'.repeat(43) };
    const page = await get('/authorize?' + new URLSearchParams(input));
    assert.equal(page.status, 200);
    assert.match(await page.text(), /PKCE|Zhidu Sync/);
    assert.equal(page.headers.get('referrer-policy'), 'no-referrer');
    assert.match(page.headers.get('content-security-policy'), /frame-ancestors 'none'/);
    assert.equal((await post('/authorize', { ...input, allow: true }, bearer)).status, 401);
    const deny = await post('/authorize', { ...input, allow: false }, 'app-test-session');
    assert.equal(new URL((await deny.json()).redirect_uri).searchParams.get('error'), 'access_denied');
    assert.equal(calls.length, 0);
    const approve = await post('/authorize', { ...input, allow: true }, 'app-test-session');
    const redirect = new URL((await approve.json()).redirect_uri);
    assert.equal(redirect.searchParams.get('state'), input.state);
    assert.match(redirect.searchParams.get('code'), /^zd_oc_/);
    assert.equal(calls[0][0], grant.user_id);
    assert.equal((await get('/sync?user_id=foreign', bearer)).status, 400);
    assert.equal((await get('/sync?limit=101', bearer)).status, 400);
    const response = await get('/sync', bearer);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal((await response.json()).limit, 50);
    failure = true;
    const failed = await get('/sync', bearer);
    assert.equal(failed.status, 500);
    assert.equal((await failed.json()).error, 'integration_unavailable');
    assert.equal((await post('/revoke', {}, bearer)).status, 204);
    assert.equal((await post('/revoke', {}, bearer)).status, 204);
    assert.equal((await get('/sync', bearer)).status, 401);
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});
