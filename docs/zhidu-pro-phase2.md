# Zhidu Pro Phase 2: Apple server infrastructure

Implementation/regression: 2026-10-04; closeout review: 2026-10-08. Backend only. No commit, push, production deployment, real purchase,
Flutter purchase UI, StoreKit client, or iOS deployment-target change in this phase.

**Phase 2 server infrastructure implemented; real Sandbox / TestFlight validation pending Apple account readiness.**

## 审阅摘要

本阶段仅实现订阅后端：Apple 官方验签、交易查询、V2 通知、幂等与乱序保护、
通用 Pro 权益、账号归属及删除保护、主动对账服务。没有接入 Flutter 购买，也没有上线。
2026-10-08 重新运行 Apple 验签/API/HTTP 测试，17 项通过，并确认临时 PostgreSQL
已停止运行。下方完整 PostgreSQL、Flutter、Obsidian 回归结果来自 2026-10-04 的实跑，
不是今天重新执行的全部测试。真实 Apple 凭据、证书在线检查、通知投递和购买尚待验收。
默认功能开关关闭；对账服务已提供，但生产定时调度和审计保留周期还需上线前落实。

## 1. Scope and files

Added:

- `backend/src/config/appleIap.js`
- `backend/src/services/appleIapError.js`
- `backend/src/services/appleTransactionVerifier.js`
- `backend/src/services/appleServerApi.js`
- `backend/src/services/appleSubscription.service.js`
- `backend/src/routes/appleSubscriptions.routes.js`
- `backend/src/db/migrations/009_apple_subscription_verification.up.sql`
- `backend/src/db/migrations/009_apple_subscription_verification.down.sql`
- `backend/src/services/appleVerification.test.js`
- `backend/src/routes/appleSubscriptions.routes.test.js`
- `backend/src/repositories/appleSubscription.postgres.test.js`
- `backend/test-support/appleSignedFixtures.js`
- This report.

Modified: `backend/src/repositories/subscription.repository.js`, `backend/src/db/schema.sql`,
`backend/src/app.js`, `backend/.env.example`, `backend/package.json`, `backend/package-lock.json`.
The existing repository tracks some `backend/node_modules` files: npm also updated its
generated lockfile and `hasown` to 2.0.4, required by the new SDK's transitive dependency.
No unrelated existing changes were reverted; Phase 1/Obsidian and pre-existing client/icon
work in the dirty workspace is not newly implemented Phase 2 work.

## 2. Official library and trust boundary

Pinned **`@apple/app-store-server-library` 3.1.0** and lockfile integrity. Apple maintains
the JWS/certificate verification, API bearer signing and response validators. Its documented
Node minimum is 16; this backend requires >=20 and was tested with Node 24.15.0.
No project-wide runtime upgrade. Dependencies installed with lifecycle scripts disabled.

`AppleTransactionVerifier` calls the official `SignedDataVerifier` methods for the outer
V2 notification, transaction AND renewal JWS. Runtime always enables online certificate
revocation/expiry checks. Roots are configured public Apple PKI DER files, not certificates
accepted from a request. No environment flag disables verification. Only Sandbox/Production
are accepted, never the SDK's signature-bypassing Xcode/LocalTesting modes.

After signature verification, strict validation requires the configured bundle/environment,
known Pro product, numeric transaction identifiers, UUID appAccountToken, auto-renewable
purchase type, PURCHASED ownership, and valid dates. Missing tokens and family-shared
purchases are not silently assigned. Renewal must match the transaction's chain/product
and token when present. Production additionally checks numeric appAppleId on notifications
and status responses. Transaction JWS itself does not have an appAppleId field.

`AppleServerApi` uses the official client to fetch transaction info and all subscription
statuses. Its transport override adds a 30-second abort and disables redirects; official
request signing/response validation remain unchanged. Version 3.1.0 selects
`api.storekit-sandbox.apple.com` / `api.storekit.apple.com`; no hand-built Apple API origin.
OCSP uses the official verifier's bounded transport. Temporary errors are sanitized 503s,
not FREE. No raw JWS, private key, full transaction or Apple response is logged.

## 3. Verification flow and endpoints

All paths below are new. Default `APPLE_IAP_ENABLED=false`; credentials are checked lazily,
so unavailable Apple configuration does not prevent existing login/reading/sync startup.

| Endpoint | Authentication | Input / result |
| --- | --- | --- |
| POST `/api/subscriptions/apple/purchase-context` | Existing App JWT, active account/token version | `{}` -> stable appAccountToken, environment, productIds |
| POST `/api/subscriptions/apple/verify` | Same App JWT | Exactly `{transactionId}` OR `{signedTransactionInfo}` -> result plus server entitlement |
| GET `/api/me/entitlements` | Same App JWT | No environment/user query override; server-owned environment |
| POST `/api/apple/notifications` | Apple JWS, not App JWT | `{signedPayload}` -> sanitized processing result |

Authenticated endpoints derive user_id exclusively from the existing auth middleware.
MCP/Obsidian tokens are not accepted as App JWTs; their existing protocols are unchanged.
Responses are no-store. Routes have bounded JSON parsing, existing DB-backed rate limits,
and a sanitized error boundary before the application's general 8 MB parser.

Example verification body (identifier is illustrative, not a real transaction):

```json
{"transactionId":"1000000000000001"}
```

After obtaining a verified transaction, the service queries Apple's **current subscription
chain status**; an old receipt/device success flag cannot grant Pro by itself. It builds the
internal Phase 1 snapshot, validates ownership, then atomically writes subscription,
entitlement grant and audit completion. No Apple HTTP call runs while holding DB write locks.

Example successful server response shape:

```json
{
  "result": "applied",
  "environment": "Sandbox",
  "tier": "PRO",
  "pro": {
    "active": true,
    "source": "apple_app_store",
    "productId": "com.youxugarden.zhreader.pro.monthly",
    "expiresAt": "2026-11-04T00:00:00.000Z",
    "autoRenew": true,
    "verifiedAt": "2026-10-04T00:00:00.000Z"
  }
}
```

Product IDs remain centrally defined in Phase 1 config. Bundle ID is intentionally
`com.youxugarden.zhireader`; agreed products are `com.youxugarden.zhreader.pro.monthly`
and `com.youxugarden.zhreader.pro.yearly`, group `Zhidu Pro`.

## 4. Notifications and entitlement rules

The eight requested V2 type names remain valid in the pinned official library. Types are
**reconciliation signals**, not instructions to blindly overwrite or toggle Pro:

| Notification | Processing |
| --- | --- |
| SUBSCRIBED / DID_RENEW | Query current chain; apply latest verified paid period |
| DID_CHANGE_RENEWAL_STATUS | Update current autoRenew; cancellation alone does not disable grant |
| DID_FAIL_TO_RENEW | Use current Apple status: paid remainder, actual grace, or expired retry |
| GRACE_PERIOD_EXPIRED / EXPIRED | Use current chain; do not override a later renewal |
| REFUND / REVOKE | Verified current-period revocation disables grant; old-period refund cannot revoke a newer paid transaction |
| REFUND_REVERSED / RENEWAL_EXTENDED / DID_CHANGE_RENEWAL_PREF / OFFER_REDEEMED | Reconcile current chain as well |
| TEST | Signature/identity validated; audit only |
| Unknown / other types | Signature validated, whitelist metadata audited as ignored; no grant mutation |

Apple API status 1/2/3/4/5 maps to active/expired/billing_retry/grace_period/revoked.
Verified revocationDate always prevents a grant. A status claiming revoked without the
required verified revocation evidence is deferred, not guessed. Upgraded/ambiguous or
missing current chain responses also fail closed and can be reconciled later.

Entitlement query combines valid grants for the authenticated user and deployment environment.
The DB checks `enabled`, no revocation, valid_from <= now < valid_until. Active/retry grants
cannot exceed verified expires_at; only actual grace status uses the verified grace deadline.
An expired chain cannot cancel another valid grant. No network failure updates a grant to FREE.
Time-based expiry still applies during outages: this phase does not invent unlimited offline
entitlements or a guessed grace extension. Client cache/refresh behavior remains Phase 3.

## 5. Idempotency, order and transaction boundaries

- Verified notification identity is `(environment, notificationUUID)`. Store only the SHA256
  of signedPayload for replay identity, never raw JWS. Same UUID/different payload -> 409.
- Notification receipt is durably registered first. Subscription/grant mutation and audit
  completion then share one business transaction. Failure rolls them back and retains a
  pending receipt with bounded error code/attempt count; return 503 for delivery retry.
- Unknown ownership is audited as awaiting_binding and ACKed without automatically creating
  a user, ownership or Pro grant. Reconciliation after explicit binding can process it.
- Processing fetches current Apple state rather than applying the old notification payload.
  Independent transaction/renewal signedDate fences are persisted, not only their maximum.
- Earlier paid purchaseDate cannot replace a later transaction even if re-signed today.
  A new transaction with a later purchaseDate is stronger evidence than the old transaction's
  re-signing time. The renewal fence must still not regress. Equal-date different transaction
  identities or equal-version conflicting state are deferred for reconciliation.
- Pending events retain minimal transaction ID/purchase/signature and renewal signature
  fences. Reconciliation cannot ACK an event that is newer than the API state fetched.
- User -> account -> chain lock ordering and user-scoped transactions serialize claims and
  account deletion. Chain advisory locks also cover orphan registration and deletion cleanup.
- No mutations of sync_changes, user_sequence, reader data or Obsidian ledger.

## 6. Ownership and account deletion

Phase 1 unique `(provider, environment, original_transaction_id)` remains authoritative.
Stable per-user/per-environment random appAccountToken is returned for a future StoreKit
purchase; it is not the user's UUID/email. Authenticated verification must match that token.
Wrong-token/wrong-owner/retired-chain attempts return explicit 409 business errors and audit
safe results. No silent transfer; same user reinstall/device restore can use the existing chain.

Account deletion still erases token mapping, details, grants and associated audits, leaving
only the minimum retired ownership reservation, with no user ID/token mapping. 009 also
removes orphan audits for a chain once bound. Before binding, an audit whose verified token
matches an existing account is associated with that account solely for erasure, not ownership.
Truly unknown-token orphan metadata cannot identify a local user; operational retention/cleanup
policy for unclaimed audits should be finalized before production. No raw receipt/token is retained.
Deleting a Zhidu account does not cancel Apple's subscription; future client deletion UI must
explain the Apple management entry point. This backend never pretends to cancel billing.

## 7. Reconciliation

`getAppleSubscriptionService().reconcileAppleSubscription(originalTransactionId)` uses the
deployment's fixed environment, looks up existing ownership, asks Apple for current state,
and calls the SAME persistence path as verification/notifications. It cannot claim an unknown
chain or resurrect a retired account. Afterwards it processes up to 100 pending receipts for
that chain, each with the same version/transaction checks. Repeat for remaining pending rows.
No publicly exposed administrative reconcile endpoint and no cron were added.

Use this service from a trusted server job/admin task after temporary failures or missing
notifications. Before selling subscriptions, configure scheduling/monitoring for aged
last_verified_at and unprocessed events; otherwise webhook loss is only corrected when this
service is explicitly invoked. Do not rely on Sandbox delivery retries as a recovery scheduler.

## 8. Environment variables

All server-only; examples have no actual credentials:

| Variable | Purpose |
| --- | --- |
| APPLE_IAP_ENABLED | `false` by default; explicit activation only after migrations/configuration |
| APPLE_IAP_ENVIRONMENT | Exactly Sandbox or Production; TestFlight belongs to Sandbox |
| APPLE_IAP_BUNDLE_ID | Exact `com.youxugarden.zhireader` |
| APPLE_IAP_ISSUER_ID | ASC In-App Purchase key issuer UUID |
| APPLE_IAP_KEY_ID | API key identifier |
| APPLE_IAP_PRIVATE_KEY | Server secret, PEM with literal newlines or escaped `\n` |
| APPLE_IAP_APP_APPLE_ID | Numeric App Store app ID; mandatory in Production |
| APPLE_IAP_ROOT_CA_PATHS | Semicolon-separated absolute paths to official Apple PKI DER roots |

Separate Sandbox and Production deployments/databases/credentials and HTTPS notification URLs.
DB composite keys/FKs additionally isolate collisions even when testing both environments in
one fixture schema. No client/body/query can select an environment. These credentials are
separate from existing Apple Sign In, JWT, MCP and Obsidian secrets.

## 9. Migration 009 / rollout

No second subscription model/table family. 009 adds:

- subscriptions: transaction_signed_at, renewal_signed_at, both-null-or-both-present constraint.
- subscription_events: original_transaction_id, signed_at, transaction_id,
  transaction_purchased_at, transaction_signed_at, renewal_signed_at, attempts, last_error_code.
- Event-kind/result constraints extended for reconciliation, retry_pending, ignored, test.
- Pending chain index; account-erasure trigger updated to remove linked orphan audits and
  share chain locks with writers. Existing unique/FK environment constraints remain intact.

DDL also appears identically in fresh schema.sql. 001-008 unchanged. Additive/repeatable up,
transactional with lock/statement timeouts, no historical backfill. Down refuses while
subscriptions/events exist: never discard ordering/audit evidence. Prefer disabling the new
feature while retaining schema/data if rolling back application code.

Apply 009 after 008 while IAP stays disabled, then deploy backend, configure public Apple roots
and credentials, verify separate test endpoint, and only then enable the intended environment.
No migration/deployment/configuration was performed on production or the user's acceptance DB.

## 10. Tests and regression

Synthetic crypto fixtures generate ephemeral EC root/intermediate/leaf certificates with the
Apple certificate extension OIDs. The **actual official verifier** checks signatures, chains,
bundle/environment, and certificate dates. Test-only injected verifier disables live OCSP
because these roots are synthetic; runtime has no such switch. Invalid signature/untrusted
root/expired certificate tests are real cryptographic rejections. The SDK API bearer signing
and environment hosts are also tested with a generated temporary API key.

Real PostgreSQL integration drives the actual verifier, service, repository, constraints and
transactions. Only the external Apple HTTP response is substituted with signed fixtures;
core subscription/grant/order decisions are not mocked.

| Run | Result |
| --- | --- |
| All backend non-PG tests | 78 pass, including 17 new crypto/API/HTTP tests |
| New Phase 2 real PG tests | 24 pass including parent test |
| Phase 1 subscription PG | 15 pass |
| Reliable Upload / ledger PG | 19 pass |
| Obsidian auth/PKCE/snapshot/incremental PG | 12 pass |
| npm check / check:subscriptions / check:apple-iap / check:obsidian / check:reliable-upload | Pass |
| Flutter harness default | Rerun 64 pass / 2 mode skips; serial confirmation also 64 pass / 2 skips |
| Flutter diagnostics-mode harness | 3 pass / 1 normal-mode skip |
| Root Flutter tests | 64 pass / 6 pre-existing SQLite asset-loading failures |
| Flutter analyze | Same baseline info at share_service.dart:64:43, async BuildContext, exit 1 |
| Obsidian plugin tests / typecheck | 20 pass / 2 existing external-server integration skips; typecheck pass |

The first harness run had 63 pass / 2 skip / 1 failure. The uncaptured/truncated first output
did not preserve enough detail to attribute that transient failure; both unchanged parallel
rerun and serial rerun passed. It is not silently counted as a clean first run or asserted to
be a proven pre-existing failure. No Flutter source/test changes were made to force a pass.
No new reproducible regression was found; the entire project is not claimed fully green.

All PG tests used the disposable 16.13 cluster at 127.0.0.1:55442, not existing port 55440.
Subscription tests create/remove only random schemas in zhidu_subscription_phase1_test;
old destructive fixtures run in the cluster's separate ledger/Obsidian fixture databases.
The temporary PostgreSQL server is stopped after the checks.

Coverage of the requested cases: valid transaction; invalid signature; wrong bundle; Sandbox;
Production; environment mismatch; SUBSCRIBED; DID_RENEW; cancellation; DID_FAIL_TO_RENEW;
grace; expiration; refund; revoke; concurrent duplicates; out-of-order/independent clocks;
unknown type; wrong owner; retired owner; token mismatch; Apple outage; DB rollback;
entitlement recalculation; orphan/unknown user. Additional tests cover erasure before binding,
pending-event recovery fences, request limits, active-session authentication and sanitized errors.

Re-run commands (backend directory; PG needs the isolated local test cluster):

```powershell
npm run test:apple-iap
$env:APPLE_IAP_TEST_DATABASE_URL='postgresql://postgres@127.0.0.1:55442/zhidu_subscription_phase1_test'
npm run test:apple-iap:postgres
npm run check:apple-iap
```

## 11. Pending real Apple validation

NOT verified: actual Apple-issued signing chains/OCSP reachability, real key permissions,
real products/prices/transactions, paid renewal/grace/refund/revocation, Apple's public V2
delivery/retry behavior, TestFlight, client purchase/finish/restore/reinstall flows.
Generated fixtures cannot certify any of these. No App Store Connect settings were changed.

After legal name/tax/Paid Apps Agreement and credentials are ready:

1. Configure isolated Sandbox backend, official PKI roots, ASC In-App Purchase server key,
   and real app ID. Verify V2 TEST delivery over public HTTPS; inspect safe audit UUID/result.
2. Complete Phase 3 client appAccountToken + StoreKit integration before purchase testing.
   Buy real Sandbox monthly and yearly products, submit transaction, verify server PRO and
   matching ownership/environment, with no client-supplied expiry/product authority.
3. Exercise accelerated renewal, cancel auto-renew while paid, real expiration, billing retry
   and configured grace. Compare Apple state, subscriptions and effective grants each time.
4. Test real refund/revoke and refund of an older period after a newer renewal. Confirm no
   early cancellation downgrade and no late-event rollback of a new paid period.
5. Replay notification UUIDs and reverse arrival order; verify one logical mutation. Block
   Apple/DB temporarily, restore, invoke reconciliation and confirm pending audits complete.
6. Test restore/reinstall/device change for same account; another account and deleted-account
   reclaim must fail with no second grant. Test a notification arriving before verification.
7. Send Sandbox evidence to the Production verifier: reject with no Production grant.
   TestFlight must show Sandbox in audit/state, not a third environment.
8. Before production activation, settle audit retention, reconcile scheduling/alerts, real
   certificate rotation/network monitoring, account deletion subscription notice, and all
   remaining client/paywall/App Store submission requirements from the overall plan.

## Official references

- [Apple-maintained Node server library](https://github.com/apple/app-store-server-library-node)
  for SignedDataVerifier, root certificates, online checks and official API client.
- [Apple PKI](https://www.apple.com/certificateauthority/) for public trust roots.
- [V2 notification types](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype)
  and [subscription status](https://developer.apple.com/documentation/appstoreserverapi/status).
- [Get all subscription statuses](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses).

Implementation stops here pending user review; no Phase 3 purchase client work started.
