# ITSR — Phase 15.3: Vercel Staging Security Remediation Report

**Date:** 2026-11-08 (07:58–08:13 UTC)
**Owner decision implemented:** Option 3 (contain first), then a protected Preview deployment.
**Overall result:** **CONTAINED AND REMEDIATED.** Every URL in the project now requires Vercel authentication. The app runs only as a **Preview**. Edge Function CORS is pinned to that one origin. `rls_auto_enable()` is no longer callable by clients.
**Untouched:** Vercel project (not deleted), Production Supabase, all prior migrations, and all staging data.

All evidence is in `reports/evidence/staging/phase15.3-vercel/`. File numbers are cited as `[nn]`.

---

## 1. Summary

| Phase | Result | Evidence |
|---|---|---|
| A. Containment | **DONE.** The public alias went from 200 to 302 (SSO) within seconds. 24 of 24 asset requests are blocked. | [01]–[04] |
| B. Protected Preview | **DONE.** The app is deployment `dpl_4heKbZ…`, with API `target = null` (Preview) and no aliases. Production now serves only a static placeholder. | [05]–[09] |
| C. Edge Function CORS | **DONE.** The `*` wildcard is replaced by the exact preview origin. 18 of 18 probes pass. | [10]–[12] |
| D. `rls_auto_enable()` | **REMEDIATED.** Migration 0500 revokes EXECUTE from client roles. The event trigger still works. | [13]–[19] |
| E. Validation | **PASS**, with one item blocked. Details are in §6. | [20]–[28] |

---

## 2. Phase A: Immediate containment

**Finding [01][02]:** The project had Vercel Authentication set to `all_except_custom_domains` (Standard Protection). Under that setting the production domain `itsr-radiant-staging.vercel.app` was **public: HTTP 200, full Flutter app**. The other two URLs already redirected to SSO.

**Action:** `ssoProtection.deploymentType` was changed from `all_except_custom_domains` to `all`, using the Vercel API (MCP `update_project`).

**Verification:**
- One request to `main.dart.js` still returned 200 a few seconds after the change, because the edge config had not finished propagating [03].
- A re-sweep about 15 s later returned 302 for all 24 requests across 3 hosts × 8 paths [04].
- No domain or alias removal was needed. The project, the original deployment and both domains are preserved.

## 3. Phase B: Protected Preview deployment

1. **Placeholder to production [05]:** A static "no application here" page with `noindex` headers was deployed as `dpl_9kEkf…`. Both production aliases moved to it.
   - The original app deployment `dpl_EkNj…` is **kept as evidence**. It is no longer aliased and remains protected.
2. **Bundle check before deploy [06]:**
   - The embedded key is staging's `default publishable` key, confirmed by SHA-256 match.
   - There are 0 secret keys and 0 JWTs.
   - The two "occurrences" the scan flagged are validation code inside the app: a `"sb_secret_"` prefix check and an error string mentioning `service_role`. These are not secrets.
3. **App deployed as Preview [07]:** `vercel deploy --target preview` from `build/web` produced **`https://itsr-radiant-staging-2vj2mwxa8-assyaref75.vercel.app`**.
4. **Server-side metadata, not the CLI flag [09]:**

| Check | Result |
|---|---|
| Target / environment | `target: null` = **Preview**. Also returned by `list_deployments target=preview`. |
| Aliases | none |
| Team / project | `team_QQyXKOl479XhgiskM7oldcHB` (assyaref75) / `prj_dBhijO1rM3apNtiA8lGcFIVypFn0` |
| Supabase URL in bundle | `https://yzjpttfwnvnuyxbdkidm.supabase.co` (staging) only |
| Key in bundle | publishable key only |
| Protection | `ssoProtection = all`. Unauthenticated requests get 302 to `vercel.com/sso-api`. |
| Authorized access | A team member (assyaref, via the Vercel connector) gets 200 and the app shell. The production alias gives 200 and the placeholder. |

**Shareable-link side effect (handled):**
- The connector's authenticated fetch creates a 23-hour shareable link. The link it created on the production alias was **revoked** (HTTP 200; 0 entries remain [28]).
- The equivalent link on the preview deployment can't be listed or revoked through the API.
  - Its URL was never returned to the operator or stored anywhere.
  - It **expires automatically by about 2026-11-09 08:01 UTC**.
  - **Owner (optional):** to revoke it sooner, go to the Vercel Dashboard → itsr-radiant-staging → Deployments → `2vj2mwxa8` → Share.

## 4. Phase C: Edge Function CORS

- **Before [10]:** `ALLOWED_ORIGINS` was unset, so all 3 functions returned `Access-Control-Allow-Origin: *` to any origin, including `https://evil.example`.
- **Action [11]:** `supabase secrets set ALLOWED_ORIGINS=https://itsr-radiant-staging-2vj2mwxa8-assyaref75.vercel.app` (staging ref only).
- **After [12], 18 of 18 pass:**
  - The approved origin is echoed back.
  - Foreign or missing origins get **no** ACAO header.
  - Authentication is unchanged:
    - `login` with a bad password → 401
    - `admin-users` with no JWT, the publishable key as bearer, or a forged JWT → 401
    - `send-notifications` with no JWT or a wrong cron secret → 401
- **Browser enforcement [26]:** real Chrome, from an unapproved origin, **blocked** all three functions.
- Authentication was not disabled, and RLS was not touched.

**Operational note:** Every new Preview deployment gets a new hostname. After any redeploy, `ALLOWED_ORIGINS` must be updated to the new URL, or the app's browser calls to the functions will be blocked (fail-closed).

**Recommendation (code, not done here):** `_shared/http.ts` still falls back to `*` when `ALLOWED_ORIGINS` is **unset**. Production should either set it, or the default should be changed to deny. That code change needs its own review and function redeploy.

## 5. Phase D: `public.rls_auto_enable()`

| Question | Answer [13] |
|---|---|
| What is it? | A platform-installed (not ITSR) PL/pgSQL function that backs the event trigger `ensure_rls` (`ddl_command_end` on CREATE TABLE / CREATE TABLE AS / SELECT INTO). |
| SECURITY DEFINER? | **Yes.** Owner `postgres`, `search_path=pg_catalog` (pinned, good). |
| Why could anon call it? | `proacl` was **NULL**, so PostgreSQL's built-in default applies: EXECUTE to `PUBLIC`. `anon`, `authenticated` and `service_role` all inherited it. There was no explicit grant. |
| Reachable from the internet? | **Yes.** `POST /rest/v1/rpc/rls_auto_enable` with only the publishable key passed the privilege check and failed only when serializing output (`0A000 cannot display a value of type event_trigger`). |
| Can it modify security settings? | It can only **enable** RLS, never disable it, and only on `public` tables listed by `pg_event_trigger_ddl_commands()`. That list is empty outside a DDL event, so a direct call is a no-op. **Impact: LOW.** |
| Justified to revoke? | **Yes.** No client role needs EXECUTE on an event-trigger function (least privilege). |

**Remediation:** `supabase/migrations/20261108000500_restrict_rls_auto_enable_execute.sql` (sha256 `f71879b8…4ff6`).
- It revokes EXECUTE from `public`, `anon`, `authenticated` and `service_role`.
- It is guarded (a no-op if the function is absent) and idempotent.
- It does not alter the trigger, the function body, RLS or any table.

**Proven before applying, on a throwaway PG 18.6 cluster [14]:**
- After the revoke, a role **without** EXECUTE that runs CREATE TABLE and CREATE TABLE AS still gets RLS enabled. PostgreSQL does not check EXECUTE on an event-trigger function when it fires.
- A direct anon call is denied.
- Running the migration twice is OK.
- My first run used a flawed fixture: the definer didn't own the test tables, so the trigger failed both before and after the revoke. The fixture was corrected, re-run, and the log shows "enabled RLS" for every table.

**Applied to staging only:**
- The dry-run showed exactly 1 pending migration [15]. `db push` returned exit 0. Remote history is now 0100–0500 [16].
- Staging retest:
  - `proacl = {postgres=X/postgres}`. anon, authenticated and service_role are false; the owner is true [17].
  - Direct calls as anon and as authenticated are **denied (42501)**.
  - `ensure_rls` still sets `relrowsecurity=true` on a new public table. That probe ran inside a transaction that raises at the end, so the probe table does not persist [18].
  - Anon via REST: **401 `42501 permission denied for function rls_auto_enable`** [19].
  - All 8 public tables have RLS on.

**Note for Production (not touched):** Migration 0500 is in the authoritative chain and is safe in any environment. If Production has the same platform function, the same finding probably applies there.

## 6. Phase E: Validation

| Test | Result | Evidence |
|---|---|---|
| Staging SQL security suite (self-rolling-back) | **96 / 96 PASS.** This includes **P02b** ("anon cannot call rls_auto_enable"), which **failed before** this phase. | [20] |
| Residue after tests | No `test` schema and no probe table. Sequence restored. tickets / profiles / auth.users = 0. login_attempts = 1, the earlier `SMOKETEST01` smoke row. | [21] |
| Edge Function unit tests (Deno) | **12 / 12 PASS.** `deno check` passes for all 3 functions. | [22] |
| Flutter `analyze` / `test` | No issues / **50 tests pass** | [23] |
| Flutter release build | Builds cleanly in 67.7 s. **Byte-identical** to the deployed preview (`main.dart.js` sha256 `7d11c8e9…80e7`). 0 secret keys, 0 JWTs. | [24] |
| Browser smoke test | **PASS, with the limitation below.** Headless Chrome 156 renders the ITSR login screen with no console errors. Browser CORS blocks an unapproved origin. Anon RPC is denied. | [25][26] |
| Unauthorized access | **45 / 45 → 302 SSO** (5 hosts × 9 paths, including an invalid `_vercel_share` token). 0 bypass links remain. | [27][28] |
| Preview protection | Unauthenticated: 302. Authorized team member: 200. | [08][09] |

**BLOCKED / limitations, reported as-is:**
1. **The browser smoke test ran against a local copy, not the protected preview URL.**
   - The served build is byte-identical to the preview.
   - Driving headless Chrome *through* Vercel SSO would have needed a short-lived bypass link, and that action was denied by the session's permission policy. **No bypass was created.**
   - The owner or a tester should open the preview URL while logged into Vercel and confirm the login screen loads.
2. **No authenticated end-user or admin flow was tested.** Staging has no user accounts, and creating one is outside the approved scope.
   - "Authorized request" tests covered the approved origin and the auth-rejection paths.
   - A full login → ticket → admin flow needs the owner to approve a synthetic staging admin.
3. Email (Gmail App Password) is still **BLOCKED**, as before.

## 7. Final configuration

| Item | Value |
|---|---|
| Staging app (Preview, SSO-protected) | `https://itsr-radiant-staging-2vj2mwxa8-assyaref75.vercel.app` |
| Production aliases | `itsr-radiant-staging.vercel.app`, `itsr-radiant-staging-assyaref75.vercel.app` → placeholder only, SSO-protected |
| Vercel protection | Vercel Authentication, **All Deployments** |
| `ALLOWED_ORIGINS` | the preview origin above (no wildcard) |
| Supabase staging migrations | 0100–0500 applied |
| Who can access | Members of the Vercel team `assyaref75` only. To add testers: Vercel → Team → Members, or Deployment → Share → invite a specific user. |

## 8. Owner action items
1. Have a tester open the preview URL while signed in to Vercel and confirm the login screen loads (§6, item 1).
2. Optional: revoke the preview's temporary share link before it expires (§3).
3. Decide whether to create a synthetic staging admin for end-to-end tests (§6, item 2).
4. After any new Preview deploy, update `ALLOWED_ORIGINS` to the new URL.
5. Decide on the fail-closed CORS default in `_shared/http.ts` (§4).
6. The original app deployment `dpl_EkNj…` is preserved for evidence. Deleting it or the project needs separate approval.
