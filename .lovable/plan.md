

## Plan: Phased Board Overhaul — Phase 1

This is a large request spanning 6 feature areas. I recommend implementing it in two phases to keep things stable. **Phase 1** (this plan) covers the navbar refactor, project field, settings menu, and auth improvements. **Phase 2** (follow-up) covers real-time presence, file attachments, and invite email flow.

---

### Phase 1 Scope

#### 1. Add "project" column to tasks table

**Database migration:**
- Create an enum `task_project` with values: `admin_ops`, `sector_research`, `macro_research`, `company_research`, `technical_setup`, `live_positions`
- Add `project` column (nullable, type `task_project`) to `tasks` table
- Update `tasks_with_detail` view to include the `project` column

#### 2. Refactor TopBar into project filter tabs + user dropdown

**`src/lib/constants.ts`** — Add a `PROJECTS` array with id/label pairs matching the enum values.

**`src/components/board/TopBar.tsx`** — Complete rewrite:
- Replace the avatar stack and person filter pills with:
  - Project filter tabs: `All | Admin & Operations | Sector Research | Macro Research | Company Research | Technical Setup | Live Positions`
  - A "User" dropdown (using `DropdownMenu`) listing: Ary LaRocca, Nik Parekh, Kushal Jain, Rad Rahmouni (mapped to team members from DB). Selecting filters by assignee.
- Move "Sign out" into a Settings gear icon dropdown (top-right) with: Sign Out
- Keep the `+ New task` button

**`src/components/board/KanbanBoard.tsx`** — Update state/props:
- Add `activeProject` state (string | null)
- Pass to TopBar, filter tasks by `task.project === activeProject` (or show all if null)
- Update `filteredTasks` memo to combine project + assignee filters

#### 3. Add Project field to task panels

**`src/components/board/NewTaskPanel.tsx`** — Add a "Project" pill selector (same style as priority) using the `PROJECTS` constant. Default to null.

**`src/components/board/TaskDetailPanel.tsx`** — Add a Project `Select` dropdown in the details grid. On change, call `onUpdate({ id, project })`.

**`src/hooks/useTasks.ts`** — Update `createTask` and `updateTask` mutation types to include `project`.

#### 4. Replace dummy auth with email/password sign-up and sign-in

**`src/pages/Auth.tsx`** — Rewrite with two tabs (Sign In / Sign Up):
- Sign Up: first name, last name, email, password fields. Calls `supabase.auth.signUp` with `full_name` in metadata.
- Sign In: email, password. Calls `supabase.auth.signInWithPassword`.
- Remove anonymous sign-in entirely.

**`src/hooks/useAuth.tsx`** — `getOrCreateMember` already extracts `full_name` from metadata — no changes needed.

#### 5. Settings gear menu (top-right)

**`src/components/board/TopBar.tsx`** — Add a `Settings` (gear icon) button that opens a `DropdownMenu` with:
- Invite Users (placeholder for Phase 2)
- Personalization (placeholder)
- User Settings (placeholder)
- Admin Settings (placeholder)
- Sign Out (moved from current location)

---

### Files Changed

| File | Change |
|------|--------|
| **Migration SQL** | Add `task_project` enum, `project` column on `tasks`, update `tasks_with_detail` view |
| `src/lib/constants.ts` | Add `PROJECTS` array |
| `src/lib/types.ts` | Add `TaskProject` type, add `project` to `TaskWithDetail` |
| `src/components/board/TopBar.tsx` | Full rewrite: project tabs, user dropdown, settings gear |
| `src/components/board/KanbanBoard.tsx` | Add `activeProject` state, dual filtering |
| `src/components/board/NewTaskPanel.tsx` | Add project pill selector |
| `src/components/board/TaskDetailPanel.tsx` | Add project select dropdown |
| `src/hooks/useTasks.ts` | Add `project` to create/update mutations |
| `src/pages/Auth.tsx` | Email/password sign-up and sign-in (replace anonymous) |

### What's deferred to Phase 2
- Real-time user presence (green dots)
- Task attachments (file uploads, URLs, Google Drive)
- Invite Users flow (email sending)
- Permissions / private projects
- Personalization and admin settings panels

