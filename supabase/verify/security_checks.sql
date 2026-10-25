-- 20261025 security checks
--
-- Read-only catalog verification for the tenancy + payment-RPC migrations.
-- Run after 20261025120000 and 20261025121000 in the Supabase SQL editor
-- (as postgres). The final result set is PASS, or one FAIL row per violation.
--
-- This script checks the deployed schema and privileges. It does not exercise
-- RLS as a real user; use supabase/verify/smoke_test.sql for that (staging
-- only, it rolls back every write).

begin;

create temp table _security_failures (
  check_name text not null,
  detail text not null
) on commit drop;

-- ---------------------------------------------------------------------------
-- 1. Tables and RLS
-- ---------------------------------------------------------------------------

insert into _security_failures
select 'missing_table', t.name
from (values
  ('accounts'), ('audit_logs'), ('budgets'), ('categories'),
  ('emi_schedules'), ('loans'), ('notification_queue'), ('parties'),
  ('payments'), ('profiles'), ('tenant_invites'), ('tenant_members'),
  ('tenants'), ('transactions')
) t(name)
where not exists (
  select 1
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = t.name
    and c.relkind = 'r'
);

insert into _security_failures
select 'rls_disabled', c.relname
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and not c.relrowsecurity;

-- ---------------------------------------------------------------------------
-- 2. Anonymous role has no surface
-- ---------------------------------------------------------------------------

insert into _security_failures
select 'anon_table_grant', g.table_name || ':' || g.privilege_type
from information_schema.role_table_grants g
where g.table_schema = 'public'
  and g.grantee = 'anon';

insert into _security_failures
select 'anon_column_grant', g.table_name || '.' || g.column_name || ':' || g.privilege_type
from information_schema.column_privileges g
where g.table_schema = 'public'
  and g.grantee = 'anon'
  and g.privilege_type in ('INSERT', 'UPDATE');

insert into _security_failures
select 'anon_function_execute', p.proname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prorettype <> 'trigger'::regtype
  and has_function_privilege('anon', p.oid, 'EXECUTE');

insert into _security_failures
select 'anon_sequence_usage', s.sequence_name
from information_schema.sequences s
where s.sequence_schema = 'public'
  and has_sequence_privilege(
    'anon',
    quote_ident(s.sequence_schema) || '.' || quote_ident(s.sequence_name),
    'USAGE'
  );

-- ---------------------------------------------------------------------------
-- 3. Authenticated table-level grants are read-only, except invite deletion
-- ---------------------------------------------------------------------------

insert into _security_failures
select 'authenticated_table_privilege',
       g.table_name || ':' || g.privilege_type
from information_schema.role_table_grants g
where g.table_schema = 'public'
  and g.grantee = 'authenticated'
  and (
    g.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')
    or g.privilege_type in ('INSERT', 'UPDATE')
    or (g.privilege_type = 'DELETE' and g.table_name <> 'tenant_invites')
  );

insert into _security_failures
select 'authenticated_missing_select', t.name
from (values
  ('accounts'), ('audit_logs'), ('budgets'), ('categories'),
  ('emi_schedules'), ('loans'), ('notification_queue'), ('parties'),
  ('payments'), ('profiles'), ('tenant_invites'), ('tenant_members'),
  ('tenants'), ('transactions')
) t(name)
where not has_table_privilege('authenticated', 'public.' || t.name, 'SELECT');

-- ---------------------------------------------------------------------------
-- 4. Payments: SELECT only, no write policy
-- ---------------------------------------------------------------------------

insert into _security_failures
select 'payments_table_write', g.privilege_type
from information_schema.role_table_grants g
where g.table_schema = 'public'
  and g.table_name = 'payments'
  and g.grantee = 'authenticated'
  and g.privilege_type <> 'SELECT';

insert into _security_failures
select 'payments_column_write', g.column_name || ':' || g.privilege_type
from information_schema.column_privileges g
where g.table_schema = 'public'
  and g.table_name = 'payments'
  and g.grantee = 'authenticated'
  and g.privilege_type in ('INSERT', 'UPDATE');

insert into _security_failures
select 'payments_write_policy', policyname || ':' || cmd
from pg_policies
where schemaname = 'public'
  and tablename = 'payments'
  and cmd <> 'SELECT';

insert into _security_failures
select 'payments_live_insert_allowed', 'authenticated'
where has_table_privilege('authenticated', 'public.payments', 'INSERT')
   or has_column_privilege('authenticated', 'public.payments', 'total_amount', 'INSERT');

-- ---------------------------------------------------------------------------
-- 5. Loans: lifecycle columns stay server-owned
-- ---------------------------------------------------------------------------

insert into _security_failures
select 'loans_forbidden_column', c.col || ':' || p.priv
from (values
  ('status'), ('accrual_end_date'), ('closed_at'), ('closed_by'),
  ('write_off_amount'), ('write_off_reason'), ('tenant_id')
) c(col)
cross join (values ('INSERT'), ('UPDATE')) p(priv)
where has_column_privilege('authenticated', 'public.loans', c.col, p.priv);

insert into _security_failures
select 'loans_missing_archive', 'deleted_at'
where not has_column_privilege('authenticated', 'public.loans', 'deleted_at', 'UPDATE');

insert into _security_failures
select 'loans_missing_client_insert', c.col
from (values
  ('party_id'), ('principal_amount'), ('rate'), ('rate_type'),
  ('calculation_method'), ('day_base'), ('start_date'), ('direction')
) c(col)
where not has_column_privilege('authenticated', 'public.loans', c.col, 'INSERT');

-- ---------------------------------------------------------------------------
-- 6. Transactions: append-only, payment_id server-owned
-- ---------------------------------------------------------------------------

insert into _security_failures
select 'txns_forbidden_insert', c.col
from (values
  ('payment_id'), ('tenant_id'), ('id'), ('created_at'), ('deleted_at')
) c(col)
where has_column_privilege('authenticated', 'public.transactions', c.col, 'INSERT');

insert into _security_failures
select 'txns_forbidden_update', c.col
from (values
  ('amount'), ('payment_id'), ('account_id'), ('tenant_id'), ('kind'),
  ('txn_date'), ('notes'), ('category_id'), ('loan_id'),
  ('transfer_direction'), ('excluded_from_cashflow'), ('id'), ('created_at')
) c(col)
where has_column_privilege('authenticated', 'public.transactions', c.col, 'UPDATE');

insert into _security_failures
select 'txns_missing_archive', 'deleted_at'
where not has_column_privilege('authenticated', 'public.transactions', 'deleted_at', 'UPDATE');

insert into _security_failures
select 'txns_missing_client_insert', c.col
from (values
  ('account_id'), ('kind'), ('amount'), ('txn_date'),
  ('transfer_direction'), ('excluded_from_cashflow')
) c(col)
where not has_column_privilege('authenticated', 'public.transactions', c.col, 'INSERT');

-- ---------------------------------------------------------------------------
-- 7. Audit, profiles and tenant administration
-- ---------------------------------------------------------------------------

insert into _security_failures
select 'audit_forbidden_insert', c.col
from (values ('tenant_id'), ('id'), ('created_at')) c(col)
where has_column_privilege('authenticated', 'public.audit_logs', c.col, 'INSERT');

insert into _security_failures
select 'audit_forbidden_update', c.col
from (values ('action'), ('new_data'), ('old_data'), ('actor')) c(col)
where has_column_privilege('authenticated', 'public.audit_logs', c.col, 'UPDATE');

insert into _security_failures
select 'profile_forbidden_update', c.col
from (values ('role'), ('tenant_id'), ('email')) c(col)
where has_column_privilege('authenticated', 'public.profiles', c.col, 'UPDATE');

insert into _security_failures
select 'profile_missing_update', c.col
from (values ('display_name'), ('phone')) c(col)
where not has_column_privilege('authenticated', 'public.profiles', c.col, 'UPDATE');

insert into _security_failures
select 'tenant_members_forbidden_update', c.col
from (values ('tenant_id'), ('user_id')) c(col)
where has_column_privilege('authenticated', 'public.tenant_members', c.col, 'UPDATE');

insert into _security_failures
select 'tenant_invites_forbidden_grant', g.privilege_type
from information_schema.role_table_grants g
where g.table_schema = 'public'
  and g.table_name = 'tenant_invites'
  and g.grantee = 'authenticated'
  and g.privilege_type not in ('SELECT', 'DELETE');

-- ---------------------------------------------------------------------------
-- 8. Policies: no ALL, no DELETE except invites
-- ---------------------------------------------------------------------------

insert into _security_failures
select 'policy_all', tablename || ':' || policyname
from pg_policies
where schemaname = 'public'
  and cmd = 'ALL';

insert into _security_failures
select 'unexpected_delete_policy', tablename || ':' || policyname
from pg_policies
where schemaname = 'public'
  and cmd = 'DELETE'
  and tablename <> 'tenant_invites';

insert into _security_failures
select 'missing_select_policy', t.name
from (values
  ('accounts'), ('audit_logs'), ('budgets'), ('categories'),
  ('emi_schedules'), ('loans'), ('notification_queue'), ('parties'),
  ('payments'), ('profiles'), ('tenant_invites'), ('tenant_members'),
  ('tenants'), ('transactions')
) t(name)
where not exists (
  select 1
  from pg_policies p
  where p.schemaname = 'public'
    and p.tablename = t.name
    and p.cmd = 'SELECT'
    and 'authenticated' = any (p.roles)
);

-- ---------------------------------------------------------------------------
-- 9. Definer functions, trigger wiring, columns, indexes
-- ---------------------------------------------------------------------------

insert into _security_failures
select 'missing_function', f.name
from (values
  ('current_tenant_id'), ('current_tenant_role'), ('is_tenant_writer'),
  ('nepal_today'), ('record_payment'), ('void_payment'), ('close_loan'),
  ('create_tenant_invite'), ('handle_new_user'), ('prevent_audit_mutation'),
  ('protect_last_tenant_owner'), ('sync_profile_role')
) f(name)
where not exists (
  select 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = f.name
);

insert into _security_failures
select 'function_not_definer', p.proname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'current_tenant_id', 'current_tenant_role', 'is_tenant_writer',
    'record_payment', 'void_payment', 'close_loan', 'create_tenant_invite',
    'handle_new_user', 'prevent_audit_mutation',
    'protect_last_tenant_owner', 'sync_profile_role'
  )
  and not p.prosecdef;

insert into _security_failures
select 'function_search_path', p.proname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'current_tenant_id', 'current_tenant_role', 'is_tenant_writer',
    'nepal_today', 'record_payment', 'void_payment', 'close_loan',
    'create_tenant_invite', 'handle_new_user', 'prevent_audit_mutation',
    'protect_last_tenant_owner', 'sync_profile_role'
  )
  and not (p.proconfig @> array['search_path=""']);

insert into _security_failures
select 'shared_tenant_fallback', 'current_tenant_id'
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'current_tenant_id'
  and pg_get_functiondef(p.oid)
      like '%00000000-0000-0000-0000-000000000001%';

insert into _security_failures
select 'function_arity', p.proname || ':' || p.pronargs
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (
    (p.proname = 'record_payment' and (p.pronargs <> 7 or p.prorettype <> 'jsonb'::regtype))
    or (p.proname = 'void_payment' and (p.pronargs <> 2 or p.prorettype <> 'jsonb'::regtype))
    or (p.proname = 'close_loan' and (p.pronargs <> 3 or p.prorettype <> 'jsonb'::regtype))
  );

insert into _security_failures
select 'rpc_privilege', p.proname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('record_payment', 'void_payment', 'close_loan')
  and (
    not has_function_privilege('authenticated', p.oid, 'EXECUTE')
    or has_function_privilege('anon', p.oid, 'EXECUTE')
  );

insert into _security_failures
select 'missing_trigger', t.name
from (values
  ('trg_audit_no_update', 'public.audit_logs'),
  ('trg_tenant_members_protect_owner', 'public.tenant_members'),
  ('trg_tenant_members_sync_profile', 'public.tenant_members'),
  ('trg_handle_new_user', 'auth.users')
) t(name, tbl)
where not exists (
  select 1
  from pg_trigger tg
  where tg.tgname = t.name
    and tg.tgrelid = t.tbl::regclass
    and not tg.tgisinternal
);

insert into _security_failures
select 'missing_index', i.name
from (values
  ('uq_payments_tenant_client'), ('idx_txns_payment'),
  ('uq_tenant_members_one_active')
) i(name)
where not exists (
  select 1 from pg_indexes
  where schemaname = 'public' and indexname = i.name
);

insert into _security_failures
select 'missing_foreign_key', c.name
from (values
  ('loans_party_tenant_fk'), ('payments_loan_tenant_fk'),
  ('transactions_payment_tenant_fk')
) c(name)
where not exists (
  select 1 from pg_constraint
  where connamespace = 'public'::regnamespace
    and conname = c.name
    and contype = 'f'
);

insert into _security_failures
select 'missing_column', c.tbl || '.' || c.col
from (values
  ('loans', 'accrual_end_date'), ('loans', 'write_off_amount'),
  ('loans', 'write_off_reason'), ('loans', 'closed_at'),
  ('payments', 'client_id'), ('payments', 'voided_at'),
  ('payments', 'voided_by'), ('transactions', 'payment_id'),
  ('transactions', 'transfer_direction'),
  ('transactions', 'excluded_from_cashflow')
) c(tbl, col)
where not exists (
  select 1 from information_schema.columns
  where table_schema = 'public'
    and table_name = c.tbl
    and column_name = c.col
);

-- ---------------------------------------------------------------------------
-- 10. Runtime sanity
-- ---------------------------------------------------------------------------

insert into _security_failures
select 'nepal_today_mismatch', public.nepal_today()::text
where public.nepal_today() <> (now() at time zone 'Asia/Kathmandu')::date;

-- ---------------------------------------------------------------------------
-- Result
-- ---------------------------------------------------------------------------

select status, check_name, detail
from (
  select 'FAIL' as status, check_name, detail
  from _security_failures
  union all
  select 'PASS', 'all_checks', 'No privilege, RLS or wiring violations found'
  where not exists (select 1 from _security_failures)
) r
order by status desc, check_name, detail;

rollback;
