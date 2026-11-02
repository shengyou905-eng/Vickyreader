const fs = require('node:fs');
const { z } = require('zod');
const { BUNDLE_ID, requireEnvironment } = require('./subscriptions');
const { AppleIapError } = require('../services/appleIapError');

// Read lazily. Missing IAP credentials must not stop existing login/sync services.
function readAppleIapConfig(env = process.env) {
  if (env.APPLE_IAP_ENABLED !== 'true') throw new AppleIapError('APPLE_IAP_DISABLED');
  try {
    const environment = requireEnvironment(env.APPLE_IAP_ENVIRONMENT);
    if (env.APPLE_IAP_BUNDLE_ID !== BUNDLE_ID) throw new Error('bundle');
    const issuerId = z.string().uuid().parse(env.APPLE_IAP_ISSUER_ID);
    const keyId = z.string().regex(/^[A-Z0-9]{10}$/).parse(env.APPLE_IAP_KEY_ID);
    const privateKey = z.string().min(64).parse(env.APPLE_IAP_PRIVATE_KEY).replaceAll('\\n', '\n');
    const appAppleId = env.APPLE_IAP_APP_APPLE_ID
      ? z.coerce.number().int().positive().safe().parse(env.APPLE_IAP_APP_APPLE_ID) : undefined;
    if (environment === 'Production' && !appAppleId) throw new Error('app id');
    const paths = z.string().min(1).parse(env.APPLE_IAP_ROOT_CA_PATHS).split(';');
    const roots = paths.map((path) => fs.readFileSync(path.trim()));
    return { environment, bundleId: BUNDLE_ID, issuerId, keyId, privateKey, appAppleId, roots };
  } catch (_) {
    throw new AppleIapError('APPLE_IAP_NOT_CONFIGURED');
  }
}

module.exports = { readAppleIapConfig };
