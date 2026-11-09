-- LOCAL-TEST-ONLY test harness. Never run on Supabase.
create schema if not exists test;
grant usage on schema test to anon, authenticated, service_role;

create table if not exists test.results (
  id serial primary key,
  name text not null,
  passed boolean not null,
  detail text,
  at timestamptz default now()
);
grant usage on sequence test.results_id_seq to anon, authenticated, service_role;

create table if not exists test.users (code text primary key, id uuid not null);

-- Record a result (definer so it works under any role)
create or replace function test.ok(p_cond boolean, p_name text, p_detail text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into test.results (name, passed, detail) values (p_name, coalesce(p_cond, false), p_detail);
  raise notice '% %', case when coalesce(p_cond, false) then 'PASS' else 'FAIL' end, p_name;
end $$;

create or replace function test.uid(p_code text) returns uuid
language sql security definer set search_path = '' stable as $$
  select id from test.users where code = p_code
$$;

-- Become a PostgREST-style request: role + JWT claims (transaction-local)
create or replace function test.act_as(p_code text) returns void
language plpgsql as $$
begin
  if p_code = 'anon' then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('role', 'anon', true);
  elsif p_code = 'service' then
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    perform set_config('role', 'service_role', true);
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', test.uid(p_code), 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
  end if;
end $$;

-- Run SQL as the current role; PASS if it raises an error
create or replace function test.expect_error(p_sql text, p_name text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    perform test.ok(true, p_name, sqlerrm);
    return;
  end;
  perform test.ok(false, p_name, 'statement succeeded but was expected to fail');
end $$;

-- Run SQL as the current role; PASS if it does NOT raise
create or replace function test.expect_ok(p_sql text, p_name text)
returns void language plpgsql as $$
begin
  execute p_sql;
  perform test.ok(true, p_name);
exception when others then
  perform test.ok(false, p_name, sqlerrm);
end $$;

grant execute on all functions in schema test to anon, authenticated, service_role;
