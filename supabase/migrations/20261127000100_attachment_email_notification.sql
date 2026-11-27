-- Email notification for a file sent alone in the ticket chat.
--
-- A chat message with text already queues a 'comment_added' notification
-- (comments_after_insert) and the sender attaches the files uploaded with it.
-- A file sent WITHOUT text creates no comment row, so nothing was emailed.
-- The `attachments` Edge Function (service role) now calls this function
-- after such an upload; it queues a 'comment_added' row whose payload names
-- the attachment instead of a comment. No new event type, no schema change
-- to notification_outbox, notifications_enabled is still respected.
begin;

create or replace function public.enqueue_attachment_notification(
  p_ticket_id     uuid,
  p_actor_id      uuid,
  p_attachment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.ticket_attachments a
     where a.id = p_attachment_id and a.ticket_id = p_ticket_id
  ) then
    raise exception 'attachment not found' using errcode = 'P0002';
  end if;
  perform private.enqueue_notification(p_ticket_id, 'comment_added',
    jsonb_build_object('actor_id', p_actor_id,
                       'attachment_ids', jsonb_build_array(p_attachment_id)));
end;
$$;

revoke all on function public.enqueue_attachment_notification(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.enqueue_attachment_notification(uuid, uuid, uuid) to service_role;

commit;
