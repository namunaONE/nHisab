-- 20261015070054 fix_lints (applied remote, exported)
create index if not exists idx_notification_queue_loan on public.notification_queue(loan_id);
alter function public.handle_updated_at() set search_path = '';
alter function public.current_tenant_id() set search_path = '';
