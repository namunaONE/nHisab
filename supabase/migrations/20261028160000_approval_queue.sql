create table if not exists public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  entity_type text not null check (entity_type in ('payment','payment_void','loan_close','loan_edit')),
  entity_id uuid,
  action text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_by uuid references auth.users(id) on delete set null,
  requested_at timestamptz not null default now(),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_approval_requests_tenant_status
  on public.approval_requests (tenant_id, status);

alter table public.approval_requests enable row level security;

drop policy if exists p_approval_requests_select on public.approval_requests;
create policy p_approval_requests_select on public.approval_requests
  for select to authenticated
  using (tenant_id = public.current_tenant_id());

drop policy if exists p_approval_requests_insert on public.approval_requests;
create policy p_approval_requests_insert on public.approval_requests
  for insert to authenticated
  with check (tenant_id = public.current_tenant_id()
              and public.is_tenant_writer(tenant_id)
              and requested_by = auth.uid());

-- Only owners/managers can decide; requester cannot decide their own.
drop policy if exists p_approval_requests_update on public.approval_requests;
create policy p_approval_requests_update on public.approval_requests
  for update to authenticated
  using (tenant_id = public.current_tenant_id()
         and public.is_tenant_writer(tenant_id)
         and requested_by is distinct from auth.uid())
  with check (tenant_id = public.current_tenant_id()
              and public.is_tenant_writer(tenant_id));

grant select, insert, update on public.approval_requests to authenticated;
revoke all on public.approval_requests from anon;
