create table if not exists public.notification_preferences (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  in_app boolean not null default true,
  email boolean not null default true,
  sms boolean not null default false,
  due_soon_days int not null default 7,
  quiet_start time,
  quiet_end time,
  updated_at timestamptz not null default now(),
  primary key (tenant_id, user_id)
);

alter table public.notification_preferences enable row level security;

drop policy if exists p_notif_prefs_select on public.notification_preferences;
create policy p_notif_prefs_select on public.notification_preferences
  for select to authenticated
  using (tenant_id = public.current_tenant_id() and user_id = auth.uid());

drop policy if exists p_notif_prefs_insert on public.notification_preferences;
create policy p_notif_prefs_insert on public.notification_preferences
  for insert to authenticated
  with check (tenant_id = public.current_tenant_id() and user_id = auth.uid());

drop policy if exists p_notif_prefs_update on public.notification_preferences;
create policy p_notif_prefs_update on public.notification_preferences
  for update to authenticated
  using (tenant_id = public.current_tenant_id() and user_id = auth.uid())
  with check (tenant_id = public.current_tenant_id() and user_id = auth.uid());

grant select, insert, update on public.notification_preferences to authenticated;
revoke all on public.notification_preferences from anon;
