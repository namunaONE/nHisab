# 07 - Getting Started (Actual)

## Prereqs - Verified
- Flutter 3.47.5, Dart 3.13.4 windows_x64
- Supabase project already live: nhisab qcbxurqxmnkzgsfpaesz ap-south-1 https://qcbxurqxmnkzgsfpaesz.supabase.co, Postgres 17.11. Do not create new.
- No local supabase/ folder. Migrations applied via MCP: 20261015065947 init + 20261015070054 fix_lints.
- Resend/SMS keys pending, Edge not deployed.

## Actual Layout
```
C:\Users\user\Downloads\Project\nHisab\
  README.md, docs/01-12
  app/ (Flutter project name nhisab, org com.nhisab)
    lib/main.dart (AuthGate + HomeShell)
    lib/src/core/calculator|theme|dates
    lib/src/features/auth|home|loans|parties|payments|import
    test/loan_calculator_test.dart
    build/web (release output, gitignore in normal flow)
```

## Run Existing
```bash
cd C:\Users\user\Downloads\Project\nHisab\app
flutter pub get
flutter analyze
flutter test test\loan_calculator_test.dart
flutter run -d chrome
```
Keys default to sb_publishable_ in code for dev. Override:
```
flutter run -d chrome --dart-define=SUPABASE_URL=https://qcbxurqxmnkzgsfpaesz.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_...
```

## First Checks
1. Signup in app, confirm email in Supabase dashboard if required. RLS needs authenticated, anon shows error by design.
2. Ledger Set 2026-10-15, Lent Principal 9960000 Interest 668653.33, Borrowed Principal 85713900.
3. Do not press Import Seed, DB has 21/21 rows, will duplicate. Seed guard pending.
4. Build: flutter build web --release --no-wasm-dry-run, 50-170s, output app/build/web.

## Missing for Reproducibility
- Export remote schema to supabase/migrations/*.sql, add firebase.json with COOP/COEP + wasm MIME, add .env.example, add seed idempotency check.
