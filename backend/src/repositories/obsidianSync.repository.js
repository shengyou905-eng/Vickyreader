const { withTransaction } = require('../config/db');
const httpError = require('../utils/httpError');
const { signCursor, readCursor } = require('../services/obsidianProtocol.service');

// These are export DTOs, not SELECT * business rows. Never include arbitrary
// metadata, credentials, file/cover paths, free notes, or chat/follow-up tables.
const currentEntities = `
  traces AS (
    SELECT * FROM user_entries WHERE user_id=$1
      AND source IN ('highlight','thought','ai_explanation','ai_question')
      AND NULLIF(btrim(book_id), '') IS NOT NULL
  ),
  book_ids AS (
    SELECT book_id FROM user_library_books WHERE user_id=$1
    UNION SELECT book_id FROM traces
    UNION SELECT book_id FROM reading_progresses WHERE user_id=$1
  ),
  trace_titles AS (
    SELECT DISTINCT ON (book_id) book_id, book_title FROM traces
    WHERE NULLIF(btrim(book_title), '') IS NOT NULL
    ORDER BY book_id, updated_at DESC, id DESC
  ),
  current_entities AS (
    SELECT 'book'::text AS entity_type, ids.book_id AS entity_id,
      jsonb_build_object('book_id',ids.book_id,'title',COALESCE(NULLIF(b.title,''),t.book_title),
        'author',NULLIF(b.author,''),'format',NULLIF(b.format,''),
        'in_library',b.book_id IS NOT NULL,'added_at',b.added_at,
        'last_opened_at',b.last_opened_at,'created_at',b.created_at,'updated_at',b.updated_at) AS data
    FROM book_ids ids
    LEFT JOIN user_library_books b ON b.user_id=$1 AND b.book_id=ids.book_id
    LEFT JOIN trace_titles t ON t.book_id=ids.book_id
    UNION ALL
    SELECT 'reading_progress',p.id::text,
      jsonb_build_object('id',p.id,'book_id',p.book_id,'progress',p.progress,
        'chapter_index',p.chapter_index,'scroll_offset',p.scroll_offset,'cfi',p.cfi,
        'created_at',p.created_at,'updated_at',p.updated_at)
    FROM reading_progresses p WHERE p.user_id=$1
    UNION ALL
    SELECT 'trace',t.id::text,
      jsonb_build_object('id',t.id,'type',t.source,'book_id',t.book_id,'book_title',t.book_title,
        'chapter_index',t.chapter_index,'chapter_title',t.chapter_title,
        'excerpt',t.original_text,'note',t.user_input,'explanation',t.ai_explanation,
        'tags',t.auto_tags,'is_important',t.is_important,
        'created_at',t.created_at,'updated_at',t.updated_at)
    FROM traces t
  )`;

async function assertGrant(tx, grant) {
  const result = await tx(`SELECT g.id FROM obsidian_grants g JOIN users u ON u.id=g.user_id
    WHERE g.id=$1 AND g.user_id=$2 AND g.revoked_at IS NULL AND g.expires_at>now()
      AND g.scope='obsidian.sync.read' AND u.account_status='active' FOR SHARE OF g`,
  [grant.id, grant.user_id]);
  if (!result.rowCount) throw httpError(401, 'invalid_token');
}

async function materialize(tx, grant, after) {
  // Separate advisory namespace: export work never takes the upload cursor lock.
  const lock = await tx(`SELECT pg_try_advisory_xact_lock(73421, hashtext($1)) AS acquired`, [grant.user_id]);
  if (!lock.rows[0].acquired) throw httpError(409, 'sync_busy');
  await tx(`DELETE FROM obsidian_sync_snapshots s USING obsidian_grants g
    WHERE s.grant_id=g.id AND g.user_id=$1 AND s.expires_at<=now()`, [grant.user_id]);
  // A lost first-page response must not allocate another export on every retry.
  const cached = (await tx(`SELECT id,phase,watermark::text,expires_at FROM obsidian_sync_snapshots
    WHERE grant_id=$1 AND after_sequence IS NOT DISTINCT FROM $2::bigint AND expires_at>now()
    ORDER BY created_at DESC LIMIT 1`, [grant.id, after])).rows[0];
  if (cached) return cached;
  const count = await tx(`SELECT count(*)::int AS n FROM obsidian_sync_snapshots s
    JOIN obsidian_grants g ON g.id=s.grant_id WHERE g.user_id=$1 AND s.completed_at IS NULL`, [grant.user_id]);
  if (count.rows[0].n >= 3) throw httpError(429, 'too_many_snapshots');

  const watermarkResult = await tx(`SELECT COALESCE(
    (SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1),0)::text AS watermark`, [grant.user_id]);
  const watermark = watermarkResult.rows[0].watermark;
  if (after !== null && BigInt(after) > BigInt(watermark)) throw httpError(409, 'resync_required');
  const phase = after === null ? 'snapshot' : 'incremental';
  const snapshot = (await tx(`INSERT INTO obsidian_sync_snapshots (grant_id, phase, watermark, after_sequence)
    VALUES ($1,$2,$3,$4) RETURNING id, phase, watermark::text, expires_at`, [grant.id, phase, watermark, after])).rows[0];

  const selection = after === null
    ? `SELECT entity_type, entity_id, 'created'::text AS operation, NULL::text AS sequence, data
       FROM current_entities`
    : `SELECT l.entity_type, l.entity_id,
         CASE WHEN c.data IS NULL THEN 'deleted'
              WHEN l.operation='created' THEN 'created' ELSE 'updated' END AS operation,
         l.user_sequence::text AS sequence, c.data
       FROM latest l LEFT JOIN current_entities c
         ON c.entity_type=l.entity_type AND c.entity_id=l.entity_id`;
  // Fold events to final state at the same MVCC watermark. We cannot reconstruct
  // historical payloads from an index-only ledger and must not pretend to do so.
  const latest = after === null ? '' : `latest AS (
    SELECT DISTINCT ON (entity_type,entity_id) entity_type, entity_id, operation, user_sequence
    FROM sync_changes WHERE user_id=$1 AND user_sequence>$4::bigint AND user_sequence<=$3::bigint
    ORDER BY entity_type,entity_id,user_sequence DESC
  ),`;
  await tx(`WITH ${latest} ${currentEntities}, selected AS (${selection}), bounded AS (
    SELECT * FROM selected ORDER BY entity_type,entity_id LIMIT 50001
  ) INSERT INTO obsidian_sync_snapshot_items (snapshot_id,ordinal,change)
    SELECT $2, row_number() OVER (ORDER BY entity_type,entity_id),
      jsonb_build_object('entity_type',entity_type,'entity_id',entity_id,
        'operation',operation,'sequence',sequence,'version',$3::text,'data',data)
    FROM bounded`, after === null
    ? [grant.user_id, snapshot.id, watermark]
    : [grant.user_id, snapshot.id, watermark, after]);
  const size = (await tx(`SELECT count(*)::int AS n, COALESCE(sum(octet_length(change::text)),0)::bigint AS bytes
    FROM obsidian_sync_snapshot_items WHERE snapshot_id=$1`, [snapshot.id])).rows[0];
  if (size.n > 50000 || BigInt(size.bytes) > 32n * 1024n * 1024n) throw httpError(413, 'export_too_large');
  const cachedBytes = (await tx(`SELECT COALESCE(sum(octet_length(i.change::text)),0)::bigint AS bytes
    FROM obsidian_sync_snapshot_items i JOIN obsidian_sync_snapshots s ON s.id=i.snapshot_id
    JOIN obsidian_grants g ON g.id=s.grant_id WHERE g.user_id=$1`, [grant.user_id])).rows[0].bytes;
  if (BigInt(cachedBytes) > 64n * 1024n * 1024n) throw httpError(429, 'export_cache_full');
  return snapshot;
}

async function sync(grant, { cursor, limit }, secret) {
  const position = cursor ? readCursor(cursor, grant.id, secret) : null;
  return withTransaction(async tx => {
    await tx('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
    await tx("SET LOCAL statement_timeout = '15s'");
    await assertGrant(tx, grant);
    let snapshot;
    let afterOrdinal = '0';
    if (position?.mode === 'page') {
      snapshot = (await tx(`SELECT id,phase,watermark::text,expires_at FROM obsidian_sync_snapshots
        WHERE id=$1 AND grant_id=$2 AND expires_at>now()`, [position.snapshot, grant.id])).rows[0];
      if (!snapshot) throw httpError(410, 'snapshot_expired');
      afterOrdinal = position.after;
    } else {
      snapshot = await materialize(tx, grant, position?.after ?? null);
    }
    const rows = (await tx(`SELECT ordinal::text,change FROM obsidian_sync_snapshot_items
      WHERE snapshot_id=$1 AND ordinal>$2::bigint ORDER BY ordinal LIMIT $3`,
    [snapshot.id, afterOrdinal, limit + 1])).rows;
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    const next = hasMore
      ? { v: 1, grant: grant.id, mode: 'page', snapshot: snapshot.id, after: page.at(-1).ordinal }
      : { v: 1, grant: grant.id, mode: 'delta', after: snapshot.watermark };
    // Completed pages remain replayable until TTL; empty polls need no cache.
    if (!rows.length && position?.mode !== 'page') {
      await tx('DELETE FROM obsidian_sync_snapshots WHERE id=$1', [snapshot.id]);
    } else if (!hasMore) {
      await tx('UPDATE obsidian_sync_snapshots SET completed_at=COALESCE(completed_at,now()) WHERE id=$1', [snapshot.id]);
    }
    return { schema_version: 1, phase: snapshot.phase, watermark: snapshot.watermark,
      next_cursor: signCursor(next, secret), has_more: hasMore,
      changes: page.map(row => row.change) };
  });
}

async function cleanupExpired() {
  return withTransaction(async tx => {
    await tx('DELETE FROM obsidian_sync_snapshots WHERE expires_at<=now()');
    await tx('DELETE FROM obsidian_authorization_codes WHERE expires_at<=now()');
  });
}

module.exports = { sync, cleanupExpired };
