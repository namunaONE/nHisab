-- 20261015073715 add_soft_delete (applied remote, exported)
-- Enforces no-hard-delete rule from docs/02. App sets deleted_at, queries filter deleted_at is null.
alter table public.parties add column if not exists deleted_at timestamptz;
alter table public.loans add column if not exists deleted_at timestamptz;
alter table public.payments add column if not exists deleted_at timestamptz;
alter table public.emi_schedules add column if not exists deleted_at timestamptz;
alter table public.notification_queue add column if not exists deleted_at timestamptz;
alter table public.audit_logs add column if not exists deleted_at timestamptz;
create index if not exists idx_parties_deleted on public.parties(deleted_at) where deleted_at is null;
create index if not exists idx_loans_deleted on public.loans(deleted_at) where deleted_at is null;
create index if not exists idx_payments_deleted on public.payments(deleted_at) where deleted_at is null;
