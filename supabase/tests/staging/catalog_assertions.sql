-- =============================================================================
-- ITSR — READ-ONLY catalog assertions (privilege / RLS drift check)
--
-- * Pure SELECT: no writes, no temp objects, safe on a database WITH data
--   (unlike staging_security_tests.sql, which needs an empty database).
-- * Run after every migration or platform upgrade, e.g. via the Management API
--   /database/query endpoint or `psql -f`.
-- * Why: Supabase's supabase_admin default ACL on schema public still grants
--   EXECUTE (functions) and full table rights to anon/authenticated for objects
--   created BY supabase_admin (platform). Project roles cannot change that
--   default, so drift must be detected instead (Gate 3 root cause).
-- Output: one row per check (id, passed, detail); expect every passed = true.
-- =============================================================================
with
app_tables as (
  select c.oid, c.relname, c.relrowsecurity
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p')
),
fns as (
  select p.oid, p.oid::regprocedure::text as sig, n.nspname, p.prosecdef, p.proconfig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
),
checks(id, passed, detail) as (
  select 'C01 every public table has RLS enabled',
         bool_and(relrowsecurity),
         coalesce(string_agg(relname, ',') filter (where not relrowsecurity), 'all on')
  from app_tables
union all
  select 'C02 exactly the 8 application tables exist in public',
         count(*) = 8 and bool_and(relname in ('profiles','categories','tickets','ticket_comments',
            'ticket_activity_log','app_settings','notification_outbox','login_attempts')),
         string_agg(relname, ',' order by relname)
  from app_tables
union all
  select 'C03 12 RLS policies (no drift)', count(*) = 12, count(*)::text
  from pg_policies where schemaname = 'public'
union all
  select 'C04 anon has no table privileges in public', count(*) = 0, count(*)::text
  from information_schema.role_table_grants
  where grantee = 'anon' and table_schema = 'public'
union all
  select 'C05 anon can execute no public/private function',
         count(*) = 0, coalesce(string_agg(sig, ','), 'none')
  from fns where has_function_privilege('anon', oid, 'EXECUTE')
union all
  select 'C06 authenticated executes exactly 3 public RPCs',
         coalesce(array_agg(sig order by sig), '{}') =
           array['assignable_staff()', 'reporter_ticket_action(uuid,text,text)', 'ticket_stats(text)'],
         coalesce(string_agg(sig, ',' order by sig), 'none')
  from fns where nspname = 'public' and has_function_privilege('authenticated', oid, 'EXECUTE')
union all
  select 'C07 service-only RPCs not executable by authenticated',
         count(*) = 0, coalesce(string_agg(sig, ','), 'none')
  from fns
  where sig in ('login_is_rate_limited(text,text,integer,integer,integer)',
                'record_login_attempt(text,text,uuid,boolean)',
                'claim_notifications(integer)',
                'complete_notification(uuid,text,text,text[],text[])')
    and has_function_privilege('authenticated', oid, 'EXECUTE')
union all
  select 'C08 every SECURITY DEFINER function pins search_path',
         count(*) = 0, coalesce(string_agg(sig, ','), 'none')
  from fns
  where prosecdef
    and not exists (select 1 from unnest(coalesce(proconfig, '{}')) c where c like 'search_path=%')
union all
  select 'C09 authenticated has no access to notification_outbox / login_attempts',
         not (has_table_privilege('authenticated', 'public.notification_outbox', 'SELECT,INSERT,UPDATE,DELETE')
           or has_table_privilege('authenticated', 'public.login_attempts', 'SELECT,INSERT,UPDATE,DELETE')),
         'checked SELECT/INSERT/UPDATE/DELETE'
union all
  select 'C10 clients cannot write profiles or delete audit records',
         not (has_table_privilege('authenticated', 'public.profiles', 'INSERT,UPDATE,DELETE')
           or has_table_privilege('authenticated', 'public.tickets', 'DELETE')
           or has_table_privilege('authenticated', 'public.ticket_activity_log', 'INSERT,UPDATE,DELETE')
           or has_table_privilege('authenticated', 'public.ticket_comments', 'UPDATE,DELETE')),
         'profiles I/U/D, tickets D, activity I/U/D, comments U/D'
union all
  select 'C11 server-owned ticket columns not client-insertable',
         not (has_column_privilege('authenticated', 'public.tickets', 'ticket_number', 'INSERT')
           or has_column_privilege('authenticated', 'public.tickets', 'status', 'INSERT')
           or has_column_privilege('authenticated', 'public.tickets', 'assigned_to_id', 'INSERT')
           or has_column_privilege('authenticated', 'public.tickets', 'reporter_id', 'UPDATE')
           or has_column_privilege('authenticated', 'public.tickets', 'ticket_number', 'UPDATE')),
         'ticket_number/status/assigned_to_id insert; reporter_id/ticket_number update'
union all
  select 'C12 anon has no USAGE on schema private',
         not has_schema_privilege('anon', 'private', 'USAGE'), ''
union all
  select 'C13 platform rls_auto_enable() not client-executable',
         to_regprocedure('public.rls_auto_enable()') is null
           or not (has_function_privilege('anon', 'public.rls_auto_enable()', 'EXECUTE')
                or has_function_privilege('authenticated', 'public.rls_auto_enable()', 'EXECUTE')),
         case when to_regprocedure('public.rls_auto_enable()') is null then 'absent' else 'present' end
union all
  -- Native Supabase auth: auth.uid() belongs to the auth service, never to the
  -- migration role. (Skipped on a local throwaway cluster, where the
  -- LOCAL-TEST-ONLY shim owns it.)
  select 'C14 auth.uid() is Supabase-native (not overridden)',
         case when not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then true
              else (select pg_get_userbyid(p.proowner) = 'supabase_auth_admin'
                    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'auth' and p.proname = 'uid' limit 1) end,
         coalesce((select pg_get_userbyid(p.proowner) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'auth' and p.proname = 'uid' limit 1), 'missing')
         || case when not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin')
                 then ' (local cluster: n/a)' else '' end
union all
  select 'C15 claim_notifications has retry cap (migration 0600)',
         (select pg_get_functiondef(oid) like '%x.attempts < 5%and x.locked_at < now() - interval ''10 minutes''%'
          from fns where sig = 'claim_notifications(integer)'),
         ''
)
select id, passed, detail from checks order by id;
