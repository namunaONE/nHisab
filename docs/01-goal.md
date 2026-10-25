# 01 - Goal (Status 2026-10-25)

## Problem

The source ledger is a 21-row Excel workbook in three groups: Rs 5,700,000 lent,
Rs 85,713,900 borrowed, and Rs 4,260,000 lent. It has a manual "Today", no audit
trail, no payment split, no access control and no reliable due-date reminders.

## Goal Statement

An invite-only nHisab web app for a Nepal-based lender: create parties, loans and
payments, calculate interest/dues/outstanding for any civil date, record payments
atomically, keep an audit trail, and export the ledger for reconciliation. The
database is the source of truth; the browser is not trusted with money.

## Success Criteria

| # | Criterion | Status |
|---|---|---|
| 1 | 21-row footers match to the paisa | **PARTIAL.** Receivable principal 9,960,000 and interest 668,653.33 match; payable principal 85,713,900 matches. Payable interest differs from the sheet's forced 1-day future rule because the app accrues real days (99,300 vs 27,506). Documented, not a bug. |
| 2 | Change Today and recalculate instantly | **PASS.** Ledger recalculation works for any selected date. |
| 3 | Partial payment interest-first | **PASS.** Client preview and server RPC use the same split; overpayment and backdating are rejected. |
| 4 | EMI matches the bank | **PARTIAL.** Formula, schedule UI and PDF exist; payment allocation is still daily accrual, not amortizing. |
| 5 | Dual AD + BS dates | **PASS.** Pickers return AD; BS is displayed/selected; tests pass under UTC and Nepal time. |
| 6 | Excel export matches the sheet | **PARTIAL.** Columns and workbook export exist; byte-for-byte comparison against the source is not recorded. |
| 7 | RLS + soft delete + audit | **PASS with caveats.** Per-operation RLS, minimum grants, append-only audit and soft deletes are implemented. Ordinary-write audit rows are client-generated and can be omitted by a crafted client; server RPCs audit themselves. Live application and cross-tenant staging tests are still pending. |
| 8 | Tenant isolation and invite-only access | **PASS locally.** Membership-derived tenancy, invite-only provisioning, viewer/owner/manager roles and fail-closed auth are covered by the PGlite suite. Not yet applied to Supabase. |
| 9 | Atomic, idempotent money writes | **PASS locally.** `record_payment` locks the loan, splits interest first, caps interest, rejects overpayment and is idempotent on `client_id`. Direct payment writes are revoked after migration 2. |
| 10 | CI and deploy are trustworthy | **PASS.** The timezone-dependent BS test is fixed; CI runs under UTC and Nepal time, checks PRs without deploying, and builds the Pages artifact. |

## Non-Goals (current)

- VAT/TDS filing, CBMS/e-billing, IRD-compatible ledgers.
- KYC/AML verification, goAML reporting, consent/retention workflows.
- Cooperative/SACCO member shares, savings, branches or NRB returns.
- Bank auto-sync, double-entry accounting, SaaS billing, native mobile apps,
  e-signatures.
- Automated email/SMS alerts: the Edge function and cron are not deployed.

These are scope tiers C/D in `docs/16-hardening-plan.md`. Do not market them as
available.

## Immediate Gate

The code and migrations are locally verified but **not applied to the live
Supabase project**. Before calling this production-ready: back up, apply the
tenancy migration, deploy the hardened client, apply the payment migration, run
`security_checks.sql` and the staging `smoke_test.sql`, and complete the manual
cross-tenant/viewer checks in `docs/15-runbook.md`.
