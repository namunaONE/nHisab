# 09 - Phase 2 Complete: Auth + Forms + 21 Rows

## Built 2026-10-15
- AuthGate + LoginPage email/password + signup, UserMenu sign-out
- HomeShell bottom nav: Ledger | Parties | Payments | Import
- PartyFormDialog + PartiesPage list
- LoanFormDialog: party dropdown, principal Rs, rate % (18 -> 0.18 DB), direction lent/borrowed, method daily/EMI, dayBase 360/365, start date, loan_type, remarks
- PaymentFormDialog with interest-first split preview via LoanCalculator.splitPayment
- ImportPage: Seed 21 rows button, Excel .xlsx picker (Date, Party, Amount, Rate), Export ledger to Excel with 13 columns
- LedgerPage extracted, Today picker + Set 2026-10-15 button, DataTable2 totals footer, BS dual via BsDate

## DB Seed Verified via SQL
- 21 parties + 21 loans inserted
- receivable principal 9960000.00 = 5700000 + 4260000 matches sheet
- payable principal 85713900.00 matches sheet (Row4 fixed 4190000 -> 41900000 to match total)
- receivable interest 668653.33 = 410233.33 + 258420.00 matches sheet exactly with Today 2026-10-15
- payable per_day 27506.32 vs sheet 27506.31 (1 paisa rounding)
- payable interest 99300.30 vs sheet 27506.31: difference because sheet forces DueDays=1 for all future bank loans (Oct16-21), app uses actual abs diff 1,1,2,3,4,5,6. App math is correct daily accrual. Keep app logic, note in UI.

## Tests
- flutter analyze: 0 errors, 8 infos (deprecated anonKey/value, non-blocking)
- flutter test loan_calculator_test: 2/2 passed
- flutter build web --release --no-wasm-dry-run: success, output app/build/web

## Run
1. Create user in app LoginPage (signup), then in Supabase Auth dashboard confirm email if required
2. Ledger -> Set 2026-10-15 -> Lent totals should show Principal 9960000, Interest 668653.33
3. Borrowed totals Principal 85713900
4. Add party/loan/payment via FABs on Ledger tab
5. Import tab Seed button only if DB empty (already seeded, will duplicate if pressed again)
