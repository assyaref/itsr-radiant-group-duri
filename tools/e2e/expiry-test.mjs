// Real-time session-expiry test against STAGING (synthetic STGEMP01 only).
// Never prints or writes tokens/passwords. Output: evidence JSON (results only).
import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const REF = "yzjpttfwnvnuyxbdkidm"; // staging only
const BASE = `https://${REF}.supabase.co`;
const OUT = process.argv[2];
const dir = join(homedir(), ".itsr-staging");
const acct = JSON.parse(readFileSync(join(dir, "test-accounts.json"), "utf8")).accounts.employee;
const key = readFileSync(join(dir, "publishable-key"), "utf8").trim();
const ev = { started_utc: new Date().toISOString(), account: acct.employee_number, steps: [] };
const save = () => writeFileSync(OUT, JSON.stringify(ev, null, 2));
const step = (name, pass, detail) => { ev.steps.push({ name, result: pass ? "PASS" : "FAIL", detail }); save(); };

const login = await fetch(`${BASE}/functions/v1/login`, {
  method: "POST",
  headers: { "content-type": "application/json", apikey: key },
  body: JSON.stringify({ employeeNumber: acct.employee_number, password: acct.password }),
});
const body = await login.json();
if (login.status !== 200 || !body.access_token) { step("login", false, { status: login.status }); process.exit(1); }
const token = body.access_token;
const claims = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString());
step("login", true, { status: 200, expires_in: body.expires_in, exp_minus_iat: claims.exp - claims.iat,
  exp_utc: new Date(claims.exp * 1000).toISOString() });

const rest = () => fetch(`${BASE}/rest/v1/tickets?select=id`, { headers: { apikey: key, authorization: `Bearer ${token}` } });
const fn = () => fetch(`${BASE}/functions/v1/admin-users`, {
  method: "POST", headers: { apikey: key, authorization: `Bearer ${token}`, "content-type": "application/json" },
  body: JSON.stringify({ action: "noop" }) });

let r = await rest();
const rows = r.status === 200 ? (await r.json()).length : null;
step("token accepted by PostgREST before expiry", r.status === 200, { status: r.status, rows });
r = await fn();
step("token accepted by Edge Function auth before expiry (403 = authenticated non-admin)", r.status === 403, { status: r.status });

const waitMs = claims.exp * 1000 - Date.now() + 90_000;
ev.wait_seconds = Math.round(waitMs / 1000); save();
await new Promise((res) => setTimeout(res, waitMs));

r = await rest();
step("expired token rejected by PostgREST", r.status === 401, { status: r.status, at_utc: new Date().toISOString() });
r = await fn();
step("expired token rejected by Edge Function", r.status === 401, { status: r.status });
r = await fetch(`${BASE}/auth/v1/user`, { headers: { apikey: key, authorization: `Bearer ${token}` } });
step("expired token rejected by Auth /user", r.status === 401 || r.status === 403, { status: r.status });
ev.finished_utc = new Date().toISOString();
ev.summary = `${ev.steps.filter((s) => s.result === "PASS").length}/${ev.steps.length} PASS`;
save();
console.log(ev.summary);
