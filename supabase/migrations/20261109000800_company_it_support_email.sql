-- =============================================================================
-- ITSR Radiant Group Duri — Migration 0800: company IT Support recipient
-- =============================================================================
-- Phase 17: configure the official IT Support recipient address used by the
-- notification rules (supabase/functions/_shared/notification_rules.ts).
--
--   it_support_group_email = 'it.support-duri@radiant-utama.com'
--
-- manager_email is intentionally left unchanged (NULL): the actual Manager
-- email address has not been provided and must not be invented.
--
-- The check constraint on it_support_group_email
--   (position('@' in it_support_group_email) > 1)
-- is satisfied by the configured address.
--
-- This is recipient configuration only. No SMTP host, port, password or
-- credential is introduced here. The send-notifications Edge Function still
-- requires SMTP sender credentials (Supabase Secrets: currently GMAIL_USER /
-- GMAIL_APP_PASSWORD, hardcoded to smtp.gmail.com:465) before any outbox row
-- can be delivered. See PHASE17-COMPANY-EMAIL-CONFIGURATION-REPORT.md.
--
-- The 36 notification outbox rows in 'held' status are untouched: none are
-- claimed, deleted, or released by this migration.
-- =============================================================================
begin;

update public.app_settings
   set it_support_group_email = 'it.support-duri@radiant-utama.com'
 where id = true;

-- Post-apply verification (run in the SQL editor against the target project):
--   select it_support_group_email, manager_email, notifications_enabled
--   from public.app_settings where id = true;
-- Expected: it_support_group_email = 'it.support-duri@radiant-utama.com',
--           manager_email = NULL, notifications_enabled = true.

commit;