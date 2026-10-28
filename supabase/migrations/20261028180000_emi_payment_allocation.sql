alter table public.loans
  add column if not exists penalty_rate numeric(6,4) not null default 0,
  add column if not exists prepayment_allowed boolean not null default true;

alter table public.emi_schedules
  add column if not exists payment_id uuid references public.payments(id) on delete set null,
  add column if not exists penalty_amount numeric(15,2) not null default 0,
  add column if not exists paid_amount numeric(15,2);

-- RPC: record an EMI installment payment.
create or replace function public.record_emi_payment(
  p_loan_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_payment_method text default 'cash',
  p_account_id uuid default null,
  p_client_id uuid default null,
  p_installment_no int default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_loan public.loans%rowtype;
  v_amount numeric(15,2);
  v_today date;
  v_payment_id uuid;
  v_account_id uuid;
  v_method text;
  v_installment_no int;
  v_due_date date;
  v_penalty numeric(15,2) := 0;
  v_late_days int;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'No active organisation membership' using errcode='42501'; end if;
  if not public.is_tenant_writer(v_tenant) then raise exception 'Only an owner or manager can record payments' using errcode='42501'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero' using errcode='22023'; end if;
  v_amount := p_amount;
  v_method := coalesce(nullif(trim(p_payment_method),''),'cash');
  if v_method not in ('cash','bank_transfer','cheque','online') then raise exception 'Unsupported payment method' using errcode='22023'; end if;
  v_today := public.nepal_today();
  if p_payment_date is null or p_payment_date > v_today then raise exception 'Invalid payment date' using errcode='22023'; end if;

  select * into v_loan from public.loans where id=p_loan_id and tenant_id=v_tenant and deleted_at is null for update;
  if not found then raise exception 'Loan not found' using errcode='P0002'; end if;
  if v_loan.status <> 'active' then raise exception 'Loan is not active' using errcode='22023'; end if;
  if v_loan.calculation_method not in ('reducing_balance','flat','emi') then
    raise exception 'Loan is not an EMI loan' using errcode='22023';
  end if;

  if p_account_id is not null then
    select a.id into v_account_id from public.accounts a
    where a.id=p_account_id and a.tenant_id=v_tenant and a.deleted_at is null;
    if v_account_id is null then raise exception 'Wallet not found' using errcode='P0002'; end if;
  end if;

  -- Determine target installment: explicit or earliest unpaid.
  if p_installment_no is not null then
    v_installment_no := p_installment_no;
  else
    select es.installment_no into v_installment_no
    from public.emi_schedules es
    where es.tenant_id=v_tenant and es.loan_id=v_loan.id and es.status in ('pending','overdue')
    order by es.due_date, es.installment_no
    limit 1;
    if v_installment_no is null then v_installment_no := 1; end if;
  end if;

  -- Ensure a schedule row exists for this installment.
  select es.due_date into v_due_date
  from public.emi_schedules es
  where es.tenant_id=v_tenant and es.loan_id=v_loan.id and es.installment_no=v_installment_no;
  if v_due_date is null then
    -- No persisted schedule; create a placeholder due date (start + n months).
    v_due_date := v_loan.start_date + (v_installment_no || ' months')::interval;
    insert into public.emi_schedules (tenant_id, loan_id, installment_no, due_date, status)
    values (v_tenant, v_loan.id, v_installment_no, v_due_date::date, 'pending')
    on conflict do nothing;
  end if;

  -- Penalty for late payment.
  if v_due_date is not null and p_payment_date > v_due_date then
    v_late_days := p_payment_date - v_due_date;
    v_penalty := round(v_loan.principal_amount * v_loan.penalty_rate * v_late_days / 365.0, 2);
  end if;

  -- Idempotency on client_id.
  if p_client_id is not null then
    select id into v_payment_id from public.payments
    where tenant_id=v_tenant and client_id=p_client_id;
    if v_payment_id is not null then
      return jsonb_build_object('payment_id', v_payment_id, 'idempotent', true);
    end if;
  end if;

  insert into public.payments (tenant_id, loan_id, payment_date, total_amount, interest_amount, principal_amount, payment_method, client_id, created_by)
  values (v_tenant, v_loan.id, p_payment_date, v_amount, 0, v_amount, v_method, p_client_id, auth.uid())
  returning id into v_payment_id;

  -- Wallet leg (optional).
  if v_account_id is not null then
    insert into public.transactions (tenant_id, account_id, loan_id, payment_id, kind, amount, txn_date, notes, excluded_from_cashflow)
    values (v_tenant, v_account_id, v_loan.id, v_payment_id,
            case when v_loan.direction='receivable' then 'income' else 'expense' end,
            v_amount, p_payment_date, 'EMI installment payment', true);
  end if;

  -- Mark installment paid.
  update public.emi_schedules
  set status = 'paid',
      paid_date = p_payment_date,
      paid_amount = v_amount,
      penalty_amount = v_penalty,
      payment_id = v_payment_id
  where tenant_id = v_tenant
    and loan_id = v_loan.id
    and installment_no = v_installment_no;

  insert into public.audit_logs (tenant_id, table_name, row_id, action, new_data, actor)
  values (v_tenant, 'emi_schedules', null, 'insert',
          jsonb_build_object('loan_id', v_loan.id, 'installment_no', v_installment_no,
                             'amount', v_amount, 'penalty', v_penalty, 'payment_id', v_payment_id),
          auth.uid());

  return jsonb_build_object(
    'payment_id', v_payment_id,
    'loan_id', v_loan.id,
    'installment_no', v_installment_no,
    'amount', v_amount,
    'penalty', v_penalty,
    'idempotent', false
  );
end;
$$;

revoke all on function public.record_emi_payment(uuid, numeric, date, text, uuid, uuid, int) from public, anon;
grant execute on function public.record_emi_payment(uuid, numeric, date, text, uuid, uuid, int) to authenticated;
