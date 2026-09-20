# Reliable Upload production deployment: 2026-09-21

Explicit user authorization covered production backup, migrations and deployment.
Completed at 2026-09-20T20:52:09Z (2026-09-21 04:52:09 Asia/Shanghai).

## Deployed state

- Host: api.youxugarden.com; actual production database: reader_dev.
- Backend advanced from 18447ec to
  186d60adac114c45ab5452a156cac05e313ee05a by fast-forward.
- Additional deployed patch: backend/src/server.js skips automatic full
  schema.sql initialization in production. Development/test startup is unchanged.
  Previously every restart called initSchema, exceeding the approved migration
  scope. The guard and its three passing tests exist in the local workspace and
  production checkout but have NOT been committed or pushed. Preserve/include
  them in the next approved commit. No dependency upgrade was necessary.
- Migrations applied explicitly in order: 003, 004, 005, 006.
  003 ran in an explicit transaction with a five-second lock wait and 60-second
  statement timeout; 004-006 used their existing transaction boundaries.
- PM2 reader-backend restarted with NODE_ENV=production and saved. Health reports
  status=ok, env=production through both localhost and public HTTPS.

## Backup and preservation

Protected server-side directory (mode 0700):
/home/ubuntu/backups/zhidu/reliable-upload-20260921

- production-before.dump: full custom-format PostgreSQL backup, 329145 bytes,
  mode 0600. Kept on the server, not copied to the repository or printed.
- backend.env.backup: exact protected copy of existing production configuration.
- backend-before.tar.gz: old application code excluding .env, modules and uploads.
- manifest.json: private verification metadata, migration results and checksums.

Stopped the sole old backend and verified no other client DB sessions remained
before the final backup. Fully restored the backup into a uniquely named temporary
database on the server. Compared counts and content fingerprints of all 45
original public tables. Applied 003-006 to the restored REAL data and checked
preservation before applying any production migration.

After production migrations and again after restart, all 45 original tables
matched the baseline, excluding only the intentionally added user_entries
updated_at/client_entry_id fields from the comparison. The new ledger began
empty; no artificial historical events were inserted. All five new state/ledger
tables and the two required unique indexes were verified.

The existing production .env digest matched before and after deployment. No
database password, JWT/MCP secret, token or user content was printed. No MCP
token was generated, regenerated or revoked. No phone data, revision, pending
operation or account was changed by this deployment.

Temporary restore database zhidu_prod_restore_20260921_test was removed only
after verification and after confirming zero remaining connections. Full backup
and verification manifest remain. Do not remove the backup during acceptance.

## Verification and limits

- Production startup guard: 3/3 tests passed; npm run check passed on the host.
- Public HTTPS /api/health: 200, production environment.
- Unauthenticated public versioned trace PUT, versioned progress PUT and book
  permanent DELETE: 401, demonstrating routes now reach authentication rather
  than the old 404. These probes changed no data.
- Public /mcp without a token: 401 as required.
- Deployed MCP handler against the isolated restored database: modern
  2026-07-28 server/discover, tools/list (five tools), and list_books passed using
  a synthetic clone-only account and injected internal auth context. This was
  NOT a public bearer-authenticated client session. No original user content
  was read through this test. The standalone test initially lacked JWT config;
  supplying an ephemeral test-only secret fixed the harness, not the application.
- New production error-log bytes: one existing SDK responseMode/json warning,
  zero unexpected error lines at final verification. Historical log errors were
  not erased and are not part of this fresh-error count.
- No iOS build, Git commit or push occurred.

## Next client step

The backend is ready for the controlled single-user acceptance attempt, but the
original phone queue has NOT yet been observed uploading successfully. Public
MCP authenticated discovery/tools with the user's existing token also remains
an end-to-end acceptance check; an unauthenticated 401 is not proof of that.

Next, with separate approval, commit the Xiaou local-read fix plus startup guard,
select an unused iOS build number, and build for the verified production API
origin. Omit ENABLE_LOCAL_SYNC_DIAGNOSTICS or set it false to restore normal
business UI and uploads. This intentionally unfreezes the queue. Preserve the
diagnostic evidence, original account, bundle identity and app container; upgrade
in place, never uninstall. Verify the original five traces, deduplication, pending
clearance and PostgreSQL/MCP visibility.

Legacy unversioned clients still receive 428. No compatibility bypass was added.
Do not roll back to unversioned backend writers or drop revision/tombstone state
after accepting new uploads. Pause writes and fix forward if acceptance fails.
