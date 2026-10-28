-- Consent records (Privacy Act 2075).
create table if not exists public.consent_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  subject_type text not null check (subject_type in ('party','user')),
  subject_id uuid not null,
  purpose text not null,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id) on delete set null,
  withdrawn_at timestamptz,
  evidence_ref text
);
alter table public.consent_records enable row level security;
drop policy if exists p_consent_select on public.consent_records;
create policy p_consent_select on public.consent_records for select to authenticated
  using (tenant_id = public.current_tenant_id());
drop policy if exists p_consent_write on public.consent_records;
create policy p_consent_write on public.consent_records for all to authenticated
  using (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id))
  with check (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id));
grant select, insert, update, delete on public.consent_records to authenticated;
revoke all on public.consent_records from anon;

-- Retention schedule (per tenant, per table).
create table if not exists public.retention_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  table_name text not null,
  retention_days int not null check (retention_days > 0),
  basis text,
  unique (tenant_id, table_name)
);
alter table public.retention_policies enable row level security;
drop policy if exists p_retention_select on public.retention_policies;
create policy p_retention_select on public.retention_policies for select to authenticated
  using (tenant_id = public.current_tenant_id());
drop policy if exists p_retention_write on public.retention_policies;
create policy p_retention_write on public.retention_policies for all to authenticated
  using (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id))
  with check (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id));
grant select, insert, update, delete on public.retention_policies to authenticated;
revoke all on public.retention_policies from anon;

-- Incident / breach log (Privacy Act 2075 breach handling).
create table if not exists public.incident_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  title text not null,
  description text,
  severity text not null default 'low' check (severity in ('low','medium','high','critical')),
  detected_at timestamptz not null default now(),
  reported_at timestamptz,
  resolved_at timestamptz,
  reported_by uuid references auth.users(id) on delete set null,
  affected_subjects int,
  created_at timestamptz not null default now()
);
alter table public.incident_log enable row level security;
drop policy if exists p_incident_select on public.incident_log;
create policy p_incident_select on public.incident_log for select to authenticated
  using (tenant_id = public.current_tenant_id());
drop policy if exists p_incident_write on public.incident_log;
create policy p_incident_write on public.incident_log for all to authenticated
  using (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id))
  with check (tenant_id = public.current_tenant_id() and public.is_tenant_writer(tenant_id));
grant select, insert, update, delete on public.incident_log to authenticated;
revoke all on public.incident_log from anon;

-- Suspicious transaction report (STR) view for goAML-style export.
create or replace view public.str_candidates
with (security_invoker = true) as
select
  p.tenant_id,
  p.id as payment_id,
  p.loan_id,
  p.payment_date,
  p.total_amount,
  l.party_id,
  pt.name as party_name,
  pt.id_number,
  case when p.total_amount >= 1000000 then 'high_value' else 'review' end as reason
from public.payments p
join public.loans l on l.tenant_id = p.tenant_id and l.id = p.loan_id
join public.parties pt on pt.tenant_id = p.tenant_id and pt.id = l.party_id
where p.deleted_at is null
  and (p.total_amount >= 1000000 or pt.id_verified = false);

grant select on public.str_candidates to authenticated;
revoke all on public.str_candidates from anon;
