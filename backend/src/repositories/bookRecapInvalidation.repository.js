const { recapError } = require('../services/bookRecapApiContract');

// No deployment pool or feature flag: privacy cleanup must work even with entrances closed.
async function hasRecapSchema(tx) {
  const { rows } = await tx(`SELECT
    to_regclass('reading_recaps') IS NOT NULL AS recaps,
    to_regclass('reading_recap_sources') IS NOT NULL AS sources,
    to_regclass('reading_recap_operations') IS NOT NULL AS operations,
    to_regclass('reading_recap_feedback') IS NOT NULL AS feedback,
    EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('xiaou_conversations')
      AND attname='recap_id' AND NOT attisdropped) AS conversation`);
  const flags = ['recaps', 'sources', 'operations', 'feedback', 'conversation'].map(k => rows[0]?.[k]);
  if (flags.every(v => v === false)) return false;
  if (!flags.every(v => v === true)) throw recapError(503, 'RECAP_SCHEMA_INCOMPLETE');
  return true;
}

// Caller holds the user lock and ALL affected recap locks, in UUID order.
async function clearDerived(tx, userId, ids, state) {
  if (!ids.length) return;
  if (!['stale', 'invalidated', 'deleted'].includes(state)) throw Error('Invalid recap cleanup state');
  await tx(`SELECT request_id FROM reading_recap_operations
    WHERE user_id=$1 AND recap_id=ANY($2::uuid[]) ORDER BY request_id FOR UPDATE`, [userId, ids]);
  await tx(`UPDATE reading_recap_operations SET status='revoked',request_mac=NULL,mac_key_version=NULL,
    result_id=NULL,error_code=NULL,finished_at=now() WHERE user_id=$1 AND recap_id=ANY($2::uuid[])`, [userId, ids]);
  await tx(`SELECT id FROM xiaou_conversations WHERE user_id=$1 AND recap_id=ANY($2::uuid[])
    ORDER BY id FOR UPDATE`, [userId, ids]);
  await tx('DELETE FROM xiaou_conversations WHERE user_id=$1 AND recap_id=ANY($2::uuid[])', [userId, ids]);
  await tx('DELETE FROM reading_recap_feedback WHERE user_id=$1 AND recap_id=ANY($2::uuid[])', [userId, ids]);
  if (state !== 'stale') {
    await tx('DELETE FROM reading_recap_sources WHERE user_id=$1 AND recap_id=ANY($2::uuid[])', [userId, ids]);
  }
  await tx(`UPDATE reading_recaps SET state=$3,result_json=NULL,revision=revision+1,updated_at=now(),
    is_saved=CASE WHEN $3='deleted' THEN false ELSE is_saved END,
    book_id=CASE WHEN $3='stale' THEN book_id ELSE NULL END,
    selected_sources_json=CASE WHEN $3='stale' THEN selected_sources_json ELSE NULL END,
    coverage_json=CASE WHEN $3='stale' THEN coverage_json ELSE NULL END,
    source_fingerprint=CASE WHEN $3='stale' THEN source_fingerprint ELSE NULL END,
    prompt_version=NULL,requested_model=NULL,returned_model=NULL,input_tokens=NULL,output_tokens=NULL,
    elapsed_ms=NULL,cost_amount=NULL,cost_currency=NULL,pricing_version=NULL,expires_at=NULL,
    deleted_at=CASE WHEN $3='deleted' THEN COALESCE(deleted_at,now()) ELSE NULL END
    WHERE user_id=$1 AND id=ANY($2::uuid[])`, [userId, ids, state]);
}

// The ORIGINAL mutation and this hook must share the same transaction/user lock.
// Dependencies include every transmitted evidence item, not just cited result refs.
async function invalidateSource(tx, userId, { entryId, bookId, deleted = false }) {
  if (!entryId && !bookId) throw Error('An exact source identity is required');
  if (!await hasRecapSchema(tx)) return 0;
  const state = deleted ? 'invalidated' : 'stale';
  const result = await tx(`SELECT r.id FROM reading_recaps r
    WHERE r.user_id=$1 AND r.state NOT IN ('deleted','invalidated')
      AND ($4::boolean OR r.state <> 'stale')
      AND (($2::uuid IS NOT NULL AND EXISTS (
        SELECT 1 FROM reading_recap_sources s WHERE s.recap_id=r.id AND s.user_id=r.user_id
          AND s.book_id=r.book_id AND s.entry_id=$2))
        OR ($2::uuid IS NULL AND r.book_id=$3))
    ORDER BY r.id FOR UPDATE OF r`, [userId, entryId ?? null, bookId ?? null, deleted]);
  await clearDerived(tx, userId, result.rows.map(r => r.id), state);
  return result.rowCount;
}

module.exports = { hasRecapSchema, clearDerived, invalidateSource };
