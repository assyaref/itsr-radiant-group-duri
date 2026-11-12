// Pure helpers for ticket attachments (unit-tested; no I/O).

export const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024; // 10 MB
export const MAX_ATTACHMENTS_PER_TICKET = 10;
export const ALLOWED_MIME = ["image/jpeg", "image/png", "application/pdf"] as const;
export type AllowedMime = typeof ALLOWED_MIME[number];

/** Detects the real type from the first bytes (never trust the client). */
export function sniffMime(bytes: Uint8Array): AllowedMime | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
    bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a) return "image/png";
  if (bytes.length >= 5 && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46 &&
    bytes[4] === 0x2d) return "application/pdf";
  return null;
}

/** Safe display/storage name: no paths or control characters, max 120 chars. */
export function sanitizeFileName(name: unknown, mime: AllowedMime): string {
  const ext = mime === "application/pdf" ? "pdf" : mime === "image/png" ? "png" : "jpg";
  let n = typeof name === "string" ? name : "";
  n = n.split(/[\\/]/).pop() ?? "";
  n = n.replace(/[\u0000-\u001f\u007f<>:"|?*]/g, "").replace(/\s+/g, " ").trim();
  if (!n || n === "." || n === "..") n = `lampiran.${ext}`;
  if (n.length > 120) {
    const dot = n.lastIndexOf(".");
    const e = dot > 0 && n.length - dot <= 6 ? n.slice(dot) : "";
    n = n.slice(0, 120 - e.length) + e;
  }
  return n;
}

export function decodeBase64(b64: unknown): Uint8Array | null {
  if (typeof b64 !== "string" || b64.length === 0) return null;
  try {
    const bin = atob(b64.replace(/\s/g, ""));
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

export type UploadCheck =
  | { ok: true; bytes: Uint8Array; mime: AllowedMime; name: string }
  | { ok: false; error: string };

export function checkUpload(fileName: unknown, dataBase64: unknown): UploadCheck {
  const bytes = decodeBase64(dataBase64);
  if (!bytes) return { ok: false, error: "File is empty or not valid" };
  if (bytes.length > MAX_ATTACHMENT_BYTES) return { ok: false, error: "File is larger than 10 MB" };
  const mime = sniffMime(bytes);
  if (!mime) return { ok: false, error: "Only JPG, PNG and PDF files are allowed" };
  return { ok: true, bytes, mime, name: sanitizeFileName(fileName, mime) };
}

/** multipart/related body for the Drive v3 upload endpoint. */
export function driveMultipart(
  metadata: Record<string, unknown>,
  bytes: Uint8Array,
  mime: string,
  boundary = "itsr" + crypto.randomUUID().replace(/-/g, ""),
): { body: Uint8Array<ArrayBuffer>; contentType: string } {
  const enc = new TextEncoder();
  const head = enc.encode(
    `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n` +
      `--${boundary}\r\nContent-Type: ${mime}\r\n\r\n`,
  );
  const tail = enc.encode(`\r\n--${boundary}--\r\n`);
  const body = new Uint8Array(new ArrayBuffer(head.length + bytes.length + tail.length));
  body.set(head, 0);
  body.set(bytes, head.length);
  body.set(tail, head.length + bytes.length);
  return { body, contentType: `multipart/related; boundary=${boundary}` };
}
