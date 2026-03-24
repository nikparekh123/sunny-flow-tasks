

## Plan: Major Feature Expansion — Phased Approach

This request contains 7+ major features. To keep the app stable, I recommend splitting into **3 phases**. Here is **Phase 2A** — the highest-impact items that build on what exists.

---

### Phase 2A Scope (This Plan)

#### 1. Seed the 4 users via edge function

Since we cannot create auth users via client-side code or migrations, create an edge function `seed-users` that uses the Supabase Admin API (`supabase.auth.admin.createUser`) to create:

| Name | Email | Password | Role |
|------|-------|----------|------|
| Nik Parekh | nik@sunnyfi.co | niknik | admin |
| Ary LaRocca | ary@sunnyfi.co | aryary | admin |
| Rad Rahmouni | rad@sunnyfi.co | radrad | member |
| Kushal Jain | kushal@sunnyfi.co | kushalkushal | member |

The function creates auth users with `email_confirm: true`, then upserts `team_members` rows with the correct `role` (admin/member). It's idempotent — skips users that already exist.

**Enable auto-confirm** for email signups so these users can sign in immediately.

**File:** `supabase/functions/seed-users/index.ts`

#### 2. Role-based settings menu

**`src/components/board/TopBar.tsx`** — Read `member.role` from `useAuth()`. Conditionally show/hide menu items:
- **Admin**: sees all items (Invite Users, Personalization, User Settings, Admin Settings, Sign Out)
- **Member**: sees Invite Users, Personalization, User Settings, Sign Out — no Admin Settings

#### 3. Left sidebar with project navigation + Dashboard

**Database migration:**
- Create `user_notes` table: `id uuid PK, user_id uuid NOT NULL, content text, updated_at timestamptz`
- RLS: users can only CRUD their own notes (`user_id = auth.uid()`)

**New files:**
- `src/components/layout/AppSidebar.tsx` — Left sidebar using the existing Sidebar component with:
  - "Dashboard" link at top
  - Project sections (Admin & Operations, Sector Research, etc.) — clicking navigates/filters to that project
  - Collapsible with icon mode
- `src/pages/Dashboard.tsx` — User-centric view with:
  - Task widget: shows tasks assigned to current user, grouped by status
  - Notes widget: private textarea that auto-saves to `user_notes` table

**Modified files:**
- `src/App.tsx` — Add routes: `/` (Dashboard), `/board` (KanbanBoard), wrap in `SidebarProvider`
- `src/pages/Index.tsx` — Update routing logic

#### 4. Refactor top-right user filter with avatars + eye icon

**`src/components/board/TopBar.tsx`**:
- Replace "All Users" button with a row of small avatar circles (from `members` data)
- Add an `Eye` icon button next to avatars that opens a dropdown with "All Users" + individual user filter options
- Avatars are dynamically driven from `team_members` table

#### 5. User Settings modal

**New file:** `src/components/settings/UserSettingsModal.tsx`
- Dialog with fields: Name (editable), Email (read-only), Status toggle (active/inactive stored in `team_members`), Avatar upload (to storage bucket), notification preferences (stored in new `user_preferences` JSON column on `team_members`)
- Save updates to `team_members` table

**Database migration:**
- Add `status text DEFAULT 'active'` and `avatar_url text` and `preferences jsonb DEFAULT '{}'` columns to `team_members`
- Create `avatars` storage bucket

#### 6. Admin Settings panel (admin-only)

**New file:** `src/components/settings/AdminSettingsModal.tsx`
- Shows all users with their roles
- Admins can toggle role between admin/member (updates `team_members.role`)
- Shows user status, can deactivate users

### Deferred to Phase 2B
- Email notifications on task assignment (requires edge function + email infrastructure)
- Admin Reports/Analytics dashboard
- Invite Users flow (email sending)

---

### Files Changed / Created

| File | Action |
|------|--------|
| `supabase/functions/seed-users/index.ts` | Create — seed 4 users |
| Migration SQL | Create `user_notes` table, add columns to `team_members`, create storage bucket |
| `src/components/layout/AppSidebar.tsx` | Create — left sidebar navigation |
| `src/pages/Dashboard.tsx` | Create — user dashboard with tasks + notes |
| `src/components/settings/UserSettingsModal.tsx` | Create — user settings dialog |
| `src/components/settings/AdminSettingsModal.tsx` | Create — admin user management |
| `src/components/board/TopBar.tsx` | Modify — role-based menu, avatar filter UI |
| `src/App.tsx` | Modify — add sidebar layout, new routes |
| `src/pages/Index.tsx` | Modify — routing updates |
| `src/hooks/useAuth.tsx` | Minor — expose `member.role` check |
| `src/lib/types.ts` | Update — add new fields |

