# 07 - Getting Started (Actual)

## Prerequisites

- Flutter 3.47.7 / Dart 3.13.5 (CI pins 3.47.7).
- Access to the Supabase project `nhisab` `qcbxurqxmnkzgsfpaesz` (or a staging
  project). Do not create a new production project casually.
- An invited owner account. Public sign-up is disabled.
- No local Postgres/Docker is required for the Flutter app. SQL verification can
  use the Supabase SQL editor; the development PGlite harness is optional.

## Repository Layout

```
C:\Users\user\Downloads\nHisab-main\nHisab-git\
  README.md
  docs/01-16
  app/                         Flutter project (name nhisab)
    lib/main.dart              Supabase init + AuthGate + HomeShell
    lib/src/core/              calculator, money, dates, cache, audit
    lib/src/features/          auth, home, parties, loans, payments,
                               accounts, categories, transactions, budgets,
                               dashboard, import, notifications, audit
    test/                      unit + widget tests
    build/web                  release output (generated)
  supabase/
    migrations/                schema, tenancy, payment RPCs
    verify/                    security_checks.sql, smoke_test.sql
    functions/dispatch-alerts/ Edge source only (not deployed)
    tests/                     legacy note; use verify/
```

## Run

```powershell
cd C:\Users\user\Downloads\nHisab-main\nHisab-git\app
flutter pub get
flutter analyze
$env:TZ='UTC'; flutter test --reporter expanded
$env:TZ='Asia/Kathmandu'; flutter test test/bs_picker_test.dart test/widget/bs_picker_test.dart
flutter run -d chrome
```

Keys default to the development publishable key in `main.dart`. Override:

```powershell
flutter run -d chrome `
  --dart-define=SUPABASE_URL=https://qcbxurqxmnkzgsfpaesz.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_...
```

Never pass a service-role key to `flutter run` or `flutter build`.

## First Checks

1. Sign in with an invited account. There is no sign-up button.
2. If the app says "Account not provisioned", the user has no active
   `tenant_members` row. Create an invite and re-invite; see `docs/15-runbook.md`.
3. Open Ledger, set the date, and verify the rows you expect. The historical
   sheet check is receivable principal `9,960,000`, interest `668,653.33`, and
   payable principal `85,713,900`.
4. **Do not press Import Seed** against a database that already has parties or
   loans. The guard aborts, but do not rely on it as a migration tool.
5. Record a small test payment on a test loan. Confirm the wallet leg and the
   party statement. Void it; confirm the loan reopens if it was closed.
6. Sign in as a viewer. Write controls are hidden and direct writes are denied by
   the database.

## Migrations

The live project may still have the pre-hardening schema. Check
`docs/08-supabase.md` for the applied history and `docs/15-runbook.md` for the
expand/contract order:

1. back up,
2. apply `20261025120000_tenant_membership_rls.sql`,
3. deploy the hardened client,
4. apply `20261025121000_payment_rpcs.sql`,
5. run `supabase/verify/security_checks.sql`,
6. run `supabase/verify/smoke_test.sql` on staging only.

Do not add `BEGIN`/`COMMIT` to migration files. Do not run the old client after
the payment migration.

## Build

```powershell
flutter build web --release --base-href=/nhisab/ --no-wasm-dry-run
```

Output: `app/build/web`. CI computes the base href from the repository name and
copies `index.html` to `404.html`, then adds `.nojekyll`.

## Common Problems

- **Blank page after deploy:** wrong `--base-href`. Check the repository name and
  the Pages URL.
- **Sign-in works but no data:** no active membership, or the tenancy migration
  has not been applied. Check `select * from public.tenant_members where
  user_id = auth.uid();`.
- **Payment fails with "could not find the function":** migration 9 is not
  applied. The client falls back to the legacy writer during the expand window;
  apply the migration and redeploy.
- **Payment fails with a permission error after migration 9:** expected. Direct
  payment writes are revoked; use the RPC.
- **Date off by one:** BS conversion is timezone-sensitive. Run the calendar
  tests under both UTC and `Asia/Kathmandu`; do not use local-midnight
  `DateTime` arithmetic.
- **Cache shows another user's data:** sign out and back in; the cache is
  namespaced per user, and a stale browser tab must be reloaded after deploy.

## Missing for Full Reproducibility

- A committed local Postgres/Supabase test harness (PGlite harness is currently
  outside the repo).
- A staging project and environment-specific CI secrets.
- A recorded backup/restore drill.
- Edge/cron deployment and provider credentials.
