
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
