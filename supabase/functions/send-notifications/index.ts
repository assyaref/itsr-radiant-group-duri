// Drains public.notification_outbox and sends email through configurable SMTP.
//
// SMTP configuration is read from public.app_settings (non-secret fields) and
// the SMTP password from Supabase Vault (server-side encrypted).
//
// Who may invoke it (it only ever processes rows the DATABASE enqueued, so
// invoking it cannot create or alter notifications):
//   * any active signed-in user (the app "kicks" it after an action), or
//   * a scheduler presenting header  x-cron-secret: $NOTIFICATIONS_CRON_SECRET
//
// Required env (Supabase Secrets, never in the Flutter app):
//   NOTIFICATIONS_CRON_SECRET, ALLOWED_ORIGINS
// Optional: MAIL_FROM_NAME
//
// No hard-coded smtp.gmail.com. No GMAIL_USER / GMAIL_APP_PASSWORD dependency.
import nodemailer from "npm:nodemailer@6.9.16";
import { bearerToken, corsHeaders, json } from "../_shared/http.ts";
import { adminClient, verifyCaller } from "../_shared/supabase.ts";
import { buildEmail, type EventContext, type Person, type Settings } from "../_shared/notification_rules.ts";
import { classifySendError, describeSendError, PermanentError } from "../_shared/smtp_errors.ts";

const PERSON = "id, full_name, email, is_active";

function smtpTransport(host: string | null, port: number | null, secure: boolean | null,
  username: string | null, password: string | null) {
  if (!host || !port || !username || !password) return null;
  return nodemailer.createTransport({
    host, port, secure: secure ?? false,
    auth: { user: username, pass: password },
  });
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"), Deno.env.get("ALLOWED_ORIGINS"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);

  const admin = adminClient();
  const cronSecret = Deno.env.get("NOTIFICATIONS_CRON_SECRET");
  const viaCron = !!cronSecret && req.headers.get("x-cron-secret") === cronSecret;
  if (!viaCron && !(await verifyCaller(admin, bearerToken(req)))) {
    return json({ error: "Not authenticated" }, 401, headers);
  }

  // Read SMTP configuration from app_settings (non-secret) + Vault (password).
  const { data: settingsRow } = await admin.from("app_settings")
    .select("smtp_host, smtp_port, smtp_secure, smtp_username, smtp_sender_name, smtp_sender_email, it_support_group_email, manager_email, app_base_url, notifications_enabled")
    .eq("id", true).single();

  const { data: pw } = await admin.rpc("get_smtp_password");
  const smtpPassword = typeof pw === "string" ? pw : null;

  const transport = smtpTransport(
    settingsRow?.smtp_host ?? null,
    settingsRow?.smtp_port ?? null,
    settingsRow?.smtp_secure ?? null,
    settingsRow?.smtp_username ?? null,
    smtpPassword,
  );

  if (!transport) {
    // Leave rows pending so nothing is lost once credentials are configured.
    return json({ error: "Email is not configured (SMTP settings incomplete)" }, 503, headers);
  }

  const from = `"${settingsRow?.smtp_sender_name ?? Deno.env.get("MAIL_FROM_NAME") ?? "ITSR Radiant Group Duri"}" <${settingsRow?.smtp_sender_email ?? settingsRow?.smtp_username ?? ""}>`;

  // Check the SMTP login BEFORE claiming anything: a wrong/revoked App Password
  // must not consume retry attempts of every queued notification.
  try {
    await transport.verify();
  } catch (e) {
    console.error("smtp verify failed", describeSendError(e));
    return json({ error: "Email server unavailable; nothing was claimed" }, 503, headers);
  }

  // A sent email whose completion is not recorded would be re-sent after the
  // 10-minute stale-lock window, so retry the completion call before giving up.
  async function rpcWithRetry(fn: string, args: Record<string, unknown>): Promise<void> {
    for (let i = 0; i < 3; i++) {
      const { error } = await admin.rpc(fn, args);
      if (!error) return;
      console.error(`${fn} failed (try ${i + 1})`, error.message);
      await new Promise((r) => setTimeout(r, 300 * (i + 1)));
    }
  }

  // (settingsRow was read once above, together with the SMTP fields.)
  const settings: Settings = {
    it_support_group_email: settingsRow?.it_support_group_email ?? null,
    manager_email: settingsRow?.manager_email ?? null,
    app_base_url: settingsRow?.app_base_url ?? null,
  };

  const { data: staffRows } = await admin.from("profiles").select(PERSON)
    .eq("is_active", true).eq("role", "it_support");
  const activeItStaff = (staffRows ?? []) as Person[];

  const { data: batch, error: claimErr } = await admin.rpc("claim_notifications", { p_limit: 20 });
  if (claimErr) return json({ error: "Could not claim notifications" }, 500, headers);

  const results = { sent: 0, skipped: 0, failed: 0, permanent: 0 };
  for (const row of (batch ?? []) as Array<{ id: string; ticket_id: string; event_type: EventContext["event"]; payload: Record<string, unknown> }>) {
    try {
      const { data: t, error: ticketErr } = await admin.from("tickets")
        .select(`id, ticket_number, subject, description, category, priority, status, resolution,
                 reporter:profiles!tickets_reporter_id_fkey(${PERSON}),
                 assignee:profiles!tickets_assigned_to_id_fkey(${PERSON})`)
        .eq("id", row.ticket_id).maybeSingle();
      if (ticketErr) throw new Error(`ticket lookup failed: ${ticketErr.message}`); // temporary
      if (!t) throw new PermanentError("ticket not found");

      const actorId = typeof row.payload?.actor_id === "string" ? row.payload.actor_id : null;
      const { data: actor } = actorId
        ? await admin.from("profiles").select(PERSON).eq("id", actorId).maybeSingle()
        : { data: null };
      const commentId = typeof row.payload?.comment_id === "string" ? row.payload.comment_id : null;
      const { data: comment } = commentId
        ? await admin.from("ticket_comments").select("content").eq("id", commentId).maybeSingle()
        : { data: null };

      const email = settingsRow?.notifications_enabled === false ? null : buildEmail({
        event: row.event_type, payload: row.payload ?? {}, ticket: t as unknown as EventContext["ticket"],
        actor: actor as Person | null, comment, activeItStaff,
      }, settings);

      if (!email) {
        await rpcWithRetry("complete_notification", { p_id: row.id, p_status: "skipped", p_error: "no recipients" });
        results.skipped++;
        continue;
      }

      const info = await transport.sendMail({ from, to: email.to, cc: email.cc, subject: email.subject, text: email.text, html: email.html });
      console.log("notification sent", row.id, row.event_type, "messageId", info.messageId,
        "accepted", (info.accepted ?? []).length, "rejected", (info.rejected ?? []).length);
      await rpcWithRetry("complete_notification", {
        p_id: row.id, p_status: "sent", p_error: null, p_recipients: email.to, p_cc: email.cc,
      });
      results.sent++;
    } catch (e) {
      const msg = describeSendError(e);
      const kind = classifySendError(e);
      console.error("notification failed", row.id, kind, msg);
      if (kind === "permanent") {
        await rpcWithRetry("fail_notification_permanently", { p_id: row.id, p_error: msg });
        results.permanent++;
      } else {
        await rpcWithRetry("complete_notification", { p_id: row.id, p_status: "failed", p_error: msg });
        results.failed++;
      }
    }
  }
  return json(results, 200, headers);
});
