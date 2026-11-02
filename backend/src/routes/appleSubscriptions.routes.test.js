const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const jwt = require('jsonwebtoken');
const { randomUUID } = require('node:crypto');
process.env.JWT_SECRET = 'iap-http-fixture-not-real';
process.env.DATABASE_URL = 'postgresql://not-used/fixture';
const users = require('../repositories/user.repository');
const { createAppleSubscriptionsRouter } = require('./appleSubscriptions.routes');
const { AppleIapError } = require('../services/appleIapError');
const { AppleSubscriptionService } = require('../services/appleSubscription.service');
const { appleSignedFixtures } = require('../../test-support/appleSignedFixtures');

test('IAP HTTP/auth/privacy boundary', async (t) => {
  const user = randomUUID();
  const other = randomUUID();
  const original = users.findAuthUserById;
  users.findAuthUserById = async (id) => id === user ? { id, account_status: 'active', token_version: 2 } : null;
  t.after(() => { users.findAuthUserById = original; });
  const token = jwt.sign({ id: user, tokenVersion: 2 }, process.env.JWT_SECRET);
  const seen = [];
  let failure;
  let allowed = true;
  let runtime = {
    config: { environment: 'Sandbox' },
    purchaseContext: async (id) => { seen.push(id); return { appAccountToken: randomUUID() }; },
    verifyPurchase: async (id, input) => { seen.push([id, input]); if (failure) throw failure; return { tier: 'PRO' }; },
    handleNotification: async () => { if (failure) throw failure; return { result: 'applied' }; },
    entitlements: async (id, environment) => { seen.push([id, environment]); return { tier: 'FREE' }; },
  };
  const app = express();
  app.use('/api', createAppleSubscriptionsRouter({ service: () => runtime,
    consumeRateLimit: async () => allowed }));
  app.get('/api/existing-route', (_req, res) => res.json({ existing: true }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const origin = 'http://127.0.0.1:' + server.address().port;
  async function request(path, body, authorization = token) {
    const result = await fetch(origin + '/api' + path, { method: body === undefined ? 'GET' : 'POST',
      headers: { 'Content-Type': 'application/json', ...(authorization ? { Authorization: 'Bearer ' + authorization } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: result.status, body: await result.json(), cache: result.headers.get('cache-control') };
  }
  await t.test('existing routes unaffected; JWT required, token version and deleted account checked', async () => {
    assert.equal((await request('/existing-route')).status, 200);
    assert.equal((await request('/subscriptions/apple/purchase-context', {}, null)).status, 401);
    assert.equal((await request('/subscriptions/apple/purchase-context', {}, jwt.sign({ id: other, tokenVersion: 2 }, process.env.JWT_SECRET))).status, 401);
    assert.equal((await request('/subscriptions/apple/purchase-context', {}, jwt.sign({ id: user, tokenVersion: 1 }, process.env.JWT_SECRET))).status, 401);
    assert.equal((await request('/subscriptions/apple/purchase-context', {})).status, 200);
    assert.equal(seen.at(-1), user);
  });
  await t.test('verification allows exactly one transaction input, never isPro/expires/user/environment', async () => {
    for (const body of [{}, { transactionId: '1', isPro: true }, { transactionId: '1', userId: other },
      { transactionId: '1', environment: 'Production' }, { transactionId: '1', signedTransactionInfo: 'x'.repeat(30) }]) {
      assert.equal((await request('/subscriptions/apple/verify', body)).status, 400);
    }
    assert.equal((await request('/subscriptions/apple/verify', { transactionId: '10001' })).status, 200);
    assert.deepEqual(seen.at(-1), [user, { transactionId: '10001' }]);
    assert.equal((await request('/me/entitlements?environment=Production')).status, 400);
    assert.equal((await request('/me/entitlements')).cache, 'no-store');
    assert.deepEqual(seen.at(-1), [user, 'Sandbox']);
  });
  await t.test('safe error bodies and request-size/rate bounds', async () => {
    failure = new Error('secret transaction/JWS must never escape');
    const result = await request('/subscriptions/apple/verify', { transactionId: '1' });
    assert.equal(result.status, 503);
    assert.equal(JSON.stringify(result.body).includes('secret'), false);
    failure = new AppleIapError('OWNERSHIP_CONFLICT', 409);
    assert.equal((await request('/subscriptions/apple/verify', { transactionId: '1' })).status, 409);
    assert.equal((await request('/apple/notifications', { signedPayload: 'x'.repeat(150000) }, null)).status, 413);
    allowed = false;
    assert.equal((await request('/subscriptions/apple/verify', { transactionId: '1' })).status, 429);
    allowed = true; failure = null;
  });
  await t.test('public notification route uses official signature verifier before any repository call', async () => {
    const f = appleSignedFixtures();
    try {
      let writes = 0;
      runtime = new AppleSubscriptionService({ config: f.config(), verifier: f.verifier(),
        repository: { recordNotification: async () => { writes++; return { result: 'test', processed_at: new Date() }; } } });
      const invalid = await request('/apple/notifications', { signedPayload: 'not-a-signed-apple-payload' }, null);
      assert.equal(invalid.status, 400); assert.equal(writes, 0);
      const tx = f.tx();
      const valid = await request('/apple/notifications', { signedPayload: f.notification(tx, f.renewal(tx), { notificationType: 'TEST' }) }, null);
      assert.equal(valid.status, 200); assert.equal(writes, 1);
    } finally { f.cleanup(); }
  });
});
