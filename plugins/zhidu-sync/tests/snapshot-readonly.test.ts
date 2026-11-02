import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { parsePage } from '../src/model';
import { render } from '../src/markdown';

test('existing local PostgreSQL snapshot DTOs parse and render without changing test data', {
  skip: process.env.ZHIDU_READONLY_SNAPSHOT_TEST !== '1',
}, async () => {
  // Fixed disposable database, read-only transaction, no credentials or reading text in output.
  const raw = execFileSync('docker', ['exec', 'zhidu-device-acceptance-pg', 'psql', '-X', '-q',
    '-U', 'postgres', '-d', 'zhidu_obsidian_phase1_test', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-c',
    `BEGIN READ ONLY;
     SELECT COALESCE(json_agg(change ORDER BY snapshot_id, ordinal), '[]'::json)
     FROM obsidian_sync_snapshot_items;
     COMMIT;`], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const changes: unknown[] = JSON.parse(raw.trim());
  assert.ok(changes.length > 0, 'Existing snapshot evidence must be present');
  let textIndexes = 0;
  for (const change of changes) {
    const page = parsePage({ schema_version: 1, phase: 'snapshot', watermark: '0', next_cursor: 'test-only',
      has_more: false, changes: [change] });
    const entity = page.changes[0].entity;
    if (!entity) continue;
    if (entity.entity_type !== 'book' && typeof entity.data.chapter_index === 'string') textIndexes++;
    await render(entity.data.book_id, { [`${entity.entity_type}:${entity.entity_id}`]: entity });
  }
  assert.ok(textIndexes > 0, 'Exercise actual TEXT chapter indexes, not only null fixtures');
});
