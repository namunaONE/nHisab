# 10 - System Design - nHisab Full Stack

Date: 2026-10-15. Status: Implemented Phase 0-2, design locks Phase 3-5.
Project: Supabase `nhisab` `qcbxurqxmnkzgsfpaesz` ap-south-1. App: `app/` Flutter 3.47.5 Web PWA.

## 1. Goals and Constraints

Goals:
- Replicate 13-column sheet exactly for Today 2026-10-15. Receivable 9960000 / 668653.33, payable 85713900 verified.
- Daily accrual `PerDay = P * RateAnnual / DayBase`, `DayBase 360` default to match `1500000*0.18/360=750`.
- Reducing-balance EMI for bank loans, interest-first payment split, dual AD/BS, Excel in/out, due alerts.
- Single-tenant now, `tenant_id` on all rows for future multi-tenant without rewrite.

Constraints:
- Postgres is source of truth. AD DATE storage only, BS is display.
- Money NUMERIC(15,2) in DB, never float/money type. Round PerDay to 2dp first, then Interest, then sum footers. Avoids 0.1+0.2 drift and locale issues with `money` type.
- RLS on all tables. anon has no read until authenticated. CVE-2025-48757 lesson: 170/1645 AI apps leaked from missing RLS. Deny by default.
- Web-first PWA, offline read, online write queue. No bank auto-sync in MVP.

## 2. Architecture

```
Browser PWA (Flutter Web, SkWasm)
  Riverpod UI -> Supabase client (PostgREST + Auth + Realtime + Storage)
  Local Hive cache (read) + outbox queue (writes)

Supabase ap-south-1
  Postgres 17: parties, loans, payments, emi_schedules, notification_queue, audit_logs
  RLS + current_tenant_id() + handle_updated_at()
  pg_cron 08:00 NPT -> pg_net -> Edge dispatch-alerts -> Resend email + SMS provider
  Storage exports/ for xlsx/pdf
  Realtime postgres_changes for bell tray

Hosting: Firebase Hosting static build/web, HTTPS, COOP/COEP for Wasm SharedArrayBuffer
```

Request paths:
- Read ledger: Flutter -> PostgREST with JWT -> RLS `tenant_id = current_tenant_id()` -> rows -> client calculates PerDay/Dues/Total for selected Today.
- Write: Flutter -> PostgREST insert -> trigger updated_at -> audit_logs via app code -> Realtime invalidate providers.
- Alert: pg_cron schedule -> net.http_post to /functions/v1/dispatch-alerts with Vault secrets -> function queries due/overdue -> insert notification_queue -> Resend/Twilio parallel -> update sent_at.
- Export: client builds xlsx via excel package, or Edge export-report for server PDF.

## 3. Frontend Design

Location: `app/lib/src/`
- `core/calculator/loan_calculator.dart`: pure functions, unit tested. dueDays abs + isProjected, annualRate conversion, perDay, interest, total, emi, splitPayment.
- `core/theme/app_theme.dart`: `ColorScheme.fromSeed(seed 0xFF002C6D, secondary 0xFF4FD166)`, tonalSpot fidelity, light + dark.
- `core/dates/bs_date.dart`: bikram_sambat AD->BS, dual label.
- `features/auth`: AuthGate on onAuthStateChange, LoginPage email/password + signup, UserMenu sign-out.
- `features/home`: HomeShell NavigationBar Ledger/Parties/Payments/Import, LedgerPage DataTable2 1400 minWidth + totals footer, Today picker + Set 2026-10-15.
- `features/parties|loans|payments`: FutureProvider + FormDialogs. LoanForm rate % UI -> decimal DB. PaymentForm preview split.
- `features/import`: seed_data 21 rows, Seed button, FilePicker xlsx import, exportExcel.

State: flutter_riverpod FutureProvider + StateProvider today/direction. No global mutable singletons except Supabase client. Invalidate on insert.

Web specifics: `flutter build web --release --no-wasm-dry-run` verified 54-170s. SkWasm default since 3.22, 2-3x canvas compute vs CanvasKit JS. Serve .wasm as application/wasm, set COOP same-origin + COEP require-corp in firebase.json for SharedArrayBuffer. PWA manifest + service worker generated. No SEO need for private ledger.

Offline (current + target):
- Current: Hive installed, used for future cache. Reads go direct to Supabase.
- Target local-first: UI observes Hive/Drift SSOT, sync layer pushes outbox on connectivity_plus online, pulls via Realtime. PowerSync/Brick pattern evaluated, deferred to avoid migration risk. Rule: never treat API cache as SSOT, queue writes with loan_id client UUID for idempotency.

## 4. Backend Design

Schema applied: `init_nhisab_schema` + `fix_lints`. All RLS enabled, indexes on tenant, party, status, due_date, loan FKs, notif status + loan.

Key DDL decisions:
- `principal NUMERIC(15,2) check >0`, `rate NUMERIC(10,6) check >=0`, `day_base int check 360/365`, `direction receivable/payable`, `status active/closed/defaulted/restructured`, no hard delete FK restrict/cascade as appropriate.
- `current_tenant_id() returns uuid coalesce(jwt app_metadata tenant_id, default 000...001)`. Allows dev auth without custom claims, still isolates when multi-tenant claims added later. Functions fixed `SET search_path=''`.
- Policies: `for all to authenticated using/with check tenant match` per table. Service_role bypasses for cron/seed. anon denied.
- `handle_updated_at()` trigger on loans.

Calculation in SQL for verification only, UI is canonical to keep rounding identical to Dart `round2`. Footers sum rounded rows.

EMI: store schedule rows in emi_schedules, unique(loan_id, installment_no). Cash Credit/Demand interest-only, no amortization.

Audit: audit_logs(table_name, row_id, action, old/new jsonb, actor). App writes on insert/update. Future: DB trigger version.

Validation matrix in docs/04: principal>0, party required, rate warning >0.15 micro / >0.24 private, payment_method required, TDS report-only.

Known sheet divergence documented: Group B future loans sheet forces DueDays=1, app uses abs diff 1,1,2,3,4,5,6. App correct, principal 85713900 matches, interest 99300 vs 27506 flagged.

## 5. Auth and Security

- Supabase Auth email/password. Publishable key `sb_publishable_...` in client, service_role only in Edge/Vault.
- JWT -> RLS. Test as different users, check zero rows cross-tenant. Advisor security lints clean except INFO unused-index expected empty.
- Secrets: RESEND_API_KEY, TWILIO/Sparrow keys in Edge Secrets + Vault decrypted_secrets for pg_net calls, never VITE_ or --dart-define public.
- Checklist: enable RLS every table, no `with check true`, SECURITY INVOKER for client functions, fully qualified names, composite index (tenant_id, id), partial index active loans, verify `select * from pg_tables where rowsecurity=false` empty in public.

## 6. Notifications

Design from Supabase Cron research:
- `notification_queue(id, loan_id, alert_type, channel email/sms/in_app, status pending/sent/failed, scheduled_at, sent_at)`.
- pg_cron `daily-loan-alerts 0 8 Asia/Kathmandu` calls Edge via pg_net http_post with Vault project_url + publishable_key.
- Edge `dispatch-alerts.ts` Deno: create service client, query loans where due_date - today in [7,1] or overdue, dedupe by date + loan + channel, Promise.all Resend + SMS, insert in_app row, update queue.
- Health: cron_health table last_run/status/retry, second cron health-check every 5m, cleanup 30d. Dashboard shows queue status for debug.
- Providers: Resend 3000/mo free for email, Twilio test +15005550006 dev, Sparrow/Aakash for Nepal prod via same Edge interface.

## 7. Data Integrity and Money

- Postgres NUMERIC(15,2) storage, DECIMAL(19,4) buffer considered for intermediate rate math if needed, final round 2dp. Never double in DB, never money type locale-sensitive.
- Dart `decimal` dep installed, current calculator uses double round2 for speed with tests locking `750.00/88500/1588500`. Migrate inner math to Decimal before high-volume interest to avoid accumulation.
- Idempotency: client UUID loan_id/payment_id, unique emi (loan, no), outbox retry safe.
- Backups: Supabase PITR, weekly filtered dump per tenant for portability. Promotion path shared->dedicated project if needed: filtered dump + storage re-upload.

## 8. Performance and Scale

- Indexes cover RLS filter + joins. Avoid RLS joins across tables in policy, keep `tenant_id = current_tenant_id()`.
- Pagination limit 200 payments, DataTable2 virtualized horizontal scroll minWidth 1400. Future: server aggregate view for footers when >10k rows.
- Realtime scoped to tenant channel, not full table.
- Web: deferred charts, tree-shaken icons verified 99% reduction, CanvasKit/Wasm fallback Auto renderer.

## 9. Deployment - GitHub Pages (Locked 2026-10-15)

- Build: `flutter build web --release --base-href="/nhisab/" --no-wasm-dry-run` -> `app/build/web`. Locked for repo `namunaONE/nhisab`.
- Host: GitHub Pages via `.github/workflows/pages.yml` (build + `upload-pages-artifact` + `deploy-pages`). Live URL `https://namunaone.github.io/nhisab/`. Source template `app/web/404.html`, marker `app/web/.nojekyll`; CI copies built `index.html -> 404.html` and touches `build/web/.nojekyll` every deploy.
- Settings: repo Settings > Pages > Source `GitHub Actions`. Secrets `SUPABASE_URL` + `SUPABASE_ANON_KEY`; unset secrets fall back to dev defaults in `app/lib/main.dart:9-12`.
- Env: `--dart-define=SUPABASE_URL --dart-define=SUPABASE_ANON_KEY`, separate projects for staging/prod, `supabase link` per env.
- Constraint: Pages sets no custom headers, so stay on JS/CanvasKit build (current `main.dart.js`, no `.wasm`). Wasm multithread needs `COOP/COEP` -> use Firebase Hosting instead if that path is taken.
- Cost: Pages $0, Supabase free 500MB, Resend free, SMS pay-use. Single shared project $0 marginal per idle tenant vs $10/mo dedicated per tenant.

## 10. Testing and Observability

- Unit: loan_calculator_test 2/2 passed Row1 + EMI sanity. Add: zero-rate, 365 base, split, abs future.
- RLS: login as two users, assert isolation, advisors security/performance on each migration.
- Integration: seed 21 -> set Today 2026-10-15 -> assert receivable 9960000/668653.33, payable 85713900.
- Logs: Supabase query_logs ClickHouse for Edge + postgres, Edge logs for Resend/Twilio IDs, notification_queue as audit trail.
- Crash: recordError hook works same Wasm/JS.

## 11. Decisions (ADRs)

- ADR1 Single shared project + tenant_id RLS over per-tenant projects. Reason: $0 idle, instant tenant, promote on pay. Ref: Erfi shared+promote, Clerk/Supabase RLS defense-in-depth.
- ADR2 360 banker default with 365 option. Reason: replicate sheet `750.00` exactly.
- ADR3 NUMERIC not money/float. Reason: exact ledger, vendor docs converge.
- ADR4 Hive cache + outbox later, not PowerSync now. Reason: avoid sync-rule + RLS complexity pre-MVP, keep SSOT migration path open.
- ADR5 Resend + pluggable SMS via Edge, pg_cron + pg_net + Vault. Reason: $0 self-healing cron, secrets off client.
- ADR6 Fixed brand seeds, tonalSpot, no dynamic image color. Reason: fidelity + contrast.

## 12. Risks and Open Questions

- Future DueDays rule confirmed correct vs sheet manual 1. Keep abs, flag in UI.
- Machhapuchhre 0.80 = 80% as per sheet PerDay 8888.89. Verify with bank, likely 8% input error.
- TDS % confirm with accountant, currently report-only configurable.
- SMS provider Nepal contract pending.
- Auth email confirmation setting in Supabase dashboard affects first login UX.

## 13. Budget Tracker v1 Skeleton (Locked 2026-10-15)

Tables (migration `20261015140000_budget_tracker_v1`): `accounts`, `categories`, `transactions`, `budgets`. Same conventions: `tenant_id default 000...001`, `current_tenant_id()` RLS `authenticated`, `deleted_at` soft-delete, `NUMERIC(15,2)`, AD `DATE`, indexes on tenant/account/category/date. Providers return `[]` on missing-table error so Pages build stays green pre-apply.

Frontend `app/lib/src/`: `core/budget/budget_calculator.dart` (pure, tested), `features/accounts|transactions|budgets|dashboard|more` stubs. Nav: Dashboard | Ledger | Txns | Budgets | More (More hosts Parties/Payments/Import/Accounts). Dashboard wires `fl_chart` BarChart cashflow + PieChart budget split + overdue strip from `loansProvider`. Loan tables remain source of truth for interest; transaction `loan_id` link only.
