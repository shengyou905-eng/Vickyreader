# Xiaou Local Trace Readiness

## Scope and evidence

This change reads local `user_entries` before requesting `/api/entries`, then
merges remote rows without importing them into SQLite. Local identity remains
stable before and after acknowledgement. Pending deletes, retained trace
tombstones and permanent book deletion markers hide stale remote cache rows.
Ordinary removal from the library does not hide reading history.

Local content wins for a locally present trace, including after its queue entry
is acknowledged: a delayed GET or disk cache is not a new local edit. Remote
rows supply remote identity and follow-up summaries. Remote-only traces remain
visible. This is a read projection, not a multi-device reconciliation protocol.
Queries are scoped to the current user; unclaimed anonymous rows are visible
only while anonymous, not mixed into another account. No free notes or full
chat history are queried. The read transaction performs SELECTs only.

The real diagnostic export showed five local traces and retained uploads;
there is no reason to backfill or recreate those records. The previous
read-only production audit found backend commit `18447ec`, missing client-entry
and versioned progress routes (404), and migrations 003-006 not applied.
Its database is named `reader_dev` but is PRODUCTION. The name is not evidence
of a safe test database. Audit observations must be rechecked before rollout.

Local visibility does not fix those missing backend routes. Evidence mode
(`ENABLE_LOCAL_SYNC_DIAGNOSTICS=true`) remains unchanged and does not run this
business UI, upload pending operations or modify the evidence database.

## Gated rollout checklist (not executed)

1. Preserve the current installation, diagnostic export and database backup.
   Do not uninstall, change accounts, delete pending operations or regenerate
   revisions. Do not switch this account's queued records to the test backend.
2. Pin the backend/client candidate commits and record build number and actual
   compiled API origin. Rehearse on an isolated non-production PostgreSQL restore
   using synthetic accounts. Never infer environment from database name.
3. Inventory installed client versions before production approval. Clients
   without persistent upload queues cannot be promised lossless recovery.
   Legacy trace writes with local IDs and unversioned progress reads/writes
   receive 428 on the new backend. Queue-capable versions retain pending work;
   much older best-effort clients may not. See
   [progress rollout constraints](reliable-upload-progress-revisions.md).
4. Obtain explicit production migration/deployment approval. Verify a restorable
   backup, actual schema/index definitions and target connection without logging
   connection strings or secrets. Preserve the existing production `.env`, JWT
   and `MCP_TOKEN_HASH_SECRET`; never replace them from this workspace.
5. In a controlled maintenance window stop old sync writers and drain in-flight
   requests. Apply 003, then 004, 005, 006 with stop-on-error. 003 has no explicit
   BEGIN/COMMIT: run it as one transaction with a bounded lock wait. 004-006
   already contain transactions and a 5-second lock wait. This is a lock-wait
   bound, not a runtime bound. Measure 003/004 backfill and ordinary index/ALTER
   locks on the restore first. Never run `db:init` or whole `schema.sql` over the
   existing database. Stop on any unexpected schema/index conflict.
6. Verify updated_at, client_entry_id, its unique index, sync_changes,
   sync_user_cursors/user_sequence, user_entry_upload_states,
   permanently_deleted_books and reading_progress_upload_states. Historical
   ambiguous client IDs stay unbound; do not merge or delete historical rows.
7. Upgrade all backend instances before reopening writes. Old SQL may still
   execute against additive tables, but old writers bypass revision/tombstone
   protection: do not mix versions or roll back to an unversioned writer after
   accepting versioned traffic. On failure pause sync and fix forward; do not
   drop revision/tombstone state.
8. Verify health, authentication, versioned trace/progress routes, idempotent
   replay, stale rejection, delete/recreate, ledger and both MCP transports
   using an explicitly approved test account. Never print bearer tokens or
   reading bodies to logs. Verify unrelated login/reader/MCP functionality.
9. Only after backend readiness and evidence preservation, explicitly approve
   replacing the evidence-only installation with a business-mode build pointing
   at the same intended backend. Omit or set the diagnostics define to false.
   This re-enables normal startup/foreground/timer uploads; it is NOT a passive
   inspection. Preserve application identity/signing/container on upgrade.
10. In the original account verify the existing five traces appear in Xiaou,
    including offline, without backfill. Pending items show pending sync. On
    successful upload, refresh Xiaou: identities stay stable, no duplicates,
    pending clears, PostgreSQL and MCP agree. Confirm ordinary archive retains
    history and explicit permanent deletion does not revive from old cache.

No production migration, deployment, build, commit, push, account change,
backfill or original-device queue consumption was performed for this fix.
