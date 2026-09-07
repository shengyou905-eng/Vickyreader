# Reliable Upload acceptance build 1.0.0+9

This is a non-production device acceptance build. Do not deploy its backend to
production or run migrations on production as part of building the app.

## Source and endpoint

- Branch: `codex/reliable-upload-acceptance`
- App version: `1.0.0+9`
- SQLite schema: 17
- API origin: `https://wonyoung.taild268af.ts.net`
- Health: `https://wonyoung.taild268af.ts.net/api/health`
- Expected environment: `zhidu-device-acceptance`
- Expected database: `zhidu_device_acceptance_test`
- Expected production flag: `false`

The endpoint must pass iPhone Safari checks over both Wi-Fi and cellular before
installation. Disconnect the phone's Tailscale/VPN for those public-access checks.
Keep the Windows backend, Docker and Tailscale running and the PC awake throughout
acceptance. Funnel does not host a copy of the backend.

## Build on Mac or in an existing signed CI workflow

Use this branch, not the old main checkout. Preserve existing signing settings.
Replace any existing production API_BASE_URL define with the test origin; do not
append duplicate API_BASE_URL defines. Never include server secrets in Flutter.

```sh
flutter pub get
flutter build ipa --release --build-name=1.0.0 --build-number=9 --dart-define=API_BASE_URL=https://wonyoung.taild268af.ts.net
```

If build 9 has already been uploaded to App Store Connect, choose an unused higher
build number. The local repository cannot determine App Store Connect history.

For GitHub Actions, manually select this branch in **Build iOS Internal IPA** and
set `api_base_url` to the test origin. That workflow creates an UNSIGNED IPA, not
a TestFlight-ready signed artifact. Pushing this test branch does not trigger the
main-only automatic build. Automatic main builds retain their existing API target.

The app's source default is still the production API. A plain build without the
explicit define is NOT an acceptance build. Codemagic UI workflows must also use
the explicit define above; this repository does not contain a Codemagic YAML file.

## Test account and local data safety

Use password registration/login with `acceptance@example.invalid` and a unique
test password. No password is preconfigured. Do not use a real production account.
The local wrapper restricts registration/login to synthetic acceptance accounts;
`local-probe@example.invalid` is reserved for automated checks. Apple login and AI
generation are intentionally unavailable. Trace upload tests do not require an
LLM key.

The bundle identifier is unchanged. Use a spare device or an installation with
synthetic test data: changing the API origin does not isolate an existing SQLite
database. Never uninstall the sole copy of an app with unsent reading data.

After installation, verify that a synthetic operation reaches the test database
and its ledger. A Safari health check alone does not prove the compiled app target.
See `reliable-upload-progress-revisions.md` and `reliable-upload-closeout.md` for
the offline/restart, stale request and book-removal acceptance checklist.

## Stop the public test endpoint after acceptance

On the Windows origin:

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' funnel --https=443 off
```

No secrets, local runner configuration, database contents or build artifacts are
part of the source commit.
