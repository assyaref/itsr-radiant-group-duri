// Pure notification rules: who receives which email for which ticket event.
// No I/O here so it can be unit-tested. Addresses come ONLY from the database
// (profiles + app_settings) — nothing is invented or hard-coded.
import { EMAIL_RE, escapeHtml } from "./http.ts";

export type EventType = "ticket_created" | "ticket_assigned" | "status_changed" | "comment_added";

export interface Person { id: string; full_name: string; email: string; is_active?: boolean }
export interface TicketInfo {
  id: string; ticket_number: string; subject: string; description: string;
  category: string; priority: string; status: string; resolution: string | null;
  reporter: Person; assignee: Person | null;
}
export interface Settings {
  it_support_group_email: string | null;
  manager_email: string | null;
  app_base_url: string | null;
}
export interface EventContext {
  event: EventType;
  payload: Record<string, unknown>;
  ticket: TicketInfo;
  actor: Person | null;
  comment: { content: string } | null;
  activeItStaff: Person[];
}
export interface Email { to: string[]; cc: string[]; subject: string; text: string; html: string }

const STATUS_LABEL: Record<string, string> = {
  open: "Menunggu", assigned: "Ditugaskan", in_progress: "Diproses", pending_user: "Butuh Respons Anda",
  resolved: "Selesai", closed: "Ditutup", reopened: "Dibuka Ulang",
};
export const statusLabel = (s: string) => STATUS_LABEL[s] ?? s;

const PRIORITY_LABEL: Record<string, string> = { low: "Low", medium: "Medium", high: "High", critical: "Critical" };
const priorityLabel = (p: string) => PRIORITY_LABEL[p] ?? p;

const PRIORITY_COLOR: Record<string, string> = { low: "#16a34a", medium: "#d97706", high: "#dc2626", critical: "#b91c1c" };
const STATUS_COLOR: Record<string, string> = {
  open: "#7c3aed", assigned: "#2563eb", in_progress: "#2563eb", pending_user: "#d97706",
  resolved: "#16a34a", closed: "#64748b", reopened: "#dc2626",
};

function clean(list: (string | null | undefined)[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of list) {
    const e = (raw ?? "").trim().toLowerCase();
    if (e && EMAIL_RE.test(e) && !seen.has(e)) { seen.add(e); out.push(e); }
  }
  return out;
}

/** Escaped text with line breaks kept (for multi-line user content). */
const multiline = (s: string) => escapeHtml(s).replace(/\r?\n/g, "<br>");

const pill = (label: string, color: string) =>
  `<span style="display:inline-block;padding:3px 10px;border-radius:12px;background:${color}1a;` +
  `color:${color};font-size:12px;font-weight:bold;border:1px solid ${color}55">${escapeHtml(label)}</span>`;

/** One "form field": grey label cell + white value cell, both boxed. */
const field = (label: string, valueHtml: string) =>
  `<tr><td style="width:34%;padding:10px 12px;background:#f8fafc;border:1px solid #e2e8f0;` +
  `color:#64748b;font-size:13px;vertical-align:top">${escapeHtml(label)}</td>` +
  `<td style="padding:10px 12px;border:1px solid #e2e8f0;color:#0f172a;font-size:14px;font-weight:600;` +
  `vertical-align:top">${valueHtml}</td></tr>`;

/** A titled box for long text (description, comment, resolution). */
const section = (title: string, bodyHtml: string, accent = "#2563eb") =>
  `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin-top:16px">` +
  `<tr><td style="padding:8px 12px;background:${accent};color:#ffffff;font-size:13px;font-weight:bold;` +
  `border:1px solid ${accent}">${escapeHtml(title)}</td></tr>` +
  `<tr><td style="padding:12px;border:1px solid #e2e8f0;color:#334155;font-size:14px;line-height:1.5">${bodyHtml}</td></tr>` +
  `</table>`;

/** Returns null when there is nobody to notify. */
export function buildEmail(ctx: EventContext, settings: Settings): Email | null {
  const { ticket: t, actor } = ctx;
  const group = settings.it_support_group_email;
  const manager = settings.manager_email;
  let to: string[] = [];
  let headline = "";
  let intro = "";

  switch (ctx.event) {
    case "ticket_created": {
      const staff = ctx.activeItStaff.map((p) => p.email);
      to = clean(staff.length ? staff : [group]);
      headline = "Tiket Baru";
      intro = `${t.reporter.full_name} mengajukan tiket baru. Mohon segera ditindaklanjuti.`;
      break;
    }
    case "ticket_assigned": {
      to = clean([t.assignee?.email]);
      headline = "Tiket Ditugaskan";
      intro = `Tiket ini ditugaskan kepada ${t.assignee?.full_name ?? "IT Support"}.`;
      break;
    }
    case "status_changed": {
      to = clean([t.reporter.email]);
      const from = statusLabel(String(ctx.payload.old_status ?? ""));
      const toS = statusLabel(String(ctx.payload.new_status ?? t.status));
      headline = `Status Diperbarui: ${from} → ${toS}`;
      intro = `Status tiket Anda diubah dari "${from}" menjadi "${toS}"` +
        (actor?.full_name ? ` oleh ${actor.full_name}.` : ".");
      break;
    }
    case "comment_added": {
      const byReporter = actor?.id === t.reporter.id;
      to = byReporter ? clean([t.assignee?.email ?? group]) : clean([t.reporter.email]);
      headline = "Komentar Baru";
      intro = `${actor?.full_name ?? "Pengguna"} menambahkan komentar pada tiket ini.`;
      break;
    }
  }

  // Never email the person who performed the action about their own action
  // (except a new-ticket confirmation, which goes to IT, not the reporter).
  if (actor?.email) to = to.filter((e) => e !== actor.email.toLowerCase());

  const cc = clean([group, manager]).filter((e) => !to.includes(e));
  if (to.length === 0 && cc.length === 0) return null;
  if (to.length === 0) { to = [cc.shift()!]; }

  const subject = `[${t.ticket_number}] ${headline}: ${t.subject}`.slice(0, 250);
  const link = settings.app_base_url
    ? `${settings.app_base_url.replace(/\/+$/, "")}/#/tickets/${t.id}`
    : null;

  // ---- plain-text part (for clients without HTML) -------------------------
  const row = (label: string, value: string) => `${(label + ":").padEnd(14)}${value}`;
  const lines = [
    headline,
    intro,
    "",
    "----------------------------------------",
    row("No. Tiket", t.ticket_number),
    row("Judul", t.subject),
    row("Status", statusLabel(t.status)),
    row("Prioritas", priorityLabel(t.priority)),
    row("Kategori", t.category),
    row("Pelapor", t.reporter.full_name),
    row("Ditangani", t.assignee?.full_name ?? "Belum ditugaskan"),
    "----------------------------------------",
  ];
  if (ctx.event === "ticket_created") lines.push("", "Deskripsi:", t.description);
  if (ctx.comment) lines.push("", `Komentar dari ${actor?.full_name ?? "pengguna"}:`, ctx.comment.content);
  if (t.status === "resolved" && t.resolution) lines.push("", "Penyelesaian:", t.resolution);
  if (link) lines.push("", `Buka tiket: ${link}`);
  lines.push("", "-- ITSR Radiant Group Duri - IT Support & Service Request",
    "Email otomatis, mohon tidak membalas email ini.");
  const text = lines.join("\n");

  // ---- HTML part: boxed "form" layout, table-based for email clients ------
  const statusColor = STATUS_COLOR[t.status] ?? "#64748b";
  const prioColor = PRIORITY_COLOR[t.priority] ?? "#64748b";
  const html =
    `<!DOCTYPE html><html><body style="margin:0;padding:0;background:#f1f5f9">` +
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9;padding:24px 12px">` +
    `<tr><td align="center">` +
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#ffffff;` +
    `border:1px solid #e2e8f0;border-radius:10px;font-family:Arial,Helvetica,sans-serif">` +
    // header
    `<tr><td style="background:#2563eb;padding:18px 24px;border-radius:10px 10px 0 0">` +
    `<div style="color:#dbeafe;font-size:12px;letter-spacing:.5px">IT SUPPORT &amp; SERVICE REQUEST · CABANG DURI</div>` +
    `<div style="color:#ffffff;font-size:20px;font-weight:bold;margin-top:4px">${escapeHtml(headline)}</div>` +
    `</td></tr>` +
    // body
    `<tr><td style="padding:20px 24px">` +
    `<p style="margin:0 0 16px;color:#334155;font-size:14px;line-height:1.5">${escapeHtml(intro)}</p>` +
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse">` +
    `<tr><td colspan="2" style="padding:8px 12px;background:#0f172a;color:#ffffff;font-size:13px;font-weight:bold;` +
    `border:1px solid #0f172a">Informasi Tiket</td></tr>` +
    field("No. Tiket", `<span style="color:#2563eb">${escapeHtml(t.ticket_number)}</span>`) +
    field("Judul", escapeHtml(t.subject)) +
    field("Status", pill(statusLabel(t.status), statusColor)) +
    field("Prioritas", pill(priorityLabel(t.priority), prioColor)) +
    field("Kategori", escapeHtml(t.category)) +
    field("Pelapor", escapeHtml(t.reporter.full_name)) +
    field("Ditangani oleh", escapeHtml(t.assignee?.full_name ?? "Belum ditugaskan")) +
    `</table>` +
    (ctx.event === "ticket_created" ? section("Deskripsi Masalah", multiline(t.description)) : "") +
    (ctx.comment
      ? section(`Komentar dari ${actor?.full_name ?? "pengguna"}`, multiline(ctx.comment.content), "#0d9488")
      : "") +
    (t.status === "resolved" && t.resolution ? section("Penyelesaian", multiline(t.resolution), "#16a34a") : "") +
    (link
      ? `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:22px 0 4px"><tr>` +
        `<td style="background:#2563eb;border-radius:8px"><a href="${escapeHtml(link)}" ` +
        `style="display:inline-block;padding:12px 22px;color:#ffffff;font-size:14px;font-weight:bold;` +
        `text-decoration:none">Buka Tiket</a></td></tr></table>`
      : "") +
    `</td></tr>` +
    // footer
    `<tr><td style="padding:14px 24px;border-top:1px solid #e2e8f0;color:#94a3b8;font-size:12px;line-height:1.5">` +
    `ITSR Radiant Group Duri – IT Support &amp; Service Request.<br>` +
    `Email ini dikirim otomatis, mohon tidak membalas email ini.</td></tr>` +
    `</table></td></tr></table></body></html>`;

  return { to, cc, subject, text, html };
}
