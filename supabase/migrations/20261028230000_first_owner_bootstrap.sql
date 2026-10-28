-- First-owner self-service bootstrap (replaces the manual staging_bootstrap /
-- dashboard step for the very first owner).
--
-- Safe by design: both functions are SECURITY DEFINER but refuse to act once
-- any tenant membership exists. Serialization via advisory lock prevents two
-- concurrent first-visitors from creating two tenants.
--
-- The created user: confirmed email + bcrypt password, provider metadata set,
-- identities row inserted best-effort (GoTrue reconciles as needed). The
-- regular handle_new_user trigger is a no-op for this path (no invite), so the
-- RPC creates tenants / tenant_members / profiles itself and audits it.

create extension if not exists pgcrypto;

create or replace function public.system_needs_bootstrap()
returns boolean
language sql
security definer
set search_path = ''
as $$
  select not exists (select 1 from public.tenant_members);
$$;

create or replace function public.bootstrap_first_owner(
  p_email text,
  p_password text,
  p_tenant_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(btrim(p_email));
  v_user_id uuid;
  v_tenant_id uuid;
  v_tenant_name text;
  v_crypted text;
begin
  -- Serialize concurrent first-bootstraps.
  perform pg_advisory_xact_lock(hashtext('nhisab_first_owner'));

  -- Guard: only while the system has no member at all.
  if exists (select 1 from public.tenant_members) then
    raise exception 'An organisation already exists; use sign-in instead'
      using errcode = '42501';
  end if;

  if v_email is null or v_email !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' then
    raise exception 'Valid email is required' using errcode = '22023';
  end if;

  if p_password is null or length(p_password) < 8 then
    raise exception 'Password must be at least 8 characters' using errcode = '22023';
  end if;

  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'A user with this email already exists; sign in instead'
      using errcode = '23505';
  end if;

  v_tenant_name := coalesce(nullif(btrim(coalesce(p_tenant_name, '')), ''),
                            'My Organisation');
  v_user_id := gen_random_uuid();
  v_crypted := extensions.crypt(p_password, extensions.gen_salt('bf'));

  -- 1. Create the organisation.
  insert into public.tenants (name) values (v_tenant_name)
  returning id into v_tenant_id;

  -- 2. Create the auth user (confirmed, bcrypt password, email provider).
  insert into auth.users (
    id, aud, role, email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) values (
    v_user_id, 'authenticated', 'authenticated', v_email,
    v_crypted,
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', split_part(v_email, '@', 1)),
    now(), now()
  );

  -- 3. Best-effort identity row (GoTrue-compatible).
  begin
    insert into auth.identities (
      user_id, identity_data, provider_id, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', v_email,
                         'email_verified', true)::jsonb,
      'email', 'email',
      now(), now(), now()
    );
  exception when others then
    -- Schema drift tolerated; password sign-in works without it.
    null;
  end;

  -- 4. Owner profile projection (trigger is invite-only; seed here).
  insert into public.profiles (id, display_name, email, role, tenant_id)
  values (
    v_user_id,
    split_part(v_email, '@', 1),
    v_email,
    'owner',
    v_tenant_id
  ) on conflict (id) do nothing;

  -- 5. Owner membership.
  insert into public.tenant_members (tenant_id, user_id, role, status)
  values (v_tenant_id, v_user_id, 'owner', 'active');

  -- 6. Audit trail.
  insert into public.audit_logs (tenant_id, table_name, row_id, action, new_data, actor)
  values (
    v_tenant_id, 'tenant_members', v_user_id, 'bootstrap',
    jsonb_build_object('email', v_email, 'tenant_name', v_tenant_name),
    null
  );

  return jsonb_build_object(
    'user_id', v_user_id,
    'tenant_id', v_tenant_id,
    'tenant_name', v_tenant_name,
    'email', v_email
  );
end;
$$;

revoke all on function public.system_needs_bootstrap() from public;
grant execute on function public.system_needs_bootstrap() to anon, authenticated;

revoke all on function public.bootstrap_first_owner(text, text, text) from public;
grant execute on function public.bootstrap_first_owner(text, text, text) to anon;

notify pgrst, 'reload schema';
