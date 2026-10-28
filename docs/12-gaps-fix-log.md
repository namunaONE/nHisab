# 12 - Gaps Fix Log

Opened 2026-10-15 from a docs/code/database audit (21 parties, 21 loans, 0
payments, 0 EMI rows, 0 notifications, 0 audit rows). This log records what was
actually fixed. Newest work is first.

## 2026-10-28 - First-owner self-service setup panel

- [x] DB `20261028230000_first_owner_bootstrap`: guarded `bootstrap_first_owner`
      RPC (works only while zero tenant memberships exist; advisory-locked) +
      `system_needs_bootstrap()` probe.
- [x] Login page: First-time setup panel (email prefilled `work.htpl@gmail.com`,
      new password + confirm, "Create first owner & sign in") with a Skip
      button that collapses to the normal invite-only sign-in. The panel
      disappears automatically once an owner exists.
- [x] CI re-run: analyze clean, 49/49 tests (TZ=UTC), release web build OK.

## 2026-10-28 - CI gate executed locally + repo/DB parity

### Local CI (now green, unblocks push/merge)

- [x] `flutter pub get` OK (Flutter 3.47.7 found at `C:\Users\user\flutter`).
- [x] Added `generate: true` to `pubspec.yaml` — l10n codegen (`l10n.yaml`)
      previously never ran, so `AppLocalizations` imports failed to resolve.
- [x] `flutter analyze`: fixed 3 compile errors (wrong relative l10n import in
      `home_shell.dart`; `mfa.unenroll(factorId:)` -> positional arg in
      `security_page.dart`; plus 9 warnings: unused import/var, duplicate
      import, redundant `?.` in `loan_form.dart`, block-style ifs) -> now
      **No issues found**.
- [x] Replaced `dart:html` CSV export with a platform-conditional downloader
      (`core/export/file_downloader.dart`: web uses `package:web` data-URL
      anchor; io/test uses a temp file) — fixes the deprecation lints AND keeps
      `package:web` out of the VM test graph.
- [x] `flutter test` under `TZ=UTC`: **49/49 passed**.
- [x] BS picker tests under `TZ=Asia/Kathmandu`: **7/7 passed**.
- [x] `flutter build web --release --base-href=/nhisab/ --no-wasm-dry-run`:
      built successfully (icons tree-shaken).

### Repo/DB parity (schema recovery)

- [x] Recovered the session's 17 live-applied migrations (exact SQL) from
      `supabase_migrations.schema_migrations` and wrote them to
      `supabase/migrations/` (previously only 20261028120000 existed on disk):
      txn idempotency, PII masking view, reconciliation view, period close,
      tenant switcher, EMI tenure, loan-edit-tenure RPC 15-arg, approval
      queue + RPCs, alert prefs, EMI payment allocation, Tier C foundations,
      perf indexes/RLS initplan, Tier C compliance, PII column revocation
      (+ `_reapply` as 20261028220001; 2 same-name applications merged into
      ordered files). The migrations dir now mirrors the live project, so a
      staging/restore rebuild is reproducible.
- [x] `security_checks.sql` (curated inline version) -> `PASS all_checks`
      re-verified after the PII column-revocation migration.

## 2026-10-25 - P0 Trust-Boundary and Money-Integrity Sprint

### CI

- [x] Reproduced the failing GitHub Actions job for commit `248cf73`: the BS
      widget test expected AD 2026-10-01 but returned 2026-09-30 under UTC. The
      conversion depended on local midnight.
- [x] Made BS/AD conversion use timezone-independent civil-date helpers.
- [x] Reworked `.github/workflows/pages.yml`:
  - Flutter pinned to 3.47.7.
  - `actions/checkout@v5`.
  - Analyze, full test suite under `TZ=UTC`, calendar tests under
    `TZ=Asia/Kathmandu`.
  - Pull requests run checks but never deploy.
  - Deploy only on non-PR events; per-ref concurrency; 20-minute timeout.
  - Dynamic base href; Pages artifact only on non-PR.
- Local: `flutter analyze` clean, 49/49 tests under UTC, 7/7 calendar tests under
  Nepal time, `flutter build web` succeeds.

### Tenancy and auth

- [x] Removed the shared-tenant fallback from `current_tenant_id()`; it now
      resolves an active `tenant_members` row and returns NULL otherwise.
- [x] Added `tenants`, `tenant_members`, `tenant_invites`; roles owner/manager/
      viewer; one active organisation per user.
- [x] Invite-only `handle_new_user()`: no profile or membership without a valid,
      unexpired invite.
- [x] Owner-only `create_tenant_invite()` RPC with email/role validation and
      audit.
- [x] Removed public sign-up from the client; added real password reset.
- [x] Fail-closed `AuthGate`: null profile, empty tenant, unknown role and
      profile errors block the app.
- [x] Viewer write gating across parties, loans, payments, accounts, categories,
      budgets, transactions, import and notifications.
- [x] Profile role is a projection of membership; trigger keeps it in sync;
      clients cannot update `role` or `tenant_id`.
- [x] Last-owner protection and append-only audit log.

### Money integrity

- [x] Future loans accrue zero interest instead of accruing backwards.
- [x] Cumulative interest capped at principal (Civil Code 2074 s.481).
- [x] Fixed `dues` and `outstanding`; principal repayment no longer reduces
      unpaid interest.
- [x] `splitPayment` returns excess and caps the principal portion; the payment
      form rejects overpayment.
- [x] Aggregate `interestPaid`/`principalPaid` per loan; the preview and split no
      longer guess from the current page.
- [x] Added `record_payment`: atomic payment + wallet legs + audit, interest
      first, date-order and overpayment guards, `client_id` idempotency, Nepal
      civil date, role check.
- [x] Added `void_payment`: newest live payment only, soft delete + wallet
      reversal, reopens a closed loan, idempotent re-void.
- [x] Added `close_loan`: freezes accrual on the Nepal date, requires an explicit
      write-off plus reason for any unpaid balance.
- [x] Direct payment writes and loan lifecycle writes revoked after migration 2.
- [x] `transactions.payment_id` is server-owned; composite tenant FK prevents
      forged cross-tenant links; principal legs excluded from cashflow.
- [x] Wallet transfers affect balances via `transfer_direction`.
- [x] Payments blocked offline instead of guessing prior allocations.
- [x] Party statement filters payments by party loan IDs, caps interest, honours
      `accrual_end_date`, and shows write-offs/outstanding adjustments.

### Offline and shared-device safety

- [x] Cache and outbox keys namespaced per user.
- [x] Outbox flushes only the current user's entries.
- [x] Auth changes invalidate providers; sign-out clears scoped cache/outbox.

### Database verification

- [x] Migration 1: tenancy/RLS/grants/audit/expand columns.
- [x] Migration 2: payment RPCs/backfills/lockdown.
- [x] `libpg-query` parses every migration and PL/pgSQL body.
- [x] PGlite PostgreSQL 18.6 applies all migrations.
- [x] Integration harness: 20/20 groups (RLS, grants, invite provisioning,
      isolation, split, idempotency, void/close/reopen, cap, 365-day math, audit).
- [x] Expand/contract harness: 11/11 groups (migration 1 legacy writes, then
      migration 2 lockdown/backfill).
- [x] `supabase/verify/security_checks.sql`: PASS.
- [x] `supabase/verify/smoke_test.sql`: PASS.
- [x] Fixed migration defects found by the harness: RLS on new tables, owner
      trigger scope, leftover `REFERENCES`/`TRIGGER`/`TRUNCATE` grants, explicit
      minimum grants, profile-role sync, voided-client-id retry, expand columns,
      explicit transaction control removed.

### Documentation

- [x] Added `docs/16-hardening-plan.md` (threat model, Nepal notes, scope tiers,
      residual risks, deployment order).
- [x] Rewrote `docs/15-runbook.md` (no free-tier PITR, manual dumps, expand/
      contract migration order, auth settings, invite bootstrap, rollback,
      alerts not deployed).
- [x] Rewrote `docs/02-scope.md`, `docs/08-supabase.md`,
      `docs/11-registration.md`, `docs/14-api-reference.md` and
      `docs/10-system-design.md` for membership tenancy, per-operation RLS and
      RPCs.

### Still open

- [x] Apply migration 9 (`payment_rpcs`) to the live project (2026-10-28).
      `security_checks.sql` now returns `PASS all_checks`.
- [ ] Disable public sign-up / enable email confirmation in the live project.
- [ ] Take and restore-test a manual `pg_dump`.
- [ ] Staging/prod split and automated backups.
- [ ] Member-admin UI, tenant switcher, invitation acceptance UI.
- [x] Alerts Edge function deployed (`dispatch-alerts`, v1, ACTIVE). In-app
      queue works; email/SMS skipped (no provider keys). Cron not yet scheduled.
- [ ] Cron scheduling: operator must add `service_role_key` to Vault and run
      the schedule SQL (see below). Channel decision: in-app only for Tier A.
- [ ] MFA, CAPTCHA/rate limits. CSP/security headers: accepted risk for
      Tier A (hosted on GitHub Pages, which cannot set headers); revisit if
      moving to a header-capable host.
- [x] Tier decision: Tier A (private ledger). Tier B only on pilot demand.
- [x] Party edit workflow added (UI + audit + id_number in model).
- [x] Loan edit RPC `update_loan_terms` added (active loans with no live
      payments only) + UI edit action (desktop + mobile).
- [x] Idempotency keys for ordinary transactions: `client_request_id` column +
      unique index; client generates UUID per save; outbox + online path treat
      unique violation (23505) as success.
- [x] PII masking for viewers: `parties_safe` view masks phone/address/id_number
      when `current_tenant_role()` is viewer; `parties_provider` reads from it.
- [x] Reconciliation view `reconciliation_exceptions` (missing wallet leg,
      amount mismatch, orphan wallet leg) with security_invoker.
- [x] Period close: `period_closes` table + `close_period`/`is_period_closed`
      RPCs + enforcement triggers on payments/transactions.
- [x] Audit export CSV button on Audit Trail page.
- [x] Tenant switcher: `active_tenant_id` on profiles + `current_tenant_id()`
      prefers it; `set_active_tenant` RPC; UserMenu switcher + Members page.
- [x] Member admin UI: invite (create_tenant_invite), role change, suspend/
      reactivate, remove; Members page + More entry.
- [x] EMI v2 (partial): persisted tenure_months + emi_amount columns;
      flat + reducing_balance schedule generation; tenure input in loan form.
      (Payment allocation, prepayment, penalty still pending.)
- [x] Maker-checker: `approval_requests` table + `request_approval`/
      `decide_approval` RPCs (self-decision blocked; approved decisions
      execute the underlying payment/void/close action) + Approval Inbox UI.
- [x] Alerts v2: `notification_preferences` table (per-user channels,
      due-soon window) + preferences page + Edge function v2 consults prefs.
- [x] MFA + session management: Security page with TOTP enroll/verify/
      unenroll and sign-out-other-sessions (Supabase Auth).
- [x] Nepali localization scaffold: l10n.yaml + app_en.arb + app_ne.arb
      (core labels) + MaterialApp delegates/supportedLocales + nav labels.
- [x] EMI v2 (more complete): persisted tenure + penalty_rate/prepayment_allowed
      columns; record_emi_payment RPC with installment allocation, late penalty,
      idempotency; emi_schedule provider merges paid status; Pay-next action.
- [x] Tier C foundations: KYC fields on parties (id_type, id_verified,
      risk_rating, consent/retention); vat_ledger + tds_ledger tables (RLS);
      Tax/Compliance report page (report-only).
- [x] Tier C compliance foundations: consent_records, retention_policies,
      incident_log tables (RLS); str_candidates view (goAML-style export);
      Tamasuk PDF export on ledger rows.
- [x] PII column-level enforcement: revoked SELECT on phone/address/id_number/
      id_type from authenticated on parties; new security-definer view
      parties_with_pii masks based on role (closes viewer bypass).
- [x] Phase 3 perf: indexes on 16 unindexed FKs; RLS initplan fix on
      audit_logs + profiles (3 policies) -> security_checks still PASS.
- [x] Phase 3 docs: staging/prod split procedure (17) + a11y checklist (18)
      + mobile build guide (19) + mobile CI workflow.
- [x] Search: client-side search on Parties and Payments pages.
- [x] Backup automation: scheduled GitHub Actions pg_dump workflow
      (.github/workflows/backup.yml) with 30-day artifact retention.
- [ ] Backup owner: TBD (assign a named operator before Phase 0).

## 2026-10-15 - P0/P1/P2 Baseline

### P0

- [x] 03 stale versions corrected to the then-current Flutter/PG/deps.
- [x] 04 missing future-day guard and payment-sum bug documented and fixed;
      flat/reducing methods flagged.
- [x] 07 unusable setup path rewritten for `app/`; seed duplicate warning added.
- [x] 01 success criteria marked PASS/PARTIAL/FAIL.
- [x] 02 actual vs planned split.
- [x] Payment preview sums prior `interest_amount` per loan; `deleted_at` added
      to 6 tables; providers filter it; archive buttons on ledger/parties/
      payments; import seed aborts when loans/parties exist; migrations exported
      to `supabase/migrations`; analyze/test/build verified.

### P1

- [x] Migrations exported; import seed count guard; `.env.example`.
- [x] Pages CI analyze/test/build (now hardened further on 2026-10-25).
- [x] `docs/14` PostgREST selects/RLS; `docs/15` runbook; `docs/10` staging split.
- [x] Profiles table + trigger + AuthGate role gating + `canWriteProvider`.
- [x] CI runs on pull requests (2026-10-25).
- [ ] Staging/prod project split (documented, not applied).

### P2

- [x] Budget tracker v1: accounts/categories/transactions/budgets schema, RLS,
      seed, CRUD, spent rollup, loan-txn link, dashboard charts, Excel/PDF,
      Decimal-exact Money, RLS checks, transaction/loan index.
- [x] Party statement (model/provider/page/PDF).
- [x] EMI schedule UI (model/provider/page/PDF).
- [x] Audit trail writer + sanitizer + hooks + audit page + tests.
- [x] Alerts bell/tray/Realtime/mark-read + Edge source (Edge/cron not deployed).
- [x] Widget tests (auth gate, dashboard, ledger, bell, empty/error states).
- [x] Offline Hive cache + outbox + banner + flush-on-reconnect + tests.
- [x] BS date pickers with dual AD/BS.
- [ ] Flat/reducing-balance end-to-end allocation (schema only).
- [ ] Edge deploy + cron schedule (needs provider keys and CLI).
- [ ] ERD/sequence diagrams, glossary, changelog/owners.

## Current Verification (2026-10-25)

- `flutter analyze`: No issues found.
- `flutter test` under UTC: 49/49.
- `flutter test test/bs_picker_test.dart test/widget/bs_picker_test.dart` under
  `Asia/Kathmandu`: 7/7.
- `flutter build web --release --base-href=/nhisab/ --no-wasm-dry-run`: success.
- SQL: 20/20 integration, 11/11 expand/contract, security checks PASS, smoke
  test PASS on PGlite 18.6.
- Not verified: live Supabase apply, PostgREST/JWT behavior, backup restore,
  Edge/cron, browser security headers.
