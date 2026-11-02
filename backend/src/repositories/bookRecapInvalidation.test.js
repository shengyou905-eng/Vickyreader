const test = require('node:test');
const assert = require('node:assert/strict');
const { hasRecapSchema, clearDerived } = require('./bookRecapInvalidation.repository');
const { validateDependencyOwners } = require('./bookRecapSource.repository');

test('recap hooks skip wholly absent legacy schema, never a partial or unknown schema', async () => {
  const keys = ['recaps', 'sources', 'operations', 'feedback', 'conversation'];
  const probe = flags => async () => ({ rows: [Object.fromEntries(keys.map((k, i) => [k, flags[i]]))] });
  assert.equal(await hasRecapSchema(probe(keys.map(() => false))), false);
  assert.equal(await hasRecapSchema(probe(keys.map(() => true))), true);
  for (let mask = 1; mask < 31; mask++) {
    await assert.rejects(hasRecapSchema(probe(keys.map((_, i) => Boolean(mask & (1 << i))))),
      { error_code: 'RECAP_SCHEMA_INCOMPLETE' });
  }
  await assert.rejects(hasRecapSchema(probe([])), { error_code: 'RECAP_SCHEMA_INCOMPLETE' });
});
test('cleanup locks operations before dedicated conversations and does not emit sync events', async () => {
  const calls = [];
  await clearDerived(async sql => { calls.push(sql); return { rows: [] }; }, 'user', ['recap'], 'invalidated');
  assert.match(calls[0], /reading_recap_operations[\s\S]*FOR UPDATE/);
  assert.match(calls[2], /xiaou_conversations[\s\S]*FOR UPDATE/);
  assert(!calls.some(s => /sync_changes|UPDATE user_entries|DELETE FROM user_entries/.test(s)));
  assert(calls.some(s => /DELETE FROM reading_recap_sources/.test(s)));
  calls.length = 0;
  await clearDerived(async sql => { calls.push(sql); }, 'user', ['recap'], 'stale');
  assert(!calls.some(s => /DELETE FROM reading_recap_sources/.test(s)));
});
test('dependency owner mapping rejects forged remote/client IDs and unselected follow-ups', () => {
  const scope = { entries: [{ id: 'remote', client_entry_id: 'local' }],
    followUps: [{ id: 'follow', entry_id: 'remote' }], selection: [{ follow_up_ids: [] }] };
  validateDependencyOwners([{ entryId: 'remote', clientEntryId: 'local' }], scope);
  for (const d of [{ entryId: 'wrong' }, { entryId: 'remote', clientEntryId: 'wrong' },
    { entryId: 'remote', followUpId: 'follow' }, { entryId: 'remote', followUpId: 'unknown' }]) {
    assert.throws(() => validateDependencyOwners([d], scope), { error_code: 'RECAP_SOURCE_UNAVAILABLE' });
  }
  scope.selection = [{}];
  validateDependencyOwners([{ entryId: 'remote', followUpId: 'follow' }], scope);
});
