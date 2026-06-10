# Handoff — Standardized cards + drill-in popups

**Status:** All design decisions locked. Implementation ready to start. ~6 files to touch.

**Goal:** Implement the standardized-popup design from `~/Downloads/design_handoff_standardized_popups/` (README + 5 source files there). All three Open cards (Call credit · Puts bought · Shares) get one tappable drill-in each, all three sheets share the same shape.

---

## Decisions locked (in conversation)

| # | Decision | Choice | Implication |
|---|---|---|---|
| 1 | "Collected" math on Open call credit card | **Open-only** (`Σ remaining_contracts · premium · 100` over open short calls). Same as currently shipped. | No change. `openCallCredit` in `TradesData.swift` stays as is. The new "Earned" stat tile and "Calls offset" tile use the same number. |
| 2 | Effective basis row position on Open shares card | **Move to last row** (was slot 2). Becomes the tappable drill-in. | Reorder rows in `OpenSharesCard` in `TickerCard.swift`. New order: Cost basis · Value now · Today · Effective basis. |
| 3 | Chevrons on tappable rows | **Keep them** (`›` neon, after the value, before the row edge). | No change to existing `FundsHedgeRow`. New tappable rows (Net cost, Effective basis) get the same chevron treatment. |
| 4 | Hedge Funding popup layout | **Rebuild** to new standardized shape (head + Patch block + By-position block + Done). | Full rewrite of `HedgeFundingSheet.swift`. |
| 5 | Downside Protection popup | **Build new** (opens from Net cost on Open puts bought). | New file `DownsideProtectionSheet.swift`. |
| 6 | Break-even popup | **Build new** (opens from Effective basis on Open shares). Math uses **effective basis** (lifetime-adjusted), not nominal cost basis. | New file `BreakevenSheet.swift`. Per-ticker lifetime premium needed. |

---

## What's already shipped (DO NOT redo)

Recent commits on `main`:

- `f56e8dc` — Original hedge-structure rows (added Funds hedge / Net cost / Effective basis rows + first-pass HedgeFundingSheet)
- `d71335c` — Three page dots on the carousel
- `e53afbe` — Removed mock IV data fallback (unrelated, just FYI)

In `TradesData.swift` already:
- `openCallCredit(store:)`, `openCallCreditNow`, `openCallCreditTimeValue`
- `openPutsPaid`, `openPutsValueNow`, `openPutsTimeValue`
- `openSharesCost`, `openSharesValue`, `openSharesTodayPnL`
- `lifetimePremiumHarvested(store:)` — **portfolio-wide** (signed across opens + closes)
- `fundedPct`, `hedgeSurplus`, `netCost`, `netCostBookPct`
- `effectiveBasis`, `effectiveBasisPct`, `hasPuts`
- Structs: `HedgePutRow` + `hedgePutRows(store:)`, `HedgeCreditRow` + `hedgeCreditRows(store:)`

In `TickerCard.swift` already:
- `OpenCallCard` with `FundsHedgeRow` tappable bottom row (has chevron — keep per Decision 3)
- `OpenPutsBoughtCard` with static `NoteRowSimple` "Net cost" bottom row (needs to become tappable)
- `OpenSharesCard` with `Effective basis` at slot 2 (needs to move to last + become tappable)
- Helper components: `FundsHedgeRow`, `NoteRowSimple`, `CardChrome`, `PRow`, `FullBleedHair`

In `TradesScreen.swift` already:
- 3-page carousel (calls/puts/shares) with dots
- `@State showHedgeFunding` + `.sheet(isPresented:)` for HedgeFundingSheet

In `IVGauges.swift`:
- `IVRGauge(value:threshold:showValueLabel:)` — the 5-segment IVR gauge we already built. Use this as a reference for `ZoneGauge`.

---

## What needs to be built

### 1. Reorder rows in `OpenSharesCard` (TickerCard.swift)

Move `Effective basis` row to last position. Make it a tappable button (chevron neon `›`, same pattern as `FundsHedgeRow`).

**New row order:**
1. Cost basis (static PRow)
2. Value now (static PRow with gainPct)
3. Today (static PRow with todayPct)
4. Effective basis (tappable, with chevron) → calls `onBreakeven`

Add `onBreakeven: () -> Void = {}` param. Make the row a Button mirroring `FundsHedgeRow`.

### 2. Make `Net cost` row tappable in `OpenPutsBoughtCard`

Currently uses `NoteRowSimple` (static). Wrap it in a Button. Add `onProtection: () -> Void = {}` param. Add the same chevron treatment as `FundsHedgeRow`.

Implementation idea: rename `NoteRowSimple` to `NoteRow` and add an optional `onTap: (() -> Void)?` parameter — when non-nil, wrap content in a Button + render chevron.

### 3. Add data layer helpers in `TradesData.swift`

#### A. Per-ticker lifetime premium

```swift
/// Lifetime net premium harvested for a SINGLE ticker — used by
/// the Break-even sheet to compute per-lot effective basis.
/// Same sign convention as the portfolio-wide
/// lifetimePremiumHarvested helper.
static func lifetimePremiumHarvested(for ticker: String, store: PortfolioStore) -> Double
```

Iterate `store.allTrades` filtered by ticker + non-voided, apply the same 4-case sign convention as the existing portfolio-wide helper.

#### B. Downside protection rows

```swift
struct ProtectionRow: Identifiable, Sendable {
    let id: String          // option_trade_id
    let ticker: String
    let strike: Double
    let spot: Double        // current company.spot
    let contracts: Double
    let expiry: String
    let paid: Double        // contracts × premium × 100
    /// (spot − strike) / spot × 100. Positive = OTM cushion before
    /// the put activates. Smaller = closer to active protection.
    let cushionPct: Double
}

static func protectionRows(store: PortfolioStore) -> [ProtectionRow]
```

Walk open long puts (`action=open, option_type=put, direction=long, remainingContracts>0`).
For each, look up the company's spot, compute cushion. Sort **ascending by cushionPct** (tightest first).

#### C. Break-even rows (effective basis math)

```swift
struct BreakevenRow: Identifiable, Sendable {
    let id: String          // ticker
    let ticker: String
    let shares: Double
    let avg: Double         // raw cost per share
    let last: Double        // current price
    /// Per-ticker lifetime premium harvested ÷ shares. Subtract
    /// from avg to get effectiveAvg.
    let premiumPerShare: Double
    var effectiveAvg: Double { avg - premiumPerShare }
    var underwater: Bool { last < effectiveAvg }
    /// Gain vs effectiveAvg as a %. (last − effectiveAvg) / effectiveAvg × 100.
    var gainPct: Double {
        guard effectiveAvg > 0 else { return 0 }
        return (last - effectiveAvg) / effectiveAvg * 100
    }
    /// Recovery move needed: (effectiveAvg − last) / last × 100.
    /// Always >= 0 when underwater; 0 or negative otherwise.
    var needPct: Double {
        guard last > 0 else { return 0 }
        return (effectiveAvg - last) / last * 100
    }
}

static func breakevenRows(store: PortfolioStore) -> [BreakevenRow]
```

One row per held ticker with `stockLeg.qty > 0`. Sort **underwater-first**, within each group by largest needPct first (so the worst lot is at the top of the underwater group, smallest recovery at the bottom of the in-profit group).

### 4. Build `ZoneGauge` shared component

New file `ZoneGauges.swift` (or add to existing `IVGauges.swift`).

Mirror `IVRGauge`'s 5-segment structure but make labels generic:

```swift
struct ZoneGauge: View {
    let value: Double             // 0..100, clamped
    let leftLabel: String         // e.g. "UNFUNDED", "OUT OF POCKET", "UNDERWATER"
    let rightLabel: String        // e.g. "FULLY FUNDED", "FULLY OFFSET", "IN PROFIT"
    var showValueLabel: Bool = false
    var threshold: Double? = nil  // optional dashed tick
}
```

**Spec from design `popups.css`:**
- 5 segments, height 9pt, gap 3pt, radius 2pt
- Segment colors: z1 `tintMuted` · z2 `fg1@10%` · z3 `page2` · z4 `tintNeon` · z5 `neon@34%`
- Marker: 3pt × 19pt, `fg1` bg, 2pt `elevated` outer ring
- Scale labels: mono 8.5pt, uppercase, tracking 0.5pt, `fg4`

Reuse this for all three new sheets. The existing `IVRGauge` can stay as a thin wrapper around ZoneGauge with `leftLabel:"0", rightLabel:"100"` and the threshold tick — or just leave IVRGauge as-is and live with the parallel code.

### 5. Build `MiniTrack` shared component

For per-position rows in Downside Protection + Break-even sheets.

```swift
struct MiniTrack: View {
    /// Width of the colored fill, 0..100.
    let fillPct: Double
    /// Tone — drives fill + mark color.
    let tone: ToneFlag        // pos | neg
    /// Mark position (vertical bar), 0..100. Usually == fillPct.
    let markPct: Double
}
```

**Spec from popups.css `.pl-track`:**
- Track: 7pt height, 3pt radius, bg `page2`, margin-top 13pt
- Fill: `pos` → `positive @ 50%`, `neg` → `negative @ 50%`, radius 3 0 0 3
- Mark: 3pt × 15pt, full color (no opacity), radius 2, top offset -4
- End marker: 3pt × 15pt at far right (100%), `fg1` bg with 2pt `elevated` ring

### 6. Rewrite `HedgeFundingSheet.swift`

Delete current implementation. New shape per `b-sheets.jsx` → `HedgeFundingSheet`:

```
Head:
  Eyebrow "FUNDS HEDGE" (mono 9pt, neon, tracking 1.6pt, uppercase)
  Title "Hedge funding" (Work Sans 800 27pt, fg1, tracking -0.03em)

Patch block (.st-block, padding 18 top/bottom, border-top hair, first-child no border + padding-top 4):
  Top row:
    "COVERAGE" mini-label (mono 9pt, fg3, tracking 1.8pt, uppercase)
    Status tag (top-right):
      - Under-funded → "X% FUNDED" with .warn tone (tintWarning bg, warning text)
      - Fully funded → "Fully funded" with .good tone (neon bg, white text)
  Hero (margin 14 0 2):
    BigNum: %X% (or +$X surplus when fullyFunded) — Work Sans 800 46pt, tracking -0.035em, neon color
    Caption: "of the hedge paid by calls" (or "surplus over the hedge") — mono 11pt, fg3, max-width 160pt
  ZoneGauge:
    value = fundedPct (or 100 when fullyFunded)
    leftLabel "UNFUNDED" rightLabel "FULLY FUNDED"
  3-up stat grid (margin 18 0 2, grid gap 10, page2 bg, radius lg):
    Tile 1: +$X EARNED (positive tone num, "EARNED" label)
    Tile 2: $X NET COST  (or +$X SURPLUS when fullyFunded)
    Tile 3: ±$X PUTS P/L (signed mark-to-market: putValue − putPaid)

By position block (.st-block, border-top):
  "BY POSITION" mini-label
  For each HedgePutRow (already sorted by paid desc):
    pl-row layout:
      Left: ticker (Work Sans 700 16pt, fg1, tracking -0.02em)
      Sub: "<qty> × $<strike> put · <expiry>" (mono 11pt, fg3, margin-top 7)
      Right: pl-num = "$<paid>" (mono 18pt, 600, fg1) + pl-lbl = "cost" (mono 9pt, fg3)

Footer:
  Done button — btn2 ghost (capsule outline, neon text, mono 12pt 0.4 tracking, min-height 48pt)
```

**Stat tile colors:**
- "Earned" — `pos` tone (positive green)
- "Net cost" — default ink (fg1) when under-funded; flips to "SURPLUS" label + signed amount when funded
- "Puts P/L" — `sgn(putValue − putPaid)` → pos if positive, neg if negative

### 7. Build new `DownsideProtectionSheet.swift`

Same template, different content:

```
Head:
  Eyebrow "NET COST"
  Title "Downside protection"

Patch:
  mini "NET COST" + tag "X.XX% OF BOOK" .muted (tintMuted bg, fg3 text)
  Hero: $<netCost> (BigNum, default fg1)
  Caption: "net cost of protection"
  ZoneGauge: value = fundedPct, left "OUT OF POCKET", right "FULLY OFFSET"
  Stats:
    Tile 1: $<putPaid> · "PUTS PAID"
    Tile 2: +$<callCredit> · "CALLS OFFSET" (pos tone)
    Tile 3: <count of protectionRows> · "PROTECTIVE PUTS"

By position (one per ProtectionRow, already sorted tightest cushion first):
  Left:
    Ticker
    Tag: "X.X% CUSHION" .warn (tintWarning bg, warning text)
    Sub: "protects below $<strike> · now $<spot>"
    MiniTrack:
      protectedZoneWidth = max(8, min(88, cushionPct/20 × 100))  // per design JSX
      floorPct = max(0, 100 - protectedZoneWidth)
      fill = floorPct% wide, .pos tone
      mark = at floorPct%, .pos tone
      end marker visible
  Right: "$<paid>" + "cost"

Footer: Done button
```

### 8. Build new `BreakevenSheet.swift` (EFFECTIVE BASIS MATH)

```
Head:
  Eyebrow "OPEN SHARES"
  Title "Break-even"

Patch:
  Let rows = breakevenRows(store:)
  Let under = rows.filter { $0.underwater }
  Let worst = under.first   // sorted underwater-first
  mini "BELOW COST" + tag:
    under.count > 0 → "<N> UNDERWATER" .neg
    else → "All in profit" .pos
  Hero: <under.count> (BigNum, neg color if any underwater, else pos)
  Caption: "of <rows.count> lots below cost"
  ZoneGauge:
    value = rows.count > 0 ? (rows.count - under.count) / rows.count × 100 : 100
    left "UNDERWATER", right "IN PROFIT"
  Stats:
    Tile 1: worst != nil → "+<worst.needPct>%" with neg tone, label "<worst.ticker> TO RECOVER"
           else → "—", label "FURTHEST"
    Tile 2: <under.count> · "UNDERWATER"
    Tile 3: <rows.count - under.count> · "IN PROFIT" (pos tone num)

By position (already sorted underwater-first, worst first):
  Left:
    Ticker
    Tag: "<gainPct%>" (pos/neg by sign — gainPct vs effectiveAvg)
    Sub: "now $<last> · cost $<effectiveAvg>"  // effectiveAvg not raw avg!
    MiniTrack:
      recPct = max(6, min(100, last/effectiveAvg × 100))
      fill = recPct% wide, .neg if underwater else .pos
      mark = at recPct%, same tone
      end marker
  Right:
    underwater → "+<needPct>%" .neg + "to recover"
    else → "✓" .pos + "in profit"

Footer: Done button
```

### 9. Wire all three sheets in `TradesScreen.swift`

Add state:
```swift
@State private var showDownsideProtection: Bool = false
@State private var showBreakeven: Bool = false
```

In the carousel, thread the new callbacks into the cards:
- `OpenPutsBoughtCard(..., onProtection: { showDownsideProtection = true })`
- `OpenSharesCard(..., onBreakeven: { showBreakeven = true })`

Add two new `.sheet(isPresented:)` modifiers next to the existing HedgeFundingSheet presentation. All three sheets use:
- `.presentationDetents([.large])`
- `.presentationDragIndicator(.visible)`
- `.presentationBackground(Color.theme.elevated)`

---

## Math reference (in one place)

### Portfolio-wide (already in TradesData.swift)

```
callCredit         = Σ remaining · premium · 100  over open short calls
putPaid            = Σ remaining · premium · 100  over open long puts
putValue           = Σ remaining · last_mark · 100  over open long puts
                     (fallback to entry premium when no greek mark)
sharesCost         = Σ shares · avg
sharesValue        = Σ shares · last

fundedPct          = min(100, round(callCredit / putPaid × 100))
hedgeSurplus       = callCredit − putPaid             // > 0 over-funded
netCost            = putPaid − callCredit              // out of pocket
netCostBookPct     = netCost / sharesValue × 100
putGain            = putValue − putPaid               // mark-to-market on hedge
```

### New (need to add)

```
// Per-ticker
lifetimePremiumHarvested(ticker) =
  Σ over non-voided trades for that ticker:
    open  · short  → +premium·ct·100
    open  · long   → −premium·ct·100
    close · short  → −premium·ct·100
    close · long   → +premium·ct·100

// Per-put protection row
cushionPct         = (spot − strike) / spot × 100     // > 0 OTM

// Per-equity-lot breakeven row (uses lifetime, not open)
premiumPerShare    = lifetimePremiumHarvested(ticker) / shares
effectiveAvg       = avg − premiumPerShare
underwater         = last < effectiveAvg
gainPct            = (last − effectiveAvg) / effectiveAvg × 100
needPct            = (effectiveAvg − last) / last × 100  // recovery move
```

---

## Design tokens — JS → SwiftUI mapping

| Design `var(--*)` | iOS `Color.theme.*` |
|---|---|
| `--fg1` | `.fg1` |
| `--fg2` | `.fg2` |
| `--fg3` | `.fg3` (muted labels) |
| `--fg4` | `.fg4` (gauge scale) |
| `--neon` | `.neon` |
| `--positive` | `.pos` |
| `--negative` | `.neg` |
| `--warning` | `.warn` |
| `--tint-positive` | `.tintPos` |
| `--tint-negative` | `.tintNeg` |
| `--tint-warning` | `.tintWarn` |
| `--tint-muted` | `.tintMuted` |
| `--tint-neon` | `.tintNeon` |
| `--page-2` | `.page2` |
| `--elevated` | `.elevated` |
| `--hair` | `.hair` |

Fonts:
- Work Sans → `.system(size:, weight:)` (default design)
- DM Mono → `.system(size:, weight:, design: .monospaced)` + `.monospacedDigit()`

Radii:
- `--radius-lg` 10 → `Radius.lg`
- `--radius-pill` → `Radius.pill` (or `Capsule()`)

Real minus sign: use `"\u{2212}"` (U+2212), not ASCII `-`, on all signed numbers per design house rule.

---

## How to test

iOS 26.5 sim is the working dev environment (iOS 27 has been flaky):

```bash
SIM="8C7889CF-387F-4DEF-9680-B8F6637784BE"
export DEVELOPER_DIR="/Users/niketparekh/Downloads/Xcode-beta.app/Contents/Developer"

cd "ios-app/Sunnyfi"
DEVELOPER_DIR=$DEVELOPER_DIR xcodebuild -scheme Sunnyfi \
  -destination "id=$SIM" \
  -derivedDataPath /tmp/SunnyfiBuild265 build

APP="/tmp/SunnyfiBuild265/Build/Products/Debug-iphonesimulator/Sunnyfi.app"
"$DEVELOPER_DIR/usr/bin/simctl" install $SIM "$APP"
"$DEVELOPER_DIR/usr/bin/simctl" launch $SIM com.sunnyfi.app
"$DEVELOPER_DIR/usr/bin/simctl" io $SIM screenshot /tmp/check.png
```

User signs in once with their 10-digit code, then Trades tab → swipe through the three carousel pages, tap each bottom row to verify the popups render.

---

## File locations

**Design references:**
- `~/Downloads/design_handoff_standardized_popups/README.md` — full spec
- `~/Downloads/design_handoff_standardized_popups/src/b-sheets.jsx` — the three new sheets (HedgeFundingSheet · ProtectionSheet · BreakevenSheet)
- `~/Downloads/design_handoff_standardized_popups/src/pos-cards.jsx` — card row triggers (CallRows · PutRows · ShareRows · NoteRow · HedgeRowBtn)
- `~/Downloads/design_handoff_standardized_popups/src/pos-data.jsx` — derived data including HEDGE_PROTECTION + SHARES_BREAKEVEN
- `~/Downloads/design_handoff_standardized_popups/src/popups.css` — exact pixel specs for st-block, zg, pl-row, pl-track
- `~/Downloads/design_handoff_standardized_popups/src/bh-app.jsx` — sheet host wiring

**iOS files to change:**
- `ios-app/Sunnyfi/Sunnyfi/TradesData.swift` — add ProtectionRow, BreakevenRow, helpers (Decision 6 needs per-ticker lifetime)
- `ios-app/Sunnyfi/Sunnyfi/TickerCard.swift` — reorder shares card rows, make Net cost + Effective basis tappable
- `ios-app/Sunnyfi/Sunnyfi/TradesScreen.swift` — wire two new sheet states
- `ios-app/Sunnyfi/Sunnyfi/HedgeFundingSheet.swift` — full rewrite
- `ios-app/Sunnyfi/Sunnyfi/DownsideProtectionSheet.swift` — NEW
- `ios-app/Sunnyfi/Sunnyfi/BreakevenSheet.swift` — NEW
- `ios-app/Sunnyfi/Sunnyfi/IVGauges.swift` (or new `ZoneGauges.swift`) — add ZoneGauge + MiniTrack

---

## Commit style

User prefers iterative commits + push per logical change. From `CLAUDE.md`:

> **Always commit + push iteratively.** No "want me to commit?" prompts. After every meaningful edit, `git add` the relevant files (NOT TabRootView.swift bisect reverts, NOT xcuserstate, NOT supabase/.temp/*), commit with a real message, and `git push origin main`.

Suggested commit order:

1. Data layer additions (per-ticker lifetime, ProtectionRow + builder, BreakevenRow + builder)
2. ZoneGauge + MiniTrack shared components
3. Card row changes (reorder shares, make Net cost + Effective basis tappable)
4. HedgeFundingSheet rewrite
5. DownsideProtectionSheet new
6. BreakevenSheet new
7. TradesScreen wiring (sheet states + presentations)

Each commit should build clean on iOS 26.5 sim before pushing.

---

## Quick acceptance checklist

- [ ] Open shares card row order: Cost basis → Value now → Today → Effective basis
- [ ] Tapping Funds hedge → Hedge funding sheet (new standardized shape)
- [ ] Tapping Net cost → Downside protection sheet
- [ ] Tapping Effective basis → Break-even sheet (effective basis math)
- [ ] All three sheets share the same Patch → By-position → Done shape
- [ ] All three sheets use the same ZoneGauge (5-segment + marker)
- [ ] Chevrons preserved on all three tappable bottom rows
- [ ] Real minus sign `−` on all signed numbers
- [ ] Numbers use `.monospacedDigit()` for tabular alignment
- [ ] Builds clean on iOS 26.5 simulator
- [ ] Sheets present with `.presentationDetents([.large])` and `Color.theme.elevated` background
