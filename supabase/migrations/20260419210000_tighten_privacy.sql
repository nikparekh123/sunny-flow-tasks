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
