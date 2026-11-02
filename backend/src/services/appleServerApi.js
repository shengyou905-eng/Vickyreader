const { AppStoreServerAPIClient } = require('@apple/app-store-server-library');
const { AppleIapError } = require('./appleIapError');
const { identifier } = require('./appleTransactionVerifier');
const { parseSnapshot } = require('./subscriptionState');

class BoundedAppleClient extends AppStoreServerAPIClient {
  // Keep official request signing/response validation; bound its HTTP transport.
  async makeFetchRequest(path, query, method, body, headers) {
    return fetch(this.urlBase + path + '?' + query, {
      method, body, headers, signal: AbortSignal.timeout(30000), redirect: 'error',
    });
  }
}

class AppleServerApi {
  constructor(config, verifier, client = null) {
    this.config = config;
    this.verifier = verifier;
    this.client = client || new BoundedAppleClient(config.privateKey, config.keyId,
      config.issuerId, config.bundleId, config.environment);
  }

  async call(method, id) {
    identifier.parse(id);
    try { return await this.client[method](id); }
    catch (_) { throw new AppleIapError('APPLE_API_UNAVAILABLE'); }
  }

  async getTransaction(transactionId) {
    const response = await this.call('getTransactionInfo', transactionId);
    const tx = await this.verifier.verifyTransaction(response.signedTransactionInfo);
    if (tx.transactionId !== transactionId) throw new AppleIapError('APPLE_RESPONSE_MISMATCH');
    return tx;
  }

  async getCurrentSnapshot(originalTransactionId, evidence = null) {
    const response = await this.call('getAllSubscriptionStatuses', originalTransactionId);
    if (response.environment !== this.config.environment || response.bundleId !== this.config.bundleId
        || (this.config.environment === 'Production' && response.appAppleId !== this.config.appAppleId)) {
      throw new AppleIapError('APPLE_RESPONSE_MISMATCH');
    }
    const matches = [];
    for (const group of response.data || []) {
      for (const row of group.lastTransactions || []) {
        if (row.originalTransactionId !== originalTransactionId) continue;
        const tx = await this.verifier.verifyTransaction(row.signedTransactionInfo);
        const rn = await this.verifier.verifyRenewal(row.signedRenewalInfo, tx);
        if (tx.originalTransactionId !== originalTransactionId || tx.isUpgraded) {
          throw new AppleIapError('APPLE_STATE_NOT_CURRENT');
        }
        if (evidence && (tx.purchaseDate < evidence.tx.purchaseDate
            || (tx.transactionId === evidence.tx.transactionId && tx.signedDate < evidence.tx.signedDate)
            || (evidence.renewal && rn.signedDate < evidence.renewal.signedDate))) {
          throw new AppleIapError('APPLE_STATE_NOT_CURRENT');
        }
        const status = { 1: 'active', 2: 'expired', 3: 'billing_retry', 4: 'grace_period', 5: 'revoked' }[row.status];
        if (!status || (status === 'revoked' && tx.revocationDate === undefined)) {
          throw new AppleIapError('APPLE_STATE_NOT_CURRENT');
        }
        const iso = (date) => new Date(date).toISOString();
        let state;
        try {
          state = parseSnapshot({ environment: tx.environment, appAccountToken: tx.appAccountToken,
            originalTransactionId, transactionId: tx.transactionId, productId: tx.productId,
            status: tx.revocationDate !== undefined ? 'revoked' : status,
            purchasedAt: iso(tx.purchaseDate), expiresAt: iso(tx.expiresDate),
            gracePeriodExpiresAt: status === 'grace_period' && rn.gracePeriodExpiresDate !== undefined
              ? iso(rn.gracePeriodExpiresDate) : null,
            revokedAt: tx.revocationDate === undefined ? null : iso(tx.revocationDate),
            autoRenew: rn.autoRenewStatus === 1, signedAt: iso(Math.max(tx.signedDate, rn.signedDate)) });
        } catch (_) { throw new AppleIapError('APPLE_STATE_NOT_CURRENT'); }
        matches.push({ state, versions: { transaction: iso(tx.signedDate), renewal: iso(rn.signedDate) } });
      }
    }
    if (matches.length !== 1) throw new AppleIapError('APPLE_STATE_NOT_CURRENT');
    return matches[0];
  }
}

module.exports = { AppleServerApi, BoundedAppleClient };
