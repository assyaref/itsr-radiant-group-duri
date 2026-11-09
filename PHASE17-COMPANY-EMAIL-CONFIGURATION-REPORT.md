# PHASE 17 — IT SUPPORT COMPANY EMAIL CONFIGURATION

**Project:** ITSR Radiant Group Duri  
**Official IT Support email:** `it.support-duri@radiant-utama.com`  
**Status:** Configuration prepared — NO email sent, NO backlog released, NO credentials stored.  
**Date:** 2026-11-09  

---

## 1. Recipient configuration status

### Audit result (before Phase 17 changes)

| Item | Source | Value |
|------|--------|-------|
| `app_settings` table | `supabase/migrations/20261108000100_core_schema.sql` | Singleton row `id = true`; `it_support_group_email` and `manager_email` are both `text`, nullable, constrained `position('@' in x) > 1` |
| Schema comment | Migration 0100, lines 116-117 | Addresses are intentionally NULL — entered by an administrator, never invented |
| `it_support_group_email` (staging) | `reports/evidence/staging/phase17/04_pre_0700_backup.json`, `11_post_test_residue_check.json` | `NULL` |
| `manager_email` (staging) | same | `NULL` |
| Flutter settings UI | `lib/screens/admin/settings_screen.dart`, `lib/data/admin_repository.dart` | Already supports editing both addresses (validator: `Validators.email`, required: false) |
| Notification rules consumer | `supabase/functions/_shared/notification_rules.ts` | `it_support_group_email` used as new-ticket fallback recipient and CC for all events |

### Change made

New migration: `supabase/migrations/20261109000800_company_it_support_email.sql`

```sql
update public.app_settings
   set it_support_group_email = 'it.support-duri@radiant-utama.com'
 where id = true;
```

- `it_support_group_email` is now configured to `it.support-duri@radiant-utama.com`.
- `manager_email` is **not** modified — remains `NULL` until the actual Manager email address is provided (task constraint).
- The configured address passes the schema check constraint (`position('@' in it.support-duri@radiant-utama.com) > 1`).
- The migration touches only `app_settings`. The 36 `notification_outbox` rows are untouched (still `held`).

### To apply

Run against the target project (staging first, production only with written approval):

```bash
supabase db push
```

Then verify:

```sql
select it_support_group_email, manager_email, notifications_enabled
from public.app_settings where id = true;
-- Expected: it.support-duri@radiant-utama.com | NULL | true
```

This migration must be applied before any notification delivery can address the IT Support group; by itself it does not send email.



---

## 2. SMTP provider requirements

### Audit of `supabase/functions/send-notifications/index.ts`

The Edge Function drains `public.notification_outbox` and sends email through **nodemailer** with the following hard-coded transport:

```ts
const transport = nodemailer.createTransport({
  host: "smtp.gmail.com", port: 465, secure: true, auth: { user, pass },
});
const from = `"${Deno.env.get("MAIL_FROM_NAME") ?? "ITSR Radiant Group Duri"}" <${user}>`;
```

Required runtime secrets (read from `Deno.env`, injected by Supabase — never in Flutter/GitHub):

| Secret | Purpose | Configured? |
|--------|---------|-------------|
| `GMAIL_USER` | SMTP AUTH username (sender address) | **No** |
| `GMAIL_APP_PASSWORD` | 16-char Google App Password for that account | **No** |
| `NOTIFICATIONS_CRON_SECRET` | Cron job authorization header | Set (name only) |
| `ALLOWED_ORIGINS` | CORS allow-list | Set (staging preview origin) |
| `MAIL_FROM_NAME` | Friendly from name (optional) | Not set |

Behavior when credentials are missing (confirmed by `reports/evidence/staging/phase17/15_cron_first_runs_no_gmail.json`):

- HTTP 503: `Email is not configured (GMAIL_USER / GMAIL_APP_PASSWORD)`
- Outbox unchanged: 36 rows, all `held`

### Gmail-specific vs provider-agnostic

**The current implementation specifically requires Gmail SMTP.** The host (`smtp.gmail.com`), port (465), secure flag (`true`), and secret names (`GMAIL_USER`, `GMAIL_APP_PASSWORD` / Google App Password) are hard-coded. It **cannot** send through the company's actual mail provider (`radiant-utama.com`) unless:

1. The company mail is confirmed to be hosted by Google Workspace **and** `GMAIL_USER`/`GMAIL_APP_PASSWORD` are set for `it.support-duri@radiant-utama.com` (or another Google account), **or**
2. The function is generalized to read `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS` (or equivalent) from Supabase Secrets and the IT team supplies the real values.

Per the task constraints: **we do not assume Google Workspace**, and we **do not invent** SMTP hostnames, ports, passwords, or credentials. Therefore no SMTP changes were made and no secrets were set.

---

## 3. Required credentials

When the IT department confirms the mail provider for `radiant-utama.com`, the following are needed — **all stored only in Supabase Secrets (`supabase secrets set`), never in Flutter Web or GitHub, never printed:**

| Credential | Notes |
|------------|-------|
| SMTP sender address | e.g. `it.support-duri@radiant-utama.com` or a dedicated sending mailbox on that domain |
| SMTP password / App Password | for the sender address |
| SMTP host | e.g. `smtp.<provider>.com` — obtain from the mail provider; not invented here |
| SMTP port + TLS/secure flag | per provider (465/587/25, SSL/TLS/STARTTLS) |
| `MAIL_FROM_NAME` | optional display name |

Until these are provided and configured, `send-notifications` returns 503 and all outbox rows remain `held`. Nothing in this phase sends or attempts to send email.

---

## 4. Configuration changes made

| File | Change |
|------|--------|
| `supabase/migrations/20261109000800_company_it_support_email.sql` | **New.** Sets `it_support_group_email = 'it.support-duri@radiant-utama.com'` where `id = true`. |
| `PHASE17-COMPANY-EMAIL-CONFIGURATION-REPORT.md` | **New.** This report. |

### Deliberately NOT changed

- `manager_email` — left `NULL` pending the actual Manager address.
- `supabase/functions/send-notifications/index.ts` — not modified; still Gmail-hardcoded (audit result reported in §2).
- Flutter client (`lib/`) — no changes needed; the Settings screen already writes `it_support_group_email`.
- Supabase Secrets — none set; no credentials known or invented.
- `public.notification_outbox` — all 36 rows remain `held`; none claimed, deleted, released, or backfilled.

---

## 5. Remaining blockers

1. **Apply migration 0800 to staging** (`supabase db push`), then run `supabase/tests/staging/catalog_assertions.sql` to confirm no RLS/privilege drift. Production only after written approval.
2. **Manager email address not provided** — `manager_email` stays NULL; manager CCs will not be configured until supplied.
3. **Company mail provider unknown** — cannot assume Google Workspace for `radiant-utama.com`.
4. **No SMTP credentials** — `GMAIL_USER`/`GMAIL_APP_PASSWORD` (or provider-equivalent secrets) are not configured; the function returns 503 until they are.
5. **Function is Gmail-locked** — to support a non-Google provider, `send-notifications/index.ts` must be generalized to read SMTP host/port/secure/user/pass from env; no values invented here.
6. **36 held notifications** — `notification_outbox` rows remain `held`; do not release or process the backlog until SMTP is configured and the IT team explicitly authorizes delivery.

---

## Security confirmation

- No sender credentials exist in this change set, in Flutter Web, or in GitHub.
- No secret values were printed or logged.
- Staging security policies (RLS, service-role-only outbox RPCs, CORS allow-list) are preserved; nothing in this phase alters them.
- **No test emails were sent.** The send-notifications function was not invoked for delivery.

