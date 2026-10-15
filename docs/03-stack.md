# 03 - Stack (Actual 2026-10-15)

Verified via app/pubspec.yaml, flutter --version, Supabase MCP.

## Frontend - Actual
- Flutter 3.47.5 stable / Dart 3.13.4 / DevTools 2.60.0
- Material 3, `ColorScheme.fromSeed(seedColor: 0xFF002C6D, secondary: 0xFF4FD166)`
- flutter_riverpod 2.6.1, go_router 15.1.3 installed not wired (MaterialApp home used), data_table_2 2.8.0, fl_chart 0.69.2 installed not wired
- BS: bikram_sambat 1.2.0 + nepali_date_picker 8.0.0 + nepali_date_converter 1.0.3 + nepali_utils 3.0.8 transitive. nepali_date_pro_max NOT used.
- decimal 3.2.6 installed, calculator currently uses double round2 with plan to migrate inner math to Decimal. intl 0.20.3, excel 4.0.6, pdf 3.12.0, printing 5.14.3, hive_flutter 1.1.0 installed not wired for cache yet, connectivity_plus 6.1.5 installed not wired, file_picker 8.3.7, supabase_flutter 2.18.3
- No freezed, no mocktail, no very_good_analysis. flutter_lints 6.0.0 only.

## Backend - Actual
- Supabase nhisab qcbxurqxmnkzgsfpaesz ap-south-1, Postgres 17.11.0.003
- Migrations remote only, versions 20261015065947 init_nhisab_schema + 20261015070054 fix_lints. No local supabase/ folder in repo.
- Tables row counts 2026-10-15: parties 21, loans 21, payments 0, emi_schedules 0, notification_queue 0, audit_logs 0. RLS enabled all 6.
- Auth email/password only. No OTP, no password reset UI, no profiles table yet.
- Realtime installed not subscribed for bell tray yet. Storage exports/ bucket NOT created. Edge dispatch-alerts NOT deployed. pg_cron NOT scheduled.

## Tooling - Actual
- No Supabase CLI link in repo, MCP apply_migration used. No firebase.json, no CI.
- Env --dart-define SUPABASE_URL + SUPABASE_ANON_KEY with sb_publishable_ key in anonKey param (deprecated info, works).
- Tests: flutter_test only, test/loan_calculator_test.dart 2/2. No RLS SQL tests, no widget tests (default deleted).
- Build verified: flutter build web --release --no-wasm-dry-run success 54-170s to app/build/web.

## Costs - Unchanged
Supabase free 500MB, Firebase Hosting free, Resend 3000/mo free, SMS pay-per-use Sparrow/Aakash pending.
