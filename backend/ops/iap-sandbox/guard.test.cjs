const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/guard.cjs', 'utf8');
async function simulate({ availableMiB = 1200, healthy = true, diskGiB = 24, busy = false } = {}) {
  const writes = new Map();
  const stops = [];
  let tick, exited, time = 0;
  const mocks = {
    'node:fs': {
      readFileSync: () => `MemAvailable: ${availableMiB * 1024} kB\n`,
      statfsSync: () => ({ bavail: diskGiB * 1024 ** 3, bsize: 1 }),
      writeFileSync: (path, value) => writes.set(path, value),
    },
    'node:os': { cpus: () => { time += 100; return [{ times: { idle: busy ? 0 : time, user: busy ? time : 0 } }]; } },
    'node:child_process': { execFileSync: (command, args) => stops.push({ command, args }) },
  };
  vm.runInNewContext(source, {
    require: name => { assert.ok(mocks[name]); return mocks[name]; },
    fetch: async url => { assert.equal(url, 'http://127.0.0.1:3000/api/health'); return { ok: healthy, json: async () => ({ status: healthy ? 'ok' : 'error', env: 'production' }) }; },
    AbortSignal, setInterval: callback => { tick = callback; },
    process: { exit: code => { exited = code; } }, console: { error() {} },
  });
  await new Promise(resolve => setImmediate(resolve));
  return { writes, stops, get exited() { return exited; }, tick };
}
test('healthy production and sufficient resources never stop any container', async () => {
  const state = await simulate();
  assert.equal(state.exited, undefined);
  assert.equal(state.stops.length, 0);
  assert.equal(JSON.parse(state.writes.get('/home/ubuntu/apps/zhidu-iap-sandbox/guard-status.json')).healthy, true);
});
for (const [name, options, reason] of [
  ['low memory', { availableMiB: 383 }, 'memory_pressure'],
  ['production unhealthy', { healthy: false }, 'production_health'],
  ['low disk', { diskGiB: 4 }, 'disk_pressure'],
]) {
  test(name + ' stops only explicitly named Sandbox containers', async () => {
    const state = await simulate(options);
    assert.equal(state.exited, 1);
    assert.equal(state.writes.get('/home/ubuntu/apps/zhidu-iap-sandbox/STOPPED'), reason);
    assert.deepEqual(state.stops.map(x => x.args.at(-1)), ['zhidu-iap-sandbox-api', 'zhidu-iap-sandbox-init', 'zhidu-iap-sandbox-deps', 'zhidu-iap-sandbox-postgres']);
    assert.ok(state.stops.every(x => x.command === 'docker' && x.args[0] === 'stop'));
  });
}
test('sustained high CPU stops Sandbox after six samples, not one spike', async () => {
  const state = await simulate({ busy: true });
  for (let n = 0; n < 5; n++) await state.tick();
  assert.equal(state.exited, undefined);
  await state.tick();
  assert.equal(state.exited, 1);
  assert.equal(state.writes.get('/home/ubuntu/apps/zhidu-iap-sandbox/STOPPED'), 'sustained_cpu_pressure');
});
