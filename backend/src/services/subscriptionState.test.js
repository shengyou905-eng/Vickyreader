const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { PRODUCTS, BUNDLE_ID, requireEnvironment } = require('../config/subscriptions');
const { parseSnapshot, snapshotHash, grantForSnapshot } = require('./subscriptionState');

const fixture = (overrides = {}) => ({
  environment: 'Sandbox', appAccountToken: randomUUID(),
  originalTransactionId: '100', transactionId: '101',
  productId: Object.keys(PRODUCTS)[0], status: 'active',
  purchasedAt: '2026-01-01T00:00:00Z', expiresAt: '2026-02-01T00:00:00Z',
  gracePeriodExpiresAt: null, revokedAt: null, autoRenew: true,
  signedAt: '2026-01-01T00:00:01Z', ...overrides,
});

test('product IDs are explicit, mapped to pro, and separate from Bundle ID', () => {
  assert.equal(BUNDLE_ID, 'com.youxugarden.zhireader');
  assert.deepEqual(Object.keys(PRODUCTS), [
    'com.youxugarden.zhreader.pro.monthly', 'com.youxugarden.zhreader.pro.yearly',
  ]);
  for (const product of Object.values(PRODUCTS)) assert.equal(product.entitlement, 'pro');
});

test('environment is mandatory; TestFlight uses Apple Sandbox, not a fabricated environment', () => {
  for (const value of [undefined, '', 'sandbox', 'TestFlight']) assert.throws(() => requireEnvironment(value));
  assert.equal(requireEnvironment('Sandbox'), 'Sandbox');
  assert.equal(requireEnvironment('Production'), 'Production');
});

test('cancel auto-renew does not remove the paid entitlement', () => {
  const state = parseSnapshot(fixture({ autoRenew: false }));
  const grant = grantForSnapshot(state);
  assert.equal(grant.enabled, true);
  assert.equal(grant.validUntil, state.expiresAt);
});

test('grace uses verified deadline; billing retry does not invent a grace extension', () => {
  const state = parseSnapshot(fixture({ status: 'grace_period', gracePeriodExpiresAt: '2026-02-08T00:00:00Z' }));
  assert.equal(grantForSnapshot(state).validUntil, state.gracePeriodExpiresAt);
  state.status = 'billing_retry';
  assert.equal(grantForSnapshot(state).validUntil, state.expiresAt);
});

test('expired and revoked snapshots disable the grant', () => {
  assert.equal(grantForSnapshot(parseSnapshot(fixture({ status: 'expired' }))).enabled, false);
  const revoked = parseSnapshot(fixture({ status: 'revoked', revokedAt: '2026-01-15T00:00:00Z' }));
  assert.equal(grantForSnapshot(revoked).enabled, false);
  assert.equal(grantForSnapshot(revoked).revokedAt, revoked.revokedAt);
});

test('schema rejects unknown products, isPro, missing token, bad dates and impossible state', () => {
  for (const fields of [
    { productId: 'unknown' }, { isPro: true }, { appAccountToken: null },
    { expiresAt: 'not-a-date' }, { expiresAt: '2025-01-01T00:00:00Z' },
    { status: 'grace_period' }, { status: 'revoked' },
    { revokedAt: '2026-01-15T00:00:00Z' },
    { gracePeriodExpiresAt: '2026-01-10T00:00:00Z' },
    { environment: 'TestFlight' },
  ]) assert.throws(() => parseSnapshot(fixture(fields)));
});

test('snapshot hashes normalize time offsets, preserve changes, and do not contain tokens', () => {
  const state = fixture();
  const a = parseSnapshot(state);
  const b = parseSnapshot({ ...state, purchasedAt: '2026-01-01T08:00:00+08:00' });
  assert.equal(snapshotHash(a), snapshotHash(b));
  assert.notEqual(snapshotHash(a), snapshotHash({ ...a, autoRenew: false }));
  assert.equal(snapshotHash(a), snapshotHash({ ...a, appAccountToken: randomUUID() }));
});

test('fresh schema and migration 008 contain exactly the same subscription DDL', () => {
  const base = path.join(__dirname, '../db');
  const schema = fs.readFileSync(path.join(base, 'schema.sql'), 'utf8');
  const up = fs.readFileSync(path.join(base, 'migrations/008_app_store_subscriptions.up.sql'), 'utf8');
  const block = schema.split('-- BEGIN SUBSCRIPTION SCHEMA 008')[1].split('-- END SUBSCRIPTION SCHEMA 008')[0].trim();
  const migration = up.slice(up.indexOf('-- Phase 1 storage only.')).replace(/COMMIT;\s*$/, '').trim();
  assert.equal(block.replaceAll('\r\n', '\n'), migration.replaceAll('\r\n', '\n'));
});
