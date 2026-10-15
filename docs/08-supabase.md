# 08 - Supabase Project nhisab

## Project
- Name: nhisab
- ID / Ref: qcbxurqxmnkzgsfpaesz
- Org: Namuna One (roxuaraiptvmqmnmwcmw)
- Region: ap-south-1 Mumbai
- Status: ACTIVE_HEALTHY on 2026-10-15
- Postgres: 17.11.0.003
- URL: https://qcbxurqxmnkzgsfpaesz.supabase.co
- DB Host: db.qcbxurqxmnkzgsfpaesz.supabase.co

## Keys (do not commit real keys, use --dart-define)
- anon (legacy JWT) available via MCP, disabled=false
- publishable sb_publishable_... available via MCP
- Get via: Supabase Dashboard > Project Settings > API

## Schema Applied
1. `init_nhisab_schema` - parties, loans (with direction receivable/payable, day_base 360/365), payments, emi_schedules, notification_queue, audit_logs + RLS + indexes + current_tenant_id() + handle_updated_at()
2. `fix_lints` - idx_notification_queue_loan, search_path fixes

Verified: RLS enabled on all 6 tables. Security lints clean except unused-index INFO (expected empty).

## Verification Test 2026-10-15
Inserted Saroj Poudel 1500000 @0.18 annual 360 start 2026-06-19:
- per_day 750.00, due_days 118, interest 88500.00, total 1588500.00 matches sheet Row 1.
Test rows deleted, loans_left=0 clean.

## Next
- Create Auth user, set app_metadata.tenant_id = 00000000-0000-0000-0000-000000000001
- Flutter: flutter create --platforms web nhisab_app + supabase_flutter init with URL/anon
- Run: flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
