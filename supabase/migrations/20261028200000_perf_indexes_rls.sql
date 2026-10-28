-- Indexes on unindexed foreign keys (performance advisor).
create index if not exists idx_audit_logs_tenant on public.audit_logs (tenant_id);
create index if not exists idx_budgets_cat_tenant on public.budgets (category_id, tenant_id);
create index if not exists idx_emi_loan_tenant on public.emi_schedules (loan_id, tenant_id);
create index if not exists idx_emi_tenant on public.emi_schedules (tenant_id);
create index if not exists idx_loans_closed_by on public.loans (closed_by);
create index if not exists idx_loans_party_tenant on public.loans (party_id, tenant_id);
create index if not exists idx_notif_loan_tenant on public.notification_queue (loan_id, tenant_id);
create index if not exists idx_notif_tenant on public.notification_queue (tenant_id);
create index if not exists idx_payments_created_by on public.payments (created_by);
create index if not exists idx_payments_loan_tenant on public.payments (loan_id, tenant_id);
create index if not exists idx_payments_voided_by on public.payments (voided_by);
create index if not exists idx_tenant_invites_accepted_by on public.tenant_invites (accepted_by);
create index if not exists idx_tenant_invites_invited_by on public.tenant_invites (invited_by);
create index if not exists idx_txns_account_tenant on public.transactions (account_id, tenant_id);
create index if not exists idx_txns_category_tenant on public.transactions (category_id, tenant_id);
create index if not exists idx_txns_loan_tenant on public.transactions (loan_id, tenant_id);

-- RLS initplan: wrap auth.uid()/current_setting in (select ...) for the 3 policies.
-- audit_logs insert policy
drop policy if exists p_audit_insert on public.audit_logs;
create policy p_audit_insert on public.audit_logs
  for insert to authenticated
  with check (tenant_id = public.current_tenant_id()
              and actor = (select auth.uid()));

-- profiles select/update own
drop policy if exists p_profiles_select_own on public.profiles;
create policy p_profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

drop policy if exists p_profiles_update_own on public.profiles
;
create policy p_profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
