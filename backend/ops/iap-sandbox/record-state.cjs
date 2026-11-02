const fs = require('node:fs');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const root = '/home/ubuntu/apps/zhidu-iap-sandbox';
const manifest = JSON.parse(fs.readFileSync(root + '/release-manifest.json', 'utf8'));
if (process.cwd() !== manifest.release) throw new Error('Wrong release directory');
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const files = manifest.files.filter(x => !x.file.startsWith('ops/')).map(x => ({ file: x.file, sha256: sha(x.file) }));
for (const file of fs.readdirSync('ops/iap-sandbox')) files.push({ file: 'ops/iap-sandbox/' + file, sha256: sha('ops/iap-sandbox/' + file) });
const containers = JSON.parse(execFileSync('docker', ['inspect', 'zhidu-iap-sandbox-api', 'zhidu-iap-sandbox-postgres'], { encoding: 'utf8' }));
const state = {
  recordedAt: new Date().toISOString(), sourceCommit: manifest.sourceCommit,
  source: manifest.source, release: manifest.release, originalManifestSha256: sha(root + '/release-manifest.json'),
  files, initialization: {
    freshSchemaExecutedOnce: true, embeddedMigrations: '002-009',
    separateMigration001AppliedOnce: true,
    note: 'Initial API smoke exposed missing 001 auth tables in schema.sql; completed 001 on the empty Sandbox, then all 11 smoke/structure groups passed. No embedded migration replayed.',
  },
  containers: containers.map(c => ({ name: c.Name, image: c.Config.Image,
    status: c.State.Status, health: c.State.Health?.Status,
    memoryMiB: c.HostConfig.Memory / 1048576, cpus: c.HostConfig.NanoCpus / 1e9,
    restart: c.HostConfig.RestartPolicy.Name, logs: c.HostConfig.LogConfig,
    ports: c.HostConfig.PortBindings, networks: Object.keys(c.NetworkSettings.Networks),
    iapEnabled: c.Name.endsWith('-api') ? c.Config.Env.includes('APPLE_IAP_ENABLED=true') : undefined,
    iapSandbox: c.Name.endsWith('-api') ? c.Config.Env.includes('APPLE_IAP_ENVIRONMENT=Sandbox') : undefined,
  })),
  productionFingerprints: Object.fromEntries([
    '/etc/nginx/sites-enabled/api.youxugarden.com',
    '/home/ubuntu/apps/Vickyreader/backend/.env',
    '/home/ubuntu/apps/Vickyreader/backend/src/app.js',
  ].map(file => [file, sha(file)])),
};
fs.writeFileSync(root + '/final-release-manifest.json', JSON.stringify(state, null, 2), { mode: 0o600 });
console.log('Final source hashes, initialization history and safe container metadata recorded.');
