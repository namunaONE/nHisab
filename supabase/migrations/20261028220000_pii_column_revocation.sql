-- Make parties_safe security_definer so it can read sensitive columns
-- regardless of the caller's column grants (masking enforced by CASE).
alter view public.parties_safe set (security_invoker = false);

-- Revoke direct SELECT on sensitive PII columns from authenticated.
-- Viewers (and any client) must read them through parties_safe, which masks
-- based on current_tenant_role().
revoke select (phone, address, id_number) on public.parties from authenticated;

-- Ensure the view can still read them (owner = migration role / postgres).
grant select (phone, address, id_number) on public.parties to postgres;
