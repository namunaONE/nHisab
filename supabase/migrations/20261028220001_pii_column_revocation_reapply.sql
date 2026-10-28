revoke select (phone, address, id_number, id_type) on public.parties from authenticated;

create or replace view public.parties_with_pii
as
select
  p.id,
  p.tenant_id,
  p.name,
  case when public.current_tenant_role() in ('owner','manager') then p.phone else null end as phone,
  case when public.current_tenant_role() in ('owner','manager') then p.address else null end as address,
  case when public.current_tenant_role() in ('owner','manager') then p.id_number else null end as id_number,
  case when public.current_tenant_role() in ('owner','manager') then p.id_type else null end as id_type,
  p.id_verified,
  p.risk_rating,
  p.created_at,
  p.deleted_at
from public.parties p
where p.tenant_id = public.current_tenant_id();

alter view public.parties_with_pii set (security_invoker = false);

grant select on public.parties_with_pii to authenticated;
revoke all on public.parties_with_pii from anon;
