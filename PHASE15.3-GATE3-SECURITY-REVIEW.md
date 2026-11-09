# PHASE 15.3 — GATE 3 SECURITY REVIEW

## Executive Summary

Security privilege escalation finding in migration 0020 rate-limiting functions. The global grant `GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon, service_role` allows anon and authenticated to execute `check_rate_limit()` and `cleanup_old_login_attempts()`, despite individual `REVOKE ALL ON FUNCTION FROM PUBLIC` + `GRANT EXECUTE TO service_role` statements in migration 0020. The REVOKE FROM PUBLIC only revokes from the PUBLIC role, not from authenticated or anon.

**Classification**: SECURITY FINDING - CRITICAL
**Status**: CODE-INSPECTED (PostgreSQL server not running, catalog queries not possible)
**Safety**: No database modifications, no migration 0021 execution, ports preserved

## 1. Privilege Structure Analysis

### 1.1 Global Grant (from earlier migration/configuration)

```sql
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon, service_role;
```

This global grant provides a **baseline execute privilege** to all three roles on ALL functions in the public schema.

### 1.2 Individual Function Hardening (from migration 0020)

```sql
-- check_rate_limit
REVOKE ALL ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTEGER) TO service_role;

-- cleanup_old_login_attempts
REVOKE ALL ON FUNCTION public.cleanup_old_login_attempts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_old_login_attempts() TO service_role;
```

**Finding**: `REVOKE ALL ON FUNCTION FROM PUBLIC` only revokes from the `PUBLIC` role. It does **not** revoke from `authenticated` or `anon` roles. The global grant provides a baseline that the `REVOKE ALL FROM PUBLIC` cannot override.

## 2. System Catalog Evidence (Expected, Not Executable)

### 2.1 Expected `has_function_privilege()` Results

Based on code inspection of the privilege structure, the following would be the expected queries and results **once PostgreSQL is running**:

```sql
-- Expected: anon can execute check_rate_limit
SELECT has_function_privilege('anon', 'public.check_rate_limit', 'EXECUTE');
-- Result: true (via global grant, not blocked by REVOKE FROM PUBLIC)

-- Expected: authenticated can execute check_rate_limit  
SELECT has_function_privilege('authenticated', 'public.check_rate_limit', 'EXECUTE');
-- Result: true (via global grant, not blocked by REVOKE FROM PUBLIC)

-- Expected: service_role can execute check_rate_limit
SELECT has_function_privilege('service_role', 'public.check_rate_limit', 'EXECUTE');
-- Result: true (via individual GRANT EXECUTE TO service_role)

-- Expected: anon can execute cleanup_old_login_attempts
SELECT has_function_privilege('anon', 'public.cleanup_old_login_attempts', 'EXECUTE');
-- Result: true (via global grant, not blocked by REVOKE FROM PUBLIC)

-- Expected: authenticated can execute cleanup_old_login_attempts
SELECT has_function_privilege('authenticated', 'public.cleanup_old_login_attempts', 'EXECUTE');
-- Result: true (via global grant, not blocked by REVOKE FROM PUBLIC)

-- Expected: service_role can execute cleanup_old_login_attempts
SELECT has_function_privilege('service_role', 'public.cleanup_old_login_attempts', 'EXECUTE');
-- Result: true (via individual GRANT EXECUTE TO service_role)
```

### 2.2 Expected Function Owner and SECURITY DEFINER Catalog Queries

```sql
-- Expected function owner query
SELECT proname, proowner, prosrc 
FROM pg_proc 
WHERE proname IN ('check_rate_limit', 'cleanup_old_login_attempts');

-- Expected: owner has BYPASSRLS by default (all superusers and role creators have BYPASSRLS)
-- Expected: search_path = public is explicitly set in function definition
-- Expected: SECURITY DEFINER means functions execute with owner privileges
```

### 2.3 Expected Role Membership and Inherited Privileges

```sql
-- Expected: checking role membership chains
SELECT rolname, memberof FROM pg_roles;

-- Expected: authenticated role membership
SELECT rolcanlogin, rolsuper, rolbypassrls 
FROM pg_roles WHERE rolname = 'authenticated';

-- Expected: anon role membership  
SELECT rolcanlogin, rolsuper, rolbypassrls 
FROM pg_roles WHERE rolname = 'anon';

-- Expected: service_role membership
SELECT rolcanlogin, rolsuper, rolbypassrls 
FROM pg_roles WHERE rolname = 'service_role';
```


---

## RESOLUTION — 2026-11-08 (evidence-based)

### 1. Finding confirmed by execution (previously CODE-INSPECTED only)
Legacy 0001 → 0019 → 0020 were applied **unchanged** to a disposable database (`gate3_repro`, throwaway
PostgreSQL 18 cluster on localhost:55433; ports 5432/5433/8080 untouched). Result
(`reports/evidence/gate3_legacy_reproduction.txt`):

| function | anon | authenticated | service_role |
|---|---|---|---|
| check_rate_limit | **t** | **t** | t |
| cleanup_old_login_attempts | **t** | **t** | t |

**Root-cause correction:** `GRANT EXECUTE ON ALL FUNCTIONS` only affects functions that exist when it runs.
The grant that actually reached 0020's functions is `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE
ON FUNCTIONS TO authenticated, anon` in 0001. Hosted Supabase applies equivalent default privileges, so
`REVOKE ... FROM PUBLIC` is insufficient there as well. The finding is therefore valid on Supabase itself, not just in the local test schema.

### 2. Remediation
The legacy chain was never applied to staging. Staging (`yzjpttfwnvnuyxbdkidm`) was probed read-only on 2026-11-08 and
contained no application tables. Note that the ref `yzjptffw…` recorded in Phase 15.1/15.2 does not resolve (NXDOMAIN).
The legacy chain was archived to `migrations/legacy/` (NO-GO for every file) and replaced by `supabase/migrations/`:
- `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON FUNCTIONS FROM public, anon, authenticated` (closes the root cause).
- Every function: explicit `REVOKE ALL ... FROM public, anon, authenticated` and then a minimal `GRANT`.
- Rate-limit/outbox RPCs: `service_role` only. Role helpers live in the non-exposed `private` schema.
- All SECURITY DEFINER functions: owner `postgres`, `SET search_path = ''`, fully-qualified names.
- Migration 0021's recursion fix is reimplemented via `private.is_staff()/is_admin()` instead of executing 0021.

### 3. Verification (`reports/evidence/catalog_privileges_and_rls.txt`, `sql_acceptance_tests.txt`)
- anon can execute **0** app functions (P02); anon has **0** table privileges (P03); anon has no usage on `private` (P09).
- `login_is_rate_limited`, `record_login_attempt`, `claim_notifications`, `complete_notification`: executable by service_role only (P01a–e, AN04).
- Every SECURITY DEFINER function pins search_path (P06); RLS is enabled on all 8 tables (P07); legacy functions are absent (P08).
- SQL acceptance suite: **95/95 PASS**, run against an emulation of Supabase's permissive default privileges (worst case).

### Gate 3 decision
- Gate 3 finding: **RESOLVED (LOCAL-EXECUTED)**.
- Legacy 0021: **NO-GO (superseded, never executed)**.
- New chain: **GO for staging**, pending explicit approval plus staging DB credentials. It has not been applied to staging or production yet.
