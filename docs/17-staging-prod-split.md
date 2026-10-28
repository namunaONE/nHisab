# 17 - Staging / Production Split

## Goal
Keep a staging Supabase project that mirrors production schema (no production
data) so migrations and client builds are verified before touching prod.

## Create staging project
1. Dashboard -> New project in org `Namuna One`, region `ap-south-1`, name `nhisab-staging`.
   Or via MCP: `create_project` (confirm cost first).
2. Note the new ref + URL + anon key. Store as GitHub secrets
   `STAGING_SUPABASE_URL`, `STAGING_SUPABASE_ANON_KEY`.
3. Apply all migrations in `supabase/migrations/` order to staging
   (via SQL editor or `supabase db push`).
4. Run `supabase/verify/security_checks.sql` (expect PASS) and
   `supabase/verify/smoke_test.sql` (transactional, rolls back).
5. Bootstrap one owner (see `supabase/verify/staging_bootstrap.sql`).
6. Deploy the app build pointed at staging (manual or a separate Pages env).

## Promote to production
1. Back up prod (`pg_dump` -> encrypted off-platform).
2. Apply only the *new* migrations to prod (never re-apply old ones).
3. Deploy the matching client build.
4. Run `security_checks.sql` on prod.
5. Smoke test on staging only (never on prod data).

## Rules
- Never run `smoke_test.sql` on production (it writes, even though it rolls back).
- Never copy production data into staging.
- One migration file = one `apply_migration` call; keep files idempotent (`if not exists`).
- Record every apply in `docs/12-gaps-fix-log.md`.