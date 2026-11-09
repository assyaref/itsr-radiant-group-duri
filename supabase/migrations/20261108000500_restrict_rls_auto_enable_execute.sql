-- =============================================================================
-- ITSR Radiant Group Duri — Migration 0500: least privilege for the platform
-- function public.rls_auto_enable() (Phase 15.3 security finding).
--
-- Finding (staging yzjpttfwnvnuyxbdkidm, 2026-11-08):
--   * public.rls_auto_enable() is platform-installed (not created by ITSR
--     migrations); it backs the event trigger "ensure_rls", which turns ON row
--     level security for tables created in schema public.
--   * It is SECURITY DEFINER, owned by postgres, search_path pinned to pg_catalog.
--   * Its ACL is NULL, so PostgreSQL's built-in default applies: EXECUTE to PUBLIC.
--     anon/authenticated therefore inherit EXECUTE, and anon could reach it via
--     PostgREST (POST /rest/v1/rpc/rls_auto_enable -> privilege check passed,
--     failed only at output: "cannot display a value of type event_trigger").
--   * Impact assessed as LOW: the body can only ENABLE RLS (never disable) and
--     only for tables reported by pg_event_trigger_ddl_commands(), which is empty
--     outside a DDL event — a direct call is a no-op. Still, no client role needs
--     EXECUTE on an event-trigger function, so the grant is removed.
--
-- Effect: removes EXECUTE from PUBLIC, anon, authenticated and service_role.
-- The owner keeps EXECUTE. The event trigger keeps firing: PostgreSQL does not
-- check EXECUTE on the trigger function at fire time (verified on a throwaway
-- cluster before applying — see PHASE15.3-VERCEL-STAGING-SECURITY-REPORT.md).
--
-- Guarded and idempotent: a no-op where the function does not exist.
-- Does NOT touch the event trigger, the function body, RLS or any table.
-- =============================================================================

begin;

do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public;
    revoke execute on function public.rls_auto_enable() from anon;
    revoke execute on function public.rls_auto_enable() from authenticated;
    revoke execute on function public.rls_auto_enable() from service_role;
  else
    raise notice 'public.rls_auto_enable() not present; nothing to revoke';
  end if;
end
$$;

commit;
