-- =============================================================================
-- ITSR Radiant Group Duri — Migration 0900: SMTP configuration (non-secret)
--
-- Adds columns to public.app_settings for SMTP transport configuration.
-- Only NON-secret fields are stored here. The SMTP password is stored in
-- Supabase Vault (server-side encrypted, backend-only access) and is never
-- written to this table, never returned to the client, never logged.
--
-- manager_email is intentionally NOT modified by this migration — remains NULL
-- until the actual Manager email address is provided.
--
-- The 36 notification_outbox rows in 'held' status are untouched.
-- =============================================================================

begin;

alter table public.app_settings
  add column if not exists smtp_host text;

alter table public.app_settings
  add column if not exists smtp_port integer
    check (smtp_port is null or (smtp_port > 0 and smtp_port < 65536));

alter table public.app_settings
  add column if not exists smtp_secure boolean
    check (smtp_secure in (true, false));

alter table public.app_settings
  add column if not exists smtp_username text;

alter table public.app_settings
  add column if not exists smtp_sender_name text;

alter table public.app_settings
  add column if not exists smtp_sender_email text
    check (smtp_sender_email is null or position('@' in smtp_sender_email) > 1);

alter table public.app_settings
  add column if not exists smtp_configured_at timestamptz;

alter table public.app_settings
  add column if not exists smtp_last_test_at timestamptz;

alter table public.app_settings
  add column if not exists smtp_last_test_result text
    check (smtp_last_test_result is null or smtp_last_test_result in ('success', 'failed'));

alter table public.app_settings
  add column if not exists smtp_last_test_error text;

alter table public.app_settings
  add column if not exists smtp_last_successful_email_at timestamptz;

alter table public.app_settings
  add column if not exists smtp_last_failed_email_at timestamptz;

-- Grant UPDATE on the new SMTP columns to authenticated (RLS restricts to admin).
grant update (smtp_host, smtp_port, smtp_secure, smtp_username, smtp_sender_name,
              smtp_sender_email, smtp_configured_at, smtp_last_test_at,
              smtp_last_test_result, smtp_last_test_error,
              smtp_last_successful_email_at, smtp_last_failed_email_at)
  on public.app_settings to authenticated;

commit;