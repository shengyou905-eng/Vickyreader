const { createHash } = require('node:crypto');
const { NotificationTypeV2 } = require('@apple/app-store-server-library');
const { PRODUCTS } = require('../config/subscriptions');
const { AppleIapError } = require('./appleIapError');

const actionable = new Set([
  'SUBSCRIBED', 'DID_RENEW', 'DID_CHANGE_RENEWAL_STATUS', 'DID_CHANGE_RENEWAL_PREF',
  'DID_FAIL_TO_RENEW', 'GRACE_PERIOD_EXPIRED', 'EXPIRED', 'REFUND', 'REVOKE',
  'REFUND_REVERSED', 'RENEWAL_EXTENDED', 'OFFER_REDEEMED',
].map((type) => NotificationTypeV2[type]));

function checkResult(value) {
  if (['stale', 'version_conflict'].includes(value.result)) throw new AppleIapError('APPLE_STATE_NOT_CURRENT');
  if (['ownership_conflict', 'account_token_mismatch', 'account_deleted', 'event_conflict'].includes(value.result)) {
    throw new AppleIapError(value.result.toUpperCase(), 409);
  }
  return value;
}

class AppleSubscriptionService {
  constructor({ config, verifier, api, repository, entitlements }) {
    Object.assign(this, { config, verifier, api, repository, entitlements });
  }

  async purchaseContext(userId) {
    const account = await this.repository.getOrCreateAccount(userId, this.config.environment);
    if (!account) throw new AppleIapError('ACCOUNT_DELETED', 409);
    return { appAccountToken: account.app_account_token, environment: account.environment,
      productIds: Object.keys(PRODUCTS) };
  }

  async verifyPurchase(userId, input) {
    const tx = input.signedTransactionInfo
      ? await this.verifier.verifyTransaction(input.signedTransactionInfo)
      : await this.api.getTransaction(input.transactionId);
    // Neither the device success flag nor an old signed transaction can grant Pro.
    const snapshot = await this.api.getCurrentSnapshot(tx.originalTransactionId, { tx });
    const result = await this.repository.applyVerifiedSnapshot(userId, snapshot.state, null,
      { versions: snapshot.versions });
    checkResult(result);
    return { result: result.result, ...(await this.entitlements(userId, this.config.environment)) };
  }

  async handleNotification(signedPayload) {
    const notice = await this.verifier.verifyNotification(signedPayload);
    const terminal = notice.type === 'TEST' ? 'test' : actionable.has(notice.type) ? null : 'ignored';
    if (!terminal && !notice.tx) throw new AppleIapError('APPLE_NOTIFICATION_INVALID', 400);
    const hash = createHash('sha256').update(signedPayload).digest('hex');
    const event = await this.repository.recordNotification(this.config.environment, notice, hash, terminal);
    if (event.result === 'event_conflict') throw new AppleIapError('EVENT_CONFLICT', 409);
    if (event.result === 'account_deleted') return { result: 'account_deleted' };
    if (event.processed_at) return { result: event.duplicate ? 'duplicate' : event.result };
    const owner = await this.repository.lookupOwnership(this.config.environment, notice.tx.originalTransactionId);
    if (!owner?.user_id) return { result: 'awaiting_binding' };
    try {
      // A notification is a reconciliation signal, not an authoritative arrival-ordered update.
      // In particular a refund of an OLD period must not revoke a NEW paid transaction.
      const snapshot = await this.api.getCurrentSnapshot(notice.tx.originalTransactionId, notice);
      return checkResult(await this.repository.applyVerifiedSnapshot(owner.user_id, snapshot.state, null,
        { versions: snapshot.versions, eventId: event.id, allowClaim: false }));
    } catch (error) {
      await this.repository.recordNotificationFailure(event.id,
        error instanceof AppleIapError ? error.code : 'APPLE_PROCESSING_UNAVAILABLE');
      if (error instanceof AppleIapError) throw error;
      throw new AppleIapError('APPLE_PROCESSING_UNAVAILABLE');
    }
  }

  async reconcileAppleSubscription(originalTransactionId) {
    const owner = await this.repository.lookupOwnership(this.config.environment, originalTransactionId);
    if (!owner) return { result: 'awaiting_binding' };
    if (!owner.user_id) return { result: 'account_deleted' };
    const snapshot = await this.api.getCurrentSnapshot(originalTransactionId);
    const result = checkResult(await this.repository.applyVerifiedSnapshot(owner.user_id, snapshot.state, null,
      { versions: snapshot.versions, allowClaim: false, reconciliation: true }));
    // No stored JWS is needed to recover failed/orphan notifications after explicit binding.
    // Each audit completion and its state/grant check share the same business transaction.
    for (const event of await this.repository.pendingNotifications(this.config.environment, originalTransactionId)) {
      checkResult(await this.repository.applyVerifiedSnapshot(owner.user_id, snapshot.state, null,
        { versions: snapshot.versions, eventId: event.id, allowClaim: false }));
    }
    return result;
  }
}

let runtime;
function getAppleSubscriptionService() {
  if (!runtime) {
    const { readAppleIapConfig } = require('../config/appleIap');
    const { AppleTransactionVerifier } = require('./appleTransactionVerifier');
    const { AppleServerApi } = require('./appleServerApi');
    const config = readAppleIapConfig();
    try {
      const verifier = new AppleTransactionVerifier(config);
      runtime = new AppleSubscriptionService({ config, verifier, api: new AppleServerApi(config, verifier),
        repository: require('../repositories/subscription.repository'),
        entitlements: require('./entitlement.service').getEntitlements });
    } catch (_) { throw new AppleIapError('APPLE_IAP_NOT_CONFIGURED'); }
  }
  return runtime;
}

module.exports = { AppleSubscriptionService, getAppleSubscriptionService, actionable };
