# PHASE 19: ITSR Radiant Group Duri internal live deployment

**Date:** 2026-11-09 (UTC times throughout)
**Backend:** Supabase staging `yzjpttfwnvnuyxbdkidm` (no production project was created or touched)
**Frontend:** Vercel project `itsr-radiant-staging`, **Production** target
**Evidence:** `reports/evidence/staging/phase19/` (every number below comes from a file there)

---

## 1. Executive summary

| Gate | Result |
|---|---|
| Flutter `pub get` / `build_runner` / `analyze` / `test` | Pass: no issues; **54/54** tests |
| Flutter Web release build | Pass (`build/web`, `main.dart.js` 3.19 MB) |
| Local SQL suite (migrations 0100–1000 on a throwaway cluster) | **113/113** |
| Deno `check` (all 4 functions) + Deno tests | Pass; **17/17** |
| Staging catalog assertions (read-only drift check) | **17/17** |
| Backend RBAC smoke (direct API, no UI) | **29/29** |
| Browser E2E (Chrome; desktop 1440 px + phone 390 px) | **30/30** (run 2; see §15) |
| Bundle secret scan | **0** secret hits |
| Vercel production deployment | READY: `dpl_H6cfAmYoihfvh9oEhj6GGSZYZvAC` |
| **Employees can open the URL** | **NO: blocked by Vercel Authentication (§24, blocker B1)** |

The application, backend and frontend are deployed and verified. **Employees cannot use it yet.** The Vercel project still has Deployment Protection "Vercel Authentication" set to **all** deployments (applied in Phase 15.3), so every visitor who is not a Vercel team member is redirected to a Vercel login. The change that fixes this, Vercel's *Standard Protection*, was attempted and **denied by the session's permission policy**. The project owner must make it (see B1). After that, a short re-run of the E2E suite against the public URL is required.

Phase 18's uncommitted SMTP work did **not compile** and its Vault functions **could not have worked**. Both were fixed before anything was deployed (§4).

## 2. Initial Git state

- Branch `main`, HEAD `4998d85` = `origin/main` (pushed in Phase 16). No conflicts.
- Modified: `.gitignore`, `lib/router/app_router.dart`, `lib/widgets/app_shell.dart`, `supabase/functions/send-notifications/index.ts`, `supabase/functions/tests/shared_test.ts`, `supabase/tests/local/20_security_and_workflow_tests.sql`, `supabase/tests/staging/catalog_assertions.sql`.
- Untracked: Phase 17 report and evidence, migrations 0700–1000, `supabase/scheduler/`, `smtp-config` function, `_shared/smtp_errors.ts`, and the 5 Flutter SMTP files.
- **Staging reference correction:** the ref given for this phase (`yzjptffw…`) does not resolve (curl `000`). The real staging ref is **`yzjpttfwnvnuyxbdkidm`** (`/auth/v1/health` → 401 = alive). Everything in this phase uses the real ref. The bundle scan confirms the wrong ref is absent from the build.
- No `git reset`, `git clean` or force push was used. No user file was discarded.

## 3. Phase 17 preservation

The Phase 17 work is kept intact and committed: migration 0700 (`held` status + permanent failures, already on staging), migration 0800 (IT Support recipient), `smtp_errors.ts` and its tests, the local tests N13–N19, catalog check C16, the scheduler SQL and the Phase 17 report/evidence.

One discrepancy: `PHASE17-COMPANY-EMAIL-CONFIGURATION-REPORT.md` §4 says `send-notifications` was "not modified", but the working tree contained the Phase 18 SMTP rewrite of it. The report is kept unchanged as a historical record; this note corrects it.

## 4. Phase 18 preservation (SMTP configuration through the admin UI)

There is no Phase 18 report. Its work was identified from file timestamps (10:20–10:30 local) and content: migrations 0900/1000, `smtp-config`, the `send-notifications` SMTP rewrite, and the Flutter Email & Notifications screen, repository, provider, model and route. **Design and intent are preserved.** These defects were fixed:

| # | File | Defect (as found) | Fix |
|---|---|---|---|
| 1 | `send-notifications/index.ts` | `const settingsRow` declared twice → **does not compile** | single read of all settings |
| 2 | same | `from` header `<addr">` (stray quote) → malformed sender | fixed |
| 3 | `20261109001000_vault_smtp_password.sql` | inserted into non-existent `vault.secrets.secret_value`; `ON CONFLICT (name)` cannot target Vault's partial unique index → **saving a password would always fail** | uses `vault.create_secret` / `vault.update_secret`; pinned `search_path = ''`; rejects empty password. Verified on staging with a rolled-back probe (§8) |
| 4 | `email_notifications_screen.dart` | broken string literals (lines 532–533) + `String?` → `String` → **does not compile**; whole test suite failed to load | fixed |
| 5 | same | password field created a new controller on every rebuild and **disabled itself after the first keystroke** | persistent controller, cleared after save/remove, never pre-filled |
| 6 | same | confirmation dialog text lost the recipient (`'sent to  using'`) | shows the recipient |
| 7 | same | company address hard-coded 3× as hint text (fails the existing client-hygiene test) | neutral placeholder |
| 8 | `smtp_repository.dart` | "Remove credential" called `remove_smtp_password` RPC directly, which is service_role-only → **always failed** | new admin-checked `remove` action in `smtp-config` |
| 9 | `smtp-config`, `send-notifications` | 26 TypeScript errors (`deno check`) from concatenated `.select()` strings | single literals |
| 10 | `supabase/config.toml` | no entry for `smtp-config` (gateway JWT check unlike the other functions) | `verify_jwt = false`; the function verifies an **active administrator** itself |

## 5. Flutter build result

`reports/evidence/staging/phase19/13_flutter_web_build.txt`: Flutter 3.47.7, `flutter build web --release --dart-define=SUPABASE_URL=https://yzjpttfwnvnuyxbdkidm.supabase.co --dart-define=SUPABASE_ANON_KEY=<publishable key> --dart-define=ENVIRONMENT=staging`, exit 0 at 06:21:57Z. Source fingerprint (sha256 over `lib/ web/ pubspec.*`) `4f37c095…5413`. It is identical immediately before commit, so the deployed artifact was built from exactly the committed source.

## 6. Flutter test result

`01_flutter_analyze_test.txt`: `pub get` ok; `build_runner` wrote 0 outputs (generated code current); `flutter analyze` → **No issues found**; `flutter test` → **54/54 passed**. Initial run before the fixes: analyze 4 issues and 4 failures (logged in §4).

## 7. Supabase migration status

| Migration | Before | After |
|---|---|---|
| 0100–0700 | applied | applied |
| 0800 company IT Support email | pending | **applied 06:17:41Z** |
| 0900 SMTP configuration columns | pending | **applied** |
| 1000 Vault SMTP password functions | pending | **applied** |

Dry run (`05_db_push_dryrun.txt`) listed exactly these three. All three are additive (columns, functions and one `app_settings` value); there are no drops or deletes. A pre-change snapshot is in `04_pre_0800_backup.json`.

## 8. Supabase security verification

- **Catalog assertions 17/17** (`07_catalog_assertions_after_1000.json`): RLS on all 8 tables, 12 policies (no drift), anon has no table or function rights, authenticated executes exactly 3 RPCs, all SECURITY DEFINER functions pin `search_path`, the outbox is service-only, and the new **C17** confirms that the SMTP password functions are service_role-only and there is no password column.
- **Vault probe** (`08_vault_function_probe_rolled_back.txt`): create → read → update → read → remove all behaved correctly. The probe ends by raising an exception, so the transaction rolled back; afterwards the Vault names were unchanged and no SMTP password was stored (`09_post_1000_state.json`).
- **Backend RBAC 29/29** (`12_backend_rbac_smoke.json`, `tools/e2e/rbac-smoke.mjs`), called directly against PostgREST and the Edge Functions:
  - `smtp-config` status/save/remove → 403 for anonymous, employee and IT Support; 200 for admin with no password/secret field (`password_configured=false`).
  - `get/remove/set_smtp_password` RPCs → 401/403 for everyone, **including administrators** (service_role only).
  - `app_settings`: employee and IT Support see 0 rows. Their PATCH changed nothing: HTTP 204 with 0 rows matched under RLS, `smtp_host` still NULL.
  - `notification_outbox`: 403 for employee and admin. `admin-users`: 403 for employee and IT Support.
  - Employee sees only own tickets (6 rows, 0 foreign); IT Support sees all 8.

## 9. Edge Function status

| Function | Action this phase | State |
|---|---|---|
| `login` | unchanged | ACTIVE |
| `admin-users` | unchanged | ACTIVE |
| `send-notifications` | **redeployed** 06:18Z (SMTP from settings + Vault) | ACTIVE; every cron call since returns **503 "SMTP settings incomplete"** and claims nothing (`22_outbox_and_cron_after.json`) |
| `smtp-config` | **new**, deployed 06:18Z | ACTIVE; admin-only (§8) |

Source hashes: `10_function_source_hashes.txt`. `deno check` passes for all 4 functions; Deno tests 17/17 (`03_deno_check_and_tests.txt`).

## 10. Environment configuration

- **Flutter (build-time `--dart-define`):** `SUPABASE_URL` = staging, `SUPABASE_ANON_KEY` = the **publishable** key (public by design), `ENVIRONMENT=staging`. Nothing else.
- **Vercel project environment variables:** none (static upload of `build/web`; nothing to leak).
- **Supabase function secrets** (names only): `ALLOWED_ORIGINS`, `NOTIFICATIONS_CRON_SECRET`, plus platform-injected `SUPABASE_*`. No `GMAIL_*` / `SMTP_*` secrets. The SMTP password, when an admin sets one, lives only in Vault.
- **CORS `ALLOWED_ORIGINS`.** It was found still containing `http://localhost:5000`: Phase 17 added it temporarily and never removed it.
  - Now: `https://itsr-radiant-staging.vercel.app,https://itsr-radiant-staging-h8c5j387u-assyaref75.vercel.app` (the production domain plus the existing SSO-protected Preview). Digest-verified.
  - Preflight check (`17_cors_verification.txt`, `20_allowed_origins_restored.txt`): both allowed origins are echoed on all 4 functions; `localhost:5000` and `evil.example.com` are refused.
  - `localhost:5000` was re-added temporarily for the E2E run (06:24:31Z) and removed again at 06:39:17Z.

## 11. Secret scan result

- **Bundle** (`14_bundle_secret_scan.txt`): 40 files, **0 hits** for `sb_secret_`, JWTs, `SUPABASE_SERVICE_ROLE_KEY`, `sbp_` management tokens, Vercel tokens, Postgres URLs with passwords, SMTP/Gmail password names, private keys, Vault secret names, probe strings, or the **exact** values of the local test-account passwords. The publishable key and the correct staging URL are present; the wrong ref is absent. The single `service_role` literal is the client-side guard that *rejects* such keys.
- **Repository:** pre-commit scan of the staged files (`23_git_secret_scan.txt`).

## 12. Vercel deployment URL

- **Production domain:** https://itsr-radiant-staging.vercel.app (also aliased as `itsr-radiant-staging-assyaref75.vercel.app`)
- Deployment URL: `https://itsr-radiant-staging-4wd9wdn3s-assyaref75.vercel.app`
- Deployment ID: **`dpl_H6cfAmYoihfvh9oEhj6GGSZYZvAC`**, state READY (`15_vercel_production_deploy.txt`)
- Replaced: production placeholder `dpl_9kEkfGwZUvStEFBzzakNurgYBikd` (still available for instant rollback)
- **Reachability:** both URLs answer `302 → vercel.com/sso-api` (Vercel Authentication). See B1.

## 13. Deployment timestamp

Started 2026-11-09T06:22:59Z, finished 06:23:12Z.

## 14. Git commit

Committed as `feat(deployment): launch ITSR internal live` on `main`, on top of `4998d85`. This report is part of that commit; the hash is in `git log` and in the push verification. The deployed build's source fingerprint equals the committed `lib/ web/ pubspec.*` (§5).

## 15. Browser E2E results

`19_browser_e2e/e2e_results.json` + screenshots. This is the **same release artifact** (`main.dart.js` hash identical) served on `localhost:5000` against staging, because the Vercel URLs are behind Vercel Authentication (B1). Headless Chrome drives the app through Flutter's accessibility tree.

- Run 1: 28/30. Both failures were harness issues: A06 read hidden `<input>.value`, which Flutter does not populate (the screenshot shows the correct value); M03 lacked the documented scroll step. Both checks were fixed in `tools/e2e/e2e.mjs`.
- **Run 2: 30/30 PASS** (synthetic ticket ITSR-00011).

## 16. Employee access test

Covered by E01–E11 and M01–M04:
- Invalid credentials get a generic error.
- Login reaches the dashboard, and the session survives a reload.
- `/queue`, `/admin/users` and **`/admin/email-notifications`** redirect to the dashboard.
- Creates a ticket (server number), comments, sees it in My Tickets.
- Another user's ticket returns "not found or no access" (RLS).
- Sees the resolution but not the internal note; closes the ticket; signs out.
- Backend enforcement is proven separately in §8.

## 17. IT Support access test

Covered by T01–T08:
- Queue and assigned sections; accepts the ticket.
- Start work → internal note → resolve with a resolution.
- Activity history records each step.
- **T08:** `/admin/email-notifications` and `/admin/settings` redirect to the dashboard. The backend also returns 403 for `smtp-config` (R01–R03).

## 18. Administrator access test

Covered by A01–A07:
- Admin navigation, user management with roles, categories, settings, and oversight of all tickets.
- **A06**, Email & Notifications: the page loads and shows "No SMTP credential configured". The `smtp-config` response received by the browser has 16 fields, none secret; `password_configured=false`, `it_support_group_email = it.support-duri@radiant-utama.com`, `manager_email = NULL`, `smtp_host = NULL`.
- **Nothing was saved, tested or sent from this page.**

## 19. Mobile and desktop test

- **Desktop 1440×900:** navigation rail and all role flows above.
- **Phone 390×844:** login fits with no horizontal scroll (`scrollWidth=390`); drawer navigation; ticket detail stacked with history reachable by scrolling; create-ticket form usable.

## 20. Email status

**Disabled in effect; safe.** No SMTP host or credential is configured, so `send-notifications` returns 503 before claiming anything. `notifications_enabled` remains `true` (unchanged); this is correct because delivery is gated on complete SMTP configuration.

- **No email was sent.** `sent` rows ever = 0. No test email; the SMTP connection test was not run.
- `it_support_group_email = it.support-duri@radiant-utama.com`; `manager_email = NULL`.
- SMTP host `mail.radiant-utama.com` is **not** configured: it is unverified, and no credential was provided.
- Ticket creation and handling work with email disabled (E2E §15).

## 21. Held notification count

- **The original 36 held rows are unchanged:** fingerprint `8ce8e2fffb35cfb8631716626d26daae` before (`04_…`) and after (`22_…`).
- E2E runs enqueued 14 rows for synthetic tickets ITSR-00010/00011. Left `pending`, they would email the **real** IT Support mailbox about test tickets as soon as SMTP is configured. They were therefore set to `held` with a query scoped to those two tickets and created after 06:17Z (`21_hold_e2e_outbox_rows.txt`).
- **Outbox now: 50 rows, all `held`** (36 original + 14 E2E). No row is pending.

## 22. Known limitations

- **Hosting:** Vercel Hobby plan; static upload from CLI (no Git integration). A future deployment changes only the per-deployment hostname; the production domain is stable.
- **Accounts:** staging holds only 3 synthetic accounts (STGADM01/STGEMP01/STGTEC01). Real employees must be created by an administrator (Users screen → `admin-users`).
- **Saving SMTP:** saving SMTP settings requires re-entering the password each time (by design, never shown back).
- **Test data:** synthetic test tickets ITSR-00001..11 remain in staging.
- **Staging backend:** the backend is the staging project (no PITR/backup guarantees reviewed for production use).

## 23. Production readiness assessment

**Not production-ready; not yet usable by employees.** The code, database and security gates are green, and the backend correctly enforces RBAC/RLS. Blocking items:
- B1, Vercel protection: no employee can reach the page.
- B2, accounts: there are no real user accounts.
- B3, email: SMTP is not configured.

The backend is a staging project, by instruction.

## 24. Remaining blockers

| # | Blocker | Owner action |
|---|---|---|
| **B1** | Vercel Authentication on **all** deployments blocks employees. The change was denied by this session's permission policy. | Vercel → `itsr-radiant-staging` → Settings → Deployment Protection → Vercel Authentication → **Standard Protection** (API: `ssoProtection.deploymentType = "prod_deployment_urls_and_all_previews"`). This makes only the production domain public; preview and per-deployment URLs stay protected. Then re-run `E2E_APP=https://itsr-radiant-staging.vercel.app node tools/e2e/e2e.mjs <out>` (no CORS change needed). |
| B2 | No real employee accounts | Administrator creates accounts for the ~50 employees |
| B3 | SMTP not configured; `mail.radiant-utama.com` unverified | IT provides host/port/TLS/user/password, then the admin enters them in Email & Notifications. Only then decide on Test Connection / test email. |
| B4 | 50 held notifications | Release only with explicit approval: `update public.notification_outbox set status='pending' where …`. The 14 E2E rows (ITSR-00010/11) should stay held. |
| B5 | `manager_email` NULL | Provide the real manager address |
| B6 | Phase 15.3 Preview share link | Expired by design ~2026-11-09 08:01Z (owner dashboard if still listed) |
