

## Plan: Full Feature & UI Enhancement Pass

This is a large update spanning 9 feature areas. Here's the implementation plan.

---

### Database Migration

Add the following schema changes in a single migration:

```sql
-- Recurring tasks
ALTER TABLE tasks ADD COLUMN recurrence text; -- 'daily','weekly','biweekly','monthly' or null
ALTER TABLE tasks ADD COLUMN brief text; -- short preview text, max 150 chars

-- Notifications table
CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  message text NOT NULL,
  task_id uuid,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own notifications" ON public.notifications FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- Rules/automation table
CREATE TABLE public.automation_rules (
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
CREATE POLICY "auth crud" ON public.automation_rules FOR ALL TO authenticated
  USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');

-- Tag colors
ALTER TABLE tags ADD COLUMN color text DEFAULT '#888888';

-- Update tasks_with_detail view to include recurrence and brief
```

Recreate the `tasks_with_detail` view to include `recurrence` and `brief` columns.

Enable realtime on `notifications` table.

---

### Task 1 — Recurring Tasks

**`NewTaskPanel.tsx`** and **`TaskDetailPanel.tsx`**: Add a "Recurring" toggle. When enabled, show a select for frequency (Daily, Weekly, Bi-weekly, Monthly). Store in `recurrence` column.

**`TaskCardContent.tsx`**: Show a small `Repeat` icon (from lucide) next to the title when `task.recurrence` is set.

**`useTasks.ts`**: When moving a task to "done" column AND `recurrence` is set, auto-create a new task with the same fields but next due date calculated from frequency. Use a helper function:
- Daily: +1 day
- Weekly: +7 days
- Bi-weekly: +14 days
- Monthly: +1 month

**`types.ts`**: Add `recurrence` and `brief` to `TaskWithDetail`.

---

### Task 2 — Fix Today/Tomorrow/Overdue Display

**`TaskCardContent.tsx`**: Replace the current `isPast` check with:
```ts
const today = startOfDay(new Date());
const dueDay = startOfDay(parseISO(task.due_date));
const isToday = isSameDay(dueDay, today);
const isTomorrow = isSameDay(dueDay, addDays(today, 1));
const isOverdue = isBefore(dueDay, today);
```
Display: "Today" in green, "Tomorrow" in neutral, past dates in red with "overdue".

Apply same logic in `TaskDetailPanel.tsx` due date display.

---

### Task 3 — Rules & Automation

**New file `src/pages/RulesPage.tsx`**: Full-page rules manager with:
- List of rules in card layout (name, trigger summary, action summary, active toggle)
- "Create Rule" button opens a builder modal
- Builder has: Rule name, Trigger type dropdown, dynamic config fields, Action type dropdown, dynamic config fields
- Edit and delete per rule

**Trigger types**: `task_assigned`, `task_moved`, `task_overdue`, `task_created`, `task_completed`, `tag_added`

**Action types**: `assign_user`, `move_to_column`, `add_tag`, `send_notification`, `set_due_date`, `remove_assignee`

**New file `src/hooks/useRules.ts`**: CRUD operations on `automation_rules` table.

**`useTasks.ts`**: After `createTask`, `updateTask`, and `moveTask` succeed, fetch active rules and evaluate triggers. Execute matching actions. Include a guard to prevent infinite loops (max 1 rule execution depth per action).

**`TopBar.tsx`**: Add "Rules" option in the gear dropdown. Opens `/rules` route or a modal.

**`App.tsx`**: Add `/rules` route.

---

### Task 4 (numbered 5 in request) — Notifications System

**New file `src/components/board/NotificationBell.tsx`**: Bell icon with red badge for unread count. Click opens dropdown panel showing notifications list with relative timestamps, message text, and click-to-navigate.

**New file `src/hooks/useNotifications.ts`**: 
- Query `notifications` table filtered to current user
- Subscribe to realtime changes
- `markAllRead` mutation
- `markRead` mutation

**`TopBar.tsx`**: Add `NotificationBell` component next to search icon.

**Notification triggers** (in `useTasks.ts`):
- On task assignment/reassignment: insert notification for assignee
- On task overdue: handled by rules system or a periodic check

---

### Task 5 (numbered 6) — Brief Field & Preview on Banners

**`TaskCardContent.tsx`**: Below the title, show `task.brief` in a muted, truncated 1-2 line preview. If no brief, show nothing (not a placeholder).

**`NewTaskPanel.tsx`** and **`TaskDetailPanel.tsx`**: Add "Brief" text input (max 150 chars) between title and description.

**`useTasks.ts`**: Include `brief` in create/update mutations.

---

### Task 6 (numbered 7) — Tag Management

**A. Tag Settings Modal** — New file `src/components/settings/TagManagementModal.tsx`:
- List all tags with editable name, color picker (preset swatches), and delete button
- Delete shows confirmation, removes from `task_tags` junction table too
- Accessible from tag dropdown in task panels ("Manage Tags" option at bottom)

**B. Tag Search**: In `TaskDetailPanel.tsx` and `NewTaskPanel.tsx`, add a searchable input that filters the tag list by name.

**`useTasks.ts`**: Add `updateTag` and `deleteTag` mutations.

**Migration**: Add RLS policies for tag UPDATE and DELETE for authenticated users.

---

### Task 7 (numbered 8) — Gantt Chart & Calendar Views

**New file `src/components/board/GanttView.tsx`**: 
- Horizontal timeline with task bars spanning creation date to due date
- Grouped by column/status or assignee (toggle)
- Click bar opens task detail
- Tasks without due date shown in "Unscheduled" section below

**New file `src/components/board/CalendarView.tsx`**:
- Monthly calendar grid
- Tasks appear as colored pills on due dates
- Previous/Next month navigation
- Click task opens detail modal

**`TopBar.tsx`** or **`KanbanBoard.tsx`**: Add view toggle buttons (Board icon, Gantt icon, Calendar icon) next to "SunnyFi Board" title. Use icons from lucide: `LayoutGrid`, `GanttChart`, `CalendarDays`.

**State management**: Add `activeView` state in parent component. Conditionally render `KanbanBoard` grid, `GanttView`, or `CalendarView`.

---

### Task 8 (numbered 9) — Sync User Icons with Profile Photos

**`TaskCardContent.tsx`**: The assignee avatar already uses `assignee_color` and `assignee_initials`. The `tasks_with_detail` view doesn't include `avatar_url`. 

**Fix**: Update the `tasks_with_detail` view to include `tm.avatar_url as assignee_avatar_url`. Add to `TaskWithDetail` type. Use `Avatar` component with `AvatarImage` fallback to initials everywhere assignees are shown.

---

### Task 9 — Error Detection & Fix Pass

After all features are implemented:
- Verify recurring task regeneration doesn't create duplicates (guard with a `regenerated_from` column or check)
- Verify date logic consistency across all views
- Add rule execution depth guard (prevent infinite loops)
- Handle null/missing dates gracefully in Gantt and Calendar views
- Test tag deletion cascade
- Verify notification badge clears correctly
- Check responsive layouts

---

### Files Changed / Created

| File | Action |
|------|--------|
| Migration SQL | Add columns, create tables, update view |
| `src/lib/types.ts` | Add `recurrence`, `brief`, `assignee_avatar_url` |
| `src/hooks/useTasks.ts` | Add recurring regeneration, brief, notification triggers, tag CRUD |
| `src/hooks/useNotifications.ts` | Create — notification queries |
| `src/hooks/useRules.ts` | Create — rules CRUD |
| `src/components/board/TaskCardContent.tsx` | Brief preview, recurring icon, fix date logic, avatar photo |
| `src/components/board/TopBar.tsx` | Notification bell, Rules menu item, view toggles |
| `src/components/board/KanbanBoard.tsx` | View state, pass data to Gantt/Calendar |
| `src/components/board/NewTaskPanel.tsx` | Recurring toggle, brief field, tag search |
| `src/components/board/TaskDetailPanel.tsx` | Recurring toggle, brief field, tag search, date display fix |
| `src/components/board/NotificationBell.tsx` | Create — bell icon + dropdown |
| `src/components/board/GanttView.tsx` | Create — Gantt chart |
| `src/components/board/CalendarView.tsx` | Create — Calendar view |
| `src/components/settings/TagManagementModal.tsx` | Create — tag CRUD modal |
| `src/pages/RulesPage.tsx` | Create — rules management |
| `src/App.tsx` | Add /rules route |
| Tags migration | Add UPDATE/DELETE RLS policies |

