# 08 - Supabase Project nhisab

## Project

- Name: `nhisab`
- Ref: `aldbvbpbittvhkecnfpx`
- Org: Namuna One (`roxuaraiptvmqmnmwcmw`)
- Region: `ap-south-1` (Mumbai, India)
- URL: `https://aldbvbpbittvhkecnfpx.supabase.co`
- DB host: `db.aldbvbpbittvhkecnfpx.supabase.co`
- Postgres: 17.11 as last verified 2026-10-15. Confirm in the dashboard before
  applying SQL.
- Plan: free tier as of 2026-10-25. No PITR and no downloadable platform backup.

## Keys

- Publishable/anon key: safe to ship in a browser bundle; RLS and grants are the
  protection. Prefer `--dart-define=SUPABASE_ANON_KEY=...` from GitHub Actions
  secrets over the development fallback in `app/lib/main.dart`.
- Service role key: bypasses RLS. Never ship it, screenshot it or commit it.
- Database password: operator-only, stored in a password manager.
- Dashboard > Project Settings > API and Database.

## Schema History

Applied to the live project before 2026-10-25:

1. `20261015065947_init_nhisab_schema` - parties, loans, payments,
   emi_schedules, notification_queue, audit_logs, RLS, indexes,
   `current_tenant_id()` (shared fallback), `handle_updated_at()`.
2. `20261015070054_fix_lints` - missing index, `search_path` fixes.
3. `20261015073715_add_soft_delete` - `deleted_at` on financial tables.
4. `20261015140000_budget_tracker_v1` - accounts, categories, transactions,
   budgets; seeded 3 accounts and 8 categories.
5. `20261015150000_fix_txns_loan_index` - transaction/loan index.
6. `20261015160000_profiles_table` - profiles, shared-tenant default, owner
   default, `handle_new_user()`.
7. `20261015170000_alert_cron` - entirely commented out; nothing scheduled.

Applied as of 2026-10-28:

8. `20261025120000_tenant_membership_rls` - invite-only tenancy, membership-based
   `current_tenant_id()`, per-operation RLS, minimum column grants, composite
   tenant FKs, append-only audit, last-owner protection, profile-role sync, and
   the expand-phase columns needed before payment lockdown.
9. `20261025121000_payment_rpcs` - `record_payment`, `void_payment`,
   `close_loan`, `nepal_today()`, backfills, and revocation of direct payment
   writes and anon access. Applied 2026-10-28; `security_checks.sql` returns
   `PASS all_checks`.

10. `20261028230000_first_owner_bootstrap` - in-app first-owner setup:
    `system_needs_bootstrap()` (truthful while `tenant_members` is empty) and
    `bootstrap_first_owner(email, password, tenant_name)` (creates the auth
    user + first tenant + owner membership + profile, fails closed once any
    membership exists). The login page shows a First-time setup panel with the
    owner email prefilled (`work.htpl@gmail.com`) while this is true.

Remaining manual steps: disable public sign-up / enable email confirmation in
Auth (after the first owner exists), deploy alerts Edge + cron, schedule
backups. First-owner bootstrap no longer needs SQL or the dashboard.

## Current Data Model

- Tenancy: `tenants`, `tenant_members`, `tenant_invites`, `profiles`.
- Lending: `parties`, `loans`, `payments`, `emi_schedules`.
- Money/wallets: `accounts`, `categories`, `transactions`, `budgets`.
- Operations: `notification_queue`, `audit_logs`.

Every business table carries `tenant_id`, is RLS-enabled, has soft-delete where
appropriate, stores money as `NUMERIC(15,2)` and dates as `DATE` (AD). Tenant
foreign keys are composite so a row cannot reference another tenant's party,
loan or payment.

## Security Model (after both migrations)

- `anon` has no table, sequence or function grants. RLS is not the only barrier.
- `authenticated` has table-level `SELECT` and narrowly scoped column grants.
  Table-level `INSERT`/`UPDATE`/`DELETE` are revoked except `tenant_invites`
  delete (an owner may revoke a pending invitation).
- RLS is per operation (`SELECT`, `INSERT`, `UPDATE`, `DELETE`), never `ALL`.
  Reads require `tenant_id = current_tenant_id()`; writes additionally require
  `is_tenant_writer(tenant_id)` except audit self-insert.
- `profiles`: own row only; client can update `display_name` and `phone` only.
- `payments`: `SELECT` only. Money movement goes through the RPCs.
- `loans`: client can insert business terms and archive (`deleted_at`) but cannot
  set `status`, `accrual_end_date`, `closed_*` or `write_off_*`.
- `transactions`: append-only from the client; only `deleted_at` is updateable.
  `payment_id` is server-owned.
- `audit_logs`: append-only trigger; actor must equal `auth.uid()`.
- Definer functions use `set search_path = ''` and repeat tenant/role checks.

## Auth Settings (manual)

- Public sign-up: **off**.
- Email confirmation: **on**.
- Site URL / redirect allow-list: deployed app URL.
- Anonymous sign-ins: **off**.
- Password reset enabled.
- No MFA, CAPTCHA or custom rate limits configured.

New users are provisioned only by invitation. Insert a `tenant_invites` row, then
invite the address from Dashboard > Authentication > Users. The trigger creates
`profiles` and `tenant_members`. Without an invite, the user authenticates but
the app blocks and no data is readable.

## Verification

Read-only catalog checks:

```sql
\i supabase/verify/security_checks.sql
```

Expected result: one `PASS all_checks` row. Any other row is a violation.

Staging-only transactional smoke test:

```sql
\i supabase/verify/smoke_test.sql
```

It impersonates the oldest active owner, records a payment, rejects an
overpayment, proves direct payment writes fail, closes with a write-off, voids and
reopens, then rolls back.

Supabase-specific checks that PGlite cannot cover:

- PostgREST returns `PGRST202`/`42883` when the RPC is missing; the client falls
  back only in that case.
- A real JWT with no membership reads zero rows and the app shows the blocked
  screen.
- A viewer's direct `POST /rest/v1/payments` is denied.
- Password reset redirects to the correct Pages URL.
- Realtime for `notification_queue` is scoped to the tenant.

## Current Verification Snapshot (2026-10-15, pre-hardening)

- 21 parties, 21 loans, 0 payments, 0 EMI rows, 0 notifications, 0 audit rows.
- A test loan of Rs 1,500,000 at 0.18 annual, day base 360, start 2026-06-19
  produced per-day 750.00, 118 days, interest 88,500.00, total 1,588,500.00,
  matching the source sheet. Test rows were removed.
- These counts predate the hardening migrations. Re-check before assuming the
  live data still matches.

## Next

1. Back up the live database.
2. Apply migration 8, deploy the hardened client, apply migration 9.
3. Run both verification scripts and the manual cross-tenant/viewer checks.
4. Configure Auth settings and bootstrap owners.
5. Schedule off-platform `pg_dump` backups.
6. Do not enable alerts until the Edge function and cron are actually deployed.
