
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
