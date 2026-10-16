# 14 - API Reference — PostgREST Selects per Provider + RLS

Date: 2026-10-15. All client reads/writes go through Supabase PostgREST
(`supabase_flutter`). Every table has RLS enabled with policy
`tenant_id = public.current_tenant_id()` for `authenticated` only; `anon` denied.

## Conventions (all tables)
- `tenant_id uuid` default `00000000-0000-0000-0000-000000000001` (single shared
  project, future multi-tenant via JWT `app_metadata.tenant_id`).
- `deleted_at timestamptz` soft-delete; all providers filter
  `deleted_at is null`.
- `NUMERIC(15,2)` for money; `DATE` for AD storage only; BS is display-only.
- All selects include `.filter('deleted_at', 'is', null)`.
- All inserts include `tenant_id` (default handles it client-side).

## Providers and PostgREST selects

### loansProvider (`app/lib/src/features/loans/loans_provider.dart`)
```ts
select('id, principal_amount, rate, rate_type, day_base, start_date, direction, parties(name)')
  .eq('direction', '<receivable|payable>')
  .eq('status', 'active')
  .filter('deleted_at', 'is', null)
  .order('start_date')
```
Joins `parties(name)` for party display. Paid amounts fetched separately from
`payments` and merged client-side (`paidByLoan`).

### partiesProvider (`app/lib/src/features/parties/parties_provider.dart`)
```ts
select('id, name, phone, address')
  .filter('deleted_at', 'is', null)
  .order('name')
```

### paymentsProvider (`app/lib/src/features/payments/payments_provider.dart`)
```ts
select('id, loan_id, payment_date, total_amount, payment_method, loans(parties(name))')
  .filter('deleted_at', 'is', null)
  .order('payment_date', ascending: false)
  .limit(200)
```

### accountsProvider (`app/lib/src/features/accounts/accounts_provider.dart`)
```ts
select('id, name, type, opening_balance')
  .filter('deleted_at', 'is', null)
  .order('name')
```
Transactions fetched separately and merged client-side for `computedBalance`.

### transactionsProvider (`app/lib/src/features/transactions/transactions_provider.dart`)
```ts
select('id, kind, amount, txn_date, accounts(name), categories(name)')
  .filter('deleted_at', 'is', null)
  .order('txn_date', ascending: false)
  .limit(200)
```

### categoriesProvider (`app/lib/src/features/categories/categories_provider.dart`)
```ts
select('id, kind, name, icon')
  .filter('deleted_at', 'is', null)
  .order('kind')
  .order('name')
```

### budgetsProvider (`app/lib/src/features/budgets/budgets_provider.dart`)
```ts
select('id, category_id, fy_year, fy_month, limit_amount, categories(name)')
  .filter('deleted_at', 'is', null)
  .order('fy_year')
  .order('fy_month')
```
Transactions fetched separately for `spent` rollup by FY month.

### profileProvider (`app/lib/src/features/auth/profiles_provider.dart`)
```ts
select('id, display_name, email, phone, role, tenant_id, created_at')
  .eq('id', <auth.uid()>)
  .maybeSingle()
```

## RLS policies (all tables)
| Table | Policy | Roles | Cmd |
|-------|--------|-------|-----|
| parties | p_parties_all | authenticated | ALL |
| loans | tenant_all | authenticated | ALL |
| payments | p_txns_all | authenticated | ALL |
| emi_schedules | tenant_all | authenticated | ALL |
| notification_queue | tenant_all | authenticated | ALL |
| audit_logs | tenant_all | authenticated | ALL |
| accounts | p_accounts_all | authenticated | ALL |
| categories | p_categories_all | authenticated | ALL |
| transactions | p_txns_all | authenticated | ALL |
| budgets | p_budgets_all | authenticated | ALL |
| profiles | p_profiles_own | authenticated | ALL (own row only) |

All policies use `using (tenant_id = public.current_tenant_id())` with matching
`with check`, except `profiles` which uses `auth.uid() = id`.

## current_tenant_id() function
```sql
select coalesce(
  nullif((auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '')::uuid,
  '00000000-0000-0000-0000-000000000001'::uuid
);
```
Returns the shared default tenant unless a custom JWT claim is set (future
multi-tenant). Fixed `SET search_path=''` for security.

## Write paths
- Inserts: client `from('table').insert({...})` — RLS `with check` enforces
  tenant match.
- Updates/deletes: soft-delete via `deleted_at = now()`; hard deletes blocked by
  FK `on delete restrict` and no delete policy.
- Audit: app writes to `audit_logs` on insert/update (see `docs/10`).

## Verified
- `select tablename, rowsecurity from pg_tables` — 10/10 tables `true`.
- `pg_policies` — 10 authenticated ALL policies, 0 open (`true`) policies.
- Security advisors: 0 lints.
