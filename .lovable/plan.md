

## SunnyFi Kanban Task App

A shared internal Kanban board for SunnyFi's investment team with real-time collaboration, role-based access, and drag-and-drop task management.

### Authentication & Onboarding
- Login/signup page with Supabase Auth (email/password)
- On first login, auto-create a `team_members` record with name, initials, and default "member" role
- No user profiles beyond what's in `team_members`

### Database Setup
- Run the provided SQL schema: `team_members`, `task_categories`, `tasks` tables with enums, RLS policies, the `reorder_task` RPC, `tasks_with_detail` view, and default categories
- Enable Supabase Realtime on `tasks` and `task_categories`

### Board Layout (Main Page)
- **Top bar**: "Team Board" title, overlapping team avatar stack (initials, 26px), category filter pills ("All" + one per category), admin-only gear icon for category management, "+ New task" button pinned right
- **4 fixed columns**: To Do → In Progress → Review → Done
- Each column header: colored status dot, name (Inter 500 12px muted), task count pill
- Column dot colors: To Do #378ADD, In Progress #EF9F27, Review #7F77DD, Done #639922

### Task Cards
- Title (Inter 500 12px), priority dot (top-right), category pill (tinted background from category color), footer with due date (red if overdue) and assignee initials avatar
- Done column: strikethrough title, 55% opacity
- Hover: "⋯" menu with Edit and Delete options
- Drag-and-drop via `@dnd-kit/core` + `@dnd-kit/sortable` — ghost at 40% opacity, grab/grabbing cursors

### Task Creation
- **Quick-add**: "+ Add task" button at bottom of To Do column only — inline title input, creates with defaults (To Do, Med priority, no assignee/category)
- **Full form**: "+ New task" top bar button opens right slide-over panel with Title, Category dropdown, Priority toggle (High/Med/Low), Due date picker, Assignee dropdown, Description textarea, Save/Cancel

### Card Detail Slide-over
- Opens on card click — right slide-over panel
- Editable inline: Title, Status, Priority, Category, Assignee, Due Date in 2-column grid, Description textarea below
- No delete button in slide-over (only via card hover menu)

### Category Management (Admin Only)
- Gear icon in top bar (hidden from members) opens modal
- List of categories with color dot, name, hover actions (rename/delete)
- "+ Add category" with inline input, auto-assigned colors from the defined sequence
- Delete sets tasks' `category_id` to null with confirmation
- Rename via inline edit

### Drag & Drop
- Cards draggable within and between all 4 columns using @dnd-kit
- On drop: call `reorder_task` RPC to update column and position
- Realtime sync ensures all teammates see moves instantly

### Realtime
- Subscribe to `tasks` and `task_categories` tables
- Board auto-updates when any teammate moves cards or admin modifies categories

### Design
- Font: Inter 300–500 throughout, no serif
- Board bg: #f7f7f5, cards: white with 0.5px #e8e8e8 border (hover #d0d0d0)
- Text: #1a1a1a primary, #6b6b6b muted, #999 tertiary
- Active filter pill: #1a1a1a bg, white text
- No dark mode

