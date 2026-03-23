

## Plan: Six Fixes for the Kanban Board

### 1. Bolder column headers
**`src/components/board/BoardColumn.tsx`** — Change column label from `font-medium text-muted-foreground` to `font-semibold text-foreground`.

### 2. Replace assignee dropdown with pill buttons in New Task panel
**`src/components/board/NewTaskPanel.tsx`**:
- Remove the `Select` dropdown for assignee
- Replace with clickable pill buttons (same style as priority buttons) showing each member's name
- Default `assigneeId` to `currentMemberId` instead of `'none'`
- Add an "Unassigned" pill as the first option

### 3. Fix ghost/transparent card during drag
**`src/components/board/TaskCard.tsx`** — When `isDragging` is true, set `opacity: 0` and `pointerEvents: 'none'` so the placeholder is invisible. Only the `DragOverlay` copy is visible.

**`src/components/board/TaskCardContent.tsx`** — Remove the `isDragging` opacity logic (line 30: `opacity: isDragging ? 0.4 : ...`). The `isDragging` prop is no longer needed for opacity since the parent wrapper handles hiding.

### 4. Remove user name next to "Sign out"
**`src/components/board/TopBar.tsx`** — Remove line 78 (`<span>` showing `member?.name`).

### 5. Color-code cards by priority
**`src/components/board/TaskCardContent.tsx`** — Add a subtle left border or soft background tint based on priority:
- High: `border-left: 3px solid #E24B4A` with very faint red bg (`rgba(226,75,74,0.04)`)
- Med: `border-left: 3px solid #EF9F27` with faint amber bg (`rgba(239,159,39,0.04)`)
- Low: `border-left: 3px solid #639922` with faint green bg (`rgba(99,153,34,0.04)`)

This replaces the current flat `#f7f7f7` background. The priority dot remains. The colors are deliberately very muted.

### 6. Making the app live with real user names
The app is already published at `https://sunny-flow-tasks.lovable.app`. Each user who signs up gets a `team_members` row auto-created from their email/name (see `useAuth.tsx` line 40). Their name appears in the filter pills and avatar stack. To get real names, users need to sign up — the system already handles this. No code changes needed here, just sharing the published URL with your team.

### Files Changed

| File | Change |
|------|--------|
| `BoardColumn.tsx` | Bolder header text |
| `NewTaskPanel.tsx` | Pill buttons for assignee, default to current user |
| `TaskCard.tsx` | Hide placeholder during drag (`opacity: 0`) |
| `TaskCardContent.tsx` | Remove `isDragging` opacity, add priority color border/tint |
| `TopBar.tsx` | Remove user name span next to sign out |

