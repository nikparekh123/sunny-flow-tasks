-- ============================================================
-- Clean slate — safe to run on an empty database.
-- Drops anything a partial previous run may have left behind so
-- the full bundle can be re-run without "already exists" errors.
-- ============================================================

drop view if exists public.tasks_with_detail cascade;
drop table if exists public.subtasks cascade;
drop table if exists public.task_assignees cascade;
drop table if exists public.task_tags cascade;
drop table if exists public.notifications cascade;
drop table if exists public.automation_rules cascade;
drop table if exists public.tags cascade;
drop table if exists public.tasks cascade;
drop table if exists public.task_categories cascade;
drop table if exists public.team_members cascade;
drop table if exists public.member_pincodes cascade;
drop type  if exists public.task_visibility cascade;
drop type  if exists public.task_priority cascade;
drop type  if exists public.task_column cascade;
drop type  if exists public.member_role cascade;
drop type  if exists public.task_project cascade;
drop function if exists public.current_member_id() cascade;
drop function if exists public.update_updated_at() cascade;
drop function if exists public.reorder_task(uuid, public.task_column, integer) cascade;


-- ============================================================
-- 20260323175859_9b9d268d-ae0b-46cc-81bd-5f7bb48d9f19.sql
-- ============================================================


create extension if not exists "uuid-ossp";

create type public.task_column   as enum ('todo','inprogress','review','done');
create type public.task_priority as enum ('high','med','low');
create type public.member_role   as enum ('admin','member');

create table public.team_members (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid references auth.users(id) on delete cascade unique not null,
  name       text not null,
  initials   text not null,
  color      text default 'blue',
  role       member_role not null default 'member',
  created_at timestamptz default now()
);

create table public.task_categories (
  id         uuid primary key default uuid_generate_v4(),
  name       text not null,
  color      text not null default '#D85A30',
  position   integer default 0,
  created_at timestamptz default now()
);

create table public.tasks (
  id          uuid primary key default uuid_generate_v4(),
  title       text not null,
  description text,
  "column"    task_column   not null default 'todo',
  priority    task_priority not null default 'med',
  position    integer not null default 0,
  due_date    date,
  category_id uuid references task_categories(id) on delete set null,
  assignee_id uuid references team_members(id) on delete set null,
  created_by  uuid references team_members(id) on delete set null,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

create index tasks_column_position_idx on tasks ("column", position);

create or replace function public.update_updated_at()
returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;

create trigger tasks_updated_at
  before update on tasks
  for each row execute function update_updated_at();

create or replace function public.reorder_task(
  p_task_id  uuid,
  p_column   task_column,
  p_position integer
) returns void as $$
begin
  update tasks set position = position + 1
  where "column" = p_column and position >= p_position and id != p_task_id;
  update tasks set "column" = p_column, position = p_position
  where id = p_task_id;
end;
$$ language plpgsql security definer;

alter table public.team_members    enable row level security;
alter table public.task_categories enable row level security;
alter table public.tasks           enable row level security;

create policy "team_members: authenticated read" on team_members
  for select using (auth.role() = 'authenticated');

create policy "team_members: own insert" on team_members
  for insert with check (auth.uid() = user_id);

create policy "team_members: own update" on team_members
  for update using (auth.uid() = user_id);

create policy "task_categories: authenticated read" on task_categories
  for select using (auth.role() = 'authenticated');

create policy "task_categories: admin insert" on task_categories
  for insert with check (
    exists (
      select 1 from team_members
      where user_id = auth.uid() and role = 'admin'
    )
  );

create policy "task_categories: admin update" on task_categories
  for update using (
    exists (
      select 1 from team_members
      where user_id = auth.uid() and role = 'admin'
    )
  );

create policy "task_categories: admin delete" on task_categories
  for delete using (
    exists (
      select 1 from team_members
      where user_id = auth.uid() and role = 'admin'
    )
  );

create policy "tasks: authenticated read" on tasks
  for select using (auth.role() = 'authenticated');

create policy "tasks: authenticated insert" on tasks
  for insert with check (auth.role() = 'authenticated');

create policy "tasks: authenticated update" on tasks
  for update using (auth.role() = 'authenticated');

create policy "tasks: creator delete" on tasks
  for delete using (
    created_by in (
      select id from team_members where user_id = auth.uid()
    )
  );

alter publication supabase_realtime add table tasks;
alter publication supabase_realtime add table task_categories;

create or replace view public.tasks_with_detail as
select
  t.id, t.title, t.description, t."column", t.priority,
  t.position, t.due_date, t.created_at, t.updated_at,
  t.created_by,
  tc.id    as category_id,
  tc.name  as category_name,
  tc.color as category_color,
  tm.id       as assignee_id,
  tm.name     as assignee_name,
  tm.initials as assignee_initials,
  tm.color    as assignee_color
from tasks t
left join task_categories tc on tc.id = t.category_id
left join team_members    tm on tm.id = t.assignee_id
order by t."column", t.position;

insert into task_categories (name, color, position) values
  ('Sector Research',  '#D85A30', 0),
  ('Macro Research',   '#7F77DD', 1),
  ('Company Research', '#1D9E75', 2),
  ('Live Positions',   '#EF9F27', 3),
  ('Technical Setup',  '#E24B4A', 4),
  ('Admin & Operations','#888780',5);


-- ============================================================
-- 20260323175916_328f9b4a-378f-4cd9-ba45-400c198dabde.sql
-- ============================================================


drop view if exists public.tasks_with_detail;

create or replace view public.tasks_with_detail
with (security_invoker = true)
as
select
  t.id, t.title, t.description, t."column", t.priority,
  t.position, t.due_date, t.created_at, t.updated_at,
  t.created_by,
  tc.id    as category_id,
  tc.name  as category_name,
  tc.color as category_color,
  tm.id       as assignee_id,
  tm.name     as assignee_name,
  tm.initials as assignee_initials,
  tm.color    as assignee_color
from public.tasks t
left join public.task_categories tc on tc.id = t.category_id
left join public.team_members    tm on tm.id = t.assignee_id
order by t."column", t.position;

create or replace function public.update_updated_at()
returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql
set search_path = public;

create or replace function public.reorder_task(
  p_task_id  uuid,
  p_column   public.task_column,
  p_position integer
) returns void as $$
begin
  update public.tasks set position = position + 1
  where "column" = p_column and position >= p_position and id != p_task_id;
  update public.tasks set "column" = p_column, position = p_position
  where id = p_task_id;
end;
$$ language plpgsql security definer
set search_path = public;


-- ============================================================
-- 20260323201258_0b5dc84b-e77b-4a1b-a432-b8c7f8faf67b.sql
-- ============================================================


-- Create tags table
CREATE TABLE public.tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  created_at timestamptz DEFAULT now()
);

-- Create task_tags junction table
CREATE TABLE public.task_tags (
  task_id uuid REFERENCES public.tasks(id) ON DELETE CASCADE NOT NULL,
  tag_id uuid REFERENCES public.tags(id) ON DELETE CASCADE NOT NULL,
  PRIMARY KEY (task_id, tag_id)
);

-- Enable RLS
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_tags ENABLE ROW LEVEL SECURITY;

-- Tags: all authenticated can read
CREATE POLICY "tags: authenticated read" ON public.tags
  FOR SELECT USING (auth.role() = 'authenticated');

-- Tags: all authenticated can insert
CREATE POLICY "tags: authenticated insert" ON public.tags
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Task_tags: all authenticated can read
CREATE POLICY "task_tags: authenticated read" ON public.task_tags
  FOR SELECT USING (auth.role() = 'authenticated');

-- Task_tags: all authenticated can insert/delete
CREATE POLICY "task_tags: authenticated insert" ON public.task_tags
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "task_tags: authenticated delete" ON public.task_tags
  FOR DELETE USING (auth.role() = 'authenticated');

-- Enable realtime for tags
ALTER PUBLICATION supabase_realtime ADD TABLE public.tags;
ALTER PUBLICATION supabase_realtime ADD TABLE public.task_tags;

-- Seed default tags
INSERT INTO public.tags (name) VALUES
  ('fintech'), ('research'), ('macro'), ('positions'), ('ops');

-- Drop old view and recreate without category fields but with tags
DROP VIEW IF EXISTS public.tasks_with_detail;

CREATE OR REPLACE VIEW public.tasks_with_detail
WITH (security_invoker = true) AS
SELECT
  t.id, t.title, t.description, t.column, t.priority,
  t.position, t.due_date, t.created_at, t.updated_at,
  t.created_by,
  t.category_id,
  tc.name  AS category_name,
  tc.color AS category_color,
  tm.id       AS assignee_id,
  tm.name     AS assignee_name,
  tm.initials AS assignee_initials,
  tm.color    AS assignee_color
FROM public.tasks t
LEFT JOIN public.task_categories tc ON tc.id = t.category_id
LEFT JOIN public.team_members    tm ON tm.id = t.assignee_id;


-- ============================================================
-- 20260324144029_a3eeba6f-c490-4f9a-ac9c-f2cf6c309762.sql
-- ============================================================


DROP VIEW IF EXISTS public.tasks_with_detail;

CREATE TYPE public.task_project AS ENUM (
  'admin_ops',
  'sector_research',
  'macro_research',
  'company_research',
  'technical_setup',
  'live_positions'
);

ALTER TABLE public.tasks ADD COLUMN project public.task_project;

CREATE VIEW public.tasks_with_detail AS
SELECT t.id,
    t.title,
    t.description,
    t."column",
    t.priority,
    t."position",
    t.due_date,
    t.created_at,
    t.updated_at,
    t.created_by,
    t.category_id,
    tc.name AS category_name,
    tc.color AS category_color,
    tm.id AS assignee_id,
    tm.name AS assignee_name,
    tm.initials AS assignee_initials,
    tm.color AS assignee_color,
    t.project
   FROM tasks t
     LEFT JOIN task_categories tc ON tc.id = t.category_id
     LEFT JOIN team_members tm ON tm.id = t.assignee_id;


-- ============================================================
-- 20260324150837_e515683d-21ae-4665-9e73-5be0e2c1ff27.sql
-- ============================================================

ALTER TABLE public.team_members ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active';
ALTER TABLE public.team_members ADD COLUMN IF NOT EXISTS avatar_url text;
ALTER TABLE public.team_members ADD COLUMN IF NOT EXISTS preferences jsonb NOT NULL DEFAULT '{}';

CREATE POLICY "team_members: admin update any"
ON public.team_members
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.team_members tm
    WHERE tm.user_id = auth.uid() AND tm.role = 'admin'::member_role
  )
);

CREATE TABLE public.user_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  content text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_notes: own select"
ON public.user_notes FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "user_notes: own insert"
ON public.user_notes FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_notes: own update"
ON public.user_notes FOR UPDATE TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "user_notes: own delete"
ON public.user_notes FOR DELETE TO authenticated
USING (user_id = auth.uid());

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "avatars: authenticated upload"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "avatars: public read"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'avatars');

CREATE POLICY "avatars: own update"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'avatars');

CREATE POLICY "avatars: own delete"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'avatars');

-- ============================================================
-- 20260325142711_c63a56d8-14f3-459b-9693-e11365e13bef.sql
-- ============================================================

-- Add pincode column to team_members
ALTER TABLE public.team_members ADD COLUMN pincode text;
CREATE UNIQUE INDEX team_members_pincode_unique ON public.team_members (pincode) WHERE pincode IS NOT NULL;

-- Add archived columns to tasks
ALTER TABLE public.tasks ADD COLUMN archived boolean NOT NULL DEFAULT false;
ALTER TABLE public.tasks ADD COLUMN archived_at timestamptz;

-- Recreate the view to include archived flag and exclude archived tasks
CREATE OR REPLACE VIEW public.tasks_with_detail AS
SELECT t.id,
    t.title,
    t.description,
    t."column",
    t.priority,
    t."position",
    t.due_date,
    t.created_at,
    t.updated_at,
    t.created_by,
    t.category_id,
    tc.name AS category_name,
    tc.color AS category_color,
    tm.id AS assignee_id,
    tm.name AS assignee_name,
    tm.initials AS assignee_initials,
    tm.color AS assignee_color,
    t.project,
    t.archived,
    t.archived_at
FROM ((tasks t
    LEFT JOIN task_categories tc ON ((tc.id = t.category_id)))
    LEFT JOIN team_members tm ON ((tm.id = t.assignee_id)))
WHERE t.archived = false;

-- Allow authenticated users to update tasks (for archive operation)
-- The existing delete policy is restrictive (creator only), but archive is an update
-- Already have authenticated update policy, so we're good

-- RLS policy for tasks: allow authenticated delete (fix frozen tasks)
DROP POLICY IF EXISTS "tasks: creator delete" ON public.tasks;
CREATE POLICY "tasks: authenticated delete" ON public.tasks FOR DELETE TO public USING (auth.role() = 'authenticated'::text);

-- ============================================================
-- 20260326152847_aba0aa9d-d58e-4e6f-8ef5-bbb830bde154.sql
-- ============================================================


-- Recurring tasks columns
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS recurrence text;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS brief text;

-- Tag colors
ALTER TABLE tags ADD COLUMN IF NOT EXISTS color text DEFAULT '#888888';

-- Notifications table
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  message text NOT NULL,
  task_id uuid REFERENCES public.tasks(id) ON DELETE SET NULL,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_notifications_select" ON public.notifications FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "own_notifications_insert" ON public.notifications FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_notifications_update" ON public.notifications FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "own_notifications_delete" ON public.notifications FOR DELETE TO authenticated USING (user_id = auth.uid());

-- Automation rules table
CREATE TABLE IF NOT EXISTS public.automation_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  trigger_type text NOT NULL,
  trigger_config jsonb NOT NULL DEFAULT '{}',
  action_type text NOT NULL,
  action_config jsonb NOT NULL DEFAULT '{}',
  active boolean NOT NULL DEFAULT true,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.automation_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_crud_select" ON public.automation_rules FOR SELECT TO authenticated USING (auth.role() = 'authenticated');
CREATE POLICY "auth_crud_insert" ON public.automation_rules FOR INSERT TO authenticated WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "auth_crud_update" ON public.automation_rules FOR UPDATE TO authenticated USING (auth.role() = 'authenticated');
CREATE POLICY "auth_crud_delete" ON public.automation_rules FOR DELETE TO authenticated USING (auth.role() = 'authenticated');

-- Tag update/delete RLS
CREATE POLICY "tags_authenticated_update" ON public.tags FOR UPDATE TO authenticated USING (auth.role() = 'authenticated');
CREATE POLICY "tags_authenticated_delete" ON public.tags FOR DELETE TO authenticated USING (auth.role() = 'authenticated');

-- Recreate tasks_with_detail view to include new columns
DROP VIEW IF EXISTS public.tasks_with_detail;
CREATE VIEW public.tasks_with_detail AS
SELECT
  t.id,
  t.title,
  t.description,
  t."column",
  t.priority,
  t.position,
  t.due_date,
  t.created_at,
  t.updated_at,
  t.created_by,
  t.category_id,
  tc.name AS category_name,
  tc.color AS category_color,
  t.assignee_id,
  tm.name AS assignee_name,
  tm.initials AS assignee_initials,
  tm.color AS assignee_color,
  tm.avatar_url AS assignee_avatar_url,
  t.project,
  t.archived,
  t.archived_at,
  t.recurrence,
  t.brief
FROM tasks t
LEFT JOIN task_categories tc ON t.category_id = tc.id
LEFT JOIN team_members tm ON t.assignee_id = tm.id
WHERE t.archived = false;

-- Enable realtime on notifications
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;


-- ============================================================
-- 20260326152904_14b44de3-a034-4f0a-9286-55c880e9a674.sql
-- ============================================================


ALTER VIEW public.tasks_with_detail SET (security_invoker = on);


-- ============================================================
-- 20260401155432_ede8efd6-ba1b-414d-a613-7456c8c275e5.sql
-- ============================================================


-- 1. Fix role escalation: replace the permissive own-update policy
-- Drop the old policy that allows updating ANY column
DROP POLICY IF EXISTS "team_members: own update" ON public.team_members;

-- Create a restricted own-update policy that prevents role/status changes
-- Users can only update safe fields on their own row
CREATE POLICY "team_members: own update safe"
ON public.team_members
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (
  auth.uid() = user_id
  AND role = (SELECT tm.role FROM public.team_members tm WHERE tm.user_id = auth.uid())
  AND status = (SELECT tm.status FROM public.team_members tm WHERE tm.user_id = auth.uid())
);

-- 2. Fix avatar storage policies with ownership checks
-- Drop existing overly-permissive policies
DROP POLICY IF EXISTS "avatars: own delete" ON storage.objects;
DROP POLICY IF EXISTS "avatars: own update" ON storage.objects;
DROP POLICY IF EXISTS "avatars: authenticated upload" ON storage.objects;

-- Recreate with path-based ownership
CREATE POLICY "avatars: own upload"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "avatars: own update"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "avatars: own delete"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);


-- ============================================================
-- 20260401155637_e99ef8b9-2a95-42a8-8ac7-e4ec46d6861b.sql
-- ============================================================


-- Create separate pincodes table
CREATE TABLE public.member_pincodes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  pincode text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.member_pincodes ENABLE ROW LEVEL SECURITY;

-- Only own user can read their pincode
CREATE POLICY "own pincode select"
ON public.member_pincodes FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- Only own user can update their pincode
CREATE POLICY "own pincode update"
ON public.member_pincodes FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Migrate existing pincodes
INSERT INTO public.member_pincodes (user_id, pincode)
SELECT user_id, pincode FROM public.team_members WHERE pincode IS NOT NULL;

-- Drop pincode from team_members
ALTER TABLE public.team_members DROP COLUMN pincode;


-- ============================================================
-- 20260402154228_8f5f436c-c260-44c4-ac99-75b0d947f8a6.sql
-- ============================================================

-- Feature 1: Add completed_at to tasks
ALTER TABLE public.tasks ADD COLUMN completed_at timestamptz;

-- Backfill completed_at for existing done tasks
UPDATE public.tasks SET completed_at = updated_at WHERE "column" = 'done' AND completed_at IS NULL;

-- Feature 2: Create task_assignees junction table
CREATE TABLE public.task_assignees (
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  assignee_id uuid NOT NULL REFERENCES public.team_members(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, assignee_id)
);

ALTER TABLE public.task_assignees ENABLE ROW LEVEL SECURITY;

CREATE POLICY "task_assignees: authenticated select"
  ON public.task_assignees FOR SELECT
  USING (auth.role() = 'authenticated'::text);

CREATE POLICY "task_assignees: authenticated insert"
  ON public.task_assignees FOR INSERT
  WITH CHECK (auth.role() = 'authenticated'::text);

CREATE POLICY "task_assignees: authenticated delete"
  ON public.task_assignees FOR DELETE
  USING (auth.role() = 'authenticated'::text);

-- Migrate existing assignee_id data into junction table
INSERT INTO public.task_assignees (task_id, assignee_id)
SELECT id, assignee_id FROM public.tasks WHERE assignee_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- Recreate tasks_with_detail view to include completed_at
CREATE OR REPLACE VIEW public.tasks_with_detail AS
SELECT
  t.id,
  t.title,
  t.description,
  t."column",
  t.priority,
  t.position,
  t.due_date,
  t.created_at,
  t.updated_at,
  t.created_by,
  t.category_id,
  tc.name AS category_name,
  tc.color AS category_color,
  t.assignee_id,
  tm.name AS assignee_name,
  tm.initials AS assignee_initials,
  tm.color AS assignee_color,
  tm.avatar_url AS assignee_avatar_url,
  t.project,
  t.archived,
  t.archived_at,
  t.recurrence,
  t.brief,
  t.completed_at
FROM public.tasks t
LEFT JOIN public.task_categories tc ON t.category_id = tc.id
LEFT JOIN public.team_members tm ON t.assignee_id = tm.id
WHERE t.archived = false;

-- ============================================================
-- 20260402154835_02d30580-cb82-4f60-b87c-b536bea94c03.sql
-- ============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.task_assignees;

-- ============================================================
-- 20260402163451_dd233af4-aadc-4847-a569-7c0efb380f3e.sql
-- ============================================================

CREATE TABLE public.subtasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  title text NOT NULL,
  done boolean NOT NULL DEFAULT false,
  assignee_id uuid REFERENCES public.team_members(id),
  position integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.subtasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "subtasks: authenticated select" ON public.subtasks FOR SELECT TO authenticated
  USING (auth.role() = 'authenticated'::text);
CREATE POLICY "subtasks: authenticated insert" ON public.subtasks FOR INSERT TO authenticated
  WITH CHECK (auth.role() = 'authenticated'::text);
CREATE POLICY "subtasks: authenticated update" ON public.subtasks FOR UPDATE TO authenticated
  USING (auth.role() = 'authenticated'::text);
CREATE POLICY "subtasks: authenticated delete" ON public.subtasks FOR DELETE TO authenticated
  USING (auth.role() = 'authenticated'::text);

-- ============================================================
-- 20260419120000_add_backlog_column.sql
-- ============================================================

-- Add 'backlog' to task_column enum.
-- Placed before 'todo' conceptually, but enum order is unchanged for existing values.
alter type public.task_column add value if not exists 'backlog' before 'todo';


-- ============================================================
-- 20260419200000_add_task_visibility.sql
-- ============================================================

-- Add per-task visibility so certain cards are only visible to their creator + selected participants.

create type public.task_visibility as enum ('team', 'private');

alter table public.tasks
  add column visibility public.task_visibility not null default 'team',
  add column participant_ids uuid[] not null default '{}';

-- Helper: get the team_member id for the current auth user.
create or replace function public.current_member_id()
returns uuid
language sql stable
security definer
set search_path = public
as $$
  select id from public.team_members where user_id = auth.uid() limit 1
$$;

-- Refresh the view so clients receive the new columns.
drop view if exists public.tasks_with_detail;

create or replace view public.tasks_with_detail
with (security_invoker = true)
as
select
  t.id, t.title, t.description, t."column", t.priority,
  t.position, t.due_date, t.created_at, t.updated_at,
  t.created_by, t.visibility, t.participant_ids,
  t.archived, t.archived_at, t.category_id, t.assignee_id,
  t.project, t.recurrence, t.brief, t.completed_at,
  tc.name  as category_name,
  tc.color as category_color,
  tm.name     as assignee_name,
  tm.initials as assignee_initials,
  tm.color    as assignee_color,
  tm.avatar_url as assignee_avatar_url
from public.tasks t
left join public.task_categories tc on tc.id = t.category_id
left join public.team_members    tm on tm.id = t.assignee_id
where t.archived = false;

-- Replace tasks read/update/delete policies with visibility-aware ones.
drop policy if exists "tasks: authenticated read" on public.tasks;
drop policy if exists "tasks: authenticated update" on public.tasks;
drop policy if exists "tasks: authenticated delete" on public.tasks;

create policy "tasks: visibility read" on public.tasks
  for select to authenticated
  using (
    visibility = 'team'
    or created_by = public.current_member_id()
    or public.current_member_id() = any(participant_ids)
  );

create policy "tasks: visibility update" on public.tasks
  for update to authenticated
  using (
    visibility = 'team'
    or created_by = public.current_member_id()
    or public.current_member_id() = any(participant_ids)
  );

create policy "tasks: visibility delete" on public.tasks
  for delete to authenticated
  using (
    visibility = 'team'
    or created_by = public.current_member_id()
    or public.current_member_id() = any(participant_ids)
  );

-- Related tables: gate by whether the referenced task is visible to the caller.
-- task_assignees
drop policy if exists "task_assignees: authenticated read" on public.task_assignees;
drop policy if exists "task_assignees: authenticated select" on public.task_assignees;
create policy "task_assignees: visibility read" on public.task_assignees
  for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

-- task_tags
drop policy if exists "task_tags: authenticated read" on public.task_tags;
drop policy if exists "task_tags: authenticated select" on public.task_tags;
create policy "task_tags: visibility read" on public.task_tags
  for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

-- subtasks
drop policy if exists "subtasks: authenticated select" on public.subtasks;
create policy "subtasks: visibility read" on public.subtasks
  for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));


-- ============================================================
-- 20260419210000_tighten_privacy.sql
-- ============================================================

-- Lock down junction-table writes (insert/update/delete) on private tasks so
-- only users who can see the parent task can touch its related rows.

-- task_assignees
drop policy if exists "task_assignees: authenticated insert" on public.task_assignees;
drop policy if exists "task_assignees: authenticated update" on public.task_assignees;
drop policy if exists "task_assignees: authenticated delete" on public.task_assignees;

create policy "task_assignees: visibility insert" on public.task_assignees
  for insert to authenticated
  with check (exists (select 1 from public.tasks t where t.id = task_id));

create policy "task_assignees: visibility update" on public.task_assignees
  for update to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

create policy "task_assignees: visibility delete" on public.task_assignees
  for delete to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

-- task_tags
drop policy if exists "task_tags: authenticated insert" on public.task_tags;
drop policy if exists "task_tags: authenticated update" on public.task_tags;
drop policy if exists "task_tags: authenticated delete" on public.task_tags;

create policy "task_tags: visibility insert" on public.task_tags
  for insert to authenticated
  with check (exists (select 1 from public.tasks t where t.id = task_id));

create policy "task_tags: visibility update" on public.task_tags
  for update to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

create policy "task_tags: visibility delete" on public.task_tags
  for delete to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

-- subtasks
drop policy if exists "subtasks: authenticated insert" on public.subtasks;
drop policy if exists "subtasks: authenticated update" on public.subtasks;
drop policy if exists "subtasks: authenticated delete" on public.subtasks;

create policy "subtasks: visibility insert" on public.subtasks
  for insert to authenticated
  with check (exists (select 1 from public.tasks t where t.id = task_id));

create policy "subtasks: visibility update" on public.subtasks
  for update to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

create policy "subtasks: visibility delete" on public.subtasks
  for delete to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

-- (skipped duplicate: 20260420214807_904bd45b-9ee4-4fb2-bee7-5335181e5cd5.sql)
-- (skipped duplicate: 20260420214856_9e853805-2bf0-45cf-9c85-f6d8dbfe93b2.sql)
