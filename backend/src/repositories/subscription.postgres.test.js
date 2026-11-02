const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { Client } = require('pg');

const target = process.env.SUBSCRIPTION_TEST_DATABASE_URL;
if (!target) {
  test('subscription real PostgreSQL tests', { skip: 'SUBSCRIPTION_TEST_DATABASE_URL not set' }, () => {});
} else {
  const url = new URL(target);
  if (!['127.0.0.1', 'localhost'].includes(url.hostname)
      || url.pathname !== '/zhidu_subscription_phase1_test') {
    throw new Error('Use a disposable localhost zhidu_subscription_phase1_test database');
  }
  // Only our random schema is created/removed. Never reset public or a user database.
  const schema = 'subtest_' + randomUUID().replaceAll('-', '');
  url.searchParams.set('options', '-c search_path=' + schema + ',public');
  process.env.DATABASE_URL = url.toString();
  process.env.JWT_SECRET = 'subscription-isolated-test-not-a-real-secret';
  const db = require('../config/db');
  const repository = require('./subscription.repository');
  const { getEntitlements } = require('../services/entitlement.service');
  const { PRODUCTS } = require('../config/subscriptions');
  const directory = path.join(__dirname, '../db');
  const up = fs.readFileSync(path.join(directory, 'migrations/008_app_store_subscriptions.up.sql'), 'utf8');
  const down = fs.readFileSync(path.join(directory, 'migrations/008_app_store_subscriptions.down.sql'), 'utf8');
  const fullSchema = fs.readFileSync(path.join(directory, 'schema.sql'), 'utf8');
  let chain = 100000;

  async function newUser() {
    const id = randomUUID();
    await db.query('INSERT INTO users (id,email,password_hash) VALUES ($1,$2,$3)', [id, id + '@example.invalid', 'test-hash']);
    return id;
  }
  async function fixture(userId, environment = 'Sandbox', changes = {}) {
    const account = await repository.getOrCreateAccount(userId, environment);
    const id = String(++chain);
    return {
      environment, appAccountToken: account.app_account_token,
      originalTransactionId: id, transactionId: id, productId: Object.keys(PRODUCTS)[0],
      status: 'active', purchasedAt: '2020-01-01T00:00:00Z', expiresAt: '2090-01-01T00:00:00Z',
      gracePeriodExpiresAt: null, revokedAt: null, autoRenew: true,
      signedAt: '2026-01-01T00:00:00Z', ...changes,
    };
  }
  async function counts() {
    const result = {};
    for (const table of ['subscription_accounts', 'subscription_ownership', 'subscriptions', 'entitlement_grants', 'subscription_events']) {
      result[table] = Number((await db.query('SELECT count(*) FROM ' + table)).rows[0].count);
    }
    return result;
  }
  const apply = repository.applyVerifiedSnapshot;
  const notice = (id = randomUUID()) => ({ uuid: id, type: 'DID_RENEW', subtype: null });

  test('subscription model on real PostgreSQL', async (t) => {
    const admin = new Client({ connectionString: target });
    await admin.connect();
    await admin.query('CREATE SCHEMA ' + schema);
    t.after(async () => {
      await db.closePool();
      await admin.query('DROP SCHEMA ' + schema + ' CASCADE');
      await admin.end();
    });
    const migrationClient = new Client({ connectionString: url.toString() });
    await migrationClient.connect();
    t.after(() => migrationClient.end());
    await migrationClient.query(fullSchema.split('-- BEGIN SUBSCRIPTION SCHEMA 008')[0]);
    for (const name of fs.readdirSync(path.join(directory, 'migrations')).filter((s) => /^00[1-7].*\.up\.sql$/.test(s)).sort()) {
      await migrationClient.query(fs.readFileSync(path.join(directory, 'migrations', name), 'utf8'));
    }
    const historicalUser = await newUser();
    const historicalTrace = (await db.query(
      "INSERT INTO user_entries (user_id,source,book_id,user_input) VALUES ($1,'thought','existing-book','preserve') RETURNING id",
      [historicalUser],
    )).rows[0].id;

    await t.test('upgrade after 001-007 preserves existing users/traces; repeatable; unused rollback and reapply', async () => {
      await migrationClient.query(up);
      await migrationClient.query(up);
      assert.equal((await db.query('SELECT user_input FROM user_entries WHERE id=$1', [historicalTrace])).rows[0].user_input, 'preserve');
      assert.deepEqual(await counts(), { subscription_accounts: 0, subscription_ownership: 0, subscriptions: 0, entitlement_grants: 0, subscription_events: 0 });
      await migrationClient.query(down);
      await migrationClient.query(up);
      await migrationClient.query(fullSchema);
    });

    await t.test('concurrent account requests return a stable token per user/environment', async () => {
      const user = await newUser();
      const accounts = await Promise.all(Array.from({ length: 8 }, () => repository.getOrCreateAccount(user, 'Sandbox')));
      assert.equal(new Set(accounts.map((a) => a.app_account_token)).size, 1);
      const production = await repository.getOrCreateAccount(user, 'Production');
      assert.notEqual(production.app_account_token, accounts[0].app_account_token);
      await assert.rejects(db.query('UPDATE subscription_accounts SET app_account_token=$1 WHERE id=$2', [randomUUID(), production.id]), { code: '23514' });
    });

    await t.test('first purchase, idempotent replay and concurrent notification duplicates', async () => {
      const user = await newUser();
      const state = await fixture(user);
      const n = notice();
      const results = await Promise.all(Array.from({ length: 6 }, () => apply(user, state, n)));
      assert.equal(results.filter((r) => r.result === 'applied').length, 1);
      assert.equal(results.filter((r) => r.result === 'duplicate').length, 5);
      assert.equal((await apply(user, state)).result, 'replay');
      assert.equal((await getEntitlements(user, 'Sandbox')).tier, 'PRO');
      assert.equal((await getEntitlements(user, 'Production')).tier, 'FREE');
      assert.equal((await apply(user, { ...state, autoRenew: false }, n)).result, 'event_conflict');
      assert.equal((await db.query('SELECT count(*) FROM subscription_events WHERE notification_uuid=$1', [n.uuid])).rows[0].count, '1');
    });

    await t.test('cancel, renewal, stale snapshots and equal-version conflicts', async () => {
      const user = await newUser();
      const state = await fixture(user);
      await apply(user, state);
      const canceled = { ...state, autoRenew: false, signedAt: '2026-01-02T00:00:00Z' };
      await apply(user, canceled);
      assert.equal((await getEntitlements(user, 'Sandbox')).pro.active, true);
      assert.equal((await getEntitlements(user, 'Sandbox')).pro.autoRenew, false);
      assert.equal((await apply(user, state)).result, 'stale');
      assert.equal((await apply(user, { ...canceled, autoRenew: true })).result, 'version_conflict');
      const renewed = { ...state, transactionId: String(++chain), expiresAt: '2091-01-01T00:00:00Z', signedAt: '2026-01-03T00:00:00Z' };
      assert.equal((await apply(user, renewed)).result, 'applied');
      assert.equal((await getEntitlements(user, 'Sandbox')).pro.expiresAt, '2091-01-01T00:00:00.000Z');
      assert.equal((await apply(user, { ...state, status: 'expired' })).result, 'stale');
      assert.equal((await getEntitlements(user, 'Sandbox')).tier, 'PRO');
    });

    await t.test('expiry uses DB time without a webhook; grace, retry, refund and revoke boundaries', async () => {
      const user = await newUser();
      const state = await fixture(user, 'Sandbox', { expiresAt: '2021-01-01T00:00:00Z' });
      await apply(user, state);
      assert.equal((await getEntitlements(user, 'Sandbox')).tier, 'FREE');
      await apply(user, { ...state, status: 'grace_period', gracePeriodExpiresAt: '2091-01-01T00:00:00Z', signedAt: '2026-01-02T00:00:00Z' });
      assert.equal((await getEntitlements(user, 'Sandbox')).tier, 'PRO');
      await apply(user, { ...state, status: 'billing_retry', signedAt: '2026-01-03T00:00:00Z' });
      assert.equal((await getEntitlements(user, 'Sandbox')).tier, 'FREE');
      await apply(user, { ...state, expiresAt: '2091-01-01T00:00:00Z', signedAt: '2026-01-04T00:00:00Z' });
      await apply(user, { ...state, status: 'revoked', revokedAt: '2026-01-05T00:00:00Z', signedAt: '2026-01-05T00:00:00Z' });
      assert.equal((await getEntitlements(user, 'Sandbox')).tier, 'FREE');
      await apply(user, { ...state, status: 'expired', signedAt: '2026-01-06T00:00:00Z' });
      assert.equal((await getEntitlements(user, 'Sandbox')).tier, 'FREE');
    });

    await t.test('wrong account token and concurrent cross-user chain claims never grant both users', async () => {
      const a = await newUser();
      const b = await newUser();
      const stateA = await fixture(a);
      const stateB = await fixture(b, 'Sandbox', { originalTransactionId: stateA.originalTransactionId });
      assert.equal((await apply(b, stateA)).result, 'account_token_mismatch');
      const results = await Promise.all([apply(a, stateA), apply(b, stateB)]);
      assert.deepEqual(results.map((r) => r.result).sort(), ['applied', 'ownership_conflict']);
      const tiers = await Promise.all([getEntitlements(a, 'Sandbox'), getEntitlements(b, 'Sandbox')]);
      assert.equal(tiers.filter((s) => s.tier === 'PRO').length, 1);
      const row = (await db.query('SELECT * FROM subscription_ownership WHERE original_transaction_id=$1', [stateA.originalTransactionId])).rows[0];
      const other = (await repository.getOrCreateAccount(row.account_id === (await repository.getOrCreateAccount(a, 'Sandbox')).id ? b : a, 'Sandbox')).id;
      await assert.rejects(db.query('UPDATE subscription_ownership SET account_id=$1 WHERE id=$2', [other, row.id]), { code: '23514' });
    });

    await t.test('DB composite FKs prevent cross-environment grants; same IDs/UUID are independent across Apple environments', async () => {
      const user = await newUser();
      const sandbox = await fixture(user);
      const production = await fixture(user, 'Production', { originalTransactionId: sandbox.originalTransactionId, transactionId: sandbox.transactionId });
      const n = notice();
      await apply(user, sandbox, n);
      await apply(user, production, n);
      assert.equal((await getEntitlements(user, 'Production')).tier, 'PRO');
      const account = await repository.getOrCreateAccount(user, 'Sandbox');
      await assert.rejects(db.query("UPDATE entitlement_grants SET environment='Production' WHERE account_id=$1", [account.id]), { code: '23503' });
      await apply(user, { ...sandbox, status: 'expired', signedAt: '2026-02-01T00:00:00Z' });
      assert.equal((await getEntitlements(user, 'Sandbox')).tier, 'FREE');
      assert.equal((await getEntitlements(user, 'Production')).tier, 'PRO');
      await assert.rejects(db.query("UPDATE subscription_events SET environment='TestFlight'"), { code: '23514' });
    });

    await t.test('failure after subscription insert rolls back ownership, state, entitlement and audit together', async () => {
      const user = await newUser();
      const state = await fixture(user);
      const before = await counts();
      await db.query(`CREATE FUNCTION reject_grant_test() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN RAISE EXCEPTION 'fixture grant failure'; END; $$;
        CREATE TRIGGER reject_grant_test BEFORE INSERT ON entitlement_grants FOR EACH ROW EXECUTE FUNCTION reject_grant_test()`);
      try {
        await assert.rejects(apply(user, state), /fixture grant failure/);
        assert.deepEqual(await counts(), before);
      } finally {
        await db.query('DROP TRIGGER reject_grant_test ON entitlement_grants; DROP FUNCTION reject_grant_test()');
      }
      assert.equal((await apply(user, state)).result, 'applied');
    });

    await t.test('cross-user grant tampering fails at the FK; entitlement read errors are not FREE', async () => {
      const user = await newUser();
      const other = await newUser();
      const state = await fixture(user);
      const otherAccount = await repository.getOrCreateAccount(other, 'Sandbox');
      await apply(user, state);
      const account = await repository.getOrCreateAccount(user, 'Sandbox');
      await assert.rejects(db.query(
        'UPDATE entitlement_grants SET account_id=$1 WHERE account_id=$2',
        [otherAccount.id, account.id],
      ), { code: '23503' });
      assert.equal((await getEntitlements(other, 'Sandbox')).tier, 'FREE');
      await db.query('ALTER TABLE entitlement_grants RENAME TO grants_failure_fixture');
      try {
        await assert.rejects(getEntitlements(user, 'Sandbox'), { code: '42P01' });
      } finally {
        await db.query('ALTER TABLE grants_failure_fixture RENAME TO entitlement_grants');
      }
      assert.equal((await getEntitlements(user, 'Sandbox')).tier, 'PRO');
    });

    await t.test('multiple chains combine grants without an expired chain revoking a valid one', async () => {
      const user = await newUser();
      const a = await fixture(user);
      const b = await fixture(user, 'Sandbox', {
        productId: Object.keys(PRODUCTS)[1], expiresAt: '2092-01-01T00:00:00Z',
      });
      await apply(user, a);
      await apply(user, b);
      await apply(user, { ...a, status: 'expired', signedAt: '2026-02-01T00:00:00Z' });
      const entitlement = await getEntitlements(user, 'Sandbox');
      assert.equal(entitlement.tier, 'PRO');
      assert.equal(entitlement.pro.productId, b.productId);
      assert.equal(entitlement.pro.expiresAt, '2092-01-01T00:00:00.000Z');
    });

    await t.test('account deletion erases personal mapping/details/grants/audits but permanently reserves the chain', async () => {
      const user = await newUser();
      const state = await fixture(user);
      await apply(user, state, notice());
      const account = await repository.getOrCreateAccount(user, 'Sandbox');
      const production = await fixture(user, 'Production', {
        originalTransactionId: state.originalTransactionId, transactionId: state.transactionId,
      });
      await apply(user, production, notice());
      // Use the exact existing DELETE path, no subscription-specific app hook.
      const users = require('./user.repository');
      await users.deleteUser(user);
      for (const table of ['subscriptions', 'entitlement_grants', 'subscription_events']) {
        assert.equal((await db.query('SELECT count(*) FROM ' + table + ' WHERE account_id=$1', [account.id])).rows[0].count, '0');
      }
      assert.equal((await db.query('SELECT count(*) FROM subscription_accounts WHERE app_account_token=$1', [state.appAccountToken])).rows[0].count, '0');
      assert.equal((await db.query('SELECT count(*) FROM subscription_accounts WHERE user_id=$1', [user])).rows[0].count, '0');
      const retired = (await db.query('SELECT * FROM subscription_ownership WHERE original_transaction_id=$1', [state.originalTransactionId])).rows;
      assert.equal(retired.length, 2);
      assert.ok(retired.every((row) => row.account_id === null && row.retired_at));
      const tombstone = retired.find((row) => row.environment === 'Sandbox');
      assert.equal(tombstone.account_id, null);
      assert.ok(tombstone.retired_at);
      assert.equal('user_id' in tombstone, false);
      assert.equal('app_account_token' in tombstone, false);
      assert.equal((await apply(user, state)).result, 'account_deleted');
      const replacement = await newUser();
      const replacementState = await fixture(replacement, 'Sandbox', { originalTransactionId: state.originalTransactionId });
      assert.equal((await apply(replacement, state)).result, 'account_token_mismatch');
      assert.equal((await apply(replacement, replacementState)).result, 'account_deleted');
      assert.equal((await getEntitlements(replacement, 'Sandbox')).tier, 'FREE');
      await assert.rejects(db.query('DELETE FROM subscription_ownership WHERE id=$1', [tombstone.id]), { code: '23514' });
      await assert.rejects(db.query('UPDATE subscription_ownership SET account_id=$1, retired_at=NULL WHERE id=$2', [(await repository.getOrCreateAccount(replacement, 'Sandbox')).id, tombstone.id]), { code: '23514' });
    });

    await t.test('account deletion rollback restores subscription and entitlement with the account', async () => {
      const user = await newUser();
      const state = await fixture(user);
      await apply(user, state);
      await assert.rejects(db.withTransaction(async (tx) => {
        await tx('DELETE FROM users WHERE id=$1', [user]);
        throw new Error('abort deletion fixture');
      }), /abort deletion fixture/);
      assert.equal((await getEntitlements(user, 'Sandbox')).tier, 'PRO');
      assert.equal((await apply(user, state)).result, 'replay');
    });

    await t.test('delete racing with a waiting verification cannot recreate a deleted account', async () => {
      const user = await newUser();
      const state = await fixture(user);
      const client = new Client({ connectionString: url.toString() });
      await client.connect();
      try {
        await client.query('BEGIN');
        await client.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [user]);
        const waiting = apply(user, state);
        await client.query('DELETE FROM users WHERE id=$1', [user]);
        await client.query('COMMIT');
        assert.equal((await waiting).result, 'account_deleted');
        assert.equal((await repository.getOrCreateAccount(user, 'Sandbox')), null);
      } finally { await client.end(); }
    });

    await t.test('no reading ledger mutations; populated rollback refuses to erase ownership', async () => {
      assert.equal((await db.query('SELECT user_input FROM user_entries WHERE id=$1', [historicalTrace])).rows[0].user_input, 'preserve');
      assert.equal((await db.query('SELECT count(*) FROM sync_changes')).rows[0].count, '0');
      const before = await counts();
      await assert.rejects(migrationClient.query(down), /rollback refused/);
      await migrationClient.query('ROLLBACK');
      assert.deepEqual(await counts(), before);
      await migrationClient.query(up);
      assert.deepEqual(await counts(), before);
    });
  });
}
