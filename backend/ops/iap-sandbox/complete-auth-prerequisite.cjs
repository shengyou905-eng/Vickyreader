const fs = require('node:fs');
const assert = require('node:assert/strict');
const { Client } = require('pg');
async function main() {
  assert.equal(process.env.POSTGRES_DB, 'zhidu_iap_sandbox');
  assert.equal(process.env.POSTGRES_USER, 'zhidu_sandbox_admin');
  const c = new Client({ host: 'sandbox-db', database: process.env.POSTGRES_DB,
    user: process.env.POSTGRES_USER, password: process.env.POSTGRES_PASSWORD, connectionTimeoutMillis: 5000 });
  try {
    await c.connect();
    await c.query('BEGIN');
    await c.query("SET LOCAL lock_timeout='5s'");
    await c.query("SET LOCAL statement_timeout='30s'");
    assert.equal((await c.query('SELECT current_database() AS db')).rows[0].db, 'zhidu_iap_sandbox');
    assert.equal((await c.query('SELECT count(*)::int AS n FROM users')).rows[0].n, 0);
    const tables = await c.query("SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename IN ('auth_rate_limits','apple_auth_challenges','apple_identities')");
    assert.equal(tables.rowCount, 0, 'Only a wholly unapplied 001 can be completed');
    await c.query('SET LOCAL ROLE zhidu_sandbox_owner');
    await c.query(fs.readFileSync('src/db/migrations/001_apple_auth.up.sql', 'utf8'));
    await c.query('COMMIT');
    console.log('Applied missing migration 001 to empty Sandbox only; no embedded migration replayed.');
  } catch (error) {
    await c.query('ROLLBACK').catch(() => {});
    console.error(JSON.stringify({ failed: true, code: error.code || error.name }));
    process.exitCode = 1;
  } finally { await c.end(); }
}
main().catch(() => { console.error('Sandbox prerequisite completion failed'); process.exitCode = 1; });
