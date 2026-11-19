// Ticket attachments stored in a Google Drive folder.
//
// Actions (POST JSON, caller = signed-in active user):
//   { action: "upload", ticket_id, file_name, data_base64 }  -> attachment row
//   { action: "download", attachment_id }                     -> file bytes
//   { action: "delete", attachment_id }                       -> { ok: true }
//
// Who may upload / download: IT Support and administrators for any ticket;
// employees only for tickets they reported. Upload is refused on closed
// tickets for employees. Files are checked by their real content (JPG, PNG,
// PDF only, max 10 MB, max 10 per ticket).
// Who may delete: the uploader, or an administrator / superadmin. Employees
// cannot delete on closed tickets. The Drive file is removed with the row.
//
// Drive access uses OAuth with the folder owner's refresh token (a service
// account cannot store files in a personal "My Drive" folder: it has no
// storage quota). Required Supabase secrets:
//   GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET,
//   GOOGLE_OAUTH_REFRESH_TOKEN, GOOGLE_DRIVE_FOLDER_ID
// Downloads are proxied here, so the Drive folder does not need link sharing.
import { bearerToken, corsHeaders, json, readJsonObject, withErrorBoundary } from "../_shared/http.ts";
import { adminClient, type CallerProfile, verifyCaller } from "../_shared/supabase.ts";
import { checkUpload, driveMultipart, MAX_ATTACHMENTS_PER_TICKET } from "../_shared/attachments.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_REQUEST = 15 * 1024 * 1024; // base64 of 10 MB + JSON

interface DriveConfig { clientId: string; clientSecret: string; refreshToken: string; folderId: string }

function driveConfig(): DriveConfig | null {
  const clientId = Deno.env.get("GOOGLE_OAUTH_CLIENT_ID");
  const clientSecret = Deno.env.get("GOOGLE_OAUTH_CLIENT_SECRET");
  const refreshToken = Deno.env.get("GOOGLE_OAUTH_REFRESH_TOKEN");
  const folderId = Deno.env.get("GOOGLE_DRIVE_FOLDER_ID");
  if (!clientId || !clientSecret || !refreshToken || !folderId) return null;
  return { clientId, clientSecret, refreshToken, folderId };
}

async function driveToken(cfg: DriveConfig): Promise<string> {
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: cfg.clientId,
      client_secret: cfg.clientSecret,
      refresh_token: cfg.refreshToken,
      grant_type: "refresh_token",
    }),
    signal: AbortSignal.timeout(15_000),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || typeof data.access_token !== "string") {
    throw new Error(`google token refresh failed (${res.status} ${data.error ?? ""})`);
  }
  return data.access_token;
}

const isStaff = (c: CallerProfile) =>
  c.role === "it_support" || c.role === "administrator" || c.role === "superadmin";
const isAdmin = (c: CallerProfile) => c.role === "administrator" || c.role === "superadmin";

Deno.serve(withErrorBoundary("attachments", async (req) => {
  const headers = corsHeaders(req.headers.get("origin"), Deno.env.get("ALLOWED_ORIGINS"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);

  const admin = adminClient();
  const caller = await verifyCaller(admin, bearerToken(req));
  if (!caller) return json({ error: "Not authenticated" }, 401, headers);

  const body = await readJsonObject(req, MAX_REQUEST);
  if (!body) return json({ error: "Invalid request (file too large or not JSON)" }, 400, headers);

  const cfg = driveConfig();
  if (!cfg) {
    return json({ error: "Penyimpanan lampiran belum dikonfigurasi. Hubungi administrator." }, 503, headers);
  }

  // Same answer for "missing" and "not yours": no existence oracle.
  async function loadTicket(id: unknown) {
    if (typeof id !== "string" || !UUID_RE.test(id)) return null;
    const { data } = await admin.from("tickets").select("id, ticket_number, reporter_id, status")
      .eq("id", id).maybeSingle();
    if (!data) return null;
    if (!isStaff(caller!) && data.reporter_id !== caller!.id) return null;
    return data as { id: string; ticket_number: string; reporter_id: string; status: string };
  }

  if (body.action === "upload") {
    const ticket = await loadTicket(body.ticket_id);
    if (!ticket) return json({ error: "Ticket not found" }, 404, headers);
    if (!isStaff(caller) && ticket.status === "closed") {
      return json({ error: "Tiket sudah ditutup" }, 400, headers);
    }
    const check = checkUpload(body.file_name, body.data_base64);
    if (!check.ok) return json({ error: check.error }, 400, headers);

    const { count } = await admin.from("ticket_attachments").select("id", { count: "exact", head: true })
      .eq("ticket_id", ticket.id);
    if ((count ?? 0) >= MAX_ATTACHMENTS_PER_TICKET) {
      return json({ error: `Maksimal ${MAX_ATTACHMENTS_PER_TICKET} lampiran per tiket` }, 400, headers);
    }

    const token = await driveToken(cfg);
    const stamp = new Date().toISOString().replace(/[-:]/g, "").slice(0, 15);
    const { body: payload, contentType } = driveMultipart(
      { name: `${ticket.ticket_number}_${stamp}_${check.name}`, parents: [cfg.folderId], mimeType: check.mime },
      check.bytes,
      check.mime,
    );
    const up = await fetch(
      "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id",
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": contentType },
        body: new Blob([payload]),
        signal: AbortSignal.timeout(60_000),
      },
    );
    const upData = await up.json().catch(() => ({}));
    if (!up.ok || typeof upData.id !== "string") {
      console.error("drive upload failed", up.status, JSON.stringify(upData).slice(0, 300));
      return json({ error: "Upload ke Google Drive gagal. Coba lagi nanti." }, 502, headers);
    }

    const { data: row, error: insErr } = await admin.from("ticket_attachments").insert({
      ticket_id: ticket.id,
      uploaded_by: caller.id,
      file_name: check.name,
      mime_type: check.mime,
      size_bytes: check.bytes.length,
      drive_file_id: upData.id,
    }).select("id, ticket_id, uploaded_by, file_name, mime_type, size_bytes, created_at").single();
    if (insErr) {
      // Do not leave an orphan file behind.
      await fetch(
        `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(upData.id)}?supportsAllDrives=true`,
        { method: "DELETE", headers: { Authorization: `Bearer ${token}` } },
      ).catch(() => {});
      console.error("attachment insert failed", insErr.message);
      return json({ error: "Could not save the attachment" }, 500, headers);
    }
    return json(row, 201, headers);
  }

  if (body.action === "download") {
    const id = body.attachment_id;
    if (typeof id !== "string" || !UUID_RE.test(id)) return json({ error: "Invalid attachment id" }, 400, headers);
    const { data: att } = await admin.from("ticket_attachments")
      .select("id, ticket_id, file_name, mime_type, drive_file_id").eq("id", id).maybeSingle();
    if (!att || !(await loadTicket(att.ticket_id))) return json({ error: "Attachment not found" }, 404, headers);

    const token = await driveToken(cfg);
    const res = await fetch(
      `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(att.drive_file_id)}?alt=media&supportsAllDrives=true`,
      { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(60_000) },
    );
    if (!res.ok) {
      console.error("drive download failed", res.status);
      return json({ error: "File tidak dapat diambil dari Google Drive" }, 502, headers);
    }
    const out = new Headers(headers);
    out.set("Content-Type", "application/octet-stream");
    out.set("Content-Disposition", `attachment; filename="${String(att.file_name).replace(/"/g, "")}"`);
    out.set("Cache-Control", "no-store");
    return new Response(res.body, { status: 200, headers: out });
  }

  if (body.action === "delete") {
    const id = body.attachment_id;
    if (typeof id !== "string" || !UUID_RE.test(id)) return json({ error: "Invalid attachment id" }, 400, headers);
    const { data: att } = await admin.from("ticket_attachments")
      .select("id, ticket_id, uploaded_by, drive_file_id").eq("id", id).maybeSingle();
    const ticket = att ? await loadTicket(att.ticket_id) : null;
    // Same answer for "missing" and "not yours".
    if (!att || !ticket || (att.uploaded_by !== caller.id && !isAdmin(caller))) {
      return json({ error: "Attachment not found" }, 404, headers);
    }
    if (!isStaff(caller) && ticket.status === "closed") {
      return json({ error: "Tiket sudah ditutup" }, 400, headers);
    }

    const token = await driveToken(cfg);
    const del = await fetch(
      `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(att.drive_file_id)}?supportsAllDrives=true`,
      { method: "DELETE", headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(30_000) },
    );
    // 404: already gone from Drive; still remove the row.
    if (!del.ok && del.status !== 404) {
      console.error("drive delete failed", del.status);
      return json({ error: "Gagal menghapus file di Google Drive. Coba lagi nanti." }, 502, headers);
    }
    const { error: delErr } = await admin.from("ticket_attachments").delete().eq("id", att.id);
    if (delErr) {
      console.error("attachment row delete failed", delErr.message);
      return json({ error: "Could not delete the attachment" }, 500, headers);
    }
    return json({ ok: true }, 200, headers);
  }

  return json({ error: "Unknown action" }, 400, headers);
}));
