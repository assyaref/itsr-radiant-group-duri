# ITSR Radiant Group Duri: Final Test Report

**Updated:** 2026-11-09 (Phase 16)
**Evidence:** `reports/evidence/staging/phase16/` (cited as `[nn]`); earlier evidence is in `reports/evidence/staging/phase15.*`.
**Environments:**
- **Local:** a throwaway PostgreSQL 18 cluster on `localhost:55433`, plus Flutter and Deno test runners.
- **Staging:** Supabase `yzjpttfwnvnuyxbdkidm` with synthetic `STG*` accounts.
- **Production:** not provisioned, not touched.

**Status meanings:**
- **PASS:** executed and verified.
- **FAIL:** executed and failed.
- **BLOCKED:** needs external credentials, access or approval.
- **NOT TESTED:** not yet executed.

## 1. Suites executed in Phase 16

| Suite | Result | Evidence |
|---|---|---|
| Flutter `analyze` | **No issues found** | [02] |
| Flutter unit + widget tests | **54 / 54 PASS**. Adds 3 accessibility and semantics regression tests, each shown to fail on the pre-fix code. | [02] |
| Local SQL migration + security + workflow suite (0100–0600 on a fresh DB) | **99 / 99 PASS**. Static checks pass: no `auth` overrides, no RLS disable, no blanket EXECUTE. | [00_local_sql_suite] |
| Deno Edge Function unit tests + type-check | **14 / 14 PASS**, type-check clean | [00_deno_tests] |
| Read-only catalog assertions, staging (privileges, RLS, `auth.uid()`, retry cap) | **14 / 15 before 0600** (only C15 failed, as expected) → **15 / 15 after 0600** | [01], [09] |
| Migration 0600 on staging (backup → dry-run → push) | **PASS** | [04]–[06] |
| `admin-users` v4 `reset_password` validation, live on staging | **6 / 6 PASS** | [10] |
| **Browser E2E**: real Flutter Web release build ↔ staging backend, headless Chrome, 3 roles, desktop + phone | **27 / 27 verified**. Run 6: 26 / 27 PASS; M03's raw FAIL was a test-design error and passed on retest M03b. See `RUN-HISTORY.md`. | [13] |
| Real-time session expiry, staging | **6 / 6 PASS**. Expired token rejected by PostgREST (401), Edge Function (401) and Auth (403). | [03] |
| Release bundle secret scan | **PASS**: 0 JWTs and 0 `sb_secret_` key material | [11] |
| CORS allow-list restored after E2E | **PASS**: localhost has no ACAO; the Preview origin is echoed | [14] |

**Earlier phases, still valid** (no schema or function-code change except 0600 and `admin-users` since then):
- Staging API functional acceptance: 139 / 142 (15.4). The 2 FAILs were a WAF test expectation; the 1 BLOCKED was Gmail.
- Staging SQL security suite: 96 / 96 (15.3).
- Vercel unauthenticated sweep: 30 / 30 → SSO (15.4).

## 2. Acceptance criteria

**Columns:**
- **API:** real HTTP calls against staging.
- **Browser:** the Phase 16 E2E against the real Flutter Web build, with the check id in brackets.

### Employee
| Criterion | Status | API | Browser |
|---|---|---|---|
| Login succeeds with valid credentials | **PASS** | 15.4 | E02 |
| Login fails safely with invalid credentials | **PASS** | 15.4 (uniform padded 401, 429 after 5) | E01 (generic message, stays on login) |
| Session persistence | **PASS** | — | E03 (survives full reload) |
| Logout | **PASS** | 15.4 (refresh token revoked) | E09 (confirmation dialog → login; protected page redirects) |
| Create ticket | **PASS** | 15.4 | E05 (server-generated `ITSR-00009`) |
| View own tickets | **PASS** | 15.4 | E07 |
| Cannot view another employee's private ticket | **PASS** | 15.4 (RLS) | E08 (direct URL → "not found or no access") |
| Add comments where permitted | **PASS** | 15.4 (never internal) | E06 |
| Track ticket progress | **PASS** | 15.4 | E10 (resolution visible, internal note hidden) |
| Confirm/close or reopen own resolved ticket | **PASS** | 15.4 | E11 |
| Blocked from staff/admin pages | **PASS** | 15.4 (server-side) | E04 |

### IT Support
| Criterion | Status | API | Browser |
|---|---|---|---|
| Login | **PASS** | 15.4 | T01 |
| View tickets permitted by policy | **PASS** | 15.4 | T02 (queue) |
| Accept and assign tickets | **PASS** | 15.4 (assign to tech, auto-status) | T03 (accept) |
| Update ticket status | **PASS** | 15.4 (valid transitions only) | T04 (confirmation dialog) |
| Technical (internal) comments | **PASS** | 15.4 | T05 |
| Record resolutions | **PASS** | 15.4 (required by DB) | T06 |
| Activity history recorded correctly | **PASS** | 15.4 (unforgeable, undeletable) | T07 |

### Administrator
| Criterion | Status | API | Browser |
|---|---|---|---|
| Login | **PASS** | 15.4 | A01 |
| Manage employees and roles | **PASS** | 15.4: create, update, 409 duplicate, self-demote 400, reset, deactivate. Phase 16: reset validation 6/6 [10]. | A02 (user list with roles) |
| Category management | **PASS** | 15.4 | A03 |
| Application settings | **PASS** | 15.4 (admin-only) | A04 |
| Ticket oversight | **PASS** | 15.4 (stats = SQL truth) | A05 (all tickets + full history) |
| Privileged actions authorized server-side | **PASS** | 15.4 (39 security checks), Phase 16 [10] | — |

### System
| Criterion | Status | Evidence |
|---|---|---|
| RLS enforced | **PASS** | Local SQL 99/99; staging catalog 15/15 [09]; API 15.4; browser E08/E10 |
| No service-role key in the browser | **PASS** | Bundle scan [11]; startup guard (unit test) |
| Session expiry | **PASS** | [03] |
| Native `auth.uid()` (no override); least-privilege EXECUTE | **PASS** | Catalog C05–C08, C14 [09]; SECURITY-REVIEW §3 |
| Mobile layout | **PASS** | M01, M02, M03b, M04; widget tests at 320 px |
| Desktop layout | **PASS** | E/T/A checks at 1440 × 900 |
| Accessible navigation (screen reader) | **PASS after fixes A1/A2** | Browser E2E is driven entirely through the accessibility tree; 3 regression tests |
| No critical analyzer errors | **PASS** | [02] |
| Automated tests pass | **PASS** | §1 |
| Production build succeeds | **PASS** | `flutter build web --release` (Phase 16 final build) |
| Notification queue (triggers → outbox) | **PASS** | 36 pending rows after E2E; internal notes not queued (15.4) |
| **Email delivery (Gmail)** | **BLOCKED** | `GMAIL_USER` / `GMAIL_APP_PASSWORD` are not set on staging, and the IT-group and manager addresses are empty. The owner chose to leave this blocked on 2026-11-09. Steps: DEPLOYMENT-GUIDE §4. |
| Notification retry scheduler | **NOT TESTED** (not configured) | `pg_cron` absent; no Dashboard cron. Owner action: DEPLOYMENT-GUIDE §4. |
| Production deployment | **NOT TESTED** (not authorized) | No production project exists. |

## 3. Observations recorded during Phase 16
- **Function versions moved to login v5, admin-users v6, send-notifications v5.** The two `ALLOWED_ORIGINS` updates each bumped every function's version by 1. Code `updated_at` is unchanged for `login` and `send-notifications` (2026-11-08 08:23Z). `admin-users` changed only at 01:24Z, which was the approved deploy.
- **Synthetic staging data now in place:**
  - 8 tickets (`ITSR-00001` to `ITSR-00009`; numbers can skip because sequence values are not reused after rollbacks)
  - 9 comments
  - 36 pending outbox rows, all addressed to `@example.com` and undeliverable by design [17]
