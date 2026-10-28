create or replace function public.update_loan_terms(
  p_loan_id uuid, p_party_id uuid, p_principal_amount numeric, p_rate numeric,
  p_rate_type text, p_calculation_method text, p_day_base int, p_start_date date,
  p_due_date date default null, p_tenure_days int default null, p_loan_type text default null,
  p_direction text default 'receivable', p_tds_pct numeric default 0, p_remarks text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid; v_loan public.loans%rowtype; v_live_payments int; v_rate_type text; v_method text; v_direction text;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'No active organisation membership' using errcode='42501'; end if;
  if not public.is_tenant_writer(v_tenant) then raise exception 'Only an owner or manager can edit loans' using errcode='42501'; end if;
  select * into v_loan from public.loans where id=p_loan_id and tenant_id=v_tenant and deleted_at is null for update;
  if not found then raise exception 'Loan not found' using errcode='P0002'; end if;
  if v_loan.status <> 'active' then raise exception 'Only an active loan can be edited (status: %)', v_loan.status using errcode='22023'; end if;
  select count(*) into v_live_payments from public.payments where tenant_id=v_tenant and loan_id=v_loan.id and deleted_at is null;
  if v_live_payments > 0 then raise exception 'Loan has % live payment(s); void them before editing terms', v_live_payments using errcode='23514'; end if;
  if p_principal_amount is null or p_principal_amount <= 0 then raise exception 'Principal must be greater than zero' using errcode='22023'; end if;
  if p_rate is null or p_rate < 0 then raise exception 'Rate cannot be negative' using errcode='22023'; end if;
  v_rate_type := coalesce(nullif(trim(p_rate_type),''),'annual');
  if v_rate_type not in ('daily','monthly','annual') then raise exception 'Unsupported rate type: %', p_rate_type using errcode='22023'; end if;
  v_method := coalesce(nullif(trim(p_calculation_method),''),'daily_accrual');
  if v_method not in ('daily_accrual','reducing_balance','flat') then raise exception 'Unsupported calculation method: %', p_calculation_method using errcode='22023'; end if;
  if p_day_base not in (360,365) then raise exception 'Day base must be 360 or 365' using errcode='22023'; end if;
  v_direction := coalesce(nullif(trim(p_direction),''),'receivable');
  if v_direction not in ('receivable','payable') then raise exception 'Unsupported direction: %', p_direction using errcode='22023'; end if;
  if p_start_date is null then raise exception 'Start date is required' using errcode='22023'; end if;
  if p_party_id is null then raise exception 'Party is required' using errcode='22023'; end if;
  if not exists (select 1 from public.parties where id=p_party_id and tenant_id=v_tenant and deleted_at is null) then raise exception 'Party not found' using errcode='P0002'; end if;
  update public.loans set party_id=p_party_id, principal_amount=p_principal_amount, rate=p_rate, rate_type=v_rate_type, calculation_method=v_method, day_base=p_day_base, start_date=p_start_date, due_date=p_due_date, tenure_days=p_tenure_days, loan_type=p_loan_type, direction=v_direction, tds_pct=coalesce(p_tds_pct,0), remarks=nullif(trim(p_remarks),'') where id=v_loan.id and tenant_id=v_tenant;
  insert into public.audit_logs (tenant_id, table_name, row_id, action, old_data, new_data, actor) values (v_tenant, 'loans', v_loan.id, 'update', to_jsonb(v_loan)-'tenant_id', jsonb_build_object('party_id',p_party_id,'principal_amount',p_principal_amount,'rate',p_rate,'rate_type',v_rate_type,'calculation_method',v_method,'day_base',p_day_base,'start_date',p_start_date,'due_date',p_due_date,'tenure_days',p_tenure_days,'loan_type',p_loan_type,'direction',v_direction,'tds_pct',coalesce(p_tds_pct,0),'remarks',nullif(trim(p_remarks),'')), auth.uid());
  return jsonb_build_object('loan_id',v_loan.id,'updated',true);
end;
$$;
revoke all on function public.update_loan_terms(uuid, uuid, numeric, numeric, text, text, int, date, date, int, text, text, numeric, text) from public, anon;
grant execute on function public.update_loan_terms(uuid, uuid, numeric, numeric, text, text, int, date, date, int, text, text, numeric, text) to authenticated;
