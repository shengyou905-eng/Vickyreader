const test = require('node:test');
const assert = require('node:assert/strict');
const { fingerprint } = require('./bookRecapContract');
const { validateAnswer, prepareFollowUp } = require('./bookRecapFollowUpContract');

function material() {
  const snapshot = { schemaVersion: 1, scope: { userId: 'synthetic-owner', origin: 'https://synthetic.invalid', bookId: 'book-a' },
    book: { title: null, author: null, documentVersion: null },
    evidence: [['selectedText', 'book_excerpt', 'Only A permits B.', 'reader_context'],
      ['user_input', 'user_question', 'Does A guarantee B?', 'trace'],
      ['ai_explanation', 'historical_ai', 'An earlier AI answer.', 'trace']].map(([field, kind, text, provenance]) => ({
      id: `e-${fingerprint(['trace-a', null, field])}`, entryId: 'trace-a', followUpId: null,
      sourceField: field, kind, provenance, text, createdAt: null, updatedAt: null,
      anchor: kind === 'book_excerpt' ? { chapterIndex: null, chapterTitle: '', documentVersion: null,
        status: 'fragment_only', start: null, end: null } : null, pendingUpload: false,
    })), coverage: { basis: 'reading_traces', fullBook: false, sourceCompleteness: 'server_selected_records',
      availableEntries: 1, includedEntries: 1, includedFollowUps: 0, quarantinedEntries: 0, selectionApplied: true } };
  snapshot.fingerprint = fingerprint(snapshot);
  return { snapshot, history: [], row: { result_json: { schemaVersion: 1, snapshotFingerprint: snapshot.fingerprint,
    knowledge: [], myThinking: [], relations: [], openQuestions: [], nextQuestions: [] } } };
}
const completion = { completed: true, finishReason: 'stop' };
function answer(s) {
  return { schemaVersion: 1, snapshotFingerprint: s.fingerprint, parts: [{ text: 'Necessary is not sufficient.',
    basis: 'source_supported', evidenceRefs: [s.evidence[0].id], quotes: [] }] };
}
test('B233 original B1 snapshot and answer references preserved without network', () => {
  const m = material(), a = answer(m.snapshot);
  assert.deepEqual(validateAnswer(a, m.snapshot, completion), a);
  const plan = prepareFollowUp(m, { question: 'Why?' }, { model: 'synthetic' });
  assert.equal(plan.status, 'ready'); assert.equal(plan.request.max_tokens, 3000);
  const s = JSON.parse(plan.request.messages[1].content);
  assert.equal(s.coverage.fullBook, false); assert.equal(s.derivedRecap.kind, 'historical_ai');
  assert.deepEqual(s.evidence.map(e => e.id), m.snapshot.evidence.map(e => e.id));
});
test('B233 quote verification rejects invented voice and text', () => {
  const { snapshot: s } = material(), a = answer(s);
  a.parts[0].quotes = [{ evidenceId: s.evidence[0].id, text: s.evidence[0].text, voice: 'author' }];
  assert.doesNotThrow(() => validateAnswer(a, s, completion));
  a.parts[0].quotes[0].voice = 'user'; assert.throws(() => validateAnswer(a, s, completion));
  a.parts[0].quotes[0].voice = 'author'; a.parts[0].quotes[0].text = 'Invented';
  assert.throws(() => validateAnswer(a, s, completion));
});
for (const kind of ['user_explicit', 'source_supported', 'ai_inference']) test(`B233 ${kind} cannot cite AI alone`, () => {
  const { snapshot: s } = material(), a = answer(s);
  a.parts[0].basis = kind; a.parts[0].evidenceRefs = [s.evidence[2].id];
  assert.throws(() => validateAnswer(a, s, completion));
});
test('B233 user evidence and uncertain inference remain distinct', () => {
  const { snapshot: s } = material(), a = answer(s);
  a.parts[0].basis = 'user_explicit'; a.parts[0].evidenceRefs = [s.evidence[1].id];
  assert.doesNotThrow(() => validateAnswer(a, s, completion));
  a.parts[0].basis = 'ai_inference'; assert.doesNotThrow(() => validateAnswer(a, s, completion));
});
test('B233 incomplete response and unsupported result versions never validate', () => {
  const { snapshot: s } = material(), a = answer(s);
  assert.throws(() => validateAnswer(a, s, { completed: false, finishReason: 'stop' }));
  assert.throws(() => validateAnswer(a, s, { completed: true, finishReason: 'length' }));
  assert.throws(() => validateAnswer({ ...a, schemaVersion: 2 }, s, completion));
  assert.throws(() => validateAnswer({ ...a, snapshotFingerprint: '0'.repeat(64) }, s, completion));
});
test('B233 preserves all 14 turns, role order, original correction and bounds rather than trimming', () => {
  const m = material();
  m.history = Array.from({ length: 14 }, (_, i) => ({ question: `Correction ${i}`, answer: answer(m.snapshot) }));
  const req = prepareFollowUp(m, { question: 'Current' }, { model: 'synthetic' }).request;
  assert.equal(req.messages.length, 31); assert.equal(req.messages[2].content, 'Correction 0');
  assert.deepEqual(req.messages.slice(2, -1).map(v => v.role), Array.from({ length: 14 }, () => ['user', 'assistant']).flat());
  m.history[0].question = 'x'.repeat(16000);
  assert.throws(() => prepareFollowUp(m, { question: 'Current' }, { model: 'synthetic' }), { error_code: 'RECAP_HISTORY_BUDGET' });
  assert.equal(m.history.length, 14);
});
test('B233 maximum turn boundary refuses next round with no partial request', () => {
  const m = material(); m.history = Array.from({ length: 64 }, () => ({ question: '?', answer: answer(m.snapshot) }));
  assert.throws(() => prepareFollowUp(m, { question: '?' }, { model: 'synthetic' }), { error_code: 'RECAP_HISTORY_BUDGET' });
});
