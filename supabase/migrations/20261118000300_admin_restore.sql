-- =============================================================================
-- ITSR Radiant Group Duri — Restore from an `admin_backup()` JSON document
--
-- public.admin_restore(p_backup jsonb, p_mode text, p_confirm text)
--   administrator + superadmin; p_confirm must be 'RESTORE DATA'.
--   p_mode 'merge'   : insert rows that do not exist yet (by id); keep the rest.
--   p_mode 'replace' : delete ALL current ticket data first, then restore.
--
-- Restored: categories, tickets, ticket_comments, ticket_activity_log,
--           ticket_attachments (metadata; files stay in Google Drive).
-- NOT restored: profiles / auth accounts (passwords are not in a backup) and
--           app_settings. Rows whose reporter / author no longer exists are
--           skipped and counted.
-- Workflow triggers are disabled for the duration of the restore so ticket
-- numbers, statuses and timestamps are kept exactly and NO notification
-- emails are queued. Ticket-number counters are moved past restored numbers.
-- Runs in one transaction: any error rolls everything back.
-- =============================================================================

begin;

alter table private.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table private.admin_audit_log add constraint admin_audit_log_action_check
  check (action in ('ticket_deleted', 'tickets_purged', 'backup_exported', 'database_restored'));

create or replace function public.admin_restore(p_backup jsonb, p_mode text, p_confirm text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  t            jsonb := p_backup -> 'tables';
  v_categories integer := 0;
  v_tickets    integer := 0;
  v_comments   integer := 0;
  v_activity   integer := 0;
  v_attach     integer := 0;
  v_skipped    integer := 0;
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_confirm is distinct from 'RESTORE DATA' then
    raise exception 'Confirmation phrase does not match' using errcode = '22023';
  end if;
  if p_mode not in ('merge', 'replace') then
    raise exception 'Mode must be merge or replace' using errcode = '22023';
  end if;
  if p_backup ->> 'format' is distinct from 'itsr-backup' or jsonb_typeof(t) is distinct from 'object' then
    raise exception 'This is not an ITSR backup file' using errcode = '22023';
  end if;

  -- Keep stored values verbatim and do not queue emails while restoring.
  alter table public.tickets         disable trigger user;
  alter table public.ticket_comments disable trigger user;
  alter table public.categories      disable trigger user;

  if p_mode = 'replace' then
    delete from public.notification_outbox where true;
    delete from public.tickets where true;   -- children cascade
  end if;

  -- Categories (tickets reference them by name)
  insert into public.categories
  select r.* from jsonb_populate_recordset(null::public.categories, coalesce(t -> 'categories', '[]')) r
  where not exists (select 1 from public.categories c where c.id = r.id or c.name = r.name);
  get diagnostics v_categories = row_count;

  -- Tickets: reporter must exist; unknown assignee -> unassigned;
  -- unknown category -> 'Other' if present.
  -- Skipped = tickets whose reporter account no longer exists.
  select count(*) into v_skipped
  from jsonb_populate_recordset(null::public.tickets, coalesce(t -> 'tickets', '[]')) r
  where not exists (select 1 from public.profiles p where p.id = r.reporter_id);
  insert into public.tickets
  select r.id, r.ticket_number, r.subject, r.description,
         case when exists (select 1 from public.categories c where c.name = r.category) then r.category
              else (select c.name from public.categories c order by (c.name = 'Other') desc, c.sort_order limit 1) end,
         r.subcategory, r.priority, r.status, r.reporter_id,
         case when exists (select 1 from public.profiles p where p.id = r.assigned_to_id) then r.assigned_to_id end,
         r.resolution, r.created_at, r.updated_at, r.resolved_at, r.closed_at
  from jsonb_populate_recordset(null::public.tickets, coalesce(t -> 'tickets', '[]')) r
  where exists (select 1 from public.profiles p where p.id = r.reporter_id)
    and not exists (select 1 from public.tickets x where x.id = r.id or x.ticket_number = r.ticket_number);
  get diagnostics v_tickets = row_count;

  insert into public.ticket_comments
  select r.* from jsonb_populate_recordset(null::public.ticket_comments, coalesce(t -> 'ticket_comments', '[]')) r
  where exists (select 1 from public.tickets x where x.id = r.ticket_id)
    and exists (select 1 from public.profiles p where p.id = r.author_id)
    and not exists (select 1 from public.ticket_comments x where x.id = r.id);
  get diagnostics v_comments = row_count;

  insert into public.ticket_activity_log
  select r.id, r.ticket_id,
         case when exists (select 1 from public.profiles p where p.id = r.actor_id) then r.actor_id end,
         r.action, r.old_value, r.new_value, r.note, r.created_at
  from jsonb_populate_recordset(null::public.ticket_activity_log, coalesce(t -> 'ticket_activity_log', '[]')) r
  where exists (select 1 from public.tickets x where x.id = r.ticket_id)
    and not exists (select 1 from public.ticket_activity_log x where x.id = r.id);
  get diagnostics v_activity = row_count;

  insert into public.ticket_attachments
  select r.id, r.ticket_id,
         case when exists (select 1 from public.profiles p where p.id = r.uploaded_by) then r.uploaded_by end,
         r.file_name, r.mime_type, r.size_bytes, r.drive_file_id, r.created_at
  from jsonb_populate_recordset(null::public.ticket_attachments, coalesce(t -> 'ticket_attachments', '[]')) r
  where exists (select 1 from public.tickets x where x.id = r.ticket_id)
    and not exists (select 1 from public.ticket_attachments x where x.id = r.id or x.drive_file_id = r.drive_file_id);
  get diagnostics v_attach = row_count;

  alter table public.tickets         enable trigger user;
  alter table public.ticket_comments enable trigger user;
  alter table public.categories      enable trigger user;

  -- New tickets must never reuse a restored number (ITSR-RGD-YYMM####).
  insert into private.ticket_number_counters as c (period, last_no)
  select substr(x.ticket_number, 10, 4), max(substr(x.ticket_number, 14)::integer)
  from public.tickets x
  where x.ticket_number ~ '^ITSR-RGD-[0-9]{4}[0-9]{4,}$'
  group by 1
  on conflict (period) do update set last_no = greatest(c.last_no, excluded.last_no);

  insert into private.admin_audit_log (actor_id, actor_role, action, details)
  values (auth.uid(), private.current_app_role(), 'database_restored',
          jsonb_build_object('mode', p_mode, 'backup_generated_at', p_backup -> 'generated_at',
                             'categories', v_categories, 'tickets', v_tickets, 'comments', v_comments,
                             'activity', v_activity, 'attachments', v_attach, 'skipped_tickets', v_skipped));

  return jsonb_build_object('mode', p_mode, 'categories', v_categories, 'tickets', v_tickets,
                            'comments', v_comments, 'activity', v_activity,
                            'attachments', v_attach, 'skipped_tickets', v_skipped);
end;
$$;

revoke all on function public.admin_restore(jsonb, text, text) from public, anon, authenticated;
grant execute on function public.admin_restore(jsonb, text, text) to authenticated, service_role;

commit;
