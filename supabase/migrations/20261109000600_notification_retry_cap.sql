-- =============================================================================
-- ITSR Radiant Group Duri — Migration 0600: cap notification retries
--
-- Finding (2026-11-09 audit): claim_notifications() (0400) re-claims rows stuck
-- in 'processing' (locked > 10 min, e.g. the Edge Function was killed mid-batch)
-- with NO attempts limit. A row that reliably crashes or times out the sender
-- would therefore be retried forever, every 10 minutes — and could re-send the
-- same email each time the SMTP send succeeded but the completion call did not.
--
-- Change:
--   * stale 'processing' rows are re-claimed only while attempts < 5
--     (the same cap already applied to 'failed' rows);
--   * stale 'processing' rows that have used all 5 attempts are moved to
--     'failed' with an explanatory last_error, so they are visible to admins
--     instead of silently stuck.
-- Signature, return type, SECURITY DEFINER, search_path and privileges are
-- unchanged (service_role only). No table, RLS or policy change.
--
-- Rollback: re-run the claim_notifications() definition from
--   20261108000400_login_and_notifications.sql (create or replace).
-- =============================================================================

begin;

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

  return query
  update public.notification_outbox o
     set status = 'processing', locked_at = now(), attempts = o.attempts + 1
   where o.id in (
     select x.id from public.notification_outbox x
      where (x.status = 'pending'
             or (x.status = 'processing' and x.attempts < 5
                 and x.locked_at < now() - interval '10 minutes')
             or (x.status = 'failed' and x.attempts < 5
                 and x.locked_at < now() - interval '5 minutes'))
      order by x.created_at
      limit greatest(1, least(p_limit, 100))
      for update skip locked
   )
  returning o.*;
end;
$$;

-- Re-assert least privilege explicitly (create or replace keeps the ACL, but
-- this migration must not depend on that).
revoke all on function public.claim_notifications(integer) from public, anon, authenticated;
grant execute on function public.claim_notifications(integer) to service_role;

commit;
