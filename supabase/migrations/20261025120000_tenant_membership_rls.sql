-- 20261025120000 tenant membership + per-operation RLS
--
-- Expands the single-tenant prototype into an invite-only, tenant-scoped
-- ledger. Safe to apply before the hardened client: existing rows are
-- backfilled into the old shared tenant and owners retain access.
--
-- Apply order for production:
--   1. this migration (tenancy + RLS, legacy payment writes still allowed)
--   2. deploy the hardened client (uses record_payment when available)
--   3. 20261025121000 payment_rpcs (revokes direct payment writes)
--
-- The old `current_tenant_id()` fell back to the shared tenant UUID whenever
-- the JWT had no tenant claim. That made every authenticated user a member of
-- the default organisation. It now derives membership from
-- public.tenant_members and returns NULL when the user has no active seat.

-- The migration runner wraps each file in a transaction. Do not add explicit
-- BEGIN/COMMIT here: an inner COMMIT would end the runner's transaction and
-- could leave an applied schema unrecorded in supabase_migrations.

-- ---------------------------------------------------------------------------
-- 1. Tenants, members, invites
-- ---------------------------------------------------------------------------

create table if not exists public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'My organisation',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Preserve the prototype's existing tenant id so no data is orphaned.
insert into public.tenants (id, name)
values ('00000000-0000-0000-0000-000000000001', 'Default organisation')
on conflict (id) do nothing;

create table if not exists public.tenant_members (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'viewer'
    check (role in ('owner', 'manager', 'viewer')),
  status text not null default 'active'
    check (status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, user_id)
);

-- The current app has no tenant switcher. Keep one active organisation per
-- user until a switch UI exists; this also keeps profiles.tenant_id coherent.
create unique index if not exists uq_tenant_members_one_active
  on public.tenant_members (user_id)
  where status = 'active';

create index if not exists idx_tenant_members_user
  on public.tenant_members (user_id, status);

create table if not exists public.tenant_invites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  email text not null,
  role text not null default 'viewer'
    check (role in ('owner', 'manager', 'viewer')),
  token uuid not null default gen_random_uuid() unique,
  invited_by uuid references auth.users(id) on delete set null,
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  accepted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create unique index if not exists uq_tenant_invites_pending_email
  on public.tenant_invites (tenant_id, lower(email))
  where accepted_at is null;

create index if not exists idx_tenant_invites_tenant
  on public.tenant_invites (tenant_id, created_at desc);

-- Any tenant_id already present in business tables must have a parent row
-- before tenant foreign keys are added.
insert into public.tenants (id, name)
select distinct x.tenant_id, 'Imported organisation'
from (
  select tenant_id from public.parties
  union select tenant_id from public.loans
  union select tenant_id from public.payments
  union select tenant_id from public.emi_schedules
  union select tenant_id from public.notification_queue
  union select tenant_id from public.audit_logs
  union select tenant_id from public.accounts
  union select tenant_id from public.categories
  union select tenant_id from public.transactions
  union select tenant_id from public.budgets
  union select tenant_id from public.profiles
) x
where x.tenant_id is not null
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Roles and helpers (security definer avoids recursive RLS)
-- ---------------------------------------------------------------------------

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('owner', 'manager', 'viewer'));

create or replace function public.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select tm.tenant_id
  from public.tenant_members tm
  where tm.user_id = auth.uid()
    and tm.status = 'active'
  order by tm.created_at
  limit 1;
$$;

create or replace function public.current_tenant_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select tm.role
  from public.tenant_members tm
  where tm.user_id = auth.uid()
    and tm.status = 'active'
    and tm.tenant_id = public.current_tenant_id()
  limit 1;
$$;

create or replace function public.is_tenant_writer(p_tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.tenant_members tm
    where tm.user_id = auth.uid()
      and tm.tenant_id = p_tenant
      and tm.status = 'active'
      and tm.role in ('owner', 'manager')
  );
$$;

revoke all on function public.current_tenant_id() from public, anon;
revoke all on function public.current_tenant_role() from public, anon;
revoke all on function public.is_tenant_writer(uuid) from public, anon;
grant execute on function public.current_tenant_id() to authenticated;
grant execute on function public.current_tenant_role() to authenticated;
grant execute on function public.is_tenant_writer(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Backfill memberships from the old profiles table
-- ---------------------------------------------------------------------------

insert into public.tenant_members (tenant_id, user_id, role, status)
select p.tenant_id, p.id, p.role, 'active'
from public.profiles p
join public.tenants t on t.id = p.tenant_id
on conflict (tenant_id, user_id) do update
  set role = excluded.role,
      status = 'active',
      updated_at = now();

-- ---------------------------------------------------------------------------
-- 4. Invite-only provisioning
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite public.tenant_invites%rowtype;
begin
  select *
  into v_invite
  from public.tenant_invites
  where lower(email) = lower(coalesce(new.email, ''))
    and accepted_at is null
    and expires_at > now()
  order by created_at desc
  limit 1;

  -- No valid invite: create no profile and no membership. The app fails
  -- closed and tells the user to ask for an invitation.
  if v_invite.id is null then
    return new;
  end if;

  insert into public.profiles (id, display_name, email, phone, role, tenant_id)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      split_part(coalesce(new.email, ''), '@', 1)
    ),
    new.email,
    new.raw_user_meta_data ->> 'phone',
    v_invite.role,
    v_invite.tenant_id
  )
  on conflict (id) do nothing;

  insert into public.tenant_members (tenant_id, user_id, role, status)
  values (v_invite.tenant_id, new.id, v_invite.role, 'active')
  on conflict (tenant_id, user_id) do update
    set role = excluded.role,
        status = 'active',
        updated_at = now();

  update public.tenant_invites
  set accepted_at = now(),
      accepted_by = new.id
  where id = v_invite.id;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon;

-- Owner-only invite creation. Callable from a future admin UI:
--   select public.create_tenant_invite('person@example.com', 'viewer');
create or replace function public.create_tenant_invite(
  p_email text,
  p_role text default 'viewer'
)
returns public.tenant_invites
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_invite public.tenant_invites%rowtype;
begin
  if v_tenant is null then
    raise exception 'No active tenant membership' using errcode = '42501';
  end if;
  if public.current_tenant_role() <> 'owner' then
    raise exception 'Only an owner can invite users' using errcode = '42501';
  end if;
  if p_role not in ('owner', 'manager', 'viewer') then
    raise exception 'Invalid invitation role' using errcode = '22023';
  end if;
  if p_email is null or position('@' in p_email) < 2 then
    raise exception 'A valid email is required' using errcode = '22023';
  end if;

  insert into public.tenant_invites (tenant_id, email, role, invited_by)
  values (v_tenant, lower(trim(p_email)), p_role, auth.uid())
  returning * into v_invite;

  insert into public.audit_logs
    (tenant_id, table_name, row_id, action, new_data, actor)
  values
    (v_tenant, 'tenant_invites', v_invite.id, 'insert',
     to_jsonb(v_invite) - 'token', auth.uid());

  return v_invite;
end;
$$;

revoke all on function public.create_tenant_invite(text, text) from public, anon;
grant execute on function public.create_tenant_invite(text, text) to authenticated;

-- Do not let an owner remove the last active owner.
create or replace function public.protect_last_tenant_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Only guard rows that are currently an active owner and are about to stop
  -- being one. The previous condition also fired when editing a viewer, which
  -- made any membership edit fail in a tenant that had exactly one owner.
  if old.role = 'owner' and old.status = 'active'
     and (
       tg_op = 'DELETE'
       or new.role <> 'owner'
       or new.status <> 'active'
     ) then
    if not exists (
      select 1
      from public.tenant_members tm
      where tm.tenant_id = old.tenant_id
        and tm.user_id <> old.user_id
        and tm.role = 'owner'
        and tm.status = 'active'
    ) then
      raise exception 'A tenant must retain at least one active owner'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.protect_last_tenant_owner() from public, anon;

drop trigger if exists trg_tenant_members_protect_owner on public.tenant_members;
create trigger trg_tenant_members_protect_owner
  before update or delete on public.tenant_members
  for each row execute function public.protect_last_tenant_owner();

drop trigger if exists trg_tenant_members_updated on public.tenant_members;
create trigger trg_tenant_members_updated
  before update on public.tenant_members
  for each row execute function public.handle_updated_at();

-- The client uses profiles.role for UI gating while the server authorises from
-- tenant_members. Keep the projection in sync so a demoted manager stops
-- seeing write controls immediately instead of after the next failed request.
create or replace function public.sync_profile_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set role = new.role,
      updated_at = now()
  where id = new.user_id
    and tenant_id = new.tenant_id;
  return new;
end;
$$;

revoke all on function public.sync_profile_role() from public, anon;

drop trigger if exists trg_tenant_members_sync_profile on public.tenant_members;
create trigger trg_tenant_members_sync_profile
  after insert or update of role on public.tenant_members
  for each row execute function public.sync_profile_role();

drop trigger if exists trg_tenants_updated on public.tenants;
create trigger trg_tenants_updated
  before update on public.tenants
  for each row execute function public.handle_updated_at();

-- ---------------------------------------------------------------------------
-- 5. Tenant defaults: no hard-coded shared tenant fallback
-- ---------------------------------------------------------------------------

alter table public.parties alter column tenant_id set default public.current_tenant_id();
alter table public.loans alter column tenant_id set default public.current_tenant_id();
alter table public.payments alter column tenant_id set default public.current_tenant_id();
alter table public.emi_schedules alter column tenant_id set default public.current_tenant_id();
alter table public.notification_queue alter column tenant_id set default public.current_tenant_id();
alter table public.audit_logs alter column tenant_id set default public.current_tenant_id();
alter table public.accounts alter column tenant_id set default public.current_tenant_id();
alter table public.categories alter column tenant_id set default public.current_tenant_id();
alter table public.transactions alter column tenant_id set default public.current_tenant_id();
alter table public.budgets alter column tenant_id set default public.current_tenant_id();
alter table public.profiles alter column tenant_id set default public.current_tenant_id();

-- ---------------------------------------------------------------------------
-- 5b. Forward-compatible columns (expand phase)
-- ---------------------------------------------------------------------------
-- The hardened client is deployed between this migration and
-- 20261025121000. It writes transfer_direction and excluded_from_cashflow on
-- ordinary transactions and reads the loan lifecycle/write-off fields. If
-- these columns only existed in migration 2, the expand window would break
-- transfers, the legacy payment fallback and the party statement. Migration 2
-- repeats every ADD COLUMN with IF NOT EXISTS, so the order stays safe.

alter table public.loans
  add column if not exists accrual_end_date date,
  add column if not exists closed_at timestamptz,
  add column if not exists closed_by uuid references auth.users(id) on delete set null,
  add column if not exists write_off_amount numeric(15,2) not null default 0,
  add column if not exists write_off_reason text;

alter table public.payments
  add column if not exists client_id uuid,
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists voided_at timestamptz,
  add column if not exists voided_by uuid references auth.users(id) on delete set null,
  add column if not exists void_reason text;

alter table public.transactions
  add column if not exists payment_id uuid,
  add column if not exists transfer_direction text,
  add column if not exists excluded_from_cashflow boolean not null default false;

-- ---------------------------------------------------------------------------
-- 6. Foreign keys: prevent cross-tenant references and cascade data loss
-- ---------------------------------------------------------------------------

alter table public.parties drop constraint if exists uq_parties_id_tenant;
alter table public.parties add constraint uq_parties_id_tenant unique (id, tenant_id);
alter table public.loans drop constraint if exists uq_loans_id_tenant;
alter table public.loans add constraint uq_loans_id_tenant unique (id, tenant_id);
alter table public.accounts drop constraint if exists uq_accounts_id_tenant;
alter table public.accounts add constraint uq_accounts_id_tenant unique (id, tenant_id);
alter table public.categories drop constraint if exists uq_categories_id_tenant;
alter table public.categories add constraint uq_categories_id_tenant unique (id, tenant_id);
alter table public.payments drop constraint if exists uq_payments_id_tenant;
alter table public.payments add constraint uq_payments_id_tenant unique (id, tenant_id);

alter table public.profiles drop constraint if exists profiles_tenant_fk;
alter table public.profiles
  add constraint profiles_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;

alter table public.parties drop constraint if exists parties_tenant_fk;
alter table public.parties add constraint parties_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;
alter table public.loans drop constraint if exists loans_tenant_fk;
alter table public.loans add constraint loans_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;
alter table public.payments drop constraint if exists payments_tenant_fk;
alter table public.payments add constraint payments_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;
alter table public.emi_schedules drop constraint if exists emi_tenant_fk;
alter table public.emi_schedules add constraint emi_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;
alter table public.notification_queue drop constraint if exists notifications_tenant_fk;
alter table public.notification_queue add constraint notifications_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;
alter table public.audit_logs drop constraint if exists audit_tenant_fk;
alter table public.audit_logs add constraint audit_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;
alter table public.accounts drop constraint if exists accounts_tenant_fk;
alter table public.accounts add constraint accounts_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;
alter table public.categories drop constraint if exists categories_tenant_fk;
alter table public.categories add constraint categories_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;
alter table public.transactions drop constraint if exists transactions_tenant_fk;
alter table public.transactions add constraint transactions_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;
alter table public.budgets drop constraint if exists budgets_tenant_fk;
alter table public.budgets add constraint budgets_tenant_fk
  foreign key (tenant_id) references public.tenants(id) on delete restrict;

-- Loans cannot point at a party in another tenant.
alter table public.loans drop constraint if exists loans_party_id_fkey;
alter table public.loans add constraint loans_party_tenant_fk
  foreign key (party_id, tenant_id)
  references public.parties(id, tenant_id)
  on delete restrict;

-- Payments/EMI/notifications must not disappear when a loan is hard-deleted.
alter table public.payments drop constraint if exists payments_loan_id_fkey;
alter table public.payments add constraint payments_loan_tenant_fk
  foreign key (loan_id, tenant_id)
  references public.loans(id, tenant_id)
  on delete restrict;

alter table public.emi_schedules drop constraint if exists emi_schedules_loan_id_fkey;
alter table public.emi_schedules add constraint emi_loan_tenant_fk
  foreign key (loan_id, tenant_id)
  references public.loans(id, tenant_id)
  on delete restrict;

alter table public.notification_queue drop constraint if exists notification_queue_loan_id_fkey;
alter table public.notification_queue add constraint notification_loan_tenant_fk
  foreign key (loan_id, tenant_id)
  references public.loans(id, tenant_id)
  on delete restrict;

alter table public.transactions drop constraint if exists transactions_account_id_fkey;
alter table public.transactions add constraint transactions_account_tenant_fk
  foreign key (account_id, tenant_id)
  references public.accounts(id, tenant_id)
  on delete restrict;

alter table public.transactions drop constraint if exists transactions_category_id_fkey;
alter table public.transactions add constraint transactions_category_tenant_fk
  foreign key (category_id, tenant_id)
  references public.categories(id, tenant_id)
  on delete restrict;

alter table public.transactions drop constraint if exists transactions_loan_id_fkey;
alter table public.transactions add constraint transactions_loan_tenant_fk
  foreign key (loan_id, tenant_id)
  references public.loans(id, tenant_id)
  on delete restrict;

alter table public.budgets drop constraint if exists budgets_category_id_fkey;
alter table public.budgets add constraint budgets_category_tenant_fk
  foreign key (category_id, tenant_id)
  references public.categories(id, tenant_id)
  on delete restrict;

-- ---------------------------------------------------------------------------
-- 7. RLS: replace `for all` policies with explicit per-operation policies
-- ---------------------------------------------------------------------------

-- Policies are inert unless RLS is enabled. The three new tables were created
-- above without it on the first draft; enabling here is idempotent.
alter table public.tenants enable row level security;
alter table public.tenant_members enable row level security;
alter table public.tenant_invites enable row level security;

drop policy if exists tenant_all on public.parties;
drop policy if exists tenant_all on public.loans;
drop policy if exists tenant_all on public.payments;
drop policy if exists tenant_all on public.emi_schedules;
drop policy if exists tenant_all on public.notification_queue;
drop policy if exists tenant_all on public.audit_logs;
drop policy if exists p_accounts_all on public.accounts;
drop policy if exists p_categories_all on public.categories;
drop policy if exists p_txns_all on public.transactions;
drop policy if exists p_budgets_all on public.budgets;
drop policy if exists p_profiles_own on public.profiles;

-- Bootstrap policies created by earlier reruns.
drop policy if exists p_parties_select on public.parties;
drop policy if exists p_parties_insert on public.parties;
drop policy if exists p_parties_update on public.parties;
drop policy if exists p_loans_select on public.loans;
drop policy if exists p_loans_insert on public.loans;
drop policy if exists p_loans_update on public.loans;
drop policy if exists p_payments_select on public.payments;
drop policy if exists p_payments_insert on public.payments;
drop policy if exists p_payments_update on public.payments;
drop policy if exists p_emi_select on public.emi_schedules;
drop policy if exists p_emi_insert on public.emi_schedules;
drop policy if exists p_emi_update on public.emi_schedules;
drop policy if exists p_notifications_select on public.notification_queue;
drop policy if exists p_notifications_insert on public.notification_queue;
drop policy if exists p_notifications_update on public.notification_queue;
drop policy if exists p_audit_select on public.audit_logs;
drop policy if exists p_audit_insert on public.audit_logs;
drop policy if exists p_accounts_select on public.accounts;
drop policy if exists p_accounts_insert on public.accounts;
drop policy if exists p_accounts_update on public.accounts;
drop policy if exists p_categories_select on public.categories;
drop policy if exists p_categories_insert on public.categories;
drop policy if exists p_categories_update on public.categories;
drop policy if exists p_txns_select on public.transactions;
drop policy if exists p_txns_insert on public.transactions;
drop policy if exists p_txns_update on public.transactions;
drop policy if exists p_budgets_select on public.budgets;
drop policy if exists p_budgets_insert on public.budgets;
drop policy if exists p_budgets_update on public.budgets;
drop policy if exists p_profiles_select_own on public.profiles;
drop policy if exists p_profiles_update_own on public.profiles;
drop policy if exists p_tenants_select on public.tenants;
drop policy if exists p_tenants_update on public.tenants;
drop policy if exists p_tenant_members_select on public.tenant_members;
drop policy if exists p_tenant_members_insert on public.tenant_members;
drop policy if exists p_tenant_members_update on public.tenant_members;
drop policy if exists p_tenant_invites_select on public.tenant_invites;
drop policy if exists p_tenant_invites_insert on public.tenant_invites;
drop policy if exists p_tenant_invites_update on public.tenant_invites;
drop policy if exists p_tenant_invites_delete on public.tenant_invites;

-- Read: every active member of the tenant.
create policy p_parties_select on public.parties for select to authenticated
  using (tenant_id = public.current_tenant_id());
create policy p_loans_select on public.loans for select to authenticated
  using (tenant_id = public.current_tenant_id());
create policy p_payments_select on public.payments for select to authenticated
  using (tenant_id = public.current_tenant_id());
create policy p_emi_select on public.emi_schedules for select to authenticated
  using (tenant_id = public.current_tenant_id());
create policy p_notifications_select on public.notification_queue for select to authenticated
  using (tenant_id = public.current_tenant_id());
create policy p_audit_select on public.audit_logs for select to authenticated
  using (tenant_id = public.current_tenant_id());
create policy p_accounts_select on public.accounts for select to authenticated
  using (tenant_id = public.current_tenant_id());
create policy p_categories_select on public.categories for select to authenticated
  using (tenant_id = public.current_tenant_id());
create policy p_txns_select on public.transactions for select to authenticated
  using (tenant_id = public.current_tenant_id());
create policy p_budgets_select on public.budgets for select to authenticated
  using (tenant_id = public.current_tenant_id());

-- Write: owners and managers only. No DELETE policy anywhere: money rows are
-- archived with deleted_at, never hard-deleted from the client.
create policy p_parties_insert on public.parties for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );
create policy p_parties_update on public.parties for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );

create policy p_loans_insert on public.loans for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );
create policy p_loans_update on public.loans for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );

-- Legacy payment writes stay until 20261025121000 creates the RPCs and
-- revokes these two policies + table grants.
create policy p_payments_insert on public.payments for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );
create policy p_payments_update on public.payments for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );

create policy p_emi_insert on public.emi_schedules for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );
create policy p_emi_update on public.emi_schedules for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );

create policy p_notifications_insert on public.notification_queue for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );
create policy p_notifications_update on public.notification_queue for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );

create policy p_accounts_insert on public.accounts for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );
create policy p_accounts_update on public.accounts for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );

create policy p_categories_insert on public.categories for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );
create policy p_categories_update on public.categories for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );

create policy p_txns_insert on public.transactions for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );
create policy p_txns_update on public.transactions for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );

create policy p_budgets_insert on public.budgets for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );
create policy p_budgets_update on public.budgets for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.is_tenant_writer(tenant_id)
  );

-- Audit is append-only from the client. The actor must be the caller.
create policy p_audit_insert on public.audit_logs for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and actor = auth.uid()
  );

-- Profiles: own row only. Column grants below prevent role/tenant escalation.
create policy p_profiles_select_own on public.profiles for select to authenticated
  using (id = auth.uid());
create policy p_profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Tenancy administration.
create policy p_tenants_select on public.tenants for select to authenticated
  using (id = public.current_tenant_id());
create policy p_tenants_update on public.tenants for update to authenticated
  using (id = public.current_tenant_id() and public.current_tenant_role() = 'owner')
  with check (id = public.current_tenant_id() and public.current_tenant_role() = 'owner');

create policy p_tenant_members_select on public.tenant_members for select to authenticated
  using (tenant_id = public.current_tenant_id());
create policy p_tenant_members_insert on public.tenant_members for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.current_tenant_role() = 'owner'
  );
create policy p_tenant_members_update on public.tenant_members for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.current_tenant_role() = 'owner'
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.current_tenant_role() = 'owner'
  );

create policy p_tenant_invites_select on public.tenant_invites for select to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.current_tenant_role() = 'owner'
  );
create policy p_tenant_invites_insert on public.tenant_invites for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.current_tenant_role() = 'owner'
  );
create policy p_tenant_invites_update on public.tenant_invites for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.current_tenant_role() = 'owner'
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.current_tenant_role() = 'owner'
  );
create policy p_tenant_invites_delete on public.tenant_invites for delete to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.current_tenant_role() = 'owner'
  );

-- ---------------------------------------------------------------------------
-- 8. Table and column grants
-- ---------------------------------------------------------------------------

-- REVOKE ALL first: the platform's default privileges include REFERENCES,
-- TRIGGER and TRUNCATE, which are not part of the app's model.
revoke all on public.tenants, public.tenant_members, public.tenant_invites
  from anon, authenticated;

grant select on public.tenants to authenticated;
grant update (name) on public.tenants to authenticated;

grant select on public.tenant_members to authenticated;
grant insert (tenant_id, user_id, role, status) on public.tenant_members to authenticated;
grant update (role, status) on public.tenant_members to authenticated;

grant select, delete on public.tenant_invites to authenticated;
grant insert (tenant_id, email, role, expires_at) on public.tenant_invites to authenticated;
grant update (email, role, expires_at, accepted_at, accepted_by)
  on public.tenant_invites to authenticated;

-- Self-service profile edits cannot touch role or tenant_id.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, phone) on public.profiles to authenticated;

-- Explicit business-table grants. Relying on the platform's default
-- "GRANT ALL TO authenticated" would leave columns such as loan.status or
-- transaction.payment_id writable. Every grant below is the minimum the
-- current client uses; anything else is server-owned.
revoke all on public.parties, public.loans, public.payments,
  public.emi_schedules, public.notification_queue, public.audit_logs,
  public.accounts, public.categories, public.transactions, public.budgets
  from anon, authenticated;

grant select on public.parties to authenticated;
grant insert (name, phone, address, id_number) on public.parties to authenticated;
grant update (name, phone, address, id_number, deleted_at)
  on public.parties to authenticated;

grant select on public.loans to authenticated;
grant insert (
  party_id, principal_amount, rate, rate_type, calculation_method, day_base,
  start_date, due_date, tenure_days, loan_type, direction, tds_pct, remarks
) on public.loans to authenticated;
grant update (deleted_at) on public.loans to authenticated;

-- Expand window only: the legacy payment writer still inserts a payment row
-- and archives it directly. Migration 2 replaces this with record_payment /
-- void_payment and reduces the client to SELECT.
grant select on public.payments to authenticated;
grant insert (
  loan_id, payment_date, total_amount, interest_amount, principal_amount,
  payment_method, remarks
) on public.payments to authenticated;
grant update (deleted_at) on public.payments to authenticated;

-- EMI rows are generated by the server/app read model; the client never
-- writes them today.
grant select on public.emi_schedules to authenticated;

-- Alerts are written by the scheduler (definer), read/acknowledged by users.
grant select on public.notification_queue to authenticated;
grant update (status, sent_at, deleted_at)
  on public.notification_queue to authenticated;

grant select on public.audit_logs to authenticated;
grant insert (table_name, row_id, action, old_data, new_data, actor)
  on public.audit_logs to authenticated;

grant select on public.accounts to authenticated;
grant insert (name, type, opening_balance) on public.accounts to authenticated;
grant update (name, type, opening_balance, deleted_at)
  on public.accounts to authenticated;

grant select on public.categories to authenticated;
grant insert (kind, name, icon) on public.categories to authenticated;
grant update (name, icon, deleted_at) on public.categories to authenticated;

grant select on public.transactions to authenticated;
grant insert (
  account_id, category_id, loan_id, kind, amount, txn_date, notes,
  transfer_direction, excluded_from_cashflow
) on public.transactions to authenticated;
grant update (deleted_at) on public.transactions to authenticated;

-- budget_form uses an upsert, which needs UPDATE on the payload columns.
grant select on public.budgets to authenticated;
grant insert (category_id, fy_year, fy_month, limit_amount)
  on public.budgets to authenticated;
grant update (category_id, fy_year, fy_month, limit_amount, deleted_at)
  on public.budgets to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Audit append-only guard
-- ---------------------------------------------------------------------------

create or replace function public.prevent_audit_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'audit_logs is append-only' using errcode = '42501';
end;
$$;

revoke all on function public.prevent_audit_mutation() from public, anon;

drop trigger if exists trg_audit_no_update on public.audit_logs;
create trigger trg_audit_no_update
  before update or delete on public.audit_logs
  for each row execute function public.prevent_audit_mutation();

