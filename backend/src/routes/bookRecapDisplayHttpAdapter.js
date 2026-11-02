const express = require('express');
const { principalSchema } = require('../services/bookRecapExecutor');
const { recapError } = require('../services/bookRecapApiContract');

// Separate additive adapter. Deliberately not mounted or enabled in app.js.
function createBookRecapDisplayHttpAdapter({ service, auth, requireAiConsent }) {
  if (!service || typeof auth !== 'function' || typeof requireAiConsent !== 'function') throw Error('Trusted display dependencies required');
  const router = express.Router();
  router.use((_req,res,next) => { res.set('Cache-Control', 'no-store, private'); res.set('Pragma', 'no-cache'); next(); });
  router.use(auth, requireAiConsent, express.json({ limit: '16kb', strict: true }));
  router.use((req,_res,next) => {
    try {
      if (!req.authUser || req.authUser.id !== req.user?.id) throw recapError(401, 'RECAP_AUTH_REQUIRED');
      if (Object.keys(req.query).length) throw recapError(400, 'RECAP_INVALID_REQUEST');
      req.recapPrincipal = principalSchema.parse({ userId: req.user.id, tokenVersion: Number(req.user.tokenVersion || 0),
        ...(req.user.exp !== undefined ? { expiresAt: req.user.exp } : {}) }); next();
    } catch (error) { next(error); }
  });
  const route = fn => (req,res,next) => Promise.resolve().then(() => fn(req,res)).catch(next);
  router.post('/history', route(async (req,res) => res.json(await service.history(req.recapPrincipal, req.body))));
  for (const action of ['scope','view','evidence','validate']) {
    router.post(`/:id/${action}`, route(async (req,res) => res.json(await service[action](req.recapPrincipal, req.params.id, req.body))));
  }
  router.use((_req,res) => res.status(404).json({ error_code: 'RECAP_ROUTE_NOT_FOUND' }));
  router.use((error,_req,res,_next) => {
    if (res.destroyed) return;
    const invalid = error.name === 'ZodError' || error.type === 'entity.parse.failed';
    const known = /^(RECAP_[A-Z0-9_]+|AI_CONSENT_REQUIRED)$/u.test(error.error_code || '');
    const status = invalid ? 400 : error.type === 'entity.too.large' ? 413 :
      known && error.statusCode >= 400 && error.statusCode <= 599 ? error.statusCode : 500;
    res.status(status).json({ error_code: invalid ? 'RECAP_INVALID_REQUEST' : status === 413 ? 'RECAP_INPUT_BUDGET' :
      known ? error.error_code : 'RECAP_INTERNAL_ERROR' });
  });
  return router;
}
function createServerBookRecapDisplayHttpAdapter(options) {
  const { createBookRecapDisplayService } = require('../services/bookRecapDisplay.service');
  const { createBookRecapAuthorization } = require('../services/bookRecapAuthorization');
  const { AI_CONSENT_VERSION } = require('../controllers/auth.controller');
  return createBookRecapDisplayHttpAdapter({
    service: createBookRecapDisplayService({ ...options, authorize: createBookRecapAuthorization(AI_CONSENT_VERSION) }),
    auth: require('../middleware/auth'), requireAiConsent: require('../middleware/requireAiConsent'),
  });
}
module.exports = { createBookRecapDisplayHttpAdapter, createServerBookRecapDisplayHttpAdapter };
