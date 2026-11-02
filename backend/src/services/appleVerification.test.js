const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID, generateKeyPairSync } = require('node:crypto');
const jwt = require('jsonwebtoken');
const { SignedDataVerifier, VerificationException, VerificationStatus } = require('@apple/app-store-server-library');
const { appleSignedFixtures } = require('../../test-support/appleSignedFixtures');
const { AppleTransactionVerifier } = require('./appleTransactionVerifier');
const { AppleServerApi, BoundedAppleClient } = require('./appleServerApi');
const { readAppleIapConfig } = require('../config/appleIap');

test('official Apple signature/certificate verification with synthetic CA (NOT real Apple Sandbox)', async (t) => {
  const f = appleSignedFixtures();
  t.after(f.cleanup);
  const verifier = f.verifier();
  const tx = f.tx();
  const rn = f.renewal(tx);
  await t.test('valid Sandbox transaction, renewal and V2 envelope', async () => {
    assert.equal((await verifier.verifyTransaction(f.sign(tx))).transactionId, tx.transactionId);
    assert.equal((await verifier.verifyRenewal(f.sign(rn), tx)).autoRenewStatus, 1);
    assert.equal((await verifier.verifyNotification(f.notification(tx, rn))).type, 'DID_RENEW');
  });
  await t.test('Production JWS verifies only under matching environment and numeric app ID', async () => {
    const production = { ...tx, environment: 'Production' };
    assert.equal((await f.verifier('Production').verifyTransaction(f.sign(production))).environment, 'Production');
    await assert.rejects(verifier.verifyTransaction(f.sign(production)), { code: 'APPLE_SIGNATURE_INVALID' });
    await assert.rejects(f.verifier('Production').verifyTransaction(f.sign(tx)), { code: 'APPLE_SIGNATURE_INVALID' });
    await assert.rejects(f.verifier('Production').verifyNotification(f.notification(production, f.renewal(production), {
      data: { environment: 'Production', bundleId: tx.bundleId, appAppleId: 999 },
    })), { code: 'APPLE_SIGNATURE_INVALID' });
  });
  await t.test('tampered payload/signature, wrong bundle and untrusted root fail cryptographically', async () => {
    const signed = f.sign(tx).split('.');
    signed[1] = Buffer.from(JSON.stringify({ ...tx, expiresDate: tx.expiresDate + 1000 })).toString('base64url');
    await assert.rejects(verifier.verifyTransaction(signed.join('.')), { code: 'APPLE_SIGNATURE_INVALID' });
    await assert.rejects(verifier.verifyTransaction(f.sign({ ...tx, bundleId: 'wrong.app' })), { code: 'APPLE_SIGNATURE_INVALID' });
    const untrusted = new AppleTransactionVerifier(f.config(), new SignedDataVerifier([], false, 'Sandbox', tx.bundleId));
    await assert.rejects(untrusted.verifyTransaction(f.sign(tx)), { code: 'APPLE_SIGNATURE_INVALID' });
    await assert.rejects(verifier.verifyTransaction(f.sign(tx, { x5c: [] })), { code: 'APPLE_SIGNATURE_INVALID' });
  });
  await t.test('certificate expired at signing time is rejected; unknown product and family sharing rejected', async () => {
    await assert.rejects(verifier.verifyTransaction(f.sign({ ...tx, signedDate: Date.now() + 5 * 86400000 })), { code: 'APPLE_SIGNATURE_INVALID' });
    for (const patch of [{ productId: 'unknown' }, { inAppOwnershipType: 'FAMILY_SHARED' },
      { expiresDate: tx.purchaseDate }, { appAccountToken: undefined }]) {
      await assert.rejects(verifier.verifyTransaction(f.sign({ ...tx, ...patch })), { code: 'APPLE_TRANSACTION_INVALID' });
    }
  });
  await t.test('renewal token/original ID mismatch fails and retryable OCSP does not imply invalid entitlement', async () => {
    await assert.rejects(verifier.verifyRenewal(f.sign({ ...rn, appAccountToken: randomUUID() }), tx), { code: 'APPLE_RENEWAL_INVALID' });
    const offline = new AppleTransactionVerifier(f.config(), { verifyAndDecodeTransaction: async () => {
      throw new VerificationException(VerificationStatus.RETRYABLE_VERIFICATION_FAILURE);
    } });
    await assert.rejects(offline.verifyTransaction(f.sign(tx)), { code: 'APPLE_VERIFICATION_UNAVAILABLE' });
  });
  await t.test('unknown notification type is verified, not crashed or treated as purchase', async () => {
    assert.equal((await verifier.verifyNotification(f.notification(tx, rn, { notificationType: 'FUTURE_EVENT' }))).type, 'FUTURE_EVENT');
  });
  await t.test('API adapter validates signed responses and current chain; trusts no supplied dates', async () => {
    const api = new AppleServerApi(f.config(), verifier, {
      getTransactionInfo: async () => ({ signedTransactionInfo: f.sign(tx) }),
      getAllSubscriptionStatuses: async () => f.response(tx, rn),
    });
    assert.equal((await api.getTransaction(tx.transactionId)).appAccountToken, tx.appAccountToken);
    const snapshot = await api.getCurrentSnapshot(tx.originalTransactionId, { tx, renewal: rn });
    assert.equal(snapshot.state.status, 'active');
    assert.equal(snapshot.state.expiresAt, new Date(tx.expiresDate).toISOString());
    await assert.rejects(api.getTransaction('99999'), { code: 'APPLE_RESPONSE_MISMATCH' });
    await assert.rejects(api.getCurrentSnapshot('99999'), { code: 'APPLE_STATE_NOT_CURRENT' });
    await assert.rejects(api.getCurrentSnapshot(tx.originalTransactionId, { tx: { ...tx, signedDate: tx.signedDate + 1 } }), { code: 'APPLE_STATE_NOT_CURRENT' });
  });
  await t.test('Apple temporary errors, wrong API environment and invalid response signatures fail closed', async () => {
    const api = new AppleServerApi(f.config(), verifier, { getAllSubscriptionStatuses: async () => { throw new Error('sensitive response'); } });
    await assert.rejects(api.getCurrentSnapshot(tx.originalTransactionId), { code: 'APPLE_API_UNAVAILABLE' });
    api.client.getAllSubscriptionStatuses = async () => ({ ...f.response(tx, rn), environment: 'Production' });
    await assert.rejects(api.getCurrentSnapshot(tx.originalTransactionId), { code: 'APPLE_RESPONSE_MISMATCH' });
    api.client.getAllSubscriptionStatuses = async () => f.response({ ...tx, bundleId: 'wrong.app' }, rn);
    await assert.rejects(api.getCurrentSnapshot(tx.originalTransactionId), { code: 'APPLE_SIGNATURE_INVALID' });
  });
  await t.test('official API client signs server credentials; correct host and bounded transport', async () => {
    const pair = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const privateKey = pair.privateKey.export({ type: 'pkcs8', format: 'pem' });
    const issuer = randomUUID(); const original = global.fetch;
    let calls = 0;
    global.fetch = async (url, options) => {
      calls++;
      assert.equal(new URL(url).hostname, calls === 1 ? 'api.storekit-sandbox.apple.com' : 'api.storekit.apple.com');
      assert.ok(options.signal instanceof AbortSignal);
      assert.equal(options.redirect, 'error');
      const token = options.headers.Authorization.slice(7);
      const claims = jwt.verify(token, pair.publicKey, { algorithms: ['ES256'], issuer, audience: 'appstoreconnect-v1' });
      assert.equal(claims.bid, tx.bundleId);
      return new Response(JSON.stringify({ signedTransactionInfo: f.sign(tx) }), { status: 200 });
    };
    try {
      for (const environment of ['Sandbox', 'Production']) {
        const client = new BoundedAppleClient(privateKey, 'TESTKEY123', issuer, tx.bundleId, environment);
        assert.ok((await client.getTransactionInfo(tx.transactionId)).signedTransactionInfo);
      }
    } finally { global.fetch = original; }
  });
  await t.test('runtime verifier always enables online certificate checks', () => {
    assert.equal(new AppleTransactionVerifier(f.config()).verifier.enableOnlineChecks, true);
  });
  await t.test('inactive config and missing credentials return sanitized errors', () => {
    assert.throws(() => readAppleIapConfig({}), { code: 'APPLE_IAP_DISABLED' });
    assert.throws(() => readAppleIapConfig({ APPLE_IAP_ENABLED: 'true', APPLE_IAP_ENVIRONMENT: 'Xcode' }), { code: 'APPLE_IAP_NOT_CONFIGURED' });
  });
});
