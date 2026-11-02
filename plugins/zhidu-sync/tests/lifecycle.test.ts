import { test } from 'node:test';
import assert from 'node:assert/strict';
import ZhiduSync from '../src/main';
import { requests } from './obsidian-mock';
test('plugin onload registers URI and commands without requesting or scheduling a sync', async () => {
  const plugin = new ZhiduSync(null as never, null as never) as ZhiduSync & { handlers: Map<string, unknown>; data: unknown };
  await plugin.onload();
  assert.equal(requests.length, 0);
  assert.ok(plugin.handlers.has('zhidu-sync'));
  assert.equal(plugin.state.connectionId, null);
  assert.equal(plugin.state.sync.cursor, null);
  assert.equal(plugin.state.journal, null);
  assert.ok(plugin.available());
  plugin.onunload(); assert.equal(plugin.available(), false);
});
test('corrupt persisted state fails closed without resetting the saved file', async () => {
  const plugin = new ZhiduSync(null as never, null as never) as ZhiduSync & { data: unknown };
  plugin.data = { schema: 999, cursor: 'important-state' };
  await plugin.onload();
  assert.equal(plugin.available(), false);
  assert.deepEqual(plugin.data, { schema: 999, cursor: 'important-state' });
  assert.equal(requests.length, 0);
});
