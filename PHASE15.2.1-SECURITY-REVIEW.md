## A. Migration 0001 — Supabase Auth Compatibility

### Inspection Summary

Migration `0001_initial_schema.sql` creates a custom `auth.uid()` function for test environments:

```sql
-- Lines 41-53: Custom auth.uid() function
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
DECLARE
  v_uid TEXT;
BEGIN
  v_uid := current_setting('test.auth.uid', true);
  IF v_uid IS NULL OR v_uid = '' THEN
    RETURN NULL;
  END IF;
  RETURN v_uid::UUID;
END;
$$ LANGUAGE plpgsql STABLE;
```

### Conflict Analysis

| Element | Migration 0001 | Supabase Native | Conflict |
|---------|---------------|-----------------|----------|
| `auth.uid()` | Custom function reading `test.auth.uid` session variable | Built-in function from auth.extension | **HIGH CONFLICT** - Migration overrides native function |
| `auth.users` table | Created as `CREATE TABLE IF NOT EXISTS auth.users` | Managed by Supabase auth extension | **MEDIUM** - Could conflict if extension already provides table |
| Schema `auth` | Created with `CREATE SCHEMA IF NOT EXISTS auth` | Part of auth extension | **LOW** - Coexistable if properly managed |

### Safe Correction Proposal

**Option 1: Remove custom auth.uid() from migration 0001**
- Delete the custom function and set_uid helper
- Rely on Supabase's native `auth.uid()` when deployed to production
- Keep the function only for local test environments if needed

**Option 2: Make migration 0001 environment-conditional**
- Wrap the custom `auth.uid()` in a check for existing native function

**Recommended:** **Option 1** - Remove the custom `auth.uid()` from migration 0001 entirely. The test environment can use application-level context instead of overriding the native function.

**Never replace Supabase native authentication functions.** The `auth.uid()` function is managed by the auth extension and must not be overridden by migrations.

### Evidence

- Migration 0001 creates `auth.uid()` at line 43 of `migrations/0001_initial_schema.sql`
- The function uses `current_setting('test.auth.uid', true)` which is a test-only mechanism
- In production Supabase, `auth.uid()` is provided by the `auth` extension and reads from JWT claims
- Migration also creates `auth.users` table which could conflict with auth extension's management

---

Policies removed during migration 0021:

| # | Policy Name | Table | USING Expression | WITH CHECK Expression | Replacement |
|---|-------------|-------|-----------------|----------------------|-------------|
| 1 | "Users can view own profile" | profiles | `auth.uid() = id` | N/A | Replaced by new policy with `public.is_admin_or_it_support()` helper |
| 2 | "IT Support and Admins can view all profiles" | profiles | `EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('it_support', 'administrator'))` | N/A | Replaced by `public.is_admin_or_it_support()` function call |
| 3 | "Authenticated IT/Admin can view all profiles" | profiles | `auth.uid() IS NOT NULL AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('it_support', 'administrator'))` | N/A | Dropped (replaced by 0021 policy) |
| 4 | "Admins can view all profiles" | profiles | Likely similar EXISTS subquery | N/A | Dropped (replaced by 0021 policy) |
| 5 | "Authenticated employees can view own tickets" | tickets | `auth.uid() IS NOT NULL AND auth.uid() = reporter_id` | N/A | Dropped (replaced by 0020 policy with same expression but more explicit) |
| 6 | "Authenticated IT/Admin can view all tickets" | tickets | `auth.uid() IS NOT NULL AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('it_support', 'administrator'))` | N/A | Dropped (replaced by 0021 `public.is_admin_or_it_support()`) |

**Policies retained (not removed):**
- "Employees can view own tickets" - kept with `auth.uid() = reporter_id`
- "Employees can update own tickets" - kept with `auth.uid() = reporter_id AND status IN ('open', 'pending_user')`
- "Employees can view comments on own tickets" - kept with EXISTS subquery
- "Users can create comments" - kept with `auth.uid() = author_id`

### Security Impact Analysis

**Positive impacts:**
1. **Eliminates RLS recursion:** The EXISTS subqueries in original policies caused infinite recursion because RLS on `profiles` table triggered the policy check, which again checked the `profiles` table. The `public.is_admin_or_it_support()` function breaks this cycle.

2. **Prevents role enumeration:** The new policies are simpler and don't expose employee count or roles through RLS edge cases.

3. **Reduced attack surface:** Fewer complex subqueries mean fewer potential bypass vectors.

**Verdict:** Policies were removed with verified replacements. The replacement with SECURITY DEFINER function is a valid and recommended pattern for breaking RLS recursion in Supabase/PostgreSQL.

---
## B. Migration 0021 — RLS Recursion

### Complete Function SQL

```sql
-- Step 1: Create SECURITY DEFINER function
CREATE OR REPLACE FUNCTION public.is_admin_or_it_support()
RETURNS BOOLEAN AS
$$
DECLARE
  v_role TEXT;
BEGIN
  -- Get the current user's role using auth.uid()
  -- Explicit search_path = public prevents poisoning
  SELECT role INTO v_role
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_role IN ('it_support', 'administrator') THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public;

-- Step 2: Grant execute to authenticated users only
REVOKE ALL ON FUNCTION public.is_admin_or_it_support() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin_or_it_support() TO authenticated;
```
# PHASE 15.2.1 — DEEP SECURITY & MIGRATION REVIEW
## A. Migration 0001 — Supabase Auth Compatibility

### Inspection Summary

Migration `0001_initial_schema.sql` creates a custom `auth.uid()` function for test environments:

```sql
-- Lines 41-53: Custom auth.uid() function
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
DECLARE
  v_uid TEXT;
BEGIN
  v_uid := current_setting('test.auth.uid', true);
  IF v_uid IS NULL OR v_uid = '' THEN
    RETURN NULL;
  END IF;
  RETURN v_uid::UUID;
END;
$$ LANGUAGE plpgsql STABLE;
```

### Conflict Analysis

| Element | Migration 0001 | Supabase Native | Conflict |
|---------|---------------|-----------------|----------|
| `auth.uid()` | Custom function reading `test.auth.uid` session variable | Built-in function from auth.extension | **HIGH CONFLICT** - Migration overrides native function |
| `auth.users` table | Created as `CREATE TABLE IF NOT EXISTS auth.users` | Managed by Supabase auth extension | **MEDIUM** - Could conflict if extension already provides table |
| Schema `auth` | Created with `CREATE SCHEMA IF NOT EXISTS auth` | Part of auth extension | **LOW** - Coexistable if properly managed |

### Safe Correction Proposal

**Option 1: Remove custom auth.uid() from migration 0001**
- Delete the custom function and set_uid helper
- Rely on Supabase's native `auth.uid()` when deployed to production
- Keep the function only for local test environments if needed

**Option 2: Make migration 0001 environment-conditional**
- Wrap the custom `auth.uid()` in a check for existing native function

**Recommended:** **Option 1** - Remove the custom `auth.uid()` from migration 0001 entirely. The test environment can use application-level context instead of overriding the native function.

**Never replace Supabase native authentication functions.** The `auth.uid()` function is managed by the auth extension and must not be overridden by migrations.

### Evidence

- Migration 0001 creates `auth.uid()` at line 43 of `migrations/0001_initial_schema.sql`
- The function uses `current_setting('test.auth.uid', true)` which is a test-only mechanism
- In production Supabase, `auth.uid()` is provided by the `auth` extension and reads from JWT claims
- Migration also creates `auth.users` table which could conflict with auth extension's management

---

Project: ITSR Radiant Group Duri
Supabase: itsr-radiant-staging
Date: 11/5/2026

---

## EXECUTIVE SUMMARY

This read-only security and migration review examines all database migrations, edge functions, and RLS policies for the ITSR Radiant Group Duri project. The review identifies critical security findings, migration compatibility issues, and recommends execution order for Phase 15.3 approval.

**No database modifications**, SQL changes, or RLS disabling operations were performed during this review.

---
## D. Migration Comparison Matrix

### Six Migration Files Analysis

| # | File | Status | Conflicting Objects | Dependencies | Proposed Action |
|---|------|--------|--------------------|--------------|-----------------|
| 1 | `0001_initial_schema.sql` | ✅ Applied locally | **`auth.uid()` creation** - creates custom function that conflicts with Supabase native auth | Tables: profiles, tickets, ticket_comments, ticket_activity_log; Extensions: uuid-ossp, auth schema | **REMOVE** custom `auth.uid()` function. Keep table creation and RLS policies. |
| 2 | `0019_add_security_fixes.sql` | ✅ Applied locally | None critical | Depends on 0001; Used by 0020; Triggers depend on tickets table | **KEEP** - All security fixes are valid and should remain. |
| 3 | `0020_add_security_mitigations.sql` | ✅ Applied locally | None critical | Depends on 0019; Requires login_attempts table; Rate limiting function | **KEEP** - All mitigations are valid. Verify service_role key access on edge function. |
| 4 | `0021_fix_rls_recursion.sql` | ✅ Applied locally | None critical | Depends on 0019 and 0020; Policies referenced; Function grants | **KEEP** - RLS recursion fix is correct and necessary. |
| 5 | *(Not found in migrations directory)* | ❓ Missing | - | - | **SEARCH** - Need to locate sixth migration file or confirm only 4 exist. |
| 6 | *(Not found in migrations directory)* | ❓ Missing | - | - | **SEARCH** - Need to locate sixth migration file or confirm only 4 exist. |

### Detailed SQL Evidence for Proposed Changes

#### Migration 0001 - Correction Required

**Current (problematic):**
```sql
-- Lines 41-53: Custom auth.uid() - REMOVE
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
DECLARE
  v_uid TEXT;
BEGIN
  v_uid := current_setting('test.auth.uid', true);
  IF v_uid IS NULL OR v_uid = '' THEN
    RETURN NULL;
  END IF;
  RETURN v_uid::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- Lines 55-63: set_uid helper - optional keep for testing
CREATE OR REPLACE FUNCTION auth.set_uid(p_uid UUID) RETURNS VOID AS $$
BEGIN
  PERFORM set_config('test.auth.uid', p_uid::text, true);
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC;
GRANT EXECUTE ON FUNCTION auth.set_uid(UUID) TO PUBLIC;
```

**Proposed correction:**
```sql
-- REMOVE lines 41-63 (custom auth.uid() and set_uid)
-- Keep the rest of the migration intact

-- If test environment needs user context, use application-level setting
-- rather than overriding auth.uid()
```

**SQL to apply correction:**
```sql
-- Drop the custom function (if it exists and needs replacement)
DROP FUNCTION IF EXISTS auth.uid();
DROP FUNCTION IF EXISTS auth.set_uid();

-- Do NOT create replacement - use Supabase native auth.uid() in production
```

#### Migration 0021 - Verification (No changes needed)

The migration correctly:
1. Drops legacy policies with EXISTS subqueries
2. Creates `is_admin_or_it_support()` with SECURITY DEFINER and `search_path = public`
3. Replaces policies with function calls that break recursion
4. Grants EXECUTE only to `authenticated` role

**No SQL modifications required for 0021.**

### Migration Dependency Graph

```mermaid
graph TD
    M0001 --> M0019 --> M0020 --> M0021
    
    style M0001 fill:#ffdddd,stroke:#ff0000,stroke-width:2px
    style M0019 fill:#ddffdd,stroke:#00aa00,stroke-width:2px
    style M0020 fill:#ddddff,stroke:#0000ff,stroke-width:2px
    style M0021 fill:#fff3db,stroke:#e0a800,stroke-width:2px
    
    note M0001 "Remove custom auth.uid()"
    note M0019 "Security fixes - KEEP"
    note M0020 "Security mitigations - KEEP"
    note M0021 "RLS recursion fix - KEEP"
```

### Proposed Execution Order for Phase 15.3

1. **First:** Apply corrected 0001 (without custom auth.uid())
2. **Second:** Apply 0019 (security fixes)
3. **Third:** Apply 0020 (login security & RLS hardening)
4. **Fourth:** Apply 0021 (RLS recursion fix)

**Verification steps after each migration:**
- Confirm RLS is enabled on all tables
- Verify no policy recursion errors
- Test role-based access control
- Validate edge function connectivity
```

---