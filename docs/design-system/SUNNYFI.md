# Navi Design System — repo integration notes

The files in this directory are the **canonical Navi handoff** from Claude
design (copied verbatim from the `claude-code-handoff/` package — see
`README.md` for the upstream description).

**Rule:** treat the contents here as **read-only reference**. They are the
source of truth. Our app's CSS in `src/` should converge on them over
time — don't drift the handoff to match the app.

---

## Start here

- **`CLAUDE.md`** — the 10 hard rules. Read once before writing any CSS.
  Tokens, color discipline, no shadows for elevation, real `−` minus,
  Unicode glyphs only.
- **`tokens.css`** — every color, font, space, radius, motion var. **Never
  hardcode a hex anywhere in the app.** Always `var(--token)`.
- **`COMPONENTS.md`** — copy-paste HTML for every component (greeks bar,
  position table, cards, cockpit, ledger, scanner, lens, etc.).
- **`example.html`** — a fully-wired page. Open it locally to see the system
  in action.

---

## What's currently consuming the design system in our app

| Page / module | Status |
|---|---|
| `/dashboard` | Uses our own `dashboard.css` — heavily aligned but pre-dates the canonical tokens.css |
| `/positions` (V2 ledger) | Uses `positions-v2.css` — forked from the handoff long ago, has drifted |
| `/income` | Uses `income-v2.css` — same as above |
| `/portfolio` | Uses `portfolio.css` — port of the Master Positions handoff (PD-0), now a few revisions behind this canonical drop |

**None of these import `tokens.css` or `components.css` from this
directory yet.** They define their own copies of the tokens inline and
maintain forked CSS. Migration to the canonical files is incremental —
see the migration path below.

---

## Token migration cheat sheet

Most of our existing CSS uses the same token *names* (`--neon`, `--page`,
`--fg1`, etc.) but defines them locally in each stylesheet. The canonical
tokens in `tokens.css` are a strict superset:

- Same canvas colors (`--page`, `--page-2`, `--surface`).
- Same text hierarchy (`--fg1` → `--fg5`).
- Same semantic colors (`--neon`, `--positive`, `--negative`, `--warning`).
- **New in canonical**: feature accents (`--earnings`, `--oi`, `--note`,
  `--whatif`) and their tints — each pinned to ONE feature, never reused
  for decoration.
- **New in canonical**: explicit type scale (`--display-size`,
  `--hero-size`, `--title-size`, `--greek-size`, `--metric-size`,
  `--body-size`, `--label-size`, `--section-size`).
- **New in canonical**: space scale (`--space-1` → `--space-12`) and
  `--card-pad` (16px 18px).
- **New in canonical**: radii scale (`--radius-sm/md/lg/xl/pill`).
- **New in canonical**: motion (`--ease`, `--ease-out`, `--dur-fast`,
  `--dur-mid`, `--dur-slow`).

To migrate a page: import `tokens.css` from `docs/design-system/` (via a
build-time copy into `public/` or a `@import` from our own CSS), remove
the local `:root { ... }` token block, and let the canonical tokens
govern. Components keep working because the names match.

---

## Migration path (when we want to converge)

1. **Phase 1**: Copy `tokens.css` into our app's stylesheet load chain
   (replacing the local `:root` blocks in `dashboard.css` /
   `positions-v2.css` / `portfolio.css`). No visual change expected — the
   token *values* match what we already use.
2. **Phase 2**: Replace `portfolio.css` (the most-forked file) with a
   direct `@import` of `components.css` + a thin Sunnyfi-specific shim.
   Removes ~700 lines of duplicated CSS. The handoff's `positions.css`
   already covers everything our portfolio page renders.
3. **Phase 3**: Same swap for `/positions` (V2 ledger) and `/income`.
4. **Phase 4**: Delete the local copies of overlapping CSS.

Don't do this all in one PR. Phase 1 alone is a meaningful diff worth
isolating.

---

## Voice

Per `CLAUDE.md`: **seasoned desk analyst**, concise, numerate, sentence
case. Em-dash for cause→effect (`Delta above 0.80 — consider rolling`).
Middle-dot for metadata chains (`SPY · $655.06 · +0.44%`). Never first
person, never marketing, **never emoji**.

Apply this voice to every copy edit, error message, empty-state line,
and tooltip we write in the app. The voice IS the brand.

---

## Iconography

`assets/glyphs.txt` is the only sanctioned icon vocabulary:
`↑ ↓ → ← ✓ ✕ ⚠ · — –`

If a real icon is unavoidable, use Lucide at Work-Sans-400 weight and
flag it in the PR description. **Never emoji. Never an icon font.**

---

## Updating this directory

If Claude design ships a new handoff, replace this directory in full:

```bash
cd /Users/niketparekh/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/sunny-flow-tasks
rm -rf docs/design-system
mkdir -p docs/design-system
cp -R /path/to/new/claude-code-handoff/. docs/design-system/
rm -f docs/design-system/.DS_Store
# Keep this SUNNYFI.md unless the integration story has changed too.
```

Then update the migration cheat sheet above if any tokens or components
have been renamed.
