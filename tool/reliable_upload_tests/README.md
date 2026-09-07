# Reliable upload SQLite tests

This small Flutter test entry point runs the production service tests against a
real temporary SQLite database. It is not an app or a new test framework.

The app's sqlite3 hook uses process symbols for mobile. Windows flutter_tester
does not export those symbols. This package selects Windows' winsqlite3 (or
system sqlite3 on other hosts) without changing the app pubspec or iOS build.
The lockfile starts from the application's lockfile; no app dependency upgrade
is needed.

From this directory:

```powershell
flutter pub get --offline
flutter test --no-pub --reporter expanded
```

The tests use temporary directories, fake HTTP clients, and real SQLite. They
do not connect to Zhidu or inspect the user's app database. See
`docs/reliable-upload-closeout.md` at the repository root for device acceptance.
