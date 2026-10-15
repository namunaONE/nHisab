# 04 - Business Logic (Locked + Known Issues)

## Daily Accrual
```
DueDays = abs(TodayDate - StartDate in days), is_projected = Start > Today
PerDay = round2(Principal * RateAnnualDecimal / DayBase), DayBase 360 default else 365
Interest = round2(PerDay * DueDays)
Dues = max(0, Interest - InterestPaidToDate)
Total = round2(Principal - PrincipalPaidToDate + Dues)
```
Example Row1: 1500000*0.18/360=750.00, 750*118=88500, total 1588500 matches.
Footers sum rounded rows, not recalc from totals.

## Future-Day Rule (Divergence Locked)
Sheet Group B forces DueDays=1 for Oct16-21 vs Today Oct15. App uses actual abs 1,1,2,3,4,5,6.
Result payable interest 99300.30 vs sheet 27506.31, principal 85713900 matches. App math canonical.
UI must flag is_projected loans.

## Rate Types
annual as-is, monthly*12, daily*360 (or 365 per loan). Store annual decimal, keep rate_type input type.

## Zero Rate
Rate 0 allowed: PerDay 0, Interest 0, Total Principal. Cases Sharada 400000, Som 150000.

## Payment Allocation - Interest-First, Fixed 2026-10-15
Spec:
```
interestDueToD = round2(PerDay * days(Start->payDate)) 
remaining = max(0, interestDueToD - sumPrevInterestPaidForLoan)
interestNow = min(payment, remaining), principalNow = payment - interestNow
Reject payment > Total. Order payments by payment_date ASC.
```
Fixed 2026-10-15: PaymentForm prevInterestPaid() sums payments.interest_amount per loan filtered deleted_at is null for preview + save. Flat method stays hidden in LoanForm UI (daily_accrual + reducing_balance only).

## EMI
`EMI = P*r*(1+r)^n/((1+r)^n-1)`, r=annualPct/12/100. Zero rate EMI=P/n.
Cash Credit/Demand interest-only monthly, no amortization rows. Prepayment default reduce tenure keep EMI.
emi_schedules unique(loan_id, installment_no). No schedule UI yet, function only.

## Flat Method
Listed in schema check but no calculator or UI. Do not offer until formula locked: TotalInterest = P * flatRate * years, EMI = (P+TotalInterest)/n. Mark hidden.

## Status
active -> closed when TotalPaid >= Total then lock edits. Manual restructured/defaulted allowed, no auto transition yet. No soft-delete column yet despite no-hard-delete rule, deletes via API possible, must add deleted_at + RLS filter.

## Validation
principal>0, party required, start required, payment_method required every payment, rate warning >0.15 micro / >0.24 private warning only, TDS pct configurable report-only TDS=Interest*tds_pct, no auto deduction.
ID required warning when principal >500000 pending per docs/11.

## Budget Tracker v1 - Wallets-First (Locked 2026-10-15, skeleton)
```
accountBalance = opening_balance + sum(txns signed: income +, expense -) + transfers net
netWorth = sum(account balances) + receivable principal outstanding - payable principal outstanding
budgetSpent(category, FY-month) = sum(expense txns in month)
budgetRemaining = max(0, limit - spent), overspent flag when spent > limit
Nepal FY: FY start = July 16 approx Shrawan 1 (AD-mapped: month>=7 ? year : year-1); month index Shrawan=1..Ashad=12. v1 uses AD month buckets labelled BS via bs_date, exact BS-day mapping deferred.
No double-count: loan payment (interestFirst split) writes 0..2 linked transactions (interest leg + principal leg) with loan_id set; dashboard excludes loan principal from income/expense totals, counts only interest leg as expense/income.
Transfer: out of account A + into account B, same amount, same date, kind='transfer', excluded from income/expense sums.
```
Validation: amount>0, account required, category required for income/expense (optional for transfer), date required, loan_id optional link only.
