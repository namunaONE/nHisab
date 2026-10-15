-- 20261015150000 fix_txns_loan_index (follow-up to budget_tracker_v1)
-- Covers transactions_loan_id_fkey flagged by performance advisor.
create index if not exists idx_txns_loan on public.transactions(loan_id);
