// Pre-commit secret scan over the files git would commit. Prints counts and
// file names only, never matched secret values.
import { execFileSync } from "node:child_process";
import { readFileSync, existsSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const repo = process.argv[2], out = process.argv[3];
const files = execFileSync("git", ["-C", repo, "diff", "--cached", "--name-only", "-z"], { encoding: "utf8" })
  .split("\0").filter(Boolean);
const dir = join(homedir(), ".itsr-staging");
const exact = [];
try {
  const a = JSON.parse(readFileSync(join(dir, "test-accounts.json"), "utf8")).accounts;
  for (const k of Object.keys(a)) if (a[k].password) exact.push({ name: `synthetic password (${k})`, value: a[k].password });
} catch {}
if (existsSync(join(dir, "db-password"))) exact.push({ name: "staging DB password", value: readFileSync(join(dir, "db-password"), "utf8").trim() });

const patterns = [
  ["sb_secret_ key", /sb_secret_[A-Za-z0-9_-]{16,}/],
  ["Supabase personal access token", /sbp_[a-f0-9]{30,}/],
  ["JWT", /eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/],
  ["GitHub token", /gh[pousr]_[A-Za-z0-9]{30,}/],
  ["Vercel token / share link", /(vercel_[A-Za-z0-9]{20,}|_vercel_share=[A-Za-z0-9]{10,})/],
  ["Postgres URL with password", /postgres(ql)?:\/\/[^:\s/]+:[^@\s]{6,}@/],
  ["private key", /-----BEGIN [A-Z ]*PRIVATE KEY-----/],
  ["Gmail app password assignment", /GMAIL_APP_PASSWORD\s*[=:]\s*["']?[a-z]{4}\s?[a-z]{4}\s?[a-z]{4}\s?[a-z]{4}/],
];
const hits = [];
for (const f of files) {
  const p = join(repo, f);
  if (!existsSync(p)) continue;
  const buf = readFileSync(p);
  if (buf.length > 5_000_000 || buf.includes(0)) continue; // skip binaries (png)
  const s = buf.toString("utf8");
  for (const [name, re] of patterns) if (re.test(s)) hits.push(`${name}: ${f}`);
  for (const e of exact) if (e.value && s.includes(e.value)) hits.push(`${e.name}: ${f}`);
}
const report = [`# Pre-commit secret scan, ${new Date().toISOString()}`,
  `staged files scanned: ${files.length} (binary files skipped)`,
  `pattern classes: ${patterns.map((p) => p[0]).join("; ")}; plus ${exact.length} exact local secrets (values never printed)`,
  `hits: ${hits.length}`, ...hits].join("\n") + "\n";
writeFileSync(out, report);
console.log(report);
process.exit(hits.length ? 1 : 0);
