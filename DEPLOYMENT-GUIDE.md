# ITSR Radiant Group Duri — Deployment Guide

Audience: the engineer deploying to Supabase staging, then production. **Production steps need explicit approval.**

## 0. Prerequisites
- Supabase CLI ≥ 2.x (`npm i -g supabase` or scoop). Flutter 3.47.x / Dart 3.13.x.
- Access to the staging project `yzjpttfwnvnuyxbdkidm`. Note: `yzjptffw…`, as written in some earlier reports, does not exist.
- A Gmail or Google Workspace account to send mail, with 2-Step Verification and an **App Password**.
- **Never** put the service-role/secret key into Flutter, `.env.*` files in the repo, or chat.

## 1. Back up first
```bash
supabase link --project-ref yzjpttfwnvnuyxbdkidm
supabase db dump -f backups/staging_$(date +%Y%m%d_%H%M).sql          # schema
supabase db dump --data-only -f backups/staging_data_$(date +%Y%m%d_%H%M).sql
```
Check that both files are non-empty before continuing.

## 2. Pre-flight
**Current state (2026-11-09):** staging has `20261108000100…0500` and `20261109000600` applied. A **new** environment (e.g. production) starts with none of them.
```bash
supabase migration list           # compare Local vs Remote; only the missing ones will be pushed
supabase db push --dry-run        # must list exactly the migrations you expect
```
Run the local suite once more: `PSQL=psql PGPORT=<free port> bash supabase/tests/local/run_local_db_tests.sh` must end with `failed=0`.
**Do not** run anything in `migrations/legacy/` or `supabase/tests/local/` against Supabase. The shim refuses to run there anyway.

## 3. Apply migrations (staging)
```bash
supabase db push                  # applies supabase/migrations/* in order
```
Then run the **read-only** post-deploy check, `supabase/tests/staging/catalog_assertions.sql`. Paste it into the SQL editor, or run `psql -f`. **All 15 rows must show `passed = true`.**
- It checks RLS on every table, the policy count, zero `anon` grants, the exact set of client-callable RPCs, the service-only RPCs, pinned `search_path`, column privileges, a native `auth.uid()`, and the 0600 retry cap.
- Re-run it after Supabase platform upgrades too. Platform-created objects inherit the `supabase_admin` default ACL, which grants `anon`; see SECURITY-REVIEW §3.

| Migration | Rollback |
|---|---|
| `20261109000600_notification_retry_cap` | Function-only change. Re-run the `claim_notifications` definition from `20261108000400_…` (`create or replace`). The pre-change definition on staging is saved in `reports/evidence/staging/phase16/04_pre_0600_backup.json`. |
| `20261108000500_restrict_rls_auto_enable_execute` | `grant execute on function public.rls_auto_enable() to public;` (restores the platform default; not recommended). |
| `0100`–`0400` | See below. **Staging now contains synthetic test data**, so restore from the §1 backup rather than dropping objects. |

**Full rollback of 0100–0400.** Use this only on an environment with **no data worth keeping**:
```sql
drop schema private cascade;
drop table if exists public.notification_outbox, public.login_attempts, public.ticket_activity_log,
  public.ticket_comments, public.tickets, public.app_settings, public.categories, public.profiles cascade;
drop sequence if exists public.ticket_number_seq;
drop function if exists public.ticket_stats(text), public.reporter_ticket_action(uuid,text,text),
  public.assignable_staff(), public.login_is_rate_limited(text,text,integer,integer,integer),
  public.record_login_attempt(text,text,uuid,boolean), public.claim_notifications(integer),
  public.complete_notification(uuid,text,text,text[],text[]);
delete from supabase_migrations.schema_migrations where version like '20261108%';
```
If data already exists, restore from the §1 backup instead of dropping.

## 4. Edge Functions and secrets
```bash
supabase secrets set GMAIL_USER="<sender@your-domain>" GMAIL_APP_PASSWORD="<16-char app password>"
supabase secrets set ALLOWED_ORIGINS="https://<your-itsr-host>"          # comma-separated
supabase secrets set NOTIFICATIONS_CRON_SECRET="$(openssl rand -hex 32)"  # optional, for the scheduler
supabase secrets set PIN_PEPPER="<stable random secret, at least 32 characters>" # required for 4–5 digit PIN login
supabase functions deploy login
supabase functions deploy admin-users
supabase functions deploy send-notifications
```
`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected by Supabase. `verify_jwt=false` comes from `supabase/config.toml`; each function authorises requests itself.
Generate `PIN_PEPPER` in a secure secret manager and never commit it. Keep it stable: changing it invalidates existing PINs, which must then be reset.

**Retry scheduler (recommended; NOT configured on staging yet).** In Dashboard → Integrations → Cron, create a job that runs every minute. It should POST `https://<ref>.supabase.co/functions/v1/send-notifications` with header `x-cron-secret: <secret>`.
- The app also triggers delivery right after each action.
- Without a scheduler, failed rows are retried only on the next user action.
- Since migration 0600, each row is tried at most 5 times and is then marked `failed` with the reason.

**`ALLOWED_ORIGINS` on Vercel Previews:** every Preview deploy gets a new hostname, so update the secret after each deploy. Production should use one stable domain.

**Verify email delivery** (closes the last BLOCKED item):
1. Set the two Gmail secrets above.
2. In Admin → Settings, enter real IT-group and manager addresses.
3. Create a ticket. The staging `STG*` accounts use undeliverable `@example.com` addresses, so give at least one test account a real inbox.
4. Check that `select status, count(*) from notification_outbox group by 1;` shows `sent` rows, and confirm the mail arrived in the inbox.

## 5. Bootstrap the first administrator
1. Dashboard → Authentication → Add user: email + strong password, auto-confirm.
2. SQL editor (replace the placeholders; do not invent values):
```sql
insert into public.profiles (id, employee_number, full_name, email, department, role)
select id, '<EMPLOYEE_NO>', '<Full Name>', email, 'IT', 'administrator'
from auth.users where email = '<admin email>';
```
3. Sign in to the app as that admin. Under **Settings**, set the IT group email, the manager email and the application URL. Under **Users**, create the IT Support staff and employees.

## 6. Build and host the web app
```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=https://yzjpttfwnvnuyxbdkidm.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key sb_publishable_…> \
  --dart-define=ENVIRONMENT=staging
```
Serve `build/web/` from any static host (Nginx/IIS/Vercel/Netlify/Supabase Storage + CDN). The app uses hash URLs (`/#/tickets/<id>`), so no rewrite rules are needed. For a local check, use a free port such as `python -m http.server 5000 -d build/web`. **Do not** use 8080 (ERPNext) or 5432/5433. A local origin only works against a backend whose `ALLOWED_ORIGINS` contains it, so add it temporarily and remove it afterwards.

Before uploading, scan the bundle: `grep -oE "sb_secret_[A-Za-z0-9_-]{8,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}" build/web/main.dart.js` must print nothing.

## 7. Staging smoke test (closes the BLOCKED rows in FINAL-TEST-REPORT)
Create the test accounts in Admin → Users: EMP-A, EMP-B (employees), IT-1 (IT Support).
1. Wrong password ×5 for EMP-A → "Too many login attempts". EMP-B can still sign in from the same network.
2. EMP-A creates a ticket → it gets an `ITSR-000NN` number. IT-1 and the group receive email; the manager is CC'd.
3. EMP-B cannot see EMP-A's ticket (the list is empty; opening the URL directly shows "not found").
4. IT-1: Accept → Start work → internal note (EMP-A must not see it) → public comment (EMP-A gets email) → Resolve with resolution (EMP-A gets email).
5. EMP-A: Reopen with a reason, then IT resolves again, then EMP-A confirms and closes. Check that History shows every step with names.
6. Admin: deactivate EMP-B → EMP-B cannot sign in. Change IT-1's role. Add or deactivate a category.
7. Check mobile layout on a phone and desktop layout in a browser.
8. SQL editor: `select status, count(*) from notification_outbox group by 1;` should show no `failed` rows.

## 8. Production
Repeat §1–§7 against the production project **only after written approval**, using production keys passed through `--dart-define`.
