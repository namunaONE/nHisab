create or replace view public.parties_safe
with (security_invoker = true) as
select
  id,
  tenant_id,
  name,
  case when public.current_tenant_role() in ('owner','manager')
       then phone else null end as phone,
  case when public.current_tenant_role() in ('owner','manager')
       then address else null end as address,
  case when public.current_tenant_role() in ('owner','manager')
       then id_number else null end as id_number,
  created_at,
  deleted_at
from public.parties;

grant select on public.parties_safe to authenticated;
revoke all on public.parties_safe from anon;
