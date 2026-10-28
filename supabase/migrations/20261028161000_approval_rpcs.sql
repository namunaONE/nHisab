create or replace function public.request_approval(
  p_entity_type text,
  p_entity_id uuid default null,
  p_action text default 'create',
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_tenant uuid; v_id uuid;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'No active organisation membership' using errcode='42501'; end if;
  if not public.is_tenant_writer(v_tenant) then raise exception 'Only an owner or manager can request approval' using errcode='42501'; end if;
  if p_entity_type not in ('payment','payment_void','loan_close','loan_edit') then
    raise exception 'Unsupported entity type: %', p_entity_type using errcode='22023';
  end if;
  insert into public.approval_requests (tenant_id, entity_type, entity_id, action, payload, requested_by)
  values (v_tenant, p_entity_type, p_entity_id, p_action, coalesce(p_payload,'{}'::jsonb), auth.uid())
  returning id into v_id;
  insert into public.audit_logs (tenant_id, table_name, row_id, action, new_data, actor)
  values (v_tenant, 'approval_requests', v_id, 'insert',
          jsonb_build_object('entity_type', p_entity_type, 'action', p_action, 'entity_id', p_entity_id),
          auth.uid());
  return jsonb_build_object('approval_id', v_id, 'status', 'pending');
end;
$$;

create or replace function public.decide_approval(
  p_approval_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_req public.approval_requests%rowtype;
  v_result jsonb := '{}'::jsonb;
  v_note text := nullif(trim(p_note), '');
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'No active organisation membership' using errcode='42501'; end if;
  if not public.is_tenant_writer(v_tenant) then raise exception 'Only an owner or manager can decide approvals' using errcode='42501'; end if;

  select * into v_req
  from public.approval_requests
  where id = p_approval_id and tenant_id = v_tenant
  for update;
  if not found then raise exception 'Approval request not found' using errcode='P0002'; end if;
  if v_req.status <> 'pending' then
    raise exception 'Approval request already decided (%)', v_req.status using errcode='22023';
  end if;
  if v_req.requested_by = auth.uid() then
    raise exception 'You cannot decide your own request' using errcode='42501';
  end if;

  if not coalesce(p_approve, false) then
    update public.approval_requests
    set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = v_note
    where id = v_req.id;
    insert into public.audit_logs (tenant_id, table_name, row_id, action, new_data, actor)
    values (v_tenant, 'approval_requests', v_req.id, 'reject',
            jsonb_build_object('entity_type', v_req.entity_type, 'note', v_note), auth.uid());
    return jsonb_build_object('approval_id', v_req.id, 'status', 'rejected');
  end if;

  -- Approved: execute the underlying action based on entity type.
  if v_req.entity_type = 'payment' then
    v_result := public.record_payment(
      (v_req.payload->>'loan_id')::uuid,
      (v_req.payload->>'amount')::numeric,
      (v_req.payload->>'payment_date')::date,
      coalesce(v_req.payload->>'payment_method', 'cash'),
      v_req.payload->>'remarks',
      nullif(v_req.payload->>'account_id','')::uuid,
      nullif(v_req.payload->>'client_id','')::uuid
    );
  elsif v_req.entity_type = 'payment_void' then
    v_result := public.void_payment(
      (v_req.payload->>'payment_id')::uuid,
      coalesce(v_req.payload->>'reason', v_note)
    );
  elsif v_req.entity_type = 'loan_close' then
    v_result := public.close_loan(
      (v_req.payload->>'loan_id')::uuid,
      coalesce((v_req.payload->>'write_off')::boolean, false),
      coalesce(v_req.payload->>'reason', v_note)
    );
  else
    raise exception 'Execution not implemented for entity type: %', v_req.entity_type using errcode='22023';
  end if;

  update public.approval_requests
  set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = v_note
  where id = v_req.id;

  insert into public.audit_logs (tenant_id, table_name, row_id, action, new_data, actor)
  values (v_tenant, 'approval_requests', v_req.id, 'approve',
          jsonb_build_object('entity_type', v_req.entity_type, 'result', v_result, 'note', v_note),
          auth.uid());

  return jsonb_build_object('approval_id', v_req.id, 'status', 'approved', 'result', v_result);
end;
$$;

revoke all on function public.request_approval(text, uuid, text, jsonb) from public, anon;
grant execute on function public.request_approval(text, uuid, text, jsonb) to authenticated;
revoke all on function public.decide_approval(uuid, boolean, text) from public, anon;
grant execute on function public.decide_approval(uuid, boolean, text) to authenticated;
