-- =============================================================================
-- ITSR Radiant Group Duri — Migration 0700: outbox quarantine + permanent failures
--
-- Phase 17 findings:
--   1. There is no way to hold back outbox rows without deleting them. Before
--      Gmail credentials are configured, the existing backlog (synthetic
--      staging data) would be sent the moment any user action "kicks" the
--      sender. -> new status 'held': never claimed, never deleted, can be
--      released later with  update ... set status = 'pending' where ...
--   2. Every failure was retried up to 5 times, including failures that can
--      never succeed (recipient rejected with SMTP 5xx, ticket deleted).
--      -> new column permanent_failure + service-only RPC
--         fail_notification_permanently(); such rows are never re-claimed.
--
-- claim_notifications() keeps the 0600 attempt cap (attempts < 5) and its
-- signature, SECURITY DEFINER, search_path and service_role-only privilege.
-- No RLS/policy change; notification_outbox stays service-only.
--
-- Rollback: release held rows (set status = 'pending'), then re-run the
-- claim_notifications() definition from 20261109000600, drop function
-- fail_notification_permanently(uuid, text), drop column permanent_failure,
-- and restore the original status check constraint.
-- =============================================================================

begin;

alter table public.notification_outbox
  drop constraint if exists notification_outbox_status_check;
alter table public.notification_outbox
  add constraint notification_outbox_status_check
  check (status in ('pending', 'processing', 'sent', 'failed', 'skipped', 'held'));

alter table public.notification_outbox
  add column if not exists permanent_failure boolean not null default false;

create or replace function public.claim_notifications(p_limit integer default 20)
returns setof public.notification_outbox
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Give up on rows that crashed the sender 5 times; keep them for inspection.
  update public.notification_outbox o
     set status = 'failed',
         last_error = left(coalesce(o.last_error || ' | ', '') ||
                           'abandoned: still processing after ' || o.attempts || ' attempts', 2000)
   where o.status = 'processing'
     and o.locked_at < now() - interval '10 minutes'
     and o.attempts >= 5;

  -- 'held', 'sent', 'skipped' and permanently failed rows are never claimed.
  return query
  update public.notification_outbox o
     set status = 'processing', locked_at = now(), attempts = o.attempts + 1
   where o.id in (
     select x.id from public.notification_outbox x
      where (x.status = 'pending'
             or (x.status = 'processing' and x.attempts < 5
                 and x.locked_at < now() - interval '10 minutes')
             or (x.status = 'failed' and x.attempts < 5 and not x.permanent_failure
                 and x.locked_at < now() - interval '5 minutes'))
      order by x.created_at
      limit greatest(1, least(p_limit, 100))
      for update skip locked
   )
  returning o.*;
end;
$$;

create or replace function public.fail_notification_permanently(p_id uuid, p_error text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.notification_outbox
     set status = 'failed',
         permanent_failure = true,
         last_error = left('permanent: ' || coalesce(p_error, 'unknown error'), 2000)
   where id = p_id;
end;
$$;

revoke all on function public.claim_notifications(integer) from public, anon, authenticated;
revoke all on function public.fail_notification_permanently(uuid, text) from public, anon, authenticated;
grant execute on function public.claim_notifications(integer) to service_role;
grant execute on function public.fail_notification_permanently(uuid, text) to service_role;

commit;
