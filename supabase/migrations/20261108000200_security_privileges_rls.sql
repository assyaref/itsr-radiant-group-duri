-- =============================================================================
-- ITSR Radiant Group Duri — Migration 0200: Privileges, role helpers, RLS
--
-- Resolves the Phase 15.3 Gate 3 finding:
--   Supabase (and legacy 0001) set DEFAULT PRIVILEGES that grant EXECUTE on every
--   new function in `public` to anon + authenticated. `REVOKE ... FROM PUBLIC`
--   does NOT remove those role-specific grants. This migration:
--     (a) revokes EXECUTE from PUBLIC, anon AND authenticated explicitly,
--     (b) changes the default privileges so future functions are not auto-exposed,
--     (c) re-grants only what each role needs.
-- Resolves the legacy 0021 recursion problem: role checks run in SECURITY DEFINER
-- helpers in the non-exposed `private` schema, so profile policies never
-- sub-select `profiles` under RLS.
-- Never overrides auth.uid().
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Default privileges: stop auto-granting to anon/authenticated
--    (applies to objects subsequently created by the migration-running role)
-- ---------------------------------------------------------------------------
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Table privileges: anon gets NOTHING. authenticated gets only the verbs and
--    columns it needs; RLS then restricts rows.
-- ---------------------------------------------------------------------------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant select on public.profiles, public.categories, public.tickets,
                public.ticket_comments, public.ticket_activity_log,
                public.app_settings
  to authenticated;

-- tickets: insert only user-supplied columns; server owns everything else
grant insert (subject, description, category, subcategory, priority, reporter_id)
  on public.tickets to authenticated;
-- tickets: staff-editable workflow columns (RLS limits UPDATE to staff)
grant update (status, priority, category, subcategory, assigned_to_id, resolution)
  on public.tickets to authenticated;

grant insert (ticket_id, author_id, content, is_internal)
  on public.ticket_comments to authenticated;

grant insert (name, description, is_active, sort_order) on public.categories to authenticated;
grant update (name, description, is_active, sort_order) on public.categories to authenticated;

grant update (it_support_group_email, manager_email, notifications_enabled, app_base_url)
  on public.app_settings to authenticated;

-- No client grants at all on: notification_outbox, login_attempts.
-- No client INSERT/UPDATE/DELETE on profiles: managed by the admin-users Edge
-- Function (service role) after it verifies the caller is an active administrator.

grant all on all tables    in schema public to service_role;
grant all on all sequences in schema public to service_role;

-- ---------------------------------------------------------------------------
-- 3. Role helpers in a schema PostgREST does not expose
-- ---------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

create or replace function private.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
    and p.is_active
$$;

create or replace function private.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() in ('it_support', 'administrator'), false)
$$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() = 'administrator', false)
$$;

create or replace function private.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_app_role() is not null
$$;

revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.current_app_role() to authenticated, service_role;
grant execute on function private.is_staff()         to authenticated, service_role;
grant execute on function private.is_admin()         to authenticated, service_role;
grant execute on function private.is_active_user()   to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. RLS policies (all scoped `to authenticated`; anon has no policy => no rows)
-- ---------------------------------------------------------------------------

-- profiles: own row; staff see everyone; everyone may see staff rows
-- (needed to display the assigned technician's name on their own tickets).
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (select private.is_staff())
    or (role in ('it_support', 'administrator') and (select private.is_active_user()))
  );

-- categories: any active user reads; admins manage
create policy categories_select on public.categories
  for select to authenticated
  using ((select private.is_active_user()));
create policy categories_insert on public.categories
  for insert to authenticated
  with check ((select private.is_admin()));
create policy categories_update on public.categories
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- tickets
create policy tickets_select on public.tickets
  for select to authenticated
  using (
    ((select private.is_active_user()) and reporter_id = (select auth.uid()))
    or (select private.is_staff())
  );
create policy tickets_insert on public.tickets
  for insert to authenticated
  with check (
    (select private.is_active_user())
    and reporter_id = (select auth.uid())
  );
create policy tickets_update_staff on public.tickets
  for update to authenticated
  using ((select private.is_staff()))
  with check ((select private.is_staff()));
-- No DELETE policy: tickets are an audit record.

-- comments
create policy comments_select on public.ticket_comments
  for select to authenticated
  using (
    (select private.is_staff())
    or (
      not is_internal
      and exists (
        select 1 from public.tickets t
        where t.id = ticket_id and t.reporter_id = (select auth.uid())
      )
    )
  );
create policy comments_insert on public.ticket_comments
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and (
      (select private.is_staff())
      or (
        not is_internal
        and (select private.is_active_user())
        and exists (
          select 1 from public.tickets t
          where t.id = ticket_id and t.reporter_id = (select auth.uid())
        )
      )
    )
  );

-- activity log: read-only for clients (rows are written by triggers)
create policy activity_select on public.ticket_activity_log
  for select to authenticated
  using (
    (select private.is_staff())
    or exists (
      select 1 from public.tickets t
      where t.id = ticket_id and t.reporter_id = (select auth.uid())
    )
  );

-- app settings: administrators only
create policy app_settings_select on public.app_settings
  for select to authenticated
  using ((select private.is_admin()));
create policy app_settings_update on public.app_settings
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- notification_outbox, login_attempts: RLS enabled, NO policies, NO grants
-- => inaccessible to anon/authenticated; service_role bypasses RLS.

commit;
