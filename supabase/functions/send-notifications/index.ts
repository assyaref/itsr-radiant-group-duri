// Drains public.notification_outbox and sends email through Gmail SMTP.
//
// Who may invoke it (it only ever processes rows the DATABASE enqueued, so
// invoking it cannot create or alter notifications):
//   * any active signed-in user (the app "kicks" it after an action), or
//   * a scheduler presenting header  x-cron-secret: $NOTIFICATIONS_CRON_SECRET
//
// Required secrets (set with `supabase secrets set`, never in the Flutter app):
//   GMAIL_USER            Gmail / Google Workspace address used as sender
//   GMAIL_APP_PASSWORD    16-char Google App Password for that account
// Optional: NOTIFICATIONS_CRON_SECRET, ALLOWED_ORIGINS, MAIL_FROM_NAME
import nodemailer from "npm:nodemailer@6.9.16";
import { bearerToken, corsHeaders, json } from "../_shared/http.ts";
import { adminClient, verifyCaller } from "../_shared/supabase.ts";
import { buildEmail, type EventContext, type Person, type Settings } from "../_shared/notification_rules.ts";

const PERSON = "id, full_name, email, is_active";

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

  const user = Deno.env.get("GMAIL_USER");
  const pass = Deno.env.get("GMAIL_APP_PASSWORD");
  if (!user || !pass) {
    // Leave rows pending so nothing is lost once credentials are configured.
    return json({ error: "Email is not configured (GMAIL_USER / GMAIL_APP_PASSWORD)" }, 503, headers);
  }

  const transport = nodemailer.createTransport({
    host: "smtp.gmail.com", port: 465, secure: true, auth: { user, pass },
  });
  const from = `"${Deno.env.get("MAIL_FROM_NAME") ?? "ITSR Radiant Group Duri"}" <${user}>`;

  const { data: settingsRow } = await admin.from("app_settings")
    .select("it_support_group_email, manager_email, app_base_url, notifications_enabled").eq("id", true).single();
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

  const results = { sent: 0, skipped: 0, failed: 0 };
  for (const row of (batch ?? []) as Array<{ id: string; ticket_id: string; event_type: EventContext["event"]; payload: Record<string, unknown> }>) {
    try {
      const { data: t } = await admin.from("tickets")
        .select(`id, ticket_number, subject, description, category, priority, status, resolution,
                 reporter:profiles!tickets_reporter_id_fkey(${PERSON}),
                 assignee:profiles!tickets_assigned_to_id_fkey(${PERSON})`)
        .eq("id", row.ticket_id).single();
      if (!t) throw new Error("ticket not found");

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
        await admin.rpc("complete_notification", { p_id: row.id, p_status: "skipped", p_error: "no recipients" });
        results.skipped++;
        continue;
      }

      await transport.sendMail({ from, to: email.to, cc: email.cc, subject: email.subject, text: email.text, html: email.html });
      await admin.rpc("complete_notification", {
        p_id: row.id, p_status: "sent", p_error: null, p_recipients: email.to, p_cc: email.cc,
      });
      results.sent++;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("notification failed", row.id, msg);
      await admin.rpc("complete_notification", { p_id: row.id, p_status: "failed", p_error: msg });
      results.failed++;
    }
  }
  return json(results, 200, headers);
});
