// Creates a NEW local cluster, never accepts a database URL or existing PGDATA.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { execFileSync, spawnSync } = require('node:child_process');
const { Client } = require('pg');

async function main() {
  const bin = path.resolve(process.argv[2] || '');
  const ext = process.platform === 'win32' ? '.exe' : '';
  for (const name of ['initdb','pg_ctl']) {
    if (!fs.existsSync(path.join(bin, name + ext))) throw new Error('Pass a PostgreSQL bin directory');
  }
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'zhidu-recap-b21-'));
  const data = path.join(root, 'data');
  const probe = net.createServer();
  await new Promise((resolve, reject) => { probe.once('error', reject); probe.listen(0, '127.0.0.1', resolve); });
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const run = (exe, args) => {
    const log = path.join(root, exe + '.log');
    const fd = fs.openSync(log, 'a');
    try {
      return execFileSync(path.join(bin, exe + ext), args,
        { windowsHide: true, timeout: 60000, stdio: ['ignore', fd, fd] });
    } catch (error) {
      // These commands only contain new synthetic paths, never credentials.
      throw new Error(exe + ': ' + fs.readFileSync(log, 'utf8') + '\n' + error.message);
    } finally { fs.closeSync(fd); }
  };
  let started = false;
  try {
    run('initdb', ['-D', data, '-U', 'recap_test', '--auth=trust', '--encoding=UTF8', '--locale=C']);
    run('pg_ctl', ['-D', data, '-l', path.join(root, 'postgres.log'), '-w', 'start', '-o',
      '-h 127.0.0.1 -p ' + port + ' -c shared_buffers=16MB -c work_mem=1MB -c max_connections=12 -c log_statement=none']);
    started = true;
    const base = 'postgresql://recap_test@127.0.0.1:' + port;
    const admin = new Client({ connectionString: base + '/postgres' });
    await admin.connect();
    try {
      const actual = (await admin.query('SHOW data_directory')).rows[0].data_directory;
      if (fs.realpathSync(actual) !== fs.realpathSync(data)) throw new Error('Cluster identity mismatch');
      await admin.query('CREATE DATABASE zhidu_recap_b21_synthetic');
    } finally { await admin.end(); }
    const env = { ...process.env };
    for (const key of Object.keys(env)) {
      if (/DATABASE_URL|^(PGHOST|PGPORT|PGDATABASE|PGUSER|PGPASSWORD|PGSERVICE|PGOPTIONS)$/i.test(key)) delete env[key];
    }
    env.RECAP_SYNTHETIC_DATABASE_URL = base + '/zhidu_recap_b21_synthetic';
    env.RECAP_SYNTHETIC_DATA = data;
    // Tests bypass config/db entirely; no dotenv or deployment credentials.
    const child = spawnSync(process.execPath,
      ['--test', 'src/repositories/bookRecap.postgres.test.js'],
      { cwd: path.join(__dirname, '..'), env, windowsHide: true, stdio: 'inherit', timeout: 180000 });
    if (child.error) throw child.error;
    process.exitCode = child.status ?? 1;
  } finally {
    // A launcher timeout can happen after PostgreSQL has started on Windows.
    // Only this invocation's freshly created data directory may be stopped.
    if (started || fs.existsSync(path.join(data, 'postmaster.pid'))) {
      run('pg_ctl', ['-D', data, '-m', 'fast', '-w', 'stop']);
      started = true;
    }
    // Preserve stopped synthetic cluster/logs for audit, never delete old backups.
    console.log('Synthetic cluster ' + (started ? 'stopped' : 'not started') + '; retained at ' + root);
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
