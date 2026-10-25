# 14 - API Reference - PostgREST, RLS and RPCs

Date: 2026-10-25. All client access goes through Supabase PostgREST and Auth via
`supabase_flutter`. The client is untrusted: RLS and column grants decide what a
request may do, and money writes go through server RPCs.

## Conventions

- `tenant_id uuid not null` on every business table, defaulted from
  `public.current_tenant_id()`.
- `deleted_at timestamptz` soft delete; all reads filter `deleted_at is null`.
- `NUMERIC(15,2)` for money, `DATE` for AD dates. BS is display/input only.
- Reads use `select('*')` or explicit columns; new rolling columns must remain
  optional so the client survives the expand window.
- Clients never send `tenant_id`, `profiles.role`, `loans.status`,
  `transactions.payment_id`, payment void fields or audit history.

## Identity Helpers

```sql
-- Active membership; NULL when the user has no active seat.
public.current_tenant_id() returns uuid

-- 'owner' | 'manager' | 'viewer' for the active membership.
public.current_tenant_role() returns text

-- True for owner/manager in the given tenant.
public.is_tenant_writer(p_tenant uuid) returns boolean

-- Civil date in Asia/Kathmandu (Supabase Postgres runs in UTC).
public.nepal_today() returns date
```

All are `SECURITY DEFINER` with `set search_path = ''`, except `nepal_today()`
which is a pure stable SQL function and is not definer. There is no shared-tenant
fallback.

## Read Paths

| Provider | PostgREST select |
|---|---|
| `loansProvider` | `loans.select('*, parties(name)')`, filter direction/status/`deleted_at`, order `start_date`; separate `payments.select('loan_id,total_amount,interest_amount,principal_amount')` aggregate |
| `partiesProvider` | `parties.select('id,name,phone,address')`, filter `deleted_at`, order `name` |
| `paymentsProvider` | `payments.select('id,loan_id,payment_date,total_amount,interest_amount,principal_amount,payment_method,loans(parties(name))')`, filter `deleted_at`, order `payment_date desc`, limit 200 |
| `accountsProvider` | `accounts.select('id,name,type,opening_balance')`; `transactions.select('*')` for balances and transfer direction |
| `transactionsProvider` | `transactions.select('id,kind,amount,txn_date,accounts(name),categories(name)')`, filter `deleted_at`, order `txn_date desc`, limit 200 |
| `categoriesProvider` | `categories.select('id,kind,name,icon')`, filter `deleted_at`, order kind/name |
| `budgetsProvider` | `budgets.select('id,category_id,fy_year,fy_month,limit_amount,categories(name)')`, filter `deleted_at` |
| `partyStatementProvider` | loans by party; `payments.select('*').inFilter('loan_id', loanIds)`; caps interest and honours `accrual_end_date` |
| `profileProvider` | `profiles.select('id,display_name,email,phone,role,tenant_id,created_at').eq('id', auth.uid()).maybeSingle()` |

Reads are wrapped in the per-user Hive cache. On network failure the last cached
list is served; if no cache exists the error is surfaced rather than shown as an
empty ledger.

## Write Paths (ordinary data)

| Table | Client grants | Notes |
|---|---|---|
| `parties` | `SELECT`; `INSERT(name,phone,address,id_number)`; `UPDATE(name,phone,address,id_number,deleted_at)` | Archive is soft delete |
| `loans` | `SELECT`; `INSERT(party_id,principal_amount,rate,rate_type,calculation_method,day_base,start_date,due_date,tenure_days,loan_type,direction,tds_pct,remarks)`; `UPDATE(deleted_at)` | `status`, close/write-off/accrual columns are server-owned |
| `payments` | `SELECT` only after migration 2 | Use `record_payment` / `void_payment` |
| `emi_schedules` | `SELECT` only | Scheduler/server-generated; no client insert grant |
| `notification_queue` | `SELECT`; `UPDATE(status,sent_at,deleted_at)` | Scheduler inserts; client acknowledges |
| `audit_logs` | `SELECT`; `INSERT(table_name,row_id,action,old_data,new_data,actor)` | Append-only; `actor` must be `auth.uid()`; `tenant_id` defaults |
| `accounts` | `SELECT`; `INSERT(name,type,opening_balance)`; `UPDATE(name,type,opening_balance,deleted_at)` | Wallet balance computed client-side |
| `categories` | `SELECT`; `INSERT(kind,name,icon)`; `UPDATE(name,icon,deleted_at)` | |
| `transactions` | `SELECT`; `INSERT(account_id,category_id,loan_id,kind,amount,txn_date,notes,transfer_direction,excluded_from_cashflow)`; `UPDATE(deleted_at)` | Append-only; `payment_id` server-owned |
| `budgets` | `SELECT`; `INSERT(category_id,fy_year,fy_month,limit_amount)`; `UPDATE(category_id,fy_year,fy_month,limit_amount,deleted_at)` | Upsert needs update payload grants |
| `profiles` | `SELECT` own; `UPDATE(display_name,phone)` | Role/tenant are not writable |
| `tenants` | `SELECT`; `UPDATE(name)` | Owner RLS |
| `tenant_members` | `SELECT`; `INSERT(tenant_id,user_id,role,status)`; `UPDATE(role,status)` | Owner RLS; last-owner trigger |
| `tenant_invites` | `SELECT`,`DELETE`; `INSERT(tenant_id,email,role,expires_at)`; `UPDATE(email,role,expires_at,accepted_at,accepted_by)` | Owner RLS; prefer `create_tenant_invite` |

Table-level `INSERT`/`UPDATE`/`DELETE` are revoked. A request that names a column
outside the grant fails with `42501` even if it includes allowed columns.

## Money RPCs

### `record_payment`

```sql
public.record_payment(
  p_loan_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_payment_method text default 'cash',
  p_remarks text default null,
  p_account_id uuid default null,
  p_client_id uuid default null
) returns jsonb
```

Returns:

```json
{
  "payment_id": "uuid",
  "loan_id": "uuid",
  "total_amount": 1050.00,
  "interest_amount": 50.00,
  "principal_amount": 1000.00,
  "outstanding_after": 9000.00,
  "idempotent": false
}
```

Rules:

- Caller must be an active owner/manager in the loan's tenant.
- Amount must be positive and have at most 2 decimals.
- Method: `cash`, `bank_transfer`, `cheque`, `online`.
- Date must be today or earlier in `Asia/Kathmandu`, not before the loan start,
  and not before the latest live payment for that loan.
- Interest is accrued through the payment date and capped at the principal.
  Interest is paid first; the remainder reduces principal.
- The principal portion cannot exceed unpaid principal. Excess raises `22003`.
- With `p_account_id`, linked wallet legs are inserted in the same transaction.
  Interest is a cashflow leg; principal is `excluded_from_cashflow = true`.
- `p_client_id` is idempotent per tenant. The same request returns the existing
  row with `idempotent: true`; a different loan/amount/date or a voided payment
  raises `23505`.
- Writes an `audit_logs` row with the actor.

Common errors: `42501` role/tenant, `22023` validation, `22003` overpayment,
`23505` idempotency conflict, `P0002` loan/wallet not found.

### `void_payment`

```sql
public.void_payment(p_payment_id uuid, p_reason text default null) returns jsonb
```

- Caller must be an owner/manager.
- Only the newest live payment for the loan can be voided (`23514` otherwise).
- Soft-deletes the payment and its wallet legs, sets `voided_at`/`voided_by`/
  `void_reason`, writes audit.
- If the loan was closed, reopens it (`status = 'active'`, clears close fields).
- Re-voiding the same payment is idempotent (`already_voided: true`).

### `close_loan`

```sql
public.close_loan(
  p_loan_id uuid,
  p_write_off boolean default false,
  p_reason text default null
) returns jsonb
```

- Caller must be an owner/manager.
- Freezes accrual at `nepal_today()` (`accrual_end_date`, `closed_at`,
  `closed_by`) and sets `status = 'closed'`.
- If any principal or capped interest is unpaid, `p_write_off` must be true and
  `p_reason` non-empty. The unpaid amount is stored in `write_off_amount`.
- Writes audit with the write-off reason.
- A fully paid loan closes without a write-off.

## RLS Policy Map

Common predicates:

- Read: `tenant_id = current_tenant_id()`.
- Write: `tenant_id = current_tenant_id() and is_tenant_writer(tenant_id)`.

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| parties, loans, emi_schedules, accounts, categories, transactions, budgets | tenant | writer | writer | none |
| payments | tenant | none after migration 2 | none after migration 2 | none |
| notification_queue | tenant | policy exists, but no client grant | writer | none |
| audit_logs | tenant | tenant + `actor = auth.uid()` | none | none |
| profiles | own row | none | own row (name/phone grant) | none |
| tenants | current tenant | none | owner | none |
| tenant_members | current tenant | owner | owner | none |
| tenant_invites | current tenant + owner | owner | owner | owner |

`security_checks.sql` asserts there is no `ALL` policy and no `DELETE` policy
outside `tenant_invites`.

## Client Compatibility / Expand Window

The hardened client is deployed after the tenancy migration but before the RPC
migration. During that window:

- `record_payment` may not exist. The client detects `PGRST202`, `42883` or
  "could not find the function", then uses the legacy writer. Any other error is
  surfaced; validation errors are not retried.
- `void_payment` has the same fallback.
- `close_loan` does not fall back; it reports that the migration is missing.
- Reads use `select('*')` where a new column would otherwise break the query.
- Migration 1 keeps temporary direct payment grants; migration 2 revokes them.

Do not run an old client after migration 2. It will fail to insert or archive
payments, which is intentional.

## Verified Locally

- `security_checks.sql`: PASS (no privilege/RLS/wiring violations) on PGlite
  PostgreSQL 18.6 with stubbed Supabase Auth.
- `smoke_test.sql`: PASS (RPC payment, overpayment rejection, direct-write denial,
  write-off close, void reopen, rollback).
- 20/20 integration groups and 11/11 expand/contract groups.
- Real PostgREST/JWT behavior still requires a staging Supabase project.
