# nHisab - Loan Records & Interest Calculator for Nepal

## Goal

Replace a manual Excel lending ledger with an invite-only Flutter Web PWA on
Supabase:

- Track money lent and borrowed, with per-party statements.
- Daily accrual `PerDay = Principal * AnnualRate / DayBase`, 360-day default,
  365-day option.
- Interest-first payments capped at the principal (Civil Code 2074 s.481).
- Dual AD/BS dates, Nepal FY budgets, Excel/PDF exports.
- Multi-tenant data with owner/manager/viewer roles, RLS, an audit trail and
  atomic, idempotent payment recording.

The database is the source of truth. The browser previews calculations but does
not authorise or post money writes.

## Status (2026-10-25)

- Flutter 3.47.7 / Dart 3.13.5, Supabase, GitHub Pages.
- `flutter analyze`: clean.
- Tests: 49/49 under UTC; 7/7 calendar tests under `Asia/Kathmandu`.
- `flutter build web`: succeeds.
- Tenancy, RLS and payment-RPC migrations are written and locally verified on
  PostgreSQL 18.6 (PGlite): 20/20 integration groups, 11/11 expand/contract
  groups, security checks and smoke test PASS.
- **The hardening migrations are not applied to the live Supabase project.** The
  live schema may still have the shared tenant and direct payment writes. See
  `docs/15-runbook.md` before deploying.
- Public sign-up is removed from the app and must be disabled in Supabase Auth.
- Alerts: Edge function and cron are **not deployed**. No email/SMS is sent.

## Repository

```
app/                  Flutter Web app
  lib/src/core/       calculator, money, dates, cache, audit
  lib/src/features/   auth, ledger, parties, loans, payments, wallets, budgets
  test/               unit and widget tests
supabase/
  migrations/         schema, tenancy/RLS, payment RPCs
  verify/             security_checks.sql, smoke_test.sql
  functions/          dispatch-alerts source (not deployed)
docs/                 design, API, runbook, threat model
.github/workflows/    analyze, test, build, Pages deploy
```

## Run

```powershell
cd app
flutter pub get
flutter analyze
$env:TZ='UTC'; flutter test --reporter expanded
flutter run -d chrome
```

Override the development Supabase key:

```powershell
flutter run -d chrome `
  --dart-define=SUPABASE_URL=https://qcbxurqxmnkzgsfpaesz.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_...
```

Never pass a service-role key to the app.

## Deploy

CI (`.github/workflows/pages.yml`) runs analyze, the UTC test suite, the Nepal-time
calendar tests, and a web build. Pull requests do not deploy. Pushes to `main`
deploy to GitHub Pages with a base href derived from the repository name.

Database deployment is expand/contract:

1. back up with `pg_dump`;
2. apply `20261025120000_tenant_membership_rls.sql`;
3. deploy the hardened client;
4. apply `20261025121000_payment_rpcs.sql`;
5. run `security_checks.sql` and, on staging, `smoke_test.sql`.

See `docs/15-runbook.md` for the exact procedure, auth settings and invite
bootstrap.

## Security Model

- Invite-only users; `tenant_members` is authoritative for role and tenant.
- Membership-derived `current_tenant_id()`, no shared fallback.
- Per-operation RLS, minimum column grants, composite tenant FKs.
- `payments` is read-only to clients after migration 2; money moves through
  `record_payment`, `void_payment` and `close_loan`.
- Audit log is append-only; last-owner protection; profile role sync.
- Offline reads use a per-user cache; payments require a connection.
- Free-tier Supabase has no PITR. Backups are manual `pg_dump`.

## Docs

- `docs/01-goal.md` - success criteria
- `docs/02-scope.md` - actual vs planned
- `docs/03-stack.md` - stack and versions
- `docs/04-business-logic.md` - accrual, payment split, lifecycle, Nepal notes
- `docs/05-design-system.md` - visual system
- `docs/06-roadmap-execution.md` - phases
- `docs/07-getting-started.md` - local setup
- `docs/08-supabase.md` - project, schema history, auth settings
- `docs/09-phase2-complete.md` - historical phase 2 notes
- `docs/10-system-design.md` - architecture, security, deployment
- `docs/11-registration.md` - invite-only provisioning and party data
- `docs/12-gaps-fix-log.md` - what was fixed and what remains
- `docs/13-codebase-standards.md` - engineering rules
- `docs/14-api-reference.md` - PostgREST reads, grants, RPC signatures
- `docs/15-runbook.md` - backup, migrations, auth, recovery, keys
- `docs/16-hardening-plan.md` - threat model, Nepal compliance, scope tiers A-D

## Legal / Compliance

This is a private lending ledger, not a VAT/TDS filing system, KYC/AML platform or
cooperative core-banking system. The migration code is tested locally but has not
been audited or applied to production. Do not market Tier C/D compliance until the
gaps in `docs/16-hardening-plan.md` are funded and closed.
