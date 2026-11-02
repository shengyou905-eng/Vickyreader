# Apple IAP Sandbox foundation: 2026-10-15

Stage 1 only. No production code/configuration/database mutation, DNS changes,
Nginx reload, production restart, real Apple key, purchase, commit or push.

## Production prerequisite checks

- Host: 101.32.186.151, VM-0-13-ubuntu, 2 CPUs / 1967 MiB RAM.
- Latest daily dump: 20261015-031501, 360558 bytes. SHA256, archive TOC and full
  pg_restore decoding to /dev/null passed. No restore into production or Sandbox.
- Historical 2026-09-21 restore manifest confirms full restore, migration rehearsal
  and canonical data preservation. This is historical restore evidence, not a new
  full restore test of today's dump.
- Existing daily backup permissions are broad (0644 file / traversable parents).
  No permission/backup-job change was made; hardening needs separate approval.
- Production .env, app.js and Nginx config fingerprints were unchanged. Backend
  PID 229374 retained its September 21 start time; reader-postgres was not restarted.
- Production IAP switch remains unset and IAP modules remain undeployed.

## Isolated runtime

- Root: /home/ubuntu/apps/zhidu-iap-sandbox (0700).
- Release: releases/20261015-phase1. Source is a local workspace snapshot based
  on caf7dd675322153bc1ee3c09747619510151d08d, including uncommitted Phase 1/2.
  It is NOT represented as a clean deployed Git commit. Original and final manifests
  record file hashes and the bootstrap correction.
- API: zhidu-iap-sandbox-api, 127.0.0.1:3001 only; Node 22.22.2 official image
  pinned by digest. Read-only code/root filesystem, unprivileged UID, no Docker socket.
- PG: zhidu-iap-sandbox-postgres, PostgreSQL 16.14 existing image ID pinned;
  no published port. Database zhidu_iap_sandbox, volume zhidu-iap-sandbox-pgdata.
- Network: zhidu-iap-sandbox, containing only the two test containers.
- Roles: separate bootstrap admin, non-login schema owner, and non-superuser
  runtime zhidu_sandbox_app with DML access but no schema/database CREATE rights.
- Independent generated DB/JWT/rate-limit credentials live in config/ (0700;
  files 0600). They are not included in source artifacts or this report.
- Each test container: 0.5 CPU, 384 MiB RAM, no additional swap allowance, 128 PIDs,
  json-file logs rotated at 10 MiB x 3. No restart policy; do not automatically
  restart after a guard stop or host reboot before repeating preflight checks.
- No production volume, source directory or configuration is mounted in test containers.
- APPLE_IAP_ENABLED=false, APPLE_IAP_ENVIRONMENT=Sandbox; no real Apple private key.
  NODE_ENV=production disables automatic schema initialization; health's env field
  therefore says production and is NOT the Apple environment or database identity.
- Obsidian integration is disabled in this test configuration. No LLM key configured.

## Initialization and checks

The current schema.sql embeds 002-009 but omits migration 001 Apple auth tables.
Initial schema initialization succeeded, but the first HTTP notification smoke returned
503 because auth_rate_limits was absent. No users or subscriptions existed at that point.
Stopped ONLY the test API and applied missing 001 transactionally to the empty test DB.
The final initializer now executes schema.sql plus 001 in one transaction, without
replaying embedded migrations. Existing business/schema source files were not changed.

Final verification: 11 groups passed: disabled IAP/key absence; DB identity/runtime
privileges; 001 prerequisites; exact 008/009 columns; composite environment constraints,
indexes/version fences; ownership/erasure triggers; empty business tables; HTTP health
and JWT rejection; malformed notification rejection; real synthetic registration/login
and disabled IAP responses; cleanup with no subscriptions/entitlements/traces left.
Rate-limit metadata from smoke requests remains naturally in the test auth_rate_limits
table. No production users or data were copied. No Apple API request was made.

## Resource safety and observations

Transient systemd unit zhidu-iap-sandbox-guard runs as ubuntu (96 MiB / 10% CPU cap).
Every five seconds it checks production loopback health, available memory and disk.
It stops ONLY the four named test/runtime/installer containers when health fails,
MemAvailable <384 MiB, free disk <5 GiB, or CPU stays >95% for six samples.
A STOPPED latch blocks subsequent deployment steps. There is no automatic recovery.
Guard status is in guard-status.json; it does not read production business records.
The guard is not installed for boot persistence; both test containers use restart=no.
Five guard unit tests passed both locally and on the server, covering healthy state,
memory pressure, production health failure, low disk, and sustained high CPU. These
simulate inputs and stop commands; no production fault or resource exhaustion was induced.

After startup: approximately 1185 MiB memory available, 23.82 GiB disk free;
API around 42 MiB and PG around 42 MiB. No OOM, significant swapping or production
health error observed. Same-host isolation is not a guarantee against all host failures.

## Stop / next stage

To stop this environment, stop only zhidu-iap-sandbox-api and
zhidu-iap-sandbox-postgres, retaining the test volume and configuration. Never use
global docker stop/prune, pm2 restart all, or production restore scripts.
Do not run verify.cjs after accumulating real Sandbox purchases: its clean-state
assertions deliberately require an empty business database.

Next approval: dedicated DNS + HTTPS/Nginx vhost with rollback plan; Apple IAP
credentials and roots; Sandbox V2 notification URL; Sandbox-only enablement.
ASC still requires active Paid Apps Agreement, app identity, Zhidu Pro monthly/yearly
products and Sandbox testers. TEST notification delivery and real transactions remain
unverified; Phase 3 Flutter integration is not implemented by this deployment task.
