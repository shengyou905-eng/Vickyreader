const { test } = require('node:test');
const assert = require('node:assert/strict');
const dto = require('./bookRecapDisplayContract');
const { createBookRecapDisplayService } = require('./bookRecapDisplay.service');
const version = { book_id: 'book', expected_revision: '1', expected_source_fingerprint: 'a'.repeat(64) };

test('display strict selection rejects trusted snapshot, owner and client completion fields', () => {
  for (const key of ['userId','user_id','snapshot','result','metadata','local_pending_verified','display']) {
    assert.equal(dto.versionRequest.safeParse({ ...version, [key]: true }).success, false);
  }
  assert.deepEqual(dto.versionRequest.parse(version), version);
});
test('history bounded pagination and strict filters', () => {
  assert.deepEqual(dto.historyRequest.parse({}), { limit: 20, filter: 'all' });
  for (const value of [{ limit: 0 }, { limit: 51 }, { limit: 1.5 }, { filter: 'body' }, { cursor: 'x'.repeat(2049) }, { book_id: 'x' }]) {
    assert.equal(dto.historyRequest.safeParse(value).success, false);
  }
});
test('evidence request denies duplicate, empty, malformed and excessive IDs', () => {
  const id = 'e-' + 'b'.repeat(64);
  assert(dto.evidenceRequest.safeParse({ ...version, evidence_ids: [id] }).success);
  for (const evidence_ids of [[], [id,id], ['guessed'], Array.from({ length: 25 }, (_,i) => 'e-' + i.toString(16).padStart(64,'0'))]) {
    assert(!dto.evidenceRequest.safeParse({ ...version, evidence_ids }).success);
  }
});
test('policy has no implicit production window or unbounded lifetime', () => {
  for (const value of [{}, { version: 'p' }, { version:'p',windowMs:0 }, { version:'p',windowMs:120001 }]) {
    assert(!dto.policy.safeParse(value).success);
  }
  assert(dto.policy.safeParse({ version:'test-only',windowMs:2000 }).success);
});
test('source display cannot elevate provenance or expose raw metadata and exact anchors', () => {
  const item = { id:'e-'+'b'.repeat(64),entry_id:'00000000-0000-4000-8000-000000000001',follow_up_id:null,
    kind:'book_excerpt',provenance:'reader_context',text:'Synthetic text',
    location:{status:'fragment_only',exact:false,chapter_index:null,chapter_title:''} };
  assert(dto.evidenceItem.safeParse(item).success);
  for (const value of [{ ...item,provenance:'current_document' }, { ...item,metadata_json:{} },
    { ...item,location:{...item.location,exact:true} }, { ...item,location:{...item.location,start:0} }]) {
    assert(!dto.evidenceItem.safeParse(value).success);
  }
});
test('service requires explicit cursor key and lifetime, never loads deployment credentials', () => {
  assert.throws(() => createBookRecapDisplayService({}));
  assert.throws(() => createBookRecapDisplayService({ repository:{},authorize:()=>{},cursorKey:Buffer.alloc(32) }));
});
