import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parse } from 'yaml';
import { initialState, parsePage, State, stateSchema } from '../src/model';
import { SyncEngine, Store, VaultPort } from '../src/sync';
import { END, identity, region, START } from '../src/markdown';

const uuid = '11111111-1111-4111-8111-111111111111';
const connection = '22222222-2222-4222-8222-222222222222';
const book = (bookId = 'book-a') => ({ entity_type: 'book', entity_id: bookId, operation: 'created', sequence: null, version: '1',
  data: { book_id: bookId, title: '规训与惩罚', author: null, format: null, in_library: true,
    added_at: null, last_opened_at: null, created_at: null, updated_at: null } });
const trace = (id = 'trace-a', bookId = 'book-a', note = '我的想法', type = 'thought') => ({ entity_type: 'trace', entity_id: id,
  operation: 'created', sequence: '1', version: '1', data: { id, book_id: bookId, type, book_title: '规训与惩罚', chapter_index: 2,
    chapter_title: '章节', excerpt: '原文', note, explanation: null, tags: ['阅读'], is_important: false,
    created_at: '2026-09-22T00:00:00Z', updated_at: '2026-09-22T00:00:00Z' } });
const deleted = (id: string, entity_type = 'trace') => ({ entity_type, entity_id: id, operation: 'deleted', sequence: '2', version: '2', data: null });
const page = (changes: unknown[], cursor = 'cursor-1', phase = 'snapshot', has_more = false) => parsePage({
  schema_version: 1, phase, watermark: '1', next_cursor: cursor, has_more, changes,
});
class MemoryStore implements Store {
  state: State = { ...initialState(uuid, 'http://127.0.0.1:3002'), connectionId: connection };
  failAck = false;
  writes: State[] = [];
  get() { return this.state; }
  async save(state: State) {
    if (this.failAck && !state.journal) throw new Error('simulated disk error');
    this.state = structuredClone(state); this.writes.push(structuredClone(state));
  }
}
class MemoryVault implements VaultPort {
  data = new Map<string, string>();
  failCreateNumber = 0;
  created = 0;
  beforeProcess?: (path: string) => void;
  files() { return [...this.data.keys()]; }
  exists(path: string) { return this.data.has(path); }
  async read(path: string) { assert.ok(this.data.has(path)); return this.data.get(path)!; }
  async create(path: string, content: string) {
    if (++this.created === this.failCreateNumber) throw new Error('simulated write failure');
    assert.equal(this.data.has(path), false); this.data.set(path, content);
  }
  async process(path: string, transform: (text: string) => string) {
    this.beforeProcess?.(path); this.beforeProcess = undefined;
    this.data.set(path, transform(await this.read(path)));
  }
}
function setup() {
  const store = new MemoryStore(); const vault = new MemoryVault();
  const run = (p: ReturnType<typeof page>) => new SyncEngine(store, vault, parse, async () => p).run();
  return { store, vault, run };
}
test('full snapshot writes native Markdown, null author, all subtypes, safe text and progress', async () => {
  const { vault, store, run } = setup();
  await run(page([book(), ...['highlight', 'thought', 'ai_explanation', 'ai_question'].map((type, i) => trace(`t${i}`, 'book-a', `<script>${START}[[unsafe]]`, type)),
    { entity_type: 'reading_progress', entity_id: 'p1', operation: 'created', sequence: null, version: '1', data: {
      id: 'p1', book_id: 'book-a', progress: .3125, chapter_index: 2, scroll_offset: null, cfi: null, created_at: null, updated_at: null } } ]));
  const text = [...vault.data.values()][0];
  assert.match(text, /author: null/); assert.match(text, /31.25%/);
  for (const heading of ['划线', '我的想法', '小U解读', '问小U']) assert.ok(text.includes(`### ${heading}`));
  assert.equal(text.split(START).length, 2); assert.doesNotMatch(text, /<script>/);
  assert.equal(store.state.sync.cursor, 'cursor-1'); assert.ok(store.state.lastSync);
  assert.ok(store.writes[0].journal); assert.equal(store.writes[0].sync.cursor, null);
});
test('incremental upsert protects user text and frontmatter byte-for-byte, supports rename and move', async () => {
  const { vault, store, run } = setup();
  await run(page([book(), trace()]));
  const originalPath = vault.files()[0];
  const original = (await vault.read(originalPath)).replace('## 我的笔记', '## 我的笔记\n\n私人追加内容');
  const renamed = 'Philosophy/福柯：规训社会.md';
  vault.data.delete(originalPath); vault.data.set(renamed, original);
  await run(page([trace('trace-a', 'book-a', '新想法')], 'cursor-2', 'incremental'));
  const updated = await vault.read(renamed);
  assert.equal(vault.files().length, 1);
  assert.equal(updated.slice(0, region(updated).start), original.slice(0, region(original).start));
  assert.equal(updated.slice(region(updated).end), original.slice(region(original).end));
  assert.match(updated, /新想法/); assert.equal(store.state.sync.receipts['b:book-a'].path, renamed);
});

test('TEXT chapter indexes from PostgreSQL survive parsing, persistence and safe rendering', async () => {
  for (const index of ['0', '002', 'chapter-intro', '', null, 2, `intro\n${END}[[embed]]`]) {
    const { vault, store, run } = setup();
    const t = { ...trace(), data: { ...trace().data, chapter_index: index, chapter_title: null } };
    const p = { entity_type: 'reading_progress', entity_id: 'p1', operation: 'created', sequence: null, version: '1', data: {
      id: 'p1', book_id: 'book-a', progress: .2, chapter_index: index, scroll_offset: 0, cfi: null, created_at: null, updated_at: null } };
    await run(page([book(), t, p]));
    const restored = stateSchema.parse(JSON.parse(JSON.stringify(store.state)));
    assert.equal((restored.sync.entities['trace:trace-a'].data as { chapter_index: unknown }).chapter_index, index);
    assert.equal((restored.sync.entities['reading_progress:p1'].data as { chapter_index: unknown }).chapter_index, index);
    const output = [...vault.data.values()][0];
    assert.equal(output.split(END).length, 2);
    assert.doesNotMatch(output, /\[\[embed\]\]/);
    if (index === '002') assert.ok(output.includes('章节索引：002'));
    assert.equal(store.state.sync.cursor, 'cursor-1');
  }
  for (const invalid of [true, {}, []]) {
    assert.throws(() => page([{ ...trace(), data: { ...trace().data, chapter_index: invalid } }]));
  }
});
test('duplicate IDs, edited managed region, corrupted identity and local deletion fail closed', async () => {
  for (const damage of ['duplicate', 'region', 'identity', 'delete']) {
    const { vault, store, run } = setup();
    await run(page([book(), trace()]));
    const path = vault.files()[0], text = await vault.read(path);
    if (damage === 'duplicate') vault.data.set('duplicate.md', text);
    if (damage === 'region') vault.data.set(path, text.replace('我的想法', '手动改动'));
    if (damage === 'identity') vault.data.set(path, text.replace('zhidu_book_id:', 'broken:'));
    if (damage === 'delete') vault.data.delete(path);
    const before = new Map(vault.data);
    await assert.rejects(run(page([trace('trace-a', 'book-a', 'update')], 'cursor-2', 'incremental')));
    assert.deepEqual(vault.data, before); assert.equal(store.state.sync.cursor, 'cursor-1');
  }
});
test('second file failure leaves old cursor; a new engine replays journal without duplicates', async () => {
  const { vault, store, run } = setup();
  vault.failCreateNumber = 2;
  await assert.rejects(run(page([book(), book('book-b'), trace(), trace('trace-b', 'book-b')])));
  assert.equal(vault.files().length, 1); assert.equal(store.state.sync.cursor, null); assert.ok(store.state.journal);
  vault.failCreateNumber = 0;
  // Simulate restart: load the durable journal, not transient in-memory state.
  store.state = structuredClone(store.state);
  await new SyncEngine(store, vault, parse, async () => { throw new Error('must replay before fetching'); }).run();
  assert.equal(vault.files().length, 2); assert.equal(store.state.sync.cursor, 'cursor-1'); assert.equal(store.state.journal, null);
});
test('file success but cursor persistence failure is replayable', async () => {
  const { vault, store, run } = setup(); store.failAck = true;
  await assert.rejects(run(page([book(), trace()])));
  assert.equal(store.state.sync.cursor, null); assert.ok(store.state.journal);
  const contents = new Map(vault.data); store.failAck = false;
  await run(page([])); assert.deepEqual(vault.data, contents); assert.equal(store.state.sync.cursor, 'cursor-1');
});
test('remote deletion removes only managed traces; empty books and user notes survive', async () => {
  const { vault, run } = setup(); await run(page([book(), trace()]));
  const path = vault.files()[0]; vault.data.set(path, (await vault.read(path)) + '\nuser-owned');
  await run(page([deleted('trace-a'), deleted('book-a', 'book')], 'cursor-2', 'incremental'));
  const text = await vault.read(path); assert.match(text, /user-owned/); assert.doesNotMatch(region(text).text, /原文/);
  assert.equal(vault.files().length, 1);
});
test('remove from bookshelf retains traces; trace-only incrementals create historical book grouping', async () => {
  const { vault, run } = setup(); await run(page([trace()]));
  const archived = book(); archived.data.in_library = false;
  await run(page([archived], 'cursor-2', 'incremental'));
  const text = [...vault.data.values()][0]; assert.match(text, /已移出书架/); assert.match(text, /原文/);
});
test('first snapshot pagination and repeated full snapshot remove only absent managed records', async () => {
  const { vault, store } = setup();
  const pages = [page([book()], 'page-1', 'snapshot', true), page([trace()], 'delta-1')];
  const cursors: (string | null)[] = [];
  await new SyncEngine(store, vault, parse, async cursor => { cursors.push(cursor); return pages.shift()!; }).run();
  assert.deepEqual(cursors, [null, 'page-1']); assert.equal(store.state.sync.cursor, 'delta-1');
  await store.save({ ...store.state, sync: { ...store.state.sync, cursor: null } });
  await new SyncEngine(store, vault, parse, async () => page([book()], 'delta-2')).run();
  assert.doesNotMatch(region([...vault.data.values()][0]).text, /原文/);
});
test('concurrent user edit inside process is not overwritten; outside edit survives', async () => {
  for (const inside of [true, false]) {
    const { vault, store, run } = setup(); await run(page([book(), trace()]));
    const path = vault.files()[0];
    vault.beforeProcess = p => vault.data.set(p, inside ? vault.data.get(p)!.replace('原文', '并发手写') : vault.data.get(p)! + '\n并发手写');
    const pending = run(page([trace('trace-a', 'book-a', 'new')], 'cursor-2', 'incremental'));
    if (inside) { await assert.rejects(pending); assert.equal(store.state.sync.cursor, 'cursor-1'); }
    else await pending;
    assert.match(await vault.read(path), /并发手写/);
  }
});
test('invalid/duplicate server IDs are rejected before writes', () => {
  assert.throws(() => page([book(), book()]));
  const invalid = trace(); invalid.data.id = 'different'; assert.throws(() => page([invalid]));
});
test('connection namespace prevents overwriting another account with the same book ID', async () => {
  const { vault, store, run } = setup(); await run(page([book(), trace()]));
  const original = [...vault.data.values()][0];
  store.state = { ...initialState(uuid, store.state.origin), connectionId: '33333333-3333-4333-8333-333333333333' };
  await run(page([book(), trace('trace-a', 'book-a', 'other account')]));
  assert.equal(vault.files().length, 2); assert.ok([...vault.data.values()].includes(original));
});
test('empty snapshot, cancellation and mutex do not perform background writes', async () => {
  const { vault, store } = setup();
  let resolve!: (value: ReturnType<typeof page>) => void;
  const engine = new SyncEngine(store, vault, parse, () => new Promise(r => { resolve = r; }));
  const first = engine.run(); await assert.rejects(engine.run()); engine.cancelled = true; resolve(page([]));
  await assert.rejects(first); assert.equal(vault.files().length, 0); assert.equal(store.writes.length, 0);
  await new SyncEngine(store, vault, parse, async () => page([])).run(); assert.equal(vault.files().length, 0);
});
