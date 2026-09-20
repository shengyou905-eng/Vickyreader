# Reliable Upload acceptance: build 12

- Source branch: codex/reliable-upload-acceptance, latest pushed commit.
- App version/build: 1.0.0+12. Build 11 was already used for evidence export.
- API origin: https://api.youxugarden.com (production, migrated through 006).
- SQLite version: 17, unchanged.
- Local diagnostics freeze: disabled. Normal automatic uploads resume.

## Codemagic iOS build arguments

Keep Release and the existing signing/export configuration. Replace old values
for these arguments rather than adding conflicting duplicate defines:

```text
--build-name=1.0.0 --build-number=12 --dart-define=API_BASE_URL=https://api.youxugarden.com --dart-define=ENABLE_LOCAL_SYNC_DIAGNOSTICS=false
```

Do not keep an older --build-number=10/11, a Tailscale API override, or a true
diagnostics define in another build argument or define file. Check the actual
Flutter command in the Codemagic log. If build 12 has independently already
been uploaded to App Store Connect, use an unused higher build number.

This is not the GitHub unsigned-iOS workflow: that workflow's acceptance-branch
default still points at Tailscale unless explicitly overridden. It is unchanged.

## Preserve the original evidence

Keep the diagnostic JSON. Install as an in-place update with the same bundle ID,
signing identity and account; do not uninstall, clear data or switch accounts.
This build intentionally resumes startup/foreground/timer uploads. It is not a
read-only evidence build, and pending metadata can change after installation.

Verify the original local traces appear in Xiaou without requiring remote IDs.
Pending traces show Pending sync; after successful upload and refresh they must
remain single entries. Confirm queue clearance and PostgreSQL/MCP consistency
before declaring the physical-device acceptance complete. A public health 200
or unauthenticated MCP 401 alone does not prove authenticated synchronization.
