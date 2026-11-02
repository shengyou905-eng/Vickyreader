const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { Client } = require('pg');
const { appleSignedFixtures } = require('../../test-support/appleSignedFixtures');

const target = process.env.APPLE_IAP_TEST_DATABASE_URL;
if (!target) {
  test('Apple Phase 2 real PostgreSQL', { skip: 'APPLE_IAP_TEST_DATABASE_URL not set' }, () => {});
} else {
  const url = new URL(target);
  if (!['127.0.0.1', 'localhost'].includes(url.hostname) || url.port !== '55442'
      || url.pathname !== '/zhidu_subscription_phase1_test') throw new Error('Use disposable localhost:55442/zhidu_subscription_phase1_test');
  const schema = 'appletest_' + randomUUID().replaceAll('-', '');
  url.searchParams.set('options', '-c search_path=' + schema + ',public');
  process.env.DATABASE_URL = url.toString();
  process.env.JWT_SECRET = 'phase2-isolated-fixture-not-real';
  const db = require('../config/db');
  const repository = require('./subscription.repository');
  const { getEntitlements } = require('../services/entitlement.service');
  const { AppleServerApi } = require('../services/appleServerApi');
  const { AppleSubscriptionService } = require('../services/appleSubscription.service');
  const ddl = (file) => fs.readFileSync(path.join(__dirname, '../db', file), 'utf8');
  let chain = 200000;
  let signed = Date.now();

  test('Phase 2 official signed fixtures -> service -> real PostgreSQL (no real Apple purchases)', async (t) => {
    const f = appleSignedFixtures();
    t.after(f.cleanup);
    const admin = new Client({ connectionString: target });
    await admin.connect();
    await admin.query('CREATE SCHEMA ' + schema);
    const migration = new Client({ connectionString: url.toString() });
    await migration.connect();
    t.after(async () => {
      await db.closePool(); await migration.end();
      await admin.query('DROP SCHEMA ' + schema + ' CASCADE'); await admin.end();
    });
    await migration.query(ddl('schema.sql'));

    const fixture = async (environment = 'Sandbox') => {
      const user = randomUUID();
      await db.query('INSERT INTO users (id,email,password_hash) VALUES ($1,$2,$3)', [user, user + '@example.invalid', 'fixture']);
      const account = await repository.getOrCreateAccount(user, environment);
      let tx = f.tx({ environment, originalTransactionId: String(++chain), transactionId: String(chain),
        appAccountToken: account.app_account_token, signedDate: ++signed });
      let rn = f.renewal(tx);
      let status = 1;
      let unavailable = false;
      const verifier = f.verifier(environment);
      const api = new AppleServerApi(f.config(environment), verifier, {
        getTransactionInfo: async () => ({ signedTransactionInfo: f.sign(tx) }),
        getAllSubscriptionStatuses: async () => {
          if (unavailable) throw new Error('temporary API failure');
          return f.response(tx, rn, status);
        },
      });
      const service = new AppleSubscriptionService({ config: f.config(environment), verifier, api, repository, entitlements: getEntitlements });
      return { user, account, service, api, tx: () => tx, rn: () => rn,
        set: (patch = {}, renewalPatch = {}, nextStatus = status) => {
          tx = { ...tx, signedDate: ++signed, ...patch };
          rn = { ...rn, signedDate: ++signed, ...renewalPatch }; status = nextStatus;
        },
        unavailable: (value) => { unavailable = value; },
        purchase: () => service.verifyPurchase(user, { signedTransactionInfo: f.sign(tx) }),
        notify: (type, changes = {}) => service.handleNotification(f.notification(tx, rn, { notificationType: type, ...changes })),
        entitlement: () => getEntitlements(user, environment),
      };
    };
    const row = async (x) => (await db.query('SELECT * FROM subscriptions WHERE account_id=$1', [x.account.id])).rows[0];

    await t.test('009 repeatable migration, empty rollback, preserves 008 subscription on upgrade, schema parity', async () => {
      const up = ddl('migrations/009_apple_subscription_verification.up.sql');
      const full = ddl('schema.sql').split('-- BEGIN SUBSCRIPTION SCHEMA 009\n')[1].split('-- END SUBSCRIPTION SCHEMA 009')[0];
      assert.equal(full.trim(), up.split("SET LOCAL statement_timeout = '60s';\n")[1].split('COMMIT;')[0].trim());
      await migration.query(up); await migration.query(up);
      await migration.query(ddl('migrations/009_apple_subscription_verification.down.sql'));
      const user = randomUUID();
      await db.query('INSERT INTO users (id,email,password_hash) VALUES ($1,$2,$3)', [user, user + '@example.invalid', 'fixture']);
      const account = await repository.getOrCreateAccount(user, 'Sandbox');
      const owner = (await db.query(`INSERT INTO subscription_ownership
        (provider,environment,original_transaction_id,account_id) VALUES ('apple_app_store','Sandbox',$1,$2) RETURNING id`,
      [String(++chain), account.id])).rows[0];
      // Seed the actual 008 column set, before 009 exists, not a parallel business implementation.
      await db.query(`INSERT INTO subscriptions (ownership_id,account_id,environment,product_id,
        latest_transaction_id,status,purchased_at,expires_at,auto_renew_status,signed_at,snapshot_hash)
        VALUES ($1,$2,'Sandbox',$3,$4,'active','2020-01-01','2090-01-01',true,'2026-01-01',$5)`,
      [owner.id, account.id, f.tx().productId, String(chain), '0'.repeat(64)]);
      await migration.query(up);
      const legacy = (await db.query('SELECT * FROM subscriptions WHERE ownership_id=$1', [owner.id])).rows[0];
      assert.equal(legacy.status, 'active'); assert.equal(legacy.transaction_signed_at, null);
      assert.equal(legacy.latest_transaction_id, String(chain));
    });
    await t.test('stable purchase context, first purchase and SUBSCRIBED; server authoritative PRO', async () => {
      const x = await fixture();
      const context = await x.service.purchaseContext(x.user);
      assert.equal(context.appAccountToken, x.account.app_account_token);
      assert.equal((await x.purchase()).tier, 'PRO');
      assert.equal((await x.notify('SUBSCRIBED')).result, 'replay');
      assert.ok((await row(x)).transaction_signed_at);
    });
    await t.test('DID_RENEW advances paid period; cancel auto renew keeps Pro', async () => {
      const x = await fixture(); await x.purchase();
      const original = x.tx();
      x.set({ transactionId: String(++chain), purchaseDate: original.purchaseDate + 1000, expiresDate: original.expiresDate + 1000 });
      assert.equal((await x.notify('DID_RENEW')).result, 'applied');
      x.set({}, { autoRenewStatus: 0 });
      await x.notify('DID_CHANGE_RENEWAL_STATUS', { subtype: 'AUTO_RENEW_DISABLED' });
      const value = await x.entitlement();
      assert.equal(value.tier, 'PRO'); assert.equal(value.pro.autoRenew, false);
    });
    await t.test('billing retry respects remaining paid time, grace deadline and expiration', async () => {
      const x = await fixture(); await x.purchase();
      x.set({}, {}, 3); await x.notify('DID_FAIL_TO_RENEW');
      assert.equal((await x.entitlement()).tier, 'PRO');
      x.set({ expiresDate: Date.now() - 1000 }, {}, 3); await x.notify('DID_FAIL_TO_RENEW');
      assert.equal((await x.entitlement()).tier, 'FREE');
      x.set({}, { gracePeriodExpiresDate: Date.now() + 86400000 }, 4);
      await x.notify('DID_FAIL_TO_RENEW', { subtype: 'GRACE_PERIOD' });
      assert.equal((await x.entitlement()).tier, 'PRO');
      x.set({}, {}, 3); await x.notify('GRACE_PERIOD_EXPIRED');
      assert.equal((await x.entitlement()).tier, 'FREE');
      x.set({}, {}, 2); await x.notify('EXPIRED');
      assert.equal((await row(x)).status, 'expired');
    });
    await t.test('expired signed active transaction cannot grant Pro without a notification', async () => {
      const x = await fixture(); x.set({ expiresDate: Date.now() - 1 });
      assert.equal((await x.purchase()).tier, 'FREE');
    });
    for (const type of ['REFUND', 'REVOKE']) await t.test(type + ' revokes current period', async () => {
      const x = await fixture(); await x.purchase();
      x.set({ revocationDate: Date.now() }, {}, 5); await x.notify(type);
      assert.equal((await x.entitlement()).tier, 'FREE');
      assert.equal((await row(x)).status, 'revoked');
    });
    await t.test('duplicate UUID concurrently mutates once; altered same UUID is rejected', async () => {
      const x = await fixture(); await x.purchase(); x.set({}, { autoRenewStatus: 0 });
      const id = randomUUID(); const payload = f.notification(x.tx(), x.rn(), { notificationUUID: id });
      const results = await Promise.all(Array.from({ length: 5 }, () => x.service.handleNotification(payload)));
      assert.equal(results.filter((value) => value.result === 'applied').length, 1);
      assert.equal((await db.query('SELECT count(*) FROM subscription_events WHERE notification_uuid=$1', [id])).rows[0].count, '1');
      await assert.rejects(x.notify('EXPIRED', { notificationUUID: id }), { code: 'EVENT_CONFLICT' });
    });
    await t.test('late old cancel/REFUND cannot replace renewed current state', async () => {
      const x = await fixture(); await x.purchase();
      const old = x.tx(); const oldRn = x.rn();
      const lateCancel = f.notification(old, { ...oldRn, autoRenewStatus: 0 }, { notificationType: 'DID_CHANGE_RENEWAL_STATUS' });
      const lateRefund = f.notification({ ...old, revocationDate: Date.now() }, oldRn, { notificationType: 'REFUND' });
      x.set({ transactionId: String(++chain), purchaseDate: old.purchaseDate + 1000, expiresDate: old.expiresDate + 1000 });
      await x.notify('DID_RENEW');
      await x.service.handleNotification(lateCancel); await x.service.handleNotification(lateRefund);
      assert.equal((await x.entitlement()).tier, 'PRO');
      assert.equal((await x.entitlement()).pro.autoRenew, true);
      assert.equal((await row(x)).latest_transaction_id, x.tx().transactionId);
    });
    await t.test('component clocks reject old renewal even with newer transaction signature', async () => {
      const x = await fixture(); await x.purchase();
      const old = x.rn(); x.set({}, { autoRenewStatus: 0 }); await x.notify('DID_CHANGE_RENEWAL_STATUS');
      const before = await row(x);
      x.set({}, old);
      await assert.rejects(x.service.reconcileAppleSubscription(x.tx().originalTransactionId), { code: 'APPLE_STATE_NOT_CURRENT' });
      assert.deepEqual(await row(x), before);
    });
    await t.test('new signatures on older paid period cannot roll back current transaction', async () => {
      const x = await fixture(); await x.purchase(); const old = x.tx();
      x.set({ transactionId: String(++chain), purchaseDate: old.purchaseDate + 1000 }); await x.notify('DID_RENEW');
      x.set({ transactionId: old.transactionId, purchaseDate: old.purchaseDate });
      await assert.rejects(x.notify('DID_RENEW'), { code: 'APPLE_STATE_NOT_CURRENT' });
      assert.notEqual((await row(x)).latest_transaction_id, old.transactionId);
    });
    await t.test('later paid transaction is authoritative even when previous period was re-signed later', async () => {
      const x = await fixture(); await x.purchase(); const old = x.tx();
      x.set({ transactionId: String(++chain), purchaseDate: old.purchaseDate + 1000,
        signedDate: old.signedDate - 1 });
      assert.equal((await x.notify('DID_RENEW')).result, 'applied');
      assert.equal((await row(x)).latest_transaction_id, x.tx().transactionId);
    });
    await t.test('same component versions with conflicting verified content do not overwrite', async () => {
      const x = await fixture(); await x.purchase(); const old = x.tx(); const oldRn = x.rn();
      x.set({ ...old }, { ...oldRn, autoRenewStatus: 0 });
      await assert.rejects(x.notify('DID_CHANGE_RENEWAL_STATUS'), { code: 'APPLE_STATE_NOT_CURRENT' });
      assert.equal((await x.entitlement()).pro.autoRenew, true);
    });
    await t.test('unknown type and TEST audit without mutating entitlement', async () => {
      const x = await fixture(); await x.purchase(); const before = await row(x);
      assert.equal((await x.notify('FUTURE_NOTIFICATION')).result, 'ignored');
      assert.equal((await x.notify('TEST')).result, 'test');
      assert.deepEqual(await row(x), before);
    });
    await t.test('wrong-user binding and signed appAccountToken mismatch are rejected and audited', async () => {
      const a = await fixture(); const b = await fixture(); await a.purchase();
      await assert.rejects(b.service.verifyPurchase(b.user, { signedTransactionInfo: f.sign(a.tx()) }), { code: 'APPLE_STATE_NOT_CURRENT' });
      // Use the SAME verified Apple chain/current response, with another authenticated user.
      await assert.rejects(a.service.verifyPurchase(b.user, { signedTransactionInfo: f.sign(a.tx()) }), { code: 'ACCOUNT_TOKEN_MISMATCH' });
      const token = b.account.app_account_token;
      a.set({ appAccountToken: token }, { appAccountToken: token });
      await assert.rejects(a.service.verifyPurchase(b.user, { signedTransactionInfo: f.sign(a.tx()) }), { code: 'OWNERSHIP_CONFLICT' });
      assert.equal((await b.entitlement()).tier, 'FREE');
    });
    await t.test('orphan verified notification audits but never auto-binds; explicit binding + reconcile recovers it', async () => {
      const x = await fixture();
      assert.equal((await x.notify('SUBSCRIBED')).result, 'awaiting_binding');
      assert.equal(await repository.lookupOwnership('Sandbox', x.tx().originalTransactionId), null);
      await x.purchase(); await x.service.reconcileAppleSubscription(x.tx().originalTransactionId);
      assert.equal((await repository.pendingNotifications('Sandbox', x.tx().originalTransactionId)).length, 0);
      assert.equal((await x.entitlement()).tier, 'PRO');
    });
    await t.test('account erasure removes orphan/details; retired chain cannot be reclaimed', async () => {
      const x = await fixture(); await x.notify('SUBSCRIBED'); await x.purchase();
      await db.query('DELETE FROM users WHERE id=$1', [x.user]);
      assert.equal((await db.query('SELECT count(*) FROM subscription_events WHERE original_transaction_id=$1', [x.tx().originalTransactionId])).rows[0].count, '0');
      assert.equal((await x.notify('DID_RENEW')).result, 'account_deleted');
      const b = await fixture(); const token = b.account.app_account_token;
      x.set({ appAccountToken: token }, { appAccountToken: token });
      await assert.rejects(x.service.verifyPurchase(b.user, { signedTransactionInfo: f.sign(x.tx()) }), { code: 'ACCOUNT_DELETED' });
      assert.equal((await b.entitlement()).tier, 'FREE');
    });
    await t.test('unclaimed notification audit follows known token account erasure; unknown token never creates a user', async () => {
      const x = await fixture(); await x.notify('SUBSCRIBED');
      assert.equal(await repository.lookupOwnership('Sandbox', x.tx().originalTransactionId), null);
      await db.query('DELETE FROM users WHERE id=$1', [x.user]);
      assert.equal((await db.query('SELECT count(*) FROM subscription_events WHERE original_transaction_id=$1', [x.tx().originalTransactionId])).rows[0].count, '0');
      const before = (await db.query('SELECT count(*) FROM subscription_accounts')).rows[0].count;
      const unknown = f.tx({ originalTransactionId: String(++chain), transactionId: String(chain) });
      const result = await x.service.handleNotification(f.notification(unknown, f.renewal(unknown), { notificationType: 'SUBSCRIBED' }));
      assert.equal(result.result, 'awaiting_binding');
      assert.equal((await db.query('SELECT count(*) FROM subscription_accounts')).rows[0].count, before);
    });
    await t.test('API outage keeps existing grant, event retryable; later reconcile restores current state', async () => {
      const x = await fixture(); await x.purchase(); const before = await row(x);
      x.set({}, { autoRenewStatus: 0 }); x.unavailable(true);
      await assert.rejects(x.notify('DID_CHANGE_RENEWAL_STATUS'), { code: 'APPLE_API_UNAVAILABLE' });
      assert.deepEqual(await row(x), before); assert.equal((await x.entitlement()).tier, 'PRO');
      const event = (await db.query("SELECT * FROM subscription_events WHERE original_transaction_id=$1 AND result='retry_pending'", [x.tx().originalTransactionId])).rows[0];
      assert.equal(event.processed_at, null); assert.equal(event.attempts, 1);
      x.unavailable(false); await x.service.reconcileAppleSubscription(x.tx().originalTransactionId);
      assert.equal((await x.entitlement()).pro.autoRenew, false);
      assert.equal((await repository.pendingNotifications('Sandbox', x.tx().originalTransactionId)).length, 0);
    });
    await t.test('reconciliation never ACKs a pending event newer than the fetched Apple snapshot', async () => {
      const x = await fixture(); await x.purchase(); const old = x.tx(); const oldRn = x.rn();
      x.set({}, { autoRenewStatus: 0 }); const current = x.tx(); const currentRn = x.rn();
      x.unavailable(true); await assert.rejects(x.notify('DID_CHANGE_RENEWAL_STATUS'), { code: 'APPLE_API_UNAVAILABLE' });
      x.unavailable(false); x.set(old, oldRn);
      await assert.rejects(x.service.reconcileAppleSubscription(old.originalTransactionId), { code: 'APPLE_STATE_NOT_CURRENT' });
      assert.equal((await repository.pendingNotifications('Sandbox', old.originalTransactionId)).length, 1);
      x.set(current, currentRn); await x.service.reconcileAppleSubscription(old.originalTransactionId);
      assert.equal((await repository.pendingNotifications('Sandbox', old.originalTransactionId)).length, 0);
    });
    await t.test('notification grant-write failure rolls back subscription/grant/audit completion and retries', async () => {
      const x = await fixture(); await x.purchase(); const before = await row(x); x.set({}, { autoRenewStatus: 0 });
      const payload = f.notification(x.tx(), x.rn());
      await db.query(`CREATE FUNCTION fail_grant() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test fault'; END $$;
        CREATE TRIGGER fail_grant BEFORE INSERT OR UPDATE ON entitlement_grants FOR EACH ROW EXECUTE FUNCTION fail_grant()`);
      try {
        await assert.rejects(x.service.handleNotification(payload), { code: 'APPLE_PROCESSING_UNAVAILABLE' });
        assert.deepEqual(await row(x), before); assert.equal((await x.entitlement()).pro.autoRenew, true);
      } finally { await db.query('DROP TRIGGER fail_grant ON entitlement_grants; DROP FUNCTION fail_grant()'); }
      assert.equal((await x.service.handleNotification(payload)).result, 'applied');
      assert.equal((await x.entitlement()).pro.autoRenew, false);
    });
    await t.test('same transaction/notification IDs isolated in Production and Sandbox at service AND DB', async () => {
      const a = await fixture(); const b = await fixture('Production');
      b.set({ originalTransactionId: a.tx().originalTransactionId, transactionId: a.tx().transactionId },
        { originalTransactionId: a.tx().originalTransactionId });
      await a.purchase(); await b.purchase(); const id = randomUUID();
      await a.notify('SUBSCRIBED', { notificationUUID: id }); await b.notify('SUBSCRIBED', { notificationUUID: id });
      assert.equal((await db.query('SELECT count(*) FROM subscription_events WHERE notification_uuid=$1', [id])).rows[0].count, '2');
      assert.equal((await getEntitlements(a.user, 'Production')).tier, 'FREE');
      assert.equal((await b.entitlement()).tier, 'PRO');
      await assert.rejects(b.service.verifyPurchase(b.user, { signedTransactionInfo: f.sign(a.tx()) }), { code: 'APPLE_SIGNATURE_INVALID' });
    });
    await t.test('populated rollback refused, ledger remains untouched', async () => {
      await assert.rejects(migration.query(ddl('migrations/009_apple_subscription_verification.down.sql')), /rollback refused/);
      await migration.query('ROLLBACK');
      assert.equal((await db.query('SELECT count(*) FROM sync_changes')).rows[0].count, '0');
    });
  });
}
