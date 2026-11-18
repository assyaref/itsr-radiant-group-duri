// SMTP configuration management Edge Function.
// All actions require an authenticated administrator caller (verified via JWT + profile).
//
// Required env (Supabase Secrets, never in Flutter/GitHub):
//   NOTIFICATIONS_CRON_SECRET   (not used here; kept for consistency)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (injected by Supabase)
//
// Vault secrets (set via `supabase vault` or the public.set_smtp_password RPC):
//   itsr_smtp_password   SMTP AUTH password (server-side encrypted)
//
// Actions (POST body: { action: 'save'|'remove'|'test'|'send_test'|'status', ... }):
//   save       Save SMTP configuration. Password goes to Vault; other fields to app_settings.
//   remove     Delete the stored SMTP password from Vault.
//   test       Test SMTP connectivity (no email sent). Requires full SMTP config.
//   send_test  Send a test email. Requires explicit confirmation + full SMTP config.
//   status     Return SMTP configuration status (no password, no secrets).
import nodemailer from "npm:nodemailer@6.9.16";
import { bearerToken, corsHeaders, json } from "../_shared/http.ts";
import { adminClient, verifyCaller, type CallerProfile } from "../_shared/supabase.ts";

const ADMIN_ROLES: readonly string[] = ["administrator", "superadmin"];

type SmtpConfig = {
  host?: string;
  port?: number;
  secure?: boolean;
  username?: string;
  password?: string;
  sender_name?: string;
  sender_email?: string;
};

function isAdmin(profile: CallerProfile | null): boolean {
  return !!profile && ADMIN_ROLES.includes(profile.role) && profile.is_active;
}

function buildTransport(cfg: SmtpConfig) {
  return nodemailer.createTransport({
    host: cfg.host,
    port: cfg.port,
    secure: cfg.secure ?? false,
    auth: cfg.username && cfg.password ? { user: cfg.username, pass: cfg.password } : undefined,
  });
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"), Deno.env.get("ALLOWED_ORIGINS"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);

  const admin = adminClient();
  const token = bearerToken(req);
  const caller = await verifyCaller(admin, token);
  if (!caller || !isAdmin(caller)) {
    return json({ error: "Administrator access required" }, 403, headers);
  }

  let body: { action?: string; [k: string]: unknown };
  try {
    body = (await req.json()) as { action?: string; [k: string]: unknown };
  } catch {
    return json({ error: "Invalid JSON body" }, 400, headers);
  }

  const action = body.action;
  if (!action || typeof action !== "string") {
    return json({ error: "Missing 'action' field" }, 400, headers);
  }

  // ------------------------------------------------------------------
  // ACTION: status — return SMTP configuration status (no secrets)
  // ------------------------------------------------------------------
  if (action === "status") {
    const { data: settings, error } = await admin
      .from("app_settings")
      .select(
        "smtp_host, smtp_port, smtp_secure, smtp_username, smtp_sender_name, smtp_sender_email, smtp_configured_at, smtp_last_test_at, smtp_last_test_result, smtp_last_test_error, smtp_last_successful_email_at, smtp_last_failed_email_at, notifications_enabled, it_support_group_email, manager_email",
      )
      .eq("id", true)
      .single();
    if (error) {
      return json({ error: "Could not read configuration" }, 500, headers);
    }

    // Check whether a password exists in Vault (without returning it).
    const { data: pw } = await admin.rpc("get_smtp_password");
    const passwordConfigured = typeof pw === "string" && pw.length > 0;

    return json({
      smtp_host: settings?.smtp_host ?? null,
      smtp_port: settings?.smtp_port ?? null,
      smtp_secure: settings?.smtp_secure ?? null,
      smtp_username: settings?.smtp_username ?? null,
      smtp_sender_name: settings?.smtp_sender_name ?? null,
      smtp_sender_email: settings?.smtp_sender_email ?? null,
      password_configured: passwordConfigured,
      notifications_enabled: settings?.notifications_enabled ?? false,
      it_support_group_email: settings?.it_support_group_email ?? null,
      manager_email: settings?.manager_email ?? null,
      smtp_configured_at: settings?.smtp_configured_at ?? null,
      smtp_last_test_at: settings?.smtp_last_test_at ?? null,
      smtp_last_test_result: settings?.smtp_last_test_result ?? null,
      smtp_last_test_error: settings?.smtp_last_test_error ?? null,
      smtp_last_successful_email_at: settings?.smtp_last_successful_email_at ?? null,
      smtp_last_failed_email_at: settings?.smtp_last_failed_email_at ?? null,
    }, 200, headers);
  }
  // ------------------------------------------------------------------
  // ACTION: save — save SMTP configuration
  // ------------------------------------------------------------------
  if (action === "save") {
    const cfg: SmtpConfig = {
      host: typeof body.host === "string" ? body.host.trim() : undefined,
      port: typeof body.port === "number" ? body.port : undefined,
      secure: typeof body.secure === "boolean" ? body.secure : undefined,
      username: typeof body.username === "string" ? body.username.trim() : undefined,
      password: typeof body.password === "string" ? body.password : undefined,
      sender_name: typeof body.sender_name === "string" ? body.sender_name.trim() : undefined,
      sender_email: typeof body.sender_email === "string" ? body.sender_email.trim() : undefined,
    };

    const errors: string[] = [];
    if (!cfg.host) errors.push("SMTP host is required");
    if (!cfg.port) errors.push("SMTP port is required");
    if (cfg.secure === undefined) errors.push("Encryption (SSL/TLS or STARTTLS) is required");
    if (!cfg.username) errors.push("SMTP username is required");
    if (!cfg.sender_email) errors.push("Sender email is required");
    if (cfg.sender_email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cfg.sender_email)) {
      errors.push("Sender email is not valid");
    }
    if (cfg.password === undefined) errors.push("SMTP password is required");

    if (errors.length > 0) {
      return json({ error: errors.join("; ") }, 400, headers);
    }

    const now = new Date().toISOString();
    const { error: updErr } = await admin
      .from("app_settings")
      .update({
        smtp_host: cfg.host,
        smtp_port: cfg.port,
        smtp_secure: cfg.secure,
        smtp_username: cfg.username,
        smtp_sender_name: cfg.sender_name ?? null,
        smtp_sender_email: cfg.sender_email,
        smtp_configured_at: now,
      })
      .eq("id", true);
    if (updErr) {
      return json({ error: "Could not save SMTP configuration" }, 500, headers);
    }

    const { error: rpcErr } = await admin.rpc("set_smtp_password", { p_password: cfg.password });
    if (rpcErr) {
      return json({ error: "Could not store SMTP credential" }, 500, headers);
    }

    return json({
      ok: true,
      message: "SMTP configuration saved. Credential stored securely.",
    }, 200, headers);
  }
  // ------------------------------------------------------------------
  // ACTION: remove — delete the stored SMTP password from Vault
  // (remove_smtp_password() is service_role-only; caller is verified admin)
  // ------------------------------------------------------------------
  if (action === "remove") {
    const { error: rmErr } = await admin.rpc("remove_smtp_password");
    if (rmErr) {
      return json({ error: "Could not remove SMTP credential" }, 500, headers);
    }
    return json({ ok: true, message: "SMTP credential removed." }, 200, headers);
  }

  // ------------------------------------------------------------------
  // ACTION: test — test SMTP connectivity (no email sent)
  // ------------------------------------------------------------------
  if (action === "test") {
    const cfg: SmtpConfig = {
      host: typeof body.host === "string" ? body.host.trim() : undefined,
      port: typeof body.port === "number" ? body.port : undefined,
      secure: typeof body.secure === "boolean" ? body.secure : undefined,
      username: typeof body.username === "string" ? body.username.trim() : undefined,
      password: typeof body.password === "string" ? body.password : undefined,
    };

    if (!cfg.host || !cfg.port || cfg.secure === undefined || !cfg.username || !cfg.password) {
      return json({ error: "SMTP host, port, encryption, username and password are required" }, 400, headers);
    }

    const transport = buildTransport(cfg);
    try {
      await transport.verify();
      await admin
        .from("app_settings")
        .update({
          smtp_last_test_at: new Date().toISOString(),
          smtp_last_test_result: "success",
          smtp_last_test_error: null,
        })
        .eq("id", true);
      return json({ ok: true, message: "SMTP connection successful" }, 200, headers);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("smtp test failed", msg.slice(0, 200));
      await admin
        .from("app_settings")
        .update({
          smtp_last_test_at: new Date().toISOString(),
          smtp_last_test_result: "failed",
          smtp_last_test_error: msg.slice(0, 500),
        })
        .eq("id", true);
      return json({ error: "SMTP connection test failed" }, 502, headers);
    }
  }

  // ------------------------------------------------------------------
  // ACTION: send_test — send a test email (requires explicit confirmation)
  // ------------------------------------------------------------------
  if (action === "send_test") {
    const confirmed = body.confirm === true;
    if (!confirmed) {
      return json({ error: "Explicit confirmation required to send test email" }, 400, headers);
    }

    const cfg: SmtpConfig = {
      host: typeof body.host === "string" ? body.host.trim() : undefined,
      port: typeof body.port === "number" ? body.port : undefined,
      secure: typeof body.secure === "boolean" ? body.secure : undefined,
      username: typeof body.username === "string" ? body.username.trim() : undefined,
      password: typeof body.password === "string" ? body.password : undefined,
      sender_name: typeof body.sender_name === "string" ? body.sender_name.trim() : undefined,
      sender_email: typeof body.sender_email === "string" ? body.sender_email.trim() : undefined,
    };

    if (!cfg.host || !cfg.port || cfg.secure === undefined || !cfg.username || !cfg.password || !cfg.sender_email) {
      return json({ error: "Incomplete SMTP configuration" }, 400, headers);
    }

    const recipient = typeof body.recipient === "string" ? body.recipient.trim() : undefined;
    if (!recipient || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipient)) {
      return json({ error: "A valid recipient email is required" }, 400, headers);
    }

    const transport = buildTransport(cfg);
    const from = `"${cfg.sender_name ?? "ITSR Radiant Group Duri"}" <${cfg.sender_email}>`;

    try {
      const info = await transport.sendMail({
        from,
        to: recipient,
        subject: "[ITSR] Test Email",
        text: "This is a test email from ITSR Radiant Group Duri SMTP configuration.",
        html: "<p>This is a test email from <b>ITSR Radiant Group Duri</b> SMTP configuration.</p>",
      });
      await admin
        .from("app_settings")
        .update({
          smtp_last_successful_email_at: new Date().toISOString(),
        })
        .eq("id", true);
      return json({ ok: true, messageId: info.messageId }, 200, headers);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("smtp test email failed", msg.slice(0, 200));
      await admin
        .from("app_settings")
        .update({
          smtp_last_failed_email_at: new Date().toISOString(),
        })
        .eq("id", true);
      return json({ error: "Test email could not be sent" }, 502, headers);
    }
  }

  return json({ error: `Unknown action: ${action}` }, 400, headers);
});