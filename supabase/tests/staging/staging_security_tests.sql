-- =============================================================================
-- STAGING SECURITY TESTS (generated from tests/local/10_test_harness.sql +
-- tests/local/20_security_and_workflow_tests.sql; assertions unchanged except P02).
--
-- SAFE FOR THE STAGING PROJECT ONLY:
--   * runs in ONE transaction; the harness schema `test` and all fixtures are
--     created inside it;
--   * the script ENDS BY RAISING AN EXCEPTION carrying the JSON results, which
--     guarantees ROLLBACK - no fixture, outbox row, or harness object survives;
--   * public.ticket_number_seq (non-transactional) is restored to its original
--     state before the final exception.
-- Does NOT use tests/local/00_supabase_shim.sql (Supabase provides the real roles).
-- =============================================================================
begin;
create temp table _seq0 on commit drop as select last_value, is_called from public.ticket_number_seq;
do $$ begin
  if exists (select 1 from public.tickets) or exists (select 1 from auth.users) then
    raise exception 'ABORT: staging is not empty; suite expects an empty database';
  end if;
end $$;
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

-- =============================================================================
-- LOCAL-TEST-ONLY: executable acceptance tests for supabase/migrations.
-- Every assertion runs as the real Postgres role PostgREST would use
-- (anon / authenticated / service_role) with JWT claims set the same way.
-- =============================================================================

-- ---------------------------------------------------------------- fixtures --
insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-000000000001', 'emp.a@example.test'),
  ('10000000-0000-0000-0000-000000000002', 'emp.b@example.test'),
  ('10000000-0000-0000-0000-000000000003', 'it.one@example.test'),
  ('10000000-0000-0000-0000-000000000004', 'it.two@example.test'),
  ('10000000-0000-0000-0000-000000000005', 'admin@example.test'),
  ('10000000-0000-0000-0000-000000000006', 'inactive@example.test');

insert into public.profiles (id, employee_number, full_name, email, department, role, is_active) values
  ('10000000-0000-0000-0000-000000000001', 'EMP001', 'Employee A', 'emp.a@example.test', 'Finance', 'employee', true),
  ('10000000-0000-0000-0000-000000000002', 'EMP002', 'Employee B', 'emp.b@example.test', 'HR', 'employee', true),
  ('10000000-0000-0000-0000-000000000003', 'IT001', 'IT One', 'it.one@example.test', 'IT', 'it_support', true),
  ('10000000-0000-0000-0000-000000000004', 'IT002', 'IT Two', 'it.two@example.test', 'IT', 'it_support', true),
  ('10000000-0000-0000-0000-000000000005', 'ADM001', 'Admin', 'admin@example.test', 'IT', 'administrator', true),
  ('10000000-0000-0000-0000-000000000006', 'EMP099', 'Inactive', 'inactive@example.test', 'Ops', 'employee', false);

insert into test.users values
  ('A',   '10000000-0000-0000-0000-000000000001'),
  ('B',   '10000000-0000-0000-0000-000000000002'),
  ('IT1', '10000000-0000-0000-0000-000000000003'),
  ('IT2', '10000000-0000-0000-0000-000000000004'),
  ('ADM', '10000000-0000-0000-0000-000000000005'),
  ('OFF', '10000000-0000-0000-0000-000000000006');

update public.app_settings set it_support_group_email = 'it-group@example.test',
                               manager_email = 'manager@example.test';

-- ------------------------------------------------- privileges (Gate 3) ------
do $$
declare n int;
begin
  perform test.ok(not has_function_privilege('anon', 'public.login_is_rate_limited(text,text,integer,integer,integer)', 'EXECUTE'), 'P01a anon cannot execute login_is_rate_limited');
  perform test.ok(not has_function_privilege('authenticated', 'public.login_is_rate_limited(text,text,integer,integer,integer)', 'EXECUTE'), 'P01b authenticated cannot execute login_is_rate_limited');
  perform test.ok(has_function_privilege('service_role', 'public.login_is_rate_limited(text,text,integer,integer,integer)', 'EXECUTE'), 'P01c service_role can execute login_is_rate_limited');
  perform test.ok(not has_function_privilege('anon', 'public.record_login_attempt(text,text,uuid,boolean)', 'EXECUTE')
              and not has_function_privilege('authenticated', 'public.record_login_attempt(text,text,uuid,boolean)', 'EXECUTE'), 'P01d record_login_attempt not executable by anon/authenticated');
  perform test.ok(not has_function_privilege('anon', 'public.claim_notifications(integer)', 'EXECUTE')
              and not has_function_privilege('authenticated', 'public.claim_notifications(integer)', 'EXECUTE')
              and not has_function_privilege('authenticated', 'public.complete_notification(uuid,text,text,text[],text[])', 'EXECUTE'), 'P01e outbox RPCs not executable by anon/authenticated');

  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname in ('public', 'private') and p.prorettype <> 'event_trigger'::regtype and has_function_privilege('anon', p.oid, 'EXECUTE');
  perform test.ok(n = 0, 'P02 anon can execute zero app functions (event triggers excluded)', n || ' executable');

  select count(*) into n from pg_class c join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public' and c.relkind = 'r'
     and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('anon', c.oid, 'INSERT')
          or has_table_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE'));
  perform test.ok(n = 0, 'P03 anon has no table privileges', n || ' tables');

  perform test.ok(not has_table_privilege('authenticated', 'public.notification_outbox', 'SELECT')
              and not has_table_privilege('authenticated', 'public.login_attempts', 'SELECT')
              and not has_table_privilege('authenticated', 'public.login_attempts', 'INSERT'), 'P04 authenticated has no access to outbox/login_attempts');

  perform test.ok(not has_table_privilege('authenticated', 'public.profiles', 'UPDATE')
              and not has_table_privilege('authenticated', 'public.profiles', 'INSERT')
              and not has_table_privilege('authenticated', 'public.tickets', 'DELETE')
              and not has_table_privilege('authenticated', 'public.ticket_activity_log', 'INSERT'), 'P05 no client write on profiles / activity, no ticket delete');

  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname in ('public', 'private') and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  perform test.ok(n = 0, 'P06 every SECURITY DEFINER function pins search_path', n || ' unpinned');

  select count(*) into n from pg_class c join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  perform test.ok(n = 0, 'P07 RLS enabled on every public table', n || ' without RLS');

  perform test.ok(not exists (select 1 from pg_proc where proname in ('check_rate_limit', 'cleanup_old_login_attempts')), 'P08 legacy anon-executable rate-limit functions absent');

  perform test.ok(not has_schema_privilege('anon', 'private', 'USAGE'), 'P09 anon has no usage on private schema');
end $$;

-- --------------------------------------------------------------- anon -------
do $$ begin
  perform test.act_as('anon');
  perform test.expect_error('select * from public.tickets', 'AN01 anon cannot read tickets');
  perform test.expect_error('select * from public.profiles', 'AN02 anon cannot read profiles');
  perform test.expect_error('select public.ticket_stats(''all'')', 'AN03 anon cannot call ticket_stats');
  perform test.expect_error('select public.login_is_rate_limited(''1.1.1.1'',''EMP001'')', 'AN04 anon cannot call rate limiter (Gate 3 exploit path)');
end $$;

-- ------------------------------------------------------ employee create -----
do $$
declare t record; n int;
begin
  perform test.act_as('A');
  insert into public.tickets (subject, description, category, priority, reporter_id)
  values ('Laptop will not boot', 'Black screen after the BIOS logo appears.', 'Hardware', 'high', test.uid('A'));

  select * into t from public.tickets where subject = 'Laptop will not boot';
  perform test.ok(t.ticket_number ~ '^ITSR-RGD-[0-9]{8,}$', 'E01 ticket number generated server-side', t.ticket_number);
  perform test.ok(t.status = 'open' and t.assigned_to_id is null, 'E02 new ticket is open and unassigned');

  select count(*) into n from public.ticket_activity_log where ticket_id = t.id and action = 'created' and actor_id = test.uid('A');
  perform test.ok(n = 1, 'E03 creation recorded in activity log by trigger');
end $$;

do $$ begin
  perform test.act_as('A');
  perform test.expect_error($q$insert into public.tickets (subject, description, category, priority, reporter_id, status)
     values ('Sneaky', 'Trying to set status myself', 'Hardware', 'low', test.uid('A'), 'resolved')$q$,
     'E04 employee cannot set status on insert (column privilege)');
  perform test.expect_error($q$insert into public.tickets (subject, description, category, priority, reporter_id)
     values ('Bad category', 'Unknown category should fail', 'Nope', 'low', test.uid('A'))$q$,
     'E05 unknown category rejected');
  perform test.expect_error($q$insert into public.tickets (subject, description, category, priority, reporter_id)
     values ('x', 'too short subject', 'Hardware', 'low', test.uid('A'))$q$,
     'E06 subject length validated');
end $$;

-- spoofed reporter is neutralised
do $$
declare r uuid;
begin
  perform test.act_as('A');
  insert into public.tickets (subject, description, category, priority, reporter_id)
  values ('Spoof reporter', 'Reporter set to employee B by a malicious client', 'Software', 'low', test.uid('B'));
  perform test.act_as('ADM');
  select reporter_id into r from public.tickets where subject = 'Spoof reporter';
  perform test.ok(r = test.uid('A'), 'E07 spoofed reporter_id is forced to the caller');
end $$;

do $$ begin
  perform test.act_as('B');
  insert into public.tickets (subject, description, category, priority, reporter_id)
  values ('Printer jam on floor 2', 'Paper jam error on the shared HP printer.', 'Hardware', 'medium', test.uid('B'));
end $$;

-- --------------------------------------------------- employee isolation -----
do $$
declare n int; b_ticket uuid; nums int; dist int;
begin
  perform test.act_as('ADM');
  select id into b_ticket from public.tickets where subject = 'Printer jam on floor 2';
  select count(*), count(distinct ticket_number) into nums, dist from public.tickets;
  perform test.ok(nums = dist and nums = 3, 'E08 ticket numbers unique across reporters', nums || '/' || dist);

  perform test.act_as('A');
  select count(*) into n from public.tickets;
  perform test.ok(n = 2, 'E09 employee A sees only own tickets', n::text);
  select count(*) into n from public.tickets where id = b_ticket;
  perform test.ok(n = 0, 'E10 employee A cannot read B''s ticket by id');
  select count(*) into n from public.ticket_activity_log where ticket_id = b_ticket;
  perform test.ok(n = 0, 'E11 employee A cannot read B''s ticket history');
  select count(*) into n from public.profiles where id = test.uid('B');
  perform test.ok(n = 0, 'E12 employee A cannot read B''s profile');
  select count(*) into n from public.profiles where id in (test.uid('A'), test.uid('IT1'));
  perform test.ok(n = 2, 'E13 employee sees own + IT staff profiles');
  select count(*) into n from public.assignable_staff();
  perform test.ok(n = 0, 'E14 assignable_staff returns nothing for employees');
  select count(*) into n from public.app_settings;
  perform test.ok(n = 0, 'E15 employee cannot read app settings');

  perform test.expect_error(format('insert into public.ticket_comments (ticket_id, author_id, content) values (%L, %L, ''hi'')', b_ticket, test.uid('A')),
    'E16 employee cannot comment on another employee''s ticket');
  perform test.expect_error('select * from public.notification_outbox', 'E17 employee cannot read notification outbox');
  perform test.expect_error('select * from public.login_attempts', 'E18 employee cannot read login attempts');
  perform test.expect_error(format('update public.profiles set role = ''administrator'' where id = %L', test.uid('A')),
    'E19 employee cannot escalate own role');
  perform test.expect_error('insert into public.categories (name) values (''Hacked'')', 'E20 employee cannot create categories');
end $$;

do $$
declare t uuid; s text;
begin
  perform test.act_as('A');
  select id into t from public.tickets where subject = 'Laptop will not boot';
  update public.tickets set status = 'resolved', resolution = 'self-resolved' where id = t;
  select status into s from public.tickets where id = t;
  perform test.ok(s = 'open', 'E21 employee cannot change ticket status directly', s);

  perform test.expect_ok(format('insert into public.ticket_comments (ticket_id, author_id, content) values (%L, %L, ''It also beeps 3 times'')', t, test.uid('A')),
    'E22 employee can comment on own ticket');
  perform test.expect_error(format('insert into public.ticket_comments (ticket_id, author_id, content, is_internal) values (%L, %L, ''x'', true)', t, test.uid('A')),
    'E23 employee cannot post internal comments');
end $$;

-- ------------------------------------------------------- inactive user ------
do $$
declare n int;
begin
  perform test.act_as('OFF');
  perform test.expect_error($q$insert into public.tickets (subject, description, category, priority, reporter_id)
     values ('Inactive user ticket', 'Should not be allowed', 'Other', 'low', test.uid('OFF'))$q$,
     'I01 deactivated user cannot create tickets');
  select count(*) into n from public.categories;
  perform test.ok(n = 0, 'I02 deactivated user reads no data');
end $$;

-- ------------------------------------------------------------- IT flow ------
do $$
declare t uuid; r record; n int;
begin
  perform test.act_as('IT1');
  select count(*) into n from public.tickets;
  perform test.ok(n = 3, 'T01 IT support sees all tickets', n::text);
  select count(*) into n from public.assignable_staff();
  perform test.ok(n = 3, 'T02 assignable_staff lists active IT/admin users', n::text);

  select id into t from public.tickets where subject = 'Laptop will not boot';
  update public.tickets set assigned_to_id = test.uid('IT1') where id = t;
  select * into r from public.tickets where id = t;
  perform test.ok(r.status = 'assigned' and r.assigned_to_id = test.uid('IT1'), 'T03 accept/assign moves ticket to assigned');
  select count(*) into n from public.ticket_activity_log where ticket_id = t and action = 'assigned' and actor_id = test.uid('IT1');
  perform test.ok(n = 1, 'T04 assignment recorded in history with actor');

  update public.tickets set status = 'in_progress' where id = t;
  select count(*) into n from public.ticket_activity_log
   where ticket_id = t and action = 'status_changed' and old_value = 'assigned' and new_value = 'in_progress';
  perform test.ok(n = 1, 'T05 status change recorded in history');

  perform test.expect_error(format('update public.tickets set status = ''closed'' where id = %L', t), 'T06 invalid transition in_progress->closed rejected');
  perform test.expect_error(format('update public.tickets set status = ''resolved'' where id = %L', t), 'T07 resolve without resolution rejected');
  perform test.expect_error(format('update public.tickets set assigned_to_id = %L where id = %L', test.uid('A'), t), 'T08 cannot assign to a non-IT user');
  perform test.expect_error(format('update public.tickets set reporter_id = %L where id = %L', test.uid('B'), t), 'T09 reporter_id is not updatable');
  perform test.expect_error(format('delete from public.tickets where id = %L', t), 'T10 tickets cannot be deleted');
  perform test.expect_error(format('insert into public.ticket_activity_log (ticket_id, action) values (%L, ''created'')', t), 'T11 clients cannot forge activity rows');

  perform test.expect_ok(format('insert into public.ticket_comments (ticket_id, author_id, content, is_internal) values (%L, %L, ''Suspect RAM failure'', true)', t, test.uid('IT1')),
    'T12 IT can add internal work note');
  perform test.expect_ok(format('insert into public.ticket_comments (ticket_id, author_id, content) values (%L, %L, ''Please bring the laptop to IT'')', t, test.uid('IT1')),
    'T13 IT can add public comment');

  update public.tickets set status = 'resolved', resolution = 'Reseated RAM module; laptop boots normally.' where id = t;
  select * into r from public.tickets where id = t;
  perform test.ok(r.status = 'resolved' and r.resolved_at is not null, 'T14 IT can resolve with resolution');
  select count(*) into n from public.ticket_activity_log where ticket_id = t and action = 'resolved' and note like 'Reseated RAM%';
  perform test.ok(n = 1, 'T15 resolution recorded in history');

  update public.categories set name = 'Hacked' where name = 'Other';
  select count(*) into n from public.categories where name = 'Hacked';
  perform test.ok(n = 0, 'T16 IT support cannot manage categories');
  select count(*) into n from public.app_settings;
  perform test.ok(n = 0, 'T17 IT support cannot read app settings');
end $$;

-- employee view of IT work
do $$
declare t uuid; n int;
begin
  perform test.act_as('A');
  select id into t from public.tickets where subject = 'Laptop will not boot';
  select count(*) into n from public.ticket_comments where ticket_id = t and is_internal;
  perform test.ok(n = 0, 'E24 employee cannot see internal work notes');
  select count(*) into n from public.ticket_comments where ticket_id = t;
  perform test.ok(n = 2, 'E25 employee sees own + IT public comments', n::text);
  select count(*) into n from public.ticket_activity_log where ticket_id = t;
  perform test.ok(n >= 4, 'E26 employee can track ticket progress (history)', n::text);
  select count(*) into n from public.profiles where id = test.uid('IT1');
  perform test.ok(n = 1, 'E27 employee can see assignee name');
end $$;

-- ---------------------------------------------------- reporter actions ------
do $$
declare t uuid; r record; n int; tb uuid;
begin
  perform test.act_as('A');
  select id into t from public.tickets where subject = 'Laptop will not boot';
  perform test.expect_error(format('select public.reporter_ticket_action(%L, ''reopen'', '''')', t), 'R01 reopen requires a reason');
  perform public.reporter_ticket_action(t, 'reopen', 'Problem came back this morning');
  select * into r from public.tickets where id = t;
  perform test.ok(r.status = 'reopened' and r.resolved_at is null, 'R02 reporter can reopen resolved ticket');
  select count(*) into n from public.ticket_activity_log where ticket_id = t and action = 'reopened' and note = 'Problem came back this morning' and actor_id = test.uid('A');
  perform test.ok(n = 1, 'R03 reopen reason recorded in history');
  perform test.expect_error(format('select public.reporter_ticket_action(%L, ''close'')', t), 'R04 reporter cannot close an unresolved ticket');

  perform test.act_as('B');
  perform test.expect_error(format('select public.reporter_ticket_action(%L, ''reopen'', ''x'')', t), 'R05 other employee cannot act on ticket');

  perform test.act_as('IT2');
  update public.tickets set status = 'resolved', resolution = 'Replaced RAM module.' where id = t;
  select assigned_to_id into tb from public.tickets where id = t;
  perform test.ok(tb = test.uid('IT1'), 'R06 resolving keeps existing assignee');

  perform test.act_as('A');
  perform public.reporter_ticket_action(t, 'close');
  select * into r from public.tickets where id = t;
  perform test.ok(r.status = 'closed' and r.closed_at is not null, 'R07 reporter can confirm/close resolved ticket');
end $$;

-- ------------------------------------------------------------ stats --------
do $$
declare s record;
begin
  perform test.act_as('A');
  select * into s from public.ticket_stats('mine');
  perform test.ok(s.total = 2 and s.closed = 1 and s.open = 1, 'S01 ticket_stats(mine) respects RLS', row_to_json(s)::text);
  select * into s from public.ticket_stats('all');
  perform test.ok(s.total = 2, 'S02 employee ticket_stats(all) still limited by RLS', row_to_json(s)::text);
  perform test.act_as('IT1');
  select * into s from public.ticket_stats('all');
  perform test.ok(s.total = 3 and s.unassigned = 2, 'S03 IT ticket_stats(all) sees everything', row_to_json(s)::text);
end $$;

-- ------------------------------------------------------------ admin --------
do $$
declare n int;
begin
  perform test.act_as('ADM');
  select count(*) into n from public.profiles;
  perform test.ok(n = 6, 'D01 admin sees all profiles');
  perform test.expect_ok('insert into public.categories (name, description) values (''Printer'', ''Printers and scanners'')', 'D02 admin can create category');
  perform test.expect_ok('update public.categories set is_active = false where name = ''Printer''', 'D03 admin can deactivate category');
  perform test.expect_ok('update public.app_settings set manager_email = ''new.manager@example.test''', 'D04 admin can update settings');
  select count(*) into n from public.app_settings where manager_email = 'new.manager@example.test';
  perform test.ok(n = 1, 'D05 settings persisted');
  perform test.expect_error('insert into public.profiles (id, employee_number, full_name, email) values (gen_random_uuid(), ''X1'', ''x'', ''x@x'')',
    'D06 even admin cannot insert profiles directly (Edge Function only)');

  perform test.act_as('A');
  perform test.expect_error($q$insert into public.tickets (subject, description, category, priority, reporter_id)
     values ('Inactive category', 'Should fail for inactive category', 'Printer', 'low', test.uid('A'))$q$,
     'D07 inactive category rejected for new tickets');
end $$;

-- category rename cascades into existing tickets through the guarded triggers
do $$
declare n int;
begin
  perform test.act_as('ADM');
  perform test.expect_ok('update public.categories set name = ''Computer Hardware'' where name = ''Hardware''',
    'D08 admin can rename a category that existing tickets use');
  select count(*) into n from public.tickets where category = 'Hardware';
  perform test.ok(n = 0, 'D09 rename cascades to existing tickets', n::text);
  select count(*) into n from public.tickets where category = 'Computer Hardware';
  perform test.ok(n = 2, 'D10 tickets now carry the new category name', n::text);
  update public.categories set name = 'Hardware' where name = 'Computer Hardware';
end $$;

-- ------------------------------------------------------- notifications ------
do $$
declare n int; c int;
begin
  -- as service role (Edge Function)
  perform test.act_as('service');
  select count(*) into n from public.notification_outbox where event_type = 'ticket_created';
  perform test.ok(n = 3, 'N01 ticket_created enqueued per ticket', n::text);
  select count(*) into n from public.notification_outbox where event_type = 'comment_added';
  perform test.ok(n = 2, 'N02 only non-internal comments enqueue notifications', n::text);
  select count(*) into n from public.notification_outbox where event_type = 'status_changed';
  perform test.ok(n >= 4, 'N03 status changes enqueue notifications', n::text);
  select count(*) into n from public.notification_outbox where event_type = 'ticket_assigned';
  perform test.ok(n = 1, 'N04 assignment enqueues notification', n::text);

  select count(*) into c from public.claim_notifications(100);
  select count(*) into n from public.notification_outbox where status = 'processing';
  perform test.ok(c = n and c > 0, 'N05 claim_notifications locks a batch', c::text);
  select count(*) into c from public.claim_notifications(100);
  perform test.ok(c = 0, 'N06 claimed rows are not re-claimed immediately');
  perform public.complete_notification(id, 'sent', null, array['x@example.test'], null)
    from public.notification_outbox where status = 'processing';
  select count(*) into n from public.notification_outbox where status = 'sent';
  perform test.ok(n > 0, 'N07 complete_notification marks rows sent');
end $$;

do $$
declare before_n int; after_n int;
begin
  update public.app_settings set notifications_enabled = false;
  select count(*) into before_n from public.notification_outbox;
  perform test.act_as('B');
  insert into public.tickets (subject, description, category, priority, reporter_id)
  values ('Muted ticket', 'Created while notifications disabled', 'Software', 'low', test.uid('B'));
  perform test.act_as('service');
  select count(*) into after_n from public.notification_outbox;
  perform test.ok(before_n = after_n, 'N08 notifications_enabled=false suppresses enqueue');
end $$;
update public.app_settings set notifications_enabled = true;

-- ------------------------------------------------------- rate limiting ------
do $$
declare limited boolean;
begin
  perform test.act_as('service');
  for i in 1..5 loop
    perform public.record_login_attempt('10.0.0.1', 'EMP001', null, false);
  end loop;
  select public.login_is_rate_limited('10.0.0.1', 'EMP001') into limited;
  perform test.ok(limited, 'L01 5 failures lock the account for 15 minutes');
  select public.login_is_rate_limited('10.0.0.1', 'EMP002') into limited;
  perform test.ok(not limited, 'L02 colleague behind the same office IP is not locked out');
  for i in 1..25 loop
    perform public.record_login_attempt('10.0.0.1', 'EMPX' || i, null, false);
  end loop;
  select public.login_is_rate_limited('10.0.0.1', 'EMP002') into limited;
  perform test.ok(limited, 'L03 IP-wide brute force (30 failures) is blocked');
  perform public.record_login_attempt('10.0.0.9', 'EMP001', test.uid('A'), true);
  select public.login_is_rate_limited('10.0.0.9', 'EMP001') into limited;
  perform test.ok(not limited, 'L04 successful login clears the account failure streak');
end $$;


-- staging-only addition: platform event-trigger function is not directly callable
do $$ begin
  perform test.act_as('anon');
  perform test.expect_error('select public.rls_auto_enable()', 'P02b anon cannot call platform event-trigger function rls_auto_enable directly');
end $$;

-- ------------------------------------------------------------- summary -----
reset role;
do $$
declare r json; s record;
begin
  select json_build_object(
    'passed', count(*) filter (where passed), 'failed', count(*) filter (where not passed), 'total', count(*),
    'results', json_agg(json_build_object('n', name, 'ok', passed, 'detail', detail) order by id)) into r
  from test.results;
  select * into s from _seq0;
  perform setval('public.ticket_number_seq', s.last_value, s.is_called);   -- sequences ignore rollback
  raise exception 'STAGING_TEST_RESULTS %', r;                               -- forces ROLLBACK of everything else
end $$;
