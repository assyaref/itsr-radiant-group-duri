// Self-service account actions for the signed-in user.
//
//   { action: "change_password", current_password, new_password }
//
// The current password is re-checked (through the same PIN derivation as the
// `login` function) before the new one is set, and attempts count towards the
// login rate limit, so a stolen session cannot brute-force or silently change
// the password. PINs (4–5 digits) are stored via authPassword() because
// Supabase Auth rejects passwords shorter than 6 characters.
import { bearerToken, clientIp, corsHeaders, json, readJsonObject, withErrorBoundary } from "../_shared/http.ts";
import { adminClient, publicClient, verifyCaller } from "../_shared/supabase.ts";
import { authPassword, isPin, newPasswordError, PIN_NOT_CONFIGURED, pinSupported, plausibleLoginPassword } from "../_shared/password.ts";

Deno.serve(withErrorBoundary("account", async (req) => {
  const headers = corsHeaders(req.headers.get("origin"), Deno.env.get("ALLOWED_ORIGINS"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);

  const admin = adminClient();
  const caller = await verifyCaller(admin, bearerToken(req));
  if (!caller) return json({ error: "Not authenticated" }, 401, headers);

  const body = await readJsonObject(req);
  if (!body) return json({ error: "Invalid JSON body" }, 400, headers);
  if (body.action !== "change_password") return json({ error: "Unknown action" }, 400, headers);

  const pepper = Deno.env.get("PIN_PEPPER");
  const next = typeof body.new_password === "string" ? body.new_password : "";
  const err = newPasswordError(next);
  if (err) return json({ error: err }, 400, headers);
  if (isPin(next) && !pinSupported(pepper)) return json({ error: PIN_NOT_CONFIGURED }, 503, headers);

  const ip = clientIp(req);
  const { data: limited, error: rlError } = await admin.rpc("login_is_rate_limited", {
    p_ip_address: ip, p_employee_number: caller.employee_number,
  });
  if (rlError || limited === true) {
    return json({ error: "Too many attempts. Please try again in 15 minutes." }, 429, headers);
  }

  const current = body.current_password;
  const { error: checkErr } = plausibleLoginPassword(current)
    ? await publicClient().auth.signInWithPassword({
      email: caller.email, password: await authPassword(current, pepper),
    })
    : { error: new Error("bad") };
  if (checkErr) {
    await admin.rpc("record_login_attempt", {
      p_ip_address: ip, p_employee_number: caller.employee_number, p_user_id: caller.id, p_success: false,
    });
    return json({ error: "Current password is incorrect" }, 400, headers);
  }

  const { error: updErr } = await admin.auth.admin.updateUserById(caller.id, {
    password: await authPassword(next, pepper),
  });
  if (updErr) return json({ error: "Could not change the password" }, 400, headers);
  return json({ ok: true }, 200, headers);
}));
