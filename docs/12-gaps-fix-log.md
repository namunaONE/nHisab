# 12 - Gaps Fix Log

Date opened 2026-10-15 from docs audit 01-11 vs code + DB 21/21/0/0/0/0 rows + migrations 20261015065947/55.

## P0
- [x] 03 stale versions: fixed to Flutter 3.47.5/Dart 3.13.4/PG17/actual deps, removed freezed/mocktail/exports bucket claims.
- [x] 04 missing future-day + payment sum bug + flat hidden + status: documented and code fixed 2026-10-15.
- [x] 07 unusable path: rewrote to app/ existing project, no local supabase folder noted, seed duplicate warning.
- [x] 01 success overstated: marked PASS/PARTIAL/FAIL per item.
- [x] 02 actual vs planned split: done.
- [x] Code 2026-10-15 (no Firebase): PaymentForm prevInterestPaid now sums payments.interest_amount per loan for preview + save. deleted_at added to 6 tables via 20261015073715, providers filter deleted_at is null, archive buttons on ledger/parties/payments set deleted_at. Import seed21 aborts when loans/parties not empty. supabase/migrations exported 3 files + README. Verified analyze 0 errors 8 infos, test 2/2, build/web success. Firebase skipped per request.

## P1
- [x] Export supabase db to supabase/migrations + Import seed count guard (done). Firebase skipped (Pages locked). .env.example added as app/.env.example 2026-10-15.
- [x] Pages CI analyze/test/build via .github/workflows/pages.yml (base /nhisab/, 404 + .nojekyll).
- [x] docs/14-api-reference: PostgREST selects per provider + RLS need (added).
- [x] docs/15-runbook: backup/restore, rate fix, duplicate cleanup, key rotation, Vault pg_net (added).
- [x] docs/10 section 9.5: staging/prod project split approach (added).
- [x] P1-1: profiles table + RLS + handle_new_user trigger applied remote (migration 20261015160000).
- [x] P1-2: extended LoginPage (display_name, phone, terms, password show/hide, inline validation) + AuthGate profile role gating + canWriteProvider.
- [ ] CI analyze/test/build on PRs (workflow runs on push only).
- [ ] Staging/prod project split (documented in docs/10 section 9.5, not applied).

## P2
- [x] Budget tracker v1: accounts/categories/transactions/budgets schema + RLS + seed (3/8/0/0), CRUD forms, spent rollup, loan-txn link, dashboard fl_chart 6-month + donut, full Excel workbook + PDF summary, Decimal-exact Money core (10/10 tests), RLS 10/10 verified + rls_check.sql, idx_txns_loan fix. Remaining: EMI schedule UI + flat compare, party statement, audit_logs writer + UI, bell tray + cron + Edge deploy.
- [x] P2-1 party statement (model + family provider + page + PDF export, statement action per party row).
- [x] P2-2 EMI schedule UI (model + family provider + page + PDF export, calendar action per loan row desktop + mobile).
- [x] P2-3 audit trail (AuditLog fire-and-forget writer + sanitizer, hooks on all 7 forms + 6 archive paths, audit page with table filter chips, More entry, 3 unit tests).
- [x] P2-4 alerts (bell badge + tray with Realtime invalidate, mark-read, More entry, 2 unit tests; Edge dispatch-alerts source + cron migration pending keys/CLI deploy).
- [x] P2-5 widget tests (auth gate login/owner/viewer, dashboard panels, ledger desktop/mobile, bell badge + tray nav, empty/error states; shared_preferences mock for Supabase init; CI runs full suite).
- [x] P2-6 offline Hive cache (CacheService read-through on 7 providers + writeMap for joins, Outbox enqueue/flush, offline banner + flush-on-reconnect in HomeShell, offline-first txn/payment forms, main init guarded, 4 cache tests).
- [ ] Flat-compare EMI, Edge deploy + cron schedule (needs Resend/SMS keys + CLI).
- [ ] UX empty/error/loading, DataTable 1400 mobile scroll strategy recorded, contrast check secondary on white result.
- [ ] ERD + sequence diagrams, glossary, party naming A/B canonical, changelog + owners.

Verify: flutter analyze 0 errors 0 infos, test 33/33 (15 unit + 14 widget + 4 cache), build/web success, RLS 11/11 (incl. profiles) + security 0.
