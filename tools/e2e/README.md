# tools/e2e — staging verification scripts (Node ≥ 20)

These scripts verify a **staging** deployment from a workstation. They read the synthetic test-account credentials and publishable key from `%USERPROFILE%\.itsr-staging\` (`test-accounts.json`, `publishable-key`). Credentials are never stored in this repository, and the scripts never print them.

| Script | What it does | Writes to staging? |
|---|---|---|
| `e2e.mjs <outDir>` | Browser E2E of the real Flutter Web build via headless Chrome (`npm i playwright-core@1.48.2`). Covers employee, IT Support, admin, and a phone layout: 27 checks. Expects `other_ticket_id.txt` next to it, holding the id of a ticket **not** owned by the employee. | Yes: one ticket, comments and status changes (synthetic) |
| `m03.mjs <#/tickets/id> <outDir>` | Phone ticket-detail retest with scrolling. Under Git Bash, prefix with `MSYS_NO_PATHCONV=1`. | No |
| `expiry-test.mjs <out.json>` | Real-time session expiry: logs in, waits past `exp` (~62 min), and checks that PostgREST, the Edge Function and Auth reject the token. | Login attempt rows only |
| `reset-smoke.mjs <out.txt>` | `admin-users reset_password` validation, using invalid or non-existent targets only. | No |
| `serve.mjs <build/web>` | Minimal static server on `127.0.0.1:5000`. | — |
| `secret-scan.mjs <repo> <out.txt>` | Pre-commit scan of **staged** files: key and token patterns plus the exact local secrets. Prints file names only. | — |

**Browser E2E prerequisites:**
1. `flutter build web --release` with the staging URL and the publishable key.
2. Temporarily add `http://localhost:5000` to staging's `ALLOWED_ORIGINS`, and **remove it afterwards**.
3. Never use port 8080 (ERPNext) or 5432/5433.

Flutter Web is driven through its accessibility tree. The scripts click the hidden "Enable accessibility" placeholder first. That also makes these tests a check that the UI is usable with a screen reader.
