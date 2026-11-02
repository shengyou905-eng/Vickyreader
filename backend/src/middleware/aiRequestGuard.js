const { createHash } = require('node:crypto');
const { validateAiInput } = require('../services/aiProtocol');

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  }
  return value;
}

// Process-local admission guard, not a durable exactly-once ledger.
function createAiRequestGuard({ ttlMs = 10 * 60 * 1000, maxEntries = 1000, now = Date.now } = {}) {
  const requests = new Map();
  return function guard(req, res, next) {
    try {
      validateAiInput(req.body);
      const id = req.get('X-Request-ID');
      if (!id) return next(); // Legacy clients remain compatible.
      if (!/^[A-Za-z0-9_-]{16,128}$/.test(id)) {
        return res.status(400).json({ error: 'Invalid request ID' });
      }
      for (const [key, record] of requests) {
        // Never evict a running request, even under memory pressure.
        if (record.state !== 'running' && record.expiresAt <= now()) requests.delete(key);
      }
      const key = JSON.stringify([String(req.user.id), id]);
      const hash = createHash('sha256').update(JSON.stringify([req.path, canonical(req.body)])).digest('hex');
      const previous = requests.get(key);
      if (previous) {
        return res.status(409).json({
          error: previous.hash === hash ? '本次请求已经受理，请勿重复发送。' : '请求标识与内容不一致。',
          code: previous.hash === hash ? 'AI_REQUEST_DUPLICATE' : 'AI_REQUEST_CONFLICT',
          state: previous.state,
        });
      }
      if (requests.size >= maxEntries) return res.status(429).json({ error: 'AI request guard at capacity; retry later' });
      const record = { hash, state: 'running', expiresAt: Infinity };
      requests.set(key, record);
      const finish = state => {
        if (record.state !== 'running') return;
        record.state = state;
        record.expiresAt = now() + ttlMs;
      };
      res.once('finish', () => finish(res.locals.aiOutcome || 'failed'));
      res.once('close', () => finish('interrupted'));
      next();
    } catch (error) {
      next(error);
    }
  };
}

module.exports = { createAiRequestGuard };
