const { z } = require('zod');
const api = require('./bookRecapApiContract');
const { fingerprint, validateSnapshot } = require('./bookRecapContract');
const { prepareGeneration, BUDGET } = require('./bookRecapGeneration');
const { assertBookWritable } = require('../repositories/uploadState.repository');

const RESOLVER_VERSION = 'server-reading-records-v1';
const LIMITS = Object.freeze({ maxFollowUps: 320, maxSourceBytes: 262144 });
const object = value => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const text = value => typeof value === 'string' ? value : '';
const date = value => value instanceof Date ? value.toISOString() : null;
const fail = (code = 'RECAP_SOURCE_UNAVAILABLE') => { throw api.recapError(422, code); };

// Inspect markers only. Never traverse another history store or fetch linked notes.
function forbiddenPrivateMaterial(value) {
  if (!value || typeof value !== 'object') return false;
  const pending = [value];
  while (pending.length) {
    for (const [key, item] of Object.entries(pending.pop())) {
      if (['free_note_id', 'freeNoteId', 'free_note', 'free_notes', 'authorized_free_note'].includes(key) ||
          (key === 'origin' && ['free_note', 'free_notes', 'authorized_free_note'].includes(item))) return true;
      if (item && typeof item === 'object') pending.push(item);
    }
  }
  return false;
}

function entryVersion(row) {
  // Include all stored trace fields, including metadata that may change classification.
  // Explicit UTC microseconds avoid pg Date millisecond loss in revision checks.
  const { created_at, updated_at, ...fields } = row;
  return fingerprint([RESOLVER_VERSION, fields]);
}
function dependencyView(d) {
  return { evidenceId: d.evidenceId, entryId: d.entryId, followUpId: d.followUpId ?? null,
    clientEntryId: d.clientEntryId ?? null, sourceField: d.sourceField, kind: d.kind,
    provenance: d.provenance, digest: d.digest, followUpSetDigest: d.followUpSetDigest,
    locator: d.locator ?? {} };
}

// tx must be the owning repository transaction: user lock, then sources, then recap.
// All queries here are bounded reads; revalidation never acquires a reverse-order lock.
function createBookRecapSourceResolver({ origin }) {
  z.url().parse(origin);
  async function resolve(tx, authenticatedUserId, bookId, selection) {
    const userId = api.uuid.parse(authenticatedUserId);
    const parsed = api.prepare.parse({ recap_id: userId, request_id: userId,
      book_id: bookId, selected_sources: selection });
    selection = parsed.selected_sources;
    await assertBookWritable(tx, userId, bookId);
    const args = [userId, bookId, selection.flatMap(s => s.entry_id ? [s.entry_id] : []),
      selection.flatMap(s => s.client_entry_id ? [s.client_entry_id] : [])];
    const where = 'user_id=$1 AND book_id=$2 AND (id=ANY($3::uuid[]) OR client_entry_id=ANY($4::text[]))';
    const size = (await tx(`SELECT count(*)::int AS count,
      COALESCE(sum(octet_length(to_jsonb(e)::text)),0)::text AS bytes FROM user_entries e WHERE ${where}`, args)).rows[0];
    if (size.count !== selection.length) fail();
    if (Number(size.bytes) > LIMITS.maxSourceBytes) fail('RECAP_SCOPE_TOO_LARGE');
    const rows = (await tx(`SELECT e.*,
      to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS created_version,
      to_char(updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS updated_version
      FROM user_entries e WHERE ${where} ORDER BY id`, args)).rows;
    const selected = selection.map(s => rows.filter(r => s.entry_id ? r.id === s.entry_id : r.client_entry_id === s.client_entry_id));
    if (selected.some(r => r.length !== 1) || new Set(selected.map(r => r[0].id)).size !== selection.length) fail();
    const ids = rows.map(r => r.id);
    const followSize = (await tx(`SELECT count(*)::int AS count,
      COALESCE(bool_or(user_id<>$1),false) AS wrong_owner,
      COALESCE(sum(octet_length(to_jsonb(f)::text)) FILTER (WHERE user_id=$1),0)::text AS bytes
      FROM user_entry_follow_ups f WHERE entry_id=ANY($2::uuid[])`, [userId, ids])).rows[0];
    if (followSize.wrong_owner) fail();
    if (followSize.count > LIMITS.maxFollowUps || Number(size.bytes) + Number(followSize.bytes) > LIMITS.maxSourceBytes) {
      fail('RECAP_SCOPE_TOO_LARGE');
    }
    const follows = (await tx(`SELECT f.*,
      to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS created_version
      FROM user_entry_follow_ups f WHERE user_id=$1 AND entry_id=ANY($2::uuid[]) ORDER BY entry_id,id`, [userId, ids])).rows;
    const states = (await tx(`SELECT client_entry_id,book_id,deleted,latest_revision::text,writer_id
      FROM user_entry_upload_states WHERE user_id=$1 AND client_entry_id=ANY($2::text[])`,
    [userId, rows.flatMap(r => r.client_entry_id ? [r.client_entry_id] : [])])).rows;
    const evidence = [], dependencies = [];
    let includedFollowUps = 0;
    for (let i = 0; i < selection.length; i++) {
      const row = selected[i][0], s = selection[i], metadata = object(row.metadata_json);
      if (metadata !== row.metadata_json ||
          !['highlight', 'thought', 'ai_explanation', 'ai_question', 'manual'].includes(row.source) ||
          ![undefined, null, '', 'reader', 'xiaou_asks'].includes(metadata.origin) ||
          forbiddenPrivateMaterial(metadata)) fail();
      const state = states.find(v => v.client_entry_id === row.client_entry_id);
      if (state && (state.deleted || (state.book_id != null && state.book_id !== bookId))) fail();
      const digest = entryVersion(row);
      // Optional expected_digest can veto a mismatch; it never supplies evidence or trust.
      if (s.expected_digest && s.expected_digest !== digest) fail('RECAP_SOURCE_VERSION_MISMATCH');
      const allFollows = follows.filter(f => f.entry_id === row.id);
      const followUpSetDigest = fingerprint([RESOLVER_VERSION, allFollows.map(({ created_at, ...f }) => f)]);
      if (s.follow_up_ids?.some(id => !allFollows.some(f => f.id === id))) fail();
      const chosenFollows = allFollows.filter(f => !s.follow_up_ids || s.follow_up_ids.includes(f.id));
      const anchor = { chapterIndex: row.chapter_index ?? null, chapterTitle: row.chapter_title ?? '',
        documentVersion: null, status: 'fragment_only', start: null, end: null };
      function add(field, kind, value, provenance, location = null, follow = null) {
        if (!text(value).trim()) return;
        const e = { id: 'e-' + fingerprint([row.id, follow?.id ?? null, field]), entryId: row.id,
          followUpId: follow?.id ?? null, sourceField: field, kind, text: value, provenance,
          createdAt: date(follow?.created_at ?? row.created_at), updatedAt: follow ? null : date(row.updated_at),
          anchor: location, pendingUpload: false };
        evidence.push(e);
        if (kind !== 'unverified_excerpt') dependencies.push({
          evidenceId: e.id, entryId: row.id, followUpId: e.followUpId, clientEntryId: row.client_entry_id,
          sourceField: field, kind, provenance, digest, followUpSetDigest,
          revision: state?.latest_revision ?? null, writerId: state?.writer_id ?? null,
          locator: location ? { chapterIndex: location.chapterIndex, documentVersion: null,
            status: 'fragment_only', start: null, end: null } : {},
        });
      }
      const start = dependencies.length;
      const context = object(metadata.reading_ai_context);
      if ((context.bookId != null && context.bookId !== bookId) ||
          (context.book_id != null && context.book_id !== bookId)) fail();
      const field = row.source === 'ai_explanation' || context.scope === 'selection' ? 'selectedText'
        : context.scope === 'page' ? 'pageText' : context.scope === 'chapter' ? 'chapterText' : null;
      const readerContext = metadata.origin !== 'xiaou_asks' &&
        ['ai_question', 'ai_explanation'].includes(row.source) && field && text(context[field]).trim();
      if (metadata.origin === 'xiaou_asks') add('original_text', 'ai_prompt', row.original_text, 'ai_prompt');
      else if (readerContext) add('reading_ai_context.' + field, 'book_excerpt', context[field], 'reader_context', anchor);
      else add('original_text', 'unverified_excerpt', row.original_text, 'legacy_unverified', anchor);
      if (row.source === 'highlight') add('highlight', 'highlight', row.original_text, 'trace');
      add('user_input', row.source === 'ai_question' ? 'user_question' : 'user_note', row.user_input, 'trace');
      add('ai_explanation', 'historical_ai', row.ai_explanation, 'trace');
      for (const follow of chosenFollows) {
        if (!text(follow.question).trim() || !text(follow.answer).trim()) fail('RECAP_INCOMPLETE_SOURCE');
        add('question', 'user_question', follow.question, 'follow_up', null, follow);
        add('answer', 'historical_ai', follow.answer, 'follow_up', null, follow);
        includedFollowUps++;
      }
      // Never silently omit a selected trace that has no transmissible material.
      if (dependencies.length === start) fail('RECAP_INSUFFICIENT_EVIDENCE');
    }
    evidence.sort((a, b) => a.id.localeCompare(b.id));
    dependencies.sort((a, b) => a.evidenceId.localeCompare(b.evidenceId));
    if (dependencies.length > BUDGET.maxEvidence) fail('RECAP_SCOPE_TOO_LARGE');
    const snapshot = { schemaVersion: 1, scope: { userId, origin, bookId },
      // Library/header changes have no invalidation hook: deliberately do not read them.
      book: { title: null, author: null, documentVersion: null }, evidence,
      coverage: { basis: 'reading_traces', fullBook: false, sourceCompleteness: 'server_selected_records',
        availableEntries: rows.length, includedEntries: rows.length, includedFollowUps,
        quarantinedEntries: 0, selectionApplied: true } };
    snapshot.fingerprint = fingerprint(snapshot);
    validateSnapshot(snapshot, snapshot.scope);
    const budget = prepareGeneration(snapshot, snapshot.scope, { model: 'unconfigured' });
    if (budget.status !== 'ready') fail(budget.status === 'scope_too_large' ? 'RECAP_SCOPE_TOO_LARGE' : 'RECAP_INSUFFICIENT_EVIDENCE');
    return { snapshot, dependencies };
  }

  async function revalidate(tx, userId, row, storedDependencies) {
    if (row.user_id !== userId || row.coverage_json?.sourceCompleteness !== 'server_selected_records') {
      throw api.recapError(409, 'RECAP_RESOLVER_VERSION_MISMATCH');
    }
    const material = await resolve(tx, userId, row.book_id, row.selected_sources_json);
    const previous = storedDependencies.map(d => {
      if (d.user_id !== userId || d.book_id !== row.book_id || d.recap_id !== row.id) fail();
      return dependencyView({ evidenceId: d.evidence_id, entryId: d.entry_id, followUpId: d.follow_up_id,
        clientEntryId: d.client_entry_id, sourceField: d.source_field, kind: d.source_kind,
        provenance: d.provenance, digest: d.source_digest, followUpSetDigest: d.follow_up_set_digest,
        locator: d.locator_json });
    }).sort((a, b) => a.evidenceId.localeCompare(b.evidenceId));
    // Upload revision alone can advance on a no-op replay; content and membership decide freshness.
    if (fingerprint(previous) !== fingerprint(material.dependencies.map(dependencyView)) ||
        row.source_fingerprint !== material.snapshot.fingerprint) {
      throw api.recapError(409, 'RECAP_SOURCE_CHANGED');
    }
    return material.snapshot;
  }
  return Object.freeze({ resolve, revalidate });
}
module.exports = { createBookRecapSourceResolver, RESOLVER_VERSION, LIMITS };
