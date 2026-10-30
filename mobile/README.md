# Reclaim mobile

Flutter app (Android and iOS), offline-first. See `../docs/ARCHITECTURE.md`.

```
lib/
  core/       theme, router, encrypted Drift database, shared widgets
  features/   onboarding, assessment, home, progress, shell (navigation + placeholders)
```

## Running

```powershell
flutter pub get
dart run build_runner build   # Drift and Riverpod code generation
flutter run
```

Generated files (`*.g.dart`, `*.drift.dart`) are not committed, so run `build_runner` after
pulling, and again whenever you change a Drift table or a `@riverpod` provider
(`dart run build_runner watch` keeps it running).

## Local database

- Drift on SQLite3MultipleCiphers, chosen with the `hooks: user_defines: sqlite3` block in
  `pubspec.yaml`. The same encrypted build is used by `flutter test` on your desktop, so
  `test/core/encrypted_connection_test.dart` checks real on-disk encryption.
- The key is created on first launch and kept in `flutter_secure_storage`.
- Drift runs in *modular* mode (`build.yaml`) so Riverpod's generator can see Drift row types.
- Ids are client-generated UUIDs, so records keep their identity when synced to an account.
- Schema changes bump `schemaVersion` in `app_database.dart` and add a step to `onUpgrade`;
  `test/core/migration_test.dart` covers upgrading from every earlier version.

## Dashboard rules

Pure functions in `lib/features/dashboard/domain/dashboard.dart`, tested in
`test/features/dashboard/dashboard_test.dart`:

- **Days without gambling** counts calendar days since the last deposit, loss or win (a
  withdrawal alone isn't gambling). Entries dated before the journey started don't count.
- **Estimated money kept** = the usual monthly spend from onboarding spread over the journey's
  days, minus net loss logged since starting, never below zero. Shown only when a usual spend
  was given, and always labelled as an estimate.
- **Net loss** = (deposited − withdrawn) + (lost − won), the same as the backend.
- An urge whose outcome is "gambled" counts as a gambling day for the streak, even if no
  amount was logged.

## Urge flow

`lib/features/urges/`. Only one urge is open at a time; starting another marks the open one
abandoned, and an open urge older than 12 hours is no longer offered on Home. The countdown is
worked out from the stored `startedAt` and `coolingOffMinutes`, so it carries on across app
restarts. All guidance copy lives in `urge_models.dart`, and `urge_test.dart` checks it for
shaming language.

## Things to keep in sync with the backend

- `lib/features/assessment/domain/questionnaire.dart` mirrors the backend questionnaire
  (version 1). `test/features/assessment/questionnaire_test.dart` pins the question ids and
  score bands; change both sides together and bump the version.
- Enums have the same members as the backend's; the backend serialises them in PascalCase.

## Tests

```powershell
flutter analyze
flutter test
```
