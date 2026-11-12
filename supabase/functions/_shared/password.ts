// Password policy + PIN support (pure helpers; unit-tested).
//
// Accounts may use either
//   * a PIN of exactly 4 or 5 digits, or
//   * a normal password of 8–128 characters (6–128 accepted at login for
//     accounts created before this policy).
//
// Supabase Auth refuses passwords shorter than 6 characters, so a PIN is never
// given to Auth as-is: it is turned into a long secret-derived string with
// HMAC-SHA256(PIN_PEPPER, "pin:" + pin). Because PIN_PEPPER exists only in the
// Edge Function runtime, nobody can try PINs directly against the public Auth
// API; every attempt has to go through the rate-limited `login` function.
// Non-PIN passwords are passed through unchanged, so existing accounts keep
// working.

export const PIN_RE = /^\d{4,5}$/;

export function isPin(p: string): boolean {
  return PIN_RE.test(p);
}

/** Validation for a NEW password (create user, reset, change own). */
export function newPasswordError(p: unknown): string | null {
  if (typeof p !== "string" || p.length === 0) return "Password is required";
  if (isPin(p)) return null;
  if (/^\d+$/.test(p) && p.length < 8) return "A numeric PIN must be exactly 4 or 5 digits";
  if (p.length < 8) return "Password must be a 4–5 digit PIN or at least 8 characters";
  if (p.length > 128) return "Password is too long";
  return null;
}

/** Shape check for a password typed at LOGIN (no policy messages leak). */
export function plausibleLoginPassword(p: unknown): p is string {
  return typeof p === "string" && (isPin(p) || (p.length >= 6 && p.length <= 128));
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * The password actually stored in / sent to Supabase Auth.
 * PINs need PIN_PEPPER (min. 32 characters); without it PINs are refused.
 */
export async function authPassword(raw: string, pepper: string | undefined): Promise<string> {
  if (!isPin(raw)) return raw;
  if (!pepper || pepper.length < 32) throw new Error("PIN_PEPPER is not configured");
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(pepper), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`pin:${raw}`)));
  return `pin1.${b64url(mac)}`;
}
