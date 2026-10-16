-- 20261015160000 profiles_table (applied remote 2026-10-15)
-- Profiles for app users (separate from parties). Per docs/11-registration.
-- Conventions: id FK auth.users.id on delete cascade, tenant_id default shared,
-- RLS authenticated only (read/update own row), trigger populates from metadata.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  email text,
  phone text,
  role text not null default 'owner' check (role in ('owner','viewer')),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists idx_profiles_tenant on public.profiles(tenant_id);
create index if not exists idx_profiles_role on public.profiles(role);

alter table public.profiles enable row level security;

drop policy if exists p_profiles_own on public.profiles;
create policy p_profiles_own on public.profiles
  for all to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Function: populate profiles row on new auth user signup (created BEFORE trigger).
create or replace function public.handle_new_user()
returns trigger language plpgsql as $$
begin
  insert into public.profiles (id, display_name, email, phone, role, tenant_id)
  values (
    new.id,
    coalesce((new.raw_user_meta_data ->> 'display_name'), ''),
    new.email,
    new.raw_user_meta_data ->> 'phone',
    'owner',
    '00000000-0000-0000-0000-000000000001'
  );
  return new;
end $$;

-- Trigger: populate profiles row on new auth user signup.
drop trigger if exists trg_handle_new_user on auth.users;
create trigger trg_handle_new_user
  after insert on auth.users
  for each row execute function public.handle_new_user();
