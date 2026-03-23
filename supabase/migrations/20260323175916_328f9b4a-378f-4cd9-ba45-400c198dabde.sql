
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
