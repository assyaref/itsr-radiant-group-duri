# PHASE 15.3 — GATE 3 SECURITY VERIFICATION CORRECTION

## Executive Summary

The Gate 3 report is NOT approved. Migration 0021 must NOT be executed. This document presents the security verification correction based on code inspection of migration SQL files, as the PostgreSQL server on localhost:5433 is currently not running (connection refused).

## Evidence Classifications

- **LOCAL-EXECUTED**: Not applicable — PostgreSQL server not running
- **CODE-INSPECTED**: All findings derived from SQL migration file inspection
- **REMOTE-READ-VERIFIED**: Not applicable — no remote database access available
- **NOT VERIFIED**: PostgreSQL connection, actual database name

## 1. PostgreSQL Connection Verification

- **Host**: localhost
- **Port**: 5433
- **Status**: NOT VERIFIED — Connection refused (server not running)
- **Docker Compose config**: Port 5433 maps to container port 5432, database `itsr_radiant_test`
- **PostgreSQL 18 installed**: `C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe` found but not running
- **Database name verification**: Expected `itsr_radiant_test_gate1` (per task), docker-compose shows `itsr_radiant_test`
- **Status**: NOT VERIFIED — Could not connect to confirm actual database name

## 2. Migration 0020 Verification

### 2.1 Applied Status

- **STATUS**: Applied (confirmed from PHASE13-FINAL-REPORT.md and PHASE15.2-FINAL-REPORT.md)
- **Migration file**: `migrations/0020_add_security_mitigations.sql`
- **Applied order**: 0001 → 0019 → 0020 (confirmed)

### 2.2 Inspected Elements

#### 2.2.1 public.login_attempts Table

```sql
CREATE TABLE public.login_attempts (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  ip_address TEXT NOT NULL,
  employee_number TEXT,
  user_id UUID REFERENCES public.profiles(id),
  success BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);
```

**RLS Status**: ENABLED

```sql
ALTER TABLE public.login_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "No direct user access to login_attempts" ON public.login_attempts
  FOR ALL USING (false);
```

- **Finding**: RLS is enabled with a policy that blocks ALL user access (FOR ALL USING (false)). This is a fail-closed rate limiting design.

#### 2.2.2 check_rate_limit() Function

```sql
CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_ip_address TEXT,
  p_max_attempts INTEGER,
  p_window_minutes INTEGER
) RETURNS BOOLEAN AS $$
DECLARE
  v_lock_id BIGINT;
  v_attempt_count INTEGER;
BEGIN
  -- Use advisory lock based on IP to prevent race conditions
  SELECT ('x'||substr(md5(p_ip_address), 1, 16))::bit(64)::bigint INTO v_lock_id;
  PERFORM pg_advisory_xact_lock(v_lock_id);

  -- Clean up old attempts within the transaction
  DELETE FROM public.login_attempts
  WHERE ip_address = p_ip_address
    AND created_at < NOW() - (p_window_minutes || ' minutes')::INTERVAL;

  -- Count remaining attempts after cleanup
  SELECT COUNT(*) INTO v_attempt_count
  FROM public.login_attempts
  WHERE ip_address = p_ip_address;

  -- If at or above limit, fail-closed: block the request
  IF v_attempt_count >= p_max_attempts THEN
    RETURN false;
  END IF;

  -- Insert the new attempt within the same locked transaction
  INSERT INTO public.login_attempts (ip_address, employee_number, success, created_at)
  VALUES (p_ip_address, NULL, false, NOW());

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    -- Fail-closed: if any database error occurs, block the request
    RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;
```

**Privilege hardening**:

```sql
REVOKE ALL ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTEGER) TO service_role;
```

#### 2.2.3 cleanup_old_login_attempts() Function

```sql
CREATE OR REPLACE FUNCTION public.cleanup_old_login_attempts()
RETURNS INTEGER AS $$
DECLARE
  v_deleted_count INTEGER;
BEGIN
  DELETE FROM public.login_attempts
  WHERE created_at < NOW() - INTERVAL '7 days'; -- Keep only 7 days of history
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN v_deleted_count;
EXCEPTION
  WHEN OTHERS THEN
    RETURN 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;
```

**Privilege hardening**:

```sql
REVOKE ALL ON FUNCTION public.cleanup_old_login_attempts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_old_login_attempts() TO service_role;
```

## 3. CRITICAL: Audit Effective EXECUTE Privileges

### 3.1 Global vs Individual Privilege Interaction

The core security finding involves the interaction between two grant types:

**Global grant** (from earlier migration or configuration):
```sql
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon, service_role;
```

**Individual function revokes/grants** (from migration 0020):
```sql
-- check_rate_limit
REVOKE ALL ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTEGER) TO service_role;

-- cleanup_old_login_attempts
REVOKE ALL ON FUNCTION public.cleanup_old_login_attempts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_old_login_attempts() TO service_role;
```

### 3.2 Security Finding: Privilege Escalation via Global Grant

**FINDING CLASSIFICATION: SECURITY FINDING - CRITICAL**

The `REVOKE ALL ON FUNCTION FROM PUBLIC` statements only revoke privileges from the `PUBLIC` role. They do NOT revoke from `authenticated` or `anon` roles. The global `GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon, service_role` grants execute on ALL functions in the public schema to both `authenticated` and `anon` roles.

**Result**: Despite the individual `GRANT EXECUTE TO service_role` statements, both `authenticated` and `anon` can still execute:
- `public.check_rate_limit(TEXT, INTEGER, INTEGER)`
- `public.cleanup_old_login_attempts()`

This is because the global grant provides a baseline of execute privileges, and the individual revokes from PUBLIC do not override the authenticated/anon grants.

### 3.3 has_function_privilege() Analysis

Based on code inspection of the privilege structure:

| Function | Role | has_function_privilege() Classification |
|---|---|---|
| check_rate_limit | anon | **CAN EXECUTE** (via global grant, not blocked) |
| check_rate_limit | authenticated | **CAN EXECUTE** (via global grant, not blocked) |
| check_rate_limit | service_role | **CAN EXECUTE** (via individual grant) |
| cleanup_old_login_attempts | anon | **CAN EXECUTE** (via global grant, not blocked) |
| cleanup_old_login_attempts | authenticated | **CAN EXECUTE** (via global grant, not blocked) |
| cleanup_old_login_attempts | service_role | **CAN EXECUTE** (via individual grant) |

**Safety Restriction**: Do NOT silently modify permissions. The current privilege structure inadvertently allows anon and authenticated to execute rate-limiting functions.

## 5. Data Integrity Verification (Read-Only Queries)

### 5.1 Attempted Queries

Since PostgreSQL is not running, read-only queries could not be executed against the live database.

### 5.2 Expected Data (from migration code inspection)

**public.login_attempts** (if migration 0020 applied):
- Should contain rate limit attempt records
- RLS policy: FOR ALL USING (false) blocks all direct access
- Trigger activity: None specified in migration 0020

**Function existence** (from migration code):
- check_rate_limit should exist
- cleanup_old_login_attempts should exist
- RLS policies on login_attempts should exist

**Status**: NOT VERIFIED — Could not execute read-only queries against running database.

**Safety**: Read-only queries preserved data integrity — no data was modified or deleted.

## 6. Regression Tests

### 6.1 Test Results from Existing Reports

From **PHASE13-FINAL-REPORT.md** (Final Report):

```
### Test Results

| Category | Result |
|---|---|
| Flutter Analyze | PASS - No issues found |
| Unit Tests | 5/5 PASS |
| Integration Tests | PASS (with clean DB state) |
| Concurrency | 10 parallel: 5 allowed, 5 blocked |
| Fail-Closed | Verified (block on DB error) |
| Cleanup | Verified (expired attempts removed) |
```

From **FINAL_REPORT.md** (Integration Test Report):

```
### Database Environment
- **Database**: itsr_radiant_test (PostgreSQL)
- **Host**: localhost:5433
- **Container**: itsr-radiant-postgres-test (Docker, healthy)

### Migration 0020 Status
- ✅ Applied to TEST database
- ✅ Creates public.check_rate_limit() function
- ✅ Creates public.login_attempts table
- ✅ Not applied to production (correctly isolated)

### Key Finding

Integration tests require clean database state (0 records in public.login_attempts) at start. Tests build rate limit state sequentially. With clean state, all tests pass. With leftover records, tests fail due to rate limit already exceeded.
```

### 6.2 Test Classification

- **Code inspection**: Integration test design verified from report review ✅
- **Runtime test execution**: Not possible (PostgreSQL not running) ❌
- **Classification**: CODE-INSPECTED — Test results reported from code inspection, not runtime execution

## 7. Safety Compliance Verification

- ✅ Do not execute migration 0021
- ✅ Do not modify Supabase staging or production
- ✅ Do not disable RLS
- ✅ Do not reset passwords
- ✅ Preserve PostgreSQL port 5433
- ✅ Preserve ERPNext port 8080
- ✅ Do not delete databases, tables, records, or containers

## 8. Evidence Log

| Claim | Evidence Type | Status |
|---|---|---|
| PostgreSQL connection to localhost:5433 | NOT VERIFIED (server not running) | ⚠️ |
| Database name is itsr_radiant_test_gate1 | NOT VERIFIED (could not connect) | ⚠️ |
| Migration 0020 applied | CODE-INSPECTED (from SQL files and reports) | ✅ |
| public.login_attempts RLS enabled | CODE-INSPECTED (from SQL) | ✅ |
| check_rate_limit() exists | CODE-INSPECTED (from SQL) | ✅ |
| cleanup_old_login_attempts() exists | CODE-INSPECTED (from SQL) | ✅ |
| RLS policy FOR ALL USING (false) | CODE-INSPECTED (from SQL) | ✅ |
| anon can execute check_rate_limit via global grant | CODE-INSPECTED (privilege analysis) | ⚠️ FINDING |
| authenticated can execute check_rate_limit via global grant | CODE-INSPECTED (privilege analysis) | ⚠️ FINDING |
| GRANT EXECUTE ON ALL FUNCTIONS interaction | CODE-INSPECTED (from SQL grants) | ✅ |
| Function SECURITY DEFINER attributes | CODE-INSPECTED (from SQL) | ✅ |
| Regression test results | CODE-INSPECTED (from reports) | ✅ |
| Migration 0021 must not execute | SAFETY RESTRICTION | ✅ |

## 4. Function Owner, SECURITY DEFINER, and Privilege Inspection

### 4.1 Function Owners (from migration code inspection)

| Function | Likely Owner | Owner Role Attributes |
|---|---|---|
| check_rate_limit | Migration runner (postgres) | Not explicitly specified; owner has BYPASSRLS by default |
| cleanup_old_login_attempts | Migration runner (postgres) | Not explicitly specified; owner has BYPASSRLS by default |
| is_admin_or_it_support() | Migration runner (postgres) | Not explicitly specified |
| enforce_ticket_update_restrictions() | Migration runner (postgres) | Not explicitly specified |
| log_ticket_status_change() | Migration runner (postgres) | Not explicitly specified |
| log_ticket_assignment_change() | Migration runner (postgres) | Not explicitly specified |

**Remote verification NOT POSSIBLE**: Function owners cannot be verified from catalogs without a running PostgreSQL instance.

### 4.2 SECURITY DEFINER Attributes (from migration code)

All the following functions are defined with `SECURITY DEFINER`:

```sql
-- check_rate_limit
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- cleanup_old_login_attempts
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- is_admin_or_it_support()
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- enforce_ticket_update_restrictions()
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- log_ticket_status_change()
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- log_ticket_assignment_change()
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
```

**Finding**: All rate-limiting and security functions use SECURITY DEFINER, meaning they execute with the privileges of the function owner. This is intentional for bypassing RLS, but creates a risk if the owner role has excessive privileges.

### 4.3 proconfig/search_path (from migration code)

All functions explicitly set `SET search_path = public;` after the SECURITY DEFINER definition. This is a security best practice to prevent search_path poisoning attacks:

```sql
SET search_path = public;  -- Explicit search_path prevents poisoning
```

Without this explicit setting, a SECURITY DEFINER function could be vulnerable to search_path manipulation that resolves to a different schema with malicious objects of the same name.

### 4.4 Effective Privileges Summary

Based on code inspection:

**check_rate_limit()**:
- Owner: postgres (migration runner)
- SECURITY DEFINER: Yes
- search_path: public (explicitly set)
- EXECUTE grantees: service_role (individual) + authenticated + anon (via global grant)
- Security finding: anon and authenticated can execute via global grant

**cleanup_old_login_attempts()**:
- Owner: postgres (migration runner)
- SECURITY DEFINER: Yes
- search_path: public (explicitly set)
- EXECUTE grantees: service_role (individual) + authenticated + anon (via global grant)
- Security finding: anon and authenticated can execute via global grant

**is_admin_or_it_support()**:
- Owner: postgres (migration runner)
- SECURITY DEFINER: Yes
- search_path: public (explicitly set)
- EXECUTE grantees: authenticated (individual) + anon + service_role (via global grant)
- Note: Function not yet deployed to staging (per PHASE15.2.3 report)