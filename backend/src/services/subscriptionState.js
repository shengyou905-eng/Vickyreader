const { createHash } = require('node:crypto');
const { z } = require('zod');
const { PRODUCTS, ENVIRONMENTS } = require('../config/subscriptions');

const uuid = z.string().uuid().transform((s) => s.toLowerCase());
const instant = z.iso.datetime({ offset: true }).transform((s) => new Date(s).toISOString());
const transactionId = z.string().regex(/^[0-9]{1,128}$/);

// Internal persistence DTO, NOT a signature verifier. No route accepts it.
// Phase 2 must construct it only after Apple verification/reconciliation.
const snapshotSchema = z.strictObject({
  environment: z.enum(ENVIRONMENTS),
  appAccountToken: uuid,
  originalTransactionId: transactionId,
  transactionId,
  productId: z.enum(Object.keys(PRODUCTS)),
  status: z.enum(['active', 'grace_period', 'billing_retry', 'expired', 'revoked']),
  purchasedAt: instant,
  expiresAt: instant,
  gracePeriodExpiresAt: instant.nullable(),
  revokedAt: instant.nullable(),
  autoRenew: z.boolean(),
  signedAt: instant,
}).superRefine((value, ctx) => {
  const invalid = (message) => ctx.addIssue({ code: 'custom', message });
  if (value.expiresAt <= value.purchasedAt) invalid('Expiry must follow purchase');
  if ((value.status === 'revoked') !== (value.revokedAt !== null)) invalid('Revocation state mismatch');
  if (value.gracePeriodExpiresAt !== null && value.gracePeriodExpiresAt <= value.expiresAt) {
    invalid('Grace must extend the paid period');
  }
  if (value.status === 'grace_period' && value.gracePeriodExpiresAt === null) invalid('Grace deadline required');
});

function parseSnapshot(input) {
  return snapshotSchema.parse(input);
}

function snapshotHash(value) {
  // Fixed field order and normalized dates; account tokens stay out of audit hashes.
  return createHash('sha256').update(JSON.stringify([
    value.environment, value.originalTransactionId, value.transactionId, value.productId,
    value.status, value.purchasedAt, value.expiresAt, value.gracePeriodExpiresAt,
    value.revokedAt, value.autoRenew, value.signedAt,
  ])).digest('hex');
}

function grantForSnapshot(value) {
  return {
    entitlement: PRODUCTS[value.productId].entitlement,
    enabled: ['active', 'grace_period', 'billing_retry'].includes(value.status),
    validFrom: value.purchasedAt,
    validUntil: value.status === 'grace_period' ? value.gracePeriodExpiresAt : value.expiresAt,
    revokedAt: value.revokedAt,
  };
}

const notificationSchema = z.strictObject({
  uuid,
  type: z.string().regex(/^[A-Z_]{1,80}$/),
  subtype: z.string().regex(/^[A-Z_]{1,80}$/).nullable(),
});

module.exports = { uuid, parseSnapshot, snapshotHash, grantForSnapshot, notificationSchema };
