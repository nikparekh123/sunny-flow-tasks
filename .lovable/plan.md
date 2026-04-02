

## Plan: Subtask Support

### Database Migration

```sql
CREATE TABLE public.subtasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  title text NOT NULL,
  done boolean NOT NULL DEFAULT false,
  assignee_id uuid,
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
```

### Types

Add to `src/lib/types.ts`:
- `Subtask` interface: `{ id, task_id, title, done, assignee_id, position, created_at }`
- Add `subtasks?: Subtask[]` to `TaskWithDetail`

### Data Hook — `src/hooks/useSubtasks.ts` (new)

- `useQuery` fetching all subtasks (or by task_id)
- `createSubtask` mutation (title, task_id, optional assignee_id)
- `toggleSubtask` mutation (update `done` field)
- `deleteSubtask` mutation
- Invalidate on success

### Task Hook — `src/hooks/useTasks.ts`

- Query subtasks alongside tasks; merge `subtasks[]` onto each `TaskWithDetail`
- In `moveTask`: when moving to `done`, check for incomplete subtasks. Add a `confirmCompleteSubtasks` option — if true, batch-update all subtasks to `done = true`

### UI — Task Detail Panel (`TaskDetailPanel.tsx`)

Add a "Subtasks" section below description:
- Checklist of existing subtasks: checkbox + title (strikethrough when done) + assignee avatar + delete icon (hover)
- "Add subtask" inline input at bottom with Enter-to-save
- When parent task is moved to done via the panel's column selector and has incomplete subtasks, show an `AlertDialog` confirmation: "This task has X incomplete subtasks. Mark them all as complete too?" with Yes/No

### UI — Task Card (`TaskCardContent.tsx`)

- If `task.subtasks?.length > 0`, show a small progress indicator in the footer area: "2/5" with a tiny progress bar (using the existing `Progress` component scaled down)

### UI — KanbanBoard / moveTask flow

- When dragging a task to "Done" column and it has incomplete subtasks, show the same confirmation dialog before completing the move

### Files Changed / Created

| File | Action |
|------|--------|
| Migration SQL | Create `subtasks` table with RLS |
| `src/lib/types.ts` | Add `Subtask` type, update `TaskWithDetail` |
| `src/hooks/useSubtasks.ts` | Create — CRUD for subtasks |
| `src/hooks/useTasks.ts` | Merge subtasks into tasks, confirmation logic |
| `src/components/board/TaskDetailPanel.tsx` | Subtask checklist UI + add/delete + completion prompt |
| `src/components/board/TaskCardContent.tsx` | Subtask progress indicator |
| `src/components/board/KanbanBoard.tsx` | Completion confirmation on drag-to-done |

