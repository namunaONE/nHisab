# Supabase - nHisab

Remote project nhisab qcbxurqxmnkzgsfpaesz ap-south-1 already live.
Migrations in this folder were applied via MCP in order:
- 20261015065947 init_nhisab_schema
- 20261015070054 fix_lints
- 20261015073715 add_soft_delete
- 20261015140000 budget_tracker_v1 (applied remote 2026-10-15 + seeded)

No Firebase used. No `supabase link` yet. To adopt CLI later:
supabase init (already have folder), supabase link --project-ref qcbxurqxmnkzgsfpaesz, supabase db pull.
