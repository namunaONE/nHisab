alter table public.transactions add column if not exists client_request_id uuid;
create unique index if not exists uq_transactions_tenant_client_request
  on public.transactions (tenant_id, client_request_id)
  where client_request_id is not null;
-- grant insert on the new column
grant insert (client_request_id) on public.transactions to authenticated;
