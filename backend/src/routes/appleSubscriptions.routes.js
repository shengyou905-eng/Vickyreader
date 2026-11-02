const express = require('express');
const { z } = require('zod');
const auth = require('../middleware/auth');
const { getAppleSubscriptionService } = require('../services/appleSubscription.service');
const { AppleIapError } = require('../services/appleIapError');
const { identifier, jws } = require('../services/appleTransactionVerifier');
const rateLimits = require('../repositories/appleAuth.repository');
const { hashRateLimitKey } = require('../utils/rateLimitHash');
const { authRateLimitSecret } = require('../config/env');

const purchaseInput = z.union([
  z.strictObject({ transactionId: identifier }), z.strictObject({ signedTransactionInfo: jws }),
]);

function createAppleSubscriptionsRouter({ service = getAppleSubscriptionService, sessionAuth = auth,
  consumeRateLimit = rateLimits.consumeRateLimit } = {}) {
  const router = express.Router();
  const body = express.json({ limit: '128kb' });
  const wrap = (fn) => (req, res, next) => Promise.resolve().then(() => fn(req, res)).catch(next);
  const headers = (_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); };
  const rate = (action, maximum) => (req, res, next) => {
    consumeRateLimit({ action: 'iap_' + action, limit: maximum, windowSeconds: 60,
      keyHash: hashRateLimitKey(req.user?.id || req.socket.remoteAddress || '', authRateLimitSecret) })
      .then((allowed) => allowed ? next() : next(new AppleIapError('RATE_LIMITED', 429))).catch(next);
  };
  router.post('/apple/notifications', headers, rate('notification', 300), body, wrap(async (req, res) => {
    const input = z.strictObject({ signedPayload: jws }).parse(req.body);
    res.json(await service().handleNotification(input.signedPayload));
  }));
  router.post('/subscriptions/apple/purchase-context', headers, sessionAuth, rate('context', 20), body,
    wrap(async (req, res) => {
      z.strictObject({}).parse(req.body || {});
      res.json(await service().purchaseContext(req.user.id));
    }));
  router.post('/subscriptions/apple/verify', headers, sessionAuth, rate('verify', 20), body,
    wrap(async (req, res) => res.json(await service().verifyPurchase(req.user.id, purchaseInput.parse(req.body)))));
  router.get('/me/entitlements', headers, sessionAuth, rate('entitlements', 60), wrap(async (req, res) => {
    z.strictObject({}).parse(req.query);
    const current = service();
    res.json(await current.entitlements(req.user.id, current.config.environment));
  }));
  router.use((error, _req, res, _next) => {
    // Do not pass Apple/JWS/PG errors into the global logger or return their messages.
    const status = error instanceof AppleIapError ? error.status
      : error instanceof z.ZodError || error.type === 'entity.parse.failed' ? 400
        : error.type === 'entity.too.large' ? 413 : 503;
    const code = error instanceof AppleIapError ? error.code : status === 400 ? 'INVALID_REQUEST'
      : status === 413 ? 'REQUEST_TOO_LARGE' : 'APPLE_PROCESSING_UNAVAILABLE';
    if (status === 503 || status === 429) res.set('Retry-After', '60');
    res.status(status).json({ error: code });
  });
  return router;
}

module.exports = { createAppleSubscriptionsRouter };
