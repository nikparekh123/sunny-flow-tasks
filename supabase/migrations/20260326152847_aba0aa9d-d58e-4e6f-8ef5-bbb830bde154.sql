
-- Recurring tasks columns
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS recurrence text;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS brief text;

-- Tag colors
ALTER TABLE tags ADD COLUMN IF NOT EXISTS color text DEFAULT '#888888';

-- Notifications table
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  message text NOT NULL,
  task_id uuid REFERENCES public.tasks(id) ON DELETE SET NULL,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_notifications_select" ON public.notifications FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "own_notifications_insert" ON public.notifications FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_notifications_update" ON public.notifications FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "own_notifications_delete" ON public.notifications FOR DELETE TO authenticated USING (user_id = auth.uid());

-- Automation rules table
CREATE TABLE IF NOT EXISTS public.automation_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  trigger_type text NOT NULL,
  trigger_config jsonb NOT NULL DEFAULT '{}',
  action_type text NOT NULL,
  action_config jsonb NOT NULL DEFAULT '{}',
  active boolean NOT NULL DEFAULT true,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.automation_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_crud_select" ON public.automation_rules FOR SELECT TO authenticated USING (auth.role() = 'authenticated');
CREATE POLICY "auth_crud_insert" ON public.automation_rules FOR INSERT TO authenticated WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "auth_crud_update" ON public.automation_rules FOR UPDATE TO authenticated USING (auth.role() = 'authenticated');
CREATE POLICY "auth_crud_delete" ON public.automation_rules FOR DELETE TO authenticated USING (auth.role() = 'authenticated');

-- Tag update/delete RLS
CREATE POLICY "tags_authenticated_update" ON public.tags FOR UPDATE TO authenticated USING (auth.role() = 'authenticated');
CREATE POLICY "tags_authenticated_delete" ON public.tags FOR DELETE TO authenticated USING (auth.role() = 'authenticated');

-- Recreate tasks_with_detail view to include new columns
DROP VIEW IF EXISTS public.tasks_with_detail;
CREATE VIEW public.tasks_with_detail AS
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
  t.brief
FROM tasks t
LEFT JOIN task_categories tc ON t.category_id = tc.id
LEFT JOIN team_members tm ON t.assignee_id = tm.id
WHERE t.archived = false;

-- Enable realtime on notifications
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
