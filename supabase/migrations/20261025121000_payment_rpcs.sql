-- 20261025121000 payment RPCs + lifecycle
--
-- Makes money writes server-authoritative. After this migration the client
-- can no longer insert or update public.payments directly; it must call:
--   record_payment(...)  interest-first split, atomic payment + wallet legs
--   void_payment(...)    soft-delete the newest live payment and its legs
--   close_loan(...)      freeze accrual and optionally write off the balance
--
-- Apply order (production):
--   1. 20261025120000_tenant_membership_rls  (tenancy + read/write RLS)
--   2. deploy the hardened client            (uses the RPCs when present)
--   3. this migration                        (revokes direct payment writes)
--
-- The function bodies intentionally mirror app/lib/src/core/calculator/
-- loan_calculator.dart. If the Dart formula changes, this file must change in
-- the same release or client previews will disagree with posted amounts.
--
-- All functions are SECURITY DEFINER and owned by the migration role
-- (postgres on Supabase), which bypasses RLS. They therefore repeat every
-- tenant/role check explicitly and use an empty search_path.

-- The migration runner wraps each file in a transaction. Do not add explicit
-- BEGIN/COMMIT here: an inner COMMIT would end the runner's transaction and
-- could leave an applied schema unrecorded in supabase_migrations.

-- ---------------------------------------------------------------------------
-- 1. Schema: loan lifecycle, payment idempotency/voiding, cashflow linkage
-- ---------------------------------------------------------------------------

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

-- NOT VALID keeps legacy rows from blocking the deploy while still enforcing
-- the rule for every new or updated row.
alter table public.loans drop constraint if exists loans_write_off_amount_check;
alter table public.loans add constraint loans_write_off_amount_check
  check (write_off_amount >= 0) not valid;

alter table public.payments drop constraint if exists payments_split_check;
alter table public.payments add constraint payments_split_check
  check (
    interest_amount >= 0
    and principal_amount >= 0
    and abs((interest_amount + principal_amount) - total_amount) <= 0.01
  ) not valid;

alter table public.payments drop constraint if exists payments_void_consistency_check;
alter table public.payments add constraint payments_void_consistency_check
  check (voided_at is null or deleted_at is not null) not valid;

-- Legacy transfer rows have no direction. Keep the check permissive so
-- archiving an old row still works; the client always writes a direction for
-- new transfers.
alter table public.transactions drop constraint if exists transactions_transfer_direction_check;
alter table public.transactions add constraint transactions_transfer_direction_check
  check (transfer_direction is null or transfer_direction in ('in', 'out'));

create unique index if not exists uq_payments_tenant_client
  on public.payments (tenant_id, client_id)
  where client_id is not null;

-- Defensive: migration 1 creates this unique key, but a partially-applied
-- environment must not fail the FK below.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.payments'::regclass
      and conname = 'uq_payments_id_tenant'
  ) then
    alter table public.payments
      add constraint uq_payments_id_tenant unique (id, tenant_id);
  end if;
end
$$;

alter table public.transactions drop constraint if exists transactions_payment_tenant_fk;
alter table public.transactions add constraint transactions_payment_tenant_fk
  foreign key (payment_id, tenant_id)
  references public.payments (id, tenant_id)
  on delete restrict;

create index if not exists idx_txns_payment
  on public.transactions (payment_id)
  where payment_id is not null;

-- Defensive copy of the migration-1 fixes for environments that applied the
-- earlier draft before those fixes landed.
alter table public.tenants enable row level security;
alter table public.tenant_members enable row level security;
alter table public.tenant_invites enable row level security;

-- ---------------------------------------------------------------------------
-- 2. Backfill legacy data
-- ---------------------------------------------------------------------------

update public.transactions
set transfer_direction = case
  when notes ilike '%(in)' then 'in'
  when notes ilike '%(out)' then 'out'
  when notes ilike 'transfer-in%' then 'in'
  when notes ilike 'transfer-out%' then 'out'
  else null
end
where kind = 'transfer'
  and transfer_direction is null;

update public.transactions
set excluded_from_cashflow = true
where loan_id is not null
  and excluded_from_cashflow = false
  and (
    notes ilike 'loan principal%'
    or notes ilike '%principal received%'
    or notes ilike '%principal paid%'
  );

-- Legacy payments were written with the payment and its wallet legs as
-- separate requests, so transactions.payment_id is null. Link the unambiguous
-- pairs; ambiguous same-day/same-amount rows stay null and are reported by the
-- verification script for manual reconciliation.
with candidates as (
  select
    t.id as txn_id,
    p.id as payment_id,
    count(*) over (partition by t.id) as matches
  from public.transactions t
  join public.payments p
    on p.tenant_id = t.tenant_id
   and p.loan_id = t.loan_id
   and p.payment_date = t.txn_date
   and p.deleted_at is null
  where t.payment_id is null
    and t.deleted_at is null
    and (
      (t.amount = p.interest_amount and t.notes ilike 'loan interest%')
      or (t.amount = p.principal_amount and t.notes ilike 'loan principal%')
    )
)
update public.transactions t
set payment_id = c.payment_id
from candidates c
where c.txn_id = t.id
  and c.matches = 1;

-- Existing closed loans have no accrual end date. Freeze them at the best
-- known date so the party statement does not keep accruing interest forever.
update public.loans
set accrual_end_date =
      coalesce(
        due_date,
        (updated_at at time zone 'Asia/Kathmandu')::date,
        start_date
      ),
    closed_at = coalesce(closed_at, updated_at)
where status = 'closed'
  and accrual_end_date is null;

-- ---------------------------------------------------------------------------
-- 3. Nepal civil date
-- ---------------------------------------------------------------------------

create or replace function public.nepal_today()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Asia/Kathmandu')::date;
$$;

comment on function public.nepal_today() is
  'Current civil date in Asia/Kathmandu. Supabase Postgres runs in UTC, so current_date is wrong for Nepal between 18:15 and midnight UTC.';

-- ---------------------------------------------------------------------------
-- 4. record_payment
-- ---------------------------------------------------------------------------

create or replace function public.record_payment(
  p_loan_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_payment_method text default 'cash',
  p_remarks text default null,
  p_account_id uuid default null,
  p_client_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_loan public.loans%rowtype;
  v_existing public.payments%rowtype;
  v_payment_id uuid;
  v_account_id uuid;
  v_today date;
  v_amount numeric(15,2);
  v_annual numeric;
  v_per_day numeric(15,2);
  v_days int;
  v_accrued numeric(15,2);
  v_interest_paid numeric(15,2);
  v_interest_due numeric(15,2);
  v_interest_part numeric(15,2);
  v_principal_part numeric(15,2);
  v_principal_paid numeric(15,2);
  v_unpaid_principal numeric(15,2);
  v_latest_date date;
  v_excess numeric(15,2);
  v_method text;
  v_is_receivable boolean;
  v_category_id uuid;
  v_outstanding_after numeric(15,2);
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'No active organisation membership' using errcode = '42501';
  end if;
  if not public.is_tenant_writer(v_tenant) then
    raise exception 'Only an owner or manager can record payments'
      using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero'
      using errcode = '22023';
  end if;
  if p_amount <> round(p_amount, 2) then
    raise exception 'Payment amount must have at most 2 decimal places'
      using errcode = '22023';
  end if;
  v_amount := p_amount;

  v_method := coalesce(nullif(trim(p_payment_method), ''), 'cash');
  if v_method not in ('cash', 'bank_transfer', 'cheque', 'online') then
    raise exception 'Unsupported payment method: %', p_payment_method
      using errcode = '22023';
  end if;

  v_today := public.nepal_today();
  if p_payment_date is null then
    raise exception 'Payment date is required' using errcode = '22023';
  end if;
  if p_payment_date > v_today then
    raise exception 'Payment date cannot be in the future (Nepal date is %)',
      v_today
      using errcode = '22023';
  end if;

  -- Idempotent retry: the client generates one UUID per save attempt. A
  -- network timeout must not create a second payment.
  if p_client_id is not null then
    select * into v_existing
    from public.payments
    where tenant_id = v_tenant
      and client_id = p_client_id;

    if found then
      -- A voided payment must not be reported as a successful retry: the money
      -- was reversed. The caller needs a new client_id for a new payment.
      if v_existing.deleted_at is not null then
        raise exception 'client_id belongs to a voided payment'
          using errcode = '23505';
      end if;
      if v_existing.loan_id <> p_loan_id then
        raise exception 'client_id was already used for a different loan'
          using errcode = '23505';
      end if;
      if v_existing.total_amount <> v_amount then
        raise exception 'client_id was already used for a different amount'
          using errcode = '23505';
      end if;
      if v_existing.payment_date <> p_payment_date then
        raise exception 'client_id was already used for a different date'
          using errcode = '23505';
      end if;
      return jsonb_build_object(
        'payment_id', v_existing.id,
        'loan_id', v_existing.loan_id,
        'total_amount', v_existing.total_amount,
        'interest_amount', v_existing.interest_amount,
        'principal_amount', v_existing.principal_amount,
        'idempotent', true
      );
    end if;
  end if;

  select * into v_loan
  from public.loans
  where id = p_loan_id
    and tenant_id = v_tenant
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Loan not found' using errcode = 'P0002';
  end if;
  if v_loan.status <> 'active' then
    raise exception 'Loan is not active (status: %)', v_loan.status
      using errcode = '22023';
  end if;
  if p_payment_date < v_loan.start_date then
    raise exception 'Payment date cannot be before the loan start date (%)',
      v_loan.start_date
      using errcode = '22023';
  end if;

  -- Out-of-order backdating makes interest-first allocations irreproducible.
  -- Same-day entries are allowed; corrections use void_payment.
  select max(payment_date) into v_latest_date
  from public.payments
  where tenant_id = v_tenant
    and loan_id = v_loan.id
    and deleted_at is null;

  if v_latest_date is not null and p_payment_date < v_latest_date then
    raise exception 'Payments must be recorded in date order; the latest payment is dated %',
      v_latest_date
      using errcode = '22023';
  end if;

  if p_account_id is not null then
    select a.id into v_account_id
    from public.accounts a
    where a.id = p_account_id
      and a.tenant_id = v_tenant
      and a.deleted_at is null;

    if v_account_id is null then
      raise exception 'Wallet not found' using errcode = 'P0002';
    end if;
  end if;

  -- Mirror LoanCalculator: annualise the quoted rate, then
  -- principal * annual / day_base rounded to paisa.
  v_annual := case v_loan.rate_type
    when 'monthly' then v_loan.rate * 12
    when 'daily' then v_loan.rate * 360
    else v_loan.rate
  end;

  v_per_day := round(v_loan.principal_amount * v_annual / v_loan.day_base, 2);
  v_days := greatest(0, p_payment_date - v_loan.start_date);
  v_accrued := round(v_per_day * v_days, 2);

  -- Civil Code 2074 s.481: cumulative interest may not exceed the principal.
  if v_accrued > v_loan.principal_amount then
    v_accrued := v_loan.principal_amount;
  end if;

  select coalesce(sum(interest_amount), 0)
    into v_interest_paid
  from public.payments
  where tenant_id = v_tenant
    and loan_id = v_loan.id
    and deleted_at is null;

  v_interest_due := greatest(0, v_accrued - v_interest_paid);
  v_interest_part := round(least(v_amount, v_interest_due), 2);
  v_principal_part := round(v_amount - v_interest_part, 2);

  select coalesce(sum(principal_amount), 0)
    into v_principal_paid
  from public.payments
  where tenant_id = v_tenant
    and loan_id = v_loan.id
    and deleted_at is null;

  v_unpaid_principal :=
    greatest(0, v_loan.principal_amount - v_principal_paid);

  if v_principal_part > v_unpaid_principal then
    v_excess := round(v_principal_part - v_unpaid_principal, 2);
    raise exception 'Payment exceeds the unpaid principal by %', v_excess
      using errcode = '22003';
  end if;

  begin
    insert into public.payments (
      tenant_id,
      loan_id,
      payment_date,
      total_amount,
      interest_amount,
      principal_amount,
      payment_method,
      remarks,
      client_id,
      created_by
    ) values (
      v_tenant,
      v_loan.id,
      p_payment_date,
      v_amount,
      v_interest_part,
      v_principal_part,
      v_method,
      nullif(trim(p_remarks), ''),
      p_client_id,
      auth.uid()
    )
    returning id into v_payment_id;
  exception when unique_violation then
    -- A concurrent retry won the insert race. Return that row instead of
    -- failing a request whose money already moved.
    if p_client_id is not null then
      select * into v_existing
      from public.payments
      where tenant_id = v_tenant
        and client_id = p_client_id;

      if found then
        if v_existing.deleted_at is not null then
          raise exception 'client_id belongs to a voided payment'
            using errcode = '23505';
        end if;
        if v_existing.loan_id <> p_loan_id
           or v_existing.total_amount <> v_amount
           or v_existing.payment_date <> p_payment_date then
          raise exception 'client_id was already used for a different request'
            using errcode = '23505';
        end if;
        return jsonb_build_object(
          'payment_id', v_existing.id,
          'loan_id', v_existing.loan_id,
          'total_amount', v_existing.total_amount,
          'interest_amount', v_existing.interest_amount,
          'principal_amount', v_existing.principal_amount,
          'idempotent', true
        );
      end if;
    end if;
    raise;
  end;

  -- Wallet legs are optional. When present they are inserted in the same
  -- transaction as the payment and can only be voided through void_payment.
  if v_account_id is not null then
    v_is_receivable := v_loan.direction = 'receivable';

    if v_interest_part > 0 then
      select c.id into v_category_id
      from public.categories c
      where c.tenant_id = v_tenant
        and c.kind = case when v_is_receivable then 'income' else 'expense' end
        and c.deleted_at is null
        and lower(c.name) like '%interest%'
      order by c.created_at
      limit 1;

      insert into public.transactions (
        tenant_id,
        account_id,
        category_id,
        loan_id,
        payment_id,
        kind,
        amount,
        txn_date,
        notes,
        excluded_from_cashflow
      ) values (
        v_tenant,
        v_account_id,
        v_category_id,
        v_loan.id,
        v_payment_id,
        case when v_is_receivable then 'income' else 'expense' end,
        v_interest_part,
        p_payment_date,
        case when v_is_receivable
          then 'loan interest received'
          else 'loan interest paid'
        end,
        false
      );
    end if;

    if v_principal_part > 0 then
      insert into public.transactions (
        tenant_id,
        account_id,
        category_id,
        loan_id,
        payment_id,
        kind,
        amount,
        txn_date,
        notes,
        excluded_from_cashflow
      ) values (
        v_tenant,
        v_account_id,
        null,
        v_loan.id,
        v_payment_id,
        case when v_is_receivable then 'income' else 'expense' end,
        v_principal_part,
        p_payment_date,
        case when v_is_receivable
          then 'loan principal received'
          else 'loan principal paid'
        end,
        true
      );
    end if;
  end if;

  v_outstanding_after := round(
    greatest(0, v_unpaid_principal - v_principal_part)
    + greatest(0, v_interest_due - v_interest_part),
    2
  );

  insert into public.audit_logs (
    tenant_id,
    table_name,
    row_id,
    action,
    new_data,
    actor
  ) values (
    v_tenant,
    'payments',
    v_payment_id,
    'insert',
    jsonb_build_object(
      'loan_id', v_loan.id,
      'payment_date', p_payment_date,
      'total_amount', v_amount,
      'interest_amount', v_interest_part,
      'principal_amount', v_principal_part,
      'payment_method', v_method,
      'account_id', v_account_id,
      'client_id', p_client_id
    ),
    auth.uid()
  );

  return jsonb_build_object(
    'payment_id', v_payment_id,
    'loan_id', v_loan.id,
    'total_amount', v_amount,
    'interest_amount', v_interest_part,
    'principal_amount', v_principal_part,
    'outstanding_after', v_outstanding_after,
    'idempotent', false
  );
end;
$$;

comment on function public.record_payment(uuid, numeric, date, text, text, uuid, uuid) is
  'Atomically records an interest-first payment, optional wallet legs and an audit row. Owner/manager only; idempotent on client_id.';

-- ---------------------------------------------------------------------------
-- 5. void_payment
-- ---------------------------------------------------------------------------

create or replace function public.void_payment(
  p_payment_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_payment public.payments%rowtype;
  v_loan public.loans%rowtype;
  v_latest_id uuid;
  v_reopened boolean := false;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'No active organisation membership' using errcode = '42501';
  end if;
  if not public.is_tenant_writer(v_tenant) then
    raise exception 'Only an owner or manager can void payments'
      using errcode = '42501';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id
    and tenant_id = v_tenant
  for update;

  if not found then
    raise exception 'Payment not found' using errcode = 'P0002';
  end if;

  if v_payment.deleted_at is not null then
    return jsonb_build_object(
      'payment_id', v_payment.id,
      'loan_id', v_payment.loan_id,
      'voided', true,
      'already_voided', true
    );
  end if;

  -- Reversal discipline: only the newest live payment can be removed, so the
  -- remaining interest-first allocations stay in recorded order.
  select p.id into v_latest_id
  from public.payments p
  where p.tenant_id = v_tenant
    and p.loan_id = v_payment.loan_id
    and p.deleted_at is null
  order by p.payment_date desc, p.created_at desc, p.id desc
  limit 1;

  if v_latest_id is distinct from v_payment.id then
    raise exception 'Only the most recent live payment for this loan can be voided'
      using errcode = '23514';
  end if;

  update public.payments
  set deleted_at = now(),
      voided_at = now(),
      voided_by = auth.uid(),
      void_reason = nullif(trim(p_reason), '')
  where id = v_payment.id
    and tenant_id = v_tenant;

  update public.transactions
  set deleted_at = now()
  where tenant_id = v_tenant
    and payment_id = v_payment.id
    and deleted_at is null;

  select * into v_loan
  from public.loans
  where id = v_payment.loan_id
    and tenant_id = v_tenant
  for update;

  -- A payment that had settled a loan reverses the closure too, otherwise the
  -- loan would stay closed with a negative/incorrect outstanding balance.
  if found and v_loan.status = 'closed' then
    update public.loans
    set status = 'active',
        accrual_end_date = null,
        closed_at = null,
        closed_by = null,
        write_off_amount = 0,
        write_off_reason = null
    where id = v_loan.id
      and tenant_id = v_tenant;
    v_reopened := true;
  end if;

  insert into public.audit_logs (
    tenant_id,
    table_name,
    row_id,
    action,
    old_data,
    new_data,
    actor
  ) values (
    v_tenant,
    'payments',
    v_payment.id,
    'void',
    to_jsonb(v_payment) - 'tenant_id',
    jsonb_build_object(
      'void_reason', nullif(trim(p_reason), ''),
      'reopened_loan', v_reopened
    ),
    auth.uid()
  );

  return jsonb_build_object(
    'payment_id', v_payment.id,
    'loan_id', v_payment.loan_id,
    'voided', true,
    'already_voided', false,
    'reopened_loan', v_reopened
  );
end;
$$;

comment on function public.void_payment(uuid, text) is
  'Soft-deletes the newest live payment for a loan, its linked wallet legs, and reopens the loan if it had been closed.';

-- ---------------------------------------------------------------------------
-- 6. close_loan
-- ---------------------------------------------------------------------------

create or replace function public.close_loan(
  p_loan_id uuid,
  p_write_off boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_loan public.loans%rowtype;
  v_today date;
  v_as_of date;
  v_annual numeric;
  v_per_day numeric(15,2);
  v_days int;
  v_accrued numeric(15,2);
  v_interest_paid numeric(15,2);
  v_interest_due numeric(15,2);
  v_principal_paid numeric(15,2);
  v_principal_due numeric(15,2);
  v_outstanding numeric(15,2);
  v_written_off numeric(15,2);
  v_reason text;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'No active organisation membership' using errcode = '42501';
  end if;
  if not public.is_tenant_writer(v_tenant) then
    raise exception 'Only an owner or manager can close loans'
      using errcode = '42501';
  end if;

  select * into v_loan
  from public.loans
  where id = p_loan_id
    and tenant_id = v_tenant
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Loan not found' using errcode = 'P0002';
  end if;

  if v_loan.status = 'closed' then
    return jsonb_build_object(
      'loan_id', v_loan.id,
      'status', 'closed',
      'already_closed', true,
      'outstanding', 0,
      'written_off', v_loan.write_off_amount
    );
  end if;

  if v_loan.status <> 'active' then
    raise exception 'Only an active loan can be closed (status: %)',
      v_loan.status
      using errcode = '22023';
  end if;

  v_today := public.nepal_today();
  v_as_of := coalesce(v_loan.accrual_end_date, v_today);
  if v_as_of < v_loan.start_date then
    v_as_of := v_loan.start_date;
  end if;

  v_annual := case v_loan.rate_type
    when 'monthly' then v_loan.rate * 12
    when 'daily' then v_loan.rate * 360
    else v_loan.rate
  end;

  v_per_day := round(v_loan.principal_amount * v_annual / v_loan.day_base, 2);
  v_days := greatest(0, v_as_of - v_loan.start_date);
  v_accrued := round(v_per_day * v_days, 2);

  if v_accrued > v_loan.principal_amount then
    v_accrued := v_loan.principal_amount;
  end if;

  select coalesce(sum(interest_amount), 0)
    into v_interest_paid
  from public.payments
  where tenant_id = v_tenant
    and loan_id = v_loan.id
    and deleted_at is null;

  select coalesce(sum(principal_amount), 0)
    into v_principal_paid
  from public.payments
  where tenant_id = v_tenant
    and loan_id = v_loan.id
    and deleted_at is null;

  v_interest_due := greatest(0, v_accrued - v_interest_paid);
  v_principal_due :=
    greatest(0, v_loan.principal_amount - v_principal_paid);
  v_outstanding := round(v_principal_due + v_interest_due, 2);
  v_written_off := case when v_outstanding > 0 then v_outstanding else 0 end;
  v_reason := nullif(trim(p_reason), '');

  if v_outstanding > 0 and not coalesce(p_write_off, false) then
    raise exception 'Loan still has % outstanding (principal % + interest %)',
      v_outstanding, v_principal_due, v_interest_due
      using errcode = '23514';
  end if;

  if v_outstanding > 0 and v_reason is null then
    raise exception 'A write-off reason is required'
      using errcode = '22023';
  end if;

  update public.loans
  set status = 'closed',
      accrual_end_date = v_as_of,
      closed_at = now(),
      closed_by = auth.uid(),
      write_off_amount = v_written_off,
      write_off_reason = case when v_written_off > 0 then v_reason else null end
  where id = v_loan.id
    and tenant_id = v_tenant;

  insert into public.audit_logs (
    tenant_id,
    table_name,
    row_id,
    action,
    old_data,
    new_data,
    actor
  ) values (
    v_tenant,
    'loans',
    v_loan.id,
    'close',
    jsonb_build_object('status', v_loan.status),
    jsonb_build_object(
      'status', 'closed',
      'as_of', v_as_of,
      'principal_outstanding', v_principal_due,
      'interest_outstanding', v_interest_due,
      'outstanding', v_outstanding,
      'written_off', v_written_off,
      'write_off_reason', v_reason
    ),
    auth.uid()
  );

  return jsonb_build_object(
    'loan_id', v_loan.id,
    'status', 'closed',
    'as_of', v_as_of,
    'principal_outstanding', v_principal_due,
    'interest_outstanding', v_interest_due,
    'outstanding', v_outstanding,
    'written_off', v_written_off,
    'already_closed', false
  );
end;
$$;

comment on function public.close_loan(uuid, boolean, text) is
  'Closes a loan after freezing accrual at the Nepal civil date. Requires full payment unless p_write_off is true with a reason.';

-- ---------------------------------------------------------------------------
-- 7. Privileges: functions callable by signed-in users, payments read-only
-- ---------------------------------------------------------------------------

revoke all on function public.nepal_today() from public, anon;
grant execute on function public.nepal_today() to authenticated;

revoke all on function public.record_payment(uuid, numeric, date, text, text, uuid, uuid) from public, anon;
grant execute on function public.record_payment(uuid, numeric, date, text, text, uuid, uuid) to authenticated;

revoke all on function public.void_payment(uuid, text) from public, anon;
grant execute on function public.void_payment(uuid, text) to authenticated;

revoke all on function public.close_loan(uuid, boolean, text) from public, anon;
grant execute on function public.close_loan(uuid, boolean, text) to authenticated;

-- Payments become append-only through the RPCs. Keep SELECT for reports.
drop policy if exists p_payments_insert on public.payments;
drop policy if exists p_payments_update on public.payments;
revoke all on public.payments from anon;
revoke all on public.payments from authenticated;
grant select on public.payments to authenticated;

-- Transactions stay directly writable for ordinary income/expense/transfer
-- entries, but payment_id is deliberately absent from the column grant so a
-- client cannot forge a link to someone else's payment. Archiving is the only
-- supported update.
revoke all on public.transactions from authenticated;
grant select on public.transactions to authenticated;
grant insert (
  account_id,
  category_id,
  loan_id,
  kind,
  amount,
  txn_date,
  notes,
  transfer_direction,
  excluded_from_cashflow
) on public.transactions to authenticated;
grant update (deleted_at) on public.transactions to authenticated;

-- Loan lifecycle columns are server-owned. Clients may create a loan and
-- archive it, but cannot set status, close dates, accrual freeze, or write-off
-- amounts directly.
revoke all on public.loans from authenticated;
grant select on public.loans to authenticated;
grant insert (
  party_id,
  principal_amount,
  rate,
  rate_type,
  calculation_method,
  day_base,
  start_date,
  due_date,
  tenure_days,
  loan_type,
  direction,
  tds_pct,
  remarks
) on public.loans to authenticated;
grant update (deleted_at) on public.loans to authenticated;

-- The app has no anonymous data surface. RLS already denies anon, but removing
-- the grants closes the second line of defence if a future policy is added
-- with the wrong role list.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

notify pgrst, 'reload schema';

