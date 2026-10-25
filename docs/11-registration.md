# 11 - Registration and User Provisioning

Date: 2026-10-25. App users and parties are separate records. Public sign-up is
disabled; new users join by invitation.

## 1. Invite-Only User Provisioning

### Roles

| Role | Read | Write ledger | Invite users | Manage members |
|---|---|---|---|---|
| `owner` | Yes | Yes | Yes | Yes (not last owner) |
| `manager` | Yes | Yes | No | No |
| `viewer` | Yes | No | No | No |

The authoritative role is `public.tenant_members.role`. `public.profiles.role`
is a projection kept in sync by a trigger so the client can gate UI without an
extra query. Authorization in RLS and RPCs always uses the membership row.

### Flow

1. An owner creates an invitation:

```sql
select public.create_tenant_invite('person@example.com', 'manager');
```

This is owner-only, validates the email and role, and writes an audit row. The
raw token is not returned to the client (`to_jsonb(v_invite) - 'token'`).

2. The owner invites the same address from Supabase Dashboard >
   Authentication > Users. Public sign-up must be off.
3. On `auth.users` insert, `handle_new_user()` looks for a matching, unexpired,
   unaccepted invite:
   - Match found: create `profiles` and `tenant_members`, then mark the invite
     accepted.
   - No match: create nothing. The user can authenticate but the app fails closed
     with "Account not provisioned" and offers sign-out.
4. The user signs in with email/password. There is no sign-up form and no
   self-service organisation creation.

### Required Auth settings

- Disable "Allow new users to sign up".
- Enable email confirmation.
- Set Site URL and redirect allow-list to the deployed app URL (password reset
  uses `redirectTo: Uri.base`).
- Keep anonymous sign-ins disabled.
- Consider CAPTCHA and rate limits; invite-only is not a substitute.

### Why public sign-up was removed

The prototype's trigger created an `owner` profile in the shared tenant for every
new auth user. Combined with the shared `current_tenant_id()` fallback, a
stranger could read and write every party, loan, payment and wallet. Removing the
form alone was insufficient; the database trigger now provisions only invited
users and RLS has no fallback tenant.

## 2. Profile Data

`public.profiles`:

| Column | Notes |
|---|---|
| `id` | PK, FK `auth.users(id)` on delete cascade |
| `display_name` | From invite metadata or email local-part; editable by the user |
| `email` | From Auth; not editable by the client |
| `phone` | Optional; editable by the user |
| `role` | `owner`, `manager`, `viewer`; synced from membership, not client-writable |
| `tenant_id` | From the invite; not client-writable |
| `created_at`, `updated_at` | Timestamps |

Clients have `SELECT` on their own profile and `UPDATE` only on
`display_name` and `phone`. Attempting to update `role` or `tenant_id` fails at
the grant layer even if the UI is bypassed.

## 3. Sign-In UX

- Email/password only.
- Email format and required-password validation inline.
- Show/hide password toggle.
- "Forgot password?" sends a Supabase reset email; the response is deliberately
  neutral so it does not disclose whether an address is registered.
- A blocked account shows one of: not provisioned, no organisation, unsupported
  role, or account-check failure. Each offers sign-out or retry; none falls
  through to the app.
- Viewers see a persistent read-only banner and no write controls.

## 4. Party Register (Borrower / Lender)

Parties are counterparties, not app users. They do not sign in.

Required:

- **Name** - include a location or family tag where needed to distinguish
  homonyms, e.g. "Madhav Koirala (Harkapur)".

Optional but recommended:

- **Phone** - for contact and future due alerts. No SMS is sent today.
- **Address** - recovery/location context.
- **ID number** - citizenship, NID or passport. Treat as sensitive personal data
  under the Privacy Act 2075. There is no verification, masking or retention
  policy yet.

For Nepal KYC/AML expectations, an ID number should eventually be mandatory above
a documented principal threshold, with verification and a risk rating. The app
does not implement that threshold today.

## 5. Implementation Checklist

- [x] Remove public sign-up from the client.
- [x] Invite-only `handle_new_user()` trigger; no invite means no profile or
      membership.
- [x] Owner-only `create_tenant_invite()` RPC with role and email validation.
- [x] `tenant_members` as the authoritative role source; profile-role sync
      trigger.
- [x] Fail-closed `AuthGate` for missing profile, empty tenant and unknown role.
- [x] Viewer read-only UI plus database-level write denial.
- [x] Password reset.
- [x] Last-owner protection.
- [ ] Disable public sign-up and enable email confirmation in the live Supabase
      project (manual dashboard step).
- [ ] Member-admin UI and invitation acceptance screen.
- [ ] ID-number requirement above a documented principal threshold.
- [ ] MFA, CAPTCHA/rate limits, session management.
- [ ] Consent, retention and data-subject request workflow.
