// Server-side Supabase clients. SUPABASE_SERVICE_ROLE_KEY exists ONLY in the
// Edge Function runtime (injected by Supabase) and is never sent to the browser.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.49.4";

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing required environment variable ${name}`);
  return v;
}

export function adminClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/** Anon/publishable client, used only to perform password sign-in. */
export function publicClient(): SupabaseClient {
  const key = Deno.env.get("SUPABASE_ANON_KEY") || env("SUPABASE_PUBLISHABLE_KEY");
  return createClient(env("SUPABASE_URL"), key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export interface CallerProfile {
  id: string; employee_number: string; full_name: string; email: string;
  role: "employee" | "it_support" | "administrator" | "superadmin"; is_active: boolean;
}

/** Verifies the caller's access token with Supabase Auth and loads the profile. */
export async function verifyCaller(admin: SupabaseClient, token: string | null): Promise<CallerProfile | null> {
  if (!token) return null;
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data?.user) return null;
  const { data: profile } = await admin
    .from("profiles")
    .select("id, employee_number, full_name, email, role, is_active")
    .eq("id", data.user.id)
    .maybeSingle();
  if (!profile || !profile.is_active) return null;
  return profile as CallerProfile;
}
