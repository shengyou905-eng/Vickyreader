import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parse } from 'yaml';
import { Api } from '../src/api';
import { Authorization } from '../src/auth';
import { initialState, State } from '../src/model';
import { SyncEngine, VaultPort } from '../src/sync';

const origin = process.env.ZHIDU_TEST_ORIGIN;
test('plugin core -> real local authorization -> PostgreSQL snapshot/delta -> protected Markdown -> revoke',
  { skip: !origin && 'Set ZHIDU_TEST_ORIGIN for the isolated local backend' }, async () => {
    assert.equal(origin, 'http://127.0.0.1:3002', 'Only the dedicated local test server is permitted');
    const health = await (await fetch(origin + '/api/health')).json() as Record<string, unknown>;
    assert.equal(health.production, false); assert.equal(health.environment, 'obsidian-local-test');
    assert.equal(health.database, 'zhidu_obsidian_phase1_test');
    const post = async (path: string, body: unknown, token?: string, method = 'POST') => {
      const response = await fetch(origin + path, { method, headers: { 'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
      assert.ok(response.ok, `HTTP ${response.status}`);
      return response.status === 204 ? null : response.json();
    };
    const email = `plugin-${crypto.randomUUID()}@example.invalid`;
    const password = crypto.randomUUID();
    await post('/api/auth/register', { email, password });
    const login = await post('/api/integrations/obsidian/login', { email, password });
    const secretValues = new Map<string, string>();
    const api = new Api(origin!, async input => {
      const response = await fetch(input.url, { method: input.method, headers: input.headers, body: input.body });
      return { status: response.status, json: response.status === 204 ? null : await response.json() };
    });
    const installId = crypto.randomUUID();
    const auth = new Authorization({ getSecret: k => secretValues.get(k) || null, setSecret: (k, v) => { secretValues.set(k, v); } }, installId, api);
    const authorization = new URL(await auth.begin());
    assert.equal((await fetch(authorization)).status, 200);
    const consent = await post('/api/integrations/obsidian/authorize', { ...Object.fromEntries(authorization.searchParams), allow: true }, login.token);
    const callback = new URL(consent.redirect_uri);
    await auth.complete(Object.fromEntries(callback.searchParams));
    const token = auth.token()!;
    const bookId = crypto.randomUUID(), entryId = crypto.randomUUID(), writer = crypto.randomUUID();
    const payload = (revision: number, note: string) => ({ source: 'thought', book_id: bookId,
      book_title: 'Synthetic integration book', user_input: note, original_text: 'Synthetic excerpt',
      client_revision: revision, writer_id: writer });
    let state: State = { ...initialState(installId, origin!), connectionId: crypto.randomUUID() };
    const files = new Map<string, string>();
    const vault: VaultPort = { files: () => [...files.keys()], exists: p => files.has(p), read: async p => files.get(p)!,
      create: async (p, v) => { assert.equal(files.has(p), false); files.set(p, v); },
      process: async (p, fn) => { files.set(p, fn(files.get(p)!)); } };
    const sync = async () => {
      await api.status(token);
      await new SyncEngine({ get: () => state, save: async v => { state = structuredClone(v); } }, vault, parse, cursor => api.page(token, cursor)).run();
    };
    try {
      await post(`/api/entries/client/${entryId}`, payload(1, 'Initial thought'), login.token, 'PUT');
      await sync(); assert.equal(files.size, 1); assert.match([...files.values()][0], /Initial thought/);
      const path = [...files.keys()][0]; files.set(path, files.get(path)! + '\nMy private note');
      const before = state.sync.cursor;
      await sync(); assert.equal(state.sync.cursor, before); assert.equal(files.size, 1);
      await post(`/api/entries/client/${entryId}`, payload(2, 'Updated thought'), login.token, 'PUT');
      await sync(); assert.match(files.get(path)!, /Updated thought/); assert.match(files.get(path)!, /My private note/);
      await post(`/api/entries/client/${entryId}`, { client_revision: 3, writer_id: writer }, login.token, 'DELETE');
      await sync(); assert.doesNotMatch(files.get(path)!, /Updated thought/); assert.match(files.get(path)!, /My private note/);
      assert.ok(!JSON.stringify(state).includes(token));
      await auth.disconnect(); await assert.rejects(api.status(token), /授权已失效/);
    } finally { if (auth.token()) await auth.disconnect(); }
  });
