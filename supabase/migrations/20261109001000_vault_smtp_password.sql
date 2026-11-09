-- =============================================================================
-- ITSR Radiant Group Duri — Migration 1000: Vault-backed SMTP password storage
--
-- SMTP password is stored in Supabase Vault (server-side encrypted).
-- Access is via SECURITY DEFINER functions that only service_role may execute
-- (the smtp-config / send-notifications Edge Functions). No client-accessible
-- function returns the password.
--
-- Phase 19 correction (before first apply): the Phase 18 draft wrote to a
-- non-existent column vault.secrets.secret_value and used ON CONFLICT (name),
-- which cannot target Vault's partial unique index. It now uses Vault's
-- supported API (vault.create_secret / vault.update_secret) and pins
-- search_path = '' like every other SECURITY DEFINER function here.
--
-- Requires the Supabase-provided vault schema. Apply after migration 0900.
-- The 36 notification_outbox rows in 'held' status are untouched.
-- =============================================================================

begin;

-- 1. Store / replace the SMTP password (service_role only).
create or replace function public.set_smtp_password(p_password text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_password is null or length(p_password) = 0 then
    raise exception 'SMTP password must not be empty';
  end if;
  select id into v_id from vault.secrets where name = 'itsr_smtp_password';
  if v_id is null then
    perform vault.create_secret(p_password, 'itsr_smtp_password',
                                'ITSR SMTP AUTH password (set via smtp-config)');
  else
    perform vault.update_secret(v_id, p_password);
  end if;
end;
$$;

revoke all on function public.set_smtp_password(text) from public, anon, authenticated;
grant execute on function public.set_smtp_password(text) to service_role;

-- 2. Read the decrypted SMTP password; NULL when none is configured
--    (service_role only).
create or replace function public.get_smtp_password()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_password text;
begin
  select decrypted_secret into v_password from vault.decrypted_secrets
   where name = 'itsr_smtp_password'
   limit 1;
  return v_password;
end;
$$;

revoke all on function public.get_smtp_password() from public, anon, authenticated;
grant execute on function public.get_smtp_password() to service_role;

-- 3. Remove the SMTP password (service_role only).
create or replace function public.remove_smtp_password()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets where name = 'itsr_smtp_password';
end;
$$;

revoke all on function public.remove_smtp_password() from public, anon, authenticated;
grant execute on function public.remove_smtp_password() to service_role;

commit;
