create table if not exists public.period_closes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  fy_year int not null,
  fy_month int not null check (fy_month between 1 and 12),
  closed_at timestamptz not null default now(),
  closed_by uuid references auth.users(id) on delete set null,
  note text,
  unique (tenant_id, fy_year, fy_month)
);

alter table public.period_closes enable row level security;

drop policy if exists p_period_closes_select on public.period_closes;
create policy p_period_closes_select on public.period_closes
  for select to authenticated
  using (tenant_id = public.current_tenant_id());

drop policy if exists p_period_closes_insert on public.period_closes;
create policy p_period_closes_insert on public.period_closes
  for insert to authenticated
  with check (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id));

grant select, insert on public.period_closes to authenticated;
revoke all on public.period_closes from anon;

create or replace function public.is_period_closed(p_tenant uuid, p_date date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- FY bucketing matches the app's approximation: FY starts July (month 7).
  select exists (
    select 1 from public.period_closes pc
    where pc.tenant_id = p_tenant
      and pc.fy_year = case when extract(month from p_date) >= 7
                            then extract(year from p_date)::int
                            else extract(year from p_date)::int - 1 end
      and pc.fy_month = case when extract(month from p_date) >= 7
                             then extract(month from p_date)::int - 6
                             else extract(month from p_date)::int + 6 end
  );
$$;

create or replace function public.close_period(p_fy_year int, p_fy_month int, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_tenant uuid;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'No active organisation membership' using errcode='42501'; end if;
  if not public.is_tenant_writer(v_tenant) then raise exception 'Only an owner or manager can close periods' using errcode='42501'; end if;
  if p_fy_month < 1 or p_fy_month > 12 then raise exception 'fy_month must be 1..12' using errcode='22023'; end if;
  insert into public.period_closes (tenant_id, fy_year, fy_month, closed_by, note)
  values (v_tenant, p_fy_year, p_fy_month, auth.uid(), nullif(trim(p_note),''))
  on conflict (tenant_id, fy_year, fy_month) do nothing;
  return jsonb_build_object('fy_year', p_fy_year, 'fy_month', p_fy_month, 'closed', true);
end;
$$;

revoke all on function public.close_period(int,int,text) from public, anon;
grant execute on function public.close_period(int,int,text) to authenticated;
revoke all on function public.is_period_closed(uuid,date) from public, anon;
grant execute on function public.is_period_closed(uuid,date) to authenticated;

-- Enforcement triggers: block inserts into a closed period.
create or replace function public.enforce_period_not_closed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_date date;
begin
  if tg_table_name = 'payments' then v_date := new.payment_date;
  elsif tg_table_name = 'transactions' then v_date := new.txn_date;
  else v_date := current_date;
  end if;
  if public.is_period_closed(new.tenant_id, v_date) then
    raise exception 'Period is closed for %', v_date using errcode='23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_payments_period_close on public.payments;
create trigger trg_payments_period_close
  before insert on public.payments
  for each row execute function public.enforce_period_not_closed();

drop trigger if exists trg_transactions_period_close on public.transactions;
create trigger trg_transactions_period_close
  before insert on public.transactions
  for each row execute function public.enforce_period_not_closed();
