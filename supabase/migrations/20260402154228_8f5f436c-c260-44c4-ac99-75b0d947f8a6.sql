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