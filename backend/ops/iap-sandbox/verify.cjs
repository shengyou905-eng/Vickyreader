const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { Client } = require('pg');
const checks = [];
function ok(name) { checks.push(name); console.log('PASS ' + name); }
const subscriptionTables = ['subscription_accounts', 'subscription_ownership', 'subscriptions', 'entitlement_grants', 'subscription_events'];
async function main() {
  const target = new URL(process.env.DATABASE_URL);
  assert.equal(target.hostname, 'sandbox-db');
  assert.equal(target.pathname, '/zhidu_iap_sandbox');
  assert.equal(target.username, 'zhidu_sandbox_app');
  assert.equal(process.env.APPLE_IAP_ENABLED, 'false');
  assert.equal(process.env.APPLE_IAP_ENVIRONMENT, 'Sandbox');
  for (const name of ['APPLE_IAP_PRIVATE_KEY', 'APPLE_PRIVATE_KEY', 'DEEPSEEK_API_KEY']) assert.ok(!process.env[name]);
  ok('Sandbox database/environment; IAP disabled; no Apple private keys or LLM key');
  const c = new Client({ connectionString: process.env.DATABASE_URL, connectionTimeoutMillis: 5000 });
  await c.connect();
  try {
    await c.query('BEGIN READ ONLY');
    const identity = (await c.query("SELECT current_database() AS db, current_user AS role, current_setting('server_version') AS version, current_setting('transaction_read_only') AS read_only")).rows[0];
    assert.equal(identity.db, 'zhidu_iap_sandbox');
    assert.equal(identity.read_only, 'on');
    console.log(JSON.stringify({ database: identity }));
    const role = (await c.query('SELECT rolsuper,rolcreatedb,rolcreaterole,rolreplication FROM pg_roles WHERE rolname=current_user')).rows[0];
    assert.ok(Object.values(role).every(value => value === false));
    const privileges = (await c.query("SELECT has_schema_privilege(current_user,'public','CREATE') AS create_schema, has_database_privilege(current_user,current_database(),'CREATE') AS create_db_objects")).rows[0];
    assert.equal(privileges.create_schema, false);
    assert.equal(privileges.create_db_objects, false);
    ok('Database connectivity and non-owner least-privilege runtime role');
    const authTables = (await c.query("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('auth_rate_limits','apple_auth_challenges','apple_identities')")).rows;
    assert.equal(authTables.length, 3);
    const passwordColumn = (await c.query("SELECT is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='password_hash'")).rows[0];
    assert.equal(passwordColumn.is_nullable, 'YES');
    ok('Separate migration 001 authentication prerequisite present');
    const expected = {
      subscription_accounts: ['id','user_id','environment','app_account_token','created_at'],
      subscription_ownership: ['id','provider','environment','original_transaction_id','account_id','retired_at'],
      subscriptions: ['id','ownership_id','account_id','environment','product_id','latest_transaction_id','status','purchased_at','expires_at','grace_period_expires_at','revoked_at','auto_renew_status','signed_at','snapshot_hash','last_verified_at','created_at','updated_at','transaction_signed_at','renewal_signed_at'],
      entitlement_grants: ['id','account_id','environment','entitlement','source','subscription_id','enabled','valid_from','valid_until','revoked_at','verified_at'],
      subscription_events: ['id','environment','event_kind','request_hash','notification_uuid','notification_type','subtype','ownership_id','account_id','result','received_at','processed_at','original_transaction_id','signed_at','transaction_id','transaction_purchased_at','transaction_signed_at','renewal_signed_at','attempts','last_error_code'],
    };
    for (const table of subscriptionTables) {
      const fields = (await c.query("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1 ORDER BY ordinal_position", [table])).rows.map(x => x.column_name);
      assert.deepEqual(fields, expected[table]);
    }
    ok('008 five tables and 009 exact final column lists');
    const constraints = (await c.query("SELECT conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid IN (SELECT oid FROM pg_class WHERE relnamespace='public'::regnamespace AND relname=ANY($1::text[]))", [subscriptionTables])).rows;
    const definitions = constraints.map(x => x.definition).join('\n');
    for (const snippet of ['UNIQUE (provider, environment, original_transaction_id)', 'UNIQUE (environment, latest_transaction_id)', 'UNIQUE (environment, notification_uuid)', 'UNIQUE (user_id, environment)', 'FOREIGN KEY (ownership_id, account_id, environment)', 'FOREIGN KEY (subscription_id, account_id, environment)', "'Sandbox'", "'Production'", 'reconciliation', 'retry_pending']) assert.ok(definitions.includes(snippet), snippet);
    assert.ok(constraints.find(x => x.conname === 'subscription_component_versions'));
    const indexes = (await c.query("SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='public' AND tablename=ANY($1::text[])", [subscriptionTables])).rows;
    for (const name of ['idx_subscription_ownership_account','idx_subscriptions_reconcile','idx_subscriptions_account','idx_entitlement_grants_effective','idx_subscription_events_owner','idx_subscription_events_account','idx_subscription_events_pending','idx_subscription_events_chain']) assert.ok(indexes.find(x => x.indexname === name), name);
    const chain = indexes.find(x => x.indexname === 'idx_subscription_events_chain').indexdef;
    assert.ok(chain.includes('(environment, original_transaction_id)'));
    assert.ok(chain.includes('processed_at IS NULL'));
    ok('Environment composite uniqueness/FKs, version fences, audit constraints and indexes');
    const triggers = (await c.query("SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN ('subscription_accounts'::regclass,'subscription_ownership'::regclass)")).rows.map(x => x.tgname).sort();
    assert.deepEqual(triggers, ['subscription_account_erasure','subscription_account_immutable','subscription_ownership_immutable']);
    const erase = (await c.query("SELECT pg_get_functiondef('erase_subscription_account()'::regprocedure) AS sql")).rows[0].sql;
    assert.ok(erase.includes('pg_advisory_xact_lock'));
    assert.ok(erase.includes('(environment, original_transaction_id) IN'));
    ok('009 account erasure function and all ownership/identity triggers');
    for (const table of [...subscriptionTables, 'users', 'user_entries', 'sync_changes']) {
      assert.equal((await c.query(`SELECT count(*)::int AS n FROM ${table}`)).rows[0].n, 0);
    }
    ok('Empty test data; no production users/traces/ledger/subscriptions imported');
    await c.query('ROLLBACK');
    const origin = 'http://127.0.0.1:3000';
    async function request(path, options = {}) {
      const response = await fetch(origin + path, { ...options, signal: AbortSignal.timeout(10000) });
      return { status: response.status, body: await response.json() };
    }
    const health = await request('/api/health');
    assert.equal(health.status, 200); assert.equal(health.body.status, 'ok');
    for (const path of ['/api/entries', '/api/me/entitlements']) assert.equal((await request(path)).status, 401);
    const unauthVerify = await request('/api/subscriptions/apple/verify', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    assert.equal(unauthVerify.status, 401);
    ok('HTTP health and JWT authentication on existing/new APIs');
    const malformed = await request('/api/apple/notifications', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    assert.equal(malformed.status, 400);
    ok('Apple notification route mounted and rejects malformed payload');
    // A synthetic account exercises real login middleware; it is removed after the smoke check.
    const credentials = { email: 'iap-smoke-' + crypto.randomUUID() + '@example.invalid', password: crypto.randomBytes(24).toString('hex') };
    const headers = { 'Content-Type': 'application/json' };
    const registration = await request('/api/auth/register', { method: 'POST', headers, body: JSON.stringify(credentials) });
    assert.equal(registration.status, 201);
    const token = registration.body.token;
    assert.ok(token);
    try {
      const login = await request('/api/auth/login', { method: 'POST', headers, body: JSON.stringify(credentials) });
      assert.equal(login.status, 200);
      const authorized = { ...headers, Authorization: 'Bearer ' + token };
      assert.equal((await request('/api/entries', { headers: authorized })).status, 200);
      for (const [path, options] of [
        ['/api/me/entitlements', {}],
        ['/api/subscriptions/apple/purchase-context', { method: 'POST', body: '{}' }],
        ['/api/subscriptions/apple/verify', { method: 'POST', body: JSON.stringify({ transactionId: '1000000000000001' }) }],
      ]) {
        const result = await request(path, { ...options, headers: authorized });
        assert.equal(result.status, 503);
        assert.equal(result.body.error, 'APPLE_IAP_DISABLED');
      }
      ok('Registration/login/read API works; authenticated IAP stays disabled without Apple calls');
    } finally {
      const removal = await request('/api/auth/account', { method: 'DELETE', headers: { ...headers, Authorization: 'Bearer ' + token }, body: JSON.stringify({ password: credentials.password }) });
      assert.equal(removal.status, 200);
    }
    for (const table of [...subscriptionTables, 'users', 'user_entries', 'sync_changes']) assert.equal((await c.query(`SELECT count(*)::int AS n FROM ${table}`)).rows[0].n, 0);
    ok('Smoke account removed; no entitlement or subscription created');
    console.log(JSON.stringify({ passed: checks.length, subscriptionTablesEmpty: true, appleIapEnabled: false }));
  } finally { await c.end(); }
}
main().catch(error => {
  console.error(JSON.stringify({ verificationFailed: true, code: error.code || error.name, passedChecks: checks.length }));
  process.exitCode = 1;
});
