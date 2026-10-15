# 02 - Scope (Actual vs Planned)

## Done
- Party CRUD list + add dialog with id_number field, no edit/delete UI, no ID threshold warning yet.
- Loan CRUD add + list with 13 columns + totals, rate % UI to decimal, no edit/close/default flows.
- Payment add + list 200 recent with split preview (prev 0 bug), no edit.
- EMI function only, no schedule table UI.
- Dashboard: Ledger totals only, no net cards, overdue filter, FY filter.
- Alerts: table exists 0 rows, no cron, no Edge, no bell.
- Reports: Excel export/import + seed 21, no PDF, no party statement.
- Auth email/password + signup, no OTP, no reset, no roles, no profiles table.
- PWA build succeeds, Hive dep unused, online-only reads.

## Planned
SaaS billing, double-entry, IRD, bank auto import. Unchanged out.

## Budget Tracker v1 (Locked 2026-10-15, wallets-first)
Scope: loans (existing) + income/expenses + monthly budgets + dashboard/charts.
- Accounts/wallets first: cash/bank/mobile. Every money event hits exactly one account. Loan disbursal/repayment auto-links to transactions, never double-counted in net-worth.
- Transactions: income/expense/transfer with category + account + optional loan_id.
- Budgets: per-category monthly limits on Nepal FY Shrawan-Ashad, no rollover in v1.
- Dashboard first: net-worth card, cashflow bars, budget donut, overdue strip (fl_chart, now wired).
- Status: skeleton on main (migration SQL + stub pages + providers returning [] until applied). Full CRUD lands in branches.

## Constraints - Actual
AD DATE only, BS display. NUMERIC(15,2) DB, Dart Decimal-exact via core/money (Money.sum2/perDay/interest) since 2026-10-15, 10/10 tests. No hard delete rule enforced via deleted_at + RLS filter.
