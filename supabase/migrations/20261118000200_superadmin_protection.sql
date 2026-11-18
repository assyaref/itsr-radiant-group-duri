-- =============================================================================
-- ITSR Radiant Group Duri — Superadmin protection
--
--   * A superadmin profile cannot be changed or deleted by ANYONE through the
--     app (admin, other superadmin, service-role Edge Functions). Nobody can
--     promote a profile to superadmin or create one through the app either.
--     Deliberate maintenance only: a DB owner runs
--       set local itsr.superadmin_maintenance = 'on';
--     in the same transaction.
--   * Superadmin accounts are invisible to everyone except superadmins
--     (users list, staff lists, name embeds, backups made by administrators).
-- The superadmin can still change their OWN password via the `account`
-- function (that only touches auth.users, not the profile).
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Lock superadmin profile rows
-- ---------------------------------------------------------------------------
create or replace function private.protect_superadmin_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('itsr.superadmin_maintenance', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op in ('UPDATE', 'DELETE') and old.role = 'superadmin' then
    raise exception 'Superadmin accounts cannot be modified' using errcode = '42501';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new.role = 'superadmin' then
    raise exception 'Superadmin accounts cannot be created or assigned' using errcode = '42501';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke all on function private.protect_superadmin_profile() from public, anon, authenticated;

drop trigger if exists profiles_protect_superadmin on public.profiles;
create trigger profiles_protect_superadmin
  before insert or update or delete on public.profiles
  for each row execute function private.protect_superadmin_profile();

-- ---------------------------------------------------------------------------
-- 2. Hide superadmin rows from everyone but superadmins
-- ---------------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (select private.is_superadmin())
    or (
      role <> 'superadmin'
      and (
        (select private.is_staff())
        or (role in ('it_support', 'administrator') and (select private.is_active_user()))
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 3. Backups made by an administrator do not contain superadmin profiles
-- ---------------------------------------------------------------------------
create or replace function public.admin_backup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_super  boolean := private.is_superadmin();
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'format',       'itsr-backup',
    'version',      1,
    'generated_at', now(),
    'generated_by', (select p.email from public.profiles p where p.id = auth.uid()),
    'tables', jsonb_build_object(
      'profiles',            coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.profiles x
                                       where v_super or x.role <> 'superadmin'), '[]'),
      'categories',          coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order, x.name) from public.categories x), '[]'),
      'tickets',             coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.tickets x), '[]'),
      'ticket_comments',     coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.ticket_comments x), '[]'),
      'ticket_activity_log', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.ticket_activity_log x), '[]'),
      'ticket_attachments',  coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.ticket_attachments x), '[]'),
      'app_settings',        coalesce((select jsonb_agg(to_jsonb(x)) from public.app_settings x), '[]')
    )
  ) into v_result;

  insert into private.admin_audit_log (actor_id, actor_role, action, details)
  values (auth.uid(), private.current_app_role(), 'backup_exported',
          jsonb_build_object('tickets', jsonb_array_length(v_result #> '{tables,tickets}')));

  return v_result;
end;
$$;
revoke all on function public.admin_backup() from public, anon, authenticated;
grant execute on function public.admin_backup() to authenticated, service_role;

commit;
