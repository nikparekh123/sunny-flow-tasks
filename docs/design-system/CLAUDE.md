# CLAUDE.md — Navi Design System build rules

You are working in a repo that uses the **Navi design system** (Sunnyfi's dark, data-dense options/positions UI). Follow these rules for every UI change. They are not suggestions.

---

## Load order (always)

```html
<link rel="stylesheet" href="tokens.css">      <!-- FIRST. defines every --token -->
<link rel="stylesheet" href="components.css">   <!-- OR individual css/*.css modules -->
```

`components.css` `@import`s four modules: `css/dashboard.css`, `css/positions.css`, `css/strategy.css`, `css/band.css`. Import only what a page needs if you prefer.

Fonts (Work Sans + DM Mono) load via `@import` at the top of `tokens.css`. No extra setup.

---

## The ten hard rules

1. **Never hardcode a color.** Always `var(--token)`. If you reach for a hex, you're wrong — find the token in `tokens.css`.
2. **DM Mono (`--mono`) for every number, ticker, hex, greek, date, percentage.** Work Sans (`--sans`) for everything else. No exceptions.
3. **One loud accent.** `--neon` is the only bright color. Reserve it for active state and key KPIs. Everything else stays desaturated.
4. **Color carries meaning, not decoration.** `--positive` (gains), `--negative` (losses), `--warning` (watch) — only on the value they describe. Labels stay `--fg3`.
5. **The four feature accents** (`--earnings` violet, `--oi` blue, `--note` magenta, `--whatif` bone) are each pinned to ONE feature. Never repurpose them.
6. **No drop shadows for elevation.** Lift with a canvas-color shift (`--page` → `--surface`), a border (`--bright`), or a tint fill. (Shadows are allowed *only* on floating overlays: menus, tooltips, drawers.)
7. **No gradients** except the skeleton shimmer and the few documented tinted card fills. No frosted glass / `backdrop-filter`.
8. **Real minus sign** `−` for negative numbers, never a hyphen `-`. Greeks as glyphs: `Δ −63.30`, not "Delta: -63.30".
9. **Glyphs are Unicode** from `assets/glyphs.txt` (`↑ ↓ → ✓ ✕ ⚠ · — –`). **No emoji. No icon font.** If a real icon is unavoidable, use Lucide at Work-Sans-400 weight and say so in the PR.
10. **Dense by design.** Use the `--space-*` scale; don't pad things out. Card padding is `--card-pad` (16px 18px).

---

## Voice (for any copy you write)

Write like a **seasoned desk analyst** — concise, numerate, slightly dry, actionable. State a fact, then its implication.

- Imperative for actions: "Close position", "Confirm roll", "Replace CSV".
- Em-dash to chain cause→effect: *"Delta above 0.80 threshold — consider rolling before FOMC."*
- En-dash for ranges: `$637–$673`, `15–25%`.
- Middle-dot to chain metadata: `SPY · $655.06 · +0.44% · Δ −63.30`.
- **Sentence case** everywhere. UPPERCASE + wide tracking only for micro-labels.
- Never first person. Never marketing. Never cheerful. Never emoji.

Assume the reader knows what a ladder, roll, strike, IV, theta, and delta are. Don't over-explain.

---

## Motion

- Curves are quiet: `--ease` standard, `--ease-out` for bar/marker grow-ins. **No bounce, elastic, or spring.**
- Durations: `--dur-fast` (.15s hover), `--dur-mid`, `--dur-slow`.
- Named keyframes already defined: `pulse` (live dot), `blink` (cursor), `shimmer` (skeleton), `todayGlow`, `navi-fade-up`, `navi-scroll`.

---

## Component CSS — where things live

| Need | Module | Key classes |
|---|---|---|
| Brand bar, pills, chips, flags, ticker, calendar, news, hero | `css/dashboard.css` | `.brandbar` `.pill` `.chip` `.ticker` `.cal` |
| Greeks bar, position table, cards, cockpit, large-type, treemap, ledger | `css/positions.css` | `.greeks-bar` `.ptable` `.pcard` `.cockpit` `.fs-stage` `.treemap` `.ledger-row` |
| Scanner: triage cards, pipeline, universe table, status tape | `css/strategy.css` | `.tcard` `.pipeline` `.uni-table` `.tape` |
| Position Lens: band, scrubber, what-if, annotations | `css/band.css` | `.layers` `.band-wrap` `.scrubber` `.wf-*` `.note-*` |

**`.pcard` is overloaded.** In `positions.css` it's the position card. In `band.css` the Lens card is scoped under `.lens` (`.lens .pcard`). Always wrap a Lens page in `<div class="lens">`.

Full copy-paste markup for every component is in **`COMPONENTS.md`**.

---

## When extending the system

- Need a new shade? Derive it in **oklch** from an existing token so it stays in-family — don't eyeball a new hex. Add it to `tokens.css` with a comment, don't inline it.
- Need a new component? Compose from existing atoms and tokens first. Match the density, the hairline-border vocabulary, and the mono-for-numbers rule.
- Reserve `--neon` — adding a second loud accent breaks the whole system's legibility.
