# 13 - Codebase Standards

Actual 2026-10-25: feature-first Flutter app, Riverpod, `flutter_lints` 6,
`flutter analyze` clean, 49 tests under UTC plus 7 calendar tests under Nepal
time. SQL migrations and verification live under `supabase/`.

## 1. Folder Structure

```
lib/main.dart                     Supabase init, AuthGate, HomeShell
lib/src/core/
  calculator/                     pure loan math
  money/                          Decimal-exact helpers
  dates/                          AD/BS civil-date conversion
  budget/                         pure wallet/budget math
  cache/                          Hive read cache + outbox
  audit/                          client audit writer (ordinary writes)
lib/src/features/<feature>/
  *_page.dart                     screen
  *_form.dart                     dialog/form
  *_provider.dart                 Riverpod providers
  *_model.dart                    plain models
test/                             mirrors lib; unit + widget tests
supabase/migrations/              ordered SQL, no explicit BEGIN/COMMIT
supabase/verify/                  read-only checks + staging smoke test
docs/                             design, runbook, API, hardening plan
```

Rules:

- Feature folders own their UI/state; `core` holds pure logic and cross-cutting
  infrastructure.
- No cross-feature imports except through providers/models.
- One page/form/dialog per file where practical. Split a file before it exceeds
  roughly 250 lines.
- No new global mutable singleton except the Supabase client and Hive boxes.

## 2. Money Rules

- The database is the source of truth; the browser previews but does not post
  allocations.
- Payments, voids and loan closes go through RPCs. Do not add a direct
  `from('payments').insert/update` path.
- Every new payment call must send a fresh `client_id` UUID. Reuse only for a
  retry of the identical request.
- Interest-first, cap cumulative interest at principal, reject overpayment.
  Mirror any change in `loan_calculator.dart` and the SQL RPC in the same
  release, with tests.
- Never use `abs()` for dates; use civil dates. Future loans accrue zero.
- `dues` is unpaid interest; `outstanding` is unpaid principal + unpaid interest.
  Do not conflate them with `total_paid`.
- Principal wallet legs are excluded from cashflow. Transfers carry a direction.
- Money writes fail closed offline. Do not add a guessed allocation fallback.

## 3. Security Rules

- Never write `tenant_id`, `profiles.role`, `loans.status`,
  `transactions.payment_id`, void fields or close fields from the client.
- Add per-operation RLS and minimum column grants for any new table. Do not use
  `for all` or table-level `GRANT ALL TO authenticated`.
- Definer functions: `set search_path = ''`, fully qualified names, repeat tenant
  and role checks, and revoke `public`/`anon`.
- `anon` must have no table, sequence or function grants.
- Do not put a service-role key in the Flutter bundle, GitHub Pages or logs.
- New auth states fail closed. Missing profile, empty tenant or unknown role must
  never fall through to the app.
- Viewer UI gating is not enough; verify the database denies the write.
- Audit rows for ordinary writes are client-generated. For money, write audit in
  the RPC.

## 4. Flutter Practices

- Run `flutter analyze` before every commit. Keep it at zero issues.
- Prefer `final`, required named parameters, explicit casts and null checks.
  Avoid empty `catch` blocks; cache failures may be swallowed, money failures may
  not.
- Check `mounted` before `setState` after an `await`.
- Invalidate providers after writes and on auth changes.
- Use the theme's color scheme and text roles; no hardcoded hex outside
  `app_theme.dart`.
- Do not use local-midnight `DateTime` arithmetic for BS conversion. Use the
  civil-date helpers and run the calendar tests under two time zones.
- Cache keys must be user-namespaced. The outbox must only flush the current
  user's entries.
- Keep the ledger responsive: DataTable2 min width + horizontal scroll on
  desktop, card layout on mobile, dialogs scrollable.

## 5. SQL and Migration Practices

- One migration file per change, timestamped, applied in order.
- Do not add explicit `BEGIN`/`COMMIT`; the Supabase runner owns the transaction.
- Expand/contract for breaking changes: add columns and compatibility first,
  deploy the client, then revoke old paths.
- Use `add column if not exists` and defensive `do $$` blocks for partially
  applied environments.
- Validate with `libpg-query` and a disposable PostgreSQL before applying.
- Add a read-only check to `supabase/verify/security_checks.sql` for every new
  privilege invariant.
- `smoke_test.sql` is staging-only and must roll back.
- No hard deletes for financial rows. Soft delete via `deleted_at`.

## 6. Tests

- Every calculator change needs an assertion for the changed branch.
- Keep zero-rate, 365-day base, future-loan, cap, dues/outstanding and
  overpayment cases.
- Widget tests for AuthGate fail-closed states, viewer gating, ledger and empty/
  error states.
- Cache/outbox tests must cover per-user scoping.
- SQL integration should cover tenant isolation, viewer denial, payment split,
  idempotency, void/close/reopen and audit.
- Do not claim Supabase verification from a PGlite run. Record the environment.

## 7. Workflow Checklist

- [ ] `flutter analyze` clean.
- [ ] `flutter test` under UTC passes.
- [ ] Calendar tests under `Asia/Kathmandu` pass.
- [ ] `flutter build web` succeeds.
- [ ] SQL migrations parse and apply to a disposable Postgres.
- [ ] `security_checks.sql` PASS; `smoke_test.sql` PASS on staging.
- [ ] Docs updated when behavior, schema, auth or deployment changes.
- [ ] No secrets, logs, build output or dumps committed.
- [ ] Expand/contract order respected; old client not left against a contracted
      schema.
