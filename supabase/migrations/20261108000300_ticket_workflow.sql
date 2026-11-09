-- =============================================================================
-- ITSR Radiant Group Duri — Migration 0300: Ticket workflow
--   * server-generated ticket numbers (sequence; no client-side counting)
--   * server-owned fields on insert
--   * guarded updates + validated status transitions
--   * activity log + notification outbox written by triggers only
--   * RPCs: ticket_stats, reporter_ticket_action, assignable_staff
-- All trigger/definer functions: SET search_path = '' and fully-qualified names.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- updated_at helper
-- ---------------------------------------------------------------------------
create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch   before update on public.profiles
  for each row execute function private.touch_updated_at();
create trigger categories_touch before update on public.categories
  for each row execute function private.touch_updated_at();
create trigger app_settings_touch before update on public.app_settings
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Allowed status transitions (pure function; also used by tests)
-- ---------------------------------------------------------------------------
create or replace function private.is_valid_transition(p_old text, p_new text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_old = p_new or (p_old, p_new) in (
    ('open',         'assigned'),
    ('open',         'in_progress'),
    ('open',         'closed'),
    ('assigned',     'in_progress'),
    ('assigned',     'pending_user'),
    ('assigned',     'resolved'),
    ('assigned',     'open'),
    ('in_progress',  'pending_user'),
    ('in_progress',  'resolved'),
    ('in_progress',  'assigned'),
    ('pending_user', 'in_progress'),
    ('pending_user', 'resolved'),
    ('resolved',     'closed'),
    ('resolved',     'reopened'),
    ('closed',       'reopened'),
    ('reopened',     'assigned'),
    ('reopened',     'in_progress'),
    ('reopened',     'resolved')
  )
$$;

-- ---------------------------------------------------------------------------
-- BEFORE INSERT: server owns number/status/assignment/timestamps
-- ---------------------------------------------------------------------------
create or replace function private.tickets_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- An end-user session can only file tickets for itself (RLS also enforces this)
  if auth.uid() is not null then
    new.reporter_id := auth.uid();
  end if;

  if not exists (select 1 from public.categories c where c.name = new.category and c.is_active) then
    raise exception 'Unknown or inactive category: %', new.category using errcode = '22023';
  end if;

  new.ticket_number  := 'ITSR-' || lpad(nextval('public.ticket_number_seq')::text, 5, '0');
  new.status         := 'open';
  new.assigned_to_id := null;
  new.resolution     := null;
  new.resolved_at    := null;
  new.closed_at      := null;
  new.created_at     := now();
  new.updated_at     := now();
  new.subject        := btrim(new.subject);
  new.description    := btrim(new.description);
  return new;
end;
$$;

create trigger tickets_before_insert before insert on public.tickets
  for each row execute function private.tickets_before_insert();

-- ---------------------------------------------------------------------------
-- BEFORE UPDATE: immutability, assignee validation, transitions, timestamps
-- ---------------------------------------------------------------------------
create or replace function private.tickets_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reporter_action boolean := coalesce(current_setting('app.reporter_action', true), '') = 'on';
begin
  if new.id <> old.id or new.ticket_number <> old.ticket_number
     or new.reporter_id <> old.reporter_id or new.created_at <> old.created_at then
    raise exception 'Immutable ticket fields cannot be changed' using errcode = '42501';
  end if;

  -- Only staff (or the reporter_ticket_action RPC, or service role with no JWT)
  -- may change a ticket.
  if auth.uid() is not null and not private.is_staff() and not v_reporter_action then
    raise exception 'Not authorized to modify this ticket' using errcode = '42501';
  end if;

  if new.assigned_to_id is distinct from old.assigned_to_id and new.assigned_to_id is not null then
    if not exists (
      select 1 from public.profiles p
      where p.id = new.assigned_to_id and p.is_active
        and p.role in ('it_support', 'administrator')
    ) then
      raise exception 'Tickets can only be assigned to active IT Support / Administrator users'
        using errcode = '22023';
    end if;
    -- Assigning an unworked ticket moves it to "assigned"
    if new.status = old.status and old.status in ('open', 'reopened') then
      new.status := 'assigned';
    end if;
  end if;

  if new.category is distinct from old.category
     and not exists (select 1 from public.categories c where c.name = new.category and c.is_active) then
    raise exception 'Unknown or inactive category: %', new.category using errcode = '22023';
  end if;

  if not private.is_valid_transition(old.status, new.status) then
    raise exception 'Invalid status transition: % -> %', old.status, new.status
      using errcode = '22023';
  end if;

  -- Working a ticket requires an owner: auto-assign to the acting staff member
  if new.status in ('in_progress', 'pending_user', 'resolved') and new.assigned_to_id is null then
    if auth.uid() is not null and private.is_staff() then
      new.assigned_to_id := auth.uid();
    end if;
  end if;

  if new.status = 'resolved' and old.status <> 'resolved' then
    if length(btrim(coalesce(new.resolution, ''))) = 0 then
      raise exception 'A resolution description is required to resolve a ticket'
        using errcode = '23514';
    end if;
    new.resolved_at := now();
  end if;

  if new.status = 'closed' and old.status <> 'closed' then
    new.closed_at := now();
    if new.resolved_at is null then new.resolved_at := now(); end if;
  end if;

  if new.status = 'reopened' then
    new.resolved_at := null;
    new.closed_at   := null;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger tickets_before_update before update on public.tickets
  for each row execute function private.tickets_before_update();

-- ---------------------------------------------------------------------------
-- Outbox helper
-- ---------------------------------------------------------------------------
create or replace function private.enqueue_notification(p_ticket uuid, p_event text, p_payload jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce((select s.notifications_enabled from public.app_settings s where s.id), true) then
    insert into public.notification_outbox (ticket_id, event_type, payload)
    values (p_ticket, p_event, coalesce(p_payload, '{}'::jsonb));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- AFTER INSERT / UPDATE on tickets: activity + notifications
-- ---------------------------------------------------------------------------
create or replace function private.tickets_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.ticket_activity_log (ticket_id, actor_id, action, new_value)
  values (new.id, auth.uid(), 'created', new.status);

  perform private.enqueue_notification(new.id, 'ticket_created',
    jsonb_build_object('actor_id', auth.uid()));
  return null;
end;
$$;

create trigger tickets_after_insert after insert on public.tickets
  for each row execute function private.tickets_after_insert();

create or replace function private.tickets_after_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_note   text := nullif(current_setting('app.activity_note', true), '');
  v_action text;
begin
  if new.assigned_to_id is distinct from old.assigned_to_id then
    insert into public.ticket_activity_log (ticket_id, actor_id, action, old_value, new_value)
    values (new.id, auth.uid(), 'assigned', old.assigned_to_id::text, new.assigned_to_id::text);
    if new.assigned_to_id is not null then
      perform private.enqueue_notification(new.id, 'ticket_assigned',
        jsonb_build_object('actor_id', auth.uid(), 'assignee_id', new.assigned_to_id));
    end if;
  end if;

  if new.status is distinct from old.status then
    v_action := case new.status
                  when 'resolved' then 'resolved'
                  when 'reopened' then 'reopened'
                  when 'closed'   then 'closed'
                  else 'status_changed'
                end;
    insert into public.ticket_activity_log (ticket_id, actor_id, action, old_value, new_value, note)
    values (new.id, auth.uid(), v_action, old.status, new.status,
            case when new.status = 'resolved' then new.resolution else v_note end);
    perform private.enqueue_notification(new.id, 'status_changed',
      jsonb_build_object('actor_id', auth.uid(), 'old_status', old.status,
                         'new_status', new.status));
  end if;

  if new.priority is distinct from old.priority then
    insert into public.ticket_activity_log (ticket_id, actor_id, action, old_value, new_value)
    values (new.id, auth.uid(), 'priority_changed', old.priority, new.priority);
  end if;

  if new.category is distinct from old.category then
    insert into public.ticket_activity_log (ticket_id, actor_id, action, old_value, new_value)
    values (new.id, auth.uid(), 'category_changed', old.category, new.category);
  end if;

  return null;
end;
$$;

create trigger tickets_after_update after update on public.tickets
  for each row execute function private.tickets_after_update();

-- ---------------------------------------------------------------------------
-- Comments: server timestamps + notification for non-internal comments
-- ---------------------------------------------------------------------------
create or replace function private.comments_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    new.author_id := auth.uid();
  end if;
  new.content    := btrim(new.content);
  new.created_at := now();
  return new;
end;
$$;

create trigger comments_before_insert before insert on public.ticket_comments
  for each row execute function private.comments_before_insert();

create or replace function private.comments_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not new.is_internal then
    perform private.enqueue_notification(new.ticket_id, 'comment_added',
      jsonb_build_object('actor_id', new.author_id, 'comment_id', new.id));
  end if;
  return null;
end;
$$;

create trigger comments_after_insert after insert on public.ticket_comments
  for each row execute function private.comments_after_insert();

-- ---------------------------------------------------------------------------
-- RPC: dashboard statistics (SECURITY INVOKER => RLS applies)
-- p_scope: 'mine' (tickets I reported), 'assigned' (assigned to me), 'all'
-- ---------------------------------------------------------------------------
create or replace function public.ticket_stats(p_scope text default 'mine')
returns table (
  total        bigint,
  open         bigint,
  in_progress  bigint,
  resolved     bigint,
  closed       bigint,
  unassigned   bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    count(*),
    count(*) filter (where t.status in ('open', 'assigned', 'reopened')),
    count(*) filter (where t.status in ('in_progress', 'pending_user')),
    count(*) filter (where t.status = 'resolved'),
    count(*) filter (where t.status = 'closed'),
    count(*) filter (where t.assigned_to_id is null and t.status not in ('resolved', 'closed'))
  from public.tickets t
  where case p_scope
          when 'mine'     then t.reporter_id = auth.uid()
          when 'assigned' then t.assigned_to_id = auth.uid()
          else true
        end
$$;

-- ---------------------------------------------------------------------------
-- RPC: reporter actions on their own ticket (reopen / confirm-close)
-- ---------------------------------------------------------------------------
create or replace function public.reporter_ticket_action(
  p_ticket_id uuid,
  p_action    text,
  p_note      text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ticket public.tickets%rowtype;
begin
  if auth.uid() is null or not private.is_active_user() then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_ticket from public.tickets where id = p_ticket_id for update;
  if not found or v_ticket.reporter_id <> auth.uid() then
    raise exception 'Ticket not found' using errcode = 'P0002';
  end if;

  perform set_config('app.reporter_action', 'on', true);
  perform set_config('app.activity_note', coalesce(left(btrim(p_note), 1000), ''), true);

  if p_action = 'reopen' then
    if v_ticket.status not in ('resolved', 'closed') then
      raise exception 'Only resolved or closed tickets can be reopened' using errcode = '22023';
    end if;
    if length(btrim(coalesce(p_note, ''))) = 0 then
      raise exception 'Please explain why the ticket is being reopened' using errcode = '22023';
    end if;
    update public.tickets set status = 'reopened' where id = p_ticket_id;
  elsif p_action = 'close' then
    if v_ticket.status <> 'resolved' then
      raise exception 'Only resolved tickets can be closed by the reporter' using errcode = '22023';
    end if;
    update public.tickets set status = 'closed' where id = p_ticket_id;
  else
    raise exception 'Unknown action: %', p_action using errcode = '22023';
  end if;

  perform set_config('app.reporter_action', '', true);
  perform set_config('app.activity_note', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: staff list for the assignment picker (staff only)
-- ---------------------------------------------------------------------------
create or replace function public.assignable_staff()
returns table (id uuid, full_name text, employee_number text, role text)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.full_name, p.employee_number, p.role
  from public.profiles p
  where private.is_staff()
    and p.is_active
    and p.role in ('it_support', 'administrator')
  order by p.full_name
$$;

-- ---------------------------------------------------------------------------
-- Privileges for everything defined above (Gate 3: explicit, least privilege)
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.current_app_role() to authenticated, service_role;
grant execute on function private.is_staff()         to authenticated, service_role;
grant execute on function private.is_admin()         to authenticated, service_role;
grant execute on function private.is_active_user()   to authenticated, service_role;

revoke all on function public.ticket_stats(text)                       from public, anon, authenticated;
revoke all on function public.reporter_ticket_action(uuid, text, text) from public, anon, authenticated;
revoke all on function public.assignable_staff()                       from public, anon, authenticated;
grant execute on function public.ticket_stats(text)                       to authenticated, service_role;
grant execute on function public.reporter_ticket_action(uuid, text, text) to authenticated, service_role;
grant execute on function public.assignable_staff()                       to authenticated, service_role;

commit;
