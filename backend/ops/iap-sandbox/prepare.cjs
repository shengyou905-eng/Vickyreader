const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');
const root = '/home/ubuntu/apps/zhidu-iap-sandbox';
if (!process.cwd().startsWith(root + '/releases/')) throw new Error('Wrong deployment directory');
const secret = () => crypto.randomBytes(32).toString('hex');
fs.mkdirSync(root + '/config', { mode: 0o700 });
const adminPassword = secret();
const appPassword = secret();
const write = (name, contents) => fs.writeFileSync(root + '/config/' + name, contents, { mode: 0o600, flag: 'wx' });
write('db.env', [
  'POSTGRES_USER=zhidu_sandbox_admin', 'POSTGRES_DB=zhidu_iap_sandbox',
  'POSTGRES_PASSWORD=' + adminPassword, 'POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256', '',
].join('\n'));
write('roles.json', JSON.stringify({ appPassword }));
write('app.env', [
  'NODE_ENV=production', 'HOST=0.0.0.0', 'PORT=3000', 'NODE_OPTIONS=--max-old-space-size=192',
  'DATABASE_URL=postgresql://zhidu_sandbox_app:' + appPassword + '@sandbox-db:5432/zhidu_iap_sandbox',
  'JWT_SECRET=' + secret(), 'AUTH_RATE_LIMIT_SECRET=' + secret(),
  'MCP_TOKEN_HASH_SECRET=' + secret(), 'OBSIDIAN_SYNC_ENABLED=false',
  'CORS_ORIGIN=http://127.0.0.1:3001', 'PUBLIC_BASE_URL=http://127.0.0.1:3001',
  'APPLE_IAP_ENABLED=false', 'APPLE_IAP_ENVIRONMENT=Sandbox',
  'APPLE_IAP_BUNDLE_ID=com.youxugarden.zhireader', '',
].join('\n'));
const files = [];
function scan(directory) {
  for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, item.name);
    if (item.isSymbolicLink()) throw new Error('Source symlink not allowed');
    if (item.isDirectory()) scan(file);
    else files.push({ file: file.replaceAll('\\', '/'), sha256: crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') });
  }
}
scan('src'); scan('ops');
for (const file of ['server.js', 'package.json', 'package-lock.json']) {
  files.push({ file, sha256: crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') });
}
fs.writeFileSync(root + '/release-manifest.json', JSON.stringify({
  createdAt: new Date().toISOString(), sourceCommit: process.argv[2],
  source: 'approved local workspace snapshot, including uncommitted Phase 1/2 files',
  release: process.cwd(), files,
}, null, 2), { mode: 0o600, flag: 'wx' });
console.log('Independent Sandbox credentials and source manifest created; no secret values printed.');
