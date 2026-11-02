# Zhidu Sync Phase 1: Authorization and Read-only Export

This phase implements the backend only. No Obsidian plugin UI, templates,
production deployment, upload protocol changes, or new ledger are included.
All examples below target a disposable local database, never production.

## Authorization boundary

- Client: `zhidu-sync`; only scope: `obsidian.sync.read`.
- Authorization code: 256-bit random, one use, five minutes, bound to exact
  client ID, redirect URI, S256 PKCE challenge, user and App session version.
- Integration access token: separate 256-bit random opaque credential, 24-hour
  lifetime; neither an App JWT nor an MCP token. Only SHA-256 hashes are stored.
- There is no refresh token in this minimal phase. Reauthorize after expiry.
  Long-running unattended plugin use will need a separately reviewed renewal UX.
- The client generates a cryptographically random verifier and state. It checks
  callback state, then exchanges the code with its verifier. Never ship a client
  secret in a plugin. A future plugin stores integration secrets in Obsidian
  SecretStorage, not settings JSON.
- App JWT is accepted only for consent. The authorization page obtains it via
  existing email/password login and retains it in page memory only. It is never
  passed to the plugin. Apple-only browser login is not implemented in this phase.
- Redirects must exactly match the server allowlist. Default is
  `obsidian://zhidu-sync`; loopback HTTP is permitted only outside production.
- Revocation affects only the supplied integration grant and clears its export
  cache. Account removal cascades; banned accounts cannot exchange or use tokens.
  App logout does not revoke already-issued independent integration grants.

## Migration and configuration

Apply `backend/src/db/migrations/007_obsidian_sync.up.sql` after migrations
001-006. It adds four tables and their indexes, without changing existing tables:

| Table | Important columns |
| --- | --- |
| obsidian_authorization_codes | code_hash, user_id, session_version, client_id, redirect_uri, code_challenge, scope, expires_at, used_at, created_at |
| obsidian_grants | id, user_id, token_hash, scope, expires_at, revoked_at, created_at |
| obsidian_sync_snapshots | id, grant_id, phase, after_sequence, watermark, completed_at, expires_at, created_at |
| obsidian_sync_snapshot_items | snapshot_id, ordinal, change (whitelisted JSONB DTO) |

The last two are short-lived export caches, not another change ledger. They do
temporarily contain exported reading text. TTL is 30 minutes. Expired caches
cannot be read; run `npm run obsidian:cleanup` in the intended environment every
five minutes for physical removal, as well as the request-time cleanup. No job
is installed automatically. Revoked grants are retained as minimal audit state.

Migration 007 uses one transaction, a five-second lock timeout and a 60-second
statement timeout. It does not backfill business rows or historical changes.
Creating user foreign keys can briefly lock the users table. Retry after a lock
timeout during a quiet window. Identical reruns use IF NOT EXISTS; this is not a
schema-drift repair mechanism. Verify the actual deployed table definitions.
The test suite applies 007 twice after 001-006 and checks historical preservation.

Activation order: backup the target TEST database, apply 007, deploy the backend
with integration disabled, configure server-only values, enable and run smoke
tests. Existing upload and MCP routes do not depend on these new tables.

```dotenv
OBSIDIAN_SYNC_ENABLED=true
OBSIDIAN_SYNC_CURSOR_SECRET=<independent random secret of at least 32 characters>
OBSIDIAN_SYNC_REDIRECT_URIS=obsidian://zhidu-sync,http://127.0.0.1:9876/callback
```

The loopback callback above is for local smoke testing only. Production should
use only the approved plugin URI/HTTPS redirects and HTTPS termination. Keep a
stable cursor secret on all instances; rotation invalidates existing cursors.
No database password or server secret belongs in Flutter or the future plugin.
Rollback: disable the integration; old backend/upload behavior continues. Do not
drop tables during normal rollback: dropping them destroys grants and snapshots
and requires users to reconnect. No automatic destructive down migration exists.

## HTTP contract

All paths below start with `/api/integrations/obsidian`. JSON is used unless noted.

| Method/path | Credential | Result |
| --- | --- | --- |
| GET /authorize | none | Browser login/consent page; validated OAuth query |
| POST /login | email/password | Existing App session for browser memory only |
| POST /authorize | App JWT | JSON redirect_uri containing code/state, or denial |
| POST /token | code and PKCE verifier | Independent integration access token |
| GET /status | integration Bearer | connected, scope, expires_at |
| POST /revoke | integration Bearer | Idempotent 204; works for expired/revoked tokens |
| GET /sync | integration Bearer | Paginated snapshot or incrementals |

Authorization query (POST consent uses the same properties plus `allow: true`):

```json
{
  "response_type": "code",
  "client_id": "zhidu-sync",
  "redirect_uri": "obsidian://zhidu-sync",
  "scope": "obsidian.sync.read",
  "code_challenge_method": "S256",
  "code_challenge": "<base64url SHA256(verifier), 43 characters>",
  "state": "<32-128 random URL-safe characters>"
}
```

The browser receives `{"redirect_uri":"obsidian://zhidu-sync?state=...&code=..."}`.
The client validates state before exchanging. Token request (JSON or form):

```json
{
  "grant_type": "authorization_code",
  "client_id": "zhidu-sync",
  "redirect_uri": "obsidian://zhidu-sync",
  "code": "<one-time authorization code>",
  "code_verifier": "<original random 43-128 character verifier>"
}
```

Response: `{"access_token":"<secret>","token_type":"Bearer","expires_in":86400,"scope":"obsidian.sync.read"}`.
Do not print or persist this response in build logs. Consent rejects client
user_id, unapproved scopes and redirects. Integration Bearer is not accepted by
App write routes. App JWT and MCP token are not accepted by /sync.

First request: `GET /api/integrations/obsidian/sync?limit=50` with integration
`Authorization: Bearer <access_token>`. Default limit is 50, maximum 100;
invalid limits are rejected, not silently expanded. Example, synthetic values:

```json
{
  "schema_version": 1,
  "phase": "snapshot",
  "watermark": "42",
  "next_cursor": "<opaque signed cursor>",
  "has_more": false,
  "changes": [{
    "entity_type": "book",
    "entity_id": "example-book-id",
    "operation": "created",
    "sequence": null,
    "version": "42",
    "data": {
      "book_id": "example-book-id", "title": "Example book",
      "author": null, "format": null, "in_library": false,
      "added_at": null, "last_opened_at": null,
      "created_at": null, "updated_at": null
    }
  }]
}
```

Next request: `GET /api/integrations/obsidian/sync?limit=50&cursor=<URL-encoded next_cursor>`.
An unchanged second sync has `phase: incremental`, `changes: []`, `has_more: false`.
An incremental item has operation created/updated/deleted and its last actual
ledger `sequence` as a decimal string. Deleted items have `data: null`.
`version` is the export watermark, not the Flutter client revision. IDs are
server-stable IDs, never filenames; all BIGINT values stay strings.

DTOs:

- book: book_id, title, author, format, in_library, added_at, last_opened_at,
  created_at, updated_at. Book IDs include the union of bookshelf, eligible
  traces and progress. Removed books remain representable via history; title may
  come from their latest nonempty trace book_title. Unknown author/format is null.
- reading_progress: id, book_id, progress, chapter_index, scroll_offset, cfi,
  created_at, updated_at. Ledger identity is the progress UUID, not book_id.
- trace: id, type, book_id, book_title, chapter_index, chapter_title, excerpt,
  note, explanation, tags (auto_tags), is_important, created_at, updated_at.
  Types: highlight, thought, ai_explanation, ai_question. No new tagging entity.
- Never export free_notes, complete conversations/followups, manual/unbound
  entries, arbitrary metadata, auto_summary, file paths, cover paths or account
  fields. Deleted trace tombstones only contain ledger ID/type: the old source
  subtype is not recoverable from the index-only ledger. Ignore unknown IDs.

## Snapshot and cursor correctness

Each new export transaction uses REPEATABLE READ to observe canonical state and
`sync_user_cursors.last_sequence = H` together. It materializes only whitelisted
DTOs and commits before serving HTTP pages. A writer invisible to that snapshot
will have a later committed per-user sequence and be returned by the subsequent
incremental. This relies on the existing per-user transactional sequence, not
the unsafe global BIGSERIAL allocation order.

Page cursors seek `ordinal > previous` within this immutable snapshot. This is
keyset traversal of a frozen export, not an offset into changing business data.
Final-page cursor carries H. Incremental exports read existing
`sync_changes.user_sequence > H AND <= new_watermark`, folding each entity to
its final state in the same database snapshot. There is no promise of historical
intermediate values: the ledger stores IDs, not old text payloads.

Bootstrap items use created with sequence null; apply them as idempotent upserts.
Do not append duplicate notes for created, or require a preexisting note for
updated. Persist a new cursor only after applying its local batch successfully.
First-page retries reuse the same live export. Final pages also remain replayable
until TTL. New changes are picked up after that export's final cursor.

Book removal produces an updated `in_library:false` book if history remains;
it never deletes its traces/progress. Permanent deletion emits their real ledger
tombstones. A trace-only incremental can reference a historical book not in the
client's map; the future plugin must create a grouping from trace.book_id/title.
If an already-archived book loses its last trace, there is no new canonical book
delete event. Do not infer a command to delete the user's book note. Derivative
book metadata is not a new independently versioned business entity.

Limits: 50,000 entities / 32 MiB per export; 64 MiB total cached payload per user;
three active paged exports per user; 15-second statement timeout. Rate limits
use existing backend storage. Concurrent export creation returns sync_busy;
uploads never take the separate export advisory lock.

Errors: 400 invalid_request/invalid_cursor; 401 invalid_token; 409 sync_busy or
resync_required; 410 snapshot_expired; 413 export_too_large; 429 rate_limited,
too_many_snapshots or export_cache_full; 503 integration_unavailable/retry_later.
Back off on transient failures. On 410 restart a full snapshot without deleting
existing user notes. On token expiry reauthorize and bootstrap with the new grant.
Ledger retention has not changed; any future ledger GC must add a cursor floor.

## Reproducible local validation (PowerShell)

The PostgreSQL test suite DESTROYS AND RECREATES public ONLY in the explicitly
named `zhidu_obsidian_phase1_test` localhost database. It refuses other targets.
Never repoint it at production or the device acceptance database. The current
machine already has this separate database on 127.0.0.1:55440.

From `backend`:

```powershell
$env:TEST_DATABASE_URL='postgresql://postgres@127.0.0.1:55440/zhidu_obsidian_phase1_test'
npm run test:obsidian
npm run test:obsidian:postgres
npm run check:obsidian
```

This runs real HTTP authorization, token exchange, first snapshot, App-side
business mutation, incremental read, revoke/401, isolation and concurrent writers.
It also prepares schema 001-007 and synthetic fixtures in that disposable DB.
Do not rerun destructive tests while manually testing against this same DB.

Start the optional local-only server in a separate terminal:

```powershell
$env:OBSIDIAN_TEST_DATABASE_URL='postgresql://postgres@127.0.0.1:55440/zhidu_obsidian_phase1_test'
npm run obsidian:test-server
```

It binds 127.0.0.1:3002 only, checks database identity, does not apply migrations,
and generates in-memory test signing keys without printing them. Restarting this
helper invalidates App sessions/cursors; reconnect. This is not a production
launcher. `/api/health` identifies `obsidian-local-test`, production:false and the
dedicated database. If port 3002 is occupied, set OBSIDIAN_TEST_PORT and use the
same port as OBSIDIAN_TEST_BASE_URL for the smoke helper. No Funnel/DNS changes.

Create an email/password TEST account through existing /api/auth/register if
needed. Use a new synthetic address and a test-only password, never real account
credentials. Do not display the registration response, which contains an App JWT.
For a manual browser-only check this account may start with an empty library.

For example, against the local-only server (both values below are disposable
fixtures, not real credentials; skip registration if the account already exists):

```powershell
$body=@{email='obsidian-local@example.invalid';password='Local-test-only-Change-42!'} | ConvertTo-Json
$null=Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:3002/api/auth/register' -ContentType 'application/json' -Body $body
```

In another terminal:

```powershell
$env:OBSIDIAN_TEST_BASE_URL='http://127.0.0.1:3002'
npm run obsidian:smoke
```

1. Open the printed authorization link in a browser on THIS computer. The helper
   owns http://127.0.0.1:9876/callback and stores verifier/state only in memory.
2. Sign in with the local test account, inspect scope, click Allow. The browser
   returns to the local callback; the helper checks state and exchanges the code.
3. Inspect terminal counts for Initial snapshot and Unchanged incremental. No
   changes between reads should yield zero incremental changes.
4. With an App/test API client targeting this SAME local backend and account,
   create/update/delete one test trace through the existing upload protocol.
   Do not change revision fields manually in PostgreSQL. Wait for upload success.
5. Press Enter in the helper. Incremental after upload shows the corresponding
   entity/operation counts, without dumping private reading text or tokens.
6. The helper revokes its grant and verifies 401, then exits. Failed runs attempt
   revocation; a network failure can leave a token valid until its 24-hour expiry.

The automated PostgreSQL HTTP test already exercises step 4 without requiring a
new Flutter build. This local-only URL is not directly reachable from an iPhone.
For a shared test server, apply the same migration/config to a separately
confirmed non-production environment; that deployment is NOT performed here.

## Security and deferred work

- Reading queries take user identity only from the authenticated integration.
  Cursors are signed and grant-bound; SQL always filters authenticated user_id.
- No raw request headers, passwords, tokens, codes or reading bodies in logs.
  Reverse proxies must redact Authorization and callback code query strings.
  The consent page uses no third-party scripts, no storage and no-referrer/CSP.
- Snapshot cache contains personal reading data: restrict DB/backups, schedule
  physical TTL cleanup, revoke to remove it immediately.
- Pre-auth rate limits currently use the socket address, not untrusted XFF.
  Behind a reverse proxy users can share a bucket; configure trusted-proxy-aware
  rate limits before a broad rollout, without trusting arbitrary forwarded IPs.
- Apple browser auth, refresh/renewal, account-side grant management, plugin
  SecretStorage, Vault writes, managed regions and automatic sync are deferred.
- No source from the referenced WeRead plugin was copied in this phase.

## Changed files

Existing files: `backend/.env.example`, `backend/package.json`,
`backend/src/app.js`, `backend/src/db/schema.sql`.

New files:

- `backend/src/db/migrations/007_obsidian_sync.up.sql`
- `backend/src/services/obsidianProtocol.service.js`
- `backend/src/services/obsidianProtocol.service.test.js`
- `backend/src/repositories/obsidianAuth.repository.js`
- `backend/src/repositories/obsidianSync.repository.js`
- `backend/src/repositories/obsidian.postgres.test.js`
- `backend/src/routes/obsidian.routes.js`
- `backend/src/routes/obsidian.routes.test.js`
- `backend/src/views/obsidian-authorize.html`
- `backend/src/views/obsidian-authorize.js`
- `backend/scripts/obsidian-test-server.js`
- `backend/scripts/obsidian-smoke.js`
- `backend/scripts/obsidian-cleanup.js`
- `docs/zhidu-sync-phase1.md`

Unrelated existing logo, Flutter, localization and platform-generated edits are
outside this change and have not been reverted, committed or included as work
performed by this phase.
