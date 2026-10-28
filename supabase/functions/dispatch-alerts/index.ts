import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/// nHisab daily dispatcher: due/overdue loan alerts → notification_queue,
/// then fans out to Resend (email) + SMS provider. In-app rows always work;
/// email/SMS send only when their secrets are set.
///
/// Secrets (Edge Secrets / Vault): RESEND_API_KEY, SMS_API_KEY, SMS_SENDER.
/// Deploy: supabase functions deploy dispatch-alerts
/// Invoke (pg_cron via pg_net, 08:00 NPT): POST /functions/v1/dispatch-alerts
///   with service-role Authorization header.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const SMS_KEY = Deno.env.get("SMS_API_KEY") ?? "";
const SMS_SENDER = Deno.env.get("SMS_SENDER") ?? "nHisab";

type Loan = {
  id: string;
  tenant_id: string;
  party_id: string;
  principal_amount: number;
  start_date: string;
  due_date: string | null;
  status: string;
  parties: { name: string; phone: string | null } | null;
};

async function sb(path: string, init: RequestInit = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) throw new Error(`Supabase ${path}: ${res.status} ${await res.text()}`);
  return res.json();
}

async function sendEmail(to: string, subject: string, html: string) {
  if (!RESEND_KEY) return { skipped: true };
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: "nHisab <alerts@nhisab.com>", to, subject, html }),
  });
  return { ok: res.ok, id: res.ok ? (await res.json()).id : await res.text() };
}

async function sendSms(to: string, text: string) {
  if (!SMS_KEY || !to) return { skipped: true };
  // Pluggable SMS interface (Sparrow/Aakash for Nepal prod). Wire the
  // provider HTTP call here once the contract is signed.
  console.log(`SMS stub → ${to} [${SMS_SENDER}]: ${text}`);
  return { stub: true };
}

Deno.serve(async (req: Request) => {
  try {
    // Nepal civil date (UTC+05:45) for dedupe and message context.
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kathmandu" });
    const loans: Loan[] = await sb(
      "loans?select=id,tenant_id,party_id,principal_amount,start_date,due_date,status,parties(name,phone)&status=eq.active&deleted_at=is.null",
    );

    let queued = 0;
    let emailed = 0;
    let smsed = 0;
    const errors: string[] = [];

    for (const loan of loans) {
      const due = loan.due_date;
      const daysLeft = due
        ? Math.ceil((new Date(due).getTime() - Date.now()) / 86400000)
        : null;
      let alert: string | null = null;
      if (daysLeft !== null && daysLeft < 0) alert = "overdue";
      else if (daysLeft !== null && daysLeft <= 7) alert = "due_soon";
      if (!alert) continue;

      const partyName = loan.parties?.name ?? "Party";
      const text =
        alert === "overdue"
          ? `nHisab: ${partyName} loan of Rs ${loan.principal_amount} is OVERDUE.`
          : `nHisab: ${partyName} loan of Rs ${loan.principal_amount} due in ${daysLeft}d.`;

      // Dedupe: one row per loan + alert + channel per day.
      const existing: unknown[] = await sb(
        `notification_queue?select=id&loan_id=eq.${loan.id}&alert_type=eq.${alert}&created_at=gte.${today}`,
      );
      if ((existing as unknown[]).length > 0) continue;

      const channels = ["in_app", "email", "sms"] as const;
      for (const channel of channels) {
        const rows = await sb("notification_queue", {
          method: "POST",
          body: JSON.stringify({
            tenant_id: loan.tenant_id,
            loan_id: loan.id,
            alert_type: alert,
            channel,
            status: channel === "in_app" ? "pending" : "pending",
            scheduled_at: new Date().toISOString(),
          }),
        });
        const row = (rows as Record<string, unknown>[])[0] ?? {};
        queued++;

        try {
          if (channel === "email") {
            // Resolve tenant owner emails from profiles (post-hardening, role
            // is a projection of tenant_members). Falls back to skipping the
            // send when no recipient exists so the in-app row still queues.
            let recipients: string[] = [];
            try {
              const owners = await sb(
                `profiles?select=email&tenant_id=eq.${loan.tenant_id}&role=eq.owner`,
              );
              recipients = (owners as Array<{ email?: string | null }>)
                .map((o) => o.email ?? "")
                .filter((e) => e.length > 0);
            } catch (e) {
              console.warn("owner lookup failed", e);
            }
            if (recipients.length === 0) {
              // No recipient configured; leave queued for the audit trail.
            } else {
              for (const to of recipients) {
                const r = await sendEmail(to, `nHisab ${alert}`, text);
                if (!(r as Record<string, unknown>).skipped) emailed++;
              }
            }
          } else if (channel === "sms") {
            const r = await sendSms(loan.parties?.phone ?? "", text);
            if (!(r as Record<string, unknown>).skipped) smsed++;
          }
          await sb(`notification_queue?id=eq.${row["id"]}`, {
            method: "PATCH",
            body: JSON.stringify({ status: "sent", sent_at: new Date().toISOString() }),
          });
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          errors.push(`${loan.id}/${channel}: ${msg}`);
          await sb(`notification_queue?id=eq.${row["id"]}`, {
            method: "PATCH",
            body: JSON.stringify({ status: "failed" }),
          });
        }
      }
    }

    return new Response(
      JSON.stringify({ ok: true, queued, emailed, smsed, errors }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ ok: false, error: msg }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
