// ITSR backend authorization smoke test (no browser, no UI guards involved).
// Signs in the synthetic STG* accounts against STAGING and calls PostgREST /
// Edge Functions directly, asserting the BACKEND denies what each role must
// not do. Read-only: performs no writes that succeed (every write attempted is
// one that must be rejected) and never sends email. Never prints credentials.
//
// Usage: node rbac-smoke.mjs <out.json>
import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const REF = "yzjpttfwnvnuyxbdkidm";
const BASE = `https://${REF}.supabase.co`;
const dir = join(homedir(), ".itsr-staging");
const KEY = readFileSync(join(dir, "publishable-key"), "utf8").trim();
const accts = JSON.parse(readFileSync(join(dir, "test-accounts.json"), "utf8")).accounts;
const results = [];

async function token(a) {
  const r = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: KEY, "content-type": "application/json" },
    body: JSON.stringify({ email: a.email, password: a.password }),
  });
  const j = await r.json();
  if (!r.ok || !j.access_token) throw new Error(`sign-in failed for ${a.employee_number}: HTTP ${r.status}`);
  return j.access_token;
}
const hdr = (t) => ({ apikey: KEY, "content-type": "application/json", ...(t ? { authorization: `Bearer ${t}` } : {}) });
async function call(method, path, t, body) {
  const r = await fetch(`${BASE}${path}`, { method, headers: hdr(t), body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  let j = null; try { j = JSON.parse(text); } catch { /* not json */ }
  return { status: r.status, json: j, text: text.slice(0, 300) };
}
function check(id, name, pass, detail) {
  results.push({ id, name, result: pass ? "PASS" : "FAIL", detail });
  console.log(`${pass ? "PASS" : "FAIL"} ${id} ${name} — ${detail}`);
}
const denied = (s) => s === 401 || s === 403 || s === 404;

const tok = {
  employee: await token(accts.employee),
  technician: await token(accts.technician),
  admin: await token(accts.admin),
};

// --- smtp-config: administrator only -----------------------------------------
for (const [who, t] of [["anonymous", null], ["employee", tok.employee], ["it_support", tok.technician]]) {
  const r = await call("POST", "/functions/v1/smtp-config", t, { action: "status" });
  check(`R01-${who}`, `${who} cannot read SMTP status`, r.status === 403, `HTTP ${r.status}`);
  const s = await call("POST", "/functions/v1/smtp-config", t,
    { action: "save", host: "smtp.invalid", port: 587, secure: false, username: "x@example.com", password: "not-a-secret", sender_email: "x@example.com" });
  check(`R02-${who}`, `${who} cannot save SMTP configuration`, s.status === 403, `HTTP ${s.status}`);
  const rm = await call("POST", "/functions/v1/smtp-config", t, { action: "remove" });
  check(`R03-${who}`, `${who} cannot remove SMTP credential`, rm.status === 403, `HTTP ${rm.status}`);
}
{
  const r = await call("POST", "/functions/v1/smtp-config", tok.admin, { action: "status" });
  const keys = r.json ? Object.keys(r.json) : [];
  const leaks = keys.filter((k) => /pass(word)?$|secret/i.test(k) && k !== "password_configured");
  check("R04", "administrator reads SMTP status; response has no password/secret field",
    r.status === 200 && leaks.length === 0 && r.json.password_configured === false,
    `HTTP ${r.status} password_configured=${r.json?.password_configured} smtp_host=${r.json?.smtp_host} it_support=${r.json?.it_support_group_email} manager=${r.json?.manager_email} keys=${keys.length}`);
}

// --- Vault RPCs are service_role only (even for administrators) --------------
for (const fn of ["get_smtp_password", "remove_smtp_password"]) {
  for (const [who, t] of [["anonymous", null], ["employee", tok.employee], ["admin", tok.admin]]) {
    const r = await call("POST", `/rest/v1/rpc/${fn}`, t, {});
    check(`R05-${fn}-${who}`, `${who} cannot execute ${fn}()`, denied(r.status), `HTTP ${r.status}`);
  }
}
{
  const r = await call("POST", "/rest/v1/rpc/set_smtp_password", tok.admin, { p_password: "not-a-secret" });
  check("R06", "administrator cannot execute set_smtp_password() directly", denied(r.status), `HTTP ${r.status}`);
}

// --- app_settings (holds SMTP host/username) visible to administrators only --
for (const [who, t] of [["employee", tok.employee], ["it_support", tok.technician]]) {
  const r = await call("GET", "/rest/v1/app_settings?select=*", t);
  check(`R07-${who}`, `${who} sees no app_settings rows (RLS)`, r.status === 200 && Array.isArray(r.json) && r.json.length === 0,
    `HTTP ${r.status} rows=${Array.isArray(r.json) ? r.json.length : "n/a"}`);
  const u = await call("PATCH", "/rest/v1/app_settings?id=eq.true", t, { smtp_host: "evil.invalid" });
  const after = await call("GET", "/rest/v1/app_settings?select=smtp_host", tok.admin);
  check(`R08-${who}`, `${who} cannot change app_settings`, after.json?.[0]?.smtp_host == null,
    `PATCH HTTP ${u.status}; smtp_host after = ${after.json?.[0]?.smtp_host ?? "null"}`);
}

// --- notification outbox is service-only -------------------------------------
for (const [who, t] of [["employee", tok.employee], ["admin", tok.admin]]) {
  const r = await call("GET", "/rest/v1/notification_outbox?select=id&limit=1", t);
  check(`R09-${who}`, `${who} cannot read notification_outbox`, denied(r.status) || (Array.isArray(r.json) && r.json.length === 0), `HTTP ${r.status}`);
}

// --- admin-users: administrator only -----------------------------------------
for (const [who, t] of [["employee", tok.employee], ["it_support", tok.technician]]) {
  const r = await call("POST", "/functions/v1/admin-users", t,
    { action: "update", user_id: "00000000-0000-0000-0000-000000000000", full_name: "x" });
  check(`R10-${who}`, `${who} cannot call admin-users`, r.status === 403, `HTTP ${r.status}`);
}

// --- tickets: employee sees only own -----------------------------------------
{
  const me = JSON.parse(Buffer.from(tok.employee.split(".")[1], "base64url").toString()).sub;
  const r = await call("GET", "/rest/v1/tickets?select=id,reporter_id", tok.employee);
  const foreign = (r.json ?? []).filter((x) => x.reporter_id !== me).length;
  check("R11", "employee sees only own tickets (RLS)", r.status === 200 && foreign === 0, `rows=${r.json?.length} foreign=${foreign}`);
  const all = await call("GET", "/rest/v1/tickets?select=id", tok.technician);
  check("R12", "IT Support sees the full ticket queue", all.status === 200 && all.json.length >= (r.json?.length ?? 0), `rows=${all.json?.length}`);
}

// --- send-notifications: unauthenticated rejected; SMTP unconfigured = 503 ---
{
  const r = await call("POST", "/functions/v1/send-notifications", null, {});
  check("R13", "send-notifications rejects unauthenticated callers", r.status === 401, `HTTP ${r.status}`);
  const a = await call("POST", "/functions/v1/send-notifications", tok.admin, {});
  check("R14", "send-notifications refuses to send while SMTP is not configured (nothing claimed)",
    a.status === 503, `HTTP ${a.status} ${a.text}`);
}

const pass = results.filter((r) => r.result === "PASS").length;
const out = { run: new Date().toISOString(), backend: `staging ${REF}`, summary: `${pass}/${results.length} PASS`, results };
writeFileSync(process.argv[2], JSON.stringify(out, null, 2));
console.log(out.summary);
