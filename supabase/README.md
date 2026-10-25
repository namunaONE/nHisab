# Supabase - nHisab

Project: `nhisab` `qcbxurqxmnkzgsfpaesz`, `ap-south-1`. See `docs/08-supabase.md`
for project facts and `docs/15-runbook.md` for the deployment procedure.

## Migrations

Apply in this order. The tenancy migration is expand; the payment migration is
contract and must come after the hardened client is live.

1. `20261015065947_init_nhisab_schema.sql`
2. `20261015070054_fix_lints.sql`
3. `20261015073715_add_soft_delete.sql`
4. `20261015140000_budget_tracker_v1.sql`
5. `20261015150000_fix_txns_loan_index.sql`
6. `20261015160000_profiles_table.sql`
7. `20261015170000_alert_cron.sql` (entirely commented out; nothing scheduled)
8. `20261025120000_tenant_membership_rls.sql`
9. `20261025121000_payment_rpcs.sql`

Steps 8 and 9 are **not applied** as of 2026-10-25. Do not add explicit
`BEGIN`/`COMMIT` to migration files; the Supabase runner owns the transaction.

## Verification

- `verify/security_checks.sql` - read-only catalog/privilege checks. Run as
  `postgres`; expect one `PASS all_checks` row.
- `verify/smoke_test.sql` - staging only. Impersonates the oldest active owner,
  exercises the RPCs and RLS, then rolls back.
- `tests/rls_check.sql` - deprecated; use `verify/security_checks.sql`.

The local PGlite/libpg-query harnesses used during development are not committed.
They are not a substitute for a staging Supabase project.

## Auth

Public sign-up must be disabled. New users are provisioned only by an invite row
plus a dashboard invite. See `docs/15-runbook.md` section 4.

## Edge / Cron

`functions/dispatch-alerts/index.ts` is source only and is not deployed. No
`pg_cron` job is scheduled. Do not claim email/SMS alerts are active.
