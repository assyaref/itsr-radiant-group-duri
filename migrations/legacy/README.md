# Legacy migrations — SUPERSEDED, DO NOT EXECUTE

These files are kept for history only. They were applied only to disposable local
test databases and **never** to the Supabase staging or production project
(verified 2026-11-08: staging `yzjpttfwnvnuyxbdkidm` contained no application tables).

The authoritative, Supabase-CLI-compatible chain is `supabase/migrations/`.

| File | Decision | Reason |
|---|---|---|
| 0001_initial_schema.sql | NO-GO | Creates `auth` schema/`auth.users`/overrides `auth.uid()` (would conflict with Supabase Auth); schema (`title`, no `ticket_number`) does not match the app; global `GRANT EXECUTE ON ALL FUNCTIONS` + `ALTER DEFAULT PRIVILEGES ... TO anon` (Gate 3 root cause). Replaced by `20261108000100_core_schema.sql`; the auth shim moved to `supabase/tests/local/00_supabase_shim.sql` (LOCAL-TEST-ONLY). |
| 0019_add_security_fixes.sql | NO-GO | Self-referencing `profiles` policies (infinite recursion); update-restriction trigger blocks reassignment/priority changes for IT; no ticket INSERT/UPDATE policies. Replaced by 0200/0300. |
| 0020_add_security_mitigations.sql | NO-GO | `check_rate_limit()`/`cleanup_old_login_attempts()` executable by anon/authenticated — **confirmed by execution** (Gate 3); per-IP counting of all attempts would lock out an office NAT. Replaced by 0200/0400. |
| 0021_fix_rls_recursion.sql | NO-GO | Not executed (Gate 3 unresolved in that chain). Its recursion fix is reimplemented in 0200 via `private.*` SECURITY DEFINER helpers with `search_path=''` and explicit EXECUTE grants. |
| cleanup_rls.sql, test_rls_*.sql | NO-GO | Ad-hoc scripts for the legacy chain. |

## obsolete_tests/
Tests written for the legacy chain, archived 2026-11-08 (not deleted):
`integration/*` (TRUNCATE + re-create legacy policies on port 5433), `rate_limiter_test.dart` /
`auth_service_test.dart` / `security_configuration_test.dart` / `widget_test.dart` (assertions that did
not exercise application code), `rls_security_test.dart` (hard-coded fake IDs), and the root-level
`test_connection_validation.dart` (did not compile; pointed at a non-existent project ref).
Replaced by `supabase/tests/local/*` (SQL, 92 assertions), `supabase/functions/tests/*` (Deno) and `test/**` (Flutter).
