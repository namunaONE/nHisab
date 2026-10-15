# 01 - Goal (Status 2026-10-15)

## Problem
Excel 3 groups: A lent 7 rows 5700000 / 410233.33 / 6110233.33, B borrowed 7 rows 85713900 / 27506.31 / 85741406.31, C lent 7 rows 4260000 / 258420 / 4518420. Manual Today, no audit, no alerts, no split.

## Goal Statement
Single-tenant nHisab web app: create party/loan/payment, auto Interest/Dues/Total for any Today, export sheet format.

## Success Criteria
1. 21 rows footers match to paisa: PASS receivable 9960000/668653.33 exact, PASS payable principal 85713900, PARTIAL payable interest 99300 vs 27506 sheet manual 1-day, 1 paisa per_day rounding diff documented.
2. Change Today recalc instantly: PASS Ledger.
3. Partial payment interest-first: PARTIAL preview uses prev 0 bug, backend sum pending.
4. EMI matches bank: FAIL UI, function only with 1 sanity test.
5. Dual AD+BS every field: PARTIAL Today + helper only, pickers not wired.
6. Excel export identical: PARTIAL columns match, byte compare not done.
7. RLS + soft-delete + audit: PARTIAL RLS on 6/6, no soft-delete column, audit table 0 rows app does not write.

## Non-Goals MVP
Multi-tenant billing, bank auto-sync, native mobile, VAT, e-sign. Unchanged.
