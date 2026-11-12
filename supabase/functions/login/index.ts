// Login Edge Function: (employee number | email) + password -> Supabase Auth session.
//  * Employee number -> email lookup happens server-side (no client enumeration).
//  * Uniform error message + padded response time (no account-existence oracle).
//  * Rate limit: 5 failures / 15 min per employee number, 30 failures / 15 min per IP
//    (office NAT safe). Only failures count.
//  * Deactivated profiles cannot log in.
//  * Service-role key stays in this runtime; the browser only ever receives the
//    user's own session tokens.
import { clientIp, corsHeaders, json, EMAIL_RE, normalizeEmployeeNumber, padResponseTime, readJsonObject, withErrorBoundary } from "../_shared/http.ts";
import { adminClient, publicClient } from "../_shared/supabase.ts";
import { authPassword, plausibleLoginPassword } from "../_shared/password.ts";

const GENERIC = "Authentication failed. Please check your credentials.";
const LIMITED = "Too many login attempts. Please try again in 15 minutes.";

Deno.serve(withErrorBoundary("login", async (req) => {
  const headers = corsHeaders(req.headers.get("origin"), Deno.env.get("ALLOWED_ORIGINS"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);

  const start = Date.now();
  const fail = async (status: number, message: string) => {
    await padResponseTime(start);
    return json({ error: message }, status, headers);
  };

  const body = await readJsonObject(req);
  if (!body) return fail(400, GENERIC);

  // Sign in with EITHER an employee number ("Akun Perusahaan") or an email.
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const byEmail = email.length > 0;
  const employeeNumber = byEmail ? null : normalizeEmployeeNumber(body.employeeNumber);
  const password = plausibleLoginPassword(body.password) ? body.password : "";
  if (byEmail ? (!EMAIL_RE.test(email) || email.length > 254) : !employeeNumber) return fail(401, GENERIC);
  if (!password) return fail(401, GENERIC); // 4–5 digit PIN or 6–128 characters

  const ip = clientIp(req);
  try {
    const admin = adminClient();

    // Profile lookup first (the uniform, padded reply hides the result), so
    // email and employee-number attempts share ONE per-account rate limit.
    const lookup = admin.from("profiles").select("id, email, is_active, employee_number");
    const { data: profile, error: lookupErr } = byEmail
      ? await lookup.eq("email", email).maybeSingle()
      : await lookup.eq("employee_number", employeeNumber).maybeSingle();
    if (lookupErr) throw new Error(`profile lookup failed: ${lookupErr.message}`);
    const rateKey: string = profile?.employee_number ?? employeeNumber ?? `@${email}`.slice(0, 40);

    const { data: limited, error: rlError } = await admin.rpc("login_is_rate_limited", {
      p_ip_address: ip, p_employee_number: rateKey,
    });
    if (rlError || limited === true) return fail(429, LIMITED); // fail closed

    if (!profile || !profile.is_active) {
      await admin.rpc("record_login_attempt", {
        p_ip_address: ip, p_employee_number: rateKey, p_user_id: null, p_success: false,
      });
      return fail(401, GENERIC);
    }

    const { data: auth, error: authError } = await publicClient().auth.signInWithPassword({
      email: profile.email, password: await authPassword(password, Deno.env.get("PIN_PEPPER")),
    });
    if (authError || !auth.session) {
      await admin.rpc("record_login_attempt", {
        p_ip_address: ip, p_employee_number: rateKey, p_user_id: profile.id, p_success: false,
      });
      return fail(401, GENERIC);
    }

    await admin.rpc("record_login_attempt", {
      p_ip_address: ip, p_employee_number: rateKey, p_user_id: profile.id, p_success: true,
    });

    await padResponseTime(start);
    return json({
      access_token: auth.session.access_token,
      refresh_token: auth.session.refresh_token,
      expires_in: auth.session.expires_in,
    }, 200, headers);
  } catch (e) {
    // Infrastructure failure (DB/Auth unreachable), not a wrong password:
    // answer 503 so the app says "try again later" instead of "wrong password".
    console.error("login error", e instanceof Error ? e.message : e);
    return fail(503, "Login is temporarily unavailable. Please try again later.");
  }
}));
