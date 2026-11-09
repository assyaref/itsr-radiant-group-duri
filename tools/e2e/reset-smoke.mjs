// admin-users reset_password validation smoke test (STAGING, synthetic admin).
// Sends only invalid inputs or a non-existent user id: no password is changed.
import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
const BASE = "https://yzjpttfwnvnuyxbdkidm.supabase.co";
const dir = join(homedir(), ".itsr-staging");
const accts = JSON.parse(readFileSync(join(dir, "test-accounts.json"), "utf8")).accounts;
const key = readFileSync(join(dir, "publishable-key"), "utf8").trim();
const out = [];
async function login(a) {
  const r = await fetch(`${BASE}/functions/v1/login`, { method: "POST",
    headers: { "content-type": "application/json", apikey: key },
    body: JSON.stringify({ employeeNumber: a.employee_number, password: a.password }) });
  return (await r.json()).access_token;
}
async function call(token, body) {
  const r = await fetch(`${BASE}/functions/v1/admin-users`, { method: "POST",
    headers: { "content-type": "application/json", apikey: key, authorization: `Bearer ${token}` },
    body: JSON.stringify(body) });
  return { status: r.status, body: await r.json().catch(() => null) };
}
const check = (name, got, want) => out.push(`${got.status === want ? "PASS" : "FAIL"} | ${name} | expected ${want}, got ${got.status} ${JSON.stringify(got.body)}`);
const admin = await login(accts.admin);
const emp = await login(accts.employee);
check("reset_password: invalid uuid -> 400", await call(admin, { action: "reset_password", user_id: "not-a-uuid", password: "longenough1" }), 400);
check("reset_password: empty user id -> 400", await call(admin, { action: "reset_password", password: "longenough1" }), 400);
check("reset_password: password > 128 chars -> 400", await call(admin, { action: "reset_password", user_id: "00000000-0000-0000-0000-000000000000", password: "x".repeat(129) }), 400);
check("reset_password: password < 8 chars -> 400", await call(admin, { action: "reset_password", user_id: "00000000-0000-0000-0000-000000000000", password: "short" }), 400);
check("reset_password: unknown user -> 404", await call(admin, { action: "reset_password", user_id: "00000000-0000-0000-0000-000000000000", password: "longenough1" }), 404);
check("reset_password as employee -> 403", await call(emp, { action: "reset_password", user_id: "00000000-0000-0000-0000-000000000000", password: "longenough1" }), 403);
const text = `# admin-users v4 reset_password validation smoke test, ${new Date().toISOString()}\n${out.join("\n")}\n`;
writeFileSync(process.argv[2], text);
console.log(text);
