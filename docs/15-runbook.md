# 15 - Runbook - Migrations, Backup, Auth, Recovery and Keys

Date: 2026-10-25. Project `nhisab` `qcbxurqxmnkzgsfpaesz`, region `ap-south-1`
(Mumbai), Postgres 17.11 as last reported by the dashboard. Verify the live
version before applying SQL; the migration set is also tested on PostgreSQL
18.6.

This runbook replaces the 2026-10-15 version, which incorrectly claimed that
free-tier PITR was available and that pg_cron/Edge alerts were deployed.

## 1. Backup and Restore

### What the free tier actually provides

As of 2026-10-25, the Supabase free plan does **not** include point-in-time
recovery (PITR) and does not expose downloadable platform backups. Daily backups
and PITR are paid-plan features. Do not plan a recovery around a feature you have
not verified in Dashboard > Project Settings > Database.

The primary backup is therefore a **manual logical dump** taken by the operator.
For a real lending deployment, either upgrade to a plan with backups or run the
dump on a schedule outside Supabase.

### Manual dump (run before every migration and weekly)

Windows PowerShell:

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$env:PGPASSWORD = '<database password>'   # Dashboard > Settings > Database
pg_dump `
  --host db.qcbxurqxmnkzgsfpaesz.supabase.co `
  --port 5432 --username postgres --dbname postgres `
  --schema=public --no-owner --no-privileges `
  --file "nhisab-$stamp.sql"
Remove-Item Env:PGPASSWORD
```

Bash:

```bash
PGPASSWORD='<database password>' pg_dump \
  -h db.qcbxurqxmnkzgsfpaesz.supabase.co -p 5432 -U postgres -d postgres \
  -n public --no-owner --no-privileges \
  -f "nhisab-$(date +%F-%H%M).sql"
```

The dump must include:

- `public` schema and data (parties, loans, payments, transactions, audit logs,
  tenancy tables).
- `auth.users` is **not** in `public`. Export it separately with the Supabase
  dashboard's auth export, or accept that users must be re-invited after a
  restore. Do not put password hashes in a shared folder.
- Storage objects, if any are ever added. The app does not use Storage today.

Store at least two copies off the Supabase account (encrypted local disk plus a
controlled cloud location). Test a restore before you need it.

### Restore into a new project

```bash
createdb nhisab_restore
psql -d nhisab_restore -f nhisab-YYYYMMDD-HHMM.sql
```

For a Supabase restore, create a new project, connect with `psql`, and load the
dump there. Verify:

```sql
select 'parties' as t, count(*) from public.parties
union all select 'loans', count(*) from public.loans
union all select 'payments', count(*) from public.payments
union all select 'transactions', count(*) from public.transactions
union all select 'tenant_members', count(*) from public.tenant_members;
```

Then run `supabase/verify/security_checks.sql`. Never restore over production
without a verified snapshot and a maintenance window.

### Restore drill checklist

- [ ] Dump completes without errors and is non-zero.
- [ ] Restore into a fresh project/database.
- [ ] Row counts match the source for the five tables above.
- [ ] `security_checks.sql` returns PASS.
- [ ] Sign in as an owner and open the ledger; payment history is visible.
- [ ] Record and void a test payment in the restored project.
- [ ] Record the restore duration and the person who performed it.

## 2. Migration Order (Expand / Contract)

The tenancy and payment hardening is deliberately split. Do not collapse the
steps.

1. **Back up** (section 1).
2. Apply `supabase/migrations/20261025120000_tenant_membership_rls.sql`.
   - Creates tenants, members and invites; backfills membership from profiles.
   - Replaces the shared-tenant `current_tenant_id()` with a membership lookup.
   - Adds per-operation RLS, minimum column grants and composite tenant FKs.
   - Keeps legacy payment inserts/updates working for the old client.
3. **Deploy the hardened client** (the build that calls `record_payment`,
   `void_payment` and `close_loan`). Verify sign-in, ledger, payment preview and
   one test payment.
4. Apply `supabase/migrations/20261025121000_payment_rpcs.sql`.
   - Creates the RPCs and `nepal_today()`.
   - Backfills transfer direction, principal cashflow flags and unambiguous
     payment links.
   - Revokes direct payment writes, loan lifecycle writes and all anon access.
5. Run `supabase/verify/security_checks.sql` (read-only, safe anywhere).
6. Run `supabase/verify/smoke_test.sql` on **staging only**. It writes test rows
   inside a transaction and rolls back.

Apply via the Supabase SQL editor or `supabase db push` after `supabase link`.
The migration runner wraps each file in a transaction; do **not** add explicit
`BEGIN`/`COMMIT` to migration files. An inner `COMMIT` would end the runner's
transaction and could leave an applied schema unrecorded.

### Post-migration smoke checks (manual)

- Owner: sign in, add a party, add a loan, record a payment, confirm the wallet
  leg and the ledger balance change.
- Owner: void the newest payment; confirm the loan reopens.
- Viewer: sign in; every write control is hidden and a direct PostgREST write is
  denied.
- Non-member: sign in; the app shows "Account not provisioned" and no rows.
- Cross-tenant: two browsers, two organisations; no rows or IDs leak.

## 3. Auth Settings (manual, required)

These are dashboard settings, not migrations:

- **Disable public sign-up.** Authentication > Providers > Email > "Allow new
  users to sign up" off. The client no longer has a sign-up form, but the Auth
  API must also refuse.
- **Enable email confirmation.** Otherwise an invited address can be claimed
  without proving control of the mailbox.
- **Set Site URL and redirect allow-list** to the deployed app URL. Password
  reset uses `redirectTo: Uri.base`.
- **Set a strong password policy** and a reasonable JWT/session lifetime.
- **Do not enable anonymous sign-ins.** The app has no anonymous surface and
  `anon` has no table grants after migration 2.
- Optional: enable CAPTCHA and Auth rate limits. Invite-only reduces exposure but
  does not stop credential stuffing.

## 4. Bootstrap the First Owner

Public sign-up is disabled and the `handle_new_user()` trigger only provisions a
user with a valid invitation. To create the first owner:

1. Pick the organisation UUID. The prototype data uses
   `00000000-0000-0000-0000-000000000001`; keep it if you are migrating the
   existing ledger.
2. As `postgres` in the SQL editor:

```sql
insert into public.tenant_invites (tenant_id, email, role, expires_at)
values (
  '00000000-0000-0000-0000-000000000001',
  'owner@example.com',
  'owner',
  now() + interval '7 days'
)
on conflict do nothing;
```

3. Dashboard > Authentication > Users > Invite user (or create the user with the
   same email). The trigger matches the invite, creates `profiles` and
   `tenant_members`, and marks the invite accepted.
4. Verify:

```sql
select p.id, p.email, p.role, p.tenant_id, tm.role, tm.status
from public.profiles p
left join public.tenant_members tm on tm.user_id = p.id
where p.email = 'owner@example.com';
```

Both roles should be `owner` and the membership `active`. If the profile is
missing, the invite email did not match or had expired. Delete the auth user,
fix the invite, and invite again.

5. Additional users: an owner can call
   `select public.create_tenant_invite('person@example.com', 'manager');` and then
   invite the address from the dashboard. There is no member-admin UI yet.

## 5. Rate Correction (wrong loan rate)

There is no loan edit UI. A wrong rate is a data correction and must be handled
deliberately:

1. Identify the loan and confirm the intended rate with the lender/borrower and
   the source document.
2. Check whether payments already exist:

```sql
select count(*) from public.payments
where loan_id = '<loan-id>' and deleted_at is null;
```

3. If there are no payments, correct the rate directly as `postgres` and write an
   audit row:

```sql
begin;
with old as (
  select id, tenant_id, rate from public.loans where id = '<loan-id>'
), upd as (
  update public.loans set rate = 0.08, updated_at = now()
  where id = (select id from old)
  returning id
)
insert into public.audit_logs
  (tenant_id, table_name, row_id, action, old_data, new_data, actor)
select old.tenant_id, 'loans', old.id, 'rate_correction',
       jsonb_build_object('rate', old.rate),
       jsonb_build_object('rate', 0.08),
       auth.uid()
from old;
commit;
```

4. If payments exist, do not silently edit the rate: the already-posted
   interest-first allocations were computed under the old rate. Void the newest
   payments in reverse order (via `void_payment`), correct the loan, then
   re-enter the payments in date order. Document the correction.
5. Verify `PerDay = Principal * Rate / DayBase` against the statement.

The old note about Machhapuchhre `0.80` being a possible 8% input error remains
a data question. Do not change it without the bank's written confirmation.

## 6. Duplicate Party / Loan Cleanup

The import seed guard aborts if `loans` or `parties` is non-empty. If duplicates
were created before the guard:

1. Identify duplicates by name/phone/id_number in the Parties page.
2. Decide the canonical row. Do not hard-delete.
3. Re-point loans only if the loan belongs to the canonical party. There is no
   loan edit UI, so this is a SQL correction with an audit row, or archive and
   recreate the loan.
4. Archive the duplicate party (`deleted_at = now()`) after it has no live loans.
5. Reconcile the ledger footers against the source sheet before and after.
6. Never hard-delete financial rows. Soft deletes preserve the audit trail.

## 7. Key Rotation

### Publishable / anon key

- Rotate in Dashboard > Project Settings > API.
- Update GitHub Actions secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- Redeploy. The publishable key is not a secret in the same sense as a service
  role key, but rotating it invalidates old bundles.
- The fallback key in `app/lib/main.dart` is a development convenience. A
  production build should always pass `--dart-define` values from secrets.

### Database password and service role

- Rotate the database password in Dashboard > Settings > Database. Update the
  operator's password manager and any `pg_dump` script.
- The service role key bypasses RLS. It must never appear in the Flutter bundle,
  GitHub Pages, logs or a screenshot. It is only for server-side jobs.
- If a service role key leaks, rotate it immediately, review Auth and database
  logs, and assume all tenant data was readable.

### Edge secrets

`RESEND_API_KEY` and SMS provider credentials are not deployed today. If the
alert function is deployed later, store them in Dashboard > Edge Functions >
Secrets and Vault, never in the client.

## 8. Alerts and Scheduled Jobs (not deployed)

The file `supabase/migrations/20261015170000_alert_cron.sql` is entirely
commented out. `supabase/functions/dispatch-alerts/index.ts` exists as source but
has not been deployed, and no `pg_cron` job is scheduled. Do not tell users that
due/overdue email or SMS alerts are running.

To deploy later:

1. Set Resend/SMS secrets in Edge Functions.
2. `supabase functions deploy dispatch-alerts`.
3. Uncomment and review the cron migration; store `project_url` and a
   service-role key in Vault.
4. Test with a staging tenant and a due loan before enabling production.
5. Add monitoring for failed sends and a dead-letter view. The current
   `notification_queue` is the only record.

The in-app bell reads `notification_queue`. With no scheduler, only manually
inserted rows appear.

## 9. Verification Commands

From the repository root:

```powershell
cd app
flutter analyze
$env:TZ='UTC'; flutter test --reporter expanded
$env:TZ='Asia/Kathmandu'; flutter test test/bs_picker_test.dart test/widget/bs_picker_test.dart
flutter build web --release --base-href=/nhisab/ --no-wasm-dry-run
```

Database, on staging:

```sql
-- Read-only catalog and privilege checks. Expect PASS.
\i supabase/verify/security_checks.sql

-- Transactional RPC/RLS exercise. Writes test rows, then rolls back.
\i supabase/verify/smoke_test.sql
```

The local PGlite/libpg-query harnesses used during development are not committed
because they are not a substitute for Supabase. Keep them out of CI until a
Postgres service container is available.

## 10. Incident Response

1. **Suspected cross-tenant access or key leak:** rotate the publishable and
   service role keys, revoke Auth sessions, preserve logs, and take a dump before
   changing data.
2. **Wrong payment posted:** void the newest payment through the app. If it is
   not the newest, void newer payments first, then correct and re-enter in date
   order. Do not update `payments` directly.
3. **Wrong loan closed/written off:** `void_payment` reopens a closed loan only
   when a payment is voided. A write-off close with no payment requires a SQL
   correction by the operator plus an audit row and documented approval.
4. **Database unavailable:** stop writes, do not let users queue payments offline
   (the client already blocks them), and follow the restore procedure.
5. **Suspicious login:** disable the Auth user, review `audit_logs` and Auth logs,
   then re-invite after resolving the account.

## 11. Escalation

- Supabase Dashboard > Support for database/Auth incidents.
- Resend dashboard for email delivery, only after the Edge function is deployed.
- SMS provider contract is still pending; there is no production SMS path.
- For legal/tax questions (interest cap, TDS, VAT, data residency), escalate to a
  Nepali chartered accountant and counsel. The app is not a compliance product.
