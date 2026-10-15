# nHisab - Loan Records & Interest Calculator for Nepal

## Goal
Replace the Excel ledger in `reference.png` with a full-stack Flutter Web PWA + Supabase app that:
- Tracks money lent (Rs. 57,00,000 + Rs. 42,60,000) and money borrowed from banks (Rs. 8,57,13,900)
- Replicates 13 columns exactly: Sn, Date, Party Name, Amount, Rate, Today Date, Due Days, Per Day, Interest, Amount Paid, Dues, Total Amount, Remarks
- Calculates daily interest as `PerDay = Principal * RateAnnual / 360`, `Interest = PerDay * DueDays`
- Supports reducing-balance EMI for bank loans: `EMI = P*r*(1+r)^n / ((1+r)^n - 1)`
- Shows dual dates AD + BS, Nepal FY Shrawan-Ashad
- Sends due/overdue alerts via Email/SMS/In-app
- Exports Excel/PDF byte-identical to current sheet

Rate convention locked: `0.18 = 18% annual decimal`. DayBase `360` default to match sheet (`1500000*0.18/360=750.00`), configurable to 365.

## How We Start
1. Docs first (this folder) - lock scope, logic, design
2. Phase 0: New Supabase project + Flutter web scaffold
3. Phase 1: Schema + Loan CRUD matching sheet
4. Phase 2: Payments + Dashboard
5. Phase 3: EMI + Export
6. Phase 4: Alerts + Hardening
7. Phase 5: PWA deploy to Firebase Hosting

## Brand
Primary seed `#002C6D` navy depth. Secondary `#4FD166` growth green. Material 3 fidelity, no dynamic color.

## Docs Index
- `docs/01-goal.md` - goal and success criteria
- `docs/02-scope.md` - in/out scope
- `docs/03-stack.md` - tech stack
- `docs/04-business-logic.md` - calculation rules
- `docs/05-design-system.md` - colors, type, components
- `docs/06-roadmap-execution.md` - phases and tasks
- `docs/07-getting-started.md` - dev setup commands
- `docs/08-supabase.md` - live project nhisab connection + verification
- `docs/09-phase2-complete.md` - auth + forms + 21 rows results
- `docs/10-system-design.md` - deep architecture, RLS, offline, money, alerts, deploy, ADRs
- `docs/11-registration.md` - app signup vs party fields, no confirm password, profiles + trigger spec
- `docs/12-gaps-fix-log.md` - audit P0-P2 with actual versions, counts, code bugs, fix checklist
- `docs/13-codebase-standards.md` - feature-first structure, clean files, avoid bugs workflow

## Status
Docs 01-13 synced 2026-10-15. Actual: Flutter 3.47.5, PG17, 21/21 rows, 0 payments. 01 marked PASS/PARTIAL/FAIL. 04 locks future-day + payment bug fixed. Code fixes done without Firebase: payment prev sum, soft-delete + archive UI, seed guard, migrations exported to supabase/. Build passes.
