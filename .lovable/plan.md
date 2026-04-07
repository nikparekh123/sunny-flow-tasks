

## Plan: Apply OWL Dark Design System to Task Board

Port the dark teal + neon green design system from [Project OWL](/projects/1eb45dfc-b98a-4e28-ae0c-3a53e0655c6a) to this task board. The entire app will shift to a dark theme using OWL's color tokens, font (Work Sans), and styling conventions.

---

### 1. Add OWL Design Tokens

**Create `src/styles/owl-tokens.css`** — copy the token file from OWL with all CSS custom properties (canvas colors, text hierarchy, semantic colors, borders, radius, animations).

### 2. Update `src/index.css`

- Import `owl-tokens.css` and Work Sans font
- Replace all `:root` CSS variables with OWL dark values:
  - `--background`: dark teal (`#0a2828`)
  - `--foreground`: cream (`#faf5f0`)
  - `--card`: dark surface (`#0f3333`)
  - `--primary`: neon green (`#d2e632`)
  - `--primary-foreground`: dark teal
  - `--secondary`, `--muted`, `--accent`: OWL surface/elevated tones
  - `--border`, `--input`: OWL border values
  - `--destructive`: OWL negative (`#e87060`)
- Update `body` font-family to `'Work Sans', sans-serif`

### 3. Update `tailwind.config.ts`

- Add `owl` color palette (page, surface, elevated, neon, positive, negative, etc.)
- Set default font-family to Work Sans

### 4. Update `src/components/board/TaskCardContent.tsx`

- Card background: `rgba(15, 51, 51, 0.55)` (OWL card) instead of white
- Card border: `rgba(30, 90, 80, 0.35)` (OWL border)
- Card shadow: subtle dark-friendly shadow (`0 1px 4px rgba(0,0,0,0.2)`)
- Title color: `--owl-text-primary` (`#faf5f0`)
- Brief/muted text: `--owl-text-secondary` (`#a8c4c0`)
- Status pill: use OWL-compatible tints (translucent column color on dark bg)
- Priority pill text: keep existing colors but adjust for dark bg contrast
- Due date text: `--owl-text-secondary`
- Tag pills: translucent color on dark bg
- Separator line: `--owl-border`
- Done state opacity stays at 0.55

### 5. Update `src/components/board/BoardColumn.tsx`

- Column background when `isOver`: translucent teal tint (`rgba(30, 90, 80, 0.15)`)
- Header text: `--owl-text-primary`
- Count badge: OWL surface bg with muted text
- "Drop here" border: `--owl-border-mid`
- "See more" button: OWL muted text colors

### 6. Update `src/components/board/KanbanBoard.tsx`

- Board container: replace `bg-muted/40` with `bg-[var(--owl-page)]` or equivalent dark background
- Loading spinner: use OWL neon color for the spinner accent

### 7. Update `src/components/board/TopBar.tsx`

- Top bar background: `rgba(15, 51, 51, 0.7)` with OWL border-bottom
- "SunnyFi Board" title: `--owl-text-primary`
- View toggle buttons: OWL surface styling, active state with neon accent
- "New task" button: neon green bg (`#d2e632`) with dark text
- All icon buttons: `--owl-text-secondary`, hover to `--owl-text-primary`
- Avatar borders: OWL surface color
- Dropdown menus will inherit from updated CSS variables

### 8. Update `src/pages/Auth.tsx`

- Background: OWL page color
- Title/text: OWL text primary/secondary
- OTP slots will inherit from updated CSS variables

### 9. Update `src/components/board/TaskDetailPanel.tsx`

- Modal background: OWL surface
- Text colors: OWL text hierarchy
- Input/textarea: OWL input styling
- Buttons: neon primary, OWL ghost styles

### 10. Update `src/components/board/NewTaskPanel.tsx`

- Same dark surface treatment as TaskDetailPanel
- Form inputs: dark bg with light text
- Priority buttons: OWL-compatible contrast

---

### Files Changed / Created

| File | Action |
|------|--------|
| `src/styles/owl-tokens.css` | Create — OWL design tokens |
| `src/index.css` | Update — dark CSS variables, Work Sans font |
| `tailwind.config.ts` | Update — add OWL colors, Work Sans font |
| `src/components/board/TaskCardContent.tsx` | Update — dark card styling |
| `src/components/board/BoardColumn.tsx` | Update — dark column styling |
| `src/components/board/KanbanBoard.tsx` | Update — dark board background |
| `src/components/board/TopBar.tsx` | Update — dark top bar with neon accents |
| `src/pages/Auth.tsx` | Update — dark auth page |
| `src/components/board/TaskDetailPanel.tsx` | Update — dark detail panel |
| `src/components/board/NewTaskPanel.tsx` | Update — dark new task form |

