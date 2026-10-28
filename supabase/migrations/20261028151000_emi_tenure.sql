alter table public.loans
  add column if not exists tenure_months int,
  add column if not exists emi_amount numeric(15,2);
