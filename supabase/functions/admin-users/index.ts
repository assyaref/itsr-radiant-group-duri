// Admin user management (service role, server-side only).
// Every request is authorized here: the caller's JWT is verified with Supabase
// Auth and the caller's profile must be an ACTIVE administrator.
//
// Actions (POST JSON):
//   { action: "create", employee_number, full_name, email, department, role, phone_number?, password }
//   { action: "update", user_id, full_name?, email?, department?, role?, phone_number?, is_active? }
//   { action: "reset_password", user_id, password }
import { bearerToken, corsHeaders, json, readJsonObject, withErrorBoundary } from "../_shared/http.ts";
import { adminClient, verifyCaller } from "../_shared/supabase.ts";
import { authPassword } from "../_shared/password.ts";
import { validateCreate, validateResetPassword, validateUpdate } from "./validation.ts";

Deno.serve(withErrorBoundary("admin-users", async (req) => {
  const headers = corsHeaders(req.headers.get("origin"), Deno.env.get("ALLOWED_ORIGINS"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);

  const admin = adminClient();
  const caller = await verifyCaller(admin, bearerToken(req));
  if (!caller) return json({ error: "Not authenticated" }, 401, headers);
  if (caller.role !== "administrator") return json({ error: "Administrator access required" }, 403, headers);

  const body = await readJsonObject(req);
  if (!body) return json({ error: "Invalid JSON body" }, 400, headers);

  try {
    switch (body.action) {
      case "create": {
        const v = validateCreate(body);
        if (!v.ok) return json({ error: v.error }, 400, headers);
        const d = v.value;

        const { count: dupNo } = await admin.from("profiles").select("id", { count: "exact", head: true })
          .eq("employee_number", d.employee_number);
        const { count: dupEmail } = await admin.from("profiles").select("id", { count: "exact", head: true })
          .eq("email", d.email);
        if ((dupNo ?? 0) > 0 || (dupEmail ?? 0) > 0) {
          return json({ error: "Employee number or email already exists" }, 409, headers);
        }

        const { data: created, error: cErr } = await admin.auth.admin.createUser({
          email: d.email, password: await authPassword(d.password, Deno.env.get("PIN_PEPPER")), email_confirm: true,
        });
        if (cErr || !created.user) return json({ error: cErr?.message ?? "Could not create auth user" }, 400, headers);

        const { error: pErr } = await admin.from("profiles").insert({
          id: created.user.id, employee_number: d.employee_number, full_name: d.full_name,
          email: d.email, department: d.department, role: d.role, phone_number: d.phone_number,
        });
        if (pErr) {
          // Roll back the auth user so a retry is possible; log if that fails too.
          const { error: delErr } = await admin.auth.admin.deleteUser(created.user.id);
          if (delErr) console.error("admin-users rollback failed; orphan auth user", created.user.id, delErr.message);
          const dup = pErr.code === "23505";
          return json({ error: dup ? "Employee number or email already exists" : "Could not create profile: " + pErr.message },
            dup ? 409 : 400, headers);
        }
        return json({ id: created.user.id }, 201, headers);
      }

      case "update": {
        const v = validateUpdate(body);
        if (!v.ok) return json({ error: v.error }, 400, headers);
        const { user_id, changes } = v.value;

        const { data: target } = await admin.from("profiles").select("id, role, is_active, email")
          .eq("id", user_id).maybeSingle();
        if (!target) return json({ error: "User not found" }, 404, headers);

        const demoting = changes.role !== undefined && changes.role !== "administrator" && target.role === "administrator";
        const deactivating = changes.is_active === false && target.is_active;
        if (user_id === caller.id && (demoting || deactivating)) {
          return json({ error: "You cannot remove your own administrator access" }, 400, headers);
        }
        if ((demoting || deactivating) && target.role === "administrator") {
          const { count } = await admin.from("profiles").select("id", { count: "exact", head: true })
            .eq("role", "administrator").eq("is_active", true);
          if ((count ?? 0) <= 1) return json({ error: "At least one active administrator is required" }, 400, headers);
        }

        if (changes.email && changes.email !== target.email) {
          const { error } = await admin.auth.admin.updateUserById(user_id, { email: changes.email, email_confirm: true });
          if (error) return json({ error: error.message }, 400, headers);
        }
        if (changes.is_active !== undefined && changes.is_active !== target.is_active) {
          const { error } = await admin.auth.admin.updateUserById(user_id, {
            ban_duration: changes.is_active ? "none" : "876000h",
          });
          if (error) return json({ error: error.message }, 400, headers);
        }
        const { error: uErr } = await admin.from("profiles").update(changes).eq("id", user_id);
        if (uErr) return json({ error: uErr.message }, 400, headers);
        return json({ ok: true }, 200, headers);
      }

      case "reset_password": {
        const v = validateResetPassword(body);
        if (!v.ok) return json({ error: v.error }, 400, headers);
        const { data: target } = await admin.from("profiles").select("id").eq("id", v.value.user_id).maybeSingle();
        if (!target) return json({ error: "User not found" }, 404, headers);
        const { error } = await admin.auth.admin.updateUserById(v.value.user_id, {
          password: await authPassword(v.value.password, Deno.env.get("PIN_PEPPER")),
        });
        if (error) return json({ error: error.message }, 400, headers);
        return json({ ok: true }, 200, headers);
      }

      default:
        return json({ error: "Unknown action" }, 400, headers);
    }
  } catch (e) {
    console.error("admin-users error", e instanceof Error ? e.message : e);
    return json({ error: "Internal error" }, 500, headers);
  }
}));
