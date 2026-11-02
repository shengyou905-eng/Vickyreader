// Deliberately restricted to the disposable local Obsidian test database.
// No schema initialization, migrations, production config writes, or seed data.
const crypto = require('node:crypto');

async function main() {
  const url = new URL(process.env.OBSIDIAN_TEST_DATABASE_URL || '');
  if (!['postgres:', 'postgresql:'].includes(url.protocol)
      || !['127.0.0.1', 'localhost'].includes(url.hostname)
      || url.pathname !== '/zhidu_obsidian_phase1_test') {
    throw new Error('Use only the local zhidu_obsidian_phase1_test database');
  }
  const port = Number(process.env.OBSIDIAN_TEST_PORT || 3002);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid test port');
  const origin = `http://127.0.0.1:${port}`;
  Object.assign(process.env, {
    NODE_ENV: 'test', DATABASE_URL: url.toString(), HOST: '127.0.0.1', PORT: String(port),
    JWT_SECRET: crypto.randomBytes(32).toString('hex'),
    AUTH_RATE_LIMIT_SECRET: crypto.randomBytes(32).toString('hex'),
    MCP_TOKEN_HASH_SECRET: '', OBSIDIAN_SYNC_ENABLED: 'true',
    OBSIDIAN_SYNC_CURSOR_SECRET: crypto.randomBytes(32).toString('hex'),
    OBSIDIAN_SYNC_REDIRECT_URIS: 'obsidian://zhidu-sync,http://127.0.0.1:9876/callback',
    CORS_ORIGIN: origin, PUBLIC_BASE_URL: origin,
  });
  const { pool, query } = require('../src/config/db');
  let server;
  try {
    const db = (await query(`SELECT current_database() AS name,
      to_regclass('obsidian_grants') AS grants, to_regclass('sync_user_cursors') AS cursors`)).rows[0];
    if (db.name !== 'zhidu_obsidian_phase1_test' || !db.grants || !db.cursors) {
      throw new Error('Prepare the isolated test database with migrations 001-007 first');
    }
    const express = require('express');
    const app = express();
    app.use((_req, res, next) => { res.set('X-Zhidu-Environment', 'obsidian-local-test'); next(); });
    app.get('/api/health', (_req, res) => res.json({ status: 'ok', production: false,
      environment: 'obsidian-local-test', database: db.name }));
    app.use(require('../src/app'));
    await new Promise((resolve, reject) => {
      server = app.listen(port, '127.0.0.1', resolve);
      server.once('error', reject);
    });
    console.log(`Obsidian local test server: ${origin}`);
    console.log('Database: zhidu_obsidian_phase1_test; temporary signing keys; no migrations run.');
    const shutdown = () => server.close(() => pool.end().then(() => process.exit(0)));
    process.once('SIGINT', shutdown);
    process.once('SIGTERM', shutdown);
  } catch (error) {
    if (server) server.close();
    await pool.end();
    throw error;
  }
}
main().catch(() => { console.error('Local test server could not start. Check the dedicated database and port.'); process.exitCode = 1; });
