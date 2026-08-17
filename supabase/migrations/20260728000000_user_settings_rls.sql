-- Lock user_settings down to its owner.
--
-- No migration in this repo ever enabled row-level security on user_settings,
-- and the app talks to PostgREST with the anon key plus the user's JWT. Without
-- RLS, any signed-in user can select every row in the table — which, while the
-- table still holds anthropic_api_key, means every user's API key.
--
-- Safe to run now, before anything else ships: it only ever removes access.
-- Idempotent, so re-running is fine.

begin;

alter table public.user_settings enable row level security;

drop policy if exists user_settings_owner_select on public.user_settings;
create policy user_settings_owner_select on public.user_settings
  for select using (auth.uid() = user_id);

drop policy if exists user_settings_owner_insert on public.user_settings;
create policy user_settings_owner_insert on public.user_settings
  for insert with check (auth.uid() = user_id);

drop policy if exists user_settings_owner_update on public.user_settings;
create policy user_settings_owner_update on public.user_settings
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists user_settings_owner_delete on public.user_settings;
create policy user_settings_owner_delete on public.user_settings
  for delete using (auth.uid() = user_id);

commit;
