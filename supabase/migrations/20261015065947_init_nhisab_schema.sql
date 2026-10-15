-- 20261015065947 init_nhisab_schema (applied remote via MCP, exported for repo reproducibility)
create extension if not exists "pgcrypto";

create table public.parties (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  name text not null,
  phone text,
  address text,
  id_number text,
  created_at timestamptz default now()
);

create table public.loans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  party_id uuid not null references public.parties(id) on delete restrict,
  principal_amount numeric(15,2) not null check (principal_amount > 0),
  rate numeric(10,6) not null check (rate >= 0),
  rate_type text not null check (rate_type in ('daily','monthly','annual')),
  calculation_method text not null check (calculation_method in ('daily_accrual','reducing_balance','flat')),
  day_base int not null default 360 check (day_base in (360,365)),
  start_date date not null,
  due_date date,
  tenure_days int,
  loan_type text check (loan_type in ('personal','business','home','vehicle','cash_credit','demand')),
  direction text not null default 'receivable' check (direction in ('receivable','payable')),
  status text not null default 'active' check (status in ('active','closed','defaulted','restructured')),
  tds_pct numeric(5,2) default 0,
  remarks text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  loan_id uuid not null references public.loans(id) on delete cascade,
  payment_date date not null,
  total_amount numeric(15,2) not null check (total_amount > 0),
  interest_amount numeric(15,2) not null default 0,
  principal_amount numeric(15,2) not null default 0,
  payment_method text check (payment_method in ('cash','bank_transfer','cheque','online')),
  remarks text,
  created_at timestamptz default now()
);

create table public.emi_schedules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  loan_id uuid not null references public.loans(id) on delete cascade,
  installment_no int not null,
  due_date date not null,
  principal_due numeric(15,2) not null default 0,
  interest_due numeric(15,2) not null default 0,
  total_due numeric(15,2) not null default 0,
  status text not null default 'pending' check (status in ('pending','paid','overdue')),
  paid_date date,
  paid_amount numeric(15,2),
  created_at timestamptz default now(),
  unique(loan_id, installment_no)
);

create table public.notification_queue (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  loan_id uuid references public.loans(id) on delete cascade,
  alert_type text not null,
  channel text not null check (channel in ('email','sms','in_app')),
  status text not null default 'pending' check (status in ('pending','sent','failed')),
  scheduled_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  table_name text not null,
  row_id uuid,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  actor uuid,
  created_at timestamptz default now()
);

create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists trg_loans_updated on public.loans;
create trigger trg_loans_updated before update on public.loans
for each row execute function public.handle_updated_at();

create index idx_parties_tenant on public.parties(tenant_id);
create index idx_loans_tenant on public.loans(tenant_id);
create index idx_loans_party on public.loans(party_id);
create index idx_loans_status on public.loans(status);
create index idx_loans_due on public.loans(due_date);
create index idx_payments_loan on public.payments(loan_id);
create index idx_payments_tenant on public.payments(tenant_id);
create index idx_emi_loan on public.emi_schedules(loan_id);
create index idx_notif_status on public.notification_queue(status);

alter table public.parties enable row level security;
alter table public.loans enable row level security;
alter table public.payments enable row level security;
alter table public.emi_schedules enable row level security;
alter table public.notification_queue enable row level security;
alter table public.audit_logs enable row level security;

create or replace function public.current_tenant_id()
returns uuid language sql stable as $$
  select coalesce(
    nullif((auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '')::uuid,
    '00000000-0000-0000-0000-000000000001'::uuid
  );
$$;

create policy tenant_all on public.parties for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());
create policy tenant_all on public.loans for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());
create policy tenant_all on public.payments for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());
create policy tenant_all on public.emi_schedules for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());
create policy tenant_all on public.notification_queue for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());
create policy tenant_all on public.audit_logs for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());
