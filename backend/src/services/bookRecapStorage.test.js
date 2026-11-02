const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { bookRecapConfig } = require('../config/bookRecap');
const api = require('./bookRecapApiContract');
const { createBookRecapStorage } = require('./bookRecapStorage.service');
const { createBookRecapRouter } = require('../routes/bookRecap.routes');
const express = require('express');
const http = require('node:http');

test('B2.1 flags are always closed, lifetimes configurable, no hardcoded polling', () => {
  const c = bookRecapConfig({ RECAP_ENABLED: 'true', RECAP_TEST_PREPARED_SECONDS: '5' });
  assert.equal(c.generationEnabled, false);
  assert.equal(c.readEnabled, false);
  assert.equal(c.preparedSeconds, 5);
  assert.equal(c.previewSeconds, 86400);
  assert.equal(c.onlineRevalidationSeconds, null);
  assert.throws(() => bookRecapConfig({ RECAP_TEST_OPERATION_SECONDS: '0' }));
});
test('strict request contract preserves omitted versus empty follow-ups and rejects private bodies', () => {
  const base = { recap_id: randomUUID(), request_id: randomUUID(), book_id: 'same-title-book',
    selected_sources: [{ entry_id: randomUUID() }] };
  assert.equal(api.prepare.parse(base).selected_sources[0].follow_up_ids, undefined);
  base.selected_sources[0].follow_up_ids = [];
  assert.deepEqual(api.prepare.parse(base).selected_sources[0].follow_up_ids, []);
  assert.throws(() => api.prepare.parse({ ...base, user_id: randomUUID() }));
  assert.throws(() => api.prepare.parse({ ...base, snapshot: { private: 'text' } }));
  assert.throws(() => api.save.parse({ request_id: randomUUID(), expected_revision: '1', result_json: {} }));
  assert.throws(() => api.revision.parse('9223372036854775808'));
  const oversized = Array.from({ length: 8 }, () => ({ entry_id: randomUUID(),
    follow_up_ids: Array.from({ length: 320 }, () => randomUUID()) }));
  assert.throws(() => api.prepare.parse({ ...base, selected_sources: oversized }));
  base.selected_sources.push(base.selected_sources[0]);
  assert.throws(() => api.prepare.parse(base));
});
test('unconfigured source resolver fails before any database or model activity', async () => {
  const service = createBookRecapStorage({ repository: new Proxy({}, {
    get() { throw new Error('Database must not be touched'); },
  }) });
  await assert.rejects(service.prepare(randomUUID(), {}), { error_code: 'RECAP_FOUNDATION_NOT_CONFIGURED' });
});
test('closed router responds without invoking auth/DB/providers', async t => {
  const app = express();
  app.use('/api/xiaou/recaps', createBookRecapRouter());
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const response = await new Promise((resolve, reject) => {
    http.get('http://127.0.0.1:' + server.address().port + '/api/xiaou/recaps', res => {
      let body = ''; res.on('data', b => { body += b; });
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: JSON.parse(body) }));
    }).on('error', reject);
  });
  assert.equal(response.status, 503);
  assert.equal(response.body.error_code, 'RECAP_NOT_AVAILABLE');
  assert.equal(response.headers['cache-control'], 'no-store, private');
});
