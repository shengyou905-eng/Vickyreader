const { z } = require('zod');
const { SignedDataVerifier, VerificationStatus } = require('@apple/app-store-server-library');
const { PRODUCTS, requireEnvironment } = require('../config/subscriptions');
const { AppleIapError } = require('./appleIapError');
const { uuid } = require('./subscriptionState');

const identifier = z.string().regex(/^[0-9]{1,128}$/);
const milliseconds = z.number().int().nonnegative().max(8640000000000000);
const jws = z.string().min(20).max(100000);
const transaction = z.object({
  environment: z.enum(['Sandbox', 'Production']), bundleId: z.string(),
  productId: z.enum(Object.keys(PRODUCTS)), transactionId: identifier, originalTransactionId: identifier,
  appAccountToken: uuid, purchaseDate: milliseconds, expiresDate: milliseconds,
  signedDate: milliseconds, revocationDate: milliseconds.optional(),
  type: z.literal('Auto-Renewable Subscription'), inAppOwnershipType: z.literal('PURCHASED'),
  isUpgraded: z.boolean().optional(),
});
const renewal = z.object({
  environment: z.enum(['Sandbox', 'Production']), originalTransactionId: identifier,
  productId: z.enum(Object.keys(PRODUCTS)), autoRenewStatus: z.union([z.literal(0), z.literal(1)]),
  signedDate: milliseconds, gracePeriodExpiresDate: milliseconds.optional(), appAccountToken: uuid.optional(),
});

class AppleTransactionVerifier {
  constructor(config, verifier = null) {
    this.environment = requireEnvironment(config.environment);
    this.bundleId = config.bundleId;
    // Runtime always checks the certificate chain, signature, expiry AND online OCSP.
    // A test may inject an official verifier using a generated test CA, never via env.
    this.verifier = verifier || new SignedDataVerifier(
      config.roots, true, this.environment, config.bundleId, config.appAppleId,
    );
  }

  async verified(method, value) {
    try {
      return await this.verifier[method](jws.parse(value));
    } catch (error) {
      if (error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) {
        throw new AppleIapError('APPLE_VERIFICATION_UNAVAILABLE');
      }
      throw new AppleIapError('APPLE_SIGNATURE_INVALID', 400);
    }
  }

  async verifyTransaction(signedTransactionInfo) {
    const decoded = await this.verified('verifyAndDecodeTransaction', signedTransactionInfo);
    try {
      const value = transaction.parse(decoded);
      if (value.bundleId !== this.bundleId || value.environment !== this.environment
          || value.expiresDate <= value.purchaseDate || value.signedDate > Date.now() + 60000) throw new Error();
      return value;
    } catch (_) { throw new AppleIapError('APPLE_TRANSACTION_INVALID', 422); }
  }

  async verifyRenewal(signedRenewalInfo, tx) {
    const decoded = await this.verified('verifyAndDecodeRenewalInfo', signedRenewalInfo);
    try {
      const value = renewal.parse(decoded);
      if (value.environment !== this.environment || value.originalTransactionId !== tx.originalTransactionId
          || value.productId !== tx.productId || value.signedDate > Date.now() + 60000
          || (value.appAccountToken && value.appAccountToken !== tx.appAccountToken)) throw new Error();
      return value;
    } catch (_) { throw new AppleIapError('APPLE_RENEWAL_INVALID', 422); }
  }

  async verifyNotification(signedPayload) {
    const value = await this.verified('verifyAndDecodeNotification', signedPayload);
    try {
      z.object({ notificationUUID: uuid, notificationType: z.string().regex(/^[A-Z_]{1,80}$/),
        subtype: z.string().regex(/^[A-Z_]{1,80}$/).optional(), version: z.literal('2.0'),
        signedDate: milliseconds }).parse(value);
      if (value.signedDate > Date.now() + 60000) throw new Error();
    } catch (_) { throw new AppleIapError('APPLE_NOTIFICATION_INVALID', 400); }
    const tx = value.data?.signedTransactionInfo
      ? await this.verifyTransaction(value.data.signedTransactionInfo) : null;
    const rn = value.data?.signedRenewalInfo && tx
      ? await this.verifyRenewal(value.data.signedRenewalInfo, tx) : null;
    if (value.data?.signedRenewalInfo && !tx) throw new AppleIapError('APPLE_NOTIFICATION_INVALID', 400);
    return { uuid: value.notificationUUID.toLowerCase(), type: value.notificationType,
      subtype: value.subtype ?? null, signedAt: new Date(value.signedDate).toISOString(), tx, renewal: rn };
  }
}

module.exports = { AppleTransactionVerifier, identifier, jws };
