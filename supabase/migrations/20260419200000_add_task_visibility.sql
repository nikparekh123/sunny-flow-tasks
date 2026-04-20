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
