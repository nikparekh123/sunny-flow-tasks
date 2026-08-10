# Handoff: NVDA covered-call planner — full-page snap planner

## Overview

A phone-sized planner for writing covered calls against a long stock position. It answers one
question per screen, top to bottom, in the order a seller actually decides: how strong is the
setup, what does that mean for size, what could break the week, is the put floor intact, what to
sell, what is running once a sale is confirmed, and how the last quarter was. Seven snap pages,
one decision each.

The governing idea: **conviction is the main number, and conviction sizes the sale.** A high
reading does not tell you to sell more, it tells you to sell *less, further out* — fewer contracts
at a further strike. The strike rail is always the same three named tiers (conservative /
balanced / aggressive); conviction changes where those three sit, never how many there are.

## About the design files

The files in this bundle are **design references created in HTML** — a working prototype of the
intended look and behaviour, not production code to lift. The task is to **recreate these designs
in the target codebase's own environment** (React Native, SwiftUI, native Android, or a web app)
using its established patterns, component library, and data layer. If no environment exists yet,
choose the most appropriate framework and implement the designs there.

The prototype renders with React 18 + Babel from CDN and reads a single global data object. That
is a prototyping convenience only — see **Data contract** for the shape the real feed should take.

## Fidelity

**High fidelity.** Colors, type, spacing, and layout are final and specified below to the pixel.
Recreate the UI pixel-perfectly using the codebase's existing primitives. All figures shown are
sample data from one server response, not literal copy to hardcode.

## Design system

The visual language is **Ink — The Risk Shop**, and its two laws are load-bearing here:

1. **Color is data.** The shell is black and white. Hue appears only on data that carries
   meaning — the seven conviction family discs, the loss region of the payoff chart. No hue on
   chrome, buttons, headers, or type. Selection is expressed by **inversion** (ink ↔ paper), never
   by a color change. No red-for-alarm: severity is carried by weight and opacity.
2. **Opacity is relevance.** Nothing is hidden; lower-priority information is faded. Secondary
   text sits at 55–62% of the text color, never lower.

This prototype does not import the Ink component bundle — the planner's pages are their own
vocabulary built on Ink's tokens and laws. If the target codebase has Ink available, prefer its
primitives (`Figure`, `Relevance`, `SeverityBand`) for the equivalents noted below.

## Design tokens

### Surfaces and text

| Token | Dark pages (01,02,03,05,07) | Light pages (00,04) |
|---|---|---|
| Page background | `#0B0B0A` | `linear-gradient(168deg,#FFFFFF 0%,#F7F7F4 62%,#F1F1ED 100%)` |
| Text (`--t`) | `#F4F4F2` | `#0C0C0B` |
| Dim text (`--d`) | `rgba(244,244,242,.55)` | `rgba(12,12,11,.62)` |
| Page glow | `radial-gradient(90% 55% at 82% 6%, rgba(255,255,255,.05), transparent 68%)` | same with `rgba(0,0,0,.03)` |
| Hairline | `color-mix(in oklab, var(--t) 18%, transparent)` | same formula |
| Inverted fill | `var(--t)` bg / `#F7F7F4` text | same formula |

Two light pages only, and they are the two you *act on*: the score you audit (00) and the sale you
place (04). Everything else is ink.

### Data hues (the only color in the app)

| Family | Hex | Family | Hex |
|---|---|---|---|
| trend | `#1F6F4A` | | |
| catalyst | `#C08A16` | grade | `#7A4BB5` |
| stretch | `#C0503A` | sector | `#93417A` |
| record | `#3B4CA8` | macro | `#8A5A2B` |
| relative | `#1E7C86` | peers (no feed yet) | `#8E8E88` |

Nine families, so the disc grid is a true 3 × 3 with no hole. `relative` is this name against the
group; `sector` is whether the group itself is working.

Payoff-chart loss region: `color-mix(in oklab, #C0503A 20%, transparent)`.

### Type

- Display / UI: **Archivo** 400, 500, 600, 700.
- Mono (every number, every label): **IBM Plex Mono** 400, 500.

| Role | Size | Weight | Tracking | Notes |
|---|---|---|---|---|
| Hero number (`.nb .v`) | 110px (84–96px where noted) | 600 | `-.055em` | `line-height:.86`, tabular numerals |
| Hero unit (`.nb .u`) | 24px | 400 | `-.02em` | dim, sits on the hero's baseline |
| Statement (`.say`) | 16px | 500 | `-.02em` | `line-height:1.3` |
| Fine print (`.fine`) | 13px | 400 | `-.005em` | dim, `line-height:1.5`, `text-wrap:pretty` |
| Kicker / eyebrow | 11px mono | 400 | `.2em` | uppercase, dim |
| Meta (right of kicker) | 10.5px mono | 400 | `.08em` | uppercase, dim |
| Trail (`67 → 70 → 91`) | 11.5px mono | 400 | `.02em` | last value at full `--t` |
| List body | 16px (15px when faded) | 400 | `-.012em` | lede in 600 |

All type sizes pass through a `textScale` multiplier (1 / 1.1 / 1.2) — see **Responsive**.

### Geometry

- Device frame: **390 × 844**, screen radius 46px. Every page is exactly one screen tall.
- Page padding: `56px 26px 44px`. Column gap between head and base: 20px.
- Radii: strike card 18px, confirm bar 14px, checkbox 6px, pills/bars 99px.
- Hairline: 1px. Disc negative ring: 3px. Disc zero/off ring: 1.5px.

## The layout law (applies to every page)

```
.pg-in { display:flex; flex-direction:column; justify-content:space-between; gap:20px }
  .pg-head  → content stacks DOWN from the top
  .pg-base  → the page's one number sits BOTTOM LEFT, unit on its baseline,
              trail / statement / fine print stacked beneath it
```

Content grows downward from the top; **the number never moves**. This is the single rule that makes
eight different pages read as one instrument. Do not center anything.

## Screens

### 00 · Conviction (light)

**Purpose:** audit the number before trusting it.

- **Layout:** date kicker, then a 3 × 3 grid of equal circles (`gap:12px 8px`, each
  `max-width:106px`, `aspect-ratio:1`). Hero `91 of 100` bottom left, trail `72 → 78 → 91`, then
  one sentence naming the two biggest movers.
- **Discs:** every family gets the *same size* disc — size says nothing. Weight is carried by
  color depth: fill = `color-mix(in oklab, <hue> P%, #fff)` where `P = 26 + 74 × |today| / max`.
  A family that *adds* conviction is solid; one that *takes it away* is a hollow 3px ring; a zero
  family is a 1.5px ring at 48%; a family with no feed is a 1.5px dashed ring at 55%.
- **Order:** biggest mover since yesterday first — the disc you read first is the one that changed.
- **Tap a disc:** the hero becomes that family's own contribution (`+22 of 22`) in its hue, the
  trail becomes that family's three days, and the fine print states the family's formula verbatim.
  Selected disc gets `box-shadow:0 0 0 2px var(--t)`. Tap again to deselect. The family name is
  revealed inside the disc on selection (10px mono, `.14em`), colored by the *measured luminance*
  of the mixed fill — not by the weight that produced it — so it always reads.

### 01 · The decision (dark)

**Purpose:** what conviction does to the size.

- Kicker `the decision`; fine print listing open positions ("60 sold for Aug 12, 60 rollable.").
- Hero: **`22 of 60 contracts`** — what conviction sized the sale to, against a neutral-reading
  full size.
- Statement: "Conviction 91 shrinks the sale: 22 at 227.50, not 60 at 222.50. Keep 94%, 7,016 of
  7,500 delta."
- Fine print: week character, price context, `Paid −12% against normal`, and why the reading moved.
- Footer row (tappable, jumps to page 06): `baseline 50` · `your grade +4`. Top hairline, mono
  11px, `.14em`, uppercase.

### 02 · The week (dark)

**Purpose:** what could break it, and what is noise.

- Two numbered lists, second directly under the first: `what matters this week` (up to 3) then
  `what won't matter`. Ordinal in mono/dim, 13px column; body 16px with a 600 lede.
- The quiet list renders at 15px and stays visible — faded, never dropped (Law 2).
- No hero number on this page: it is the only page that is all content.

### 03 · Put floor (dark)

**Purpose:** a prerequisite, decided before anything is written.

- Hero: `220` with unit `0.2% under spot`; statement is the verdict ("The floor is level with
  spot."); fine print states the rule: the floor is rolled first, as its own decision, and nothing
  is written against an unprotected book.

### 04 · What to sell (light) — the page that acts

**Purpose:** pick a tier, see the whole position's payoff, confirm what was executed.

- **Head row:** kicker `what to sell` + meta `10 AUG → AUG 12 · 2D`.
- **Strike rail:** horizontal, `overflow-x:auto`, x-snap, cards 152px wide, 9px gap, bleeding into
  both page margins (`margin:0 -26px; padding:2px 26px 8px`). **Always exactly three tiers**, in
  order: conservative, balanced, aggressive — i.e. furthest strike first, which at high conviction
  is the consistent end of the rail. Each card: tier name (9px mono `.16em` dim), strike (24px
  mono), `N contracts · X% out`, a hairline, then a 2-column greeks grid (`iv`, `Δ`, `Γ`), then the
  credit (19px mono). **Selected = inverted** (`background:var(--t); color:#F7F7F4`), never a hue.
  A tier that would sit inside the put floor renders dashed at 50% with its strike struck through
  and the reason in place of its size; it is not selectable.
- **Rail opens on the recommended tier** (`rec: true`), never on the biggest credit.
- **Payoff chart** (SVG, 338×150, no axes furniture): the whole position from today — shares plus
  the call being sold. It rises with the stock until the strike, then flattens to the uncovered
  shares; that kink *is* the cap. Elements: 2.5px position line; a filled loss region below zero in
  `#C0503A` at 20%; 1px zero line; 1px `now` marker at spot; a solid dot at the strike labelled
  `capped 227.50`; a hollow dot at the position breakeven. Header above it: `7,500 shares + call`
  and `5,300 uncapped`. Nothing is computed client-side beyond geometry.
- **Base:** hero `$2K` with unit `credit at 227.50`, then two fine lines. First: tier, premium per
  share, contract count, where the same tier sat at a neutral 50, and hedge coverage. Second, the
  breakeven **in words** — "Breakeven 228.44: the 227.50 strike plus the 0.94 you were paid, 9.7%
  above your 208.33 basis." The chart's hollow dot is a marker, not a statement; this line is the
  statement. Its percentage comes from the feed (`beBasisPct`), not the client.
- **Confirm:** a checkbox — *"This is what is executed: 22 at 227.50, 08-12."* — then the button,
  which is inert (`background: color-mix(in oklab, var(--t) 16%, transparent)`) until ticked and
  reads **start monitoring**. Switching tier clears the tick. Once confirmed the checkbox becomes a
  read-only checked line: *"Executed 22 at 227.50, 08-12. Logged Mon 10 Aug and counted against the
  record."* Selecting a different tier while a position is live offers **replace the position**.

### 05 · Monitoring (dark) — only exists once a sale is confirmed

**Purpose:** what is running, and how much room is left.

- Kicker `the position you are running` + meta `sold Mon 10 Aug`.
- Ticket line, mono 13px: `22 NVDA Aug 12 227.50 C at 0.94`.
- **Room bar:** a 6px track (`color-mix(in oklab, var(--t) 14%, transparent)`) filled from the sale
  price toward the cap by `(spot − soldSpot) / (strike − soldSpot)`, clamped 0–1. Labels above:
  `sold at 220.47` / `cap 227.50`; below: `now 220.47 · unchanged` / `5,300 uncapped`.
- Hero: `3.19% of room left`. Statement: called odds and sessions to run. Trio beneath: collected /
  if called at strike / delta kept.
- `stand down` clears the position (and removes this page).

### 06 · Earnings grade (dark)

**Purpose:** the one input no feed provides.

- Kicker `earnings grade` + meta `reported 27 May`; asks "How was Q1 FY27?" and states the decay
  ("53 sessions ago. It fades out over 60, and the next one opens after the 26 Aug print.").
- Hero `7 of 10` with a − / + stepper (two 60px circles, 1px border at 28%, hover inverts).
- History strip: a 4-column grid, one column per graded quarter — value, a bar (`grade × 10%`
  width, 4px; 5px and full opacity for the current one), quarter label. The current column updates
  live as you step, so the trend is visible while you set it.

### Deliberately not built: a track record

An earlier draft carried a page counting which tier was picked over the last 30 and 60 **sessions**.
It was removed, and should not be rebuilt in that form. The unit was wrong: you roll weekly, so
"18 of the last 30 sessions" is really four or five actual decisions dressed up as eighteen — a
record too thin to read, presented as though it were thick. When this returns it must count
**decisions, not days** ("your last 20 rolls"), which is a different page with a different shape.

## Interactions & behaviour

- **Navigation:** vertical scroll container with `scroll-snap-type:y mandatory` and
  `scroll-snap-stop:always` — one page per gesture (seven, or six with no live position). A
  right-edge dot rail (6px dots, active dot
  grows to 18px, `mix-blend-mode:difference` so it reads on both grounds) also jumps directly.
  Transitions are the platform's own scroll; no custom animation anywhere in this design.
- **Disc tap:** instant state change; disc fill/border transition 300ms ease, name fades in 220ms.
- **Tier select:** 180ms ease on background, color, border-color.
- **Confirm flow:** select tier → tick checkbox → button enables → confirm creates the position,
  reveals page 05, and locks the checkbox into its executed state.
- **Reduced motion:** `@media (prefers-reduced-motion:reduce)` disables all transitions and smooth
  scrolling. Honour this.
- **Hit targets:** every control is ≥ 44px in its short dimension (steppers are 60px, the confirm
  bar is 51px tall, discs are ~106px).

## State

| State | Scope | Notes |
|---|---|---|
| `selectedFamily` | page 00 | null = show conviction; otherwise a family key |
| `selectedTier` | page 04 | initialised to the committed tier, else the recommended one |
| `confirmTicked` | page 04 | resets to false whenever the tier changes |
| `position` | app | `{ tierIndex, iso, label, spotAtSale }`; **persisted** (prototype uses `localStorage["nvda-planner-pages-commit-v1"]`). Presence of this record is what makes page 05 exist. In production this is a server-side position record, not local storage. |
| `grade` | page 06 | 0–10, stepper; writes back to the server and feeds the grade family on page 00 |
| `textScale` | app | 1 / 1.1 / 1.2 accessibility multiplier |

## Data contract

Everything on screen comes from one response — `window.PLAN2` in the prototype
(`planner-pages-data.jsx`). **Nothing is computed in the app** except the payoff chart's geometry
and the room bar's fraction. Keep it that way: the client must not re-derive pricing, conviction,
or counts.

```
asOf        { dow, label, short, iso, spot }
ticker
book        { shares, buyAvg }                 // the calls are written against these
expiries    [{ iso, load, verdict }]           // pre-cased strings; never re-case them
plan
  conviction, convictionYest, convictionTrail[3], paidVsNormal
  size      { sold, full, strike, fullStrike }  // what conviction did to the size
  keepPct, keepDelta, totalDelta
  event, price, why, baseline, convictionMove
  expiry, expCode, expDays, expectedMove
  picks[3]  { tier, ct, strike, otm, delta, gamma, iv, prem, breakeven, beBasisPct,
              posBe, uncovered, kept, called, income, label, rec?, was?, blocked?,
              out: { prem, shares } }          // 'out' figures are per tier, never global
  tierNote, hedgeNote
  grade, gradePrice, gradeQuarter { label, reported, sessionsAgo, nextPrint }
  gradeHistory[] { q, on, g, current? }
factors[9]  { key, hue, reads, min, max, today, yest, d2, computed? }
observations{ matters[], quiet[], silent[] }
floorAdvice { stale, floor, gapPct, head, verdict }
```

Notes for the implementer:

- `computed:false` on a factor means *the slot exists and the number does not yet* — render the
  dashed ring and an em dash, never a zero.
- `blocked` on a pick is a refusal with its reason in words; render it struck and unpickable.
- Every family's contribution must reconcile: the eight computed families summed off the neutral
  50 equal `conviction`, for all three days in `convictionTrail`. If they don't, the audit page is
  lying and the discs should not render.
- Percent signs must be concatenated into their figure (`${n}%` as one string), not left as a
  sibling text node, or the number can break across lines.

## Responsive

The design is authored at one size (390 × 844) because it is a phone instrument. Scale up by
increasing `textScale`, not by widening the column. On taller devices, the extra height goes to
the gap between `.pg-head` and `.pg-base` — the number stays pinned to the bottom left.

## Assets

None. No images, no icon font. The two SVGs in the prototype are the status-bar battery glyph and
the payoff chart, both drawn from data. Fonts are Archivo and IBM Plex Mono (Google Fonts) — use
the codebase's existing font loading.

## Files in this bundle

| File | What it is |
|---|---|
| `NVDA Planner - Pages.html` | The prototype. Open it directly; it is the source of truth for look and behaviour. Contains the full stylesheet inline plus a small host panel (text size, grade page on/off) that is **not part of the design**. |
| `ink-planner-pages.jsx` | All eight page components, the payoff chart, and the snap stack. |
| `planner-pages-data.jsx` | One sample server response — the data contract above, with comments. |
| `planner-pages.css` | The same stylesheet extracted as a standalone file, for reading tokens without wading through the HTML. |
| `screenshots/*.png` | High-resolution captures (1170 × 2532, 3×) of all seven pages, in order. Page 05 is captured with a confirmed position, which is the only state in which it exists. |
