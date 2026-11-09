## 9. Corrected Deployment Sequence with Gates

### Pre-Deployment Checklist (Must Complete Before Each Gate)

| Check | Description | Status |
|-------|-------------|--------|
| **Backup** | Full database backup of local PostgreSQL (port 5433) and Supabase staging (read-only inventory) | ⬜ Not done |
| **Preflight** | Verify local database is operational on port 5433 | ⬜ Not done |
| **Port Check** | Confirm PostgreSQL port 5433 and ERPNext port 8080 are operational | ⬜ Not done |
| **Dependency Verification** | Confirm previous migration completed successfully | ⬜ Not done |

### 9.2 Deployment Sequence with Approval Gates

#### **Gate 1: Pre-Flight Validation**
```
□ Backup local PostgreSQL (port 5433)
□ Verify ERPNext (port 8080) operational
□ Read-only verify Supabase staging connectivity
□ Confirm corrected 0001 SQL can execute on isolated test DB (no auth.users)
□ GO/NO-GO Decision: Proceed to Gate 2?
```

#### **Gate 2: After Migration 0001 (LOCAL-TEST-ONLY)**
```
□ Execute corrected 0001 on local PostgreSQL port 5433
□ Verify all 5 tables created: profiles, tickets, ticket_activity_log, ticket_comments
□ Verify RLS is enabled on all tables
□ Verify no auth.uid(), auth.users, or auth.schema objects exist
□ GO/NO-GO Decision: Proceed to Gate 3? (If NO-GO, stop and resolve)
```

#### **Gate 3: After Migration 0019**
```
□ Apply 0019_add_security_fixes.sql
□ Verify RLS policies created: ticket_activity_log, ticket_comments, profiles
□ Verify triggers created: log_ticket_status_change, log_ticket_assignment_change, enforce_ticket_update_restrictions
□ Verify all SECURITY DEFINER functions have search_path = public
□ Verify EXECUTE grants: authenticated only (not PUBLIC) for security functions
□ GO/NO-GO Decision: Proceed to Gate 4? (If NO-GO, stop and resolve)
```

#### **Gate 4: After Migration 0020**
```
□ Apply 0020_add_security_mitigations.sql
□ Verify login_attempts table created with RLS policy "No direct user access"
□ Verify check_rate_limit() and cleanup_old_login_attempts() functions created
□ Verify search_path = public on all SECURITY DEFINER functions
□ Verify EXECUTE grants: service_role only on rate-limiting functions
□ Verify profiles/tickets/ticket_comments RLS policies updated
□ GO/NO-GO Decision: Proceed to Gate 5? (If NO-GO, stop and resolve)
```

#### **Gate 5: After Migration 0021**
```
□ Apply 0021_fix_rls_recursion.sql
□ Verify is_admin_or_it_support() function created (SECURITY DEFINER, search_path = public)
□ Verify EXECUTE GRANT TO authenticated only (not PUBLIC)
□ Verify legacy recursive policies DROPPED
□ Verify new policies use is_admin_or_it_support() helper function
□ Read-only verify function metadata (owner, BYPASSRLS, privileges)
□ GO/NO-GO Decision: Deployment to staging approved? (If NO-GO, stop and resolve)
```

### 9.3 Stop Conditions (Abort Deployment)
- ❌ **Any GO/NO-GO gate returns NO-GO** — stop and resolve before proceeding
- ❌ **Backup verification fails** — abort and restore from backup
- ❌ **Port conflict detected** (PostgreSQL 5433 or ERPNext 8080) — resolve before proceeding
- ❌ **Supabase staging metadata unverified** — do not proceed past Gate 5
- ❌ **Migration 0001 applied to Supabase staging** — immediately stop, this creates auth.uid()/auth.users conflicts
- ❌ **0021 applied before 0019 and 0020** — immediately stop, policy errors will occur
- ❌ **Rollback risks not accepted** — do not proceed if team cannot accept HIGH RISK rating for 0021 rollback

### 9.4 Final GO/NO-GO Assessment
VERDICT: **GO** — proceed with phased production promotion
VERDICT: **NO-GO** — resolve failing condition(s) before proceeding
```
All gates passed:
□ Corrected 0001 executed on local port 5433 (no auth.users dependencies)
□ 0019 applied successfully with proper RLS policies and triggers
□ 0020 applied successfully with security mitigations
□ 0021 applied successfully with is_admin_or_it_support() function
□ All function metadata read-verified against Supabase staging
□ Rollback plan documented and risks accepted
□ No broad EXECUTE grants to PUBLIC on SECURITY DEFINER functions
□ Port 5433 and 8080 preserved and operational
□ Supabase staging project status confirmed Healthy

VERDICT: **GO** — proceed with phased production promotion
VERDICT: **NO-GO** — resolve failing condition(s) before proceeding
```

The mandatory execution order is strict. **Never deviate** from this chain:

```
0001_initial_schema.sql (LOCAL-TEST-ONLY) → 0019_add_security_fixes.sql → 0020_add_security_mitigations.sql → 0021_fix_rls_recursion.sql
```

### 2.1 Migration 0001 — LOCAL-TEST-ONLY
- **Classification**: LOCAL-TEST-ONLY (do not apply to Sup
- **Purpose**: Baseline local PostgreSQL (port 5433) schema for testing
- **Dependencies**: None (base schema only)
- **Critical**: Does NOT create custom `auth.uid()`, `auth.set_uid()`, `auth.users` table, or Supabase-managed roles
- **See Section 3 for corrected SQL**

### 2.2 Migration 0019 — Security Policies and Triggers
- **Depends on**: 0001 (profiles, tickets tables must exist first)
- **Applies to**: Local test database AND Supabase staging
- **Contains**: RLS policies for ticket_activity_log, ticket_comments, profiles; triggers log_ticket_status_change(), log_ticket_assignment_change(), enforce_ticket_update_restrictions(); all functions with `SECURITY DEFINER` and `SET search_path = public`

### 2.3 Migration 0020 — Security Mitigations
- **Depends on**: 0019 (login_attempts table, hardened policies build on 0019 RLS)
- **Applies to**: Local test database AND Supabase staging
- **Contains**: login_attempts table, RLS profiles/tickets/ticket_comments hardening, check_rate_limit(), cleanup_old_login_attempts() functions (SECURITY DEFINER, search_path=public), EXECUTE grants to `service_role` only

### 2.4 Migration 0021 — SECURITY DEFINER Function and Non-Recursive RLS Policy Replacements
- **Depends on**: 0019 and 0020 (policies referencing is_admin_or_it_support(), login_attempts)
- **Applies to**: Local test database AND Supabase staging (after 0019 and 0020 are confirmed)
- **Contains**: is_admin_or_it_support() function (SECURITY DEFINER, search_path=public), policy replacements using the helper function, DROP of legacy recursive policies
- **Critical**: Never apply 0021 before its dependencies (0019 and 0020) are in place

### 2.5 Forbidden Order Violations
- ❌ **Never apply 0021 before 0019 and 0020 are complete** — policies referencing is_admin_or_it_support() will fail
- ❌ **Never apply 0001 to Supabase staging** — creates auth.uid()/auth.users conflicts with Supabase native auth
- ❌ **Never skip migrations** — leaves security gaps
## 1. Supabase Project Status Reconciliation

### 1.1 Verified Facts
- Supabase project `itsr-radiant-staging` was successfully created
- Dashboard status: **Healthy**
- Real runtime connection verified in PHASE 15.2 (HTTP requests succeeded, client initialized)
- `.env.staging` contains placeholder credentials only: `SUPABASE_URL=YOUR_STAGING_SUPABASE_URL`, `SUPABASE_ANON_KEY=YOUR_STAGING_SUPABASE_ANON_KEY`
- Key validation: Anon key prefix `sb_publishable_`, length 58 characters, not a service_role key

### 1.2 Required Separate Verification (Read-Only)
Do not execute migrations. Perform these read-only verifications separately:
- **Connection test**: Verify TCP connectivity to `https://yzjptffwnvnuyxbdkidm.supabase.co`
- **Schema inventory**: Read-only inspection of tables, columns, types, PK/FK, indexes, RLS status
- **Function metadata**: Read-only query of `pg_proc` for function existence, owner, SECURITY DEFINER status, search_path
- **Never present planned SQL output as executed evidence** (see Evidence Classifications section)

### 1.3 Evidence Classification
- **REMOTE-READ-VERIFIED**: Read-only SQL inspection of Supabase staging project metadata
- **NOT VERIFIED**: Any claim without actual read-only database inspection
## PHASE 15.3 — REVISED DEPLOYMENT READINESS PLAN

### Project Overview
- **Project**: ITSR Radiant Group Duri
- **Local PostgreSQL**: Port 5433 (preserved)
- **ERPNext**: Port 8080 (preserved)
- **Supabase Staging Project**: `itsr-radiant-staging` (URL: https://yzjptffwnvnuyxbdkidm.supabase.co, Region: Singapore)
- **Status**: Project dashboard shows Healthy; connectivity verified via runtime connection test