# ITSR — Staging Migration & Deployment Execution Report

> **UPDATE 2026-11-08 ~08:13 UTC (Phase 15.3 security remediation):** the Vercel deviation is **resolved**.
> - All deployments now require Vercel authentication; the production aliases serve only a placeholder.
> - The app is a **Preview**: `https://itsr-radiant-staging-2vj2mwxa8-assyaref75.vercel.app`.
> - `ALLOWED_ORIGINS` is pinned to that origin, so there is no more `*`.
> - Migration **0500** revokes client EXECUTE on `rls_auto_enable()`; the staging suite is now **96/96**, with P02b passing.
>
> See **PHASE15.3-VERCEL-STAGING-SECURITY-REPORT.md** and `reports/evidence/staging/phase15.3-vercel/`.

**Date:** 2026-11-08 · **Target:** Supabase `itsr-radiant-staging` (`yzjpttfwnvnuyxbdkidm`) only · **Production Supabase:** not accessed (the CLI account can see only this one project)
**Authorization:** owner approval for 0100–0400, the three Edge Functions, and a Vercel **Preview**. Gmail may stay BLOCKED.
Raw evidence is in `reports/evidence/staging/` (files numbered 01–19, cited below as `[NN]`).

## Status summary
| Step | Result |
|---|---|
| Pre-checks (ref, empty schema, file integrity, plan) | **PASS** |
| Migrations 0100 → 0400 | **APPLIED.** Exit 0, 07:44:40–07:44:46 UTC `[05]` |
| Post-migration catalog verification | **PASS.** Identical to the reviewed local evidence `[06]` |
| Staging SQL security tests | **95/95 reviewed assertions PASS.** 1 staging-only add-on FAILED (informational, see §4) `[08]` |
| PostgREST anonymous probes | **PASS.** All app tables and RPCs denied `[10]` |
| Edge Functions (login, admin-users, send-notifications) | **DEPLOYED v1, ACTIVE, smoke tests PASS** `[14][15]` |
| Gmail | **BLOCKED** (as authorized). `send-notifications` returns 503 and outbox rows stay pending |
| Vercel | **DEVIATION.** Build is deployed, but Vercel assigned the **production** target and a **public** alias (§6). Awaiting owner decision. |

## 1. Pre-execution checks
- **Linked project:** `supabase/.temp/project-ref` = `yzjpttfwnvnuyxbdkidm`. `projects list` shows only `itsr-radiant-staging` (●linked, Singapore). The ref was re-checked inside the push command itself.
- **Public schema empty** `[01][02]`:
  - 0 tables and 0 auth users; no `private` schema; `schema_migrations` had 0 rows.
  - The only object found was `public.rls_auto_enable()`, which is platform-installed (event trigger `ensure_rls`).
- **File integrity:** no SHA-256 was recorded at review time.
  - The files were last modified at 09:18–09:19, and the review and evidence were written at 12:51–12:53.
  - The hashes were captured below and re-checked with `sha256sum -c` immediately before the push, and all passed `[05]`.
  ```
  e24ed85aa4160e9fe4ebeb93e12358b001955e34263cee2f3e596af94c2b4e2f  20261108000100_core_schema.sql
  d53a875c4f3c320038e9d6b3c75a55a0e738bedf345196258c9a07b0ea355689  20261108000200_security_privileges_rls.sql
  3b4407d7fe8c572a60bb15afd2a7dba7e4aba74309a758e49b0f656a57eccb25  20261108000300_ticket_workflow.sql
  1a44ef3219c7b0a51b7a8d8a4cbd3dfa931bce2aeced9d6632926a01608bf1c4  20261108000400_login_and_notifications.sql
  ```
- **Plan:**
  - `migration list` showed 4 local migrations and 0 remote `[03]`.
  - `db push --dry-run` planned exactly those 4 files, in order `[04]`.
  - A scan for destructive statements found no DROP or TRUNCATE. The only `delete` statements are inside the login-attempt cleanup functions.
- **Initial-state evidence:** a catalog snapshot, `[01][02]`. No `pg_dump` was taken, because no DB password was supplied, and the schema contained no application data to back up.
- **Credentials:**
  - The existing Supabase CLI login was used, for `db push` (temporary login role) and for Management API SQL queries (token read in memory from Windows Credential Manager).
  - No secret was printed or written to the repo. The publishable key was saved to `%USERPROFILE%\.itsr-staging\publishable-key`; secret and service-role keys were filtered out unread.
  - `db reset` was not used, and no destructive command was run.

## 2. Execution
`npx supabase@2.54.11 db push` was run without `--include-all`. Each file was applied in order (0100, 0200, 0300, 0400), and the push finished with exit 0 `[05]`.
Afterwards, remote migration history shows all four versions `[06][12]`.

## 3. Post-migration verification `[06]`
- **Tables (8):** app_settings, categories, login_attempts, notification_outbox, profiles, ticket_activity_log, ticket_comments, tickets. All are owned by `postgres`, and **RLS is enabled on all 8**.
- **Policies (12):** these match the reviewed list exactly. All are scoped to the `authenticated` role, and `anon` has none.
- **Table privileges:**
  - `anon`: none on any table.
  - `authenticated`: SELECT only at table level. Writes are limited to column-level grants:
    - tickets INSERT (subject, description, category, subcategory, priority, reporter_id)
    - tickets UPDATE (category, subcategory, priority, status, assigned_to_id, resolution)
    - comments INSERT
    - categories INSERT/UPDATE
    - app_settings UPDATE
  - `service_role`: full access.
- **Sequence:** `ticket_number_seq` has no usage grant for anon or authenticated.
- **Schemas:** `anon` has no USAGE on `private`.
- **Default ACL for postgres-created functions:** `{postgres=X}` only, which closes the root cause of the Gate 3 finding.
- **Functions:** the same 20 app functions as the local evidence.
  - Every function is owned by `postgres` and has `search_path=""`. The SECURITY DEFINER settings are identical.
  - `anon` can execute **none** of them.
  - The login and outbox RPCs (`login_is_rate_limited`, `record_login_attempt`, `claim_notifications`, `complete_notification`) are executable by `service_role` only.
- **Triggers (9):** 3 `touch_updated_at`, 2 on comments, 4 on tickets. All enabled.
- **Indexes (21):** the primary keys, unique keys (categories.name, profiles.email, profiles.employee_number, tickets.ticket_number), plus the assignee, created, reporter, status, ticket, outbox-pending and login-attempt indexes.
- **Seed data:** 6 categories and 1 app_settings row.

## 4. Staging SQL security tests `[08]`
The suite is `supabase/tests/staging/staging_security_tests.sql`, generated from the reviewed local harness and suite.
- **Safety:** the whole run is one transaction. It ends with `RAISE EXCEPTION` carrying the results, which forces a rollback. The ticket sequence is restored, because sequences ignore rollback.
- **No residue** `[11]`: there is no `test` schema, 0 users, 0 tickets, 0 outbox rows, and the sequence is back at `1/false`.
- **Result:** 96 run, 95 pass, 1 fail.
  - **All 95 assertions from the reviewed local suite pass** on real Supabase. This includes P01–P09 (Gate 3), the anon, employee-isolation, inactive-user, IT workflow, reporter, stats, admin, notification and rate-limit tests.
  - P02 was adjusted to exclude event-trigger functions; it still passes.
  - **FAIL: P02b, a staging-only add-on.** The test assumed `anon` could not call the platform function `public.rls_auto_enable()` directly. In fact a direct SQL call succeeds as a no-op `[09]`.
- **Impact analysis:**
  - Through the API, PostgREST returns `400 cannot display a value of type event_trigger` `[10]`.
  - The function body only acts on DDL commands from the current event-trigger context, and its only action is *enabling* RLS on new public tables.
  - **Severity: informational, not exploitable.** It is a Supabase platform object outside the authorized change, so it was **not modified**.
  - Optional hardening, as a future reviewed migration: `revoke execute on function public.rls_auto_enable() from public, anon, authenticated;`

## 5. Edge Functions `[13][14][15]`
- **Source:** unchanged since the Deno tests (12 of 12 passed). Hashes are in `[13]`.
- **Deploy:** `functions deploy login admin-users send-notifications --use-api --project-ref yzjpttfwnvnuyxbdkidm`. All three are ACTIVE at v1 (07:49:18 UTC).
- **Smoke tests:**

| Check | Result |
|---|---|
| CORS preflight | 200 |
| GET on `login` | 405 |
| Bad JSON | 400 (generic message) |
| Short password | 401 |
| Unknown employee | 401, not 429. The rate-limit RPC ran as service_role, and 1 row `SMOKETEST01` was recorded in `login_attempts` (removed by the 30-day cleanup) |
| `admin-users` with no JWT or a non-JWT bearer | 401 |
| `send-notifications` with no JWT or a wrong cron secret | 401 |

- **Secrets:**
  - `ALLOWED_ORIGINS` is **not set yet**, so CORS is `*`. It should be set to the final Vercel origin.
  - `NOTIFICATIONS_CRON_SECRET` is not set, so the cron path is disabled.
  - `GMAIL_*` is BLOCKED.

## 6. Vercel — DEVIATION (owner decision required) `[16]–[19]`
- **Build:** Flutter web release, staging URL plus publishable key, built in 74 s `[16]`.
- **Bundle scan** `[17]`: 0 `sb_secret_` matches and 0 JWTs. Only the publishable key is embedded, as expected.
- **Deploy:** project `itsr-radiant-staging` (`prj_dBhijO1rM3apNtiA8lGcFIVypFn0`) was created and deployed with `vercel deploy --target preview` `[18]`.
- **What Vercel did:** it recorded deployment `dpl_EkNjNzCDe5sitjWwyVTntTJwaJyL` with **target = production**, because this was the project's first deployment. It also assigned the production aliases.
- **Access check** `[19]`:

| URL | Result |
|---|---|
| `https://itsr-radiant-staging.vercel.app` | **200, public, no login** |
| `https://itsr-radiant-staging-assyaref75.vercel.app` | 302 to Vercel SSO (protected) |
| `https://itsr-radiant-staging-13dyd4g5f-assyaref75.vercel.app` | 302 to Vercel SSO (protected) |

- **Risk:** low. The public alias serves only the staging app shell, backed by the staging DB, which has 0 users and denies all anonymous data access `[10]`.
- **Condition broken:** this is not the "Preview-only, no production deployment" condition. No further Vercel changes were made, pending the owner's choice of remediation.

## 7. Not done / open items
- The Vercel remediation decision (§6).
- `ALLOWED_ORIGINS` and `NOTIFICATIONS_CRON_SECRET` secrets.
- Gmail credentials (BLOCKED).
- First-admin bootstrap and end-to-end UI smoke test (DEPLOYMENT-GUIDE §5 and §7).
- No `pg_dump` backup, because there was no DB password and the schema was empty beforehand.
