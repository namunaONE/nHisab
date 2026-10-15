-- RLS verification for nHisab (run after every migration).
-- Verified 2026-10-15: 10/10 tables rowsecurity=true, 10 authenticated ALL
-- policies, security lints 0. Unused-index INFOs expected on fresh tables.

-- 1. All public tables must have RLS on (expect 10 rows, all true).
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
order by tablename;

-- 2. No table may expose an open policy (expect 0 rows).
select tablename, policyname
from pg_policies
where schemaname = 'public'
  and (qual = 'true' or with_check = 'true');

-- 3. Every table needs at least one authenticated policy (expect 10 rows).
select tablename, policyname, roles, cmd
from pg_policies
where schemaname = 'public'
order by tablename;

-- 4. TWO-USER ISOLATION (manual, needs two auth users A and B):
-- a. As service_role: insert probe rows with distinct tenant_ids:
--    insert into public.parties (tenant_id, name) values
--      ('00000000-0000-0000-0000-0000000000a1', 'probe-A'),
--      ('00000000-0000-0000-0000-0000000000b2', 'probe-B');
-- b. Set user A app_metadata.tenant_id = ...a1, sign in as A:
--    select * from public.parties;  -- must show probe-A only
-- c. Sign in as B (tenant ...b2): must show probe-B only.
-- d. Anon (no JWT): must show 0 rows on every table.
-- e. Delete probe rows as service_role afterwards.
