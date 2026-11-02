const express = require('express');
const dto = require('../services/bookRecapHttpContract');
const { principalSchema } = require('../services/bookRecapExecutor');

// Unmounted adapter, explicitly composed for isolated tests. The public router
// and both feature flags remain closed. Never infer enablement from an env flag.
function createBookRecapHttpAdapter({ storage, executor, followUpExecutor, auth, requireAiConsent }) {
  if (typeof auth !== 'function' || typeof requireAiConsent !== 'function') throw Error('Trusted auth and AI consent middleware required');
  const router = express.Router();
  router.use((_req, res, next) => { res.set('Cache-Control', 'no-store, private'); next(); });
  router.use(auth);
  router.use(express.json({ limit: '80kb', strict: true }));
  router.use((req, _res, next) => {
    try {
      if (!req.authUser || req.authUser.id !== req.user?.id) throw dto.recapError(401, 'RECAP_AUTH_REQUIRED');
      req.recapPrincipal = principalSchema.parse({ userId: req.user.id, tokenVersion: Number(req.user.tokenVersion || 0),
        ...(req.user.exp !== undefined ? { expiresAt: req.user.exp } : {}) });
      if (Object.keys(req.query).length) throw dto.recapError(400, 'RECAP_INVALID_REQUEST');
      next();
    } catch (e) { next(e); }
  });
  const route = fn => (req, res, next) => Promise.resolve().then(() => fn(req, res)).catch(next);
  const id = req => dto.uuid.parse(req.params.id);
  router.post('/prepare', requireAiConsent, route(async (req, res) => {
    const body = dto.prepare.parse(req.body);
    await storage.prepare(req.recapPrincipal.userId, body);
    const { row, snapshot } = await storage.inspect(req.recapPrincipal.userId, body.recap_id);
    res.json(dto.present(row, snapshot));
  }));
  router.get('/:id', requireAiConsent, route(async (req, res) => {
    const { row, snapshot } = await storage.inspect(req.recapPrincipal.userId, id(req));
    res.json(dto.present(row, snapshot));
  }));
  router.post('/:id/generate', requireAiConsent, route(async (req, res) => {
    const controller = new AbortController();
    const closed = () => { if (!res.writableEnded) controller.abort(); };
    res.on('close', closed);
    try {
      const outcome = await executor.generate(req.recapPrincipal, id(req), dto.generate.parse(req.body), { signal: controller.signal });
      if (!res.destroyed) res.status(outcome.status === 'running' ? 202 : 200).json(dto.outcome.parse(outcome));
    } finally { res.removeListener('close', closed); }
  }));
  router.post('/:id/save', requireAiConsent, route(async (req, res) => {
    await storage.save(req.recapPrincipal.userId, id(req), dto.save.parse(req.body));
    const { row, snapshot } = await storage.inspect(req.recapPrincipal.userId, id(req));
    res.json(dto.present(row, snapshot));
  }));
  router.get('/:id/follow-ups', requireAiConsent, route(async (req, res) => {
    if (!followUpExecutor) throw dto.recapError(503, 'RECAP_FOUNDATION_NOT_CONFIGURED');
    res.json(await followUpExecutor.list(req.recapPrincipal, id(req)));
  }));
  router.post('/:id/follow-ups', requireAiConsent, route(async (req, res) => {
    if (!followUpExecutor) throw dto.recapError(503, 'RECAP_FOUNDATION_NOT_CONFIGURED');
    const controller = new AbortController();
    const closed = () => { if (!res.writableEnded) controller.abort(); };
    res.on('close', closed);
    try {
      const outcome = await followUpExecutor.ask(req.recapPrincipal, id(req), req.body, { signal: controller.signal });
      if (!res.destroyed) res.status(outcome.status === 'running' ? 202 : 200).json(dto.outcome.parse(outcome));
    } finally { res.removeListener('close', closed); }
  }));
  router.post('/:id/feedback', route(async (req, res) => {
    const feedbackId = await storage.feedback(req.recapPrincipal.userId, id(req), dto.feedback.parse(req.body));
    res.json({ id: dto.uuid.parse(feedbackId) });
  }));
  // Revoking AI consent must not prevent cancellation or privacy deletion.
  router.post('/:id/operations/:requestId/cancel', route(async (req, res) => {
    dto.empty.parse(req.body || {});
    await executor.cancel(req.recapPrincipal.userId, id(req), dto.uuid.parse(req.params.requestId));
    // Cancellation is idempotent; abort either executor's local network wait.
    if (followUpExecutor) await followUpExecutor.cancel(req.recapPrincipal.userId, id(req), dto.uuid.parse(req.params.requestId));
    res.status(204).end();
  }));
  router.delete('/:id', route(async (req, res) => {
    dto.empty.parse(req.body || {});
    await storage.remove(req.recapPrincipal.userId, id(req)); res.status(204).end();
  }));
  router.use((_req, res) => res.status(404).json({ error_code: 'RECAP_ROUTE_NOT_FOUND' }));
  router.use((error, _req, res, _next) => {
    if (res.destroyed) return;
    // Whitelist shape AND status; never serialize Zod issues, SQL or provider messages.
    const validation = error.name === 'ZodError' || error.type === 'entity.parse.failed';
    const known = /^[A-Z][A-Z0-9_]{1,80}$/u.test(error.error_code || '') &&
      (error.error_code.startsWith('RECAP_') || error.error_code === 'AI_CONSENT_REQUIRED');
    const status = validation ? 400 : error.type === 'entity.too.large' ? 413 :
      known && error.statusCode >= 400 && error.statusCode <= 599 ? error.statusCode : 500;
    res.status(status).json({ error_code: validation ? 'RECAP_INVALID_REQUEST' :
      status === 413 ? 'RECAP_INPUT_BUDGET' : known ? error.error_code : 'RECAP_INTERNAL_ERROR' });
  });
  return router;
}
// Future server composition, still NOT called/mounted by app.js. All credentials
// and model settings must be explicitly supplied by a reviewed server bootstrap.
function createServerBookRecapHttpAdapter({ repository, origin, macKey, keyVersion, config,
  endpoint, apiKey, model, pricing, timeoutMs, maxConcurrent }) {
  const auth = require('../middleware/auth');
  const requireAiConsent = require('../middleware/requireAiConsent');
  const { AI_CONSENT_VERSION } = require('../controllers/auth.controller');
  const { createBookRecapAuthorization } = require('../services/bookRecapAuthorization');
  const { createServerBookRecapStorage } = require('../services/bookRecapStorage.service');
  const { createBookRecapExecutor } = require('../services/bookRecapExecutor');
  const { createBookRecapModelTransport } = require('../services/bookRecapModelTransport');
  const { createBookRecapFollowUpExecutor } = require('../services/bookRecapFollowUpExecutor');
  const storage = createServerBookRecapStorage({ repository, origin, macKey, keyVersion, config });
  const executionOptions = { storage, model, pricing, timeoutMs, maxConcurrent,
    authorize: createBookRecapAuthorization(AI_CONSENT_VERSION),
    transport: createBookRecapModelTransport({ endpoint, apiKey }) };
  const executor = createBookRecapExecutor(executionOptions);
  const followUpExecutor = createBookRecapFollowUpExecutor(executionOptions);
  return createBookRecapHttpAdapter({ storage, executor, followUpExecutor, auth, requireAiConsent });
}
module.exports = { createBookRecapHttpAdapter, createServerBookRecapHttpAdapter };
