-- Edit and delete chat comments.
--
-- * Edit:   only the author, only while the comment is not deleted.
--           Sets edited_at; no new email is sent.
-- * Delete: the author, or an administrator / superadmin (moderation).
--           Soft delete: the row stays (audit / timeline order) but the
--           original text is erased and replaced by a placeholder.
--
-- Clients still have no UPDATE / DELETE privilege on ticket_comments; all
-- changes go through these SECURITY DEFINER functions, which enforce the rules.
-- New columns are nullable, so existing backups restore unchanged.

alter table public.ticket_comments
  add column if not exists edited_at  timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null;

create or replace function public.edit_comment(p_comment_id uuid, p_content text)
returns public.ticket_comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row     public.ticket_comments;
  v_content text := btrim(coalesce(p_content, ''));
begin
  if not private.is_active_user() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if length(v_content) < 1 or length(v_content) > 5000 then
    raise exception 'Komentar harus 1 sampai 5000 karakter' using errcode = '22023';
  end if;

  select * into v_row from public.ticket_comments where id = p_comment_id for update;
  -- Same answer for "missing" and "not yours".
  if not found or v_row.author_id is distinct from auth.uid() then
    raise exception 'Komentar tidak ditemukan' using errcode = 'P0002';
  end if;
  if v_row.deleted_at is not null then
    raise exception 'Komentar sudah dihapus' using errcode = '22023';
  end if;
  if v_row.content = v_content then
    return v_row;
  end if;

  update public.ticket_comments
     set content = v_content, edited_at = now()
   where id = p_comment_id
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.delete_comment(p_comment_id uuid)
returns public.ticket_comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.ticket_comments;
begin
  if not private.is_active_user() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;

  select * into v_row from public.ticket_comments where id = p_comment_id for update;
  if not found
     or (v_row.author_id is distinct from auth.uid()
         and not private.is_admin()
         and not private.is_superadmin()) then
    raise exception 'Komentar tidak ditemukan' using errcode = 'P0002';
  end if;
  if v_row.deleted_at is not null then
    return v_row;
  end if;

  update public.ticket_comments
     set content = '[dihapus]', deleted_at = now(), deleted_by = auth.uid()
   where id = p_comment_id
  returning * into v_row;
  return v_row;
end;
$$;

revoke all on function public.edit_comment(uuid, text)  from public, anon;
revoke all on function public.delete_comment(uuid)      from public, anon;
grant execute on function public.edit_comment(uuid, text) to authenticated;
grant execute on function public.delete_comment(uuid)     to authenticated;
