# 13 - Codebase Standards: Structure, Clean Files, Avoid Bugs

Actual 2026-10-15: app/lib 20 dart files, feature-first flat, Riverpod FutureProvider + StateProvider, flutter_lints only, analyze 0 errors 8 infos, test 1 file 2/2.

## 1. Folder Structure - Feature-First
```
lib/main.dart (Supabase init + AuthGate + HomeShell only)
lib/src/core/calculator|theme|dates (pure, no Flutter deps except theme/dates)
lib/src/features/auth|home|loans|parties|payments|import (per feature: provider + page + form + model)
test/ mirrors lib: test/loan_calculator_test.dart
supabase/migrations/*.sql exported remote
docs/01-13
```
Rules from 2025 guides: feature folders own their UI+state, core holds shared pure logic, no cross-feature imports except via providers. Riverpod lives in presentation + core only. Add per-feature data/ later when repository layer needed. Add barrel index.dart per folder when imports exceed 3 lines. Mirror test/ path per lib file.

Gap: go_router + fl_chart installed not wired, hive/connectivity installed not wired, no supabase/ CLI link, no assets/ folder. Either wire or remove to avoid dead deps.

## 2. Keep Files Clean, Short, Expandable
- One widget per file for dialogs/pages, max ~150 lines. Current loan_form 130, payment_form 106, import_page 170 - split import_page into seed_service + excel_service + page next.
- Pure functions in calculator, no BuildContext. Models as simple classes LoanRow/Party/PaymentRow, add freezed/json_serializable only when boilerplate hurts.
- Providers small: todayProvider, directionFilter, loansProvider with deleted_at filter. No global mutable singletons except Supabase client.
- No hardcoded hex outside app_theme, no hardcoded TextStyle sizes outside theme, use scheme + textTheme roles.
- Name consistently: *_page.dart screens, *_form.dart dialogs, *_provider.dart riverpod, loan_model.dart singular.

## 3. Avoid Bugs on Flutter
- Always flutter analyze before commit. Current 8 infos are deprecated anonKey/value - track migration to publishableKey/initialValue, do not add new ignores without comment.
- Upgrade path: very_good_analysis over flutter_lints for 100+ rules, enable missing_return + missing_required_param as error, keep parameter_assignments warning. Run dart fix where safe, flutter pub upgrade --major-versions in branch.
- Null safety: prefer final, required named params, handle (parties as Map?) null with fallback '-', never dynamic calls without cast. Avoid empty catch, log to notification_queue/crash hook.
- Async: avoid async void except callbacks, check mounted before setState after await - already done in forms. Invalidate providers after insert/delete.
- Tests: every calculator change needs assertion, no tests without expect, no duplicate assertions. Add zero-rate, 365 base, split with prev sum, abs future cases. Add RLS tests as two users, widget test for AuthGate login->ledger.
- Common pitfalls hit here: const with non-const TextCellValue fixed, widget_test MyApp deleted after rename to NHisabApp, pub version bikram_sambat 0.0.2 nonexistent fixed to 1.2.0 via pub.dev check, build timeout 120s fixed with 600s + --no-wasm-dry-run.
- Caches: flutter clean + pub get on EventChannel/pub-cache corruption, flutter pub cache repair for internals missing.
- Layout: no hardcoded heights in ledger, DataTable2 minWidth 1400 + horizontal scroll, dialogs SingleChildScrollView, test RenderFlex on small device.

## 4. Workflow Checklist
- [ ] Enable stricter lints, fix 8 infos to 0.
- [ ] Split import_page, add seed_service guard test, add deleted_at filter test per provider.
- [ ] Add test mirroring lib/src structure.
- [ ] Remove or wire go_router/fl_chart/hive/connectivity.
- [ ] Document ADRs for structure choices in docs/10.
