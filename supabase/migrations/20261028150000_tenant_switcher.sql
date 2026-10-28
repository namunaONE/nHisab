alter table public.profiles
  add column if not exists active_tenant_id uuid references public.tenants(id) on delete set null;

create or replace function public.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.active_tenant_id
       from public.profiles p
       where p.id = auth.uid()
         and p.active_tenant_id is not null
         and exists (
           select 1 from public.tenant_members tm
           where tm.user_id = auth.uid()
             and tm.tenant_id = p.active_tenant_id
             and tm.status = 'active'
         )),
    (select tm.tenant_id
       from public.tenant_members tm
       where tm.user_id = auth.uid()
         and tm.status = 'active'
       order by tm.created_at
       limit 1)
  );
$$;

create or replace function public.set_active_tenant(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.tenant_members
    where user_id = auth.uid()
      and tenant_id = p_tenant_id
      and status = 'active'
  ) then
    raise exception 'Not a member of this organisation' using errcode = '42501';
  end if;
  update public.profiles
  set active_tenant_id = p_tenant_id, updated_at = now()
  where id = auth.uid();
  return jsonb_build_object('active_tenant_id', p_tenant_id);
end;
$$;

revoke all on function public.set_active_tenant(uuid) from public, anon;
grant execute on function public.set_active_tenant(uuid) to authenticated;
