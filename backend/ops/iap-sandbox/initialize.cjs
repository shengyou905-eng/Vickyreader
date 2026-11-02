const fs = require('node:fs');
const { Client } = require('pg');
async function main() {
  if (process.env.POSTGRES_DB !== 'zhidu_iap_sandbox' || process.env.POSTGRES_USER !== 'zhidu_sandbox_admin') {
    throw new Error('Sandbox identity required');
  }
  const c = new Client({ host: 'sandbox-db', port: 5432, database: process.env.POSTGRES_DB,
    user: process.env.POSTGRES_USER, password: process.env.POSTGRES_PASSWORD, connectionTimeoutMillis: 10000 });
  try {
    await c.connect();
    await c.query('BEGIN');
    await c.query("SET LOCAL lock_timeout='5s'");
    await c.query("SET LOCAL statement_timeout='60s'");
    const identity = await c.query('SELECT current_database() AS name');
    if (identity.rows[0].name !== 'zhidu_iap_sandbox') throw new Error('Database identity mismatch');
    const tables = await c.query("SELECT count(*)::int AS n FROM information_schema.tables WHERE table_schema='public'");
    if (tables.rows[0].n !== 0) throw new Error('Initialization requires a completely empty database');
    const { appPassword } = JSON.parse(fs.readFileSync('/config/roles.json', 'utf8'));
    if (!/^[a-f0-9]{64}$/.test(appPassword)) throw new Error('Invalid generated credential');
    await c.query('CREATE ROLE zhidu_sandbox_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE');
    await c.query("CREATE ROLE zhidu_sandbox_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD '" + appPassword + "'");
    await c.query('REVOKE CONNECT ON DATABASE zhidu_iap_sandbox FROM PUBLIC');
    await c.query('GRANT CONNECT ON DATABASE zhidu_iap_sandbox TO zhidu_sandbox_app');
    await c.query('REVOKE CREATE ON SCHEMA public FROM PUBLIC');
    await c.query('GRANT USAGE, CREATE ON SCHEMA public TO zhidu_sandbox_owner');
    await c.query('CREATE EXTENSION IF NOT EXISTS pgcrypto');
    await c.query('SET LOCAL ROLE zhidu_sandbox_owner');
    // Fresh schema embeds 002-009, but not the separate Apple-auth migration 001.
    await c.query(fs.readFileSync('src/db/schema.sql', 'utf8'));
    await c.query(fs.readFileSync('src/db/migrations/001_apple_auth.up.sql', 'utf8'));
    await c.query('GRANT USAGE ON SCHEMA public TO zhidu_sandbox_app');
    await c.query('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO zhidu_sandbox_app');
    await c.query('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO zhidu_sandbox_app');
    await c.query('ALTER DEFAULT PRIVILEGES FOR ROLE zhidu_sandbox_owner IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO zhidu_sandbox_app');
    await c.query('ALTER DEFAULT PRIVILEGES FOR ROLE zhidu_sandbox_owner IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO zhidu_sandbox_app');
    await c.query('COMMIT');
    console.log('Fresh Sandbox schema plus missing auth migration 001 initialized atomically; embedded 002-009 not replayed; runtime role is not schema owner.');
  } catch (error) {
    await c.query('ROLLBACK').catch(() => {});
    console.error(JSON.stringify({ initializationFailed: true, code: error.code || error.name }));
    process.exitCode = 1;
  } finally { await c.end(); }
}
main().catch(() => { console.error('Sandbox initialization failed'); process.exitCode = 1; });
