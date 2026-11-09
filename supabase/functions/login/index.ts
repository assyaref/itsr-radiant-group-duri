// Login Edge Function: employee number + password -> Supabase Auth session.
//  * Employee number -> email lookup happens server-side (no client enumeration).
//  * Uniform error message + padded response time (no account-existence oracle).
//  * Rate limit: 5 failures / 15 min per employee number, 30 failures / 15 min per IP
//    (office NAT safe). Only failures count.
//  * Deactivated profiles cannot log in.
//  * Service-role key stays in this runtime; the browser only ever receives the
//    user's own session tokens.
import { clientIp, corsHeaders, json, normalizeEmployeeNumber, padResponseTime } from "../_shared/http.ts";
import { adminClient, publicClient } from "../_shared/supabase.ts";

const GENERIC = "Authentication failed. Please check your credentials.";
const LIMITED = "Too many login attempts. Please try again in 15 minutes.";

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"), Deno.env.get("ALLOWED_ORIGINS"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);

  const start = Date.now();
  const fail = async (status: number, message: string) => {
    await padResponseTime(start);
    return json({ error: message }, status, headers);
  };

  let body: { employeeNumber?: unknown; password?: unknown };
  try { body = await req.json(); } catch { return fail(400, GENERIC); }

  const employeeNumber = normalizeEmployeeNumber(body.employeeNumber);
  const password = typeof body.password === "string" ? body.password : "";
  if (!employeeNumber || password.length < 6 || password.length > 128) return fail(401, GENERIC);

  const ip = clientIp(req);
  try {
    const admin = adminClient();

    const { data: limited, error: rlError } = await admin.rpc("login_is_rate_limited", {
      p_ip_address: ip, p_employee_number: employeeNumber,
    });
    if (rlError || limited === true) return fail(429, LIMITED); // fail closed

    const { data: profile } = await admin
      .from("profiles")
      .select("id, email, is_active")
      .eq("employee_number", employeeNumber)
      .maybeSingle();

    if (!profile || !profile.is_active) {
      await admin.rpc("record_login_attempt", {
        p_ip_address: ip, p_employee_number: employeeNumber, p_user_id: null, p_success: false,
      });
      return fail(401, GENERIC);
    }

    const { data: auth, error: authError } = await publicClient().auth.signInWithPassword({
      email: profile.email, password,
    });
    if (authError || !auth.session) {
      await admin.rpc("record_login_attempt", {
        p_ip_address: ip, p_employee_number: employeeNumber, p_user_id: profile.id, p_success: false,
      });
      return fail(401, GENERIC);
    }

    await admin.rpc("record_login_attempt", {
      p_ip_address: ip, p_employee_number: employeeNumber, p_user_id: profile.id, p_success: true,
    });

    await padResponseTime(start);
    return json({
      access_token: auth.session.access_token,
      refresh_token: auth.session.refresh_token,
      expires_in: auth.session.expires_in,
    }, 200, headers);
  } catch (e) {
    console.error("login error", e instanceof Error ? e.message : e);
    return fail(401, GENERIC);
  }
});
