# ITSR Radiant Group Duri: Security Review

**Updated:** 2026-11-09 (Phase 16). Supersedes the 2026-11-08 local-only version.

**Scope:**
- Migrations: `supabase/migrations/*` (0100–0600)
- Edge Functions: `supabase/functions/*`
- Flutter app: `lib/`
- Live state of **staging** `yzjpttfwnvnuyxbdkidm`

**Production:** not provisioned and not touched.

**Evidence labels:**
- **STAGING-EXECUTED**: read-only catalog queries or live API calls against staging. Output is in `reports/evidence/staging/`.
- **LOCAL-EXECUTED**: a throwaway PostgreSQL 18 cluster on `localhost:55433`.
- **CODE-INSPECTED**: established by reading the code only.

## 1. Findings

| # | Finding | Severity | Status |
|---|---|---|---|
| S1 | Rate-limit and outbox functions were executable by `anon`/`authenticated` (Phase 15.3 Gate 3) | Critical | **RESOLVED**. STAGING-EXECUTED: catalog C05 and C07 report 0 such grants. |
| S2 | Legacy 0001 created the `auth` schema, `auth.users` and `auth.uid()`, which would break Supabase Auth | Critical | **RESOLVED**. Legacy files are archived NO-GO. On staging, `auth.uid()` is owned by `supabase_auth_admin` (C14). The shim is LOCAL-TEST-ONLY. |
| S3 | Self-referencing `profiles` policies caused infinite recursion (legacy 0019/0020/0021) | High | **RESOLVED**. Role checks go through `private.*` SECURITY DEFINER helpers. |
| S4 | No ticket INSERT/UPDATE policies; legacy 0019's guard blocked legitimate IT updates | High | **RESOLVED**. Scoped policies, column grants and a transition guard (C10, C11). |
| S5 | Client-side ticket numbers (`count()+1`) | High | **RESOLVED**. Sequence plus trigger. The browser E2E received a server-generated `ITSR-000NN`. |
| S6 | Clients could insert activity-log rows | High | **RESOLVED**. No client grant; only triggers write history (C10). |
| S7 | The rate limiter counted every attempt per IP, so one office NAT could lock out all 50 users | High (availability) | **RESOLVED**. Counts failures only: 5 per account and 30 per IP per 15 min (L01–L04). |
| S8 | `reporter_id` could be spoofed, and clients could set status or assignee on insert | High | **RESOLVED**. A trigger forces the caller as reporter; column privileges block the rest (C11). |
| S9 | Search text was interpolated into the PostgREST `or=` filter | Medium | **RESOLVED**. `Validators.sanitizeSearch` (unit-tested). |
| S10 | The admin duplicate check interpolated email into `.or()` | Medium | **RESOLVED**. Parameterised `.eq()`. |
| S11 | Invented notification addresses were hard-coded | Medium | **RESOLVED**. Addresses come from `app_settings`; a test asserts no emails appear in `lib/`. |
| S12 | Deactivated users kept access | Medium | **RESOLVED**. `is_active` is checked in every policy, plus an Auth ban (staging API test). |
| S13 | Edge Function CORS was `*` | Low | **RESOLVED**. Fail-closed allow-list (Deno test). Staging echoes only the approved origin. |
| **S14** | `admin-users reset_password` did not validate the UUID or the maximum password length, and did not check that the target exists (new, Phase 16) | Low | **RESOLVED**. `validateResetPassword` (Deno test), deployed to staging as v4. Live smoke test: 6/6 (`phase16/10_*`). |
| **S15** | `claim_notifications` re-claimed stuck `processing` rows with **no attempts cap**, which risked endless retries or duplicate emails (new, Phase 16) | Medium (reliability) | **RESOLVED**. Migration 0600, tests N09–N12, applied to staging. C15 passes. |
| **S16** | Supabase's platform default ACL: objects created by `supabase_admin` in `public` are auto-granted EXECUTE (functions) and full rights (tables) to `anon` and `authenticated` | Medium (latent) | **MITIGATED by detection**. See §3. |

## 2. Supabase-native auth (`auth.uid()`)
- `supabase/migrations/*` never create or replace anything in the `auth` schema. The local test runner statically fails on `create schema auth`, `function auth.` and `create table auth.`.
- **STAGING-EXECUTED:** `auth.uid()` is owned by `supabase_auth_admin`, i.e. Supabase-native and not overridden.
- The emulation in `supabase/tests/local/00_supabase_shim.sql` is **LOCAL-TEST-ONLY**. It aborts if Supabase roles exist and is never part of the migration chain.

## 3. Privileges: the Gate 3 "global EXECUTE grant", investigated on the live catalog

`pg_default_acl` on staging (STAGING-EXECUTED, read-only):

| Default ACL owner | Object type | Grants to new objects |
|---|---|---|
| `postgres` (runs our migrations) | functions | `postgres` only (tightened by migration 0200) |
| `postgres` | tables / sequences | `postgres`, plus `service_role` (`Dxtm`) |
| **`supabase_admin`** (the platform) | functions | **`anon`, `authenticated`, `service_role`, `postgres`** |
| **`supabase_admin`** | tables / sequences | **all rights to `anon`, `authenticated`, `service_role`** |

**Interpretation:**
- The project's own default (the original Gate 3 root cause) is fixed.
- The **platform's** default cannot be changed by the project's roles: `ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin` requires membership in `supabase_admin`, which hosted Supabase does not grant.
- So any object the platform creates in `public` would be exposed to clients. The platform function `public.rls_auto_enable()` was a real example: it was found anon-executable in Phase 15.3 and fixed by migration 0500.

**Control:** `supabase/tests/staging/catalog_assertions.sql`.
- It is a **read-only** suite of 15 checks that works on a populated database.
- It fails if any new public function or table becomes reachable by `anon`/`authenticated`, if any table lacks RLS, if the policy count changes, or if a SECURITY DEFINER function lacks a pinned `search_path`.
- **Run it after every migration and after Supabase platform upgrades.**
- Staging results: **14/15** before 0600 (only C15 failed, as expected) → **15/15** after 0600 (`phase16/01_*`, `phase16/09_*`).

**Function ACLs on staging** (STAGING-EXECUTED). Every function is owned by `postgres`, and every SECURITY DEFINER function has `search_path=''` (C08).

| Function | Definer | anon | authenticated | service_role |
|---|---|---|---|---|
| `private.current_app_role`, `is_staff`, `is_admin`, `is_active_user` | yes | no | yes | yes |
| `private.*` trigger and helper functions | mixed | no | no | no |
| `public.ticket_stats`, `assignable_staff` | **invoker** (RLS applies) | no | yes | yes |
| `public.reporter_ticket_action` | yes (checks ownership and state) | no | yes | yes |
| `public.login_is_rate_limited`, `record_login_attempt`, `claim_notifications`, `complete_notification` | yes | no | no | yes |
| `public.rls_auto_enable` (platform event trigger) | yes | no | no | no (0500) |

## 4. Row-level security
- **STAGING-EXECUTED:** RLS is enabled on all 8 tables, with 12 policies, and `anon` has no table grants (C01–C04).

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| profiles | Own row. Staff see all. Everyone sees active staff (for assignee names). | — (Edge Function) | — (Edge Function) | — |
| tickets | Own (active user) or staff | Own, user columns only | Staff, workflow columns only | — |
| ticket_comments | Staff see all; the reporter sees non-internal comments on own tickets | Author = caller. Internal comments only by staff. Employees only on own tickets. | — | — |
| ticket_activity_log | Staff; the reporter on own tickets | — (triggers only) | — | — |
| categories | Active users | Admin | Admin | — |
| app_settings | Admin | — | Admin | — |
| notification_outbox, login_attempts | — | — | — | — |

**Browser-level proof (Phase 16 E2E, real UI against staging):**
- Opening another user's ticket URL as an employee shows "not found or you do not have access".
- Internal notes written by IT are not visible to the reporting employee.
- Employees navigating to `/queue` or `/admin/*` are redirected to the dashboard. That redirect is cosmetic; RLS is the real guard.

## 5. Service-role key
- It is used only in `supabase/functions/_shared/supabase.ts`, inside the Edge runtime where Supabase injects it. It has never been set in Flutter, `.env*` or the repo.
- The Flutter app refuses to start with an `sb_secret_…` key or a JWT whose role is `service_role` (unit-tested).
- **Phase 16 release bundle scan** (`phase16/11_*`): 0 JWT-shaped strings and 0 `sb_secret_` key material. The only literal match is the guard's own error message. The build embeds the `sb_publishable_…` key only.

## 6. Edge Functions
- **`login`:** server-side employee-number lookup, one generic error, a response time padded to at least 800 ms, fail-closed rate limiting, and inactive accounts rejected. It returns only the caller's own tokens.
- **`admin-users` (Phase 16 code, deployed 2026-11-09 01:24Z):** checks the JWT and an **active administrator** profile on every call. It validates create, update and reset input, blocks self-demotion, keeps at least one active admin, and rolls back the auth user if the profile insert fails.
- **`send-notifications`:** only drains rows the database enqueued, so calling it cannot forge an email. The caller must hold an active-user JWT or present `x-cron-secret`. User-supplied text is HTML-escaped.
- **`verify_jwt = false`:** publishable keys are not JWTs, so each function authorises requests in code.
- **CORS:** fail-closed. On staging, `ALLOWED_ORIGINS` is the Vercel Preview origin. During the Phase 16 E2E, `http://localhost:5000` was added temporarily and then **removed** (`phase16/12_*`, `phase16/14_*`).

## 7. Session handling (STAGING-EXECUTED)
- The access token lifetime is 3600 s, with rotating refresh tokens.
- A real-time test waited past `exp`. The expired token was then rejected by PostgREST, the Edge Function and Auth (`phase16/03_*`).
- Logout revokes the refresh token immediately. An already-issued access token remains valid until it expires (stateless JWT), but RLS `is_active` checks stop data access for deactivated users immediately.

## 8. Residual risks and open items
1. **Gmail delivery has not been verified.** `GMAIL_USER` and `GMAIL_APP_PASSWORD` are not set on staging, and the IT-group and manager addresses are empty. The queue works: 14 or more rows are pending and none have been lost.
2. **No retry scheduler.** `pg_cron` is not installed and no Dashboard cron job exists. Delivery is triggered after each user action. Retries of failed rows wait for the next action until a scheduler is configured (DEPLOYMENT-GUIDE §4).
3. **Initial passwords.** Administrators set them, and there is no forced change at first login. Recommendation: enable a Supabase Auth password policy and ask users to change their password.
4. **Direct email sign-in.** Supabase Auth email sign-in remains enabled. Users can bypass the employee-number login by calling Auth with their email: they get the same RLS-restricted access, but the login function's rate limit does not apply. Rely on Supabase Auth's own rate limits.
5. **Supabase WAF.** It returns an HTML 403 for classic SQL-injection strings before the request reaches `login`. This depends only on the payload, so it is not an enumeration oracle (Phase 15.4).
6. **Preview origin changes.** Every Vercel Preview deploy gets a new hostname, so `ALLOWED_ORIGINS` must be updated with each deploy. Production should use a stable domain.
