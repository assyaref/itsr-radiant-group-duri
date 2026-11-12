import { assert, assertEquals } from "jsr:@std/assert@1.0.13";
import { clientIp, corsHeaders, escapeHtml, isValidHost, normalizeEmployeeNumber, parsePort, readJsonObject, withErrorBoundary } from "../_shared/http.ts";
import { buildEmail, type EventContext, type Settings } from "../_shared/notification_rules.ts";
import { validateCreate, validateResetPassword, validateUpdate } from "../admin-users/validation.ts";
import { authPassword, isPin, newPasswordError, plausibleLoginPassword } from "../_shared/password.ts";

Deno.test("PIN policy: 4-5 digit PINs or 8+ character passwords", () => {
  assert(isPin("1234") && isPin("12345"));
  assert(!isPin("123") && !isPin("123456") && !isPin("12a4"));
  assertEquals(newPasswordError("1234"), null);
  assertEquals(newPasswordError("54321"), null);
  assertEquals(newPasswordError("longenough"), null);
  assert(newPasswordError("123") !== null);
  assert(newPasswordError("123456") !== null);
  assert(newPasswordError("short") !== null);
  assert(plausibleLoginPassword("1234") && plausibleLoginPassword("legacy6"));
  assert(!plausibleLoginPassword("12") && !plausibleLoginPassword("abc"));
});

Deno.test("PIN is HMAC-derived for Supabase Auth; passwords pass through", async () => {
  const pepper = "p".repeat(32);
  const a = await authPassword("1234", pepper);
  assert(a.startsWith("pin1.") && a.length > 40, "long derived secret");
  assertEquals(a, await authPassword("1234", pepper), "deterministic");
  assert(a !== await authPassword("1235", pepper));
  assert(a !== await authPassword("1234", "q".repeat(32)), "depends on the pepper");
  assertEquals(await authPassword("longenough", undefined), "longenough");
  let threw = false;
  try { await authPassword("1234", undefined); } catch { threw = true; }
  assert(threw, "PINs refused without PIN_PEPPER");
});

Deno.test("employee number normalisation", () => {
  assertEquals(normalizeEmployeeNumber(" emp001 "), "EMP001");
  assertEquals(normalizeEmployeeNumber("EMP 001"), null);
  assertEquals(normalizeEmployeeNumber("E"), null);
  assertEquals(normalizeEmployeeNumber("emp'; drop"), null);
  assertEquals(normalizeEmployeeNumber(42), null);
});

Deno.test("CORS: allow-list echoes only listed origins", () => {
  assertEquals(corsHeaders("https://a.test", "https://a.test,https://b.test").get("Access-Control-Allow-Origin"), "https://a.test");
  assertEquals(corsHeaders("https://evil.test", "https://a.test").get("Access-Control-Allow-Origin"), null);
});

Deno.test("CORS: fail-closed when ALLOWED_ORIGINS is unset, empty or wildcard", () => {
  const acao = (o: string | null, a: string | undefined) => corsHeaders(o, a).get("Access-Control-Allow-Origin");
  assertEquals(acao("https://x.test", undefined), null);
  assertEquals(acao("https://x.test", ""), null);
  assertEquals(acao("https://x.test", " , "), null);
  assertEquals(acao("https://x.test", "*"), null);
  assertEquals(acao("*", "*"), null);
  assertEquals(acao(null, "https://a.test"), null);
  assertEquals(acao("https://a.test", "*, https://a.test"), "https://a.test");
});

Deno.test("client IP takes first X-Forwarded-For hop", () => {
  const r = new Request("http://x", { headers: { "x-forwarded-for": "203.0.113.7, 10.0.0.1" } });
  assertEquals(clientIp(r), "203.0.113.7");
  assertEquals(clientIp(new Request("http://x")), "unknown");
});

Deno.test("HTML escaping", () => {
  assertEquals(escapeHtml(`<script>"x"&'y'</script>`), "&lt;script&gt;&quot;x&quot;&amp;&#39;y&#39;&lt;/script&gt;");
});

const reporter = { id: "r", full_name: "Rina Reporter", email: "rina@example.test" };
const tech = { id: "t", full_name: "Tono Tech", email: "tono@example.test" };
const ticket = {
  id: "tid", ticket_number: "ITSR-00007", subject: "VPN down", description: "Cannot connect",
  category: "Network", priority: "high", status: "open", resolution: null, reporter, assignee: null,
};
const settings: Settings = { it_support_group_email: "it-group@example.test", manager_email: "mgr@example.test", app_base_url: "https://itsr.example.test/" };
const ctx = (o: Partial<EventContext>): EventContext => ({
  event: "ticket_created", payload: {}, ticket, actor: reporter, comment: null, activeItStaff: [tech], ...o,
});

Deno.test("new ticket -> IT staff, CC group + manager, link built", () => {
  const e = buildEmail(ctx({}), settings)!;
  assertEquals(e.to, ["tono@example.test"]);
  assertEquals(e.cc, ["it-group@example.test", "mgr@example.test"]);
  assert(e.subject.startsWith("[ITSR-00007]"));
  assert(e.text.includes("https://itsr.example.test/#/tickets/tid"));
});

Deno.test("new ticket with no IT staff falls back to group address", () => {
  const e = buildEmail(ctx({ activeItStaff: [] }), settings)!;
  assertEquals(e.to, ["it-group@example.test"]);
  assertEquals(e.cc, ["mgr@example.test"]);
});

Deno.test("status change -> reporter; actor not emailed about own action", () => {
  const e = buildEmail(ctx({ event: "status_changed", actor: tech, payload: { old_status: "open", new_status: "in_progress" },
    ticket: { ...ticket, status: "in_progress", assignee: tech } }), settings)!;
  assertEquals(e.to, ["rina@example.test"]);
  assert(e.subject.includes("Menunggu → Diproses"));
});

Deno.test("comment by reporter -> assignee; by tech -> reporter", () => {
  const t2 = { ...ticket, assignee: tech };
  assertEquals(buildEmail(ctx({ event: "comment_added", actor: reporter, ticket: t2, comment: { content: "hi" } }), settings)!.to, ["tono@example.test"]);
  assertEquals(buildEmail(ctx({ event: "comment_added", actor: tech, ticket: t2, comment: { content: "hi" } }), settings)!.to, ["rina@example.test"]);
});

Deno.test("no configured addresses and no recipients -> null (nothing invented)", () => {
  const none: Settings = { it_support_group_email: null, manager_email: null, app_base_url: null };
  assertEquals(buildEmail(ctx({ activeItStaff: [] }), none), null);
});

Deno.test("HTML email is a boxed form with Indonesian labels and a button", () => {
  const e = buildEmail(ctx({}), settings)!;
  for (const label of ["Informasi Tiket", "No. Tiket", "Judul", "Status", "Prioritas", "Kategori", "Pelapor",
                       "Ditangani oleh", "Deskripsi Masalah", "Buka Tiket"]) {
    assert(e.html.includes(label), `missing ${label}`);
  }
  assert(e.html.includes("border:1px solid #e2e8f0"), "boxed cells");
  assert(e.html.includes('href="https://itsr.example.test/#/tickets/tid"'));
  assert(e.text.includes("No. Tiket:    ITSR-00007"));
  assert(e.html.includes("Sistem developed by"), "developer credit");
  assert(e.html.includes('href="https://api.whatsapp.com/send?phone=6282167472765&amp;text=Haii%20..%F0%9F%91%8B"'));
  assert(e.text.includes("Sistem developed by Assyaref.dev"));
});

Deno.test("user-supplied content is escaped in HTML body", () => {
  const e = buildEmail(ctx({ ticket: { ...ticket, description: "<img src=x onerror=alert(1)>" } }), settings)!;
  assert(!e.html.includes("<img"));
});

Deno.test("admin create validation", () => {
  const ok = validateCreate({ employee_number: "emp010", full_name: "New Person", email: "New@Example.test", role: "employee", password: "longenough" });
  assert(ok.ok && ok.value.employee_number === "EMP010" && ok.value.email === "new@example.test");
  assert(!validateCreate({ employee_number: "EMP010", full_name: "x", email: "bad", role: "employee", password: "longenough" }).ok);
  assert(!validateCreate({ employee_number: "EMP010", full_name: "x", email: "a@b.co", role: "superuser", password: "longenough" }).ok);
  assert(!validateCreate({ employee_number: "EMP010", full_name: "x", email: "a@b.co", role: "employee", password: "short" }).ok);
  assert(validateCreate({ employee_number: "EMP010", full_name: "x", email: "a@b.co", role: "employee", password: "1234" }).ok, "4-digit PIN");
});

Deno.test("admin update validation", () => {
  assert(!validateUpdate({ user_id: "not-a-uuid", role: "employee" }).ok);
  assert(!validateUpdate({ user_id: "10000000-0000-0000-0000-000000000001" }).ok);
  const r = validateUpdate({ user_id: "10000000-0000-0000-0000-000000000001", role: "it_support", is_active: false });
  assert(r.ok && r.value.changes.role === "it_support" && r.value.changes.is_active === false);
  assert(!validateUpdate({ user_id: "10000000-0000-0000-0000-000000000001", is_active: "no" }).ok);
});

Deno.test("admin reset_password validation", () => {
  const id = "10000000-0000-0000-0000-000000000001";
  const ok = validateResetPassword({ user_id: id, password: "longenough" });
  assert(ok.ok && ok.value.user_id === id);
  assert(!validateResetPassword({ user_id: "", password: "longenough" }).ok);
  assert(!validateResetPassword({ user_id: "not-a-uuid", password: "longenough" }).ok);
  assert(!validateResetPassword({ user_id: id, password: "short" }).ok);
  assert(!validateResetPassword({ user_id: id, password: "x".repeat(129) }).ok);
  assert(!validateResetPassword({ user_id: id, password: 12345678 }).ok);
});

// ---- Phase 17: send-failure classification (retry vs give up) ----
import { classifySendError, describeSendError, PermanentError } from "../_shared/smtp_errors.ts";

Deno.test("send errors: SMTP 5xx recipient/message rejections are permanent", () => {
  assertEquals(classifySendError({ code: "EENVELOPE", responseCode: 550, message: "550 5.1.1 user unknown" }), "permanent");
  assertEquals(classifySendError({ code: "EMESSAGE", responseCode: 552 }), "permanent");
  assertEquals(classifySendError({ code: "EENVELOPE", message: "No recipients defined" }), "permanent");
  assertEquals(classifySendError(new PermanentError("ticket not found")), "permanent");
});

Deno.test("send errors: network, 4xx and auth problems are temporary (retried)", () => {
  assertEquals(classifySendError({ code: "ETIMEDOUT" }), "temporary");
  assertEquals(classifySendError({ code: "ECONNECTION", message: "connect ECONNREFUSED" }), "temporary");
  assertEquals(classifySendError({ code: "EENVELOPE", responseCode: 451 }), "temporary");
  assertEquals(classifySendError({ code: "EAUTH", responseCode: 535 }), "temporary");
  assertEquals(classifySendError({ responseCode: 534 }), "temporary");
  assertEquals(classifySendError(new Error("ticket lookup failed: timeout")), "temporary");
  assertEquals(classifySendError("weird"), "temporary");
  assertEquals(classifySendError(null), "temporary");
});

Deno.test("send errors: description is short and structured", () => {
  assertEquals(describeSendError({ code: "EENVELOPE", responseCode: 550, message: "rejected" }), "EENVELOPE 550 rejected");
  assert(describeSendError({ message: "x".repeat(2000) }).length <= 500);
  assertEquals(describeSendError("plain"), "plain");
});

const post = (body: string) => new Request("https://x.test/f", { method: "POST", body });

Deno.test("readJsonObject: only plain JSON objects are accepted", async () => {
  assertEquals(await readJsonObject(post('{"a":1}')), { a: 1 });
  assertEquals(await readJsonObject(post("null")), null);
  assertEquals(await readJsonObject(post("[]")), null);
  assertEquals(await readJsonObject(post('"x"')), null);
  assertEquals(await readJsonObject(post("{bad")), null);
  assertEquals(await readJsonObject(post("")), null);
  assertEquals(await readJsonObject(post(JSON.stringify({ a: "x".repeat(100) })), 50), null);
});

Deno.test("parsePort: strict integer 1-65535", () => {
  assertEquals(parsePort(587), 587);
  assertEquals(parsePort("465"), 465);
  assertEquals(parsePort(0), null);
  assertEquals(parsePort(70000), null);
  assertEquals(parsePort(25.5), null);
  assertEquals(parsePort("abc"), null);
  assertEquals(parsePort(null), null);
});

Deno.test("isValidHost rejects schemes, paths and spaces", () => {
  assert(isValidHost("smtp.gmail.com"));
  assert(isValidHost("10.0.0.5"));
  assert(!isValidHost("https://smtp.gmail.com"));
  assert(!isValidHost("smtp.gmail.com/x"));
  assert(!isValidHost("smtp gmail.com"));
  assert(!isValidHost(""));
});

Deno.test("withErrorBoundary turns exceptions into JSON 500 with CORS", async () => {
  Deno.env.set("ALLOWED_ORIGINS", "https://app.test");
  const h = withErrorBoundary("t", () => { throw new Error("boom"); });
  const res = await h(new Request("https://x.test/f", { method: "POST", headers: { origin: "https://app.test" } }));
  assertEquals(res.status, 500);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "https://app.test");
  const body = await res.json();
  assert(!JSON.stringify(body).includes("boom"));
});

import { checkUpload, driveMultipart, sanitizeFileName, sniffMime } from "../_shared/attachments.ts";

Deno.test("attachments: type sniffing, size limit and safe names", () => {
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2]);
  const jpg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0]);
  const pdf = new TextEncoder().encode("%PDF-1.7 ...");
  assertEquals(sniffMime(png), "image/png");
  assertEquals(sniffMime(jpg), "image/jpeg");
  assertEquals(sniffMime(pdf), "application/pdf");
  assertEquals(sniffMime(new TextEncoder().encode("<html>")), null);
  const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
  const ok = checkUpload("../../etc/foto laptop.png", b64(png));
  assert(ok.ok && ok.name === "foto laptop.png" && ok.mime === "image/png");
  assert(!checkUpload("evil.exe", btoa("MZ....")).ok, "unknown content refused");
  assert(!checkUpload("x.png", "not base64!!").ok);
  assertEquals(sanitizeFileName("", "application/pdf"), "lampiran.pdf");
  assert(sanitizeFileName("a".repeat(300) + ".pdf", "application/pdf").endsWith(".pdf"));
  assert(sanitizeFileName("a".repeat(300) + ".pdf", "application/pdf").length <= 120);
});

Deno.test("attachments: Drive multipart body", () => {
  const { body, contentType } = driveMultipart({ name: "a.png" }, new Uint8Array([1, 2, 3]), "image/png", "B");
  assertEquals(contentType, "multipart/related; boundary=B");
  const text = new TextDecoder().decode(body);
  assert(text.startsWith("--B\r\nContent-Type: application/json"));
  assert(text.includes('{"name":"a.png"}'));
  assert(text.endsWith("\r\n--B--\r\n"));
});
