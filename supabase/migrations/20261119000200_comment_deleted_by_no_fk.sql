-- Hotfix: a second foreign key from ticket_comments to profiles (deleted_by)
-- made the PostgREST embed `author:profiles(full_name)` ambiguous, so loading
-- a ticket's comments failed. Keep the column (who deleted is still recorded)
-- but without the relationship.
alter table public.ticket_comments drop constraint if exists ticket_comments_deleted_by_fkey;
notify pgrst, 'reload schema';
