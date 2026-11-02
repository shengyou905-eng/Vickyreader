const { query, withTransaction } = require('../config/db');
const { requireEnvironment } = require('../config/subscriptions');
const {
  uuid, parseSnapshot, snapshotHash, grantForSnapshot, notificationSchema,
} = require('../services/subscriptionState');

async function getOrCreateAccount(userId, environment) {
  userId = uuid.parse(userId);
  requireEnvironment(environment);
  return withTransaction(async (tx) => {
    // Match account deletion lock order; a concurrent delete cannot leave a grant.
    const user = await tx('SELECT id FROM users WHERE id = $1 FOR UPDATE', [userId]);
    if (!user.rowCount) return null;
    await tx(
      'INSERT INTO subscription_accounts (user_id, environment) VALUES ($1, $2) ON CONFLICT (user_id, environment) DO NOTHING',
      [userId, environment],
    );
    const result = await tx(
      'SELECT id, app_account_token, environment FROM subscription_accounts WHERE user_id = $1 AND environment = $2',
      [userId, environment],
    );
    return result.rows[0];
  });
}

// INTERNAL ONLY: Phase 2 service supplies verified Apple/API data, never an HTTP DTO.
async function applyVerifiedSnapshot(userId, input, notification = null, options = {}) {
  userId = uuid.parse(userId);
  const state = parseSnapshot(input);
  const notice = notification === null ? null : notificationSchema.parse(notification);
  const hash = snapshotHash(state);
  return withTransaction(async (tx) => {
    const user = await tx('SELECT id FROM users WHERE id = $1 FOR UPDATE', [userId]);
    if (!user.rowCount) return { result: 'account_deleted' };
    const account = (await tx(
      'SELECT * FROM subscription_accounts WHERE user_id = $1 AND environment = $2 FOR UPDATE',
      [userId, state.environment],
    )).rows[0];
    if (!account) return { result: 'account_token_mismatch' };

    let event;
    if (options.eventId) {
      event = (await tx('SELECT * FROM subscription_events WHERE id=$1 AND environment=$2 FOR UPDATE',
        [options.eventId, state.environment])).rows[0];
      if (!event || event.original_transaction_id !== state.originalTransactionId) return { result: 'event_conflict' };
      if (event.processed_at) return { result: 'duplicate' };
      if (event.transaction_purchased_at && (Date.parse(state.purchasedAt) < event.transaction_purchased_at.getTime()
          || (state.transactionId === event.transaction_id
            && Date.parse(options.versions.transaction) < event.transaction_signed_at.getTime())
          || (event.renewal_signed_at && Date.parse(options.versions.renewal) < event.renewal_signed_at.getTime()))) {
        return { result: 'stale' };
      }
    } else event = (await tx(
      `INSERT INTO subscription_events
        (environment, event_kind, request_hash, notification_uuid, notification_type, subtype, account_id, result)
       VALUES ($1, $2, $3, $4, $5, $6, $7, 'awaiting_binding')
       ON CONFLICT (environment, notification_uuid) DO NOTHING RETURNING id`,
      [state.environment, notice ? 'notification' : options.reconciliation ? 'reconciliation' : 'verification', hash,
        notice?.uuid ?? null, notice?.type ?? null, notice?.subtype ?? null, account.id],
    )).rows[0];
    if (!event) {
      const previous = (await tx(
        'SELECT request_hash, account_id FROM subscription_events WHERE environment = $1 AND notification_uuid = $2',
        [state.environment, notice.uuid],
      )).rows[0];
      return { result: previous.request_hash === hash && previous.account_id === account.id
        ? 'duplicate' : 'event_conflict' };
    }
    const finish = async (result, ownershipId = null) => {
      await tx(
        `UPDATE subscription_events SET result = $2, ownership_id = $3, account_id=$4,
           processed_at = CASE WHEN $5 THEN NULL ELSE now() END WHERE id = $1`,
        [event.id, result, ownershipId, account.id,
          Boolean(options.eventId && ['stale', 'version_conflict'].includes(result))],
      );
      return { result };
    };
    if (state.appAccountToken !== account.app_account_token) {
      return finish('account_token_mismatch');
    }
    await tx('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',
      [state.environment + ':' + state.originalTransactionId]);
    if (options.allowClaim !== false) await tx(
      `INSERT INTO subscription_ownership (provider, environment, original_transaction_id, account_id)
       VALUES ('apple_app_store', $1, $2, $3)
       ON CONFLICT (provider, environment, original_transaction_id) DO NOTHING`,
      [state.environment, state.originalTransactionId, account.id],
    );
    const owner = (await tx(
      `SELECT * FROM subscription_ownership
       WHERE provider = 'apple_app_store' AND environment = $1 AND original_transaction_id = $2 FOR UPDATE`,
      [state.environment, state.originalTransactionId],
    )).rows[0];
    if (!owner) return finish('awaiting_binding');
    if (owner.account_id === null) return finish('account_deleted', owner.id);
    if (owner.account_id !== account.id) return finish('ownership_conflict', owner.id);

    const existing = (await tx('SELECT * FROM subscriptions WHERE ownership_id = $1', [owner.id])).rows[0];
    if (existing) {
      if (existing.transaction_signed_at && !options.versions) return finish('version_conflict', owner.id);
      if (options.versions && existing.transaction_signed_at) {
        // Independent fences: max(signedDate) alone loses renewal/transaction order.
        // A newly re-signed OLD paid period must not replace a later transaction.
        const purchase = Date.parse(state.purchasedAt) - existing.purchased_at.getTime();
        const transaction = Date.parse(options.versions.transaction) - existing.transaction_signed_at.getTime();
        const renewal = Date.parse(options.versions.renewal) - existing.renewal_signed_at.getTime();
        if (purchase < 0 || (state.transactionId === existing.latest_transaction_id && transaction < 0)
            || renewal < 0) return finish('stale', owner.id);
        if (purchase === 0 && state.transactionId !== existing.latest_transaction_id) return finish('version_conflict', owner.id);
        if (state.transactionId === existing.latest_transaction_id && transaction === 0 && renewal === 0) {
          return finish(existing.snapshot_hash === hash ? 'replay' : 'version_conflict', owner.id);
        }
      } else {
        // Historical Phase 1 rows have only the original combined fence.
        const incomingTime = Date.parse(state.signedAt);
        const storedTime = existing.signed_at.getTime();
        if (incomingTime < storedTime) return finish('stale', owner.id);
        if (incomingTime === storedTime) {
          return finish(existing.snapshot_hash === hash ? 'replay' : 'version_conflict', owner.id);
        }
      }
    }
    const subscription = (await tx(
      `INSERT INTO subscriptions
        (ownership_id, account_id, environment, product_id, latest_transaction_id, status,
         purchased_at, expires_at, grace_period_expires_at, revoked_at, auto_renew_status, signed_at, snapshot_hash,
         transaction_signed_at, renewal_signed_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
       ON CONFLICT (ownership_id) DO UPDATE SET
         product_id = EXCLUDED.product_id, latest_transaction_id = EXCLUDED.latest_transaction_id,
         status = EXCLUDED.status, purchased_at = EXCLUDED.purchased_at, expires_at = EXCLUDED.expires_at,
         grace_period_expires_at = EXCLUDED.grace_period_expires_at, revoked_at = EXCLUDED.revoked_at,
         auto_renew_status = EXCLUDED.auto_renew_status, signed_at = EXCLUDED.signed_at,
         snapshot_hash = EXCLUDED.snapshot_hash, last_verified_at = now(), updated_at = now(),
         transaction_signed_at = EXCLUDED.transaction_signed_at, renewal_signed_at = EXCLUDED.renewal_signed_at
       RETURNING id`,
      [owner.id, account.id, state.environment, state.productId, state.transactionId, state.status,
        state.purchasedAt, state.expiresAt, state.gracePeriodExpiresAt, state.revokedAt, state.autoRenew,
        state.signedAt, hash, options.versions?.transaction ?? null, options.versions?.renewal ?? null],
    )).rows[0];
    const grant = grantForSnapshot(state);
    await tx(
      `INSERT INTO entitlement_grants
        (account_id, environment, entitlement, source, subscription_id, enabled, valid_from, valid_until, revoked_at)
       VALUES ($1,$2,$3,'apple_app_store',$4,$5,$6,$7,$8)
       ON CONFLICT (subscription_id) DO UPDATE SET
         enabled = EXCLUDED.enabled, valid_from = EXCLUDED.valid_from, valid_until = EXCLUDED.valid_until,
         revoked_at = EXCLUDED.revoked_at, verified_at = now()`,
      [account.id, state.environment, grant.entitlement, subscription.id, grant.enabled,
        grant.validFrom, grant.validUntil, grant.revokedAt],
    );
    return finish('applied', owner.id);
  });
}

async function findEffectiveGrants(userId, environment) {
  userId = uuid.parse(userId);
  requireEnvironment(environment);
  return (await query(
    `SELECT g.entitlement, g.source, g.valid_until, g.verified_at, s.product_id, s.auto_renew_status
     FROM entitlement_grants g
     JOIN subscription_accounts a ON a.id = g.account_id AND a.environment = g.environment
     JOIN subscriptions s ON s.id = g.subscription_id AND s.environment = g.environment
     WHERE a.user_id = $1 AND g.environment = $2
       AND g.enabled AND g.revoked_at IS NULL AND g.valid_from <= now() AND g.valid_until > now()
     ORDER BY g.valid_until DESC, g.id`,
    [userId, environment],
  )).rows;
}

async function lookupOwnership(environment, originalTransactionId) {
  requireEnvironment(environment);
  return (await query(`SELECT o.*, a.user_id FROM subscription_ownership o
    LEFT JOIN subscription_accounts a ON a.id=o.account_id AND a.environment=o.environment
    WHERE o.provider='apple_app_store' AND o.environment=$1 AND o.original_transaction_id=$2`,
  [environment, originalTransactionId])).rows[0] ?? null;
}

async function recordNotification(environment, notice, requestHash, terminal = null) {
  requireEnvironment(environment);
  return withTransaction(async (tx) => {
    const owner = notice.tx ? (await tx(`SELECT o.*, a.user_id FROM subscription_ownership o
      LEFT JOIN subscription_accounts a ON a.id=o.account_id AND a.environment=o.environment
      WHERE o.environment=$1 AND o.original_transaction_id=$2`,
    [environment, notice.tx.originalTransactionId])).rows[0] : null;
    // Link only the audit (NOT ownership) to a verified token so early notices are erased on deletion.
    const tokenAccount = !owner && notice.tx ? (await tx(`SELECT id, user_id FROM subscription_accounts
      WHERE environment=$1 AND app_account_token=$2`, [environment, notice.tx.appAccountToken])).rows[0] : null;
    const userId = owner?.user_id || tokenAccount?.user_id;
    let userExists = false;
    if (userId) userExists = Boolean((await tx('SELECT id FROM users WHERE id=$1 FOR UPDATE', [userId])).rowCount);
    if (notice.tx) await tx('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',
      [environment + ':' + notice.tx.originalTransactionId]);
    // Recheck after the account lock: deletion may have won the race.
    const current = notice.tx ? (await tx(`SELECT * FROM subscription_ownership
      WHERE environment=$1 AND original_transaction_id=$2 FOR UPDATE`,
    [environment, notice.tx.originalTransactionId])).rows[0] : null;
    if (current && current.account_id === null) return { result: 'account_deleted' };
    // A concurrent first binding will retry registration using the account lock order.
    if (current && current.account_id !== owner?.account_id) throw new Error('ownership changed; retry');
    const row = (await tx(`INSERT INTO subscription_events
      (environment,event_kind,request_hash,notification_uuid,notification_type,subtype,
       original_transaction_id,signed_at,result,processed_at,account_id,ownership_id,
       transaction_id,transaction_purchased_at,transaction_signed_at,renewal_signed_at)
      VALUES ($1,'notification',$2,$3,$4,$5,$6,$7,$8,CASE WHEN $9 THEN now() END,$10,$11,$12,$13,$14,$15)
      ON CONFLICT (environment,notification_uuid) DO NOTHING RETURNING *`,
    [environment, requestHash, notice.uuid, notice.type, notice.subtype,
      notice.tx?.originalTransactionId ?? null, notice.signedAt,
      terminal || (current ? 'retry_pending' : 'awaiting_binding'), Boolean(terminal),
      current?.account_id ?? (userExists ? tokenAccount?.id : null) ?? null,
      current?.id ?? null, notice.tx?.transactionId ?? null,
      notice.tx ? new Date(notice.tx.purchaseDate) : null, notice.tx ? new Date(notice.tx.signedDate) : null,
      notice.renewal ? new Date(notice.renewal.signedDate) : null])).rows[0];
    if (row) return row;
    const existing = (await tx('SELECT * FROM subscription_events WHERE environment=$1 AND notification_uuid=$2',
      [environment, notice.uuid])).rows[0];
    if (existing.request_hash !== requestHash) return { result: 'event_conflict' };
    return { ...existing, duplicate: true };
  });
}

async function recordNotificationFailure(id, code) {
  // No error.message/raw response/JWS is persisted. Successful concurrent delivery wins.
  if (!/^[A-Z_]{1,80}$/.test(code)) code = 'APPLE_PROCESSING_UNAVAILABLE';
  await query(`UPDATE subscription_events SET attempts=attempts+1,last_error_code=$2,
    result='retry_pending' WHERE id=$1 AND processed_at IS NULL`, [id, code]);
}

async function pendingNotifications(environment, originalTransactionId) {
  return (await query(`SELECT id FROM subscription_events WHERE environment=$1
    AND original_transaction_id=$2 AND processed_at IS NULL ORDER BY received_at LIMIT 100`,
  [requireEnvironment(environment), originalTransactionId])).rows;
}

module.exports = { getOrCreateAccount, applyVerifiedSnapshot, findEffectiveGrants,
  lookupOwnership, recordNotification, recordNotificationFailure, pendingNotifications };
