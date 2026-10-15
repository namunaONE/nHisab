# 11 - Registration Data Spec

Date: 2026-10-15. Separates app user signup from party record.

## 1. App User Register (Supabase Auth)

Goal: low friction owner/viewer login. Current LoginPage has email/password only, to be extended.

Required:
- Full Name / Display Name: min 2 chars, autocomplete name. Shown in AppBar, audit actor, reports. Passed as signUp options.data display_name.
- Email: unique, format check, autocomplete username, keyboard emailAddress. Supabase verification email expected.
- Password single field: 8+ chars with number + uppercase hint upfront, show/hide toggle, autocomplete new-password, strength checks inline. No Confirm Password field per web.dev / Authgear 2025 / NN/g: double entry increases abandonment and breaks autofill. Email verification + Forgot password covers mistype.
- Terms checkbox: required, consent for financial record storage.

Optional at signup, collect later:
- Phone Number: format +977-98XXXXXXXX, autocomplete tel, keyboard phone. Verify via Supabase phone confirm in Phase 2 if self SMS alerts needed. Forcing upfront drops conversion.

Never collect at app signup: address, citizenship, DOB. Those belong to parties.

Storage:
- auth.users.raw_user_meta_data holds display_name/phone for convenience only. Never use in RLS or authorization, user editable.
- public.profiles table: id uuid PK FK auth.users.id on delete cascade, display_name text, email text, phone text nullable, role text owner/viewer default owner, tenant_id uuid default 00000000-0000-0000-0000-000000000001, created_at timestamptz.
- Trigger on new auth.users insert populates profiles from metadata. RLS: authenticated can read/update own row where auth.uid() = id.

Validation UX:
- Realtime inline, specific messages e.g. Enter valid email like name@example.com, Add at least one number and one uppercase letter.
- Mobile keyboards per field, Forgot password link, verification notice We will send verification email.

## 2. Party Register (Borrower / Lender)

Existing public.parties table. For Nepal AML 2008 + NRB KYC norm:
- Party Name required, keep location tag e.g. Madhav Koirala (Harkapur), Madhu (Japan) A/B distinct.
- Phone optional but recommended for due alerts.
- Address optional, Harkapur etc for recovery.
- ID Number optional now, required for large loans: citizenship / NID / passport. NID centralized KYC per NRB 2082/83, Supreme Court 2026 allows citizenship where NID missing. Record for Black Money Act audit trail.

## 3. Implementation Checklist
- [ ] Extend LoginPage signup mode with display_name + phone optional + terms + show toggle
- [ ] Migration: profiles table + RLS + trigger handle_new_user
- [ ] Update AuthGate to fetch profile role for owner/viewer gating
- [ ] PartyForm already covers name/phone/address/id_number, add ID required warning when principal > threshold e.g. 500000
