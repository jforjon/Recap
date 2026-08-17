-- Personal notes can now hang off either a project or a single recording.
--
-- Before: personal_notes.project_id was NOT NULL, so a recording's personal
-- thoughts lived in notes.personal_reaction (one free-text field per recording).
-- After: personal_notes rows carry exactly one of project_id / note_id, and the
-- recording detail screen uses the same feed UI as a project.
--
-- Run this BEFORE shipping the app build that expects note_id, otherwise the
-- recording Notes tab will error on insert.

begin;

-- 1. New owner column, cascading so deleting a recording drops its notes.
alter table public.personal_notes
  add column if not exists note_id uuid
  references public.notes (id) on delete cascade;

-- 2. A row is now owned by a project OR a recording, so project_id is optional.
alter table public.personal_notes
  alter column project_id drop not null;

-- 3. Backfill: move each recording's existing "My thoughts" into the feed so
--    nothing the user already wrote disappears from the UI. reaction_type
--    already distinguishes voice from text, so carry it across.
insert into public.personal_notes (note_id, user_id, content, type, created_at)
select
  n.id,
  n.user_id,
  btrim(n.personal_reaction),
  coalesce(nullif(n.reaction_type::text, ''), 'text'),
  coalesce(n.created_at, now())
from public.notes n
where n.personal_reaction is not null
  and btrim(n.personal_reaction) <> ''
  -- Idempotent: re-running won't duplicate the backfilled rows.
  and not exists (
    select 1 from public.personal_notes p
    where p.note_id = n.id
      and p.content = btrim(n.personal_reaction)
  );

-- 4. Enforce exactly one owner per row.
alter table public.personal_notes
  drop constraint if exists personal_notes_one_owner;
alter table public.personal_notes
  add constraint personal_notes_one_owner
  check (num_nonnulls(project_id, note_id) = 1);

-- 5. Index the new lookup path (the feed queries eq(note_id)).
create index if not exists personal_notes_note_id_idx
  on public.personal_notes (note_id);

commit;
