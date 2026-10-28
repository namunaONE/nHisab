-- staging_bootstrap.sql
--
-- Run AFTER applying both hardening migrations to a staging project and AFTER
-- inviting at least one user from Dashboard > Authentication > Users.
--
-- Replace the placeholders below, then run as postgres (SQL editor). This
-- creates the tenant + membership + profile projection for the invited user so
-- smoke_test.sql and manual cross-tenant checks have an owner to impersonate.
--
-- Idempotent: safe to re-run; uses ON CONFLICT where possible.

-- 1. Parameters (edit these)
--    :owner_user_id  = auth.users.id of the invited owner
--    :owner_email    = their email
--    :tenant_name    = organisation name for staging

-- 2. Tenant
insert into public.tenants (name)
values (:'tenant_name'::text)
on conflict do nothing;

-- 3. Membership (active owner). If the tenant already exists, look it up.
with t as (
  select id from public.tenants where name = :'tenant_name'::text order by created_at desc limit 1
)
insert into public.tenant_members (tenant_id, user_id, role, status)
select t.id, :'owner_user_id'::uuid, 'owner', 'active'
from t
on conflict (tenant_id, user_id) do update set role = 'owner', status = 'active';

-- 4. Profile projection (kept in sync by trigger on role changes; seed here).
insert into public.profiles (id, display_name, email, role, tenant_id)
select :'owner_user_id'::uuid,
       coalesce(nullif(:'owner_email'::text, ''), 'Staging Owner'),
       :'owner_email'::text,
       'owner',
       (select id from public.tenants where name = :'tenant_name'::text order by created_at desc limit 1)
on conflict (id) do update
  set email = excluded.email,
      role = 'owner',
      tenant_id = excluded.tenant_id;

-- 5. Verify
select 'owner_memberships' as check, count(*) as n
from public.tenant_members
where user_id = :'owner_user_id'::uuid and role = 'owner' and status = 'active';

select 'profile' as check, id, role, tenant_id
from public.profiles
where id = :'owner_user_id'::uuid;