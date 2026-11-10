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

create index if not exists framescan_projects_owner on public.framescan_projects (owner);

alter table public.framescan_projects enable row level security;

drop policy if exists "own rows: read" on public.framescan_projects;
drop policy if exists "own rows: insert" on public.framescan_projects;
drop policy if exists "own rows: update" on public.framescan_projects;
drop policy if exists "own rows: delete" on public.framescan_projects;

create policy "own rows: read"   on public.framescan_projects for select using (owner = (select auth.uid()));
create policy "own rows: insert" on public.framescan_projects for insert with check (owner = (select auth.uid()));
create policy "own rows: update" on public.framescan_projects for update using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy "own rows: delete" on public.framescan_projects for delete using (owner = (select auth.uid()));
