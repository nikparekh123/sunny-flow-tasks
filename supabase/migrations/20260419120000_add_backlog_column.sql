-- Add 'backlog' to task_column enum.
-- Placed before 'todo' conceptually, but enum order is unchanged for existing values.
alter type public.task_column add value if not exists 'backlog' before 'todo';
