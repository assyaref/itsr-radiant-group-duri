-- =============================================================================
-- ITSR Radiant Group Duri — Migration 0100: Core schema
-- Target: Supabase (native auth). Uses Supabase-provided auth.users / auth.uid().
-- This file MUST NOT create the auth schema, auth.users or auth.uid().
-- (For local validation those are emulated by supabase/tests/local/00_supabase_shim.sql,
--  which is LOCAL-TEST-ONLY and never part of this migration chain.)
-- Supersedes legacy migrations/0001_initial_schema.sql (never applied to staging/prod).
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  employee_number text not null unique
                  check (employee_number ~ '^[A-Z0-9]{2,20}$'),
  full_name       text not null check (length(btrim(full_name)) between 1 and 120),
  email           text not null unique check (position('@' in email) > 1),
  department      text not null default 'General',
  role            text not null default 'employee'
                  check (role in ('employee', 'it_support', 'administrator')),
  phone_number    text,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Ticket categories (managed by administrators)
-- ---------------------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique check (length(btrim(name)) between 1 and 60),
  description text,
  is_active   boolean not null default true,
  sort_order  integer not null default 100,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Neutral starter categories (editable/deactivatable by admins).
insert into public.categories (name, description, sort_order) values
  ('Hardware',        'Computers, laptops, printers, peripherals', 10),
  ('Software',        'Applications, licenses, installation',      20),
  ('Network',         'Internet, Wi-Fi, LAN, VPN',                  30),
  ('Email',           'Mailbox, Outlook/Gmail access',              40),
  ('Account Access',  'Passwords, permissions, new accounts',       50),
  ('Other',           'Anything else',                              90);

-- ---------------------------------------------------------------------------
-- Tickets
-- ---------------------------------------------------------------------------
create sequence public.ticket_number_seq start 1;

create table public.tickets (
  id              uuid primary key default gen_random_uuid(),
  ticket_number   text not null unique,
  subject         text not null check (length(btrim(subject)) between 3 and 200),
  description     text not null check (length(btrim(description)) between 5 and 5000),
  category        text not null references public.categories(name) on update cascade,
  subcategory     text,
  priority        text not null default 'medium'
                  check (priority in ('low', 'medium', 'high', 'critical')),
  status          text not null default 'open'
                  check (status in ('open', 'assigned', 'in_progress', 'pending_user',
                                    'resolved', 'closed', 'reopened')),
  reporter_id     uuid not null references public.profiles(id),
  assigned_to_id  uuid references public.profiles(id),
  resolution      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  resolved_at     timestamptz,
  closed_at       timestamptz,
  constraint tickets_resolution_required
    check (status not in ('resolved', 'closed') or length(btrim(coalesce(resolution, ''))) > 0)
);

create index tickets_reporter_idx  on public.tickets (reporter_id, created_at desc);
create index tickets_assignee_idx  on public.tickets (assigned_to_id, created_at desc);
create index tickets_status_idx    on public.tickets (status, created_at desc);
create index tickets_created_idx   on public.tickets (created_at desc, id desc);

-- ---------------------------------------------------------------------------
-- Comments
-- ---------------------------------------------------------------------------
create table public.ticket_comments (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.tickets(id) on delete cascade,
  author_id   uuid not null references public.profiles(id),
  content     text not null check (length(btrim(content)) between 1 and 5000),
  is_internal boolean not null default false,
  created_at  timestamptz not null default now()
);
create index ticket_comments_ticket_idx on public.ticket_comments (ticket_id, created_at);

-- ---------------------------------------------------------------------------
-- Activity log (written ONLY by server-side triggers)
-- ---------------------------------------------------------------------------
create table public.ticket_activity_log (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null references public.tickets(id) on delete cascade,
  actor_id   uuid references public.profiles(id),   -- null = system / service role
  action     text not null check (action in ('created', 'assigned', 'status_changed',
                                              'priority_changed', 'resolved', 'reopened',
                                              'closed', 'category_changed')),
  old_value  text,
  new_value  text,
  note       text,
  created_at timestamptz not null default now()
);
create index ticket_activity_ticket_idx on public.ticket_activity_log (ticket_id, created_at);

-- ---------------------------------------------------------------------------
-- Application settings (singleton row). Email addresses are intentionally NULL:
-- they must be entered by an administrator — never invented.
-- ---------------------------------------------------------------------------
create table public.app_settings (
  id                      boolean primary key default true check (id),
  it_support_group_email  text check (it_support_group_email is null or position('@' in it_support_group_email) > 1),
  manager_email           text check (manager_email is null or position('@' in manager_email) > 1),
  notifications_enabled   boolean not null default true,
  app_base_url            text,
  updated_at              timestamptz not null default now(),
  updated_by              uuid references public.profiles(id)
);
insert into public.app_settings (id) values (true);

-- ---------------------------------------------------------------------------
-- Notification outbox (filled by triggers, drained by the send-notifications
-- Edge Function using the service role). No client access.
-- ---------------------------------------------------------------------------
create table public.notification_outbox (
  id           uuid primary key default gen_random_uuid(),
  ticket_id    uuid not null references public.tickets(id) on delete cascade,
  event_type   text not null check (event_type in ('ticket_created', 'ticket_assigned',
                                                    'status_changed', 'comment_added')),
  payload      jsonb not null default '{}'::jsonb,
  status       text not null default 'pending'
               check (status in ('pending', 'processing', 'sent', 'failed', 'skipped')),
  attempts     integer not null default 0,
  last_error   text,
  recipients   text[],
  cc           text[],
  created_at   timestamptz not null default now(),
  locked_at    timestamptz,
  sent_at      timestamptz
);
create index notification_outbox_pending_idx
  on public.notification_outbox (created_at) where status in ('pending', 'processing');

-- ---------------------------------------------------------------------------
-- Login attempts (rate limiting; written by the login Edge Function only)
-- ---------------------------------------------------------------------------
create table public.login_attempts (
  id              uuid primary key default gen_random_uuid(),
  ip_address      text not null,
  employee_number text,
  user_id         uuid references public.profiles(id) on delete set null,
  success         boolean not null default false,
  created_at      timestamptz not null default now()
);
create index login_attempts_emp_idx on public.login_attempts (employee_number, created_at desc);
create index login_attempts_ip_idx  on public.login_attempts (ip_address, created_at desc);

-- ---------------------------------------------------------------------------
-- RLS ON for every table (policies are defined in migration 0200).
-- A table with RLS enabled and no policy denies all client access.
-- ---------------------------------------------------------------------------
alter table public.profiles            enable row level security;
alter table public.categories          enable row level security;
alter table public.tickets             enable row level security;
alter table public.ticket_comments     enable row level security;
alter table public.ticket_activity_log enable row level security;
alter table public.app_settings        enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.login_attempts      enable row level security;

commit;
