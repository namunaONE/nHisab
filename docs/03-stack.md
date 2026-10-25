# 03 - Stack (Actual 2026-10-25)

Verified from `app/pubspec.yaml`, `flutter --version`, the Supabase project and
the CI workflow.

## Frontend

- Flutter 3.47.7 stable, Dart 3.13.5, DevTools 2.60.0.
- Material 3, `ColorScheme.fromSeed(seedColor: 0xFF002C6D, secondary:
  0xFF4FD166)`, tonalSpot. Light and dark.
- `flutter_riverpod` 2.6.x for state; `MaterialApp` with `AuthGate`/`HomeShell`.
  `go_router` is a dependency but not wired.
- `data_table_2` for the ledger; `fl_chart` for dashboard charts.
- BS conversion: `bikram_sambat`, `nepali_date_picker`,
  `nepali_date_converter`. `nepali_utils` is transitive. The app uses its own
  civil-date wrapper so tests do not depend on the machine time zone.
- `decimal` and `rational` for exact money intermediates. Public calculator APIs
  still take/return `double` with `round2`.
- `excel` for workbook import/export; `pdf` + `printing` for statements and
  schedules.
- `hive_flutter` for the read cache and outbox; `connectivity_plus` for the
  offline banner and reconnect flush.
- `file_picker` for Excel import.
- `supabase_flutter` for Auth, PostgREST and Realtime.
- `flutter_lints` 6.0 only. No freezed, mocktail or very_good_analysis.
- `shared_preferences` as a test dependency for Supabase Auth storage.

## Backend

- Supabase project `nhisab` `qcbxurqxmnkzgsfpaesz`, `ap-south-1` (Mumbai).
  Postgres 17.11 as last verified 2026-10-15.
- Auth: email/password, invite-only, email confirmation required. No OTP, MFA or
  social login.
- Tables: tenants/members/invites/profiles; parties/loans/payments/
  emi_schedules; accounts/categories/transactions/budgets;
  notification_queue/audit_logs.
- RLS: per-operation policies, membership-derived tenant, minimum column grants,
  composite tenant FKs. `anon` has no grants.
- Money RPCs: `record_payment`, `void_payment`, `close_loan`; `nepal_today()`.
- Realtime is used for the notification bell only.
- Edge `dispatch-alerts` is source only; pg_cron is not scheduled.
- Migrations live in `supabase/migrations`; verification in `supabase/verify`.
- No `supabase/config.toml` or CLI link in the repository. Apply through the
  dashboard SQL editor or link the CLI.

## Hosting and CI

- GitHub Pages via `.github/workflows/pages.yml`.
- Flutter 3.47.7, `actions/checkout@v5`.
- Analyze; full tests under `TZ=UTC`; calendar tests under `TZ=Asia/Kathmandu`;
  web build; Pages deploy only on non-PR events.
- Build: `flutter build web --release --base-href=/<repo>/ --no-wasm-dry-run`.
- No Firebase Hosting configuration. No custom headers on Pages.
- Supabase URL/key come from GitHub Actions secrets; `main.dart` has a
  development publishable-key fallback.

## Tooling / Tests

- `flutter analyze`: clean.
- `flutter test` under UTC: 49 tests.
- Calendar tests under Nepal time: 7 tests.
- SQL harnesses (local, not committed): `libpg-query` parse, PGlite PostgreSQL
  18.6 apply/integration/expand-contract, `security_checks.sql`,
  `smoke_test.sql`.
- No Postgres/Docker/WSL locally; PGlite is not a Supabase runtime. Live
  PostgREST/JWT behavior still needs staging.

## Costs

Supabase free tier (no PITR, manual backups), GitHub Pages free, Resend/SMS not
configured. A production lending deployment should budget for a paid Supabase
plan or off-platform backups, a custom host with security headers, and provider
credentials if alerts are enabled.
