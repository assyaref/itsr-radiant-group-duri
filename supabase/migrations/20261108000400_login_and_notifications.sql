-- =============================================================================
-- ITSR Radiant Group Duri — Migration 0400: Login rate limiting + outbox RPCs
-- These functions are callable by service_role ONLY (Edge Functions).
-- They replace legacy check_rate_limit()/cleanup_old_login_attempts() from 0020,
-- which (a) were executable by anon/authenticated (Gate 3) and (b) counted every
-- attempt per IP, which would lock out a whole office behind one NAT address.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Rate limit: returns TRUE when the attempt must be BLOCKED.
-- Counts only FAILED attempts, per employee number and (looser) per IP.
-- ---------------------------------------------------------------------------
create or replace function public.login_is_rate_limited(
  p_ip_address       text,
  p_employee_number  text,
  p_max_per_account  integer default 5,
  p_max_per_ip       integer default 30,
  p_window_minutes   integer default 15
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_since timestamptz := now() - make_interval(mins => p_window_minutes);
  v_account_failures integer;
  v_ip_failures integer;
begin
  select count(*) into v_account_failures
  from public.login_attempts a
  where a.employee_number = p_employee_number
    and not a.success
    and a.created_at > v_since;

  select count(*) into v_ip_failures
  from public.login_attempts a
  where a.ip_address = p_ip_address
    and not a.success
    and a.created_at > v_since;

  return v_account_failures >= p_max_per_account or v_ip_failures >= p_max_per_ip;
end;
$$;

create or replace function public.record_login_attempt(
  p_ip_address      text,
  p_employee_number text,
  p_user_id         uuid,
  p_success         boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.login_attempts (ip_address, employee_number, user_id, success)
  values (left(coalesce(p_ip_address, 'unknown'), 100), left(p_employee_number, 40), p_user_id, p_success);

  -- A successful login clears that account's failure streak
  if p_success then
    delete from public.login_attempts
    where employee_number = p_employee_number and not success;
  end if;

  -- Retention: keep 30 days
  delete from public.login_attempts where created_at < now() - interval '30 days';
end;
$$;

-- ---------------------------------------------------------------------------
-- Outbox: claim a batch atomically (SKIP LOCKED => safe for concurrent runs)
-- ---------------------------------------------------------------------------
create or replace function public.claim_notifications(p_limit integer default 20)
returns setof public.notification_outbox
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.notification_outbox o
     set status = 'processing', locked_at = now(), attempts = o.attempts + 1
   where o.id in (
     select x.id from public.notification_outbox x
      where (x.status = 'pending'
             or (x.status = 'processing' and x.locked_at < now() - interval '10 minutes')
             or (x.status = 'failed' and x.attempts < 5
                 and x.locked_at < now() - interval '5 minutes'))
      order by x.created_at
      limit greatest(1, least(p_limit, 100))
      for update skip locked
   )
  returning o.*;
end;
$$;

create or replace function public.complete_notification(
  p_id         uuid,
  p_status     text,
  p_error      text default null,
  p_recipients text[] default null,
  p_cc         text[] default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_status not in ('sent', 'failed', 'skipped') then
    raise exception 'invalid status %', p_status;
  end if;
  update public.notification_outbox
     set status = p_status,
         last_error = left(p_error, 2000),
         recipients = coalesce(p_recipients, recipients),
         cc = coalesce(p_cc, cc),
         sent_at = case when p_status = 'sent' then now() else sent_at end
   where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- service_role ONLY. Explicit revoke from anon/authenticated (Gate 3 fix).
-- ---------------------------------------------------------------------------
revoke all on function public.login_is_rate_limited(text, text, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.record_login_attempt(text, text, uuid, boolean)            from public, anon, authenticated;
revoke all on function public.claim_notifications(integer)                               from public, anon, authenticated;
revoke all on function public.complete_notification(uuid, text, text, text[], text[])    from public, anon, authenticated;

grant execute on function public.login_is_rate_limited(text, text, integer, integer, integer) to service_role;
grant execute on function public.record_login_attempt(text, text, uuid, boolean)            to service_role;
grant execute on function public.claim_notifications(integer)                               to service_role;
grant execute on function public.complete_notification(uuid, text, text, text[], text[])    to service_role;

commit;
