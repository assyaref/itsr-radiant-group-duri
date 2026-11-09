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
