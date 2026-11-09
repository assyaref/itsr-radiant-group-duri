// ITSR browser E2E: real Flutter Web release build (E2E_APP, default localhost:5000) against the
// STAGING backend, driven through Flutter's semantics tree in headless Chrome.
// Synthetic STG* accounts only. Never prints or saves passwords/tokens.
import { chromium } from "playwright-core";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const APP = (process.env.E2E_APP ?? "http://localhost:5000").replace(/\/+$/, "");
const OUT = process.argv[2];
mkdirSync(join(OUT, "screens"), { recursive: true });
const accts = JSON.parse(readFileSync(join(homedir(), ".itsr-staging", "test-accounts.json"), "utf8")).accounts;
const OTHER_TICKET = readFileSync(new URL("./other_ticket_id.txt", import.meta.url), "utf8").trim();
const RUN = new Date().toISOString().replace(/[-:]/g, "").slice(0, 13);
const SUBJECT = `E2E browser test ${RUN}`;
const results = [];
const COMMENT_BOX = 'textarea[aria-label*="Add a comment"]';
let shot = 0;

const browser = await chromium.launch({
  executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe", headless: true });

async function snap(page, name) {
  const f = `screens/${String(++shot).padStart(2, "0")}_${name}.png`;
  await page.screenshot({ path: join(OUT, f) });
  return f;
}
async function dump(page) {
  return page.$$eval("flt-semantics, input, textarea", (es) => es
    .map((e) => `${e.tagName.toLowerCase()}[${e.getAttribute("role") ?? ""}] ${e.getAttribute("aria-label") ?? ""} | ${(e.textContent || "").trim().slice(0, 60)}`)
    .filter((s) => s.replace(/[\[\]| ]/g, "").length > 0).slice(0, 80).join("\n"));
}
async function check(page, id, name, fn) {
  try {
    const detail = await fn();
    results.push({ id, name, result: "PASS", detail: detail ?? "", screenshot: await snap(page, id) });
    console.log(`PASS ${id} ${name}`);
  } catch (e) {
    const f = await snap(page, `${id}_FAIL`).catch(() => "");
    results.push({ id, name, result: "FAIL", detail: String(e.message).split("\n")[0].slice(0, 300), screenshot: f,
      semantics: await dump(page).catch(() => "") });
    console.log(`FAIL ${id} ${name}: ${String(e.message).split("\n")[0].slice(0, 200)}`);
  }
  writeFileSync(join(OUT, "e2e_results.json"), JSON.stringify({ run: RUN, app: APP, backend: "staging yzjpttfwnvnuyxbdkidm", results }, null, 2));
}

async function a11y(page) {
  const ph = page.locator("flt-semantics-placeholder");
  try { await ph.waitFor({ state: "attached", timeout: 15000 }); } catch { return; }
  await ph.evaluate((e) => e.click()).catch(() => {});
  await page.waitForTimeout(600);
}
async function open(page, hash) {
  await page.goto(`${APP}/#${hash}`, { waitUntil: "load" });
  await a11y(page);
}
// Flutter exposes text either as aria-label or as text content; parents contain
// their children's text. Match both, and act on the SMALLEST matching element.
const pat = (t) => (t instanceof RegExp ? { src: t.source, flags: t.flags } : { src: t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), flags: "" });
async function locate(page, t, role) {
  const { src, flags } = pat(t);
  return page.evaluate(({ src, flags, role }) => {
    const re = new RegExp(src, flags);
    let best = null;
    for (const e of document.querySelectorAll("flt-semantics, input, textarea, flt-semantics-placeholder")) {
      if (role && e.getAttribute("role") !== role) continue;
      const s = `${e.getAttribute("aria-label") ?? ""}\n${e.textContent ?? ""}\n${e.value ?? ""}`;
      if (!re.test(s)) continue;
      const r = e.getBoundingClientRect();
      if (r.width < 1 || r.height < 1) continue;
      const area = r.width * r.height;
      if (!best || area < best.area) best = { x: r.x + r.width / 2, y: r.y + r.height / 2, area };
    }
    return best;
  }, { src, flags, role: role ?? null });
}
async function waitText(page, t, timeout = 20000, role) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    const hit = await locate(page, t, role);
    if (hit) return hit;
    await page.waitForTimeout(300);
  }
  throw new Error(`not found within ${timeout}ms: ${t}${role ? ` (role ${role})` : ""}`);
}
async function clickText(page, t, role, timeout = 20000) {
  const hit = await waitText(page, t, timeout, role);
  await page.mouse.click(hit.x, hit.y);
  await page.waitForTimeout(300);
}
async function absent(page, t, ms = 1500) {
  await page.waitForTimeout(ms);
  if (await locate(page, t)) throw new Error(`unexpectedly visible: ${t}`);
}
const text = (page, t) => ({ click: () => clickText(page, t) });
const button = (page, name) => ({ click: () => clickText(page, name instanceof RegExp ? name : new RegExp(`^\\s*${pat(name).src}\\s*$`, "m"), "button") });
async function type(page, selector, value) {
  const el = page.locator(selector).first();
  await el.waitFor({ state: "visible", timeout: 15000 });
  await el.click();
  await page.waitForTimeout(400); // let Flutter finish focusing before keystrokes
  await page.keyboard.press("Control+A");
  await page.keyboard.press("Backspace");
  await page.keyboard.type(value, { delay: 15 });
}
async function waitHash(page, re, timeout = 20000) {
  await page.waitForFunction((src) => new RegExp(src).test(location.hash), re.source, { timeout });
  return page.evaluate(() => location.hash);
}
async function login(page, acct) {
  // Full reload so the form is guaranteed empty (no text left from a prior attempt).
  await page.goto(`${APP}/#/login`, { waitUntil: "load" });
  await page.reload({ waitUntil: "load" });
  await a11y(page);
  await type(page, 'input[aria-label="Employee Number"]', acct.employee_number);
  await type(page, 'input[aria-label="Password"]', acct.password);
  await button(page, "Sign in").click();
  await waitHash(page, /#\/dashboard/);
  await waitText(page, /Welcome,/);
}
async function signOut(page) {
  await clickText(page, /^\s*Sign out\s*$/m);
  await waitText(page, "Do you want to sign out?");
  await button(page, "Sign out").click(); // dialog confirm (page below is excluded while modal)
  await waitHash(page, /#\/login/);
}
async function chooseDropdown(page, label, option) {
  await clickText(page, new RegExp(label));
  await page.waitForTimeout(500);
  await clickText(page, new RegExp(`^\\s*${option}\\s*$`, "m"));
  await page.waitForTimeout(500);
}
async function readText(page, re) {
  const { src, flags } = pat(re);
  return page.evaluate(({ src, flags }) => {
    const r = new RegExp(src, flags);
    for (const e of document.querySelectorAll("flt-semantics, textarea, input")) {
      const m = `${e.getAttribute("aria-label") ?? ""}\n${e.textContent ?? ""}\n${e.value ?? ""}`.match(r);
      if (m) return m[0];
    }
    return null;
  }, { src, flags });
}

let ticketHash = "", ticketNumber = "";

// ============================ DESKTOP: employee ==============================
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  await check(page, "E01", "invalid credentials are rejected with a generic message", async () => {
    await open(page, "/login");
    await type(page, 'input[aria-label="Employee Number"]', accts.employee.employee_number);
    await type(page, 'input[aria-label="Password"]', "definitely-wrong-pw");
    await button(page, "Sign in").click();
    await waitText(page, "Authentication failed. Please check your credentials.");
    if (!(await page.evaluate(() => location.hash)).includes("/login")) throw new Error("left login page");
  });
  await check(page, "E02", "employee signs in and lands on the dashboard", async () => {
    await login(page, accts.employee);
    await waitText(page, "My tickets");
    await waitText(page, "Recent activity");
    await absent(page, "Support Queue");
    await absent(page, "Users");
  });
  await check(page, "E03", "session persists across a full page reload", async () => {
    await page.reload({ waitUntil: "load" });
    await a11y(page);
    await waitText(page, /Welcome,/);
    return await page.evaluate(() => location.hash);
  });
  await check(page, "E04", "employee is redirected away from staff/admin routes", async () => {
    await open(page, "/queue");
    const h1 = await waitHash(page, /#\/dashboard/);
    await open(page, "/admin/users");
    const h2 = await waitHash(page, /#\/dashboard/);
    await open(page, "/admin/email-notifications");
    const h3 = await waitHash(page, /#\/dashboard/);
    await absent(page, "SMTP Configuration", 500);
    return `${h1} ; ${h2} ; ${h3}`;
  });
  await check(page, "E05", "employee creates a ticket (server-generated number)", async () => {
    await open(page, "/tickets/new");
    await waitText(page, "Describe your problem");
    await type(page, 'input[aria-label="Subject *"]', SUBJECT);
    await chooseDropdown(page, "Category", "Hardware");
    await type(page, 'textarea[aria-label="Description *"], input[aria-label="Description *"]',
      "Automated browser E2E: laptop shows a black screen after login. Synthetic staging data.");
    await button(page, "Submit ticket").click();
    ticketHash = await waitHash(page, /#\/tickets\/[0-9a-f-]{36}/);
    await waitText(page, SUBJECT);
    await waitText(page, /ITSR-\d{5}/);
    ticketNumber = await readText(page, /ITSR-\d{5}/);
    return `${ticketNumber} ${ticketHash}`;
  });
  await check(page, "E06", "employee adds a comment", async () => {
    await type(page, COMMENT_BOX, "E2E employee comment: it also happens on battery.");
    await button(page, "Post comment").click();
    await waitText(page, "E2E employee comment: it also happens on battery.");
    await absent(page, "Internal work note", 200);
  });
  await check(page, "E07", "employee sees the new ticket in My Tickets", async () => {
    await open(page, "/tickets");
    await waitText(page, SUBJECT);
  });
  await check(page, "E08", "employee cannot open another user's ticket (RLS)", async () => {
    await open(page, `/tickets/${OTHER_TICKET}`);
    await waitText(page, /not found or you do not have access/);
  });
  await check(page, "E09", "employee signs out (confirmation dialog) and returns to login", async () => {
    await open(page, "/dashboard");
    await waitText(page, /Welcome,/);
    await signOut(page);
    await open(page, "/dashboard");
    await waitHash(page, /#\/login/);
  });
  await ctx.close();
}

// ============================ DESKTOP: technician ============================
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  await check(page, "T01", "IT Support signs in; dashboard shows queue + assigned sections", async () => {
    await login(page, accts.technician);
    await waitText(page, "Support queue");
    await waitText(page, "Assigned to me");
  });
  await check(page, "T02", "IT Support sees the employee's new ticket in the queue", async () => {
    await open(page, "/queue");
    await waitText(page, SUBJECT);
  });
  await check(page, "T03", "IT Support accepts the ticket", async () => {
    await text(page, SUBJECT).click();
    await waitHash(page, /#\/tickets\//);
    await button(page, /Accept ticket|Take over/).click();
    await waitText(page, "You are now assigned to this ticket");
    await waitText(page, "Assigned to");
  });
  await check(page, "T04", "IT Support starts work (status change with confirmation)", async () => {
    await page.waitForTimeout(1500);
    await button(page, "Start work").click();
    await waitText(page, "Change status");
    await button(page, "Start work").click();
    await waitText(page, /Status updated to In Progress/);
  });
  await check(page, "T05", "IT Support adds an internal technical note", async () => {
    await clickText(page, "Internal work note");
    await type(page, COMMENT_BOX, "E2E internal note: reseated RAM module.");
    await button(page, "Add note").click();
    await waitText(page, "Internal note added");
    await waitText(page, "INTERNAL NOTE");
  });
  await check(page, "T06", "IT Support resolves with a recorded resolution", async () => {
    await page.waitForTimeout(1200);
    await button(page, "Resolve").click();
    await waitText(page, "Resolve ticket");
    await type(page, 'textarea[aria-label*="What was done"], input[aria-label*="What was done"]',
      "E2E resolution: RAM reseated, laptop boots normally.");
    await button(page, "Resolve").click();
    await waitText(page, /Status updated to Resolved/);
    await waitText(page, "E2E resolution: RAM reseated, laptop boots normally.");
  });
  await check(page, "T07", "activity history records accept / status / resolve", async () => {
    await waitText(page, /Ticket assigned by/);
    await waitText(page, /Ticket status Open → In Progress|Ticket status Assigned → In Progress/);
    await waitText(page, /Ticket resolved by/);
  });
  await check(page, "T08", "IT Support is redirected away from admin + SMTP configuration routes", async () => {
    await open(page, "/admin/email-notifications");
    const h1 = await waitHash(page, /#\/dashboard/);
    await absent(page, "SMTP Configuration", 500);
    await open(page, "/admin/settings");
    const h2 = await waitHash(page, /#\/dashboard/);
    await absent(page, "Email & Notifications", 300);
    return `${h1} ; ${h2}`;
  });
  await signOut(page).catch(() => {});
  await ctx.close();
}

// ======================= DESKTOP: employee tracks + closes ===================
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  await check(page, "E10", "employee tracks progress: resolution visible, internal note hidden", async () => {
    await login(page, accts.employee);
    await open(page, ticketHash.slice(1));
    await waitText(page, "E2E resolution: RAM reseated, laptop boots normally.");
    await waitText(page, "Is your problem fixed?", 10000);
    await absent(page, "E2E internal note: reseated RAM module.");
    await absent(page, "INTERNAL NOTE", 200);
  });
  await check(page, "E11", "employee confirms and closes the resolved ticket", async () => {
    await button(page, "Yes, close ticket").click();
    await waitText(page, "Confirm and close");
    await button(page, "Close ticket").click();
    await waitText(page, "Ticket closed. Thank you!");
    await waitText(page, "This ticket is closed.");
  });
  await signOut(page).catch(() => {});
  await ctx.close();
}

// ============================ DESKTOP: administrator =========================
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  await check(page, "A01", "administrator signs in; admin navigation visible", async () => {
    await login(page, accts.admin);
    for (const t of ["Support Queue", "Users", "Categories", "Settings"]) await waitText(page, t);
  });
  await check(page, "A02", "administrator user management lists employees with roles", async () => {
    await open(page, "/admin/users");
    await waitText(page, /STGEMP01/);
    await waitText(page, /STGTEC01/);
    await waitText(page, "Add user");
  });
  await check(page, "A03", "administrator category management", async () => {
    await open(page, "/admin/categories");
    await waitText(page, "Hardware");
    await waitText(page, "Network");
  });
  await check(page, "A04", "administrator application settings load", async () => {
    await open(page, "/admin/settings");
    await waitText(page, "Email notifications");
    await page.locator('input[aria-label^="IT Support group email"]').first().waitFor({ timeout: 15000 });
    await page.locator('input[aria-label^="Manager email"]').first().waitFor({ timeout: 15000 });
    await waitText(page, "Save settings");
  });
  await check(page, "A05", "administrator oversees all tickets incl. the closed E2E ticket", async () => {
    await open(page, "/queue");
    await waitText(page, SUBJECT);
    await open(page, ticketHash.slice(1));
    await waitText(page, "IT Support actions");
    await waitText(page, /Ticket closed by/);
  });
  // Read-only inspection: nothing is saved, tested or sent from this page.
  await check(page, "A06", "Email & Notifications page: SMTP not configured, recipients shown, no secret", async () => {
    // Flutter's hidden semantic <input>s do not expose .value until focused, so
    // assert on the smtp-config response the page itself received instead.
    const resp = page.waitForResponse((r) => r.url().includes("/functions/v1/smtp-config"), { timeout: 30000 });
    await open(page, "/admin/email-notifications");
    const body = await (await resp).json();
    await waitText(page, "SMTP Configuration");
    await waitText(page, "No SMTP credential configured");
    await waitText(page, "Notification Recipients");
    const leaks = Object.keys(body).filter((k) => /pass(word)?$|secret/i.test(k) && k !== "password_configured");
    if (leaks.length) throw new Error(`secret-like fields sent to browser: ${leaks}`);
    if (body.password_configured !== false) throw new Error("password_configured is not false");
    if (body.it_support_group_email !== "it.support-duri@radiant-utama.com") throw new Error(`IT Support email = ${body.it_support_group_email}`);
    if (body.manager_email !== null) throw new Error("manager email is not NULL");
    if (body.smtp_host !== null) throw new Error("smtp_host unexpectedly set");
    return `it=${body.it_support_group_email} manager=null smtp_host=null password_configured=false; ${Object.keys(body).length} fields, none secret`;
  });
  await check(page, "A07", "Email & Notifications nav entry present for administrator", async () => {
    await open(page, "/dashboard");
    await waitText(page, "Email & Notifications");
  });
  await ctx.close();
}

// ============================ MOBILE (390 x 844) =============================
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  await check(page, "M01", "phone: login screen fits and signs in", async () => {
    await login(page, accts.employee);
    const w = await page.evaluate(() => document.documentElement.scrollWidth);
    if (w > 390) throw new Error(`horizontal page scroll: ${w}px`);
    return `scrollWidth=${w}`;
  });
  await check(page, "M02", "phone: drawer navigation replaces the rail", async () => {
    await clickText(page, /Open navigation menu/);
    await waitText(page, "My Tickets");
    await waitText(page, "Sign out");
    await clickText(page, /^\s*My Tickets\s*$/m);
    await waitHash(page, /#\/tickets$/);
    await waitText(page, SUBJECT);
  });
  await check(page, "M03", "phone: ticket detail renders stacked (no horizontal scroll)", async () => {
    await open(page, ticketHash.slice(1));
    await waitText(page, SUBJECT, 20000);
    // ListView only builds semantics near the viewport: scroll to the history.
    let found = false;
    for (let i = 0; i < 12 && !found; i++) {
      await page.mouse.move(195, 600); await page.mouse.wheel(0, 500); await page.waitForTimeout(500);
      found = !!(await locate(page, "History & comments"));
    }
    if (!found) throw new Error("History & comments not reachable by scrolling");
    const w = await page.evaluate(() => document.documentElement.scrollWidth);
    if (w > 390) throw new Error(`horizontal page scroll: ${w}px`);
    return `scrollWidth=${w}`;
  });
  await check(page, "M04", "phone: create-ticket form usable", async () => {
    await open(page, "/tickets/new");
    await waitText(page, "Describe your problem");
    await waitText(page, "Submit ticket");
  });
  await ctx.close();
}

await browser.close();
const pass = results.filter((r) => r.result === "PASS").length;
const summary = `${pass}/${results.length} PASS`;
writeFileSync(join(OUT, "e2e_results.json"), JSON.stringify({ run: RUN, app: APP, backend: "staging yzjpttfwnvnuyxbdkidm",
  ticket: ticketNumber, summary, results }, null, 2));
console.log(summary, ticketNumber);
