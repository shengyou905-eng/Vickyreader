const { z } = require('zod');
const { performance } = require('node:perf_hooks');
const api = require('./bookRecapApiContract');
const { prepareGeneration, BUDGET } = require('./bookRecapGeneration');
const { validateResult } = require('./bookRecapContract');
const { OUTPUT_BYTES } = require('./bookRecapModelTransport');

const principalSchema = z.strictObject({ userId: api.uuid, tokenVersion: z.number().int().nonnegative(),
  expiresAt: z.number().int().positive().optional() });
const rateSchema = z.strictObject({ model: z.string().min(1).max(128), currency: z.string().regex(/^[A-Z]{3}$/u),
  inputPerMillion: z.number().finite().nonnegative().max(1000000),
  outputPerMillion: z.number().finite().nonnegative().max(1000000), version: z.string().min(1).max(128) });
const SAFE_ERRORS = new Set(['RECAP_TIMEOUT','RECAP_CANCELLED','RECAP_UPSTREAM_FAILED','RECAP_STREAM_INVALID',
  'RECAP_STREAM_INCOMPLETE','RECAP_OUTPUT_BUDGET','RECAP_SCOPE_NOT_READY','RECAP_INVALID_RESULT',
  'RECAP_SOURCE_CHANGED','RECAP_UNAVAILABLE','RECAP_COMPLETION_REJECTED','RECAP_AUTH_REQUIRED','AI_CONSENT_REQUIRED',
  'RECAP_HISTORY_INVALID','RECAP_HISTORY_BUDGET']);

function createBookRecapExecutor({ storage, transport, authorize, model, pricing = null,
  timeoutMs = 90000, maxConcurrent = 4, workflow = null }) {
  if (typeof transport !== 'function' || typeof authorize !== 'function' ||
      typeof model !== 'string' || !/^[a-zA-Z0-9._:/-]{1,128}$/u.test(model) || !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 ||
      timeoutMs > 600000 || !Number.isSafeInteger(maxConcurrent) || maxConcurrent < 1 || maxConcurrent > 64) {
    throw Error('Explicit bounded executor configuration required');
  }
  const rate = pricing === null ? null : rateSchema.parse(pricing);
  const active = new Map();
  const key = (user, id, request) => `${user}:${id}:${request}`;
  async function generate(principalValue, idValue, input, { signal } = {}) {
    const principal = principalSchema.parse(principalValue), id = api.uuid.parse(idValue);
    const body = (workflow?.requestSchema || api.generate).parse(input), user = principal.userId;
    const check = (tx, userId) => authorize(tx, userId, principal);
    // Bound in-flight work before acquiring a durable claim; no unbounded queue.
    if (active.size >= maxConcurrent) throw api.recapError(429, 'RECAP_BUSY');
    const slot = Symbol('admission'); active.set(slot, null);
    let op, timer, abortListener, started = performance.now(), metrics;
    const controller = new AbortController();
    const abort = code => controller.abort(api.recapError(code === 'RECAP_TIMEOUT' ? 504 : 409, code));
    let k;
    let observed = { returnedModel: null, inputTokens: null, outputTokens: null };
    function measurement() {
      const { returnedModel, inputTokens, outputTokens } = observed;
      const costKnown = rate && rate.model === returnedModel && inputTokens !== null && outputTokens !== null;
      return { requestedModel: model, returnedModel, inputTokens, outputTokens,
        elapsedMs: Math.max(0, Math.round(performance.now() - started)),
        costAmount: costKnown ? ((inputTokens * rate.inputPerMillion + outputTokens * rate.outputPerMillion) / 1e6).toFixed(8) : null,
        costCurrency: costKnown ? rate.currency : null, pricingVersion: costKnown ? rate.version : null };
    }
    try {
      signal?.throwIfAborted();
      op = await storage.begin(user, id, body, { authorize: check });
      if (!op.executionClaimed) {
        if (op.status === 'running' && new Date(op.deadline_at).getTime() <= Date.now()) {
          await storage.cancel(user, id, body.request_id, { expiredOnly: true });
          return { status: 'interrupted', replay: true };
        }
        return { status: op.status, replay: true };
      }
      k = key(user, id, body.request_id); active.delete(slot); active.set(k, controller);
      abortListener = () => abort('RECAP_CANCELLED');
      signal?.addEventListener('abort', abortListener, { once: true });
      if (signal?.aborted) abortListener();
      const context = await storage.dispatch(user, id, body.request_id, op.generation_id, check);
      const { snapshot, deadline } = context;
      if (snapshot.coverage.sourceCompleteness !== 'server_selected_records') throw api.recapError(409, 'RECAP_SOURCE_CHANGED');
      const plan = workflow ? workflow.prepare(context, body, { model }) : prepareGeneration(snapshot, snapshot.scope, { model });
      if (plan.status !== 'ready') throw api.recapError(422, 'RECAP_SCOPE_NOT_READY');
      const remaining = Math.min(timeoutMs, new Date(deadline).getTime() - Date.now());
      if (remaining <= 0) abort('RECAP_TIMEOUT');
      timer = setTimeout(() => abort('RECAP_TIMEOUT'), Math.max(1, remaining));
      controller.signal.throwIfAborted();
      // dispatch has committed: no DB connection or source lock is held here.
      const stopped = new Promise((_, reject) => controller.signal.addEventListener('abort',
        () => reject(controller.signal.reason), { once: true }));
      started = performance.now();
      const response = await Promise.race([stopped, transport(plan.request, {
        signal: controller.signal,
        observe(value) {
          if (controller.signal.aborted) return;
          observed = {
            returnedModel: typeof value.returnedModel === 'string' && /^[a-zA-Z0-9._:/-]{1,128}$/u.test(value.returnedModel) ? value.returnedModel : null,
            inputTokens: Number.isSafeInteger(value.inputTokens) && value.inputTokens >= 0 && value.inputTokens <= 1e9 ? value.inputTokens : null,
            outputTokens: Number.isSafeInteger(value.outputTokens) && value.outputTokens >= 0 && value.outputTokens <= 1e9 ? value.outputTokens : null,
          };
        },
      })]);
      controller.signal.throwIfAborted();
      metrics = measurement();
      if (typeof response?.text !== 'string' || Buffer.byteLength(response.text, 'utf8') > OUTPUT_BYTES ||
          (metrics.outputTokens !== null && metrics.outputTokens > BUDGET.maxOutputTokens)) throw api.recapError(502, 'RECAP_OUTPUT_BUDGET');
      let result;
      try { result = workflow ? workflow.validate(JSON.parse(response.text), snapshot, response)
        : validateResult(JSON.parse(response.text), snapshot, snapshot.scope, response); }
      catch { throw api.recapError(502, 'RECAP_INVALID_RESULT'); }
      // Abort is checked again inside the final transaction; a queued complete cannot beat cancel.
      const finalCheck = async (tx, uid) => { controller.signal.throwIfAborted(); await check(tx, uid); controller.signal.throwIfAborted(); };
      await storage.complete(user, id, body.request_id, op.generation_id, result, response, { authorize: finalCheck, metrics, context, body });
      return { status: 'succeeded', replay: false };
    } catch (error) {
      const code = SAFE_ERRORS.has(error.error_code) ? error.error_code : 'RECAP_UPSTREAM_FAILED';
      if (op?.executionClaimed) {
        // If cleanup itself fails, durable running state still fences retries; report it, never claim success.
        try { await storage.fail(user, id, body.request_id, op.generation_id, code, metrics || measurement()); }
        catch { throw api.recapError(503, 'RECAP_FINALIZATION_UNAVAILABLE'); }
      }
      if (!op) throw error; // authentication/conflict before a model claim; HTTP still sanitizes it
      throw api.recapError(error.statusCode || 502, code);
    } finally {
      clearTimeout(timer); signal?.removeEventListener('abort', abortListener);
      active.delete(slot); if (k) active.delete(k);
    }
  }
  async function cancel(user, id, request) {
    // Commit cancellation first. A completion already committed wins; do not relabel success.
    await storage.cancel(user, id, request);
    active.get(key(user, id, request))?.abort(api.recapError(409, 'RECAP_CANCELLED'));
  }
  return { generate, cancel };
}
module.exports = { createBookRecapExecutor, principalSchema };
