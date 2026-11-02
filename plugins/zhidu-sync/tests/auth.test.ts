import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Api, Transport } from '../src/api';
import { Authorization, Secrets } from '../src/auth';
import { initialState } from '../src/model';
import { sha256 } from '../src/crypto';
import { userMessage } from '../src/errors';
const id = '11111111-1111-4111-8111-111111111111';
const token = 'zd_os_' + 'a'.repeat(43);
class MemorySecrets implements Secrets {
  data = new Map<string, string>();
  getSecret(key: string) { return this.data.get(key) || null; }
  setSecret(key: string, value: string) { assert.match(key, /^[a-z0-9-]+$/); this.data.set(key, value); }
}
test('PKCE matches RFC vector and credentials stay only in SecretStorage across restart', async () => {
  assert.equal(await sha256('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
  const secrets = new MemorySecrets(); let verifier = '';
  const api = new Api('https://test.example', async input => {
    const body = JSON.parse(input.body!); verifier = body.code_verifier;
    assert.equal(body.redirect_uri, 'obsidian://zhidu-sync');
    return { status: 200, json: { access_token: token, expires_in: 86400, scope: 'obsidian.sync.read', token_type: 'Bearer' } };
  });
  const first = new Authorization(secrets, id, api), url = new URL(await first.begin());
  assert.equal(url.searchParams.get('code_challenge_method'), 'S256');
  const restarted = new Authorization(secrets, id, api);
  await restarted.complete({ code: 'zd_oc_' + 'c'.repeat(43), state: url.searchParams.get('state')! });
  assert.equal(await sha256(verifier), url.searchParams.get('code_challenge'));
  assert.equal(restarted.token(), token);
  const ordinary = JSON.stringify(initialState(id, api.origin));
  assert.ok(!ordinary.includes(token)); assert.ok(!ordinary.includes(verifier));
  await assert.rejects(restarted.complete({ code: 'zd_oc_' + 'c'.repeat(43), state: url.searchParams.get('state')! }));
});
test('wrong state, denial and different vault callback do not exchange tokens', async () => {
  let calls = 0;
  const secrets = new MemorySecrets(), api = new Api('https://test.example', async () => { calls++; return { status: 500, json: null }; });
  const auth = new Authorization(secrets, id, api), url = new URL(await auth.begin());
  await assert.rejects(auth.complete({ state: 'wrong' }));
  await assert.rejects(new Authorization(secrets, '22222222-2222-4222-8222-222222222222', api).complete({ state: url.searchParams.get('state')! }));
  await assert.rejects(auth.complete({ state: url.searchParams.get('state')!, error: 'access_denied' }));
  assert.equal(calls, 0); assert.equal(auth.token(), null);
});
test('revocation failure retains token for retry; success clears credentials', async () => {
  const secrets = new MemorySecrets(); let fail = true;
  const auth = new Authorization(secrets, id, new Api('https://test.example', async input => {
    assert.equal(input.headers.Authorization, `Bearer ${token}`);
    return { status: fail ? 500 : 204, json: null };
  }));
  secrets.setSecret(auth.tokenKey, token);
  await assert.rejects(auth.disconnect()); assert.equal(auth.token(), token);
  fail = false; await auth.disconnect(); assert.equal(auth.token(), null);
});
test('expired/revoked access, networking and invalid response have human-readable safe errors', async () => {
  for (const status of [401, 403, 410, 429, 500]) {
    const api = new Api('https://test.example', async () => ({ status, json: { token, reading_body: 'private' } }));
    try { await api.page(token, null); assert.fail(); }
    catch (error) { assert.doesNotMatch(userMessage(error), /zd_os_|private|Unauthorized|ECONNRESET/); }
  }
  const transport: Transport = async () => { throw new Error(`ECONNRESET ${token}`); };
  await assert.rejects(new Api('https://test.example', transport).status(token), /暂时无法连接/);
});
test('late authorization from an unloaded instance cannot replace a newer SecretStorage token', async () => {
  const secrets = new MemorySecrets(); let active = true;
  let release!: (value: { status: number; json: unknown }) => void;
  const api = new Api('https://test.example', async input => input.url.endsWith('/revoke')
    ? { status: 204, json: null } : new Promise(resolve => { release = resolve; }));
  const auth = new Authorization(secrets, id, api, () => active);
  const url = new URL(await auth.begin());
  const old = auth.complete({ state: url.searchParams.get('state')!, code: 'zd_oc_' + 'c'.repeat(43) });
  active = false;
  const newer = 'zd_os_' + 'b'.repeat(43);
  secrets.setSecret(auth.tokenKey, newer);
  secrets.setSecret(auth.pendingKey, 'a new instance owns this pending state');
  release({ status: 200, json: { access_token: token, expires_in: 86400, token_type: 'Bearer', scope: 'obsidian.sync.read' } });
  await assert.rejects(old, /更新的连接/);
  assert.equal(auth.token(), newer); assert.equal(secrets.getSecret(auth.pendingKey), 'a new instance owns this pending state');
});
