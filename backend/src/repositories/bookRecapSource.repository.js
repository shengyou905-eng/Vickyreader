const { assertBookWritable } = require('./uploadState.repository');
const { recapError } = require('../services/bookRecapApiContract');

// Identity/lock boundary ONLY. This does not certify text provenance or construct model inputs.
async function lockSelection(tx, userId, bookId, selection) {
  await assertBookWritable(tx, userId, bookId);
  const entries = (await tx(`SELECT id,user_id,book_id,client_entry_id FROM user_entries WHERE user_id=$1 AND book_id=$2
    AND (id=ANY($3::uuid[]) OR client_entry_id=ANY($4::text[])) ORDER BY id FOR UPDATE`,
  [userId, bookId, selection.flatMap(s => s.entry_id ? [s.entry_id] : []),
    selection.flatMap(s => s.client_entry_id ? [s.client_entry_id] : [])])).rows;
  const mapped = selection.map(s => entries.find(e => s.entry_id ? e.id === s.entry_id : e.client_entry_id === s.client_entry_id));
  if (mapped.some(e => !e) || new Set(mapped.map(e => e.id)).size !== selection.length) {
    throw recapError(422, 'RECAP_SOURCE_UNAVAILABLE');
  }
  const followUps = (await tx(`SELECT id,user_id,entry_id FROM user_entry_follow_ups WHERE user_id=$1
    AND entry_id=ANY($2::uuid[]) ORDER BY entry_id,id LIMIT 321 FOR UPDATE`, [userId, entries.map(e => e.id)])).rows;
  if (followUps.length > 320) throw recapError(422, 'RECAP_SCOPE_TOO_LARGE');
  for (let i = 0; i < selection.length; i++) {
    if (selection[i].follow_up_ids?.some(id => !followUps.some(f => f.id === id && f.entry_id === mapped[i].id))) {
      throw recapError(422, 'RECAP_SOURCE_UNAVAILABLE');
    }
  }
  return { entries: mapped, followUps, selection };
}

function validateDependencyOwners(deps, scope) {
  for (const dep of deps) {
    const index = scope.entries.findIndex(e => e.id === dep.entryId);
    if (index < 0 || (dep.clientEntryId != null && dep.clientEntryId !== scope.entries[index].client_entry_id) ||
        (dep.followUpId && (!scope.followUps.some(f => f.id === dep.followUpId && f.entry_id === dep.entryId) ||
          (scope.selection[index].follow_up_ids && !scope.selection[index].follow_up_ids.includes(dep.followUpId))))) {
      throw recapError(422, 'RECAP_SOURCE_UNAVAILABLE');
    }
  }
}

async function lockRecapSources(tx, userId, id) {
  const rows = (await tx(`SELECT e.id FROM user_entries e WHERE e.user_id=$1 AND EXISTS (
    SELECT 1 FROM reading_recap_sources s WHERE s.user_id=$1 AND s.recap_id=$2
      AND s.entry_id=e.id AND s.book_id=e.book_id) ORDER BY e.id FOR UPDATE OF e`, [userId, id])).rows;
  await tx(`SELECT id FROM user_entry_follow_ups WHERE user_id=$1 AND entry_id=ANY($2::uuid[])
    ORDER BY entry_id,id FOR UPDATE`, [userId, rows.map(r => r.id)]);
}
module.exports = { lockSelection, validateDependencyOwners, lockRecapSources };
