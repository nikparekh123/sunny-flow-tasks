-- Add pincode column to team_members
ALTER TABLE public.team_members ADD COLUMN pincode text;
CREATE UNIQUE INDEX team_members_pincode_unique ON public.team_members (pincode) WHERE pincode IS NOT NULL;

-- Add archived columns to tasks
ALTER TABLE public.tasks ADD COLUMN archived boolean NOT NULL DEFAULT false;
ALTER TABLE public.tasks ADD COLUMN archived_at timestamptz;

-- Recreate the view to include archived flag and exclude archived tasks
CREATE OR REPLACE VIEW public.tasks_with_detail AS
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
    t.project,
    t.archived,
    t.archived_at
FROM ((tasks t
    LEFT JOIN task_categories tc ON ((tc.id = t.category_id)))
    LEFT JOIN team_members tm ON ((tm.id = t.assignee_id)))
WHERE t.archived = false;

-- Allow authenticated users to update tasks (for archive operation)
-- The existing delete policy is restrictive (creator only), but archive is an update
-- Already have authenticated update policy, so we're good

-- RLS policy for tasks: allow authenticated delete (fix frozen tasks)
DROP POLICY IF EXISTS "tasks: creator delete" ON public.tasks;
CREATE POLICY "tasks: authenticated delete" ON public.tasks FOR DELETE TO public USING (auth.role() = 'authenticated'::text);