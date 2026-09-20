const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

for (const nodeEnv of ['production', 'development', 'test']) {
  test(`${nodeEnv} startup respects explicit production migrations`, async () => {
    let schemaCalls = 0;
    let listenCalls = 0;
    const server = {};
    const modules = {
      './app': { listen(port, host) {
        assert.equal(port, 3000);
        assert.equal(host, '127.0.0.1');
        listenCalls++;
        return server;
      } },
      './config/env': { host: '127.0.0.1', port: 3000, nodeEnv },
      './db/init': { async initSchema() { schemaCalls++; } },
    };
    vm.runInNewContext(fs.readFileSync(require.resolve('./server'), 'utf8'), {
      require: (name) => {
        assert.ok(Object.hasOwn(modules, name));
        return modules[name];
      },
      console: { log() {}, error() { assert.fail('Unexpected startup error'); } },
      process: { exit() { assert.fail('Unexpected exit'); } },
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(schemaCalls, nodeEnv === 'production' ? 0 : 1);
    assert.equal(listenCalls, 1);
    assert.equal(server.requestTimeout, 180000);
    assert.equal(server.headersTimeout, 65000);
    assert.equal(server.keepAliveTimeout, 65000);
  });
}
