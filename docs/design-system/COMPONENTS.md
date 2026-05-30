# COMPONENTS.md — copy-paste reference

Every block below uses **only** classes defined in `tokens.css` + `css/*.css`. Copy the markup, swap the data. Numbers go in DM Mono automatically via the component classes; where you write raw values use the `--mono` font and a real minus `−`.

> Load `tokens.css` then `components.css` first. Wrap the page body in `class="navi"` for the base background/type, or use `.dash` / `.dash-inner` for the dashboard shell.

**Jump to:** [Atoms](#atoms) · [Dashboard](#dashboard) · [Greeks bar](#greeks-bar) · [Position table](#position-table) · [Position card](#position-card) · [Cockpit](#cockpit) · [Large type](#large-type) · [Treemap & buckets](#treemap--buckets) · [Ledger](#ledger) · [Scanner](#scanner) · [Position Lens](#position-lens)

---

## Atoms

### Pills
```html
<span class="pill">↑ Replace CSV</span>
<span class="pill muted">→ View positions</span>
<span class="pill warn">⚠ 3 at risk</span>
```

### Chips & flags
```html
<span class="chip">Equity</span>
<span class="chip neon">Income</span>
<span class="chip pos">Safe</span>
<span class="chip warn">Watch</span>
<span class="chip neg">At risk</span>

<div class="flagrow">
  <span class="flag">Δ 0.62</span>
  <span class="flag warn">IV 38%</span>
  <span class="flag neg">Δ&gt;0.80</span>
  <span class="flag pos">Collecting 68%</span>
  <span class="flag more">+3</span>
</div>
```

### View toggle · filter chips · sort switch
```html
<div class="view-toggle">
  <button class="vt on">Table</button>
  <button class="vt">Cards</button>
  <button class="vt">Cockpit</button>
</div>

<span class="fchip on">Income</span>
<span class="fchip">Investment</span>
<span class="fchip risk on">At risk</span>
<span class="fchip closed">Closed</span>

<label class="sort-toggle on">Smart sort <span class="sw"></span></label>
```

### Live indicators
```html
<span class="live-dot"></span>          <!-- pulsing 6px dot -->
Project Navi<span class="cursor"></span>  <!-- blinking terminal cursor -->
```

---

## Dashboard

Wrap a dashboard page:
```html
<div class="dash"><div class="dash-inner">
  <!-- brand bar, then .row sections -->
</div></div>
```

### Brand bar
```html
<div class="brandbar">
  <div class="mark">
    <span class="logo">SUNNYFI<span class="cursor"></span></span>
    <span class="slash">/</span>
    <span class="route">Positions</span>
    <span class="top-nav">
      <a class="nav-link on">Dashboard</a>
      <a class="nav-link">Positions</a>
      <a class="nav-link">Scan</a>
    </span>
  </div>
  <div class="actions">
    <span class="pill muted">↑ Replace CSV</span>
  </div>
</div>
```

### Ticker strip
```html
<div class="ticker">
  <div class="tick">
    <div class="head"><span class="label">SPY</span><span class="live-dot"></span></div>
    <div class="price">655.06</div>
    <div class="change pos">+0.44%</div>
  </div>
  <!-- repeat .tick … -->
</div>
```

### Winners / losers
```html
<div class="bar-row">
  <span class="num-mono">NVDA</span>
  <div class="bar pos" style="width:80%"></div>
  <span class="num-mono pos" style="text-align:right">+$4,210</span>
</div>
```

### Event calendar
```html
<div class="cal">
  <div class="cal-cell">
    <div class="day-label">Mon</div>
    <div class="cal-event">CPI · 8:30</div>
    <div class="cal-event mine">AAPL roll</div>
  </div>
  <div class="cal-cell today neon-highlight">
    <div class="day-label">Tue</div>
    <div class="cal-event mine">NVDA earnings</div>
    <div class="focus-tag">Focus</div>
  </div>
  <!-- …5 cells -->
</div>
```

### Macro rows / news band
```html
<div class="macro-row">
  <span class="ticker-name">DXY</span>
  <span class="note">Dollar firm into FOMC — watch 2Y break</span>
  <span class="change neg">−0.3%</span>
  <span class="num-mono fg3">103.4</span>
</div>

<div class="news-band">
  <div class="news-card">
    <div class="head"><span class="ticker-tag">NVDA</span><span class="time">09:41</span></div>
    <div class="headline">Chipmaker guides Q4 above consensus; options imply ±9% move.</div>
  </div>
</div>
```

---

## Greeks bar

```html
<div class="greeks-bar">
  <div class="cell lead">
    <div class="gk-lbl">Portfolio value</div>
    <div class="gk-val neon">$604,472</div>
    <div class="gk-sub">+$8,210 today · +1.38%</div>
  </div>
  <div class="cell"><div class="gk-lbl"><span class="glyph">Δ</span> Net delta</div><div class="gk-val neg">−63.30</div><div class="gk-sub">−9.6% exposure</div></div>
  <div class="cell"><div class="gk-lbl"><span class="glyph">Θ</span> Theta</div><div class="gk-val pos">+1,240</div><div class="gk-sub">/ day</div></div>
  <div class="cell"><div class="gk-lbl"><span class="glyph">Γ</span> Gamma</div><div class="gk-val">−4.1</div><div class="gk-sub">per $1</div></div>
  <div class="cell"><div class="gk-lbl">ν Vega</div><div class="gk-val">−820</div><div class="gk-sub">per 1% IV</div></div>
  <div class="cell"><div class="gk-lbl">YTD premium</div><div class="gk-val neon">$56,064</div><div class="gk-sub">68% of target</div></div>
</div>
```
`.cell.lead` = the neon-tinted first cell. `.gk-val` modifiers: `.neon` `.pos` `.neg`.

---

## Position table

One shared header strip + one `<table class="ptable">` per ticker inside a `.ptbl-card`, separated by `.tbl-stack` gap. Use a fixed `<colgroup>` so every card's columns align.

```html
<div class="tbl-stack">
  <div class="ptbl-card">
    <table class="ptable">
      <colgroup><col style="width:30%"><col style="width:14%"><col style="width:14%"><col style="width:14%"><col style="width:14%"><col style="width:14%"></colgroup>

      <tr class="co-head"><td colspan="6">
        <div style="display:flex;justify-content:space-between;align-items:center">
          <div class="co-id"><span class="t">NVDA</span><span class="nm">NVIDIA Corp</span><span class="strat Income">Income</span></div>
          <div class="co-meta"><span class="px">$184.22</span><span class="pos">+1.2%</span><span class="ev">Earns 14d</span></div>
        </div>
      </td></tr>

      <tr class="leg">
        <td class="l"><span class="leg-id"><span class="leg-glyph stock">100</span><span class="leg-name">Shares<span class="side">long</span></span></span></td>
        <td>100</td><td>$162.10</td><td>$184.22</td><td class="pos">+$2,212</td><td class="neon">Δ 100</td>
      </tr>
      <tr class="leg">
        <td class="l"><span class="leg-id"><span class="leg-glyph c-short">C</span><span class="leg-name">195 Call<span class="side">short</span></span></span></td>
        <td>−1</td><td>$3.20</td><td>$2.05</td><td class="pos">+$115</td><td class="neg">Δ −38</td>
      </tr>

      <tr class="agg">
        <td class="l"><span class="agg-lbl">Net position</span></td>
        <td colspan="3" class="strong">Covered call</td>
        <td class="pos strong">+$2,327</td>
        <td class="posd"><span class="num-mono neon">Δ 62</span></td>
      </tr>
    </table>
  </div>
</div>
```
- `.strat` modifiers: `.Income` (neon) · `.Investment` (sage) · `.Yield` (amber).
- `.leg-glyph` modifiers: `.stock` `.c-short` `.c-long` `.p-short` `.p-long`.
- `.ptbl-card.attn` (coral border) for an at-risk ticker; `.ptbl-card.closed` dims it.
- Hover-magnify (`scale(1.7)` on value cells) is automatic via `positions.css`.

---

## Position card

```html
<div class="pcard">
  <div class="pc-head">
    <div class="pc-id"><div class="t">AAPL</div><div class="nm">Apple Inc <span class="pc-strat Income">Income</span></div></div>
    <div class="pc-px"><div class="v">$229.10</div><div class="ch pos">+0.8%</div><div class="pc-ev far">Earns 38d</div></div>
  </div>
  <div class="pc-greeks">
    <div class="pc-gk"><div class="k">Δ</div><div class="v">+58</div></div>
    <div class="pc-gk"><div class="k">Θ</div><div class="v pos">+42</div></div>
    <div class="pc-gk"><div class="k">IV</div><div class="v">22%</div></div>
    <div class="pc-gk"><div class="k">DTE</div><div class="v">16</div></div>
  </div>
  <div class="pc-foot">
    <div class="net"><div class="k">Open P&amp;L</div><div class="v pos">+$3,180</div></div>
    <div class="posd-wrap"><div class="k">Position Δ</div><div class="v">+58</div></div>
  </div>
</div>
```
Grid them with `.card-grid` (2-col). `.pcard.attn` = at-risk border.

---

## Cockpit

A signed delta-exposure spectrum per ticker.
```html
<div class="cockpit">
  <div class="ck-row">
    <div class="ck-id">
      <div class="top"><span class="t">NVDA</span><span class="net">net Δ +62</span></div>
      <div class="meta">Covered call · Income</div>
    </div>
    <div class="ck-track">
      <div class="ck-zero" style="left:50%"></div>
      <div class="ck-seg stock"  style="left:50%;width:24%"><span class="seglab">+100</span></div>
      <div class="ck-seg c-short" style="left:38%;width:12%"></div>
      <div class="ck-net-mark" style="left:62%"><span class="nm-val">+62</span></div>
    </div>
    <div class="ck-rail">
      <div class="ck-gk"><div class="k">Θ</div><div class="v pos">+42</div></div>
      <div class="ck-flags"><span class="flag pos">On track</span></div>
    </div>
  </div>
</div>
```
`.ck-seg` colors: `.stock` (neon) `.c-short` (coral) `.p-short` (sage) `.c-long` `.p-long`. `.ck-row.attn` adds a coral inset bar.

---

## Large type

The full-screen "Show in Large Type" data story (mount via a portal to `document.body` so `position:fixed` escapes any transformed wrapper). Skeleton:
```html
<div class="fs-stage">
  <div class="fs-top">
    <span class="fs-eyebrow"><span class="d">●</span> Position · large type</span>
    <span class="fs-count">03<span class="sl">/</span>12</span>
    <button class="fs-exit">Close <span class="k">Esc</span></button>
  </div>
  <div class="fs-main">
    <div class="fs-left">
      <div class="fs-kicker">Covered call · Income</div>
      <div class="fs-ticker">NVDA</div>
      <div class="fs-name">NVIDIA Corp</div>
      <div class="fs-spotline"><span class="px">$184.22</span><span class="fs-day pos">+1.2%</span></div>
      <div class="fs-headline">
        <div class="fs-hk">Open P&amp;L</div>
        <div class="fs-hv pos">+$2,327</div>
      </div>
    </div>
    <div class="fs-right">
      <div>
        <div class="fs-slabel">Attention</div>
        <div class="fs-alert warn"><div class="fs-alert-h">IV elevated — 38th pct</div><div class="fs-alert-s">Post-event crush 15–25% likely after earnings.</div></div>
      </div>
    </div>
  </div>
  <div class="fs-foot">
    <button class="fs-nav">← Prev</button>
    <span class="fs-hint">← → to step · Esc to close</span>
    <button class="fs-nav">Next →</button>
  </div>
</div>
```
There is also a modal (`.lt-scrim` → `.lt-card`) and drawer (`.lt-drawer`) variant of the same `.lt-body` content in `positions.css`.

---

## Treemap & buckets

```html
<div class="treemap">
  <div class="tile lead"><div class="glyph">42% NAV</div><div class="sector">Income</div><div class="name">NVDA</div><div class="meta">$254k · +6.1%</div></div>
  <div class="tile pos"><div class="sector">Tech</div><div class="name">AAPL</div><div class="meta">$92k</div></div>
  <!-- tiles: .lead .pos .neg .warn -->
</div>

<div class="bucket-row">
  <div class="b-name"><span class="b-dot" style="background:var(--neon)"></span><div><div class="b-label">Income</div><div class="b-meta">12 positions</div></div></div>
  <div class="b-bar-wrap"><div class="b-bar-fill" style="width:64%;background:var(--neon)"></div><div class="b-bar-mv">$386k</div></div>
  <div class="b-right"><div class="b-pnl pos">+$12,400</div><div class="b-pct">+3.3%</div></div>
</div>
```
Also: `.holdings-row` (top-holdings rail), `.protection` (downside-protection bar), `.realized-row` (realized-P&L hairlines).

---

## Ledger

```html
<div class="ledger-group">
  <span class="g-name"><span class="g-dot" style="background:var(--neon)"></span>Income</span>
  <span class="g-meta">12 positions</span>
  <span class="g-right">Unrealized <b>+$18,200</b></span>
</div>
<div class="ledger-head">
  <span class="label">Ticker</span><span class="label">Sector</span><span class="label">Price</span>
  <span class="label">Size</span><span class="label">Unrealized</span><span class="label">Realized</span><span class="label">IV</span><span class="label">Signals</span>
</div>
<div class="ledger-row">
  <span class="t">NVDA</span>
  <span class="sec">Semis</span>
  <span class="price">$184.22 <span class="ch pos">+1.2%</span></span>
  <span class="size">100 sh</span>
  <span class="unr pos">+$2,327</span>
  <span class="real">+$540</span>
  <span class="num-mono">42%</span>
  <span class="sigs"><span class="chip warn">IV</span><span class="chip neon">Δ</span></span>
</div>
```

### P&L tooltip
```html
<div class="pnl-tip">
  <div class="tip-head"><span class="tip-t">NVDA</span><span class="tip-sec">Semis</span></div>
  <div class="tip-hero"><span class="tip-pnl pos">+$2,327</span><span class="tip-sub">open</span></div>
  <div class="tip-rows">
    <div class="tip-row"><span>Shares</span><span class="pos">+$2,212</span></div>
    <div class="tip-row"><span>Short call</span><span class="pos">+$115</span></div>
  </div>
</div>
```

---

## Scanner

### Triage card
```html
<div class="tcard match">
  <div class="head">
    <div class="id"><span class="t">META</span><span class="badge">EQ</span></div>
    <span class="verdict clean">Clean</span>
  </div>
  <div class="name">Meta Platforms</div>
  <div class="sector">Communication</div>
  <div class="price-block"><div class="price">$612.40</div><div class="price-sub"><span class="live-dot"></span><span class="today pos">+1.4% today</span></div></div>
  <div class="dev-wrap">
    <div class="dev-row"><span class="l">Dev from MA</span><span class="v up">−6.2%</span></div>
    <div class="dev-band"><div class="zone" style="left:30%;width:40%"></div><div class="marker neon" style="left:44%"></div></div>
    <div class="dev-axis"><span>−15%</span><span class="neon">target</span><span>+5%</span></div>
  </div>
  <div class="seg">
    <button class="pending">Pending</button>
    <button class="skipped">Skip</button>
    <button class="considering">Watch</button>
    <button class="on approved">Approve</button>
  </div>
</div>
```
Card state classes: `.match` (neon) · `.borderline` (amber) · `.approved` · `.bought`. `.verdict` classes: `.clean` `.review` `.caution` `.none`.

### Pipeline
```html
<div class="pipeline">
  <div class="stage pending"><div class="l">Screened</div><div class="v">248</div><div class="sub">universe</div></div>
  <div class="sep"></div>
  <div class="stage considering"><div class="l">Considering</div><div class="v">31</div><div class="sub">in review</div></div>
  <div class="sep"></div>
  <div class="stage approved"><div class="l">Approved</div><div class="v">8</div><div class="sub">queued</div></div>
  <div class="sep"></div>
  <div class="stage bought"><div class="l">Bought</div><div class="v">3</div><div class="sub">today</div></div>
</div>
```

### Status tape (marquee)
```html
<div class="tape">
  <div class="tape-track">
    <!-- duplicate the item set twice for a seamless loop -->
    <span class="tape-item"><span class="ts">09:41</span><span class="t">NVDA</span><span class="arrow">→</span><span class="s approved">approved</span></span>
    <span class="tape-item"><span class="ts">09:38</span><span class="t">AMD</span><span class="arrow">→</span><span class="s considering">considering</span></span>
    <!-- … then repeat all items again -->
  </div>
</div>
```

### Universe table (row)
```html
<table class="uni-table">
  <thead><tr><th>Ticker</th><th>Name</th><th class="num">Price</th><th class="num">Dev</th><th class="ctr">Risk</th><th class="ctr">Status</th></tr></thead>
  <tbody>
    <tr class="match">
      <td><div class="tk"><span class="t">NVDA</span><span class="b eq">EQ</span></div></td>
      <td class="nm">NVIDIA <span class="sec">Semis</span></td>
      <td class="num"><span class="px">$184.22</span></td>
      <td class="num"><span class="dev neon">−6.2%</span></td>
      <td class="ctr"><span class="risk"><span class="dot clean"></span></span></td>
      <td class="ctr"><button class="stat approved">Approved</button></td>
    </tr>
  </tbody>
</table>
```

### Scan hero
```html
<div class="scan-hero">
  <div class="col"><div class="label">Matches</div><div class="big neon">12</div><div class="cap">in expected-move zone</div></div>
  <div class="col"><div class="label">Borderline</div><div class="big warn">31</div><div class="cap">within 2% of band</div></div>
  <div class="col"><div class="label">Screened</div><div class="big fg2">248</div><div class="cap">universe today</div></div>
  <div class="col meta">
    <div class="live-line"><span class="live-dot"></span> Scanning</div>
    <div class="scan-cnt">248<span class="of"> / 248</span></div>
    <div class="stamp">Updated <b>09:41</b> · <span class="neon">live</span></div>
  </div>
</div>
```

---

## Position Lens

**Wrap the whole page in `<div class="lens">`** — the Lens card classes are scoped under it so `.pcard` doesn't collide with the Positions card.

### Layers control bar
```html
<div class="lens">
  <div class="layers">
    <span class="lh">Layers</span>
    <button class="layer-toggle on"><span class="sw shares"></span>Shares</button>
    <button class="layer-toggle on"><span class="sw call"></span>Calls</button>
    <button class="layer-toggle on"><span class="sw put"></span>Puts</button>
    <span class="sep"></span>
    <button class="layer-toggle on"><span class="sw zone"></span>Exp-move</button>
    <button class="layer-toggle"><span class="sw earnings"></span>Earnings</button>
    <button class="layer-toggle"><span class="sw oi"></span>OI</button>
    <button class="reset">Reset</button>
  </div>
```

### Band card + scrubber
```html
  <div class="pcard">
    <div class="pc-head">
      <div class="pc-id"><div class="pc-t">NVDA</div><div class="pc-nm"><span class="pc-sector">Semiconductors</span><span class="pc-name">NVIDIA Corp</span></div></div>
      <div class="pc-earn">Earnings <b>14d</b> · <span class="em">exp-move ±9.2%</span></div>
    </div>
    <div class="pc-pricerow">
      <div class="pc-price-blk"><div class="pc-px">$184.22</div><div class="pc-px-sub"><span class="live-dot"></span><span class="pos">+1.2% today</span></div></div>
    </div>
    <div class="band-wrap">
      <svg class="band-svg" viewBox="0 0 900 150"><!-- axis, strikes, zone, live line --></svg>
    </div>
    <div class="scrubber">
      <button class="play">▶</button>
      <div class="track"><input type="range" min="0" max="100" value="100"></div>
      <div class="date-read live">Live · <b>now</b></div>
    </div>
    <div class="summary">Spot <b>$184.22</b> sits <span class="neon">inside</span> the expected-move zone.</div>
  </div>
</div>
```

### What-if readout & annotation pin (overlay HTML over the band)
```html
<div class="wf-readout">
  <div class="r-px">$198.40</div>
  <div class="r-row"><span class="k">Short call</span><span class="v neg">ITM −$340</span></div>
  <div class="r-row"><span class="k">Net Δ</span><span class="v warn">+18</span></div>
</div>

<div class="note-pin"><div class="np-flag">Roll target<span class="np-x">✕</span></div></div>
```

### Lens tooltip
```html
<div class="tooltip show">
  <div class="tt-head"><span class="tag call-sold">Call · short</span><span class="state active">active</span></div>
  <div class="tt-row big"><span class="k">Strike</span><span class="v">$195</span></div>
  <div class="tt-row"><span class="k">Δ</span><span class="v neg">−38</span></div>
  <div class="tt-bar"></div>
  <div class="tt-foot neon">$10.78 OTM · 14 DTE</div>
</div>
```
