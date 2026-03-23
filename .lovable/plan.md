

## Plan: Fix Task Creation Bugs, Improve DnD Smoothness, and Optimize Load Time

### Problems Identified

1. **Slow initial load**: The app fires 4 parallel queries (tasks, tags, task_tags, members) with no `staleTime`, so React Query refetches on every mount. The Google Fonts `@import` in CSS also blocks rendering.
2. **New task creation bugs**: The `NewTaskPanel` calls `handleClose()` immediately after `onSave()`, closing the panel before the mutation completes. There's no loading state, no error handling, and no toast feedback. If the save fails silently, the user sees nothing.
3. **DnD jerkiness**: The `SortableContext` uses `verticalListSortingStrategy` but the optimistic update operates on `rawTasks` (the query cache before tag merging), while the UI renders `tasks` (with tags merged). This mismatch causes a brief flicker when `onSettled` refetches. Also, `CSS.Transform.toString` produces transforms that can cause layout shifts without `will-change`.

### Changes

#### 1. Optimize initial load time (2 files)

**`src/App.tsx`** — Add `staleTime` and `refetchOnWindowFocus: false` to the QueryClient defaults so data isn't refetched unnecessarily:
```ts
const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, refetchOnWindowFocus: false },
  },
});
```

**`index.html`** — Preload the Inter font with a `<link rel="preconnect">` + `<link rel="preload">` so it doesn't block first paint via the CSS `@import`.

#### 2. Fix task creation flow (2 files)

**`src/components/board/NewTaskPanel.tsx`**:
- Add a `saving` state that disables the Save button and shows "Saving..." text
- Don't call `handleClose()` from `handleSave()` — instead, pass an `onSuccess` callback
- Show a toast on success/error via sonner

**`src/components/board/TopBar.tsx`** / **`KanbanBoard.tsx`**:
- Change `onCreateTask` to return a Promise so the panel can `await` it
- Wire `createTask.mutateAsync` instead of `createTask.mutate` so the panel knows when it's done

#### 3. Smooth out drag-and-drop (3 files)

**`src/components/board/TaskCard.tsx`**:
- Use `CSS.Translate.toString` instead of `CSS.Transform.toString` to avoid scale transforms that cause layout shifts
- Add `will-change: transform` and `transition: transform 200ms cubic-bezier(0.25, 1, 0.5, 1)` for GPU-accelerated movement
- Set `z-index: 1` when dragging so the card stays above siblings

**`src/hooks/useTasks.ts`**:
- In the `moveTask.onMutate`, also cancel and snapshot `task_tags` queries to prevent mid-drag refetch from causing flicker
- Debounce the `onSettled` invalidation by 300ms so rapid successive drags don't trigger cascading refetches

**`src/components/board/BoardColumn.tsx`**:
- Add `transition-all duration-200` to the card list container for smoother reflows when cards enter/leave

#### 4. Add toast notifications (1 file)

**`src/components/board/KanbanBoard.tsx`**:
- Import `toast` from sonner
- Add `onSuccess`/`onError` toasts for create, delete, and move operations

### File Change Summary

| File | Change |
|------|--------|
| `src/App.tsx` | Add QueryClient `staleTime` defaults |
| `index.html` | Add font preconnect/preload |
| `src/components/board/NewTaskPanel.tsx` | Add saving state, async save, toast |
| `src/components/board/TopBar.tsx` | Pass `mutateAsync` for create |
| `src/components/board/KanbanBoard.tsx` | Wire async create, add toasts |
| `src/components/board/TaskCard.tsx` | Use `CSS.Translate`, add `will-change` |
| `src/hooks/useTasks.ts` | Cancel tag queries on drag, debounce settle |
| `src/components/board/BoardColumn.tsx` | Smooth container transitions |

