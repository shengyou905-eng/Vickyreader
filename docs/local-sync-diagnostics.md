# Temporary Local Sync Diagnostics

This is a metadata-only, offline export for the existing iPhone incident. It does
not repair, backfill, retry, authenticate, or contact any backend. No production
deployment or database migration is required. No new dependency was added.

## Acceptance Build

Add this argument to the **actual** Codemagic/Mac `flutter build ipa` invocation:

```text
--dart-define=ENABLE_LOCAL_SYNC_DIAGNOSTICS=true
```

Optionally supply `--dart-define=BUILD_COMMIT=<the actual built Git SHA>`.
The commit is explicitly marked build-supplied, not independently verified.
With the first argument, the App starts directly on the evidence export screen.
It does not mount the normal providers, bookshelf, reader, account/settings
flows, or foreground observer. Without it, normal startup is unchanged and the
temporary entry is hidden, including in Release. This switch does not change API_BASE_URL. Preserve the incident
build's API configuration; do not switch accounts or silently retarget it.

Install as an update with the same bundle identity/signing. **Do not uninstall
the existing App**, clear storage, or create replacement test records. If an
Xcode sandbox backup is available, preserve it before installing the update.

## iPhone

1. Fully close the old App before installing the evidence update. Keeping the
   device offline until the update is installed is an additional precaution.
2. Launch the evidence build: it opens Developer Diagnostics directly. Tap
   Export Local Sync State (开发者诊断 > 导出本地同步状态).
3. In the iOS Share Sheet choose Save to Files, preferably On My iPhone.
4. Preserve the timestamped `zhidu_diagnostic_*.json` file. It still contains
   reading record identifiers, so share it only with the intended investigator.

The export contains no authentication credentials or reading/note/AI bodies.
It is not a full SQLite backup and cannot restore missing content.

## Fields and Interpretation

- `app`: installed iOS Bundle version/build, optional build commit, effective
  compiled API base URL (credentials/query/fragment stripped), expected SQLite
  version. Backend environment remains unknown: no health/auth probe is made.
- `database`: actual `PRAGMA user_version`, SQLite version, journal mode.
- `current_user_ref`: domain-separated SHA-256 of the stored `auth_user_id`,
  read without starting the auth provider or validating/changing the session.
  Each row uses the same hash plus current/other/anonymous owner relation. This
  is pseudonymization, not proof of server authentication. No email/token read.
- `schema`: per-table existence, selected and missing columns. Missing fields
  are not silently filled with guessed values or migrated.
- `highlights` / `notes`: IDs, book/chapter, available timestamps, offsets for
  highlights, remote IDs, source record ID, linked trace IDs. Hard-deleted rows
  cannot be reconstructed. All owners are included with pseudonymized IDs so an
  ownership mismatch is visible.
- `user_entries`: local/client ID (the local upload endpoint ID), source/type,
  metadata source record ID, remote ID, local revision counter, matching
  pending revision/generation/operation. Remote-imported rows with no counter
  are not claimed to have been uploaded. No raw metadata JSON is exported.
- `reading_progress`: book/chapter/offset, timestamps, matching revision/pending.
- `pending_upload_operations`: operation/entity IDs, operation, client revision,
  generation, retries, failure and next-retry timestamps. Payload projection
  contains only book/source IDs; raw payload is excluded. Invalid JSON is
  reported without repair or including its contents.
- `upload_writer`, `upload_entity_revisions`, `locally_deleted_books`: persisted
  writer ID, revision counter and state hash, explicit book deletion markers.
  Exact known `delete + {}` hash is labeled as tombstone evidence; an unmatched
  hash is not proof that a server record is live.
- `server_revision` and `last_error` are null: the current local model does not
  persist server revisions or raw error messages. Failure time remains available.

## Read-Only Guarantee and Limits

The exporter opens the existing DB via `readOnly: true, singleInstance: false`,
without DatabaseService, migration callbacks, or a requested schema version.
It issues only SELECT/read-only PRAGMA and explicit BEGIN DEFERRED/COMMIT/ROLLBACK.
It does not use sqflite `transaction()` because the installed implementation
skips BEGIN for read-only handles. One real read transaction spans all tables.
SQLite reads committed WAL frames itself; there is no manual DB copy or checkpoint.
See [SQLite WAL snapshot semantics](https://www.sqlite.org/wal.html).

Only a new JSON file in a unique temporary directory is written for sharing.
SQLite may maintain shared-memory reader locks; this is not a business-data,
revision, queue, or schema update. Tests verify DB and WAL bytes stay identical
when no independent writer is running, that the actual handle rejects writes,
and that concurrent writes are excluded from the pinned snapshot.

**Evidence-only startup is enforced by the compile-time switch.** No business
providers, startup migration, anonymous queue claim, bookshelf snapshot, or
automatic cloud merge runs. The foreground handler also returns immediately.
Uploader start/drain/claim return before creating any retry timer, accessing a
database, or calling the client. Enqueue operations fail closed, and the business
DatabaseService getter is blocked even if a future caller accidentally reaches
it. Only the independent read-only inspector can open the evidence database.
No pause/frozen flag is persisted; no queue/revision/account state is changed.
These guards last for the entire lifetime of this build, including after sharing.

The report includes `evidence_only_startup: true` and
`automatic_sync_disabled: true`. This preserves the state at evidence-build
startup, not an earlier state that the old App may already have changed. Do not
use this build for reading or general acceptance tests. Install a normal build
with the define omitted/false only after preserving the evidence.

## Verification

Use the existing isolated SQLite harness, not the device or backend database:

```text
cd tool/reliable_upload_tests
flutter test --no-pub --reporter expanded
flutter test --no-pub --dart-define=ENABLE_LOCAL_SYNC_DIAGNOSTICS=true test/local_diagnostics_mode_test.dart test/local_sync_diagnostics_test.dart --reporter expanded
```

The first command covers normal/default mode including scheduling and the
existing upload/deletion suite. The second covers evidence mode, real SQLite
DB/WAL byte equality across App startup, foreground, simulated timer intervals,
the export button and a mocked native Share Sheet. An older schema fixture is
not migrated, and stored account preferences remain unchanged.

The fixtures live only in a disposable OS temporary directory. Native iOS Bundle
and Share Sheet behavior still require a Mac/iPhone smoke test; Windows cannot
compile or validate the iOS binary. No iOS build is performed by this change.
