const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const url = process.env.TEST_DATABASE_URL;
if (!url) {
  test('Obsidian PostgreSQL integration', { skip: 'TEST_DATABASE_URL not set' }, () => {});
} else {
  const target = new URL(url);
  if (!['localhost', '127.0.0.1'].includes(target.hostname)
      || target.pathname !== '/zhidu_obsidian_phase1_test') {
    throw new Error('Fixtures may reset only local zhidu_obsidian_phase1_test');
  }
  process.env.DATABASE_URL = url;
  process.env.JWT_SECRET = 'synthetic-obsidian-test-session-secret';
  const { query, closePool, pool } = require('../config/db');
  const accounts = require('./obsidianAuth.repository');
  const exports = require('./obsidianSync.repository');
  const entries = require('./entry.repository');
  const library = require('./mcp.repository');
  const progress = require('./readingProgress.repository');
  const deletion = require('./bookDeletion.repository');
  const p = require('../services/obsidianProtocol.service');
  const secret = 'synthetic-obsidian-cursor-secret-at-least-32';
  const version = n => ({ client_revision: n, writer_id: '11111111-1111-4111-8111-111111111111' });
  const authInput = verifier => ({ client_id: p.CLIENT_ID, redirect_uri: 'obsidian://zhidu-sync', code_challenge: p.challenge(verifier) });
  async function user() {
    const id = crypto.randomUUID();
    await query("INSERT INTO users (id,email,password_hash) VALUES ($1,$2,'synthetic-unused')", [id, `${id}@example.invalid`]);
    return id;
  }
  async function issued(id) {
    const verifier = crypto.randomBytes(32).toString('base64url');
    const code = p.randomCredential('zd_oc_');
    await accounts.createCode(id, 0, code, authInput(verifier));
    const token = p.randomCredential('zd_os_');
    await accounts.exchangeCode({ ...authInput(verifier), code, code_verifier: verifier }, token);
    return { token, grant: await accounts.authenticate(token) };
  }
  async function trace(id, localId, book, rev = 1, note = 'synthetic-note') {
    return entries.upsertEntryByClientId(id, localId, { source: 'thought', book_id: book,
      book_title: 'Synthetic title', user_input: note, original_text: 'synthetic excerpt', auto_tags: ['tag'],
      metadata_json: { file_path: '/private/not-exportable', secret: 'not-exportable' } }, version(rev));
  }
  async function all(grant, cursor, limit = 50) {
    const changes = [];
    let page;
    do {
      page = await exports.sync(grant, { cursor, limit }, secret);
      changes.push(...page.changes);
      cursor = page.next_cursor;
    } while (page.has_more);
    return { ...page, changes };
  }

  test('Obsidian real PostgreSQL migration, auth and snapshot/incremental isolation', async t => {
    t.after(closePool);
    await query('DROP SCHEMA public CASCADE; CREATE SCHEMA public');
    const schema = fs.readFileSync(path.join(__dirname, '../db/schema.sql'), 'utf8');
    await query(schema.split('-- Obsidian read-only integration (migration 007).')[0]);
    const migrations = path.join(__dirname, '../db/migrations');
    for (const file of fs.readdirSync(migrations).filter(f => /^00[1-6].*\.up\.sql$/.test(f)).sort()) {
      await query(fs.readFileSync(path.join(migrations, file), 'utf8'));
    }
    const historicalUser = await user();
    const historical = (await query(`INSERT INTO user_entries (user_id,source,book_id,book_title,user_input)
      VALUES ($1,'highlight','historical-book','Historical title','synthetic historical') RETURNING id`, [historicalUser])).rows[0];
    const migration = fs.readFileSync(path.join(migrations, '007_obsidian_sync.up.sql'), 'utf8');
    await query(migration);
    await query(migration);

    await t.test('migration is repeatable and preserves historical rows without synthetic ledger', async () => {
      assert.equal((await query('SELECT id FROM user_entries WHERE id=$1', [historical.id])).rowCount, 1);
      assert.equal((await query('SELECT * FROM sync_changes WHERE user_id=$1', [historicalUser])).rowCount, 0);
      const { grant } = await issued(historicalUser);
      const snapshot = await all(grant);
      assert.equal(snapshot.watermark, '0');
      assert.ok(snapshot.changes.some(c => c.entity_id === historical.id));
      assert.equal(snapshot.changes.find(c => c.entity_type === 'book').data.author, null);
    });
    await t.test('wrong PKCE, redirect and expired/consumed code cannot issue a token', async () => {
      const id = await user();
      const verifier = 'v'.repeat(43);
      const code = p.randomCredential('zd_oc_');
      await accounts.createCode(id, 0, code, authInput(verifier));
      const input = { ...authInput(verifier), code, code_verifier: verifier };
      for (const patch of [{ code_verifier: 'x'.repeat(43) }, { redirect_uri: 'https://attacker.invalid' }]) {
        await assert.rejects(accounts.exchangeCode({ ...input, ...patch }, p.randomCredential('zd_os_')), { statusCode: 400 });
      }
      const winners = await Promise.allSettled([1, 2].map(() => accounts.exchangeCode(input, p.randomCredential('zd_os_'))));
      assert.equal(winners.filter(r => r.status === 'fulfilled').length, 1);
      await assert.rejects(accounts.exchangeCode(input, p.randomCredential('zd_os_')), { statusCode: 400 });
      const expired = p.randomCredential('zd_oc_');
      await accounts.createCode(id, 0, expired, authInput(verifier));
      await query('UPDATE obsidian_authorization_codes SET expires_at=now()-interval \'1 second\' WHERE code_hash=$1', [p.digest(expired)]);
      await assert.rejects(accounts.exchangeCode({ ...input, code: expired }, p.randomCredential('zd_os_')), { statusCode: 400 });
      const states = await query('SELECT token_hash FROM obsidian_grants WHERE user_id=$1', [id]);
      assert.equal(states.rowCount, 1);
      assert.match(states.rows[0].token_hash, /^[0-9a-f]{64}$/);
    });
    await t.test('token expiry, revoked grant and disabled account reject reads', async () => {
      const id = await user();
      const a = await issued(id);
      await query("UPDATE obsidian_grants SET expires_at=now()-interval '1 second' WHERE id=$1", [a.grant.id]);
      assert.equal(await accounts.authenticate(a.token), null);
      await assert.rejects(all(a.grant), { statusCode: 401 });
      const b = await issued(id);
      const initial = await all(b.grant);
      await accounts.revoke(b.token);
      await accounts.revoke(b.token);
      assert.equal(await accounts.authenticate(b.token), null);
      await assert.rejects(all(b.grant, initial.next_cursor), { statusCode: 401 });
      assert.equal((await query('SELECT * FROM obsidian_sync_snapshots WHERE grant_id=$1', [b.grant.id])).rowCount, 0);
      const c = await issued(id);
      await query("UPDATE users SET account_status='banned' WHERE id=$1", [id]);
      assert.equal(await accounts.authenticate(c.token), null);
    });
    await t.test('full snapshot has strict DTOs, stable pagination, archived traces and no private extras', async () => {
      const id = await user();
      await trace(id, 'archived', 'removed-book');
      await library.syncLibraryBooks(id, [{ book_id: 'shelf', title: 'Shelf', author: 'Author' }]);
      await progress.upsertReadingProgress(id, { book_id: 'removed-book', progress: 0.6, ...version(1) });
      await query("INSERT INTO free_notes (id,user_id,content) VALUES ($1,$2,'not-exportable free note')", [crypto.randomUUID(), id]);
      const { grant } = await issued(id);
      const result = await all(grant, undefined, 1);
      assert.equal(result.changes.length, 4);
      const removed = result.changes.find(c => c.entity_type === 'book' && c.entity_id === 'removed-book').data;
      assert.equal(removed.in_library, false);
      assert.equal(removed.author, null);
      assert.equal(removed.title, 'Synthetic title');
      assert.doesNotMatch(JSON.stringify(result), /not-exportable|metadata_json|token_hash|password_hash/);
      assert.deepEqual(result.changes.find(c => c.entity_type === 'trace').data.tags, ['tag']);
      const empty = await all(grant, result.next_cursor);
      assert.deepEqual(empty.changes, []);
    });
    await t.test('signed cursors cannot be reused by another user or another grant', async () => {
      const id = await user();
      await trace(id, 'private', 'book');
      const a = await issued(id);
      const b = await issued(await user());
      const c = await issued(id);
      const first = await exports.sync(a.grant, { limit: 1 }, secret);
      for (const grant of [b.grant, c.grant]) {
        await assert.rejects(all(grant, first.next_cursor), { statusCode: 400 });
      }
      assert.deepEqual((await all(b.grant)).changes, []);
    });
    await t.test('writes between snapshot pages arrive via subsequent incrementals without loss', async () => {
      const id = await user();
      const original = await trace(id, 'entry', 'book');
      const { grant } = await issued(id);
      const first = await exports.sync(grant, { limit: 1 }, secret);
      assert.equal(first.has_more, true);
      await trace(id, 'entry', 'book', 2, 'new value');
      const next = await trace(id, 'second', 'book');
      const last = await all(grant, first.next_cursor, 1);
      assert.equal(last.changes.find(c => c.entity_id === original.entry.id).data.note, 'synthetic-note');
      const delta = await all(grant, last.next_cursor, 1);
      assert.equal(delta.changes.find(c => c.entity_id === original.entry.id).data.note, 'new value');
      assert.ok(delta.changes.some(c => c.entity_id === next.entry.id));
      assert.ok(BigInt(delta.watermark) > BigInt(first.watermark));
    });
    await t.test('remove-from-library preserves history; permanent delete emits tombstones', async () => {
      const id = await user();
      await library.syncLibraryBooks(id, [{ book_id: 'book', title: 'Book' }]);
      const entry = await trace(id, 'entry', 'book');
      const savedProgress = await progress.upsertReadingProgress(id, { book_id: 'book', progress: 0.8, ...version(1) });
      const { grant } = await issued(id);
      const full = await all(grant);
      await library.deleteLibraryBook(id, 'book');
      const archive = await all(grant, full.next_cursor);
      assert.equal(archive.changes.length, 1);
      assert.equal(archive.changes[0].operation, 'updated');
      assert.equal(archive.changes[0].data.in_library, false);
      assert.ok(await library.getTraceById(id, entry.entry.id));
      await deletion.permanentlyDeleteBookData(id, 'book');
      const purge = await all(grant, archive.next_cursor);
      assert.ok(purge.changes.some(c => c.entity_id === entry.entry.id && c.operation === 'deleted' && c.data === null));
      assert.ok(purge.changes.some(c => c.entity_id === savedProgress.id && c.operation === 'deleted'));
      assert.equal(await library.getTraceById(id, entry.entry.id), null);
    });
    await t.test('page retries are identical; expiration is explicit, not silent reset', async () => {
      const id = await user();
      await trace(id, 'entry', 'book');
      const { grant } = await issued(id);
      const first = await exports.sync(grant, { limit: 1 }, secret);
      assert.deepEqual(await exports.sync(grant, { limit: 1 }, secret), first);
      const replay1 = await all(grant, first.next_cursor);
      const replay2 = await all(grant, first.next_cursor);
      assert.deepEqual(replay2, replay1);
      const cursor = p.readCursor(first.next_cursor, grant.id, secret);
      await query("UPDATE obsidian_sync_snapshots SET expires_at=now()-interval '1 second' WHERE id=$1", [cursor.snapshot]);
      await assert.rejects(all(grant, first.next_cursor), { statusCode: 410 });
      await exports.cleanupExpired();
      assert.equal((await query('SELECT * FROM obsidian_sync_snapshot_items WHERE snapshot_id=$1', [cursor.snapshot])).rowCount, 0);
    });
    await t.test('HTTP authorization code exchange to full and incremental reads uses real database', async () => {
      const express = require('express');
      const bcrypt = require('bcryptjs');
      const { createObsidianRouter } = require('../routes/obsidian.routes');
      const id = await user();
      const password = 'Synthetic-test-password-only-42';
      await query('UPDATE users SET password_hash=$2 WHERE id=$1', [id, await bcrypt.hash(password, 4)]);
      await trace(id, 'entry', 'book');
      const app = express();
      app.use(express.json());
      app.use('/api/integrations/obsidian', createObsidianRouter({ config: {
        enabled: true, nodeEnv: 'test', cursorSecret: secret, redirectUris: ['obsidian://zhidu-sync'],
      } }));
      const server = app.listen(0, '127.0.0.1');
      await new Promise(resolve => server.once('listening', resolve));
      const base = `http://127.0.0.1:${server.address().port}/api/integrations/obsidian`;
      const post = (route, body, token) => fetch(base + route, { method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
      try {
        const verifier = crypto.randomBytes(32).toString('base64url');
        const input = { ...authInput(verifier), scope: p.SCOPE, state: 's'.repeat(43),
          response_type: 'code', code_challenge_method: 'S256', allow: true };
        const login = await post('/login', { email: `${id}@example.invalid`, password });
        assert.equal(login.status, 200);
        const appToken = (await login.json()).token;
        assert.equal((await fetch(base + '/sync', { headers: { Authorization: `Bearer ${appToken}` } })).status, 401);
        const consent = await post('/authorize', input, appToken);
        assert.equal(consent.status, 200);
        const code = new URL((await consent.json()).redirect_uri).searchParams.get('code');
        const response = await post('/token', { client_id: p.CLIENT_ID, grant_type: 'authorization_code',
          redirect_uri: input.redirect_uri, code, code_verifier: verifier });
        assert.equal(response.status, 200);
        const token = (await response.json()).access_token;
        const headers = { Authorization: `Bearer ${token}` };
        const first = await (await fetch(base + '/sync', { headers })).json();
        assert.equal(first.schema_version, 1);
        assert.equal(first.changes.length, 2);
        await trace(id, 'entry', 'book', 2, 'updated');
        const delta = await (await fetch(base + '/sync?cursor=' + encodeURIComponent(first.next_cursor), { headers })).json();
        assert.equal(delta.changes[0].data.note, 'updated');
        assert.equal((await post('/revoke', {}, token)).status, 204);
        assert.equal((await fetch(base + '/sync', { headers })).status, 401);
      } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
    });
    await t.test('failed token issuance rolls back code consumption; failed export leaves no partial snapshot', async () => {
      const id = await user();
      const verifier = 'v'.repeat(43);
      const code = p.randomCredential('zd_oc_');
      await accounts.createCode(id, 0, code, authInput(verifier));
      const input = { ...authInput(verifier), code, code_verifier: verifier };
      await query(`CREATE FUNCTION obsidian_test_failure() RETURNS trigger AS $$
        BEGIN RAISE EXCEPTION 'synthetic transaction failure'; END; $$ LANGUAGE plpgsql;
        CREATE TRIGGER obsidian_test_failure BEFORE INSERT ON obsidian_grants
          FOR EACH ROW EXECUTE FUNCTION obsidian_test_failure()`);
      try {
        await assert.rejects(accounts.exchangeCode(input, p.randomCredential('zd_os_')));
        assert.equal((await query('SELECT used_at FROM obsidian_authorization_codes WHERE code_hash=$1', [p.digest(code)])).rows[0].used_at, null);
      } finally { await query('DROP TRIGGER obsidian_test_failure ON obsidian_grants'); }
      const token = p.randomCredential('zd_os_');
      await accounts.exchangeCode(input, token);
      const grant = await accounts.authenticate(token);
      await trace(id, 'entry', 'book');
      const ledger = await query('SELECT user_sequence::text FROM sync_changes WHERE user_id=$1 ORDER BY user_sequence', [id]);
      await query(`CREATE TRIGGER obsidian_test_failure BEFORE INSERT ON obsidian_sync_snapshot_items
        FOR EACH ROW EXECUTE FUNCTION obsidian_test_failure()`);
      try {
        await assert.rejects(all(grant));
        assert.equal((await query('SELECT * FROM obsidian_sync_snapshots WHERE grant_id=$1', [grant.id])).rowCount, 0);
        assert.deepEqual((await query('SELECT user_sequence::text FROM sync_changes WHERE user_id=$1 ORDER BY user_sequence', [id])).rows, ledger.rows);
      } finally {
        await query('DROP TRIGGER obsidian_test_failure ON obsidian_sync_snapshot_items; DROP FUNCTION obsidian_test_failure()');
      }
    });
    await t.test('uncommitted upload is absent from snapshot and present after commit', async () => {
      const id = await user();
      const { grant } = await issued(id);
      const writer = await pool.connect();
      try {
        await writer.query('BEGIN');
        const entry = (await writer.query("INSERT INTO user_entries (user_id,source,book_id,user_input) VALUES ($1,'thought','book','late') RETURNING id", [id])).rows[0];
        await require('./syncChange.repository').appendSyncChange(writer.query.bind(writer), {
          userId: id, entityType: 'trace', entityId: entry.id, operation: 'created',
        });
        const first = await all(grant);
        assert.equal(first.watermark, '0');
        assert.deepEqual(first.changes, []);
        await writer.query('COMMIT');
        const delta = await all(grant, first.next_cursor);
        assert.equal(delta.changes[0].entity_id, entry.id);
        assert.equal(delta.watermark, '1');
      } finally { await writer.query('ROLLBACK'); writer.release(); }
    });
  });
}
