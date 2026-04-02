

## Plan: 6-Feature Update — Paginated Done, Multi-Assignee, Gantt Improvements, Custom Recurrence, and Rule Execution

---

### Feature 1 — Paginated Done Column with Sort by Completion Date

**Database migration:**
- Add `completed_at timestamptz` column to `tasks` table
- Update `tasks_with_detail` view to include `completed_at`

**`src/hooks/useTasks.ts`:**
- In `moveTask` mutation: when moving to `done`, set `completed_at = now()`. When moving out of `done`, set `completed_at = null`.

**`src/components/board/BoardColumn.tsx`:**
- Accept a `pageSize` prop (default 20 for done column)
- Add `visibleCount` state, initially 20
- Slice tasks to `visibleCount` for done column
- Show "See more" button at bottom when there are more tasks; clicking appends 20 more
- Sort done column tasks by `completed_at` descending

**`src/lib/types.ts`:** Add `completed_at: string | null` to `TaskWithDetail`.

---

### Feature 2 — Multiple Assignees per Task

**Database migration:**
- Create `task_assignees` table: `task_id uuid NOT NULL, assignee_id uuid NOT NULL, PRIMARY KEY (task_id, assignee_id)`
- Add RLS policies for authenticated users (select, insert, delete)
- Migrate existing `assignee_id` data into `task_assignees`
- Keep `assignee_id` on `tasks` for backward compat (will be ignored in favor of junction table)

**`src/hooks/useTasks.ts`:**
- Add `useQuery` for `task_assignees` (like `task_tags`)
- Map each task's assignees from the junction table + `members` list
- Update `createTask` and `updateTask` to accept `assignee_ids: string[]` and sync the junction table
- Update notification logic to notify all assignees

**`src/lib/types.ts`:**
- Add to `TaskWithDetail`: `assignee_ids: string[]`, `assignees: { id: string; name: string; initials: string; color: string | null; avatar_url: string | null }[]`

**`src/components/board/NewTaskPanel.tsx`:**
- Convert assignee picker from single-select buttons to multi-select checkboxes/tokens

**`src/components/board/TaskDetailPanel.tsx`:**
- Convert assignee field to multi-select in edit mode
- Display all assignees in read mode

**`src/components/board/TaskCardContent.tsx`:**
- Show stacked avatars for all assignees (up to 3 visible + "+N" overflow)

**`src/components/board/KanbanBoard.tsx`:**
- Update assignee filter to match if current user is ANY of the task's assignees

**`src/components/board/GanttView.tsx` and `CalendarView.tsx`:**
- Update to show multiple assignee avatars

**`tasks_with_detail` view:** Keep as-is for primary assignee display; the multiple assignees come from the client-side join with `task_assignees`.

---

### Feature 3 — Gantt Chart: Larger Fonts + Full-Screen Mode

**`src/components/board/GanttView.tsx`:**
- Increase all font sizes by ~25%: task labels from `10px` to `12px`, date headers from `8px` to `10px`, group labels accordingly
- Add a fullscreen toggle button in the toolbar area
- When fullscreen: render the Gantt in a fixed full-viewport overlay (`position: fixed; inset: 0; z-index: 50`) with a close/escape button
- Listen for `Escape` key to exit fullscreen via `useEffect`

---

### Feature 4 — Recurring Tasks: Add Custom Option

Recurring tasks already exist (Daily, Weekly, Bi-weekly, Monthly). Add:

**`src/lib/types.ts`:** Expand `RecurrenceFrequency` to include `'custom'`.

**`src/components/board/NewTaskPanel.tsx` and `TaskDetailPanel.tsx`:**
- Add "Custom" option in the recurrence select
- When "Custom" is selected, show day-of-week checkboxes (Mon–Sun) and/or day-of-month input
- Store custom config as JSON string in `recurrence` field (e.g. `custom:{"days":["mon","wed"]}`)

**`src/hooks/useTasks.ts`:**
- Update `calcNextDueDate` to handle custom recurrence by finding the next matching day

---

### Feature 5 — Weekly View in Gantt Chart

**`src/components/board/GanttView.tsx`:**
- Add a view-switcher in the Gantt toolbar: "Week" (alongside existing default)
- In week mode:
  - Show exactly 7 columns (Mon–Sun) for the selected week
  - Add "← Prev" and "Next →" buttons to shift by 7 days
  - Add "Today" button to snap to current week
  - Highlight today's column with a distinct background
  - Each column = 1 day with wider width for readability

---

### Feature 6 — Bug Fix: Automation Rules Not Executing

**Root cause:** Rules are saved to the database but there is NO rule evaluation engine anywhere in the code. `useTasks.ts` mutations never check rules after task changes.

**Fix — add rule evaluation in `src/hooks/useTasks.ts`:**
- Create a `useRuleEngine` helper or inline function that:
  1. Fetches active rules from the `automation_rules` table
  2. After `createTask`, `updateTask`, and `moveTask` succeed, evaluates trigger conditions
  3. For matching rules, executes the action (assign user, move column, add tag, send notification, remove assignee)
  4. Includes a depth guard (max 1 level) to prevent infinite loops
  5. Logs rule execution to console for debugging

**Trigger mapping:**
- `task_created` → fires after `createTask` succeeds
- `task_assigned` → fires after `updateTask`/`createTask` when `assignee_id` changes to match config
- `task_moved` → fires after `moveTask` when target column matches config
- `task_completed` → fires after `moveTask` when column = `done`
- `tag_added` → fires after tag changes when new tag matches config

**Action execution:**
- `assign_user` → update task's assignee(s)
- `move_to_column` → call `reorder_task` RPC
- `add_tag` → insert into `task_tags`
- `send_notification` → insert into `notifications`
- `remove_assignee` → clear assignee(s)

---

### Files Changed / Created

| File | Action |
|------|--------|
| Migration SQL | Add `completed_at`, create `task_assignees`, update view |
| `src/lib/types.ts` | Add `completed_at`, `assignee_ids`, `assignees`, expand `RecurrenceFrequency` |
| `src/hooks/useTasks.ts` | Paginated done sort, multi-assignee CRUD, rule engine, custom recurrence |
| `src/components/board/BoardColumn.tsx` | Paginated "See more" for done column |
| `src/components/board/TaskCardContent.tsx` | Stacked multi-assignee avatars |
| `src/components/board/NewTaskPanel.tsx` | Multi-select assignee, custom recurrence UI |
| `src/components/board/TaskDetailPanel.tsx` | Multi-select assignee, custom recurrence UI |
| `src/components/board/GanttView.tsx` | Larger fonts, fullscreen mode, weekly view |
| `src/components/board/KanbanBoard.tsx` | Multi-assignee filter, done sort logic |
| `src/components/board/CalendarView.tsx` | Multi-assignee display |

