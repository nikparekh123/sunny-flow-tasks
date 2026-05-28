# Sunnyfi · New Strategy page — design handoff

A self-contained snapshot of the current **New Strategy** page (the BNF
mean-reversion scanner) for a layout rethink. Open `NewStrategy.html` in any
browser — it pulls in the real production stylesheets so what you see matches
the live app's visual language.

## Run

Just open `NewStrategy.html` in a browser, or serve the folder
(`python3 -m http.server`, `npx serve`, etc.). No build step, no deps.

## Files

| File | What it is |
|------|------------|
| `NewStrategy.html` | The page snapshot — top bar, universe scanner table, open equity + ETF position tables, closed-trades section. |
| `positions.css` | The shared production shell stylesheet, copied verbatim. Defines the dark "Navi" theme + the `.np-app` shell, top bar, buttons, sections, and base `.np-table`. Everything scoped under `.np-app`. |
| `new-strategy.css` | The page-specific production stylesheet, copied verbatim — all the `bnf-*` classes (tier chips, risk-flag tones, status dots, universe-badge, filter row, closed-trades stats). |

Both stylesheets are required; the page imports both in the live app.

## The design system (same as the rest of the app)

Dark "Navi" theme. Key tokens (CSS variables under `.np-app`):

```
--navi-page        #0a2828   page base
--navi-surface     #0f3333   card surface
--navi-fg1         #faf5f0   bone white (primary text)
--navi-fg2         #a8c4c0   muted teal
--navi-fg3         #468278   dim label
--navi-neon        #d2e632   primary accent (yellow-green)
--navi-positive    #a8d4a0   gains (soft green)
--navi-negative    #e87060   losses (coral)
--navi-warning     #e0c060   amber
Fonts:  Work Sans (sans / display) · DM Mono (numerals + labels)
```

## What this page does

It's the **idea-sourcing** page for a "Buy-the-dip / mean-reversion" (BNF)
strategy. A nightly scan grades ~1,030 tickers (S&P 400 + 600 + ~30 sector
ETFs); you triage the matches, mark research status, buy a starter position,
then manage the open position until price reverts to its 25-day average.

## Page structure (top → bottom)

1. **Top bar** (`.np-top`) — brand + breadcrumb ("NEW STRATEGY · BNF
   mean-reversion") on the left; a row of scan/cache actions on the right
   (Backfill cache, Refresh cache, Refresh risk flags, Refresh ETF scan,
   Refresh equity scan, Refresh all).
2. **Banners** — scan-progress / "N positions ready to sell" status strips.
3. **Universe table** (`.np-section`) — the heart of the page. Title carries
   live counts as chips (**N match** / **N near miss** / **N on watch**), a
   description of the match rule, and a filter row (a `Show:` dropdown +
   "Hide skipped" toggle). The table itself has 14 columns:
   - Ticker (with ETF badge + "near miss" chip), Name / sector, Price, SMA25,
     **Dev %** (deviation from SMA25 — the core signal), SMA200, ADV20 $M,
     Today %, then three **risk-flag** columns (Days since earnings, Insider
     sales 14d, recent 8-Ks 14d) which color green/amber/red, a **Setup**
     quality verdict (Clean / Review / Caution), a **Status** dropdown
     (pending / skipped / considering / approved), and a **Buy** button.
   - Row tone: neon = BNF match, amber = near miss, dim = not in setup /
     skipped.
4. **Open equity positions** (`.np-section`) — a status dot (green = target
   hit/ready to sell, yellow = approaching, grey = holding, red = stale),
   ticker, entry date/price, entry deviation, current price, SMA25, distance
   to SMA25, unrealized %, days held, and a **Sell** button.
5. **Open ETF positions** — same table, separate section (different stale
   threshold).
6. **Closed trades** — a collapsible section with win-rate / avg-return /
   avg-hold stats per universe, then a table of every closed trade
   (entry/exit dates + prices, return %, hold days, exit reason).

## What's simplified in this snapshot

These are live, data-driven React components in the app; here they're static
stand-ins with a handful of representative rows:

- The universe table → ~1,030 live rows in the app; **5 sample rows** here
  (a clean match, a match with a caution flag, a near-miss, an ETF match, a
  neutral non-setup ticker) to show every row state.
- Open positions → **2 equity + 1 ETF** sample rows covering the status tones.
- Closed trades → **3 sample rows** (wins + a stale loss).
- All buttons, dropdowns, scan progress, sorting, count-up animations → static.

## What I'd love help rethinking

- The page is **one very wide, very dense table** (14 columns) plus three more
  tables. On a normal screen the universe table scrolls horizontally. Is there
  a tighter, more scannable composition — cards, a master/detail split, a
  triage queue?
- The **risk-flag columns** (earnings / insider / 8-K / setup quality) are the
  decision-critical part but get lost on the right edge. How should the
  "should I buy this?" verdict be surfaced?
- The **match / near-miss / watch** chips in the title are the daily story —
  could the top of the page be a punchier "here's what the scan found today"
  summary before the firehose table?
- Bring the same **bold, editorial, big-number** feel the dashboard and
  positions page now have to this page.

Don't worry about implementation — layout direction + mockups are what I'm
after.
