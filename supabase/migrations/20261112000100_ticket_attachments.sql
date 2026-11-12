-- Ticket attachments stored in Google Drive.
--
-- The file bytes live in a Google Drive folder; this table only records the
-- metadata and the Drive file id. Rows are written ONLY by the `attachments`
-- Edge Function (service role), after it has checked that the caller may see
-- the ticket. Clients can read the rows of tickets they can see (same rule as
-- comments / activity) and download through the Edge Function, so the Drive
-- folder itself never has to be shared with employees.
begin;

create table if not exists public.ticket_attachments (
  id             uuid primary key default gen_random_uuid(),
  ticket_id      uuid not null references public.tickets(id) on delete cascade,
  uploaded_by    uuid references public.profiles(id) on delete set null,
  file_name      text not null check (char_length(file_name) between 1 and 255),
  mime_type      text not null check (mime_type in ('image/jpeg', 'image/png', 'application/pdf')),
  size_bytes     integer not null check (size_bytes > 0 and size_bytes <= 10485760),
  drive_file_id  text not null unique check (char_length(drive_file_id) between 1 and 200),
  created_at     timestamptz not null default now()
);

create index if not exists ticket_attachments_ticket_idx
  on public.ticket_attachments (ticket_id, created_at);

alter table public.ticket_attachments enable row level security;

revoke all on public.ticket_attachments from anon, authenticated;
grant select on public.ticket_attachments to authenticated;
grant all on public.ticket_attachments to service_role;

drop policy if exists attachments_select on public.ticket_attachments;
create policy attachments_select on public.ticket_attachments
  for select to authenticated
  using (
    (select private.is_staff())
    or exists (
      select 1 from public.tickets t
      where t.id = ticket_id and t.reporter_id = (select auth.uid())
    )
  );
-- No INSERT / UPDATE / DELETE policy for clients: writes go through the
-- `attachments` Edge Function with the service role.

commit;
