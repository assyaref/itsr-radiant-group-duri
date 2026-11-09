// M03 retest: phone ticket detail. No horizontal scroll; history reachable by scrolling.
import { chromium } from "playwright-core";
import { readFileSync, writeFileSync } from "node:fs"; import { homedir } from "node:os"; import { join } from "node:path";
const [hash, out] = process.argv.slice(2);
const acct = JSON.parse(readFileSync(join(homedir(), ".itsr-staging", "test-accounts.json"), "utf8")).accounts.employee;
const browser = await chromium.launch({ executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe", headless: true });
const page = await (await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 })).newPage();
const a11y = async () => { try { await page.locator("flt-semantics-placeholder").waitFor({ state: "attached", timeout: 8000 }); } catch { return; } await page.locator("flt-semantics-placeholder").evaluate((e) => e.click()); await page.waitForTimeout(800); };
const has = (re) => page.evaluate((src) => [...document.querySelectorAll("flt-semantics, textarea")].some((e) => new RegExp(src).test(`${e.getAttribute("aria-label") ?? ""}\n${e.textContent}\n${e.value ?? ""}`)), re);
await page.goto("http://localhost:5000/#/login"); await page.reload(); await a11y();
for (const [sel, v] of [['input[aria-label="Employee Number"]', acct.employee_number], ['input[aria-label="Password"]', acct.password]]) { await page.locator(sel).click(); await page.waitForTimeout(400); await page.keyboard.type(v, { delay: 15 }); }
const b = await page.$$eval("flt-semantics[role=button]", (es) => { const r = es.find((x) => /Sign in/.test(x.textContent)).getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; });
await page.mouse.click(b[0], b[1]);
await page.waitForFunction(() => location.hash.includes("dashboard"), null, { timeout: 25000 });
await page.goto(`http://localhost:5000/${hash}`); await a11y(); await page.waitForTimeout(2500);
const steps = [];
const w = await page.evaluate(() => document.documentElement.scrollWidth);
steps.push([w <= 390, `no horizontal page scroll (scrollWidth=${w})`]);
steps.push([await has("E2E resolution: RAM reseated"), "resolution visible at top of stacked layout"]);
await page.screenshot({ path: join(out, "M03b_top.png") });
let found = false;
for (let i = 0; i < 12 && !found; i++) { await page.mouse.move(195, 600); await page.mouse.wheel(0, 500); await page.waitForTimeout(500); found = await has("History & comments"); }
steps.push([found, "History & comments reachable by scrolling"]);
steps.push([await has("Ticket resolved by|Ticket closed by"), "timeline entries rendered on phone"]);
await page.screenshot({ path: join(out, "M03b_scrolled.png") });
const pass = steps.every((s) => s[0]);
const txt = `M03b (retest) phone ticket detail ${new Date().toISOString()}: ${pass ? "PASS" : "FAIL"}\n` + steps.map((s) => `  ${s[0] ? "PASS" : "FAIL"} ${s[1]}`).join("\n") + "\n";
writeFileSync(join(out, "M03b_result.txt"), txt); console.log(txt);
await browser.close();
