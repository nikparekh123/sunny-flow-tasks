

## Plan: Pincode Auth, Task Improvements, Archive, and Admin Updates

### 1. Pincode Authentication System

**Database migration:**
- Add `pincode text` column to `team_members` table

**Update seed-users edge function** to include pincode mappings:
- 5499 → Ary LaRocca, 6617 → Nik Parekh, 2026 → Radhouen Rahmouni, 0987 → Kushal Jain

**New `src/pages/Auth.tsx`** — Complete rewrite:
- Single input field labeled "Enter your 4-digit code"
- Numeric-only, exactly 4 digits (use `InputOTP` component already in project)
- On submit: call a new edge function `pincode-login` that looks up the pincode in `team_members`, finds the corresponding `user_id`, gets email from auth admin API, and signs in with `signInWithPassword` using a stored password hash approach

**Better approach — edge function `pincode-login`:**
- Receives 4-digit code
- Queries `team_members` where `pincode = code`
- Uses service role to look up the user's email from `auth.users`
- Calls `auth.admin.generateLink({ type: 'magiclink' })` or returns a custom JWT
- Actually simplest: store email+password mapping in edge function, look up by pincode, call `signInWithPassword` server-side and return the session tokens

**Simplest secure approach:** The edge function receives the pincode, looks up the `team_members` row, gets `user_id`, uses admin API to generate a sign-in link/token, returns it. The client sets the session.

**Files:**
- `supabase/functions/pincode-login/index.ts` — New edge function
- `src/pages/Auth.tsx` — Rewrite to pincode UI
- Migration SQL — Add `pincode` column

### 2. Task Deletion Fix & Archive System

**Database migration:**
- Add `archived boolean DEFAULT false` and `archived_at timestamptz` columns to `tasks` table
- Update `tasks_with_detail` view to include `archived` and exclude archived tasks by default

**`src/hooks/useTasks.ts`:**
- Change `deleteTask` to set `archived = true, archived_at = now()` instead of hard delete
- Add `restoreTask` mutation (sets `archived = false`)
- Add `permanentlyDeleteTask` mutation
- Add `archivedTasks` query (fetches where `archived = true`)

**`src/components/board/KanbanBoard.tsx`:**
- Add `deletedTask` state for undo functionality
- On delete: show toast with "Undo" button, 30-second timer
- If undo clicked: call `restoreTask`

**New `src/components/board/ArchivePanel.tsx`:**
- Slide-out panel showing archived tasks
- Each task has "Restore" and "Delete permanently" buttons
- Triggered by Archive button in TopBar

**`src/components/board/TopBar.tsx`:**
- Add Archive icon button next to search icon

### 3. Task Editing with Save/Cancel

**`src/components/board/TaskDetailPanel.tsx`** — Refactor:
- Add `editing` boolean state (default false)
- In view mode: show read-only fields with an "Edit Task" button
- In edit mode: all fields become editable, show "Save Changes" and "Cancel" buttons
- Cancel reverts all local state to original task values
- Save calls `onUpdate` with all changed fields, then exits edit mode

### 4. Multi-Tag Search Filter

**`src/components/board/TopBar.tsx`:**
- Add a tag filter dropdown (multi-select) next to the search icon
- Selected tags filter tasks using AND logic

**`src/components/board/KanbanBoard.tsx`:**
- Add `activeTagIds` state
- In `filteredTasks` memo: if `activeTagIds.length > 0`, filter tasks that have ALL selected tags

### 5. Admin: Create Users with Pincode

**`src/components/settings/AdminSettingsModal.tsx`** — Expand:
- Add "Create User" section at top with fields: Name, 4-digit pincode
- On submit: call a new edge function `create-user` that creates auth user (with generated email like `pin_{code}@sunnyfi.local` and the pincode as password), creates team_member row with pincode
- Keep existing role/status management

**New `supabase/functions/create-user/index.ts`:**
- Receives name, pincode
- Creates auth user with service role
- Creates team_member with pincode, name, role=member

### 6. Invite Users Modal

**`src/components/board/TopBar.tsx`:**
- Wire up "Invite Users" menu item to open a modal

**New `src/components/settings/InviteUserModal.tsx`:**
- Fields: Name, 4-digit pincode
- Calls the same `create-user` edge function
- Shows success/error feedback

### 7. User Settings: Pincode Change

**`src/components/settings/UserSettingsModal.tsx`:**
- Add "Change Pincode" section
- Two inputs: new 4-digit code + confirm code
- On save: update `team_members.pincode` and update the auth user's password via edge function

### 8. UI Cleanup

**`src/components/board/TopBar.tsx`:**
- Remove "Personalization" from gear dropdown

---

### Files Changed / Created

| File | Action |
|------|--------|
| Migration SQL | Add `pincode` to `team_members`, add `archived`/`archived_at` to `tasks`, update view |
| `supabase/functions/pincode-login/index.ts` | Create — pincode auth |
| `supabase/functions/create-user/index.ts` | Create — admin user creation |
| `supabase/functions/seed-users/index.ts` | Update — add pincode values |
| `src/pages/Auth.tsx` | Rewrite — 4-digit pincode input |
| `src/hooks/useTasks.ts` | Add archive/restore mutations, undo logic |
| `src/components/board/KanbanBoard.tsx` | Archive button, undo toast, multi-tag filter state |
| `src/components/board/TopBar.tsx` | Archive icon, tag filter, remove Personalization |
| `src/components/board/TaskDetailPanel.tsx` | Edit mode with Save/Cancel |
| `src/components/board/ArchivePanel.tsx` | Create — archived tasks view |
| `src/components/settings/AdminSettingsModal.tsx` | Add create user form |
| `src/components/settings/InviteUserModal.tsx` | Create — invite user modal |
| `src/components/settings/UserSettingsModal.tsx` | Add pincode change |

