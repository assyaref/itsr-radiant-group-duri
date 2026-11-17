import { authPassword, plausibleLoginPassword, pinSupported } from "../_shared/password.ts";

Deno.test("login password validation matches the known-good PIN policy", () => {
  if (plausibleLoginPassword("abcde")) throw new Error("five-character non-PIN password should be rejected");
  if (!plausibleLoginPassword("abcdef")) throw new Error("six-character password should be accepted");
  if (!plausibleLoginPassword("03233")) throw new Error("five-digit PIN should be accepted");
  if (!plausibleLoginPassword("1234")) throw new Error("four-digit PIN should be accepted by the password policy");
  if (plausibleLoginPassword("x".repeat(129))) throw new Error("oversized password should be rejected");
});

Deno.test("PIN auth password is secret-derived and regular passwords stay unchanged", async () => {
  const pepper = "test-only-pepper-value-with-at-least-32-characters";
  if (!pinSupported(pepper)) throw new Error("valid pepper should enable PINs");
  const pin = await authPassword("03233", pepper);
  if (!pin.startsWith("pin1.") || pin.length <= 6) throw new Error("PIN should be transformed");
  if (await authPassword("03233", pepper) !== pin) throw new Error("PIN transform should be stable");
  if (await authPassword("abcdef", undefined) !== "abcdef") {
    throw new Error("non-PIN password should remain unchanged");
  }
});

Deno.test("PIN auth password refuses an absent pepper", async () => {
  let rejected = false;
  try {
    await authPassword("03233", undefined);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("PIN without a pepper should be rejected");
});
