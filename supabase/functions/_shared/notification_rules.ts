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
  /** Files sent with this event (chat message or new report). Images with a
   *  `cid` are shown inline in the HTML body; the rest are listed by name. */
  files?: EmailFile[];
}
export interface EmailFile { file_name: string; mime_type: string; cid: string | null }
export interface Email { to: string[]; cc: string[]; subject: string; text: string; html: string }

const STATUS_LABEL: Record<string, string> = {
  open: "Open", assigned: "Assigned", in_progress: "In Progress", pending_user: "Waiting for you",
  resolved: "Resolved", closed: "Closed", reopened: "Reopened",
};
export const statusLabel = (s: string) => STATUS_LABEL[s] ?? s;

function clean(list: (string | null | undefined)[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of list) {
    const e = (raw ?? "").trim().toLowerCase();
    if (e && EMAIL_RE.test(e) && !seen.has(e)) { seen.add(e); out.push(e); }
  }
  return out;
}

/** Returns null when there is nobody to notify. */
export function buildEmail(ctx: EventContext, settings: Settings): Email | null {
  const { ticket: t, actor } = ctx;
  const group = settings.it_support_group_email;
  const manager = settings.manager_email;
  let to: string[] = [];
  let headline = "";

  switch (ctx.event) {
    case "ticket_created": {
      const staff = ctx.activeItStaff.map((p) => p.email);
      to = clean(staff.length ? staff : [group]);
      headline = `New ticket from ${t.reporter.full_name}`;
      break;
    }
    case "ticket_assigned": {
      to = clean([t.assignee?.email]);
      headline = `Ticket assigned to ${t.assignee?.full_name ?? "IT Support"}`;
      break;
    }
    case "status_changed": {
      to = clean([t.reporter.email]);
      const from = statusLabel(String(ctx.payload.old_status ?? ""));
      const toS = statusLabel(String(ctx.payload.new_status ?? t.status));
      headline = `Status changed: ${from} → ${toS}`;
      break;
    }
    case "comment_added": {
      const byReporter = actor?.id === t.reporter.id;
      to = byReporter ? clean([t.assignee?.email ?? group]) : clean([t.reporter.email]);
      const who = actor?.full_name ?? "a user";
      const files = ctx.files ?? [];
      headline = ctx.comment || files.length === 0
        ? `New comment from ${who}`
        : files.every((f) => f.mime_type.startsWith("image/"))
        ? `New image from ${who}`
        : `New attachment from ${who}`;
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

  const lines = [
    headline,
    "",
    `Ticket:    ${t.ticket_number}`,
    `Subject:   ${t.subject}`,
    `Status:    ${statusLabel(t.status)}`,
    `Priority:  ${t.priority}`,
    `Category:  ${t.category}`,
    `Reporter:  ${t.reporter.full_name}`,
    `Assignee:  ${t.assignee?.full_name ?? "Unassigned"}`,
  ];
  if (ctx.event === "ticket_created") lines.push("", "Description:", t.description);
  if (ctx.comment) lines.push("", "Comment:", ctx.comment.content);
  const files = ctx.files ?? [];
  if (files.length) {
    lines.push("", "Attachments:", ...files.map((f) => `- ${f.file_name}`));
  }
  if (t.status === "resolved" && t.resolution) lines.push("", "Resolution:", t.resolution);
  if (link) lines.push("", `Open ticket: ${link}`);
  lines.push("", "— ITSR Radiant Group Duri (automated message, please do not reply)");
  const text = lines.join("\n");

  const images = files.filter((f) => f.cid && f.mime_type.startsWith("image/"));
  const imageHtml = images.map((f) =>
    `<div style="margin:12px 0">` +
    `<img src="cid:${escapeHtml(f.cid!)}" alt="${escapeHtml(f.file_name)}" ` +
    `style="max-width:100%;width:560px;height:auto;border:1px solid #e5e7eb;border-radius:8px">` +
    `<div style="font-size:12px;color:#6b7280">${escapeHtml(f.file_name)}</div></div>`
  ).join("");
  const html = `<div style="font-family:Arial,sans-serif;font-size:14px;color:#1f2937">` +
    `<pre style="font-family:inherit;white-space:pre-wrap">${escapeHtml(text)}</pre>${imageHtml}</div>`;

  return { to, cc, subject, text, html };
}
