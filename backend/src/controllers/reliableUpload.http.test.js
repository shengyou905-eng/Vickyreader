process.env.JWT_SECRET ||= 'local-test-only-jwt-secret-at-least-32-characters';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';
const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const jwt = require('jsonwebtoken');
const { jwtSecret } = require('../config/env');
const users = require('../repositories/user.repository');
const entries = require('../repositories/entry.repository');
const deletion = require('../repositories/bookDeletion.repository');
const progress = require('../repositories/readingProgress.repository');

test('reliable write HTTP routes use authenticated ownership and validate revision envelopes', async () => {
  const original = { auth: users.findAuthUserById, upsert: entries.upsertEntryByClientId,
    remove: entries.deleteEntryByClientId, purge: deletion.permanentlyDeleteBookData };
  const calls = [];
  users.findAuthUserById = async id => ({ id, account_status: 'active', token_version: 0, role: 'user' });
  entries.upsertEntryByClientId = async (...args) => { calls.push(['put', ...args]); return { entry: null, operation: null }; };
  entries.deleteEntryByClientId = async (...args) => { calls.push(['delete', ...args]); return false; };
  deletion.permanentlyDeleteBookData = async (...args) => { calls.push(['purge', ...args]); };
  const app = express();
  app.use(express.json());
  app.use('/api/entries', require('../routes/entries.routes'));
  app.use('/api/library', require('../routes/library.routes'));
  app.use((error, req, res, next) => res.status(error.statusCode || 500).json({ error: 'test error' }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const owner = '10000000-0000-4000-8000-000000000001';
  const token = jwt.sign({ id: owner }, jwtSecret);
  const headers = { authorization: `Bearer ${token}`, 'content-type': 'application/json' };
  const version = { writer_id: '11111111-1111-4111-8111-111111111111', client_revision: 6 };
  try {
    assert.equal((await fetch(`${base}/api/library/books/book/data`, { method: 'DELETE' })).status, 401);
    assert.equal(calls.length, 0);
    const badRevision = await fetch(`${base}/api/entries/client/entry`, {
      method: 'DELETE', headers, body: JSON.stringify({ ...version, client_revision: 0 }),
    });
    assert.equal(badRevision.status, 428);
    assert.equal(calls.length, 0);
    const put = await fetch(`${base}/api/entries/client/entry`, {
      method: 'PUT', headers, body: JSON.stringify({ ...version, source: 'thought', user_id: 'not-owner' }),
    });
    assert.equal(put.status, 200);
    const remove = await fetch(`${base}/api/entries/client/entry`, {
      method: 'DELETE', headers, body: JSON.stringify({ ...version, user_id: 'not-owner' }),
    });
    assert.equal(remove.status, 204);
    const purge = await fetch(`${base}/api/library/books/book/data?user_id=not-owner`, {
      method: 'DELETE', headers, body: JSON.stringify({ user_id: 'not-owner' }),
    });
    assert.equal(purge.status, 204);
    assert.equal((await fetch(`${base}/api/library/books/%20/data`, { method: 'DELETE', headers })).status, 400);
    assert.deepEqual(calls.map(call => [call[0], call[1], call[2]]), [
      ['put', owner, 'entry'], ['delete', owner, 'entry'], ['purge', owner, 'book'],
    ]);
    assert.equal(calls[1][3].client_revision, 6);
  } finally {
    users.findAuthUserById = original.auth;
    entries.upsertEntryByClientId = original.upsert;
    entries.deleteEntryByClientId = original.remove;
    deletion.permanentlyDeleteBookData = original.purge;
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});

test('progress writes require versions on both routes; old servers cannot accept the versioned path', async () => {
  const original = { auth: users.findAuthUserById, save: progress.upsertReadingProgress,
    remove: progress.deleteReadingProgress, get: progress.getReadingProgress };
  const owner = '10000000-0000-4000-8000-000000000001';
  const calls = [];
  users.findAuthUserById = async id => ({ id, account_status: 'active', token_version: 0, role: 'user' });
  progress.upsertReadingProgress = async (...args) => { calls.push(['save', ...args]); return { progress: 0.2 }; };
  progress.deleteReadingProgress = async (...args) => { calls.push(['remove', ...args]); return false; };
  progress.getReadingProgress = async (user, book) => ({ user_id: user, book_id: book, progress: 0.2 });
  const app = express();
  app.use(express.json());
  app.use('/api/reading-progress', require('../routes/readingProgress.routes'));
  // The previous backend's actual route shapes, without making any writes.
  const old = express.Router();
  old.post('/', (req, res) => res.sendStatus(200));
  old.get('/:bookId', (req, res) => res.sendStatus(200));
  old.delete('/:bookId', (req, res) => res.sendStatus(204));
  app.use('/old/reading-progress', old);
  app.use((error, req, res, next) => res.status(error.statusCode || 500).json({ error: 'test error' }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const headers = { authorization: `Bearer ${jwt.sign({ id: owner }, jwtSecret)}`, 'content-type': 'application/json' };
  const version = { writer_id: '11111111-1111-4111-8111-111111111111', client_revision: 2 };
  const send = (url, method, body, auth = headers) => fetch(`${base}${url}`, { method, headers: auth, body: JSON.stringify(body) });
  try {
    const root = '/api/reading-progress';
    assert.equal((await send(`${root}/versioned/book`, 'PUT', version, { 'content-type': 'application/json' })).status, 401);
    assert.equal((await send(root, 'POST', { book_id: 'book', progress: 0.8 })).status, 428);
    assert.equal((await send(`${root}/book`, 'DELETE', {})).status, 428);
    assert.equal((await send(`${root}/versioned/book`, 'PUT', { ...version, client_revision: 0 })).status, 428);
    assert.equal((await send(`${root}/versioned/%20`, 'PUT', version)).status, 400);
    assert.equal(calls.length, 0);
    assert.equal((await send(`${root}/versioned/book`, 'PUT', { ...version, progress: 0.2, user_id: 'foreign', book_id: 'other' })).status, 200);
    assert.equal((await send(`${root}/versioned/book?user_id=foreign`, 'DELETE', { ...version, user_id: 'foreign' })).status, 204);
    assert.equal(calls[0][1], owner);
    assert.equal(calls[0][2].book_id, 'book');
    assert.equal(calls[0][2].client_revision, 2);
    assert.equal(calls[1][1], owner);
    assert.equal(calls[1][2], 'book');
    assert.equal(calls[1][3].client_revision, 2);
    assert.equal((await fetch(`${base}${root}/book`, { headers })).status, 428);
    const get = await fetch(`${base}${root}/versioned/book?user_id=foreign`, { headers });
    assert.equal(get.status, 200);
    assert.equal((await get.json()).reading_progress.user_id, owner);
    for (const method of ['PUT', 'DELETE']) {
      assert.equal((await send('/old/reading-progress/versioned/book', method, version)).status, 404);
    }
  } finally {
    users.findAuthUserById = original.auth;
    progress.upsertReadingProgress = original.save;
    progress.deleteReadingProgress = original.remove;
    progress.getReadingProgress = original.get;
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});
