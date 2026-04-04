

## Plan: Card Visual Redesign — Bigger, Bolder, Shadow, No Left Border

Based on both Dribbble references, the cards need a complete visual overhaul.

---

### Changes to `src/components/board/TaskCardContent.tsx`

**Card container styling:**
- Remove the colored left border entirely (`borderLeft: 3px solid ...` gone)
- Background: solid white `#ffffff` for all cards (no priority-tinted backgrounds)
- Add box shadow: `0 1px 4px rgba(0,0,0,0.08)` resting, `0 4px 12px rgba(0,0,0,0.12)` on hover
- Border: `1px solid #f0f0f0` (very subtle)
- Border-radius: `10px`
- Padding: `14px 16px`

**Card layout (top to bottom), matching the Keitoto reference:**

1. **Top row**: Status pill (colored dot + column name like "Not Started" / "In Research") on the left, recurrence icon + three-dot menu on the right
2. **Title**: `16px`, font-weight 600, line-height 1.4
3. **Brief**: `12px`, 2-line clamp, muted color
4. **Assignees row**: "Assignees:" label + stacked avatars (size `h-6 w-6`)
5. **Separator**: thin `1px` line (`#f0f0f0`)
6. **Footer row**: Due date with calendar icon (`12px`) on left, Priority pill on right (colored text like "High" in red, "Medium" in orange, "Low" in green)
7. **Bottom meta row** (if applicable): Subtask progress + count

**Remove:** Priority dot, priority-tinted backgrounds, colored left border

**Hover:** Background stays white, shadow increases. No background color change.

---

### Changes to `src/components/board/BoardColumn.tsx`

- Remove `bg-card`, `border`, `border-border` — columns become transparent containers on the board background
- Keep `rounded-xl p-3` for spacing
- Increase header text from `text-xs` to `text-sm`
- Increase card gap from `space-y-2` to `space-y-3`
- When `isOver`: use a subtle background tint instead of border highlight

---

### Changes to `src/components/board/KanbanBoard.tsx` (if needed)

- Ensure board background is the light gray (`#f5f5f4` or similar) so borderless columns sit naturally on it

---

### Props/Data needed

The status pill on the card needs the column label. `TaskCardContent` doesn't currently receive column info, so pass `columnLabel` as a new prop from `BoardColumn` → `TaskCard` → `TaskCardContent`, along with `columnColor`.

---

### Files Changed

| File | Change |
|------|--------|
| `src/components/board/TaskCardContent.tsx` | Full visual redesign: white bg, shadow, 16px title, status pill, priority pill, separator, no left border |
| `src/components/board/TaskCard.tsx` | Pass `columnLabel` and `columnColor` props through |
| `src/components/board/BoardColumn.tsx` | Remove white card/border, transparent columns, pass column info to cards |
| `src/components/board/KanbanBoard.tsx` | Ensure board has light gray background |

