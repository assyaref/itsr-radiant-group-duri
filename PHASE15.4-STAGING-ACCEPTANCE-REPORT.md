# ITSR: Phase 15.4 Staging Functional Acceptance Report

**Date:** 2026-11-08 (08:20–09:30 UTC)
**Target:** Supabase **staging** `yzjpttfwnvnuyxbdkidm`, plus the Vercel **Preview** `https://itsr-radiant-staging-2vj2mwxa8-assyaref75.vercel.app`
**Production:** untouched. No production Supabase project is visible to the CLI account, and there was no Vercel production deploy.
**Evidence:** `reports/evidence/staging/phase15.4/`, cited below as `[nn]`.
**Classification:** PASS / FAIL / BLOCKED / NOT RUN. Nothing below is inferred; every row comes from an executed request.

---

## 0. Verdict

| Area | Result |
|---|---|
| A. Staging security finalisation | **PASS**, with 1 owner-only item **BLOCKED** (share-link revocation) |
| B. Synthetic test accounts | **PASS** (3 of 3 created and role-verified) |
| C. Functional acceptance (API level, real staging backend) | **139 PASS / 2 FAIL / 1 BLOCKED** of 142 automated checks [05]. Both FAILs come from one test-design expectation, explained in §3.1. A retest shows no application defect [07]. |
| C. Real-time session expiry | **NOT COMPLETED in Phase 15.4** (the session ended while the test was waiting). Re-run in Phase 16: **6/6 PASS**, see `phase16/03_session_expiry_realtime.json` [06] |
| C. Browser UI walk-through on the protected Preview | **BLOCKED**: Vercel SSO and no approved bypass (§5) |
| C. Gmail delivery | **BLOCKED**: `GMAIL_USER` / `GMAIL_APP_PASSWORD` not configured [08] |

**What "functional testing" means here:** these tests call the *same* HTTP endpoints the Flutter app calls, against the live staging backend:
- the `login`, `admin-users` and `send-notifications` Edge Functions;
- PostgREST tables and RPCs;
- Supabase Auth.

Each call uses a real user session for the relevant role. They prove the backend's behaviour, authorization and data rules end to end. They do **not** click through the Flutter UI. That part is covered locally by 50 widget tests [11]. On the live Preview it is BLOCKED (§5).

---

## 1. Part A: Staging security finalisation

| # | Item | Result | Evidence |
|---|---|---|---|
| A1 | Revoke the remaining temporary Vercel share link (Preview `2vj2mwxa8`) | **BLOCKED (owner action)** | See note below. |
| A2 | Vercel Authentication protects all deployments | **PASS**. `ssoProtection = {enabled:true, deploymentType:"all"}`. The unauthenticated sweep returned **30 / 30 → 302 `vercel.com/sso-api`**: 5 hosts (Preview, prod placeholder, preserved original, both prod aliases) × 6 paths, including an invalid `_vercel_share` token. | [01] |
| A3 | `ALLOWED_ORIGINS` default changed from wildcard to **fail-closed** | **PASS**. `_shared/http.ts`: an unset, empty or `*`-only list now produces **no** `Access-Control-Allow-Origin`, and a `*` entry is never echoed. New unit test added. Deno **13 / 13** pass and type-check is clean. All 3 functions redeployed to staging (v3). | [02][03] |
| A4 | Exact staging Preview origin verified | **PASS**. The Preview URL is unchanged (`dpl_4heKbZ`, `target:null`), so no secret update or redeploy was needed. Each of the 3 functions echoes the approved origin, returns no ACAO for `https://evil.example`, and returns no ACAO when the Origin header is missing. | [05] `SEC-cors-*` |
| A5 | All three Edge Functions verified | **PASS**. All three are ACTIVE v3. Login, authz and CORS were exercised (§3.5). | [03][05] |
| A6 | Anonymous access restrictions and RLS | **PASS**. Anon is denied on all 8 tables (`42501`) and on every RPC. The post-test catalog shows RLS on for all 8 tables, 12 policies, **0** anon table privileges, **0** anon-executable functions, and only `ticket_stats`, `assignable_staff` and `reporter_ticket_action` executable by `authenticated`. | [05][09] |
| A7 | Production untouched | **PASS**. The CLI account sees only `itsr-radiant-staging`. Every write used the hard-coded staging ref. There were no Vercel deployments; the list is unchanged at 3. | [10] |

**A1 note (BLOCKED, owner action):**
- **Why the API can't do it:** Vercel's API can revoke a share link only when given the link's secret (`revoke.secret`). The Preview hostname is a *deployment URL*, not an alias.
  - `GET /v4/aliases/<host>` returns 404, and `list_deployment_aliases` returns `[]`, so the secret can't be listed.
  - The link was created implicitly in Phase 15.3 and its URL was never returned to the operator.
- **Risk:** the link is invisible to anyone without the URL, and it **expires automatically by about 2026-11-09 08:01 UTC**.
- **To revoke it now:** Vercel Dashboard → *itsr-radiant-staging* → Deployments → `2vj2mwxa8` → **Share** → revoke.

---

## 2. Part B: Synthetic accounts

| # | Item | Result | Evidence |
|---|---|---|---|
| B1 | Staging administrator `STGADM01` | **PASS**. Bootstrapped through the Auth admin API, with the server key held in memory only. Logged in via the `login` Edge Function (200). | [04] |
| B2 | Staging employee `STGEMP01` | **PASS**. Created by the admin through `admin-users` (201). | [04] |
| B3 | Staging technician `STGTEC01` (`it_support`) | **PASS**. Created through `admin-users` (201). | [04] |
| B4 | Synthetic identities, no real NIK or PII | **PASS**. `STG*` numbers, "(Synthetic)" names, RFC 2606 `example.com` emails. | `STAGING-TEST-ACCOUNTS.md` |
| B5 | Credentials stored securely outside the repo | **PASS**. `%USERPROFILE%\.itsr-staging\test-accounts.json` with a user-only ACL. Passwords were never printed. The secret scan of the repo found 0 occurrences. | §4 of `GITHUB-PUSH-REPORT.md` |
| B6 | Role assignments and authorized-function boundaries verified | **PASS**. A role-by-capability matrix was verified live. | [05], `STAGING-TEST-ACCOUNTS.md` §2 |

---

## 3. Part C: Functional testing (142 automated checks) [05]

| Section | PASS | FAIL | BLOCKED |
|---|---|---|---|
| Authentication (incl. invalid login, rate limit, refresh, anon) | 22 | 2 | 0 |
| Account deactivation and logout | 11 | 0 | 0 |
| Ticket workflow | 38 | 0 | 0 |
| Administration: categories | 7 | 0 | 0 |
| Administration: dashboard, users, roles | 18 | 0 | 0 |
| Security | 39 | 0 | 0 |
| Notifications | 4 | 0 | 1 |
| **Total** | **139** | **2** | **1** |

### 3.1 Authentication

| Test | Result | Evidence (actual) |
|---|---|---|
| Admin, employee and technician login | **PASS** ×3 | 200. The JWT `sub` matches the profile and the role resolves correctly. ACAO = Preview origin. |
| Admin, employee and technician logout | **PASS** ×3 | `logout` → 204. The refresh token is then invalid (400) and `/auth/v1/user` returns 403. |
| Invalid login: wrong password, unknown number, too-short password | **PASS** ×3 | 401 with the same generic message. Each response is padded to ≥ 800 ms (about 850–930 ms). |
| Invalid login: malformed number `x' or 1=1--` | **FAIL** (test expectation) | 403 in 45 ms, an HTML page from **Supabase's Cloudflare WAF**. There is no `sb-request-id`, so the request never reached the function. |
| Invalid-login responses indistinguishable | **FAIL** (consequence of the row above) | Two distinct responses: the generic 401, and the WAF 403. |
| Rate limit | **PASS** | Five failures, then the 6th attempt → **429** (`401×5, 429`). |
| Session lifetime configured | **PASS** | `exp − iat = 3600 = expires_in`, and the token carries a `session_id`. |
| Tampered JWT signature | **PASS** | PostgREST 401; `admin-users` and `send-notifications` 401. |
| Refresh token rotation | **PASS** | 200, and a new refresh token is issued. |
| Session expiration (real time, past 1 h) | **NOT COMPLETED in Phase 15.4** (the session ended while the test was waiting). Re-run in Phase 16: **6/6 PASS**, see `phase16/03_session_expiry_realtime.json` | [06] |
| Unauthorized (anon) access, 8 tables | **PASS** ×8 | 401 `42501 permission denied` on every table. |
| Deactivated user | **PASS** ×5 | Login 401. The user's live token sees 0 tickets (RLS) and gets 401 from the Edge Function. The user is removed from the staff picker. After reactivation, login returns 200 again. |

**Analysis of the two FAILs:**
- The test expected the login function's uniform 401. Instead, the platform's WAF rejected a classic SQL-injection string before the application saw it.
- The retest [07] shows that `x' or 1`, `abc def`, `STG-EMP-01` and `<script>` all reach the function and get the uniform padded 401.
- The WAF decision depends only on the request payload, not on whether an account exists, so it is **not** an account-enumeration oracle.
- The function also normalises the employee number against `^[A-Z0-9]{2,20}$` before any lookup.
- **No application defect.** The raw FAIL classification is kept as recorded and not altered.

**Platform observations (informational, counted as PASS in [05]):**
- A rotated refresh token can be reused within Supabase's default reuse interval of about 10 s.
- After logout, the old *access* token is still honoured by PostgREST until it expires (max 3600 s), because Supabase JWTs are stateless.
- The Auth API and refresh token are revoked immediately.
- Users can edit their own `user_metadata`. A test that wrote `role: administrator` there granted nothing, because the app's authz reads `public.profiles.role`. The key was cleaned up afterwards [09].

### 3.2 Ticket workflow (38 / 38 PASS)

| Test | Evidence (actual) |
|---|---|
| Create ticket | 201, `ITSR-00001`, `status=open`, `assigned_to_id=null`, `reporter=employee` |
| Server-owned fields protected | `status` on insert → 401/403 (column not granted). A `reporter_id` spoof is overridden to the caller. An unknown category is rejected. A too-short subject or description is rejected. |
| View ticket | The employee sees their own ticket. The technician sees it with the reporter join. |
| Edit ticket | Employee: 0 rows affected; `subject` is immutable (column not granted). Technician: priority `high` and category changed (200). |
| Assign technician | `assignable_staff` returns exactly `[STGADM01, STGTEC01]`. Assigning to an employee is rejected. The admin assigns the technician, and the status automatically becomes `assigned`. |
| Change status | `assigned→in_progress→pending_user` both OK. `in_progress→closed` is rejected. The employee's status change affects 0 rows. Resolving without a resolution is rejected. Resolving with one sets `resolved_at`. |
| Comments | The employee comments on their own ticket. The employee's internal comment → 403. The technician's internal and public comments both succeed, and the author spoof is overridden. The employee sees 2 comments (none internal); staff see 3. |
| Reopen / close (reporter RPC) | Reopen without a reason → rejected. Reopen with a reason → `reopened`, `resolved_at` cleared. Re-resolve, then the reporter closes → `closed`, `closed_at` set. |
| Activity timeline | The employee sees, in order: `created, priority_changed, category_changed, assigned, status_changed×3, resolved, reopened, resolved, closed` |
| Ticket history integrity | The reopen row carries the reason and the employee as actor. Clients can't insert into the activity log (403). The admin can't delete the log (403) or delete tickets (403). |
| Employee ticket visibility | The employee sees only their own 2 of 4 tickets. The technician sees all 4. |

### 3.3 Administration (25 / 25 PASS)

| Test | Evidence (actual) |
|---|---|
| User management | The admin lists 3 users. `update` (department, phone) → 200. Duplicate number → 409. Invalid payload → 400. Self-demotion → 400. `reset_password` → 200: the old password then fails (401) and the new one logs in (200). Deactivate and reactivate → 200 (§3.1). |
| Category management | Admin create → 201 and edit → 200. Hard delete is not granted (403; deactivation is used instead). Employee and technician create → 403. Employee edit → 0 rows. The employee can read categories. |
| Role / permission enforcement | Employee and technician get 403 from `admin-users`. `app_settings`: the admin reads 1 row; the employee and technician read 0 rows and update 0 rows. |
| Dashboard statistics | Admin `ticket_stats('all')` exactly matches SQL ground truth (`total 4, open 3, in_progress 0, resolved 0, closed 1, unassigned 3`). Employee `'all'` is RLS-scoped to their own tickets (2 = 2). Technician `'assigned'` returns 1 = 1. |
| Employee access restrictions | The staff picker is empty for the employee. Profile visibility is limited to their own row plus staff rows. |

### 3.4 Security (39 / 39 PASS)

| Test | Evidence (actual) |
|---|---|
| RLS isolation | The employee gets 0 rows on the admin's ticket by ID and 0 activity rows on the technician's ticket. A comment on another user's ticket → 403. `reporter_ticket_action` on another user's ticket → error. Updating another user's ticket → 0 rows. |
| Privilege escalation | `PATCH profiles.role` → 401/403, and the role stays `employee`. Insert into profiles → 403. A `user_metadata` role → no effect. `admin-users` called as employee or technician → 403. |
| Service-only RPCs | `claim_notifications`, `complete_notification`, `login_is_rate_limited`, `record_login_attempt` and `rls_auto_enable` are denied for anon, employee **and admin** (15 / 15). `notification_outbox` and `login_attempts` are denied even for the admin. |
| Anonymous API | `ticket_stats`, `assignable_staff` and `reporter_ticket_action` are denied to anon. An invalid API key → 401. |
| Edge Function authorization | `admin-users`: no token, publishable key as bearer, or forged JWT → 401. `send-notifications`: no token, forged JWT, or wrong `x-cron-secret` → 401. Expired token → 401 (Phase 16 re-run, `phase16/03_*`) [06]. |

### 3.5 Notifications

| Test | Result | Evidence (actual) |
|---|---|---|
| Queue populated by triggers | **PASS** | 14 pending rows: `ticket_created`, `ticket_assigned`, `status_changed` ×7 and `comment_added` ×2. |
| Internal comments not queued | **PASS** | `comment_added` (2) equals the number of public comments (2). |
| `send-notifications` authorization | **PASS** | An active user is accepted (not 401). |
| No loss while email is unconfigured | **PASS** | Returns 503 `Email is not configured`. Pending stays at 14 before and after. |
| Gmail SMTP delivery | **BLOCKED** | The staging secrets list (names only) has no `GMAIL_USER` and no `GMAIL_APP_PASSWORD` [08]. |

---

## 4. Supporting suites

| Suite | Result | Evidence |
|---|---|---|
| Deno unit tests (Edge Function logic, incl. the new fail-closed CORS test) | **13 / 13 PASS**; type-check clean | [02] |
| Flutter `analyze` / `test` | **No issues / 50 / 50 PASS** | [11] |
| Staging SQL security suite (`supabase/tests/staging/…`) | **NOT RUN this phase** | See note below. |

**Why the SQL suite was not run:** by design, the suite aborts on a non-empty database: it guards against `auth.users` or `tickets` existing. Running it now would have meant changing the suite.
- It last ran at **96 / 96** in Phase 15.3.
- The schema has not changed since then: migrations are still 0100–0500, and the catalog snapshot matches [09].
- Its RLS and privilege assertions were re-proven live through the API in §3.4.

---

## 5. Not covered / BLOCKED, with what unblocks each

| Item | Status | To unblock |
|---|---|---|
| Revoke Phase 15.3's 23 h share link on the Preview | **BLOCKED** (owner) | Dashboard → Deployment `2vj2mwxa8` → Share → revoke, or let it expire about 2026-11-09 08:01 UTC. |
| Browser UI walk-through on the protected Preview (login screen → tickets → admin) | **BLOCKED** | A Vercel team member opens the Preview while signed in to Vercel and signs in with the `STG*` accounts (passwords in the local credentials file). Automation would need a bypass link, which this session's permission policy denies. |
| Gmail delivery | **BLOCKED** | Set `GMAIL_USER`, `GMAIL_APP_PASSWORD` (and optionally `NOTIFICATIONS_CRON_SECRET`) on staging, and put the real IT group and manager addresses in `app_settings`. Then invoke `send-notifications`: 14 rows are waiting. **Note:** with the current data, recipients are `@example.com` addresses, which are undeliverable by design. |
| Staging SQL suite re-run | **NOT RUN** | Make the suite's empty-DB guard tolerate the `STG*` fixtures, or run it before seeding a future environment. |

## 6. Changes made in this phase
1. `supabase/functions/_shared/http.ts`: CORS made fail-closed.
2. `supabase/functions/tests/shared_test.ts`: new fail-closed test.
3. Edge Functions redeployed to **staging** (v3).
4. Three synthetic accounts and their test data created on **staging**.
5. `.gitignore` hardened.
6. The project initialised as a Git repository and pushed (see `GITHUB-PUSH-REPORT.md`).

**No** changes to migrations, RLS, Vercel settings, or any production resource.
