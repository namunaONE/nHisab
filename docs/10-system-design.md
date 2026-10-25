# 10 - System Design - nHisab Full Stack

Date: 2026-10-25. Status: Phase 0-2 implemented; P0 trust-boundary hardening
implemented in code and migrations but not applied to the live Supabase project.
Scope tier (A-D) is still undecided; see `docs/16-hardening-plan.md`.

Project: Supabase `nhisab` `qcbxurqxmnkzgsfpaesz` `ap-south-1`. App: Flutter Web
PWA in `app/`, hosted on GitHub Pages.

## 1. Goals and Constraints

Goals:

- Replicate the source 13-column lending sheet: principal, rate, dates, due days,
  per-day interest, interest, paid, dues, total.
- Daily accrual `PerDay = round(Principal × AnnualRate / DayBase, 2)` with 360 as
  the default to match the sheet (`1,500,000 × 0.18 / 360 = 750.00`).
- Interest-first payments, capped at the principal (Civil Code 2074 s.481).
- Dual AD/BS dates, Nepali fiscal year, Excel/PDF output, party statements.
- Multi-tenant data with invite-only users, roles and an audit trail.
- No silent money corruption: money writes are atomic or they fail.

Constraints:

- Postgres is the source of truth. AD `DATE` is stored; BS is display/input.
- `NUMERIC(15,2)` in the database; Decimal-exact intermediates in Dart, rounded
  at the public API boundary.
- RLS on every table, per-operation policies, minimum grants, no `anon` surface.
- Web-first PWA, read cache and outbox, but **no offline payment writes**.
- Free-tier Supabase has no PITR; backups are manual.
- No service-role key in the client.
- No compliance claim beyond scope tier A/B.

## 2. Architecture

```
Browser PWA (Flutter Web)
  Riverpod UI
  Supabase Auth (JWT) + PostgREST + Realtime
  Hive read cache + per-user outbox
        |
        | HTTPS, publishable key + user JWT
        v
Supabase ap-south-1
  Postgres 17
    tenants, tenant_members, tenant_invites, profiles
    parties, loans, payments, emi_schedules
    accounts, categories, transactions, budgets
    notification_queue, audit_logs
    RLS + column grants + tenant FKs
    SECURITY DEFINER RPCs:
      current_tenant_id/current_tenant_role/is_tenant_writer
      nepal_today
      record_payment / void_payment / close_loan
      create_tenant_invite
    Auth: email/password, invite-only, email confirmation
  Realtime: notification_queue (bell)
  Edge dispatch-alerts: source exists, NOT deployed
  pg_cron: NOT scheduled
```

Request paths:

- **Read ledger:** Flutter -> PostgREST with JWT -> RLS tenant filter -> rows ->
  client computes per-day/dues/total for the selected date. Cache is written per
  user; on network failure the last cache is served.
- **Write ordinary row:** Flutter -> PostgREST insert with only granted columns
  -> RLS writer check -> app audit row -> invalidate providers.
- **Record payment:** Flutter -> `record_payment` RPC -> loan row lock -> interest
  accrual/cap -> payment + wallet legs + audit in one transaction -> JSON result.
- **Void/close:** RPC only; no direct payment or loan-lifecycle writes.
- **Alerts (planned):** pg_cron -> pg_net -> Edge `dispatch-alerts` -> provider ->
  `notification_queue`. Not deployed.

## 3. Frontend Design

Location: `app/lib/src/`.

Core:

- `core/calculator/loan_calculator.dart` - accrual, rate conversion, cap, dues,
  outstanding, split, EMI. Unit tested.
- `core/money/money.dart` - Decimal-exact intermediates.
- `core/dates/bs_date.dart`, `bs_picker.dart` - AD/BS conversion with civil-date
  arithmetic independent of the machine time zone.
- `core/cache/cache_service.dart`, `outbox.dart` - per-user Hive namespaces.
- `core/audit/audit_service.dart` - fire-and-forget audit writer for ordinary
  writes. RPCs write their own audit rows server-side.
- `core/ids.dart` - UUID v4 generator for payment idempotency.

Features:

- `auth`: fail-closed `AuthGate`, invite-only `LoginPage`, profile/role provider,
  `signOutAndClear`.
- `home`: `HomeShell` navigation and ledger. Desktop DataTable and mobile cards.
- `parties`, `loans`, `payments`: forms, lists, close/write-off dialog, statement.
- `accounts`, `categories`, `transactions`, `budgets`, `dashboard`: wallet-first
  budget tracker.
- `import`: Excel import with a non-empty guard; seed data.
- `notifications`: bell/tray backed by `notification_queue`; no scheduler.

State: Riverpod `FutureProvider`/`StateProvider`, invalidated after writes and on
auth change. No global mutable singleton except the Supabase client and the
static Hive boxes.

Web:

- `flutter build web --release --base-href=/<repo>/ --no-wasm-dry-run`.
- GitHub Pages serves the JS/CanvasKit build. Pages cannot set CSP/COOP/COEP
  headers, so the Wasm SharedArrayBuffer path is not used.
- PWA manifest and service worker are generated.
- The app is a private ledger; SEO is irrelevant.

Offline:

- Reads: read-through cache keyed per user. A cache miss with the network down
  surfaces an error, not an empty list.
- Writes: ordinary inserts may be queued in the outbox and replayed by the
  current user. Payments/voids/closes require a connection because the allocation
  must be authoritative.
- On sign-out, scoped caches are cleared and providers invalidated so a shared
  browser cannot show the previous user's rows.

## 4. Backend Design

### 4.1 Tenancy and identity

- `tenants` is the organisation. The prototype UUID
  `00000000-0000-0000-0000-000000000001` is preserved for existing data.
- `tenant_members(tenant_id,user_id,role,status)` is authoritative. One active
  membership per user until a tenant switcher exists.
- `tenant_invites` is an allow-list for provisioning. The `auth.users` trigger
  creates `profiles` and `tenant_members` only for a valid, unexpired invite.
- `profiles` is the UI projection: display name, contact, role, tenant. Role is
  synced from membership; the client cannot write role or tenant.
- `current_tenant_id()` resolves the active membership, not a JWT claim and not a
  shared default. No membership means NULL, and RLS returns no rows.

### 4.2 RLS and grants

- Per-operation policies for `SELECT`/`INSERT`/`UPDATE`/`DELETE`; no `ALL`.
- Reads: `tenant_id = current_tenant_id()`.
- Writes: tenant match plus `is_tenant_writer(tenant_id)`.
- Profiles: own row; only `display_name`/`phone` are updateable.
- Tenancy administration: owner only, with last-owner protection.
- Audit: append-only trigger, no update/delete grants, actor must be caller.
- Table-level DML is revoked. Column grants define the exact payload a client can
  write; this blocks `tenant_id`, `role`, `loans.status`,
  `transactions.payment_id`, void fields and lifecycle fields.
- Composite tenant FKs prevent cross-tenant party/loan/payment references.
- `anon` has no table, sequence or function grants.

### 4.3 Loans and payments

- Loan terms are client-insertable; lifecycle (`status`, `accrual_end_date`,
  `closed_*`, `write_off_*`) is server-owned.
- `record_payment` locks the loan `FOR UPDATE`, validates the date and method,
  computes per-day interest from the loan terms, caps cumulative interest at the
  principal, pays interest first, rejects overpayment, inserts wallet legs and
  audit, and returns the split.
- Idempotency: `(tenant_id, client_id)` unique partial index. Same request
  returns the original row; changed terms or a voided payment raise `23505`.
- `void_payment` only reverses the newest live payment, so allocations remain
  reproducible. It soft-deletes wallet legs and reopens a closed loan.
- `close_loan` freezes accrual on the Nepal civil date. Any unpaid balance
  requires `write_off = true` and a reason.
- Daily accrual is implemented end to end. `reducing_balance` and `flat` are
  accepted by schema/form but not implemented in the payment split; do not use
  them for live money until tested.
- EMI formula and schedule UI exist; payment allocation still uses daily accrual.

### 4.4 Nepal dates

- `nepal_today()` = `(now() at time zone 'Asia/Kathmandu')::date`.
- Server-side close/void/validation uses this, not `current_date`, because
  Supabase runs in UTC and Nepal is UTC+05:45.
- Client BS conversion uses civil-date helpers, not local-midnight timestamps.
  CI runs the calendar tests under UTC and `Asia/Kathmandu`.

## 5. Auth and Security

- Email/password only. Public sign-up disabled at Auth and removed from the app.
- Invite-only provisioning; the first owner is bootstrapped with an invite row
  plus the dashboard invite.
- Password reset via Supabase email.
- Fail-closed gate: no profile, no tenant, unknown role, or profile error blocks
  the app. Viewer sees a read-only banner.
- Publishable key in the browser; service role only server-side. No Edge function
  is deployed today.
- No MFA, CAPTCHA, custom rate limit or CSP. See the threat model in `docs/16`.
- Secrets: `SUPABASE_URL`/`SUPABASE_ANON_KEY` via GitHub Actions secrets. The
  development fallback in `main.dart` is a publishable key and should be
  overridden in production.
- Audit: payment/void/close audit is server-side. Ordinary write audit is
  client-side and can be omitted by a crafted client; it is not a compliance
  control.

## 6. Notifications (designed, not deployed)

- `notification_queue(id, tenant_id, loan_id, alert_type, channel, status,
  scheduled_at, sent_at, ...)`.
- The in-app bell reads this table and uses Realtime invalidation; users can mark
  rows read.
- `supabase/functions/dispatch-alerts/index.ts` is source only.
- `20261015170000_alert_cron.sql` is entirely commented out. No pg_cron job, no
  Edge deployment, no Resend/SMS credentials.
- Do not advertise due/overdue email or SMS until the function and scheduler are
  deployed and monitored.

## 7. Data Integrity and Money

- Database: `NUMERIC(15,2)`, checks for positive principal, non-negative rate,
  valid day base, payment split consistency and void consistency. Some legacy
  checks are `NOT VALID` so old rows do not block the deploy.
- Dart: Decimal intermediates; rounded rows; footers sum rounded rows.
- Payment split is server-authoritative. The client preview uses the same formula
  but is never trusted to post.
- Interest cap: cumulative interest ≤ principal (Civil Code 2074 s.481).
- `dues` = unpaid interest; `outstanding` = unpaid principal + unpaid interest.
  Principal repayment does not reduce unpaid interest.
- Principal wallet legs are tagged `excluded_from_cashflow`; interest legs count
  as income/expense. Transfers carry `transfer_direction` so wallet balances are
  correct without double-counting.
- Legacy payment links are backfilled only when unambiguous. Ambiguous rows stay
  null and need manual reconciliation; the verification script reports them.
- Soft deletes preserve history. Payment void is RPC-only.
- Manual backups only. See `docs/15-runbook.md`.

## 8. Performance and Scale

- Indexes cover tenant filters, party/loan FKs, due dates, notification status,
  payment links and the unique idempotency key.
- Reads are paginated at 200 for payments/transactions; the ledger is a client
  DataTable with horizontal scroll and a mobile card layout.
- RLS predicates are simple tenant/role checks; role helpers are `STABLE`
  definer functions to avoid recursive policy evaluation.
- Future: server-side aggregate views for footers above ~10k rows, keyset
  pagination, and a reconciliation view. No caching layer beyond Hive today.
- Realtime is limited to notification rows; the ledger is invalidated after
  writes rather than streamed.

## 9. Deployment - GitHub Pages

- Build: `flutter build web --release --base-href=/<repo>/ --no-wasm-dry-run`.
- CI/CD: `.github/workflows/pages.yml`.
  - `actions/checkout@v5`, Flutter 3.47.7.
  - `flutter analyze`.
  - `flutter test` under `TZ=UTC`.
  - Calendar tests under `TZ=Asia/Kathmandu`.
  - Build with optional `SUPABASE_URL`/`SUPABASE_ANON_KEY` secrets.
  - Pull requests run checks only; deploy job is skipped.
  - Deploy on push to `main`/manual dispatch; per-ref concurrency; 20-minute
    timeout.
- Pages source: GitHub Actions. Live URL follows the repository name; the
  workflow computes the base href.
- No custom headers on Pages. A custom host is required for CSP/COOP/COEP.

## 9.5 Staging / Production Split (planned)

The single project has served as dev and prod. Before real money:

1. Create `nhisab-staging` and `nhisab-prod` projects (same org/region or a
   Nepal-compliant region if required).
2. Link each environment and apply migrations in order:
   `init`, `fix_lints`, `add_soft_delete`, `budget_tracker_v1`,
   `fix_txns_loan_index`, `profiles_table`, tenancy, payment RPCs.
3. Use separate GitHub environments/secrets per project.
4. Back up prod before every migration; run `security_checks.sql` and
   `smoke_test.sql` on staging only.
5. Promote data with a filtered `pg_dump`, never by pointing staging at prod.
6. Keep a restore drill record.

Do not split until the operational cost is funded; a shared project with tenant
RLS is acceptable for tier A only if backups and access are controlled.

## 10. Testing and Observability

- `flutter analyze`: clean.
- `flutter test` under UTC: 49 tests passing.
- Calendar tests under `Asia/Kathmandu`: 7 tests passing (the two BS files also
  run in the UTC suite; the dedicated run proves timezone independence).
- `flutter build web`: succeeds.
- SQL:
  - `security_checks.sql`: PASS locally.
  - `smoke_test.sql`: PASS locally.
  - 20/20 integration groups, 11/11 expand/contract groups on PGlite 18.6.
- These are local results. Supabase PostgREST/JWT/RLS behavior still requires a
  staging project.
- Observability is minimal: Supabase logs, Auth logs, `audit_logs` and
  `notification_queue`. No error tracker, uptime monitor, alert or backup
  verification job.
- Crash reporting hook exists (`recordError`), but no backend sink.

## 11. Decisions (ADRs)

- **ADR1 Shared project + tenant RLS, not per-tenant projects.** Lower cost and
  instant tenancy, at the price of strict RLS discipline.
- **ADR2 360-day banker default with 365 option.** Matches the source sheet.
- **ADR3 NUMERIC in Postgres, Decimal in Dart.** Avoids float drift.
- **ADR4 Hive read cache + outbox, not PowerSync.** Avoids sync-rule complexity;
  Postgres remains the source of truth. Payments do not use the outbox.
- **ADR5 Invite-only membership.** Public sign-up plus a shared tenant was the
  original data leak; invites are the minimum safe provisioning model.
- **ADR6 Expand/contract migrations.** Deploy the client before revoking legacy
  payment writes.
- **ADR7 Server-authoritative money.** The browser previews; the RPC posts.
- **ADR8 No compliance claims.** Tier C/D work is explicitly out of scope until
  funded and audited.

## 12. Risks and Open Questions

- Migrations are not applied to the live project; the current live schema still
  has the shared tenant and direct payment writes.
- No staging environment, automated backup or restore drill.
- Scope tier is unconfirmed. Do not promise VAT/TDS/CBMS/KYC or cooperative
  features.
- `reducing_balance`/`flat` are schema options without an end-to-end
  implementation.
- Alerts/Edge/cron are not deployed.
- No MFA/CSP/rate limiting; GitHub Pages cannot set headers.
- Viewer sees all tenant PII; no masking.
- Outbox replay for ordinary transactions can duplicate after a lost response.
- Loan rate corrections require void/re-entry or operator SQL; no edit UI.
- Interest accrual is simple daily accrual, not a full amortization schedule.
- Data residency: Supabase Mumbai may not satisfy NRB requirements for regulated
  lenders.
- The Machhapuchhre `0.80` rate remains a data question; verify with the bank
  before changing it.
- TDS percentage/application needs an accountant's confirmation.
