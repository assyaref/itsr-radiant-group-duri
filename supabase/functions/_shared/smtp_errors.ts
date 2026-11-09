// Pure classification of email send failures (unit-tested; no I/O).
//
//   permanent -> retrying can never help (recipient/message rejected with an
//                SMTP 5xx reply, or the ticket no longer exists). The outbox row
//                is marked permanent_failure and is never claimed again.
//   temporary -> network/TLS problems, timeouts, SMTP 4xx "try later" replies,
//                anything unknown. The row is retried (max 5 attempts in total,
//                enforced by claim_notifications in the database).
//
// Authentication failures (535/534/EAUTH) are a configuration problem that
// affects every row; the sender checks SMTP login BEFORE claiming rows, so
// they never consume attempts. If one still happens mid-batch it is treated
// as temporary so the row is retried once credentials are fixed.

export type FailureKind = "permanent" | "temporary";

export class PermanentError extends Error {
  constructor(message: string) { super(message); this.name = "PermanentError"; }
}

interface SmtpLikeError { code?: unknown; responseCode?: unknown; message?: unknown }

const AUTH_CODES = new Set([530, 534, 535]);

export function classifySendError(e: unknown): FailureKind {
  if (e instanceof PermanentError) return "permanent";
  if (!e || typeof e !== "object") return "temporary";
  const err = e as SmtpLikeError;
  const rc = typeof err.responseCode === "number" ? err.responseCode : null;
  const code = typeof err.code === "string" ? err.code : "";
  if (code === "EAUTH" || (rc !== null && AUTH_CODES.has(rc))) return "temporary";
  if (rc !== null && rc >= 500 && rc < 600) return "permanent";
  // EENVELOPE without an SMTP reply = no valid recipient address at all.
  if (code === "EENVELOPE" && rc === null) return "permanent";
  return "temporary";
}

/** Short, secret-free description for last_error (never includes credentials). */
export function describeSendError(e: unknown): string {
  if (e && typeof e === "object") {
    const err = e as SmtpLikeError;
    const parts = [
      typeof err.code === "string" ? err.code : null,
      typeof err.responseCode === "number" ? String(err.responseCode) : null,
      typeof err.message === "string" ? err.message : null,
    ].filter((p): p is string => !!p);
    if (parts.length) return parts.join(" ").slice(0, 500);
  }
  return String(e).slice(0, 500);
}
