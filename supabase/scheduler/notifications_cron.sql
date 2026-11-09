-- =============================================================================
-- ITSR — notification retry scheduler (pg_cron + pg_net -> send-notifications)
--
-- NOT a migration: it depends on per-environment Vault secrets and on the
-- pg_cron / pg_net extensions, which the local throwaway test cluster lacks.
-- Idempotent: safe to re-run (re-creates the single job by name).
--
-- Prerequisites (created separately, values NEVER committed):
--   vault secret 'itsr_functions_base_url'        e.g. https://<ref>.supabase.co/functions/v1
--   vault secret 'itsr_notifications_cron_secret' == Edge Function secret NOTIFICATIONS_CRON_SECRET
--
-- Why this cannot duplicate emails:
--   * pg_net is fire-and-forget, so cron runs never block or pile up in Postgres;
--   * if two sender invocations overlap (cron + an app "kick"), claim_notifications()
--     uses FOR UPDATE SKIP LOCKED and flips rows to 'processing' atomically, so
--     each row is handed to exactly one invocation;
--   * a 'processing' row is only re-claimed after 10 minutes (far longer than
--     one invocation can run), failed rows after 5 minutes, max 5 attempts,
--     permanent failures / 'held' / 'sent' / 'skipped' never.
--
-- Disable:  select cron.unschedule('itsr-send-notifications');
-- =============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'itsr_functions_base_url')
     or not exists (select 1 from vault.secrets where name = 'itsr_notifications_cron_secret') then
    raise exception 'missing vault secrets itsr_functions_base_url / itsr_notifications_cron_secret';
  end if;
  if exists (select 1 from cron.job where jobname = 'itsr-send-notifications') then
    perform cron.unschedule('itsr-send-notifications');
  end if;
end $$;

select cron.schedule(
  'itsr-send-notifications',
  '*/2 * * * *',
  $job$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets
                where name = 'itsr_functions_base_url') || '/send-notifications',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets
                                   where name = 'itsr_notifications_cron_secret')),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $job$
);
