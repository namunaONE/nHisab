-- 20261015140000 budget_tracker_v1 (APPLIED remote 2026-10-15, seeded 3 accounts + 8 categories)
-- Wallets-first budget tracker: accounts, categories, transactions, budgets.
-- Conventions: tenant_id default single-tenant, RLS authenticated via current_tenant_id(),
-- soft-delete deleted_at, NUMERIC(15,2) money, AD DATE storage, BS display in app.
-- Apply via Supabase MCP/SQL only after review. Providers return [] until applied.

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  name text not null,
  type text not null check (type in ('cash','bank','mobile_wallet')),
  opening_balance numeric(15,2) not null default 0,
  created_at timestamptz default now(),
  deleted_at timestamptz
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  kind text not null check (kind in ('income','expense')),
  name text not null,
  icon text,
  created_at timestamptz default now(),
  deleted_at timestamptz,
  unique(tenant_id, kind, name)
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  account_id uuid not null references public.accounts(id) on delete restrict,
  category_id uuid references public.categories(id) on delete restrict,
  loan_id uuid references public.loans(id) on delete set null,
  kind text not null check (kind in ('income','expense','transfer')),
  amount numeric(15,2) not null check (amount > 0),
  txn_date date not null,
  notes text,
  created_at timestamptz default now(),
  deleted_at timestamptz
);

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  category_id uuid not null references public.categories(id) on delete cascade,
  fy_year int not null,
  fy_month int not null check (fy_month between 1 and 12),
  limit_amount numeric(15,2) not null check (limit_amount >= 0),
  created_at timestamptz default now(),
  deleted_at timestamptz,
  unique(tenant_id, category_id, fy_year, fy_month)
);

create index if not exists idx_accounts_tenant on public.accounts(tenant_id);
create index if not exists idx_categories_tenant on public.categories(tenant_id);
create index if not exists idx_txns_tenant on public.transactions(tenant_id);
create index if not exists idx_txns_account on public.transactions(account_id);
create index if not exists idx_txns_category on public.transactions(category_id);
create index if not exists idx_txns_date on public.transactions(txn_date);
create index if not exists idx_budgets_tenant on public.budgets(tenant_id);
create index if not exists idx_budgets_cat_month on public.budgets(category_id, fy_year, fy_month);
create index if not exists idx_accounts_deleted on public.accounts(deleted_at) where deleted_at is null;
create index if not exists idx_txns_deleted on public.transactions(deleted_at) where deleted_at is null;

alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;

drop policy if exists p_accounts_all on public.accounts;
create policy p_accounts_all on public.accounts
  for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

drop policy if exists p_categories_all on public.categories;
create policy p_categories_all on public.categories
  for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

drop policy if exists p_txns_all on public.transactions;
create policy p_txns_all on public.transactions
  for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

drop policy if exists p_budgets_all on public.budgets;
create policy p_budgets_all on public.budgets
  for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());
