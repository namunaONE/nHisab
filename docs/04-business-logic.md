# 04 - Business Logic (Locked)

Date: 2026-10-25. This is the arithmetic and lifecycle contract. The server RPCs
mirror the Dart calculator; if one changes, both must change in the same release.

## 1. Daily Accrual

```
DueDays   = max(0, PayDate - StartDate in whole days)   // no abs()
PerDay    = round2(Principal * AnnualRateDecimal / DayBase)
Interest  = round2(PerDay * DueDays)
Capped    = min(Interest, Principal)                    // Civil Code s.481
Dues      = max(0, Capped - InterestPaidToDate)
Outstanding = max(0, (Principal - PrincipalPaidToDate) + Dues)
```

- `DayBase` is 360 by default (matches the source sheet) or 365 per loan.
- A loan that starts in the future accrues zero; the old `abs()` accrued interest
  backwards before disbursement.
- Footers sum already-rounded rows, not a recalculation from aggregate principal.
- Example Row 1: `1,500,000 * 0.18 / 360 = 750.00`; `750 * 118 = 88,500.00`;
  total `1,588,500.00`, matching the sheet.

## 2. Rate Types

- `annual`: stored decimal is the annual rate (`0.18` = 18%).
- `monthly`: annualise as `rate * 12`.
- `daily`: annualise as `rate * 360`.
- Zero rate is valid: per-day 0, interest 0, total is principal.
- UI accepts percent (`18`) and stores the decimal (`0.18`).

## 3. Future-Dated Loans

The source sheet's Group B forces `DueDays = 1` for a handful of rows dated after
the sheet's "Today". The app uses the real civil-date difference (1, 1, 2, 3, 4,
5, 6 for those rows) and shows them as projected. Principal matches; interest
differs because the app does not fabricate a day of accrual. The app math is
canonical.

## 4. Payment Allocation (Interest First)

Specification:

```
interestDue = cap(round2(PerDay * days(Start -> payDate)), Principal)
remainingInterest = max(0, interestDue - sum(previous live interest_amount))
interestNow = min(payment, remainingInterest)
requestedPrincipal = payment - interestNow
unpaidPrincipal = max(0, Principal - sum(previous live principal_amount))
principalNow = min(requestedPrincipal, unpaidPrincipal)
excess = payment - interestNow - principalNow
```

Rules:

- Reject `excess > 0` (overpayment) instead of silently discarding money.
- Reject a payment date before the loan start.
- Reject a payment date in the future in Nepal (`Asia/Kathmandu`).
- Reject a payment date earlier than the latest live payment for that loan.
  Same-day multiple payments are allowed. Corrections use void, not backdating.
- The server is authoritative. The client preview uses the same formula but only
  `record_payment` posts the split.
- A payment retry with the same `client_id` returns the original row. A retry
  after the payment was voided is rejected (`client_id belongs to a voided
  payment`).
- `void_payment` may remove only the newest live payment, so the remaining
  interest-first allocations stay reproducible. It soft-deletes the payment and
  its wallet legs and reopens a closed loan.

Offline: payments cannot be recorded offline. Guessing prior allocations caused
wrong splits; the client now fails closed and asks for a connection.

## 5. Loan Lifecycle

- `active` is the normal state.
- `close_loan` freezes accrual at `nepal_today()` and sets `closed_at`,
  `closed_by` and `accrual_end_date`.
- If any principal or capped interest is unpaid, closing requires
  `write_off = true` plus a non-empty reason. The unpaid amount is stored in
  `write_off_amount` and shown on the party statement.
- A fully paid loan closes with no write-off.
- Voiding the newest payment reopens a closed loan.
- There is no loan edit UI and no `restructured`/`defaulted` workflow. Rate or
  term corrections require voiding payments, operator SQL and an audit row.
- Clients cannot write `status`, `accrual_end_date`, `closed_*` or
  `write_off_*`; those columns are server-owned.

## 6. EMI

`EMI = P*r*(1+r)^n / ((1+r)^n - 1)`, where `r = annualPercent / 12 / 100`.
Zero rate: `EMI = P / n`.

- `emi_schedules` has a unique `(loan_id, installment_no)`.
- The schedule model/provider/page and PDF export exist.
- Payment allocation still uses daily accrual; EMI schedules are a read/report
  artifact, not an amortizing ledger.
- Cash Credit/Demand interest-only and prepayment/tenure rules are not
  implemented as automated workflows.

## 7. Calculation Methods

- `daily_accrual` is implemented end to end.
- `reducing_balance` and `flat` are accepted by the database check and appear in
  the loan form, but the calculator and payment split do not implement them.
  **Do not use them for live money** until the formulas and tests land.
- Flat formula (future, not implemented): total interest = `P * flatRate * years`,
  EMI = `(P + totalInterest) / n`.

## 8. Validation

- Principal > 0; party required; start date required.
- Rate >= 0; UI warns above 24% but permits it.
- Payment method required; allowed values `cash`, `bank_transfer`, `cheque`,
  `online`.
- Payment amount > 0, at most 2 decimals.
- TDS is report-only: `interest * tds_pct`, no withholding or deposit.
- ID number is optional today. A warning/requirement above a documented principal
  threshold (proposed Rs 500,000) is not implemented.

## 9. Wallet / Budget Logic

```
accountBalance = opening_balance
               + income
               - expense
               + transfer-in
               - transfer-out

netWorth = sum(account balances)
         + receivable principal outstanding
         - payable principal outstanding

budgetSpent(category, FY month) = sum(expense transactions in that month)
budgetRemaining = max(0, limit - spent)
```

- Every money event hits exactly one account.
- A loan payment with an account writes up to two linked transactions:
  interest (cashflow income/expense) and principal (`excluded_from_cashflow =
  true`). The dashboard counts only the interest leg.
- A transfer writes an out leg and an in leg with the same amount/date;
  `transfer_direction` makes each wallet's balance correct. Transfers are
  excluded from income/expense totals.
- Loan principal movements are never counted as income or expense.
- Budget FY bucketing is an AD approximation (July-June, Shrawan=1) labelled as
  the Nepali FY. Exact BS-day mapping is deferred.

## 10. Nepal Legal / Tax Notes

- Civil Code 2074 s.481: cumulative interest may not exceed the principal.
  Implemented in Dart and SQL.
- Civil Code 2074 s.484 is reported to set a 10-year limitation period. Not
  tracked by the app.
- A Tamasuk should identify parties, principal, rate, date and witnesses. The app
  stores terms but does not generate a legal instrument.
- VAT is 13%; thresholds are commonly cited as Rs 50 lakh (goods) and Rs 30 lakh
  (services). Interest treatment differs from fees; confirm with an accountant.
- TDS on interest is generally 15%; the app does not withhold or file.
- CBMS binding is commonly cited at Rs 20 crore turnover; not integrated.
- FY 2083/84 runs from 17 July 2026 to mid-July 2027.
- Privacy Act 2075 and NRB data-residency expectations apply to regulated
  lenders. The current Supabase region is Mumbai, not Nepal.
- None of the above is legal or tax advice. Tier C/D work is out of scope. See
  `docs/16-hardening-plan.md`.
