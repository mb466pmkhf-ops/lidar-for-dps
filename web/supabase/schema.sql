-- FrameScan sync: one row per project. Run once in the Supabase SQL editor.
-- What syncs: project.json (`doc`) and the 2D plan of each scan (`plans`: walls, doors, windows,
-- set pieces). Scan meshes, textures and photos never leave the phone. See Docs/DECISIONS.md D-007.

create table if not exists public.framescan_projects (
  id          text primary key,                       -- the project's UUID, as the app writes it
  owner       uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null default '',
  doc         jsonb not null,
  plans       jsonb not null default '{}'::jsonb,
  rev         bigint not null default 1,              -- bumped on every write (compare-and-swap)
  deleted     boolean not null default false,
  updated_at  timestamptz not null default now(),
  updated_by  text
);



alter table public.framescan_projects enable row level security;

drop policy if exists "own rows: read" on public.framescan_projects;
drop policy if exists "own rows: insert" on public.framescan_projects;
drop policy if exists "own rows: update" on public.framescan_projects;
drop policy if exists "own rows: delete" on public.framescan_projects;

create policy "own rows: read"   on public.framescan_projects for select using (owner = (select auth.uid()));
create policy "own rows: insert" on public.framescan_projects for insert with check (owner = (select auth.uid()));
create policy "own rows: update" on public.framescan_projects for update using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy "own rows: delete" on public.framescan_projects for delete using (owner = (select auth.uid()));

-- Hardening (2026-11). Safe to run again on an existing install.
-- 1. Project ids are unique per account, not across the whole server: another account can't block
--    yours by taking an id first, and the same backup can be opened in two accounts.
alter table public.framescan_projects drop constraint if exists framescan_projects_pkey;
alter table public.framescan_projects add constraint framescan_projects_pkey primary key (owner, id);
drop index if exists public.framescan_projects_owner;  -- covered by the primary key

-- 2. Signed-out visitors get nothing; signed-in users get plain row access (RLS still applies).
revoke all on public.framescan_projects from anon;
revoke all on public.framescan_projects from authenticated;
grant select, insert, update, delete on public.framescan_projects to authenticated;

-- 3. Size limits, so one account can't fill the database. Real projects are a few hundred KB at most.
alter table public.framescan_projects drop constraint if exists framescan_projects_size;
alter table public.framescan_projects add constraint framescan_projects_size
  check (pg_column_size(doc) < 5000000 and pg_column_size(plans) < 20000000 and length(name) <= 500);

-- 4. Delete account (App Store rule 5.1.1(v): an app that creates accounts must let people delete
--    them). Removes the signed-in user's projects and the account itself. Projects stay on the
--    devices that have them. Runs with the owner's rights because users can't delete from auth.users.
create or replace function public.delete_my_account() returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  delete from public.framescan_projects where owner = uid;
  delete from auth.users where id = uid;
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
