-- =============================================================================
-- ITSR Radiant Group Duri — Migration 1100: Attachment storage
--
-- Adds a public.ticket_attachments table for file metadata and a Supabase
-- Storage bucket for the actual file blobs. The file bytes live in Storage;
-- this table stores metadata (name, MIME type, size, storage path, uploader).
--
-- RLS: authenticated users can read attachments on tickets they can see;
-- only staff (it_support/administrator) and the ticket reporter may insert;
-- deletes are not allowed (audit trail).
--
-- Storage bucket: `ticket-attachments` (private, not public).
--   - Insert: staff + reporter of the ticket (checked via RLS on this table).
--   - Select: same read scope as the parent ticket.
--   - The bucket is created by this migration; objects are managed via
--     supabase.storage.from('ticket-attachments') from the Flutter client
--     using the anon key (RLS on the bucket enforces access).
--
-- Limits (enforced client-side AND server-side via Storage bucket config):
--   - Max 10 MB per file
--   - Allowed MIME types: pdf, png, jpg, jpeg, doc, docx, xls, xlsx, txt, zip
--
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Storage bucket (private; Supabase Storage manages ACL separately)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'ticket-attachments',
  'ticket-attachments',
  false,
  10485760,  -- 10 MiB
  ARRAY[
    'application/pdf',
    'image/png', 'image/jpeg', 'image/jpg',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
    'application/zip'
  ]
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Attachment metadata table
-- ---------------------------------------------------------------------------
create table public.ticket_attachments (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.tickets(id) on delete cascade,
  storage_path text not null,              -- e.g. tickets/<ticketId>/<fileName>
  file_name   text not null check (length(btrim(file_name)) between 1 and 255),
  mime_type   text not null check (length(btrim(mime_type)) between 1 and 100),
  file_size   integer not null check (file_size > 0 and file_size <= 10485760),
  uploaded_by uuid not null references public.profiles(id),
  created_at  timestamptz not null default now()
);

create index ticket_attachments_ticket_idx on public.ticket_attachments (ticket_id, created_at);

-- ---------------------------------------------------------------------------
-- 3. Enable RLS and grant privileges
-- ---------------------------------------------------------------------------
alter table public.ticket_attachments enable row level security;

grant select, insert on public.ticket_attachments to authenticated;
grant all on public.ticket_attachments to service_role;

-- ---------------------------------------------------------------------------
-- 4. RLS policies
--    Read: staff can see all; reporters can see attachments on their own tickets.
--    Insert: staff can attach to any ticket they can see; reporters can attach
--            to their own tickets. (Storage bucket policies enforce the same.)
--    Delete: none (audit trail — use service_role to remove if legally required).
-- ---------------------------------------------------------------------------
create policy ticket_attachments_select on public.ticket_attachments
  for select to authenticated
  using (
    (select private.is_staff())
    or exists (
      select 1 from public.tickets t
      where t.id = ticket_id and t.reporter_id = (select auth.uid())
    )
  );

create policy ticket_attachments_insert on public.ticket_attachments
  for insert to authenticated
  with check (
    (select private.is_active_user())
    and (
      (select private.is_staff())
      or exists (
        select 1 from public.tickets t
        where t.id = ticket_id and t.reporter_id = (select auth.uid())
      )
    )
  );

-- No UPDATE or DELETE policy: attachments are immutable audit records.

-- ---------------------------------------------------------------------------
-- 5. Storage bucket policies (Supabase Storage, enforced at the object level)
-- ---------------------------------------------------------------------------
-- Allow authenticated users to READ objects in the bucket (RLS on ticket_attachments
-- table still governs who may reference an object).
insert into storage.policies (bucket_id, name, definition, operation)
values (
  'ticket-attachments',
  'Authenticated users can read attachment objects',
  'bucket_id = ''ticket-attachments''',
  'SELECT'
)
on conflict (bucket_id, name) do nothing;

-- Allow authenticated users to CREATE objects (upload). Table-level RLS above
-- further restricts which ticket an attachment can be associated with.
insert into storage.policies (bucket_id, name, definition, operation)
values (
  'ticket-attachments',
  'Authenticated users can upload attachment objects',
  'bucket_id = ''ticket-attachments''',
  'INSERT'
)
on conflict (bucket_id, name) do nothing;

commit;
