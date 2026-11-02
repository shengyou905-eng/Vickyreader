// Browser-based acceptance client. Secrets and reading content stay in memory.
// No files, vault content, business rows or tokens are printed by this helper.
const http = require('node:http');
const crypto = require('node:crypto');
const readline = require('node:readline/promises');

async function main() {
  const base = new URL(process.env.OBSIDIAN_TEST_BASE_URL || 'http://127.0.0.1:3002');
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(base.hostname);
  if ((!local && base.protocol !== 'https:') || base.username || base.password
      || base.pathname !== '/' || base.search || base.hash
      || base.hostname === 'api.youxugarden.com') throw new Error('Use an explicit non-production API origin');
  const port = Number(process.env.OBSIDIAN_CALLBACK_PORT || 9876);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid callback port');
  const redirect = `http://127.0.0.1:${port}/callback`;
  const verifier = crypto.randomBytes(32).toString('base64url');
  const state = crypto.randomBytes(32).toString('base64url');
  const root = new URL('/api/integrations/obsidian/', base).toString();
  let token;
  let cursor;
  const api = async (path, body) => {
    const response = await fetch(root + path, {
      method: body === undefined ? 'GET' : 'POST', signal: AbortSignal.timeout(20000),
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (!response.ok) throw new Error(`Test endpoint returned HTTP ${response.status}`);
    return response.status === 204 ? null : response.json();
  };
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const server = http.createServer();
  try {
    const receiveCode = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Authorization timed out')), 300000);
      timer.unref();
      server.on('error', reject);
      server.on('request', (req, res) => {
        const callback = new URL(req.url, redirect);
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('Referrer-Policy', 'no-referrer');
        if (callback.pathname !== '/callback' || callback.searchParams.get('state') !== state) {
          res.writeHead(400).end('Invalid callback'); return;
        }
        clearTimeout(timer);
        if (callback.searchParams.get('error')) {
          res.end('Authorization declined. You can close this page.');
          reject(new Error('Authorization declined')); return;
        }
        const code = callback.searchParams.get('code');
        if (!/^zd_oc_[A-Za-z0-9_-]{43}$/.test(code || '')) {
          res.writeHead(400).end('Invalid code'); reject(new Error('Invalid authorization code')); return;
        }
        res.end('Connected to Zhidu test environment. Return to the terminal.');
        resolve(code);
      });
    });
    // Attach a rejection handler immediately while the browser is not open yet.
    receiveCode.catch(() => {});
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); });
    const authorize = new URL('authorize', root);
    authorize.search = new URLSearchParams({ response_type: 'code', client_id: 'zhidu-sync',
      redirect_uri: redirect, scope: 'obsidian.sync.read', state,
      code_challenge: crypto.createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256' });
    console.log('Open in the browser on THIS computer and sign in with a test account:');
    console.log(authorize.toString());
    const code = await receiveCode;
    const credentials = await api('token', { grant_type: 'authorization_code', client_id: 'zhidu-sync',
      redirect_uri: redirect, code, code_verifier: verifier });
    token = credentials.access_token;
    console.log('Authorization exchanged. Access token is kept in memory, not printed.');
    async function readAll(label) {
      let more;
      let count = 0;
      const summary = {};
      do {
        const query = new URLSearchParams({ limit: '50', ...(cursor ? { cursor } : {}) });
        const page = await api(`sync?${query}`);
        for (const change of page.changes) {
          const key = `${change.entity_type}:${change.operation}`;
          summary[key] = (summary[key] || 0) + 1;
        }
        count += page.changes.length;
        cursor = page.next_cursor;
        more = page.has_more;
      } while (more);
      console.log(`${label}: ${count} changes`, summary);
    }
    await readAll('Initial snapshot');
    await readAll('Unchanged incremental');
    await rl.question('Create/update/delete a trace in the TEST app, wait for upload, then press Enter: ');
    await readAll('Incremental after upload');
    await api('revoke', {});
    const revoked = await fetch(root + 'sync', { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(10000) });
    if (revoked.status !== 401) throw new Error('Revocation did not reject access');
    token = null;
    console.log('Revocation verified (401). No reading content was printed or saved.');
  } finally {
    if (token) {
      try { await api('revoke', {}); }
      catch (_) { console.error('Could not revoke this test grant; it expires within 24 hours.'); }
    }
    rl.close(); server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
