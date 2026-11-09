-- =============================================================================
-- LOCAL-TEST-ONLY — DO NOT RUN ON SUPABASE (staging or production).
--
-- Emulates the pieces of a Supabase database that the migrations depend on, so
-- supabase/migrations/*.sql can be validated on a disposable local PostgreSQL:
--   * roles anon / authenticated / service_role (service_role BYPASSRLS)
--   * auth schema, minimal auth.users, auth.uid()/auth.role()/auth.jwt()
--     implemented exactly like Supabase: read from the `request.jwt.claims` GUC
--   * Supabase's permissive DEFAULT PRIVILEGES on schema public (the root cause of
--     the Gate 3 finding), so the migrations are tested against the worst case.
--
-- Guard: refuses to run if a real Supabase auth schema is detected.
-- =============================================================================

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'auth')
     and exists (select 1 from pg_roles where rolname in ('supabase_auth_admin', 'supabase_admin')) then
    raise exception 'Refusing to install LOCAL-TEST-ONLY shim on a Supabase database';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  -- Roles are cluster-wide: enforce Supabase attributes even if a role pre-existed
  alter role service_role bypassrls;
  alter role anon nobypassrls;
  alter role authenticated nobypassrls;
end $$;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (
  id         uuid primary key default gen_random_uuid(),
  email      text unique,
  created_at timestamptz not null default now()
);

create or replace function auth.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;

grant execute on all functions in schema auth to anon, authenticated, service_role;

-- Supabase-like defaults on public (worst case for least-privilege testing)
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
