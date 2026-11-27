// Google Drive access shared by the `attachments` and `send-notifications`
// Edge Functions. OAuth with the folder owner's refresh token. Secrets:
//   GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET,
//   GOOGLE_OAUTH_REFRESH_TOKEN, GOOGLE_DRIVE_FOLDER_ID

export interface DriveConfig { clientId: string; clientSecret: string; refreshToken: string; folderId: string }

export function driveConfig(): DriveConfig | null {
  const clientId = Deno.env.get("GOOGLE_OAUTH_CLIENT_ID");
  const clientSecret = Deno.env.get("GOOGLE_OAUTH_CLIENT_SECRET");
  const refreshToken = Deno.env.get("GOOGLE_OAUTH_REFRESH_TOKEN");
  const folderId = Deno.env.get("GOOGLE_DRIVE_FOLDER_ID");
  if (!clientId || !clientSecret || !refreshToken || !folderId) return null;
  return { clientId, clientSecret, refreshToken, folderId };
}

export async function driveToken(cfg: DriveConfig): Promise<string> {
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: cfg.clientId,
      client_secret: cfg.clientSecret,
      refresh_token: cfg.refreshToken,
      grant_type: "refresh_token",
    }),
    signal: AbortSignal.timeout(15_000),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || typeof data.access_token !== "string") {
    throw new Error(`google token refresh failed (${res.status} ${data.error ?? ""})`);
  }
  return data.access_token;
}

/** Downloads a Drive file's bytes; null when Drive refuses or times out. */
export async function driveDownload(token: string, fileId: string, timeoutMs = 30_000): Promise<Uint8Array | null> {
  try {
    const res = await fetch(
      `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?alt=media&supportsAllDrives=true`,
      { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(timeoutMs) },
    );
    if (!res.ok) {
      console.error("drive download failed", res.status);
      await res.body?.cancel();
      return null;
    }
    return new Uint8Array(await res.arrayBuffer());
  } catch (e) {
    console.error("drive download error", e instanceof Error ? e.message : String(e));
    return null;
  }
}
