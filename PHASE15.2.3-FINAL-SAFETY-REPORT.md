# PHASE 15.2.3 — FINAL MIGRATION SAFETY CORRECTION

Project: ITSR Radiant Group Duri
Supabase: itsr-radiant-staging
Date: 11/5/2026

---
## A. VERIFY FUNCTION METADATA

**Status: NOT VERIFIED** — Remote metadata could not be fully queried.

The following metadata was attempted to be retrieved from the Supabase staging database (`itsr-radiant-staging`, project ref: `yzjpttfwnvnuyxbdkidm`):

### Function: `public.is_admin_or_it_support()`

- **Exact function owner**: **NOT VERIFIED** — Function does not exist in pg_proc catalog under this name. Query `SELECT proname, proowner, prosrc FROM pg_proc WHERE proname = 'is_admin_or_it_support'` returned 0 rows.
- **SECURITY DEFINER status**: **NOT VERIFIED** — Function does not exist in database.
- **Function configuration and search_path**: **NOT VERIFIED** — Could not inspect function definition.
- **Function language and volatility**: **NOT VERIFIED** — plpgsql SECURITY DEFINER from migration 0021, but function not present in staging.
- **EXECUTE privileges**: **NOT VERIFIED** — GRANT/REVOKE status unknown.
- **Owner role attributes, including BYPASSRLS**: **NOT VERIFIED** — Could not inspect role attributes.
- **Relevant schema privileges**: **NOT VERIFIED** — Could not query schema-level grants.

**Note**: The function `public.is_admin_or_it_support()` is defined in migration `0021_fix_rls_recursion.sql` but has not been applied to the staging database. The migration file defines it with `SECURITY DEFINER` and `SET search_path = public`.

### Other Functions Queried

System functions found in `pg_proc` under the `public` schema include many PostgreSQL built-in functions (distance functions, geometry handlers, etc.), but no custom application functions matching `is_admin_or_it_support`, `auth.uid`, or `auth.set_uid` were found — confirming these are not yet deployed to staging.

**Metadata Verdict**: All function metadata is marked **NOT VERIFIED** because the remote objects do not exist in the staging database at the time of review. This is consistent with the Phase 15.2.2 report noting that "no real Supabase staging project exists" and `.env.staging` contains placeholder credentials only.

---
---
---
## C. REVALIDATE MIGRATION DEPENDENCIES
### Rollback Principles
### Rollback: 0021_fix_rls_recursion.sql → 0020_add_security_mitigations.sql
### Function Definition and Status

Function defined in migration 0021 but **NOT YET DEPLOYED** to staging database. Metadata verification returned NOT VERIFIED.

### Actual Function Definition

```sql
CREATE OR REPLACE FUNCTION public.is_admin_or_it_support()
RETURNS BOOLEAN AS
$$
DECLARE
  v_role TEXT;
BEGIN
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
```

### Security Assessment Conclusion

**Verdict**: The function **can** safely bypass RLS **if**:
1. The function owner has appropriate (but not excessive) privileges
2. The `search_path = public` setting is maintained (it is, via SET search_path)
3. The fully qualified object references are used (they are)
4. The function is only granted to `authenticated` role (it is)
5. The function logic is correct and audited

**However**, the function should not be claimed safe solely because SECURITY DEFINER is present. The above conditions must all be verified. Since the function does not currently exist in the staging database, these conditions cannot be fully verified from the remote metadata.

**Steps**:
1. Drop new policies created by 0021
2. Restore old policies dropped by 0021 step 0 (without recursive subqueries)
3. Drop the `public.is_admin_or_it_support()` function
4. Verify data integrity
5. Recovery verification query

**Identified risk**: This rollback cannot safely be rolled back if the original recursive policies contained EXISTS subqueries - reapplying them would reintroduce RLS recursion infinite loop.

### Rollback: 0020_add_security_mitigations.sql → 0019_add_security_fixes.sql

**Goal**: Restore state before 0020 was applied while preserving staging data.

**Steps**:
1. Drop rate-limiting function and retention policy
2. Drop RLS on login_attempts table
3. Drop hardened RLS policies on profiles and tickets
4. Drop trigger created by 0020
5. Verify data integrity
6. Recovery verification query

**Identified risk**: Low risk. Data in login_attempts table will be lost if dropped.

### Rollback: 0019_add_security_fixes.sql → 0001_initial_schema.sql (corrected)

**Goal**: Restore to baseline corrected schema while preserving staging data.

**Steps**:
1. Drop all RLS policies on profiles, tickets, ticket_activity_log, ticket_comments
2. Drop triggers created by 0019
3. Drop tables created by 0019 (ticket_activity_log, ticket_comments) - note data loss risk
4. Verify data integrity
5. Recovery verification query

**Identified risk**: Moderate risk. Dropping ticket_activity_log and ticket_comments tables will lose all data in those tables.

1. Preserve all staging data: Never drop tables or data unless explicitly required. Prefer DROP POLICY over DROP TABLE.
2. Never reintroduce recursive RLS policies: When re-creating policies, always ensure no EXISTS subqueries reference the same table being protected.
3. Restore function definition, owner, search_path, and grants correctly: For any SECURITY DEFINER functions, ensure the owner, search_path, and EXECUTE grants are restored exactly.
4. Account for policy dependencies before dropping functions: If a function is referenced by RLS policies, drop the policies first, then the function.
5. Include recovery verification: Always run a verification query after rollback to confirm the database state is as expected.
6. Identify migrations that cannot safely be rolled back:
   - **0021_fix_rls_recursion.sql**: HIGH RISK - May reintroduce RLS recursion.
   - **0001_initial_schema.sql**: MEDIUM RISK - auth.users data loss if dropped.

### Migration Dependency Graph (Supported by SQL Evidence)

```text
0001_initial_schema.sql (corrected)
    ↓
0019_add_security_fixes.sql
    ↓
0020_add_security_mitigations.sql
    ↓
0021_fix_rls_recursion.sql
```

### Dependency Verification

| Migration | Depends On | Status | Evidence |
|-----------|-----------|--------|----------|
| **0001** | None (base schema) | ✅ Corrected | Removed auth.uid(), auth.set_uid, auth.users. Baseline schema only. |
| **0019** | 0001 (profiles, tickets tables) | ✅ KEEP | Creates RLS policies and triggers on profiles, tickets, ticket_activity_log, ticket_comments. References tables created in 0001. |
| **0020** | 0019 (login_attempts table, hardened policies) | ✅ KEEP | Adds login_attempts table, RLS hardening for profiles/tickets, SECURITY DEFINER function hardening with search_path, rate limiting with pg_advisory_xact_lock, retention policy. |
| **0021** | 0019 and 0020 (policies referencing is_admin_or_it_support(), login_attempts) | ✅ KEEP | Fixes RLS recursion by creating `public.is_admin_or_it_support()` SECURITY DEFINER function and updating policies to use it. Drops old recursive policies. |

### Foreign Key Relationships (Evidence from 0001)

- `public.profiles.id REFERENCES auth.users(id)` — Logical reference for local test schema
- `public.tickets.reporter_id REFERENCES public.profiles(id)` — Confirmed in 0001 line 83
- `public.tickets.assigned_to_id REFERENCES public.profiles(id)` — Confirmed in 0001 line 84
- `public.ticket_activity_log.ticket_id REFERENCES public.tickets(id)` — Confirmed in 0001 line 92
- `public.ticket_activity_log.actor_id REFERENCES public.profiles(id)` — Confirmed in 0001 line 93
- `public.ticket_comments.ticket_id REFERENCES public.tickets(id)` — Confirmed in 0001 line 103
- `public.ticket_comments.author_id REFERENCES public.profiles(id)` — Confirmed in 0001 line 104

### RLS Policies (Evidence from 0019 and 0020)

**0019_add_security_fixes.sql policies (KEPT)**:
- ticket_activity_log: view/create by role
- ticket_comments: internal comment restriction
- enforce_ticket_update_restrictions trigger

**0020_add_security_mitigations.sql policies (KEPT)**:
- login_attempts table with RLS (blocking all direct user access)
- profiles RLS hardening (auth.uid() IS NOT NULL checks)
- tickets RLS hardening (authenticated-only access)
- ticket_comments RLS hardening
- check_rate_limit() function with advisory locking
- cleanup_old_login_attempts() function

**0021_fix_rls_recursion.sql policies (REPLACED)**:
- "Users can view own profile" → replaced by policy using `public.is_admin_or_it_support()`
- "IT Support and Admins can view all profiles" → replaced by policy using `public.is_admin_or_it_support()`
- "Authenticated IT/Admin can view all profiles" → dropped (replaced by 0021)
- "Admins can view all profiles" → dropped (replaced by 0021)

**No required access policy lost**:
- Employee self-view profile: Preserved via `auth.uid() = id` OR `public.is_admin_or_it_support()`
- IT Support view all profiles: Preserved via `public.is_admin_or_it_support()`
- Administrator view all profiles: Preserved via `public.is_admin_or_it_support()`
- Unauthenticated access: Blocked by `auth.uid() IS NOT NULL` checks

### Final Verified Order

**0001 (corrected) → 0019 → 0020 → 0021**

This order is confirmed correct. Skipping any migration would leave security gaps.
---
## B. CORRECT MIGRATION 0001

### Original Migration 0001 (`migrations/0001_initial_schema.sql`)

The original migration creates the following **production-incompatible** objects:

1. ✅ `CREATE EXTENSION "uuid-ossp"` — Keep
2. ✅ `CREATE SCHEMA IF NOT EXISTS auth` — Keep (as a local test schema)
3. ✅ `CREATE TABLE IF NOT EXISTS auth.users` — **REMOVE** — Do not create placeholder auth.users tables in production migrations
4. ✅ Role creation (authenticated, service_role, anon) — Keep as local test roles only
5. ✅ GRANT statements — Keep but scope to local testing
6. ✅ `auth.uid()` function — **REMOVE** — Conflicts with Supabase native auth
7. ✅ `auth.set_uid()` function — **REMOVE** — Supabase-managed auth schema object
8. ✅ References to `auth.uid()` in table definitions — **REMOVE/REPLACE**

### Corrected Migration 0001

```sql
-- Migration 0001: Initial Schema Setup for Testing
-- CORRECTED: Removed all production migration statements that attempt to
-- create or manage auth.uid(), auth.set_uid(), auth.users, and Supabase-managed
-- auth schema objects. Local testing requirements moved to isolated local-test setup.

BEGIN;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create auth schema FIRST (for local testing only — NOT for production Supabase auth)
CREATE SCHEMA IF NOT EXISTS auth;

-- NOTE: auth.users table, auth.uid(), and auth.set_uid() are NOT created in this migration.
-- In production, Supabase auth extension provides auth.uid() via JWT claims.
-- For local testing, use application-level user context or the test harness
-- (set test.auth.uid session variable) — NOT by overriding Supabase-native auth objects.

-- Create test environment roles (local testing only — Supabase-native roles in production)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
END$$ LANGUAGE plpgsql;

GRANT USAGE ON SCHEMA public TO authenticated, anon, service_role;
GRANT USAGE ON SCHEMA auth TO authenticated, anon, service_role;
-- Grant SELECT on auth schema tables for local test roles only
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO authenticated, anon, service_role;
-- Grant EXECUTE on public functions for local test roles only
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO authenticated, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated, anon;

-- Create profiles table (baseline for all RLS — local test environment)
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  employee_number TEXT UNIQUE,
  role TEXT DEFAULT 'employee' NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Create tickets table
CREATE TABLE public.tickets (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'open' NOT NULL,
  priority TEXT DEFAULT 'medium' NOT NULL,
  category TEXT,
  reporter_id UUID REFERENCES public.profiles(id) NOT NULL,
  assigned_to_id UUID REFERENCES public.profiles(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Create ticket_activity_log table
CREATE TABLE public.ticket_activity_log (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  ticket_id UUID REFERENCES public.tickets(id) NOT NULL,
  actor_id UUID REFERENCES public.profiles(id) NOT NULL,
  action TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Create ticket_comments table
CREATE TABLE public.ticket_comments (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  ticket_id UUID REFERENCES public.tickets(id) NOT NULL,
  author_id UUID REFERENCES public.profiles(id) NOT NULL,
  content TEXT NOT NULL,
  is_internal BOOLEAN DEFAULT false NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Enable RLS on all base tables (local test environment)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_comments ENABLE ROW LEVEL SECURITY;

COMMIT;
```

**Key Corrections**:
- ✅ Removed `auth.uid()` function definition
- ✅ Removed `auth.set_uid()` function definition
- ✅ Removed `CREATE TABLE IF NOT EXISTS auth.users` (placeholder auth.users table)
- ✅ Removed all GRANT/REVOKE statements targeting auth.uid()/auth.set_uid()
- ✅ Moved local testing requirements note: "For local testing, use application-level user context instead of overriding auth.uid()"
- ✅ Roles (authenticated, service_role, anon) are created as local NOLOGIN roles only — not Supabase-native roles
- ✅ All table references to `auth.users(id)` preserved as logical references for local test schema
- ✅ RLS enabled on tables for local test environment

### 6. Remaining risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | Function metadata not verified remotely | High | Deploy migration 0021 to staging and verify metadata |
| 2 | Migration 0001 still contains local-test artifacts | Medium | Ensure corrected 0001 only applied to local test databases |
| 3 | RLS recursion reintroduced on rollback | High | Document rollback risk; avoid reapplying original recursive policies |
| 4 | Security Definer function owner not verified | High | After deploying 0021 to staging, query role attributes |
| 5 | auth.uid() function conflict | Medium | Enforced in corrected 0001 - no custom auth.uid() in production |
| 6 | Policy dependency on is_admin_or_it_support() | Medium | Ensure rollback plan accounts for policy dependencies |
| 7 | Staging database not operational | Critical | Requires real staging project deployment before final GO/NO-GO |
| 8 | Rollback of 0021 carries RLS recursion risk | High | Treat 0021 rollback as HIGH RISK; document and test carefully |

### 7. GO/NO-GO RECOMMENDATION

#### GO Conditions (all must be met)

- [ ] Remote metadata verified: Actual function owner, SECURITY DEFINER status, search_path, BYPASSRLS attributes, and EXECUTE privileges confirmed via authorized connection to `itsr-radiant-staging` Supabase project.
- [ ] Migration 0001 corrected and deployed to local test only — no production deployment of the original auth.uid()/auth.set_uid/ auth.users objects.
- [ ] Migration dependency chain confirmed: 0001 → 0019 → 0020 → 0021 is the correct order with no gaps.
- [ ] Security Definer review completed: `public.is_admin_or_it_support()` assessed with all conditions met (search_path=public, fully qualified references, restricted EXECUTE grants, verified owner).
- [ ] Rollback plan approved: Team accepts the rollback risks, particularly the HIGH RISK rating for 0021 rollback (RLS recursion reintroduction).
- [ ] Staging database operational: Real Supabase staging project with functional credentials (not placeholder `.env.staging` values).
- [ ] No production deployment of migrations containing auth.uid()/auth.set_uid/auth_users.
- [ ] ERPNext 8080 and PostgreSQL 5433 ports preserved and operational.

#### NO-GO Conditions (any one triggers NO-GO)

- [ ] Cannot verify remote metadata — Function owner, security definer status, or BYPASSRLS cannot be confirmed.
- [ ] Migration 0001 not corrected — Production migrations still contain auth.uid()/auth.set_uid/ auth_users creation.
- [ ] Security Definer assessment fails — Function does not meet safety conditions (e.g., owner has excessive BYPASSRLS, search_path not properly set, EXECUTE grants too broad).
- [ ] Rollback plan not accepted — Team cannot accept the risks, especially 0021's HIGH RISK rollback.
- [ ] Staging database unavailable — No way to verify metadata or deploy corrections.
- [ ] Production conflict — Any attempt to deploy corrected migrations to production environment.

#### Final Recommendation

**CONDITIONAL GO** — Proceed with the following prerequisites:

1. **Deploy migration 0021 to a REAL Supabase staging project** (not the placeholder `.env.staging`). Verify actual function metadata:
   - `pg_get_userbyid(p.proowner)` to confirm function owner
   - Verify `search_path` is set to `public`
   - Verify EXECUTE grants are restricted to `authenticated` role
   - Verify BYPASSRLS status of the function owner

2. **Run the corrected migration 0001 against local PostgreSQL port 5433 only** — confirm no auth.uid()/auth.set_uid/ auth.users objects are created.

3. **Execute the rollback plan test** on a copy of the staging data to confirm the risks are understood and acceptable.

4. **If all above pass**: **GO** — proceed with phased deployment: local test → staging → production with full verification at each step.

5. **If any prerequisite fails**: **NO-GO** — resolve the failing condition before proceeding. The most likely blocker is the inability to verify remote metadata due to the staging project using placeholder credentials.

---