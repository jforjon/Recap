-- Let a signed-in user delete their own account from inside the app.
--
-- WHY THIS EXISTS AS A FUNCTION. Deleting a user is an admin operation:
-- `auth.admin.deleteUser()` only accepts the service_role key, which bypasses
-- every row-level security policy. That key can never ship inside an app
-- binary — anyone could extract it and delete every account — so the client SDK
-- deliberately offers no "delete me" call.
--
-- A SECURITY DEFINER function is the way round it. It runs with its owner's
-- privileges rather than the caller's, so it can reach auth.users, but the only
-- row it will ever touch is auth.uid() — the caller's own. There is no argument
-- to tamper with.
--
-- App Store guideline 5.1.1(v) requires in-app account deletion for any app
-- that lets you create an account, so this is a shipping requirement, not a
-- nicety.
--
-- Idempotent. Run before shipping the build whose Account screen offers Delete.

begin;

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
-- An unpinned search_path on a SECURITY DEFINER function is a privilege
-- escalation hole: the caller could shadow `notes` with their own table and
-- have this function operate on it as the owner. Pin it.
set search_path = public, auth, pg_temp
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'delete_own_account must be called by a signed-in user';
  end if;

  -- Deleted explicitly, oldest dependency first, rather than leaning on
  -- ON DELETE CASCADE from auth.users. The CREATE TABLE statements for these
  -- tables predate this repo, so nothing here can verify those foreign keys
  -- actually cascade — and a deletion that silently orphans a user's notes is
  -- worse than no deletion at all. Explicit is also auditable: this list is the
  -- answer to "what does deleting my account remove?".
  --
  -- personal_notes first: its rows reference both notes and projects.
  delete from public.personal_notes where user_id = uid;
  delete from public.notes         where user_id = uid;
  delete from public.projects      where user_id = uid;
  delete from public.user_settings where user_id = uid;

  -- Last, and the only statement that needs the elevated privileges. Removing
  -- the auth row also drops the user's identities, sessions and refresh tokens.
  delete from auth.users where id = uid;
end;
$$;

-- Reachable only by a signed-in caller. `anon` must not have it: the function
-- would raise anyway on a null auth.uid(), but the grant is the real fence.
revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;

commit;
