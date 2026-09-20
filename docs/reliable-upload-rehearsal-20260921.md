# Reliable Upload pre-deployment rehearsal: 2026-09-21

## Scope

Production access was read-only: Git/process metadata, health, catalog queries,
aggregate counts, and a schema-only pg_dump with default_transaction_read_only.
No production rows were exported. No production migration, restart, deployment,
configuration update, commit, push, phone operation or pending consumption occurred.
No business code changed in this round. This document is the only new repository
file. Existing uncommitted Xiaou fixes and unrelated workspace changes remain.

## Verified production baseline

- Backend Git HEAD: `18447ec`; PM2 reader-backend PID: `3097749`.
- Local backend health: status `ok`, environment `production`.
- Actual database: `reader_dev`. Despite its name this is PRODUCTION.
- PostgreSQL: 16.14 (Debian); pg_dump client: 16.15.
- Existing migration files: 001 and 002 only.
- user_entries lacks updated_at and client_entry_id.
- sync_changes, sync_user_cursors, user_entry_upload_states,
  permanently_deleted_books and reading_progress_upload_states are absent.
- No ambiguous nonblank metadata.local_id groups were found by the aggregate
  preflight query. No individual user IDs, content or credentials were printed.
- Existing backend/.env is modified relative to Git. It was not overwritten;
  its contents' digest matched before and after the schema-only export. No
  digest or secret was printed.

Candidate backend is the unchanged backend at local HEAD
`186d60adac114c45ab5452a156cac05e313ee05a`, branch
`codex/reliable-upload-acceptance`. Xiaou UI fixes are still uncommitted and
must be included in a separately approved client build.

## Isolated rehearsal

Container: zhidu-device-acceptance-pg, PostgreSQL 16.15, loopback-only
127.0.0.1:55440. Created three NEW databases; preexisting names were rejected:

- zhidu_rollout_20260921_upgrade_test
- zhidu_rollout_20260921_restore_test
- zhidu_rollout_20260921_concurrency_test

The existing zhidu_device_acceptance_test database was not used or modified.
Database port exposure and Funnel configuration were not changed.

Restored the actual production schema (45 public tables) into the upgrade
database, then seeded synthetic data: one user, four traces with unique,
ambiguous and missing local identities, one progress and one library book.
No original phone data or production reading content was used.

The initial schema restore succeeded, but pg_dump's empty search_path caused
the first unqualified synthetic INSERT to fail with 42P01. Verified there were
zero users and no migrations had run. Continued in a new local session with
public search_path; explicitly restored that setting after subsequent dump
imports. This was a rehearsal-session issue, not a migration failure.

Made an in-memory dump of the synthetic baseline and restored it into the
separate restore database. Verified trace identities/metadata/timestamps and
progress/library rows. This proves the synthetic restore path, NOT that a
current full production backup has been created or restored.

Applied migrations 003, 004, 005, 006 in order, twice. Wrapped 003 in a transaction
with lock_timeout=5s; 004-006 contain their own transactions. Both passes passed.

| Migration | First pass | Second pass |
| --- | ---: | ---: |
| 003 | 52 ms | 18 ms |
| 004 | 22 ms | 6 ms |
| 005 | 30 ms | 4 ms |
| 006 | 19 ms | 3 ms |

These small-fixture timings do not predict production lock waits or duration.
Confirmed historical fields preserved, updated_at backfilled from created_at,
only the unique local identity bound, ambiguous/missing identities retained,
and zero fabricated historical ledger events.

## Verification results

- Existing real PostgreSQL concurrency/revision/ledger suite: 19 passed,
  zero skipped. Its destructive fixtures ran only in the new concurrency DB.
- Additional real HTTP/auth/repository/PostgreSQL smoke checks on the upgraded
  production-schema clone: 25 assertions passed. Covered 401, authenticated
  ownership, create/replay, delete/recreate, stale DELETE rejection, stale
  progress rejection, a legitimate newer LOWER progress, legacy 428 responses,
  permanent purge replay, and MCP repository visibility before/after purge.
  Seven real ledger events remained for the synthetic smoke operations.
- The smoke server listened on a random localhost port and was closed afterward.
  AI insight scheduling alone was disabled in the test process to prevent
  unrelated generation/network traffic; authentication and write repositories
  were real. No production token or MCP token was used for these HTTP checks.
- npm run test:reliable-upload: 21 passed.
- npm run test:mcp: 17 passed, modern and legacy Streamable HTTP included.
- npm run check: passed. git diff --check: passed.
- Flutter tests were not rerun in this backend-only rehearsal; see the previous
  Xiaou fix verification. No iOS build or new physical-device test occurred.

## Remaining release gates

1. Explicit production deployment/migration approval is still required.
2. Create and verify a recoverable current production backup before migration;
   this rehearsal exported schema only and is not a production backup.
3. Inventory supported installed clients and agree upgrade/maintenance policy.
   Real HTTP checks confirmed legacy unversioned progress and local-ID trace
   writes receive 428. Durable-queue clients retain pending work, but old
   best-effort clients cannot be promised lossless recovery. No compatibility
   bypass was added; unversioned writes must not overwrite revision-safe data.
4. Drain old sync writers, apply 003-006, upgrade every backend instance, verify,
   then reopen sync. Do not mix old unversioned writers with the new backend.
   Old backend SQL may still execute on additive schemas, but that is NOT a
   safe rollback after accepting versioned traffic. Pause writes and fix forward
   rather than dropping tombstones/revisions or rolling back protection.
5. Preserve .env and existing JWT/MCP secrets. Never initialize production with
   the entire schema.sql or db:init.
6. Preserve original device/account/queue evidence. Only after backend readiness
   and separate approval, replace the evidence-only install in-place with a
   correctly targeted business build. Disabling diagnostics re-enables normal
   automatic upload; it is not a passive inspection step.

No new migration defect was found. This result clears the isolated backend
rehearsal, not production release, full old-client compatibility or phone E2E.
See [rollout sequence](xiaou-local-trace-rollout.md) and
[version compatibility](reliable-upload-progress-revisions.md).
