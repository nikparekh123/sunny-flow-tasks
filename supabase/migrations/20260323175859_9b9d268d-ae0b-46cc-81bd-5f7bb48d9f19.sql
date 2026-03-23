
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
