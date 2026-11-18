// Shared HTTP helpers for ITSR Edge Functions (pure; unit-tested).

/**
 * CORS headers. ALLOWED_ORIGINS is a comma-separated list of exact origins
 * (e.g. "https://itsr.example.com,http://localhost:5000").
 * FAIL-CLOSED: when ALLOWED_ORIGINS is unset or empty, NO
 * Access-Control-Allow-Origin header is sent, so browsers block every
 * cross-origin call. A wildcard entry ("*") is ignored, never echoed.
 * Every deployment MUST set ALLOWED_ORIGINS to its exact app origin(s).
 */
export function corsHeaders(origin: string | null, allowedOrigins: string | undefined): Headers {
  const headers = new Headers({
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
    "Content-Type": "application/json",
    "Vary": "Origin",
  });
  const list = (allowedOrigins ?? "").split(",").map((s) => s.trim())
    .filter((s) => s.length > 0 && s !== "*");
  if (origin && list.includes(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
  }
  return headers;
}

export function json(body: unknown, status: number, headers: Headers): Response {
  return new Response(JSON.stringify(body), { status, headers });
}

/** Best-effort client IP (Supabase sits behind a proxy). */
export function clientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) {
    const first = xff.split(",")[0]?.trim();
    if (first) return first.slice(0, 100);
  }
  return (req.headers.get("cf-connecting-ip") ?? req.headers.get("x-real-ip") ?? "unknown").slice(0, 100);
}

export function bearerToken(req: Request): string | null {
  const h = req.headers.get("authorization") ?? req.headers.get("Authorization");
  if (!h) return null;
  const m = /^Bearer\s+(.+)$/i.exec(h.trim());
  return m ? m[1] : null;
}

export const EMPLOYEE_NUMBER_RE = /^[A-Z0-9]{2,20}$/;
export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
// `superadmin` is deliberately absent: it can never be assigned through the app.
export const ROLES = ["employee", "it_support", "administrator"] as const;
export type Role = typeof ROLES[number];

export function normalizeEmployeeNumber(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const n = v.trim().toUpperCase();
  return EMPLOYEE_NUMBER_RE.test(n) ? n : null;
}

/** Constant-ish response time so timing does not reveal whether an account exists. */
export async function padResponseTime(startMs: number, minMs = 800): Promise<void> {
  const elapsed = Date.now() - startMs;
  if (elapsed < minMs) await new Promise((r) => setTimeout(r, minMs - elapsed));
}

export function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

// ---------------------------------------------------------------------------
// Robustness helpers
// ---------------------------------------------------------------------------

/** Largest request body any ITSR function accepts (bytes). */
export const MAX_BODY_BYTES = 64 * 1024;

export function isJsonObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/**
 * Parses the request body as a JSON object. Returns null for a missing,
 * oversized, malformed or non-object body (e.g. `null`, `[]`, `"x"`), so
 * handlers never dereference a property of null.
 */
export async function readJsonObject(req: Request, maxBytes = MAX_BODY_BYTES): Promise<Record<string, unknown> | null> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > maxBytes) return null;
  let text: string;
  try { text = await req.text(); } catch { return null; }
  if (text.length > maxBytes) return null;
  try {
    const v: unknown = JSON.parse(text);
    return isJsonObject(v) ? v : null;
  } catch {
    return null;
  }
}

/** SMTP port as a strict integer 1–65535, or null. */
export function parsePort(v: unknown): number | null {
  const n = typeof v === "string" && v.trim() !== "" ? Number(v.trim()) : v;
  return typeof n === "number" && Number.isInteger(n) && n >= 1 && n <= 65535 ? n : null;
}

/** Hostname or IP literal without scheme/path/spaces. */
export function isValidHost(v: unknown): v is string {
  return typeof v === "string" && v.length > 0 && v.length <= 253 &&
    /^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$|^\[[0-9A-Fa-f:.]+\]$/.test(v);
}

/**
 * Socket timeouts for every nodemailer transport. Without them a silent SMTP
 * server can hold a request until the Edge Function wall-clock limit kills it.
 */
export const SMTP_TIMEOUTS = {
  connectionTimeout: 10_000,
  greetingTimeout: 10_000,
  socketTimeout: 20_000,
} as const;

type Handler = (req: Request) => Promise<Response>;

/**
 * Wraps a Deno.serve handler: any unexpected exception (missing secret,
 * network failure to Supabase, bug) becomes a JSON 500 that still carries the
 * CORS headers, so the browser shows a readable error instead of an opaque
 * "CORS/Failed to fetch". Details go to the function log only.
 */
export function withErrorBoundary(name: string, handler: Handler): Handler {
  return async (req: Request) => {
    try {
      return await handler(req);
    } catch (e) {
      console.error(`${name} unhandled error`, e instanceof Error ? `${e.name}: ${e.message}` : String(e));
      const headers = corsHeaders(req.headers.get("origin"), Deno.env.get("ALLOWED_ORIGINS"));
      return json({ error: "Internal error. Please try again later." }, 500, headers);
    }
  };
}
