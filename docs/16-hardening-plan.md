# 16 - Hardening Plan, Threat Model and Scope Tiers

Date: 2026-10-25. Status: P0 hardening implemented and locally verified; not yet
applied to the live Supabase project or deployed. This document records what was
fixed, why, and what still blocks a production lending deployment.

## 1. Executive Summary

The prototype worked as a single-tenant ledger but had three trust-boundary
defects that made real money data unsafe:

1. `current_tenant_id()` fell back to a shared tenant UUID whenever the JWT had
   no tenant claim. Any authenticated user was therefore a member of the default
   organisation.
2. Public sign-up created an `owner` profile, so a stranger could read every
   party, loan, payment and wallet.
3. Payments were written by the browser as separate PostgREST requests. The
   client computed the interest/principal split, could backdate or overpay, and
   a retry could create a duplicate.

The P0 sprint replaced those assumptions with membership-derived tenancy,
invite-only provisioning, per-operation RLS with minimum column grants, and
server-authoritative payment RPCs. The Flutter client fails closed, blocks
offline money writes, and uses the RPCs when the migration is present. The
migration set has been exercised on PostgreSQL 18.6 (PGlite) and parsed with
`libpg-query`; it has **not** been run against Supabase.

The GitHub Actions failure was fixed first: the BS picker test was timezone
dependent, returning 2026-09-30 under UTC instead of 2026-10-01. CI now pins
Flutter 3.47.7, runs the main suite under UTC and the calendar tests under
`Asia/Kathmandu`, checks pull requests without deploying, and uses a 20-minute
timeout.

## 2. Scope Tiers (decision still open)

No tier has been explicitly chosen. The current work is the minimum required for
Tier A, with some foundations for Tier B. Do not describe the product as
Tier C/D compliant.

| Tier | Customer | What is required | Current fit |
|---|---|---|---|
| **A. Private ledger** | One household, moneylender or small partnership; one organisation; no public onboarding | Invite-only auth, tenant isolation, atomic payments, audit trail, manual backups | **Close.** Needs live staging verification, backup routine and owner training. |
| **B. Small lending back office** | 2-10 staff, several organisations, owner/manager/viewer roles | Staff invite UI, tenant switcher/admin, maker-checker or approval, reconciliation, automated backups, monitoring, staging/prod split | **Foundations only.** Schema and roles exist; no admin UI, approvals, reconciliation, backup automation or monitoring. |
| **C. Nepal-compliant finance back office** | Finance company or licensed lender | VAT/TDS ledgers and returns, CBMS/e-billing where applicable, KYC/AML and goAML, statutory retention, data residency, external audit, incident response | **Not compliant.** No tax filing, KYC workflow, goAML export, legal document generation or Nepal-hosted data. |
| **D. Cooperative / SACCO** | Savings and credit cooperative, multi-branch | Member/share accounting, committee workflows, NRB returns, branch controls, core-banking integration, BCP, penetration test, dedicated infrastructure | **Out of scope.** Requires a different product and regulatory programme. |

Recommendation: finish Tier A, verify on a staging Supabase project, and only
then decide whether Tier B demand justifies staff administration and operational
tooling. Tier C/D should not be promised until the compliance gaps in section 8
are funded.

## 3. Threat Model

### 3.1 Assets

- Party identity and contact data: name, phone, address, citizenship/NID/passport
  number. This is personal data under the Privacy Act 2075.
- Loan terms and balances: principal, rate, start date, accrual, write-offs.
- Payment allocations and wallet movements.
- The audit trail and its actor attribution.
- Tenant membership, roles and invitations.
- Supabase keys, owner credentials and the database backup.

### 3.2 Actors and trust boundaries

| Actor / boundary | Trust |
|---|---|
| Anonymous internet | Untrusted. Must have no table or function surface. |
| Authenticated viewer | May read their tenant; must not write or invite. |
| Authenticated owner/manager | May write within their tenant; may invite (owner only). |
| Malicious or careless tenant member | Can read tenant data by design; must not escalate role, cross tenants, forge payment links or rewrite history. |
| Browser | Untrusted for authorization and money math. Holds a publishable key and a user JWT. |
| PostgREST | Enforces grants and RLS using the caller's JWT. |
| `SECURITY DEFINER` RPCs | Trusted code; must repeat every tenant and role check and use an empty `search_path`. |
| Supabase platform | Trusted for hosting and Auth, but not for free-tier backup guarantees. |
| Operator | Can run SQL and restore backups; human error is a primary risk. |

### 3.3 Threats addressed in this sprint

| Threat | Control |
|---|---|
| Cross-tenant read/write from a shared fallback tenant | `current_tenant_id()` derives an active `tenant_members` row and returns NULL without one. Every business table has RLS and a tenant FK. |
| Public sign-up becoming an owner | Sign-up removed from the client and must be disabled in Supabase Auth. The `auth.users` trigger provisions only a valid, unexpired invite; otherwise no profile or membership is created. |
| Role escalation through `profiles` | Clients may update only `display_name` and `phone`. `role`/`tenant_id` are not granted. Writes authorize from `tenant_members`, and a trigger projects role changes into `profiles.role` for UI gating. |
| Viewer writing money | Per-operation policies call `is_tenant_writer()`; UI also hides write actions. Integration tests cover viewer denial. |
| Client forging a payment split, date or amount | `record_payment` locks the loan, validates date order, caps interest at principal, rejects overpayment and writes payment, wallet legs and audit in one transaction. |
| Duplicate payment after a timeout | `client_id` is unique per tenant; a retry with the same request returns the existing row. A retry of a voided `client_id` is rejected. |
| Deleting an arbitrary old payment to rewrite history | `void_payment` only permits the newest live payment for the loan, soft-deletes it and its wallet legs, and reopens a closed loan. |
| Backdated or out-of-order payments | Rejected by the RPC; same-day entries are allowed, corrections use void. |
| Closing a loan while hiding an unpaid balance | `close_loan` freezes accrual on the Nepal civil date and requires `write_off = true` plus a reason for any unpaid balance. |
| Interest above the principal | Capped in Dart and SQL, mirroring Civil Code 2074 s.481. |
| Forged transaction-to-payment links / double-counted principal | `transactions.payment_id` is server-owned; a composite tenant FK prevents cross-tenant links; principal legs are excluded from cashflow. |
| Audit tampering | `audit_logs` is append-only via trigger and has no update/delete grant; the insert policy binds `actor` to `auth.uid()`. |
| Shared-device data leak | Cache and outbox keys are namespaced per user; auth changes invalidate providers; sign-out clears scoped stores. |
| Offline payment with a guessed allocation | Money writes fail closed offline; reads may use the cache. |
| CI false failures from time zones | Civil-date helpers and dual-timezone CI jobs instead of local-midnight `DateTime` arithmetic. |

### 3.4 Threats not fully addressed

- A compromised owner account can still read and alter tenant data through
  legitimate paths. MFA, session revocation policy and anomaly alerts are not
  implemented.
- Ordinary income/expense/transfer transactions remain client-writable within
  the tenant. An owner/manager can misclassify spending; there is no
  maker-checker or double-entry control.
- Audit rows for non-RPC writes are written by the app. A malicious client can
  omit an audit row for a permitted ordinary write. Payment RPCs write audit
  server-side.
- A viewer can read all PII in the tenant, including ID numbers. There is no
  field-level restriction or PII masking.
- No rate limiting or CAPTCHA on Auth endpoints; invite-only reduces exposure
  but does not eliminate credential stuffing.
- GitHub Pages cannot set security headers (CSP, COOP/COEP). A stolen JWT in
  browser storage is a real risk. A custom host with headers is required for a
  stronger posture.
- The outbox uses plain inserts for ordinary writes. If a request committed but
  the response was lost, a replay can duplicate a transaction. Payments are
  protected by `client_id`; ordinary transactions are not.
- No automated backup, no PITR and no restore drill on the free tier.

## 4. Nepal-Specific Accounting and Compliance Notes

These are engineering notes, not legal or tax advice. Confirm with a Nepali
chartered accountant and counsel before relying on them commercially.

### 4.1 Interest and limitation

- **Civil Code 2074 (2017), s.481** limits cumulative interest to the principal.
  Implemented in `LoanCalculator.cappedInterest` and `record_payment`.
  `dues`/`outstanding` keep principal repayment from reducing unpaid interest.
- **Civil Code 2074, s.484** is reported to set a 10-year limitation period for
  loan claims. The app does not track limitation or send legal reminders.
- A **Tamasuk** should identify the parties, principal, rate, date and
  witnesses. The app stores loan terms but does not generate or stamp a legally
  enforceable instrument.
- Interest is calculated as simple daily accrual:
  `per_day = round(principal × annual_rate / day_base, 2)`, then
  `interest = round(per_day × days, 2)`. `day_base` is 360 by default to match
  the source sheet, with 365 available. `reducing_balance` and `flat` are
  accepted by the schema and form but the calculator/payment split currently
  implement daily accrual; do not market them as supported until tested.

### 4.2 Tax

- **VAT is 13%.** Registration thresholds are commonly stated as Rs 50 lakh
  turnover for goods and Rs 30 lakh for services. Interest on loans is generally
  treated separately from taxable fees; confirm the treatment of fee income.
- **TDS on interest** is generally 15% for resident recipients, subject to
  status and thresholds. The app records `tds_pct` but does not withhold, deposit
  or file TDS. It is a report-only field.
- **CBMS** (Central Billing Monitoring System) binding applies at Rs 20 crore
  annual turnover; e-billing integration is not implemented.
- Fiscal year **2083/84** runs from 17 July 2026 to mid-July 2027. The budget
  tracker currently approximates the FY with AD month buckets (July-June,
  Shrawan=1) labelled as the Nepali FY; exact BS-day boundaries are deferred.
- No VAT return, TDS return, income-tax schedule or IRD-compatible ledger export
  exists. Tier C requires these.

### 4.3 KYC, AML and privacy

- The **Privacy Act 2075 (2018)** requires lawful purpose, consent, minimisation,
  security and breach handling for personal data. Party ID numbers and phone
  numbers are personal data. There is no consent record, retention schedule,
  data-subject export or breach workflow.
- **AML/CFT** obligations include customer due diligence and suspicious
  transaction reporting (goAML) for regulated entities. The app records an
  optional ID number but has no verification, screening, risk rating or goAML
  export.
- **NRB data-residency** expectations for regulated lenders may require data to
  remain in Nepal. The current Supabase project is in `ap-south-1` (Mumbai).
  This is a blocker for Tier C/D unless a Nepal-hosted deployment or explicit
  regulatory approval is obtained.
- Cooperatives and SACCOs have separate NRB/Cooperative Act obligations. The
  current schema has no member shares, savings accounts, branch accounting or
  committee approvals.

### 4.4 Record keeping

- Payments and voids are soft-deleted, never hard-deleted, and the audit log is
  append-only. This supports reconstruction but is not a certified audit trail.
- The client can archive ordinary transactions; payment archiving is now
  RPC-only. There is no period close, immutable ledger snapshot or accountant
  sign-off.

## 5. Implemented Changes

### 5.1 CI and client

- `.github/workflows/pages.yml`: Flutter 3.47.7, `actions/checkout@v5`, UTC test
  run plus Nepal-time calendar run, PR checks without deploy, per-ref
  concurrency, 20-minute timeout, dynamic base href.
- Timezone-independent BS/AD civil-date conversion; the failing widget test now
  passes under both UTC and Nepal time.
- Fail-closed `AuthGate`: missing profile, empty tenant or unknown role is
  blocked, not treated as owner. Public sign-up removed; password reset added.
- Viewer write gating across parties, loans, payments, accounts, categories,
  budgets, transactions, import and notifications.
- Correct accrual: no backward interest for future loans; cumulative interest
  capped at principal; `dues` and `outstanding` fixed; split rejects excess and
  caps the principal portion; aggregate interest/principal paid per loan.
- `PaymentFormDialog` generates a `client_id`, calls `record_payment`, and falls
  back to the legacy writer only when the RPC is genuinely absent
  (`PGRST202`, `42883`, "could not find the function"). Validation errors are
  surfaced, never retried as a legacy write.
- Payments page voids through `void_payment`; `CloseLoanDialog` and ledger
  actions call `close_loan`, with an explicit write-off reason.
- Party statements filter payments by the party's loans, cap interest, honour
  `accrual_end_date`, and show write-offs and outstanding adjustments.
- Wallet transfers affect balances; principal movements are excluded from
  cashflow.
- Per-user cache and outbox namespaces; the outbox only flushes the current
  user; `signOutAndClear()` drops both scopes.

### 5.2 Database

`supabase/migrations/20261025120000_tenant_membership_rls.sql`:

- `tenants`, `tenant_members`, `tenant_invites`; roles `owner`, `manager`,
  `viewer`; one active organisation per user until a switcher exists.
- Membership-derived `current_tenant_id()`, `current_tenant_role()` and
  `is_tenant_writer()`; no shared-tenant fallback.
- Invite-only `handle_new_user()` trigger and owner-only
  `create_tenant_invite()` RPC.
- Per-operation RLS for every business table; no `ALL` policies.
- Minimum column grants: clients cannot write `tenant_id`, `profiles.role`,
  `loans.status`, `transactions.payment_id`, audit history, EMI rows or alerts.
- Composite tenant foreign keys prevent cross-tenant party/loan/payment links.
- Append-only audit log; last-owner protection; profile-role sync trigger.
- Expand-phase columns (`accrual_end_date`, void fields, `transfer_direction`,
  `excluded_from_cashflow`) so the hardened client works before migration 2.

`supabase/migrations/20261025121000_payment_rpcs.sql`:

- `nepal_today()` returns the civil date in `Asia/Kathmandu`.
- `record_payment(p_loan_id, p_amount, p_payment_date, p_payment_method,
  p_remarks, p_account_id, p_client_id)` returns JSONB. Owner/manager only;
  interest-first; caps interest at principal; rejects future, pre-start,
  out-of-order and overpaid payments; idempotent on `client_id`.
- `void_payment(p_payment_id, p_reason)` soft-deletes only the newest live
  payment and its wallet legs; reopens a closed loan.
- `close_loan(p_loan_id, p_write_off, p_reason)` freezes accrual on the Nepal
  date and requires a reason for any write-off.
- Backfills legacy transfer directions, principal cashflow flags and unambiguous
  payment links.
- Revokes direct payment writes, loan lifecycle writes and all anon table and
  function access.

### 5.3 Verification tooling

- `supabase/verify/security_checks.sql`: read-only catalog checks for RLS,
  grants, policies, definer functions, `search_path`, triggers, indexes, FKs and
  columns. Returns PASS or one FAIL row per violation.
- `supabase/verify/smoke_test.sql`: staging-only transaction that impersonates an
  owner, records a payment, rejects an overpayment, proves direct payment writes
  fail, closes with a write-off, voids and reopens, then rolls back.
- Local harnesses (not committed) use `libpg-query` for syntax/PL/pgSQL parsing
  and PGlite PostgreSQL 18.6 for semantic tests:
  - 20/20 integration groups (RLS, grants, tenancy, payment split, idempotency,
    void/close/reopen, interest cap, 365-day math, audit).
  - 11/11 expand/contract groups (migration 1 legacy writes, then migration 2
    lockdown and backfill).
  - `security_checks.sql` and `smoke_test.sql` both PASS.

## 6. Deployment Order and Rollback

The order is expand/contract and is **not optional**:

1. Back up the database (`pg_dump`; see `docs/15-runbook.md`).
2. Apply `20261025120000_tenant_membership_rls.sql`.
3. Deploy the hardened client. Legacy payment writes still work during this
   window; the client uses the RPC only if it exists.
4. Apply `20261025121000_payment_rpcs.sql`.
5. Run `security_checks.sql`, then `smoke_test.sql` on staging.
6. Verify a viewer cannot write, an owner can record/void/close, and a
   non-member cannot read.

Rollback:

- Migration 2 is the hard boundary: direct payment writes are revoked. If the
  client must be rolled back to a pre-RPC build, first restore the expand-phase
  payment grants by re-running migration 1's payment grant block, or restore the
  pre-migration backup. Do not leave an old client running against the contracted
  schema.
- Migration 1 is additive. A rollback that drops the new tables would orphan
  memberships; restore from backup instead.

## 7. Residual Risks and Staging Gates

Before calling this production-ready for Tier A:

- [ ] Apply both migrations to a staging project and run both verification
      scripts. PGlite does not exercise PostgREST, JWT claims or Supabase Auth.
- [ ] Disable public sign-up in Supabase Auth; enable email confirmation; set
      the site URL and redirect allow-list for password reset.
- [ ] Bootstrap the first owner: insert a `tenant_invites` row, invite the user
      from the dashboard, then confirm the trigger created `profiles` and
      `tenant_members`.
- [ ] Take a `pg_dump` before and after the migration and store it off-platform.
- [ ] Test restore into a new Supabase project and compare row counts.
- [ ] Verify `security_checks.sql` returns PASS and `smoke_test.sql` passes.
- [ ] Test two tenants with two browsers: no cross-tenant reads, writes, wallet
      links or audit rows.
- [ ] Test a viewer: read works, every write fails at the database even if the UI
      is bypassed.
- [ ] Test payment idempotency by replaying the same `client_id` after a forced
      timeout.
- [ ] Test void of an older payment is rejected; void of the newest reopens the
      loan.
- [ ] Confirm the live client build points at the intended Supabase project and
      that no service-role key is in the bundle.
- [ ] Document a manual backup schedule and an owner for it.

Remaining product gaps for Tier A: loan editing/correction workflow, a formal
period close, a reconciliation report between wallet legs and payments, and an
operator runbook for rate corrections. Alerts remain undeployed: the
`20261015170000_alert_cron.sql` body is entirely commented out and the
`dispatch-alerts` Edge function is not deployed.

## 8. Tier B/C/D Build-Out (not started)

**Tier B**

- Tenant admin UI: members, roles, invitations, suspend/remove, ownership
  transfer; one active tenant per user is a current constraint.
- Maker-checker for payments, voids, write-offs and loan edits; approval queue.
- Reconciliation: payment ↔ wallet legs ↔ bank/cash statement; exception report.
- Automated encrypted backups, restore drills, staging/prod split, uptime and
  error monitoring, audit export.
- Security: MFA, session management, rate limiting, CSP/security headers,
  dependency scanning, incident response.

**Tier C**

- VAT/TDS ledgers, returns and challan tracking; CBMS/e-billing integration where
  threshold applies; IRD-compatible reports.
- KYC/AML workflow, risk rating, screening, goAML export, retention schedule,
  consent and data-subject requests.
- Nepal-hosted data or a documented residency exception; DPA and privacy notice;
  external security assessment.
- Legal document generation (Tamasuk), limitation tracking, statutory registers.

**Tier D**

- Member/share/savings modules, branch and fund accounting, committee approvals,
  NRB returns, core-banking integration, BCP and a penetration test.

## 9. Decisions

- **Expand/contract, not a big-bang migration.** A hardened client must be live
  before direct payment writes are revoked.
- **Server owns money.** The browser may preview a split, but only the RPC posts
  it.
- **Fail closed.** Missing profile, missing tenant, unknown role, offline payment
  and missing RPC are all explicit failures; none silently degrade to a wider
  permission or a guessed allocation.
- **Minimum grants, not table-wide grants.** Column grants are part of the
  authorization model, not an optimization.
- **Nepal civil dates on the server.** `current_date` is wrong for Nepal between
  18:15 and midnight UTC.
- **No compliance claims.** Tier C/D require work that this codebase does not
  contain.
