-- 20261025 staging smoke test
--
-- Exercises the deployed RPCs as a real authenticated owner so RLS and column
-- grants are in force. Every write happens inside this transaction and is
-- rolled back. Run only on a staging project, never on production data.
--
-- Requires at least one active owner in public.tenant_members. The script
-- impersonates the oldest active owner; replace the SELECT with a specific
-- user id if you want a dedicated test account.
--
-- Any raised exception aborts the transaction. Roll back manually if your SQL
-- client leaves the session in a failed transaction.

begin;

select set_config('request.jwt.uid', tm.user_id::text, true)
from public.tenant_members tm
where tm.role = 'owner'
  and tm.status = 'active'
order by tm.created_at
limit 1;

do $$
begin
  if coalesce(current_setting('request.jwt.uid', true), '') = '' then
    raise exception 'No active owner membership found; bootstrap a tenant first';
  end if;
end;
$$;

create temp table _smoke_ids (
  key text primary key,
  id uuid not null
) on commit drop;

grant select, insert, update, delete on _smoke_ids to authenticated;

set local role authenticated;

do $$
declare
  v_tenant uuid;
  v_today date;
begin
  v_tenant := public.current_tenant_id();
  v_today := public.nepal_today();
  if v_tenant is null then
    raise exception 'current_tenant_id() returned null for an active owner';
  end if;
  if v_today <> (now() at time zone 'Asia/Kathmandu')::date then
    raise exception 'nepal_today() disagrees with Asia/Kathmandu';
  end if;
  raise notice 'tenant=% nepal_today=%', v_tenant, v_today;
end;
$$;

with p as (
  insert into public.parties (name, phone)
  values ('__smoke_test__', '0000000000')
  returning id
)
insert into _smoke_ids (key, id) select 'party', id from p;

with a as (
  insert into public.accounts (name, type, opening_balance)
  values ('__smoke_cash__', 'cash', 0)
  returning id
)
insert into _smoke_ids (key, id) select 'account', id from a;

with l as (
  insert into public.loans
    (party_id, principal_amount, rate, rate_type, calculation_method,
     day_base, start_date, direction, loan_type)
  values (
    (select id from _smoke_ids where key = 'party'),
    1000, 0, 'annual', 'daily_accrual', 360,
    public.nepal_today(), 'receivable', 'personal'
  )
  returning id
)
insert into _smoke_ids (key, id) select 'loan', id from l;

with r as (
  select public.record_payment(
    (select id from _smoke_ids where key = 'loan'),
    100,
    public.nepal_today(),
    'cash',
    'staging smoke test',
    (select id from _smoke_ids where key = 'account'),
    gen_random_uuid()
  ) as res
)
insert into _smoke_ids (key, id)
select 'payment', (res ->> 'payment_id')::uuid from r;

do $$
declare
  v_payment public.payments%rowtype;
  v_legs int;
begin
  select * into v_payment
  from public.payments
  where id = (select id from _smoke_ids where key = 'payment');

  if not found then
    raise exception 'record_payment did not create a visible payment';
  end if;
  if v_payment.total_amount <> 100
     or v_payment.interest_amount <> 0
     or v_payment.principal_amount <> 100
     or v_payment.created_by is null then
    raise exception 'unexpected payment split: total=% interest=% principal=% created_by=%',
      v_payment.total_amount, v_payment.interest_amount,
      v_payment.principal_amount, v_payment.created_by;
  end if;

  select count(*) into v_legs
  from public.transactions
  where payment_id = v_payment.id
    and deleted_at is null;
  if v_legs <> 1 then
    raise exception 'expected 1 live wallet leg, found %', v_legs;
  end if;
end;
$$;

-- Overpayment must be rejected by the server even though the client hides it.
do $$
begin
  perform public.record_payment(
    (select id from _smoke_ids where key = 'loan'),
    100000,
    public.nepal_today(),
    'cash',
    null,
    (select id from _smoke_ids where key = 'account'),
    gen_random_uuid()
  );
  raise exception 'overpayment was accepted';
exception
  when sqlstate '22003' then
    null;
end;
$$;

-- Direct payment writes must be impossible after migration 2.
do $$
begin
  insert into public.payments
    (loan_id, payment_date, total_amount, interest_amount, principal_amount)
  values (
    (select id from _smoke_ids where key = 'loan'),
    public.nepal_today(), 1, 1, 0
  );
  raise exception 'direct payment insert was accepted';
exception
  when insufficient_privilege then
    null;
end;
$$;

select public.close_loan(
  (select id from _smoke_ids where key = 'loan'),
  true,
  'staging smoke-test write-off'
) as close_result;

do $$
declare
  v_status text;
  v_written numeric;
begin
  select status, write_off_amount into v_status, v_written
  from public.loans
  where id = (select id from _smoke_ids where key = 'loan');

  if v_status <> 'closed' or v_written <> 900 then
    raise exception 'unexpected close state: status=% written_off=%', v_status, v_written;
  end if;
end;
$$;

select public.void_payment(
  (select id from _smoke_ids where key = 'payment'),
  'staging smoke-test reversal'
) as void_result;

do $$
declare
  v_status text;
  v_voided timestamptz;
begin
  select status into v_status
  from public.loans
  where id = (select id from _smoke_ids where key = 'loan');
  select voided_at into v_voided
  from public.payments
  where id = (select id from _smoke_ids where key = 'payment');

  if v_status <> 'active' then
    raise exception 'void_payment did not reopen the loan (status=%)', v_status;
  end if;
  if v_voided is null then
    raise exception 'void_payment did not set voided_at';
  end if;
end;
$$;

select 'PASS' as status,
       'record_payment, overpayment guard, write-off close and void reopen' as exercised;

rollback;
