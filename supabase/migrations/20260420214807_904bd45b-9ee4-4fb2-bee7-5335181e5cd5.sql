-- Migration 1: add visibility + participants
create type public.task_visibility as enum ('team', 'private');

alter table public.tasks
  add column visibility public.task_visibility not null default 'team',
  add column participant_ids uuid[] not null default '{}';

create or replace function public.current_member_id()
returns uuid
language sql stable
security definer
set search_path = public
as $$
  select id from public.team_members where user_id = auth.uid() limit 1
$$;

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

drop policy if exists "task_assignees: authenticated read" on public.task_assignees;
drop policy if exists "task_assignees: authenticated select" on public.task_assignees;
create policy "task_assignees: visibility read" on public.task_assignees
  for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

drop policy if exists "task_tags: authenticated read" on public.task_tags;
drop policy if exists "task_tags: authenticated select" on public.task_tags;
create policy "task_tags: visibility read" on public.task_tags
  for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

drop policy if exists "subtasks: authenticated select" on public.subtasks;
create policy "subtasks: visibility read" on public.subtasks
  for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id));

-- Migration 2: tighten writes on related tables
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

NOTIFY pgrst, 'reload schema';