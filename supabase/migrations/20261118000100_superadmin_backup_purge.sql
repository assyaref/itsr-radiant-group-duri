-- =============================================================================
-- ITSR Radiant Group Duri — Superadmin role, ticket deletion, backup & purge
--
--   * New role `superadmin`: everything an administrator can do, plus it is the
--     ONLY role allowed to permanently delete a ticket (public.delete_ticket).
--   * public.admin_backup()        administrator + superadmin: full JSON export
--                                  of the application data (no secrets).
--   * public.admin_purge_tickets() administrator + superadmin: deletes ALL
--                                  ticket data (tickets, comments, activity,
--                                  attachment rows, outbox). Users, categories
--                                  and settings are kept so the app still works.
--   * private.admin_audit_log      who deleted / purged / backed up what, when.
--
-- Role checks stay in the non-exposed `private` schema (see migration 0200).
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Role constraint
-- ---------------------------------------------------------------------------
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('employee', 'it_support', 'administrator', 'superadmin'));

-- ---------------------------------------------------------------------------
-- 2. Role helpers: superadmin is a superset of administrator (and so staff)
-- ---------------------------------------------------------------------------
create or replace function private.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() in ('it_support', 'administrator', 'superadmin'), false)
$$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() in ('administrator', 'superadmin'), false)
$$;

create or replace function private.is_superadmin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() = 'superadmin', false)
$$;

revoke all on function private.is_superadmin() from public, anon, authenticated;
grant execute on function private.is_superadmin() to authenticated, service_role;

-- Everyone may see staff rows (assigned technician name); include superadmin.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (select private.is_staff())
    or (role in ('it_support', 'administrator', 'superadmin') and (select private.is_active_user()))
  );

-- ---------------------------------------------------------------------------
-- 3. Audit log (no client access at all)
-- ---------------------------------------------------------------------------
create table if not exists private.admin_audit_log (
  id         bigint generated always as identity primary key,
  actor_id   uuid,
  actor_role text,
  action     text not null check (action in ('ticket_deleted', 'tickets_purged', 'backup_exported')),
  details    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
revoke all on private.admin_audit_log from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Delete one ticket — SUPERADMIN ONLY
--    Comments, activity, attachment rows and outbox rows cascade.
--    Returns the Google Drive file ids that were attached so they can be
--    cleaned up from Drive if wanted (the DB only stores metadata).
-- ---------------------------------------------------------------------------
create or replace function public.delete_ticket(p_ticket_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_number text;
  v_files  text[];
begin
  if not private.is_superadmin() then
    raise exception 'Only a superadmin can delete tickets' using errcode = '42501';
  end if;

  select t.ticket_number into v_number from public.tickets t where t.id = p_ticket_id;
  if v_number is null then
    raise exception 'Ticket not found' using errcode = 'P0002';
  end if;

  select coalesce(array_agg(a.drive_file_id), '{}') into v_files
  from public.ticket_attachments a where a.ticket_id = p_ticket_id;

  delete from public.tickets t where t.id = p_ticket_id;

  insert into private.admin_audit_log (actor_id, actor_role, action, details)
  values (auth.uid(), private.current_app_role(), 'ticket_deleted',
          jsonb_build_object('ticket_id', p_ticket_id, 'ticket_number', v_number,
                             'drive_file_ids', to_jsonb(v_files)));

  return jsonb_build_object('ticket_number', v_number, 'drive_file_ids', to_jsonb(v_files));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Backup — administrator + superadmin
--    Exports application data as one JSON document. Contains NO secrets:
--    the SMTP password lives in Vault and auth passwords in auth.users.
-- ---------------------------------------------------------------------------
create or replace function public.admin_backup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
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
      'profiles',            coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.profiles x), '[]'),
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

-- ---------------------------------------------------------------------------
-- 6. Purge all ticket data — administrator + superadmin
--    Requires the exact confirmation phrase. Users, categories, settings and
--    the ticket-number counters are kept (numbers are never reused).
-- ---------------------------------------------------------------------------
create or replace function public.admin_purge_tickets(p_confirm text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tickets     integer;
  v_comments    integer;
  v_attachments integer;
  v_files       text[];
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_confirm is distinct from 'HAPUS SEMUA DATA' then
    raise exception 'Confirmation phrase does not match' using errcode = '22023';
  end if;

  select count(*) into v_tickets from public.tickets;
  select count(*) into v_comments from public.ticket_comments;
  select count(*), coalesce(array_agg(a.drive_file_id), '{}')
    into v_attachments, v_files from public.ticket_attachments a;

  -- Children cascade from tickets; explicit WHERE keeps pg-safeupdate happy.
  delete from public.notification_outbox where true;
  delete from public.tickets where true;

  insert into private.admin_audit_log (actor_id, actor_role, action, details)
  values (auth.uid(), private.current_app_role(), 'tickets_purged',
          jsonb_build_object('tickets', v_tickets, 'comments', v_comments,
                             'attachments', v_attachments, 'drive_file_ids', to_jsonb(v_files)));

  return jsonb_build_object('tickets', v_tickets, 'comments', v_comments,
                            'attachments', v_attachments, 'drive_file_ids', to_jsonb(v_files));
end;
$$;

revoke all on function public.delete_ticket(uuid)        from public, anon, authenticated;
revoke all on function public.admin_backup()             from public, anon, authenticated;
revoke all on function public.admin_purge_tickets(text)  from public, anon, authenticated;
grant execute on function public.delete_ticket(uuid)       to authenticated, service_role;
grant execute on function public.admin_backup()            to authenticated, service_role;
grant execute on function public.admin_purge_tickets(text) to authenticated, service_role;

commit;
