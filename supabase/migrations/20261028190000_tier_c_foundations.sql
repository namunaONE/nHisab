-- KYC / AML fields on parties (Tier C foundations; verification workflow TBD).
alter table public.parties
  add column if not exists id_type text
    check (id_type is null or id_type in ('citizenship','passport','nid','pan','other')),
  add column if not exists id_verified boolean not null default false,
  add column if not exists verified_at timestamptz,
  add column if not exists verified_by uuid references auth.users(id) on delete set null,
  add column if not exists risk_rating text not null default 'low'
    check (risk_rating in ('low','medium','high')),
  add column if not exists consent_recorded_at timestamptz,
  add column if not exists retention_until date;

-- VAT ledger (report-only; not a filing system).
create table if not exists public.vat_ledger (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  entry_date date not null,
  description text,
  taxable_amount numeric(15,2) not null default 0,
  vat_rate numeric(5,2) not null default 13,
  vat_amount numeric(15,2) not null default 0,
  entry_type text not null check (entry_type in ('output','input')),
  reference text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.vat_ledger enable row level security;
drop policy if exists p_vat_ledger_select on public.vat_ledger;
create policy p_vat_ledger_select on public.vat_ledger for select to authenticated
  using (tenant_id = public.current_tenant_id());
drop policy if exists p_vat_ledger_write on public.vat_ledger;
create policy p_vat_ledger_write on public.vat_ledger for all to authenticated
  using (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id))
  with check (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id));
grant select, insert, update, delete on public.vat_ledger to authenticated;
revoke all on public.vat_ledger from anon;

-- TDS ledger (report-only).
create table if not exists public.tds_ledger (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  entry_date date not null,
  description text,
  gross_amount numeric(15,2) not null default 0,
  tds_rate numeric(5,2) not null default 15,
  tds_amount numeric(15,2) not null default 0,
  recipient text,
  reference text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.tds_ledger enable row level security;
drop policy if exists p_tds_ledger_select on public.tds_ledger;
create policy p_tds_ledger_select on public.tds_ledger for select to authenticated
  using (tenant_id = public.current_tenant_id());
drop policy if exists p_tds_ledger_write on public.tds_ledger;
create policy p_tds_ledger_write on public.tds_ledger for all to authenticated
  using (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id))
  with check (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id));
grant select, insert, update, delete on public.tds_ledger to authenticated;
revoke all on public.tds_ledger from anon;
