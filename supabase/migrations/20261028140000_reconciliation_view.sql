create or replace view public.reconciliation_exceptions
with (security_invoker = true) as
-- Payments that have no live wallet leg at all.
select
  p.tenant_id,
  p.id as payment_id,
  p.loan_id,
  p.payment_date,
  p.total_amount as payment_total,
  0::numeric(15,2) as legs_total,
  'missing_wallet_leg'::text as issue
from public.payments p
where p.deleted_at is null
  and not exists (
    select 1 from public.transactions t
    where t.tenant_id = p.tenant_id
      and t.payment_id = p.id
      and t.deleted_at is null
  )
union all
-- Payments whose live legs do not sum to the payment total.
select
  p.tenant_id,
  p.id as payment_id,
  p.loan_id,
  p.payment_date,
  p.total_amount as payment_total,
  coalesce(sum(t.amount), 0)::numeric(15,2) as legs_total,
  'amount_mismatch'::text as issue
from public.payments p
join public.transactions t
  on t.tenant_id = p.tenant_id and t.payment_id = p.id and t.deleted_at is null
where p.deleted_at is null
group by p.tenant_id, p.id, p.loan_id, p.payment_date, p.total_amount
having abs(coalesce(sum(t.amount), 0) - p.total_amount) > 0.01
union all
-- Wallet legs pointing at a voided or missing payment.
select
  t.tenant_id,
  t.payment_id as payment_id,
  t.loan_id,
  t.txn_date as payment_date,
  0::numeric(15,2) as payment_total,
  t.amount as legs_total,
  'orphan_wallet_leg'::text as issue
from public.transactions t
where t.payment_id is not null
  and t.deleted_at is null
  and not exists (
    select 1 from public.payments p
    where p.tenant_id = t.tenant_id and p.id = t.payment_id and p.deleted_at is null
  );

grant select on public.reconciliation_exceptions to authenticated;
revoke all on public.reconciliation_exceptions from anon;
