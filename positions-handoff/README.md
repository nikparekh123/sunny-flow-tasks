# Sunnyfi · Positions page — design handoff

A self-contained snapshot of the current **Positions** page for a layout
rethink. Open `Positions.html` in any browser — it pulls in the real
production stylesheet so what you see matches the live app's visual
language.

## Run

Just open `Positions.html` in a browser, or serve the folder
(`python3 -m http.server`, `npx serve`, etc.). No build step, no deps.

## Files

| File | What it is |
|------|------------|
| `Positions.html` | Main page snapshot — hero, allocation, insights strip, positions table, realized summary. |
| `Trades.html` | The **Trades matrix** view (shares / options-open / closed zones + realized totals + footer). |
| `Modal-Insight.html` | The read-only **insight modal** (opens on ticker click). |
| `Modal-PositionDetail.html` | The **write modal** — Open tab with the action picker, spot chip, and the Income/Cost rail graph card. |
| `positions.css`  | **The production stylesheet, copied verbatim** (≈5,300 lines). Everything is scoped under `.np-app`. Self-imports Work Sans + DM Mono. This is the source of truth for the visual system. |

All four HTML files share the one `positions.css`. Open any of them in
a browser.

## The design system (from `positions.css`)

Dark "Navi" theme. Key tokens (all CSS variables under `.np-app`):

```
--navi-page        #0a2828   page base
--navi-dash-page   #061a10   darker app background
--navi-surface     #0f3333   card surface
--navi-elevated    #1e5a50
--navi-fg1         #faf5f0   bone white (primary text)
--navi-fg2         #a8c4c0   muted teal
--navi-fg3         #468278   dim label
--navi-neon        #d2e632   primary accent (yellow-green)
--navi-positive    #a8d4a0   gains (soft green)
--navi-negative    #e87060   losses (coral)
--navi-warning     #e0c060   amber
--navi-border-bright #326e64 hairline / border highlight

Fonts:  Work Sans (sans / display) · DM Mono (numerals + labels)
```

## Page structure (top → bottom)

1. **Top bar** (`.np-top`) — brand + breadcrumb on the left, Refresh +
   Upload actions on the right.
2. **Hero** (`.np-hero`) — big total portfolio value + unrealized P&L
   (amount + percent). Color flips green/red on direction.
3. **Allocation** (`.np-section`) — view toggle (By stock / By sector /
   By strategy / P&L by position) above a **treemap**. *In the live app
   this is an interactive SVG/canvas treemap; here it's a static tile
   grid standing in for the proportions.*
4. **Stock insights strip** — a horizontally snap-scrolling carousel of
   big vibrant per-ticker cards (price, day %, β, IV, position P&L,
   earnings countdown). Three sample cards shown.
5. **Positions table** (`.np-table`) — rows grouped by **strategy
   bucket** (Income / Investment / Yield / Unassigned), each with a
   colored header + subtotal footer row. Columns: Ticker, Status
   (overall P&L), Sector, Qty, Avg cost, Net cost (break-even),
   Price, Mkt value, P&L $, P&L %, % portfolio. View toggle switches
   to **Trades** (a matrix) or **Calendar** (expiry timeline) — not
   reproduced here.
6. **Realized summary** — strategy-bucket stat blocks (premium
   collected, realized gains, protective-put cost).

## What's simplified in this snapshot

These are interactive React components in the live app, represented as
static stand-ins here so the snapshot stays self-contained:

- **Allocation treemap** → static tile grid (real one is computed +
  interactive, `AllocationTreemap.tsx`)
- **Stock insights strip** → 3 static cards (real one is a data-driven
  snap carousel, `StockInsightsStrip.tsx`)
- **Trades matrix + Calendar views** → not shown (table view only)
- **Modals** (position detail, insight, CSV upload) → not shown
- **Realized summary** → simplified to 3 stat blocks
- Sorting, hover states, animations (count-up numbers) → static

## What I'd love help rethinking

- The overall **information hierarchy** — hero → allocation → insights →
  table → realized is a lot of vertical scroll. Is there a tighter
  composition?
- The **table is dense** (11 columns × grouped rows). Could the
  strategy-bucket grouping + subtotals be more scannable / visual?
- The **allocation treemap** placement + the **insights strip** feel
  like separate islands — could they be unified or reordered?
- Bringing the same **bold, editorial, big-number** feel the dashboard
  now has (see the separate dashboard handoff) into this page.

Don't worry about implementation — layout direction + mockups are what
I'm after.
