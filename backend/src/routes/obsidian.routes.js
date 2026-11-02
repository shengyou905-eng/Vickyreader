const express = require('express');
const path = require('node:path');
const auth = require('../middleware/auth');
const authController = require('../controllers/auth.controller');
const authRepository = require('../repositories/obsidianAuth.repository');
const syncRepository = require('../repositories/obsidianSync.repository');
const rateLimits = require('../repositories/appleAuth.repository');
const { hashRateLimitKey } = require('../utils/rateLimitHash');
const httpError = require('../utils/httpError');
const protocol = require('../services/obsidianProtocol.service');
const env = require('../config/env');

function createObsidianRouter({
  accounts = authRepository, exports = syncRepository, sessionAuth = auth,
  consumeRateLimit = rateLimits.consumeRateLimit,
  config = {
    enabled: process.env.OBSIDIAN_SYNC_ENABLED === 'true',
    cursorSecret: process.env.OBSIDIAN_SYNC_CURSOR_SECRET || '',
    redirectUris: String(process.env.OBSIDIAN_SYNC_REDIRECT_URIS || 'obsidian://zhidu-sync').split(',').map(s => s.trim()),
    nodeEnv: env.nodeEnv,
  },
} = {}) {
  const router = express.Router();
  router.use(express.urlencoded({ extended: false, limit: '8kb' }));
  router.use((_req, res, next) => {
    res.set({ 'Cache-Control': 'no-store', 'Pragma': 'no-cache',
      'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; img-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'" });
    if (!config.enabled || config.cursorSecret.length < 32) return res.status(503).json({ error: 'integration_unavailable' });
    next();
  });
  const wrap = fn => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);
  const rate = (action, maximum, identity = req => req.socket.remoteAddress || '') => (req, res, next) => {
    consumeRateLimit({ action: `obsidian_${action}`,
      keyHash: hashRateLimitKey(identity(req), env.authRateLimitSecret), windowSeconds: 60, limit: maximum })
      .then(allowed => {
        if (allowed) return next();
        res.set('Retry-After', '60');
        next(httpError(429, 'rate_limited'));
      }).catch(next);
  };
  const integrationAuth = (req, res, next) => {
    const match = /^Bearer (\S+)$/.exec(req.headers.authorization || '');
    if (!match || !protocol.tokenPattern.test(match[1])) return next(httpError(401, 'invalid_token'));
    accounts.authenticate(match[1]).then(grant => {
      if (!grant) throw httpError(401, 'invalid_token');
      req.obsidianGrant = grant;
      next();
    }).catch(next);
  };

  router.get('/authorize', rate('authorize_page', 30), wrap(async (req, res) => {
    protocol.authorizeInput(req.query, config);
    res.sendFile(path.join(__dirname, '../views/obsidian-authorize.html'));
  }));
  router.get('/authorize.js', (_req, res) => res.sendFile(path.join(__dirname, '../views/obsidian-authorize.js')));
  router.get('/brand.png', (_req, res) => res.sendFile(path.resolve(__dirname, '../../../assets/icon.png')));
  router.post('/login', rate('login', 10), authController.login);
  router.post('/authorize', sessionAuth, rate('authorize', 10, req => req.user.id), wrap(async (req, res) => {
    const input = protocol.authorizeInput(req.body, config, true);
    const redirect = new URL(input.redirect_uri);
    redirect.searchParams.set('state', input.state);
    if (input.allow) {
      const code = protocol.randomCredential('zd_oc_');
      await accounts.createCode(req.user.id, Number(req.authUser.token_version || 0), code, input);
      redirect.searchParams.set('code', code);
    } else redirect.searchParams.set('error', 'access_denied');
    res.json({ redirect_uri: redirect.toString() });
  }));
  router.post('/token', rate('token', 30), wrap(async (req, res) => {
    const input = protocol.tokenInput(req.body, config);
    const token = protocol.randomCredential('zd_os_');
    await accounts.exchangeCode(input, token);
    res.json({ access_token: token, token_type: 'Bearer', expires_in: protocol.TOKEN_TTL_SECONDS, scope: protocol.SCOPE });
  }));
  router.get('/status', integrationAuth, wrap(async (req, res) => {
    res.json({ connected: true, scope: req.obsidianGrant.scope, expires_at: req.obsidianGrant.expires_at });
  }));
  router.post('/revoke', rate('revoke', 30), wrap(async (req, res) => {
    const match = /^Bearer (\S+)$/.exec(req.headers.authorization || '');
    if (!match || !protocol.tokenPattern.test(match[1])) throw httpError(401, 'invalid_token');
    // Possession revokes only this integration, even if already expired/revoked.
    await accounts.revoke(match[1]);
    res.sendStatus(204);
  }));
  router.get('/sync', integrationAuth, rate('sync', 60, req => req.obsidianGrant.user_id), wrap(async (req, res) => {
    const input = protocol.syncInput(req.query);
    res.json(await exports.sync(req.obsidianGrant, input, config.cursorSecret));
  }));
  router.use((error, _req, res, _next) => {
    // Database errors may embed row content; never forward them to global logging.
    let status = error.statusCode || 500;
    let message = error.statusCode ? error.message : 'integration_unavailable';
    if (['40001', '40P01', '57014'].includes(error.code)) { status = 503; message = 'retry_later'; }
    if (status === 401) res.set('WWW-Authenticate', 'Bearer realm="zhidu-obsidian"');
    if (status >= 500) console.error('[obsidian] request_failed status=%d', status);
    res.status(status).json({ error: message });
  });
  return router;
}

module.exports = { createObsidianRouter };
