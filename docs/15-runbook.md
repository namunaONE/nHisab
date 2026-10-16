# 15 - Runbook — Backup, Restore, Rate Fix, Duplicate Cleanup, Key Rotation

Date: 2026-10-15. Project `nhisab` `qcbxurqxmnkzgsfpaesz` ap-south-1 PG 17.
Supabase free tier: 500MB DB, PITR (point-in-time recovery) available.

## 1. Backup / Restore

### Automated (Supabase platform)
- PITR enabled on free tier — restore to any time within retention window via
  Supabase Dashboard > Project Settings > Restore.
- Daily base backup + continuous WAL archiving.

### Manual filtered dump (per-tenant portability)
```bash
# Export public schema + data for the shared tenant
pg_dump -h db.qcbxurqxmnkzgsfpaesz.supabase.co -U postgres \
  -d postgres -n public > nhisab_dump_$(date +%F).sql
# Requires DB password from Supabase Dashboard > Settings > Database.
```

### Restore
```bash
psql -h db.<project>.supabase.co -U postgres -d postgres < nhisab_dump.sql
```
- Restore into a **new** project first, verify row counts (parties/loans = 21),
  then promote. Do not restore over production without a PITR snapshot.

## 2. Rate Fix (wrong annual rate entered)

If a loan rate was entered wrong (e.g. `0.80` = 80% instead of `0.08` = 8%):
1. Identify the loan in Ledger (PerDay anomalously high).
2. Open LoanForm (edit) — rate field accepts decimal %; correct to intended
   value (e.g. `8` for 8% → stored `0.08`).
3. Save. Ledger recalculates instantly for current Today.
4. Verify against sheet: PerDay = `Principal * Rate / 360`.

Note: `docs/04` flags Machhapuchhre `0.80` as likely 8% input error — verify
with bank before changing.

## 3. Duplicate Cleanup (re-seed guard triggered)

The ImportPage seed guard aborts if `loans` or `parties` is non-empty. If
duplicates were accidentally created:
1. Identify duplicate parties (same name, different id) in Parties page.
2. Archive (soft-delete) the duplicate party: `deleted_at = now()`.
3. Repoint its loans to the canonical party via LoanForm edit (party dropdown).
4. Archive duplicate loans: `deleted_at = now()`.
5. Verify Ledger footers match sheet:
   - Receivable principal `9960000`, interest `668653.33`
   - Payable principal `85713900`

Never hard-delete; soft-delete preserves audit trail.

## 4. Key Rotation

### Supabase anon / publishable key
- Rotate in Supabase Dashboard > Project Settings > API.
- Update `app/lib/main.dart` defaults OR (preferred) set as GitHub Actions
  secrets `SUPABASE_URL` + `SUPABASE_ANON_KEY` and redeploy.
- Old key remains valid for a grace period; rotate during low-traffic window.

### Service role / Edge secrets (Vault)
- Rotate in Supabase Dashboard > Project Settings > Edge Functions > Secrets.
- Affected: `RESEND_API_KEY`, SMS provider keys (Sparrow/Aakash pending).
- Edge `dispatch-alerts` reads from Vault — no client exposure.

### Never commit real keys
- `app/.env.example` has placeholders only.
- `main.dart` default `sb_publishable_...` is a publishable key (safe by design,
  RLS still blocks anon reads). Do not add `service_role` to client code.

## 5. Vault pg_net (Edge dispatch-alerts)
- Scheduled via `pg_cron` at 08:00 NPT daily.
- Calls Edge `dispatch-alerts` with Vault project_url + publishable_key.
- Edge queries due/overdue loans, dedupes by date+loan+channel, sends Resend +
  SMS in parallel, inserts `notification_queue`, updates `sent_at`.
- Health: `cron_health` table (last_run/status/retry), second cron health-check
  every 5 min, cleanup 30d.

## 6. Emergency Contacts / Escalation
- Supabase Dashboard > Support for DB incidents.
- Resend dashboard for email delivery failures.
- SMS provider (Sparrow/Aakash) contract pending — email in-app alerts work
  without SMS in MVP.
