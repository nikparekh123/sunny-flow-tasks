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