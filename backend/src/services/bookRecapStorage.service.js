const { createHmac } = require('node:crypto');
const { z } = require('zod');
const api = require('./bookRecapApiContract');
const { validateSnapshot, validateResult, fingerprint } = require('./bookRecapContract');
const { PROMPT_VERSION, prepareGeneration } = require('./bookRecapGeneration');
const { bookRecapConfig } = require('../config/bookRecap');
const follow = require('./bookRecapFollowUpContract');
const { lockSelection, validateDependencyOwners } = require('../repositories/bookRecapSource.repository');

const dependency = z.strictObject({
  evidenceId: z.string().min(1).max(256), entryId: api.uuid,
  followUpId: api.uuid.nullable().optional(), clientEntryId: z.string().max(256).nullable().optional(),
  sourceField: z.string().min(1).max(128),
  kind: z.enum(['book_excerpt', 'highlight', 'user_note', 'user_question', 'historical_ai', 'ai_prompt']),
  provenance: z.enum(['reader_context', 'business_record', 'current_document', 'trace', 'follow_up', 'ai_prompt']),
  digest: z.string().regex(/^[a-f0-9]{64}$/u), followUpSetDigest: z.string().regex(/^[a-f0-9]{64}$/u),
  revision: z.string().regex(/^[0-9]+$/u).nullable().optional(), writerId: api.uuid.nullable().optional(),
  locator: z.strictObject({
    chapterIndex: z.string().max(100).nullable().optional(),
    documentVersion: z.string().max(256).nullable().optional(),
    status: z.enum(['fragment_only','exact','ambiguous','changed','unavailable']).optional(),
    start: z.number().int().nonnegative().nullable().optional(),
    end: z.number().int().positive().nullable().optional(),
  }).optional(),
});

// No provider/network calls may run inside these transactions.
// The resolver is a server-owned dependency, never selected from request input.
function createBookRecapStorage({
  repository: repo, resolver, macKey, keyVersion = 'synthetic-v1',
  origin, config = bookRecapConfig(), clock = () => new Date(),
}) {
  function available() {
    if (!resolver?.resolve || !resolver?.revalidate || !Buffer.isBuffer(macKey) || macKey.length < 32) {
      throw api.recapError(503, 'RECAP_FOUNDATION_NOT_CONFIGURED');
    }
  }
  function mac(operation, id, body) {
    return createHmac('sha256', macKey).update(fingerprint([operation, id, body])).digest('hex');
  }
  const expiry = seconds => new Date(clock().getTime() + seconds * 1000);
  function scope(userId, bookId) { return { userId, origin, bookId }; }
  function live(row) {
    if (row.state === 'stale') throw api.recapError(409, 'RECAP_SOURCE_CHANGED');
    if (['deleted', 'invalidated', 'expired'].includes(row.state)) throw api.recapError(410, 'RECAP_UNAVAILABLE');
    if (!row.is_saved && row.expires_at && row.expires_at <= clock()) throw api.recapError(410, 'RECAP_EXPIRED');
  }
  function revision(row, expected) {
    if (row.revision !== expected) throw api.recapError(412, 'RECAP_REVISION_CONFLICT');
  }
  async function current(tx, userId, row) {
    available();
    live(row);
    if (row.schema_version !== 1) throw api.recapError(409, 'RECAP_VERSION_UNSUPPORTED');
    const deps = await repo.dependencies(tx, userId, row.id);
    const snapshot = validateSnapshot(
      await resolver.revalidate(tx, userId, row, deps), scope(userId, row.book_id));
    if (snapshot.fingerprint !== row.source_fingerprint) throw api.recapError(409, 'RECAP_SOURCE_CHANGED');
    return snapshot;
  }
  async function prepare(user, input) {
    available();
    const userId = api.uuid.parse(user);
    const body = api.prepare.parse(input);
    const digest = mac('prepare', body.recap_id, body);
    return repo.transaction(userId, async tx => {
      const replay = await repo.replay(tx, userId, body.request_id, 'prepare', body.recap_id, digest);
      if (replay) {
        const row = await repo.find(tx, userId, body.recap_id);
        await current(tx, userId, row);
        return row;
      }
      const identities = await lockSelection(tx, userId, body.book_id, body.selected_sources);
      const material = await resolver.resolve(tx, userId, body.book_id, body.selected_sources);
      const snapshot = validateSnapshot(material.snapshot, scope(userId, body.book_id));
      const deps = z.array(dependency).min(1).max(320).parse(material.dependencies);
      const sent = snapshot.evidence.filter(e => e.kind !== 'unverified_excerpt');
      if (new Set(deps.map(d => d.evidenceId)).size !== deps.length || deps.length !== sent.length ||
          sent.some(e => !deps.some(d => d.evidenceId === e.id && d.entryId === e.entryId &&
            (d.followUpId ?? null) === (e.followUpId ?? null) && d.sourceField === e.sourceField &&
            d.kind === e.kind && d.provenance === e.provenance))) {
        throw api.recapError(422, 'RECAP_DEPENDENCIES_INCOMPLETE');
      }
      validateDependencyOwners(deps, identities);
      // This prepares a request for budget checks; it never sends it.
      const budget = prepareGeneration(snapshot, scope(userId, body.book_id), { model: 'unconfigured' });
      if (budget.status !== 'ready') throw api.recapError(422, 'RECAP_SCOPE_NOT_READY');
      const row = await repo.insertPrepared(tx, userId, body.recap_id, {
        bookId: body.book_id, fingerprint: snapshot.fingerprint, selection: body.selected_sources,
        coverage: snapshot.coverage, promptVersion: PROMPT_VERSION, dependencies: deps,
      }, expiry(config.preparedSeconds));
      await repo.record(tx, { userId, requestId: body.request_id, id: row.id, operation: 'prepare',
        mac: digest, keyVersion, revision: row.revision, deadline: row.expires_at, status: 'succeeded' });
      return row;
    });
  }
  async function begin(user, idValue, input, { authorize } = {}) {
    available();
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue), body = api.generate.parse(input);
    return repo.transaction(userId, async tx => {
      if (authorize) await authorize(tx, userId);
      let row = await repo.find(tx, userId, id);
      await current(tx, userId, row);
      const digest = mac('generate', id, body);
      const replay = await repo.replay(tx, userId, body.request_id, 'generate', id, digest);
      if (replay) return { ...replay, executionClaimed: false };
      revision(row, body.expected_revision);
      if (row.state !== 'prepared') throw api.recapError(409, 'RECAP_NOT_PREPARED');
      if (body.source_fingerprint !== row.source_fingerprint ||
          body.consent_scope_fingerprint !== row.source_fingerprint) {
        throw api.recapError(409, 'RECAP_SCOPE_CHANGED');
      }
      row = await repo.setGenerating(tx, userId, id);
      const op = await repo.record(tx, { userId, requestId: body.request_id, id, operation: 'generate',
        mac: digest, keyVersion, revision: row.revision, deadline: expiry(config.operationSeconds), status: 'running' });
      // Only the first committed caller may dispatch; retries cannot take over.
      return { ...op, executionClaimed: true };
    });
  }
  async function complete(user, idValue, requestValue, generationValue, result, completion = {}, { authorize, metrics } = {}) {
    available();
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue), requestId = api.uuid.parse(requestValue);
    const generationId = api.uuid.parse(generationValue);
    return repo.transaction(userId, async tx => {
      if (authorize) await authorize(tx, userId);
      const row = await repo.find(tx, userId, id);
      const snapshot = await current(tx, userId, row);
      const op = await repo.operation(tx, userId, requestId);
      if (!op || op.recap_id !== id || op.operation !== 'generate' || op.generation_id !== generationId ||
          op.status !== 'running' || op.deadline_at <= clock() || row.state !== 'generating' ||
          op.expected_revision !== row.revision) throw api.recapError(409, 'RECAP_COMPLETION_REJECTED');
      const valid = validateResult(result, snapshot, scope(userId, row.book_id), completion);
      if (authorize) await authorize(tx, userId);
      const next = await repo.setReady(tx, userId, id, valid, expiry(config.previewSeconds));
      if (metrics) await repo.metrics(tx, userId, id, metrics);
      await repo.createConversation(tx, userId, id, row.book_id);
      await repo.finishOperation(tx, userId, requestId, 'succeeded', id);
      if (authorize) await authorize(tx, userId);
      return next;
    });
  }
  // A fresh snapshot is released only to the internal executor, never accepted from HTTP.
  async function dispatch(user, idValue, requestValue, generationValue, authorize) {
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue);
    const requestId = api.uuid.parse(requestValue), generationId = api.uuid.parse(generationValue);
    return repo.transaction(userId, async tx => {
      await authorize(tx, userId);
      const row = await repo.find(tx, userId, id);
      const snapshot = await current(tx, userId, row);
      const op = await repo.operation(tx, userId, requestId);
      if (!op || op.recap_id !== id || op.operation !== 'generate' || op.generation_id !== generationId ||
          op.status !== 'running' || op.deadline_at <= clock() || row.state !== 'generating' ||
          op.expected_revision !== row.revision || row.prompt_version !== PROMPT_VERSION) {
        throw api.recapError(409, 'RECAP_COMPLETION_REJECTED');
      }
      return { snapshot, deadline: op.deadline_at };
    });
  }
  async function fail(user, idValue, requestValue, generationValue, errorCode, metrics) {
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue);
    const requestId = api.uuid.parse(requestValue), generationId = api.uuid.parse(generationValue);
    return repo.transaction(userId, async tx => {
      const row = await repo.find(tx, userId, id);
      const op = await repo.operation(tx, userId, requestId);
      // Never restore metadata or change a newer generation/deletion/cancellation.
      if (!op || op.recap_id !== id || op.operation !== 'generate' || op.generation_id !== generationId ||
          op.status !== 'running' || row.state !== 'generating' || op.expected_revision !== row.revision) return;
      const state = errorCode === 'RECAP_CANCELLED' ? 'cancelled' : 'failed';
      await repo.finishOperation(tx, userId, requestId, state);
      await tx('UPDATE reading_recap_operations SET error_code=$3 WHERE user_id=$1 AND request_id=$2',
        [userId, requestId, errorCode]);
      await tx(`UPDATE reading_recaps SET state=$3,result_json=NULL,revision=revision+1,updated_at=now()
        WHERE id=$1 AND user_id=$2`, [id, userId, state]);
      if (metrics) await repo.metrics(tx, userId, id, metrics);
    });
  }
  async function inspect(user, idValue) {
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue);
    return repo.transaction(userId, async tx => {
      const row = await repo.find(tx, userId, id);
      const snapshot = await current(tx, userId, row);
      return { row, snapshot };
    });
  }
  async function get(user, idValue) {
    available();
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue);
    return repo.transaction(userId, async tx => {
      const row = await repo.find(tx, userId, id);
      await current(tx, userId, row);
      repo.readable(row, clock());
      return row;
    });
  }
  async function save(user, idValue, input) {
    available();
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue), body = api.save.parse(input);
    return repo.transaction(userId, async tx => {
      const row = await repo.find(tx, userId, id);
      await current(tx, userId, row);
      repo.readable(row, clock());
      const digest = mac('save', id, body);
      if (await repo.replay(tx, userId, body.request_id, 'save', id, digest)) return row;
      revision(row, body.expected_revision);
      const saved = await repo.save(tx, userId, id);
      await repo.record(tx, { userId, requestId: body.request_id, id, operation: 'save', mac: digest,
        keyVersion, revision: row.revision, deadline: expiry(config.operationSeconds), status: 'succeeded' });
      return saved;
    });
  }
  async function feedback(user, idValue, input) {
    available();
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue), body = api.feedback.parse(input);
    return repo.transaction(userId, async tx => {
      const row = await repo.find(tx, userId, id);
      await current(tx, userId, row);
      repo.readable(row, clock());
      const digest = mac('feedback', id, body);
      const replay = await repo.replay(tx, userId, body.request_id, 'feedback', id, digest);
      if (replay) return replay.result_id;
      revision(row, body.expected_revision);
      if (body.item_id && !['knowledge','relations','myThinking','openQuestions','nextQuestions']
        .some(k => row.result_json[k].some(item => item.id === body.item_id))) {
        throw api.recapError(422, 'RECAP_ITEM_NOT_FOUND');
      }
      await repo.record(tx, { userId, requestId: body.request_id, id, operation: 'feedback', mac: digest,
        keyVersion, revision: row.revision, deadline: expiry(config.operationSeconds), status: 'succeeded' });
      const feedbackId = await repo.feedback(tx, userId, id, body.request_id, body);
      await repo.finishOperation(tx, userId, body.request_id, 'succeeded', feedbackId);
      return feedbackId;
    });
  }
  async function cancel(user, idValue, requestValue, { expiredOnly = false } = {}) {
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue), requestId = api.uuid.parse(requestValue);
    return repo.transaction(userId, async tx => {
      const row = await repo.find(tx, userId, id);
      if (['deleted', 'invalidated'].includes(row.state)) throw api.recapError(410, 'RECAP_UNAVAILABLE');
      const op = await repo.operation(tx, userId, requestId);
      if (!op || op.recap_id !== id || !['generate', 'follow_up'].includes(op.operation)) throw api.recapError(404, 'RECAP_REQUEST_NOT_FOUND');
      if (['cancelled','interrupted'].includes(op.status)) return;
      if (op.status !== 'running') throw api.recapError(409, 'RECAP_ALREADY_COMPLETED');
      if (expiredOnly && op.deadline_at > clock()) throw api.recapError(409, 'RECAP_NOT_EXPIRED');
      await repo.finishOperation(tx, userId, requestId, expiredOnly ? 'interrupted' : 'cancelled');
      // Cancelling a follow-up must not erase the valid recap or earlier pairs.
      if (op.operation === 'follow_up') return;
      await tx(`UPDATE reading_recaps SET state=$3,result_json=NULL,revision=revision+1,updated_at=now()
        WHERE id=$1 AND user_id=$2`, [id, userId, expiredOnly ? 'failed' : 'cancelled']);
    });
  }
  async function remove(user, idValue) {
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue);
    return repo.transaction(userId, tx => repo.remove(tx, userId, id));
  }
  async function history(tx, userId, row, snapshot) {
    const stored = await repo.followUpHistory(tx, userId, row);
    try {
      const questions = new Map(), answers = new Map();
      for (const message of stored.messages) {
        if (message.user_id !== userId || message.status !== 'completed') throw Error('owner/status');
        const isQuestion = message.role === 'user';
        if (!isQuestion && message.role !== 'assistant') throw Error('role');
        const value = (isQuestion ? follow.questionEnvelope : follow.answerEnvelope).parse(JSON.parse(message.content));
        const collection = isQuestion ? questions : answers;
        if (collection.has(value.turn) || value.sourceFingerprint !== snapshot.fingerprint) throw Error('identity');
        collection.set(value.turn, { value, id: message.id });
      }
      if (questions.size !== answers.size || questions.size !== stored.operations.length) throw Error('missing pair');
      const turns = [];
      for (let i = 1; i <= questions.size; i++) {
        const q = questions.get(i)?.value, a = answers.get(i);
        if (!q || !a) throw Error('sequence');
        const { seal, ...unsigned } = a.value;
        const op = stored.operations.find(o => o.request_id === q.body.request_id);
        if (q.generationId !== a.value.generationId || !op || op.generation_id !== q.generationId ||
            op.result_id !== a.id || op.expected_revision !== q.body.expected_revision ||
            op.request_mac !== mac('follow_up', row.id, q.body) ||
            seal !== mac('follow_up_pair', row.id, { question: q, answer: unsigned })) throw Error('integrity');
        follow.validateAnswer(a.value.answer, snapshot, { completed: true, finishReason: 'stop' });
        turns.push({ turn: i, question: q.body.question, answer: a.value.answer });
      }
      return { ...stored, history: turns, historyFingerprint: follow.historyFingerprint(stored.messages) };
    } catch { throw api.recapError(409, 'RECAP_HISTORY_INVALID'); }
  }
  async function followCurrent(tx, userId, id) {
    const row = await repo.find(tx, userId, id);
    const snapshot = await current(tx, userId, row);
    repo.readable(row, clock());
    if (snapshot.coverage.sourceCompleteness !== 'server_selected_records' || row.prompt_version !== PROMPT_VERSION) {
      throw api.recapError(409, 'RECAP_SOURCE_CHANGED');
    }
    validateResult(row.result_json, snapshot, scope(userId, row.book_id), { completed: true, finishReason: 'stop' });
    return { row, snapshot };
  }
  async function beginFollowUp(user, idValue, input, { authorize }) {
    const userId = api.uuid.parse(user), id = api.uuid.parse(idValue), body = api.followUp.parse(input);
    return repo.transaction(userId, async tx => {
      await authorize(tx, userId);
      const material = await followCurrent(tx, userId, id);
      const digest = mac('follow_up', id, body);
      const replay = await repo.replay(tx, userId, body.request_id, 'follow_up', id, digest);
      if (replay) {
        await repo.operation(tx, userId, body.request_id);
        await history(tx, userId, material.row, material.snapshot);
        return { ...replay, executionClaimed: false };
      }
      revision(material.row, body.expected_revision);
      if (body.item_id && !['knowledge','relations','myThinking','openQuestions','nextQuestions']
        .some(k => material.row.result_json[k].some(item => item.id === body.item_id))) throw api.recapError(422, 'RECAP_ITEM_NOT_FOUND');
      const running = await tx(`SELECT request_id FROM reading_recap_operations WHERE user_id=$1 AND recap_id=$2
        AND status='running' AND operation IN ('generate','follow_up') ORDER BY request_id FOR UPDATE`, [userId, id]);
      if (running.rowCount) throw api.recapError(409, 'RECAP_BUSY');
      const op = await repo.record(tx, { userId, requestId: body.request_id, id, operation: 'follow_up',
        mac: digest, keyVersion, revision: material.row.revision, deadline: expiry(config.operationSeconds), status: 'running' });
      const previous = await history(tx, userId, material.row, material.snapshot);
      // Validate the complete input before persisting the claim. No model request here.
      follow.prepareFollowUp({ ...material, ...previous }, body, { model: 'unconfigured' });
      return { ...op, executionClaimed: true };
    });
  }
  function followOperation(op, row, id, generationId) {
    if (!op || op.recap_id !== id || op.operation !== 'follow_up' || op.generation_id !== generationId ||
        op.status !== 'running' || op.deadline_at <= clock() || op.expected_revision !== row.revision) {
      throw api.recapError(409, 'RECAP_COMPLETION_REJECTED');
    }
  }
  async function dispatchFollowUp(userId, id, requestId, generationId, authorize) {
    return repo.transaction(userId, async tx => {
      await authorize(tx, userId);
      const material = await followCurrent(tx, userId, id);
      const op = await repo.operation(tx, userId, requestId);
      followOperation(op, material.row, id, generationId);
      return { ...material, ...await history(tx, userId, material.row, material.snapshot), deadline: op.deadline_at };
    });
  }
  async function completeFollowUp(userId, id, requestId, generationId, result, completion,
    { authorize, context, body }) {
    return repo.transaction(userId, async tx => {
      await authorize(tx, userId);
      const material = await followCurrent(tx, userId, id);
      const op = await repo.operation(tx, userId, requestId);
      followOperation(op, material.row, id, generationId);
      if (op.request_mac !== mac('follow_up', id, body)) throw api.recapError(409, 'RECAP_REQUEST_CONFLICT');
      const previous = await history(tx, userId, material.row, material.snapshot);
      if (previous.historyFingerprint !== context.historyFingerprint ||
          fingerprint(material.row.result_json) !== fingerprint(context.row.result_json)) throw api.recapError(409, 'RECAP_HISTORY_INVALID');
      const valid = follow.validateAnswer(result, material.snapshot, completion);
      const common = { version: 1, turn: previous.history.length + 1,
        sourceFingerprint: material.snapshot.fingerprint, generationId };
      const question = follow.questionEnvelope.parse({ ...common, body });
      const answer = { ...common, answer: valid };
      const signed = follow.answerEnvelope.parse({ ...answer, seal: mac('follow_up_pair', id, { question, answer }) });
      await authorize(tx, userId);
      const messageId = await repo.appendFollowUpPair(tx, userId, id, previous.conversationId, question, signed);
      await repo.finishOperation(tx, userId, requestId, 'succeeded', messageId);
      await authorize(tx, userId);
    });
  }
  async function failFollowUp(userId, id, requestId, generationId, errorCode) {
    return repo.transaction(userId, async tx => {
      const row = await repo.find(tx, userId, id);
      const op = await repo.operation(tx, userId, requestId);
      if (!op || op.recap_id !== id || op.operation !== 'follow_up' || op.generation_id !== generationId ||
          op.status !== 'running' || row.state !== 'ready') return;
      await repo.finishOperation(tx, userId, requestId, errorCode === 'RECAP_CANCELLED' ? 'cancelled' : 'failed');
      await tx('UPDATE reading_recap_operations SET error_code=$3 WHERE user_id=$1 AND request_id=$2', [userId, requestId, errorCode]);
    });
  }
  async function getFollowUps(userId, id, authorize) {
    return repo.transaction(api.uuid.parse(userId), async tx => {
      await authorize(tx, userId);
      const material = await followCurrent(tx, userId, api.uuid.parse(id));
      const previous = await history(tx, userId, material.row, material.snapshot);
      await authorize(tx, userId);
      return { revision: material.row.revision, source_fingerprint: material.snapshot.fingerprint,
        coverage: material.snapshot.coverage, local_pending_verified: false, turns: previous.history };
    });
  }
  return { prepare, begin, dispatch, complete, fail, inspect, get, save, feedback, cancel, remove,
    beginFollowUp, dispatchFollowUp, completeFollowUp, failFollowUp, getFollowUps };
}
// Explicit internal wiring. Nothing in app.js or the disabled router invokes it.
function createServerBookRecapStorage(options) {
  const { createBookRecapSourceResolver } = require('./bookRecapSourceResolver');
  return createBookRecapStorage({ ...options,
    resolver: createBookRecapSourceResolver({ origin: options.origin }) });
}
module.exports = { createBookRecapStorage, createServerBookRecapStorage };
