# ITSR — Staging Deployment Report (Phase 15.3)

> **UPDATE 2026-11-08 ~08:13 UTC (Phase 15.3 security remediation):** the Vercel deviation is **resolved**.
> - All deployments now require Vercel authentication; the production aliases serve only a placeholder.
> - The app is a **Preview**: `https://itsr-radiant-staging-2vj2mwxa8-assyaref75.vercel.app`.
> - `ALLOWED_ORIGINS` is pinned to that origin, so there is no more `*`.
> - Migration **0500** revokes client EXECUTE on `rls_auto_enable()`; the staging suite is now **96/96**, with P02b passing.
>
> See **PHASE15.3-VERCEL-STAGING-SECURITY-REPORT.md** and `reports/evidence/staging/phase15.3-vercel/`.

> **UPDATE 2026-11-08 ~07:52 UTC:** the owner authorized execution.
> - Migrations 0100–0400 are **applied** to staging and verified; the reviewed SQL suite passes 95/95 on staging.
> - The 3 Edge Functions are **deployed**.
> - Vercel deployed with **production target + a public alias**, which is a deviation pending the owner's decision.
>
> See **STAGING-MIGRATION-EXECUTION-REPORT.md** and `reports/evidence/staging/`. The text below is the earlier pre-authorization state, kept for history.

**Status (historical): BLOCKED. Owner credentials are needed. Nothing has been deployed or changed on staging.**
Date: 2026-11-08 · Target Supabase ref: `yzjpttfwnvnuyxbdkidm` · Production: untouched

## 1. Environment discovery (verified)
| Item | Finding |
|---|---|
| Frontend | **Flutter Web** (Flutter 3.47.7 / Dart 3.13.5), not Next.js. Config comes only from `--dart-define` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ENVIRONMENT`). Uses hash routing, so no rewrite rules are needed. |
| Build output | `build/web/`: 39 files, about 41 MB including CanvasKit, with a 3.1 MB `main.dart.js`. A release build with the staging URL compiles cleanly (69.8 s). That build used a placeholder key and was **not** deployed. |
| Git / GitHub | The project folder is **not a git repository** and has no remote. There is no commit hash to report and no Git-based Vercel integration. |
| Vercel | The connector is authenticated as `assyaref` (hobby plan), team `team_QQyXKOl479XhgiskM7oldcHB`. There is **no ITSR project**; the existing projects are kopikir, bcs-radiant and radiant-lucky-draw. The project has no `vercel.json`. |
| Supabase config | `supabase/config.toml` sets `verify_jwt=false` for `login`, `admin-users` and `send-notifications`. Each function does its own authorization. |
| Migrations | `supabase/migrations/20261108000100..0400` (4 files) are authoritative. Nothing under `migrations/legacy/` will be applied. |
| Env files | All `.env.*` files contain placeholders only. No real keys are stored in the repo. |
| Staging reachability | `https://yzjpttfwnvnuyxbdkidm.supabase.co` returns 401 without a key, so the project exists. The direct DB host is **IPv6-only** and this machine has no IPv6, so DB access has to go through the Supabase IPv4 session pooler. |
| Tooling | Supabase CLI 2.54.11 and Vercel CLI 48.10.2 work via `npx`, but **neither is logged in**. `pg_dump` 18.6 is available for the backup. |

## 2. Blockers (owner action required)
1. **Supabase access token.** Run `npx supabase@2.54.11 login` in your own terminal. This unblocks link, Edge Function deploy (`--use-api`, no Docker needed), secrets, and reading the publishable key.
2. **Staging DB password.** Needed for the pre-deploy `pg_dump` backup and `supabase db push`. It must not be pasted into chat. Put it in `%USERPROFILE%\.itsr-staging\db-password`, which is outside the repo; it will be read into an environment variable and never printed.
3. **Vercel CLI login.** Run `npx vercel@48.10.2 login`. The connector can only upload files inline as base64, which is not practical for a 41 MB Flutter build.
4. **Gmail App Password**, optional for now. Email tests are marked **BLOCKED** until you run `npx supabase@2.54.11 secrets set GMAIL_USER=... GMAIL_APP_PASSWORD=... --project-ref yzjpttfwnvnuyxbdkidm` yourself.
5. **Commit hash**, optional. Only possible if the folder is put under git. Otherwise deployments are identified by Vercel deployment ID plus a SHA-256 of `main.dart.js`.

## 3. Planned sequence once unblocked
1. Re-verify the ref (`yzjpttfwnvnuyxbdkidm`) before every operation.
2. Back up with `pg_dump`: schema and data, through the pooler.
3. Run `supabase migration list`. It must show none of 20261108*.
4. Run `supabase db push`, which applies only the four approved migrations.
5. Deploy `login`, `admin-users` and `send-notifications`. Set `ALLOWED_ORIGINS` to the preview URL and set `NOTIFICATIONS_CRON_SECRET`.
6. Run the RLS and function-privilege verification queries from DEPLOYMENT-GUIDE §3.
7. Create a synthetic staging admin. Its password is stored only in a local file outside the repo.
8. Build Flutter with the **publishable** key only and deploy `build/web` as a Vercel **Preview** to a new `itsr-staging` project.
9. Run visual and functional smoke tests, then write STAGING-URL.md, STAGING-SMOKE-TEST-REPORT.md and the updated FINAL-TEST-REPORT.md.
