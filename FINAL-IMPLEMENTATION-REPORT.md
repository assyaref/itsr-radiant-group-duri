# ITSR Radiant Group Duri: Final Implementation Report

**Updated:** 2026-11-09 (Phase 16)
**Stack:** Flutter Web 3.47 / Dart 3.13, Riverpod 2.6, GoRouter 14, Supabase (PostgreSQL, Auth, Edge Functions on Deno), Gmail SMTP
**Status of every acceptance criterion:** FINAL-TEST-REPORT.md
**Security:** SECURITY-REVIEW.md

## 1. Phase 16 audit (from source and live systems, not from earlier reports)

| Area | Finding |
|---|---|
| Application features | Complete in source: authentication, role dashboards, the ticket lifecycle, IT Support workflow, the admin module and notifications. The code had no stubs, TODOs or mocks. |
| Local verification at audit start | Analyzer clean; Flutter 50/50; SQL 95/95; Deno 13/13 (all re-run, not trusted from reports). |
| Staging database (read-only probe) | Migrations 0100–0500 applied. RLS is on for all 8 tables, with 12 policies. `anon` has 0 grants. Only 3 RPCs are callable by `authenticated`. `auth.uid()` is native. |
| **Git and reporting integrity** | The repository had **no commits** and the GitHub remote was **empty**, yet `GITHUB-PUSH-REPORT.md` claimed a push. Two reports contained unfilled placeholders (`__COMMIT1__`, `__EXPIRY_*__`). The Phase 15.4 session had ended mid-task. Corrected in this phase. |
| Defects found by audit and E2E | See §2. |

## 2. Changes made in Phase 16

| # | Change | Files | Verification |
|---|---|---|---|
| D1 | **Notification retry cap.** Stuck `processing` rows were re-claimed forever, risking duplicate emails. They are now capped at 5 attempts and then marked `failed` with a reason. | `supabase/migrations/20261109000600_notification_retry_cap.sql`; tests N09–N12 | Local 99/99; staging catalog C15 |
| D2 | **`admin-users reset_password` validation:** UUID, 8–128 character password, target must exist (404). | `supabase/functions/admin-users/{index,validation}.ts`; Deno test | Deno 14/14; live smoke 6/6 |
| D3 | `loadMore()` spinner could stick if the session ended mid-load | `lib/providers/tickets_provider.dart` | Analyzer and tests |
| **A1** | **Accessibility:** ticket number, subject, description, resolution and comments were invisible to screen readers (`SelectableText` rendered as empty textareas on Web). Now `Text` inside `SelectionArea`, still selectable. | `lib/screens/ticket_detail_screen.dart` | Regression test fails on old code; E2E E05/E10 |
| **A2** | **Accessibility:** the desktop sidebar (all navigation **and Sign out**) was missing from the accessibility tree. The ShellRoute's `ModalBarrier`/`BlockSemantics` dropped it. The content pane is now its own semantics container. | `lib/widgets/app_shell.dart` | `test/widget/router_semantics_test.dart` (real router; fails on old code); E2E E09 |
| **A3** | **URL did not follow navigation:** opening a ticket from a list (`context.push`) left the address bar on the list, so a refresh or copied link lost the ticket. | `lib/main.dart` (`GoRouter.optionURLReflectsImperativeAPIs = true`) | E2E T03 |
| T1 | **Read-only catalog assertions.** 15 checks that work on a populated database. They detect privilege and RLS drift, including drift from Supabase's `supabase_admin` default ACL. | `supabase/tests/staging/catalog_assertions.sql` | Local 15/15; staging 15/15 |
| T2 | Reproducible staging verification scripts: browser E2E, session expiry, reset smoke test, secret scan | `tools/e2e/*` | Evidence `phase16/` |
| R1 | Reports corrected and completed | FINAL-*, SECURITY-REVIEW, DEPLOYMENT-GUIDE, GITHUB-PUSH-REPORT, PHASE15.4 placeholders | — |

**Attachments:** not part of the existing architecture (no storage bucket, table or UI), so none were added.

## 3. Migrations: GO / NO-GO

| Migration | Purpose | Depends on | Security impact | Backup | Test evidence | Rollback | Decision / state |
|---|---|---|---|---|---|---|---|
| `20261108000100_core_schema` | Tables, sequence, constraints, RLS enabled on all tables | Supabase `auth.users` | RLS on from the start; creates no `auth` objects | Staging was empty at the time (15.3) | Local SQL; staging catalog C01/C02/C14 | DEPLOYMENT-GUIDE §3 | **GO, applied to staging** (2026-11-08) |
| `…0200_security_privileges_rls` | Least-privilege grants, `private` helpers, 12 policies | 0100 | Fixes the Gate 3 root cause for project-created objects; removes the RLS recursion | as above | P*, AN*, C03–C12 | §3 | **GO, applied** |
| `…0300_ticket_workflow` | Numbering, guards, transitions, trigger history, outbox, 3 RPCs | 0200 | History can't be forged; reporter can't be spoofed; definer functions pinned | as above | E*, T*, R*, S*, N01–N04; browser E2E | §3 | **GO, applied** |
| `…0400_login_and_notifications` | Rate limit and outbox RPCs, service-role only | 0100–0300 | Replaces legacy functions that `anon` could execute | as above | L01–L04, N05–N07, C07 | §3 | **GO, applied** |
| `…0500_restrict_rls_auto_enable_execute` | Revokes client EXECUTE on the platform's `rls_auto_enable()` | Platform function (guarded) | Removes an `anon`-callable platform function | Function ACL recorded (15.3) | C13 | §3 table | **GO, applied** (2026-11-08) |
| **`20261109000600_notification_retry_cap`** | Caps outbox retries at 5 | 0400 | No privilege change; re-asserts service-role-only | **Function definition and 14 outbox rows captured before applying** [04] | N09–N12 (local), C15 (staging) | Re-run the 0400 definition | **GO, applied to staging 2026-11-09 with owner approval** [05][06] |
| legacy `0001`, `0019`, `0020`, `0021`, `cleanup_rls`, `test_rls_*` | Superseded | — | 0001 overrides `auth`; 0019/0020 have `anon`-executable functions and recursion; 0021 is the Gate 3 escalation | — | Gate 3 reproduction (15.3) | — | **NO-GO**: archived in `migrations/legacy/`, never applied |

## 4. Infrastructure touched in Phase 16 (all owner-approved or read-only)
- **Staging database:** read-only probes; migration 0600 via `supabase db push` after a backup and dry-run.
- **Staging Edge Functions:** `admin-users` redeployed.
- **Staging secrets:** `ALLOWED_ORIGINS` gained `http://localhost:5000` at 01:27Z and was **restored** to the Preview origin only at 02:10Z, verified by digest and by a live CORS check.
- **Staging data:** synthetic tickets `ITSR-00006` to `ITSR-00009`, created by the E2E runs.
- **Local:** a throwaway PG18 cluster in the session scratchpad on port 55433. **Untouched:** PostgreSQL 5432, the Docker test DB on 5433, ERPNext 8080, Docker, existing containers and databases. The local web server used port 5000 and was stopped afterwards.
- **Production:** none exists; nothing deployed.
- **Git:** committed and pushed to `origin/main` with owner approval, after a secret scan (GITHUB-PUSH-REPORT.md).

## 5. Remaining items (not complete; do not treat as done)

| Item | Status | Unblock |
|---|---|---|
| Gmail delivery | **BLOCKED** | Owner provides a Gmail App Password and real recipient addresses (DEPLOYMENT-GUIDE §4). The queue already holds 36 rows. |
| Retry scheduler | **NOT CONFIGURED** | Dashboard cron + `NOTIFICATIONS_CRON_SECRET` |
| Production environment | **NOT AUTHORIZED** | Separate written approval, then DEPLOYMENT-GUIDE §1–§8 |
| Vercel Preview with the Phase 16 build | **NOT DONE** (not requested) | The Preview still serves the Phase 15.3 build, which lacks fixes A1–A3. Redeploy, then update `ALLOWED_ORIGINS` to the new hostname. |
| First-login password change / password policy | Recommendation | SECURITY-REVIEW §8 |
