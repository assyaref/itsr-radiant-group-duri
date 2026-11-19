// Password policy + PIN support (pure helpers; unit-tested).
//
// Accounts may use either
//   * a PIN of 4, 5 or 6 digits, or
//   * a normal password of 6–128 characters (Supabase Auth's own minimum).
//
// Supabase Auth refuses passwords shorter than 6 characters, so a PIN is never
// given to Auth as-is: it is turned into a long secret-derived string with
// HMAC-SHA256(PIN_PEPPER, "pin:" + pin). Because PIN_PEPPER exists only in the
// Edge Function runtime, nobody can try PINs directly against the public Auth
// API; every attempt has to go through the rate-limited `login` function.
// Non-PIN passwords are passed through unchanged, so existing accounts keep
// working.

export const PIN_RE = /^\d{4,6}$/;

export function isPin(p: string): boolean {
  return PIN_RE.test(p);
}

/** Validation for a NEW password (create user, reset, change own). */
export function newPasswordError(p: unknown): string | null {
  if (typeof p !== "string" || p.length === 0) return "Password is required";
  if (isPin(p)) return null;
  if (/^\d+$/.test(p) && p.length < 4) return "PIN must be at least 4 digits";
  if (p.length < 6) return "Use a PIN of at least 4 digits or a password of at least 6 characters";
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

/** Whether PINs can be used (PIN_PEPPER configured with >= 32 characters). */
export function pinSupported(pepper: string | undefined): boolean {
  return !!pepper && pepper.length >= 32;
}

export const PIN_NOT_CONFIGURED =
  "PIN 4–6 digit belum diaktifkan oleh administrator. Gunakan password minimal 6 karakter.";

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
