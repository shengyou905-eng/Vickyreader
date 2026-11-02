const { createHash } = require('node:crypto');
const { z } = require('zod');
const { verifyDirectQuotes } = require('./readingInterpretation');

const SCHEMA_VERSION = 1;
const id = z.string().min(1).max(256);
const hash = z.string().regex(/^[a-f0-9]{64}$/u);
const text = z.string().trim().min(1).max(3000);
const kinds = ['book_excerpt', 'highlight', 'user_note', 'user_question',
  'historical_ai', 'ai_prompt', 'unverified_excerpt'];
const anchor = z.strictObject({
  chapterIndex: z.string().max(100).nullable(),
  chapterTitle: z.string().max(1000),
  documentVersion: z.string().max(256).nullable(),
  status: z.enum(['fragment_only', 'exact', 'ambiguous', 'changed', 'unavailable']),
  start: z.number().int().nonnegative().nullable(),
  end: z.number().int().positive().nullable(),
});
const evidence = z.strictObject({
  id, entryId: id, followUpId: id.nullable(),
  kind: z.enum(kinds), text: z.string().min(1).max(100000),
  sourceField: z.string().min(1).max(128),
  provenance: z.enum(['reader_context', 'business_record', 'current_document', 'legacy_unverified',
    'trace', 'follow_up', 'ai_prompt']),
  createdAt: z.iso.datetime().nullable(), updatedAt: z.iso.datetime().nullable(),
  anchor: anchor.nullable(), pendingUpload: z.boolean(),
});
const scope = z.strictObject({ userId: id, origin: z.url(), bookId: id });
const snapshotSchema = z.strictObject({
  schemaVersion: z.literal(SCHEMA_VERSION), scope,
  book: z.strictObject({
    title: z.string().max(1000).nullable(), author: z.string().max(1000).nullable(),
    documentVersion: z.string().max(256).nullable(),
  }),
  evidence: z.array(evidence).max(20000),
  coverage: z.strictObject({
    basis: z.literal('reading_traces'), fullBook: z.literal(false),
    // Coverage vocabulary, NOT proof of book-text authenticity or authorization.
    sourceCompleteness: z.enum(['local_and_supplied_cache', 'server_selected_records']),
    availableEntries: z.number().int().nonnegative(),
    includedEntries: z.number().int().nonnegative(),
    includedFollowUps: z.number().int().nonnegative(),
    quarantinedEntries: z.number().int().nonnegative(),
    selectionApplied: z.boolean(),
  }),
  fingerprint: hash,
});
const refs = z.array(id).min(1).max(24).refine(v => new Set(v).size === v.length);
const basis = z.enum(['source_supported', 'user_explicit', 'ai_inference']);
const quote = z.strictObject({
  evidenceId: id, text: z.string().min(1).max(2000),
  voice: z.enum(['author', 'user', 'historical_ai']),
});
const claim = z.strictObject({
  id, title: text, summary: text, basis, evidenceRefs: refs,
  quotes: z.array(quote).max(8),
});
const resultSchema = z.strictObject({
  schemaVersion: z.literal(SCHEMA_VERSION),
  snapshotFingerprint: hash,
  knowledge: z.array(claim.extend({
    kind: z.enum(['concept', 'viewpoint', 'argument']),
  })).max(12),
  relations: z.array(z.strictObject({
    id, from: id, to: id,
    type: z.enum(['supports', 'conflicts', 'complements', 'compares', 'unconfirmed']),
    explanation: text, basis, evidenceRefs: refs,
  })).max(16),
  myThinking: z.array(claim).max(12),
  openQuestions: z.array(claim).max(12),
  nextQuestions: z.array(claim).max(3),
});

function fail(code) {
  throw Object.assign(new Error(code), { code });
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  }
  return value;
}
function fingerprint(value) {
  return createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
}

// A checksum detects stale/mixed snapshots, not ownership or authenticity.
// trustedScope must come from the authenticated session, never the request body.
function validateSnapshot(input, trustedScope) {
  const parsed = snapshotSchema.parse(input);
  const expected = scope.parse(trustedScope);
  if (fingerprint(parsed.scope) !== fingerprint(expected)) fail('RECAP_SCOPE_MISMATCH');
  const { fingerprint: digest, ...body } = parsed;
  if (fingerprint(body) !== digest) fail('RECAP_SNAPSHOT_CHANGED');
  const ids = new Set();
  const entries = new Set();
  const follows = new Set();
  for (const e of parsed.evidence) {
    if (ids.has(e.id)) fail('RECAP_DUPLICATE_EVIDENCE');
    ids.add(e.id); entries.add(e.entryId);
    if (e.followUpId) follows.add(e.followUpId);
    if (e.id !== `e-${fingerprint([e.entryId, e.followUpId, e.sourceField])}`) {
      fail('RECAP_IDENTITY_MISMATCH');
    }
    if (e.kind === 'book_excerpt') {
      if (!['reader_context', 'business_record', 'current_document'].includes(e.provenance) ||
          !e.anchor || e.anchor.status === 'changed') fail('RECAP_UNVERIFIED_SOURCE');
      if (e.provenance === 'current_document' && e.anchor.status !== 'exact') {
        fail('RECAP_UNVERIFIED_SOURCE');
      }
    }
    if (e.anchor?.status === 'exact' &&
        (e.anchor.start == null || e.anchor.end == null ||
         e.anchor.end - e.anchor.start !== e.text.length ||
         !e.anchor.documentVersion || e.anchor.chapterIndex == null)) {
      fail('RECAP_INVALID_ANCHOR');
    }
    if (e.anchor && e.anchor.status !== 'exact' &&
        (e.anchor.start !== null || e.anchor.end !== null)) fail('RECAP_INVALID_ANCHOR');
    if (e.followUpId && !['user_question', 'historical_ai'].includes(e.kind)) {
      fail('RECAP_INVALID_FOLLOW_UP');
    }
  }
  const c = parsed.coverage;
  if (entries.size > c.includedEntries || follows.size > c.includedFollowUps ||
      c.includedEntries > c.availableEntries ||
      (!c.selectionApplied && c.includedEntries !== c.availableEntries)) {
    fail('RECAP_INVALID_COVERAGE');
  }
  return parsed;
}

function validateResult(input, snapshot, trustedScope, { finishReason, completed } = {}) {
  const source = validateSnapshot(snapshot, trustedScope);
  if (finishReason !== 'stop' || completed !== true) fail('RECAP_INCOMPLETE');
  const result = resultSchema.parse(input);
  if (result.snapshotFingerprint !== source.fingerprint) fail('RECAP_SNAPSHOT_CHANGED');
  const byId = new Map(source.evidence.map(e => [e.id, e]));
  const seen = new Set();
  const knowledgeIds = new Set(result.knowledge.map(c => c.id));
  function check(item, section) {
    if (seen.has(item.id)) fail('RECAP_DUPLICATE_RESULT_ID');
    seen.add(item.id);
    const sources = item.evidenceRefs.map(ref => {
      const e = byId.get(ref);
      if (!e || e.kind === 'unverified_excerpt') fail('RECAP_INVALID_REFERENCE');
      return e;
    });
    const hasBook = sources.some(e => e.kind === 'book_excerpt');
    const hasUser = sources.some(e => ['user_note', 'user_question'].includes(e.kind));
    if (item.basis === 'source_supported' && !hasBook) fail('RECAP_MISSING_BOOK_EVIDENCE');
    if (item.basis === 'user_explicit' && !hasUser) fail('RECAP_MISSING_USER_EVIDENCE');
    if (['knowledge', 'relations'].includes(section) &&
        (!hasBook || item.basis === 'user_explicit')) fail('RECAP_MISSING_BOOK_EVIDENCE');
    if (['myThinking', 'openQuestions'].includes(section) &&
        (!hasUser || item.basis === 'source_supported')) fail('RECAP_MISSING_USER_EVIDENCE');
    if (section === 'nextQuestions' &&
        (item.basis !== 'ai_inference' || (!hasBook && !hasUser))) fail('RECAP_INVALID_SUGGESTION');
    verifyDirectQuotes([item.title, item.summary, item.explanation].filter(Boolean).join('\n'), {
      segments: sources.filter(e => e.kind === 'book_excerpt').map(e => ({ text: e.text })),
    });
    for (const q of item.quotes || []) {
      const e = byId.get(q.evidenceId);
      if (!item.evidenceRefs.includes(q.evidenceId) || !e?.text.includes(q.text)) {
        fail('RECAP_QUOTE_MISMATCH');
      }
      const voice = e.kind === 'book_excerpt' ? 'author'
        : ['user_note', 'user_question'].includes(e.kind) ? 'user'
          : e.kind === 'historical_ai' ? 'historical_ai' : null;
      if (voice !== q.voice) fail('RECAP_QUOTE_VOICE_MISMATCH');
    }
  }
  for (const section of ['knowledge', 'myThinking', 'openQuestions', 'nextQuestions']) {
    for (const item of result[section]) check(item, section);
  }
  for (const item of result.relations) {
    check(item, 'relations');
    if (item.from === item.to || !knowledgeIds.has(item.from) || !knowledgeIds.has(item.to)) {
      fail('RECAP_INVALID_RELATION');
    }
    const endpoints = result.knowledge.filter(k => k.id === item.from || k.id === item.to);
    if (endpoints.some(k => !k.evidenceRefs.some(ref => item.evidenceRefs.includes(ref)))) {
      fail('RECAP_RELATION_MISSING_ENDPOINT_EVIDENCE');
    }
  }
  // This validates referential integrity, not semantic entailment.
  return result;
}

function assessFreshness(previous, current, trustedScope) {
  const old = validateSnapshot(previous, trustedScope);
  const next = validateSnapshot(current, trustedScope);
  if (old.fingerprint === next.fingerprint) return { state: 'current', displayAllowed: true };
  const withoutLocation = value => {
    const copy = structuredClone(value);
    delete copy.fingerprint;
    copy.book.documentVersion = null;
    for (const e of copy.evidence) {
      if (e.anchor) {
        e.anchor.documentVersion = null;
        e.anchor.status = 'fragment_only';
        e.anchor.start = null; e.anchor.end = null;
      }
    }
    return copy;
  };
  if (old.book.documentVersion && next.book.documentVersion === null &&
      fingerprint(withoutLocation(old)) === fingerprint(withoutLocation(next))) {
    // Only location availability changed. Recorded sources are still present,
    // owned and byte-identical; this is not a deletion or a new edition.
    return { state: 'location_unavailable', displayAllowed: true };
  }
  const ids = new Set(next.evidence.map(e => e.id));
  return {
    state: old.evidence.some(e => !ids.has(e.id)) ? 'source_unavailable' : 'stale',
    displayAllowed: false,
  };
}

module.exports = {
  SCHEMA_VERSION, snapshotSchema, resultSchema, fingerprint,
  validateSnapshot, validateResult, assessFreshness,
};
