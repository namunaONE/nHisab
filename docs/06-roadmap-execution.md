# 06 - Roadmap Execution

## Phase 0 - Setup (3-4 days)
- [ ] Create Supabase project (new), get URL/anon key
- [ ] `flutter create --platforms web nhisab` + pubspec deps
- [ ] Theme from seed, go_router shell, Supabase init
- [ ] Supabase CLI init, first migration with tables

## Phase 1 - Core Ledger (2-3 weeks)
- [ ] Migration: parties, loans, payments, emi_schedules, notification_queue, audit_logs + RLS + indexes
- [ ] Models + Decimal calculator + 360/365 tests
- [ ] Loan list UI matching 13 columns, Today Date picker, dual AD/BS
- [ ] Acceptance: 21 rows entered, footers match sheet

## Phase 2 - Payments + Dashboard (2 weeks)
- [ ] Payment form with interest-first split preview
- [ ] Dashboard cards + overdue filter + FY filter
- [ ] Audit log UI

## Phase 3 - EMI + Export (2 weeks)
- [ ] EMI calculator + schedule table + flat vs reducing compare
- [ ] Excel export same column order, PDF receipt + loan agreement

## Phase 4 - Alerts + Hardening (2 weeks)
- [ ] dispatch-alerts Edge Function (Resend + SMS), pg_cron 08:00 NPT
- [ ] Bell tray Realtime, prefs page
- [ ] RLS tests, soft-delete enforcement

## Phase 5 - Deploy (1 week)
- [ ] `flutter build web --release`, Firebase Hosting, PWA manifest, HTTPS check
- [ ] Backup test, handover

## Task Tracking
Use GitHub issues per checkbox. Each phase ends with demo vs image totals.
