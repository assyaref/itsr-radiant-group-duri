-- Ticket numbers: ITSR-RGD-YYMM#### (e.g. ITSR-RGD-26110001).
--
--   YY   = year, MM = month (Asia/Jakarta time)
--   #### = running number that restarts at 0001 every month
--          (grows to 5+ digits only if a month ever exceeds 9999 tickets)
--
-- A per-month counter row is incremented with INSERT ... ON CONFLICT, which
-- takes a row lock, so concurrent inserts can never get the same number.
begin;

create table if not exists private.ticket_number_counters (
  period   text primary key check (period ~ '^[0-9]{4}$'),   -- YYMM
  last_no  integer not null check (last_no > 0)
);
revoke all on private.ticket_number_counters from public, anon, authenticated;

create or replace function private.next_ticket_number()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'Asia/Jakarta', 'YYMM');
  v_no     integer;
begin
  insert into private.ticket_number_counters as c (period, last_no)
  values (v_period, 1)
  on conflict (period) do update set last_no = c.last_no + 1
  returning c.last_no into v_no;
  return 'ITSR-RGD-' || v_period || case when v_no < 10000 then lpad(v_no::text, 4, '0') else v_no::text end;
end;
$$;
revoke all on function private.next_ticket_number() from public, anon, authenticated;

create or replace function private.tickets_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- An end-user session can only file tickets for itself (RLS also enforces this)
  if auth.uid() is not null then
    new.reporter_id := auth.uid();
  end if;

  if not exists (select 1 from public.categories c where c.name = new.category and c.is_active) then
    raise exception 'Unknown or inactive category: %', new.category using errcode = '22023';
  end if;

  new.ticket_number  := private.next_ticket_number();
  new.status         := 'open';
  new.assigned_to_id := null;
  new.resolution     := null;
  new.resolved_at    := null;
  new.closed_at      := null;
  new.created_at     := now();
  new.updated_at     := now();
  new.subject        := btrim(new.subject);
  new.description    := btrim(new.description);
  return new;
end;
$$;

commit;
