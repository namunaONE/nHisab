# 02 - Scope (Actual vs Planned)

Date: 2026-10-25. This file describes the code in this repository and the
database migrations that accompany it. It does not claim that the migrations are
applied to the live project. See `docs/16-hardening-plan.md` for the deployment
gates.

## Implemented

### Tenancy, auth and access control

- Invite-only sign-in. Public sign-up was removed from the client and must also
  be disabled in Supabase Auth.
- `tenants`, `tenant_members` and `tenant_invites`; roles `owner`, `manager` and
  `viewer`. One active organisation per user until a tenant switcher exists.
- Membership-derived `current_tenant_id()`; no shared-tenant fallback. A user
  without an active membership sees no rows and the app blocks.
- Fail-closed `AuthGate`: missing profile, empty tenant or unknown role is
  blocked, not elevated.
- Per-operation RLS and minimum column grants. Viewers can read but cannot write
  or invite. Only owners can create invitations. The last active owner cannot be
  removed or demoted.
- Profile role is a projection of `tenant_members.role`; a trigger keeps it in
  sync for UI gating. Authorization always uses the membership row.
- Password reset via Supabase Auth. No OTP, MFA or social login.
- Audit log is append-only; actors cannot spoof another user.

### Ledger and money

- Parties: list, add, archive (soft delete), optional ID number, phone and
  address. No edit UI and no ID-threshold enforcement yet.
- Loans: add and list, direction receivable/payable, rate `%` UI converted to a
  decimal, rate types daily/monthly/annual, day base 360/365, soft delete,
  close with an optional explicit write-off and reason. No loan edit UI.
- Payments: list 200 most recent, add with preview, void through the server RPC.
  `record_payment` allocates interest first, caps cumulative interest at the
  principal, rejects future/pre-start/out-of-order/overpaid payments, and is
  idempotent on `client_id`. Payments cannot be recorded offline.
- Daily accrual: `PerDay = round(Principal × AnnualRate / DayBase, 2)`,
  `Interest = round(PerDay × DueDays, 2)`. Future loans accrue zero, not
  backwards. `dues` and `outstanding` separate unpaid interest from unpaid
  principal.
- `void_payment` soft-deletes only the newest live payment for a loan, reverses
  its wallet legs, and reopens a closed loan.
- `close_loan` freezes accrual on the Nepal civil date and requires an explicit
  write-off plus reason for any unpaid balance.
- Wallet transfers affect balances through `transfer_direction`; principal
  movements are excluded from cashflow so they are not double-counted.
- Party statement: payments filtered by the party's loans, interest capped,
  accrual stops on `accrual_end_date`, write-offs and outstanding adjustments
  shown. PDF export exists.

### Budget tracker

- Accounts (cash/bank/mobile wallet), categories (income/expense), transactions
  (income/expense/transfer, optional loan link) and monthly budgets. FY bucketing
  is an approximation on the AD calendar (July-June, Shrawan=1) labelled as the
  Nepali FY; exact BS-day boundaries are not implemented.
- Dashboard: net-worth, cashflow bars, budget donut and overdue strip using
  `fl_chart`.
- Excel import/export and PDF summary. The seed guard aborts when parties or
  loans already exist.

### Offline and reliability

- Hive read cache with per-user namespaces; providers fall back to the cache only
  when the network fails and a cache exists.
- Outbox for ordinary failed inserts, namespaced per user. It flushes only the
  current user's entries.
- Money writes (payments/voids/closes) require a connection; the cache is not a
  source of truth.
- Auth changes invalidate in-memory providers; sign-out drops the cache/outbox
  scopes so another account cannot read or replay the previous user's entries.

### CI and tests

- GitHub Actions: analyze, UTC test suite, Nepal-time calendar tests, web build;
  pull requests run checks but do not deploy. Flutter pinned to the locally
  verified version.
- Unit/widget tests cover the calculator, BS conversion under two time zones,
  auth gating, roles, cache/outbox scoping, transfers and money splitting.
- SQL verification scripts:
  - `supabase/verify/security_checks.sql` (read-only catalog checks)
  - `supabase/verify/smoke_test.sql` (staging-only, transactional)
- Local PGlite PostgreSQL 18.6 suites passed 20/20 integration groups and 11/11
  expand/contract groups. These harnesses are development tools, not a Supabase
  substitute.

## Partial / not deployed

- **Alerts:** `notification_queue`, the in-app bell and the `dispatch-alerts`
  Edge source exist, but the Edge function is not deployed and the cron
  migration is entirely commented out. No email or SMS is sent.
- **EMI:** the formula and schedule model/UI exist, but payment allocation and
  interest accrual are daily-accrual only. `reducing_balance` and `flat` are
  accepted by the schema/form but are not implemented end to end.
- **Reports:** Excel/PDF export exists; there is no accountant-grade general
  ledger, trial balance or statutory return.
- **Audit:** payments, voids and closes write server-side audit rows. Ordinary
  writes rely on the app's fire-and-forget audit writer and can be omitted by a
  malicious client.
- **Backups:** manual `pg_dump` only. The free tier has no PITR or downloadable
  platform backups. No restore drill has been recorded in the repository.
- **Hosting:** GitHub Pages cannot set CSP/COOP/COEP headers. The build uses the
  JavaScript/CanvasKit path.

## Known gaps

- No staging/prod split; no live application of the tenancy or RPC migrations.
- No member-admin UI, tenant switcher, invitation acceptance screen, or ownership
  transfer. Invites are created with SQL plus the Supabase dashboard.
- No maker-checker, approval workflow, reconciliation report or period close.
- No MFA, CAPTCHA, Auth rate-limit configuration or CSP.
- No KYC/AML verification, goAML export or consent/retention workflow.
- No VAT/TDS filing, CBMS/e-billing or IRD-compatible reports.
- No Nepal-hosted data; the project is in Mumbai. This blocks regulated-lender
  residency requirements.
- Viewer can read all tenant PII, including ID numbers.
- Outbox replay for ordinary transactions can duplicate a write if the first
  request committed but the response was lost.
- Loan corrections require voiding/re-entering payments or operator SQL; there is
  no edit workflow.

## Out of scope (unchanged)

SaaS billing, double-entry accounting, bank auto-import, statutory filing,
multi-branch cooperative accounting, member shares/savings and core-banking
integration. These belong to scope tiers C/D in `docs/16-hardening-plan.md`.

## Constraints

- Postgres is the source of truth. AD `DATE` is stored; BS is a display/input
  layer.
- `NUMERIC(15,2)` for money; Dart uses Decimal-exact intermediates in
  `core/money`, with `round2` at the public API boundary.
- No hard deletes for financial rows. `deleted_at` plus RLS and grants preserve
  history.
- Nepal civil dates on the server use `Asia/Kathmandu`, not `current_date`.
- Deployment is expand/contract: tenancy migration, hardened client, then payment
  lockdown. See `docs/15-runbook.md`.
