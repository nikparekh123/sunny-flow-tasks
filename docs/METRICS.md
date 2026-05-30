# Sunnyfi Metrics Glossary — Draft

> **Purpose.** Single source of truth for every number that appears in the app.
> Each metric has exactly one canonical name, one definition, one
> implementation. Pages **read** these; they never re-derive.
>
> **How to read this doc.** For each metric:
> - **Definition** — the math, in plain words.
> - **Inputs** — DB tables/fields it depends on.
> - **Window** — `now` (point-in-time), `period(start, end)` (rolling), or
>   `all-time`.
> - **Sign** — `+` always positive, `±` signed.
> - **Canonical hook** — the React hook / function pages should call. (To-be
>   built; current implementations listed under "Where it's computed today.")
> - **Where it's computed today** — every file that currently derives it.
>   When more than one row appears here, that's drift we need to delete.
> - **Notes / edge cases** — gotchas and renaming proposals.
>
> ---
> **Status:** v0 — first draft, **for review.** Not all metrics are listed;
> we'll grow the list as we audit more surfaces.

---

## Raw data tables (sources of truth at the DB layer)

| Table | Key fields used | Role |
|---|---|---|
| `positions` | `ticker, quantity, avg_cost, current_price, status, realized_stock_pl, earnings_date` | One row per ticker. `realized_stock_pl` accumulates *stock* realized as shares are sold; option realized is computed from `option_trades`. |
| `option_trades` | `ticker, action(open\|close), option_type(call\|put), direction(short\|long), contracts, premium, strike, expiry, closes_trade_id, closed_via, share_pnl, trade_date` | Every option open + close. Closes link to opens via `closes_trade_id`. |
| `share_sells` | `ticker, quantity, price, realized_pl, source(manual\|assignment), trade_date` | One row per share-decreasing event. `realized_pl` snapshotted at sale time. |
| `daily_closes` | `ticker, date, close_price` | EOD prices for historical value reconstruction. Has gaps; metrics must carry-forward. |

---

## The atoms — every metric reduces to a combination of these

> **Why this layer matters.** When you say "cost," "income," "realized," or
> "total" without specifying the ingredients, you bake in ambiguity. So we
> define a fixed set of **atomic computations** that every higher-level metric
> sums, subtracts, or filters. *Pages never invent new math.* They pick atoms,
> apply a window, and arrange the display. New page = new arrangement,
> never new arithmetic.
>
> **Stable but extendable.** These atoms cover everything we have data for
> today (equity, premium flow, option realized, open leg state, historical
> series). When we add new data sources (option MTM via PL-C, dividends, etc.)
> we extend this list — we don't change existing atoms.
>
> **Every atom is filterable along the same dimensions:**
> - `ticker` (per-position vs portfolio total)
> - `sector`
> - `call | put` (for option atoms)
> - `short | long` (for option atoms)
> - `window(start, end)` — for time-bounded atoms (defaults to all-time)
> - `live state` (`TODAY`, `IN ≤7D`, `IN >7D`, `EXPIRED`) for open-leg atoms

### Equity atoms (shares)

| # | Name | Definition | Data |
|---|---|---|---|
| **A1** | `equity_mv` | Σ (qty × current_price) over open positions | `positions.{quantity, current_price, status}` |
| **A2** | `equity_cost_basis` | Σ (qty × avg_cost) over open positions | `positions.{quantity, avg_cost, status}` |
| **A3** | `equity_realized` | Σ realized_pl over share_sells (windowable) | `share_sells.{realized_pl, trade_date}` |

> Note: `positions.realized_stock_pl` is the running accumulator of A3 over
> all-time. Use `share_sells` directly when windowing.

### Option premium flow atoms (gross cash, signed by direction)

| # | Name | Definition | Data |
|---|---|---|---|
| **A4** | `premium_collected` | Σ short-direction OPEN premium × contracts × 100 | `option_trades` where `action=open && direction=short` |
| **A5** | `premium_paid` | Σ long-direction OPEN premium × contracts × 100 | `option_trades` where `action=open && direction=long` |
| **A6** | `debit_close_short` | Σ CLOSE premium × contracts × 100 for closes of short opens (the buy-to-close cost) | `option_trades` where `action=close && direction=short` |
| **A7** | `credit_close_long` | Σ CLOSE premium × contracts × 100 for closes of long opens (sell-to-close proceeds) | `option_trades` where `action=close && direction=long` |

> These four atoms are **gross cash flows**, not P&L. They're what feed the
> Income page's stacked-vs-debit chart. Each is independently filterable by
> call/put.

### Option realized atom (settled P&L from matched pairs)

| # | Name | Definition | Data |
|---|---|---|---|
| **A8** | `option_realized` | Σ closeRealizedPL(close, open) over all matched close-pairs | `option_trades` (close → open via `closes_trade_id`) |

> The canonical `closeRealizedPL` function (below) is the implementation of
> A8 at the per-pair level. **All option realized math reduces to A8** —
> filtered by call/put × short/long × window as needed.
>
> Example slices:
> - **Short-call realized** = A8 filtered to `direction=short && option_type=call`.
> - **Long-put realized (protection sold at profit/loss)** = A8 filtered to
>   `direction=long && option_type=put`. (This is what answers the "puts
>   bought that have been sold at a profit" question.)
> - **Realized this week** = A8 with `window = trailing 7 days` on `close.trade_date`.

### Open-leg state atoms (current state, no window)

| # | Name | Definition | Data |
|---|---|---|---|
| **A9** | `open_short_premium` | Σ (still-open short opens premium × contracts × 100). "Still open" = `contracts > Σ matched close contracts`. | `option_trades` opens, less closes |
| **A10** | `open_long_premium` | Σ (still-open long opens premium × contracts × 100), same idea | `option_trades` opens, less closes |
| **A11** | `live_leg_count` | # of still-open legs, filterable by call/put × short/long × live state | same |

### Historical / time-series atom

| # | Name | Definition | Data |
|---|---|---|---|
| **A12** | `historical_portfolio_value(date)` | Σ over open tickers of (today's qty × carry-forward close at date). Carry-forward fills missing closes per ticker so no leg drops out. | `positions.quantity` + `daily_closes` |

> A12 backfills today's share count against past prices — it's a clean
> mark-to-market series for currently-held positions, not a true historical
> NAV. Documented limitation; will sharpen when `share_lots` (PL-B) lands.

---

## Higher-level metrics in atom terms

Every metric reduces to atoms + filters. A few worked examples to anchor the pattern (we'll do all 15 once you sign off on the atoms):

| Metric | In atom terms |
|---|---|
| **Total Portfolio Value** | `A1` *only* (equity, no options). Live mark of what we own. |
| **Unrealized P&L** | `A1 − A2` (or equivalently `A3` applied to *current holdings*, which is the same thing). |
| **Realized P&L (total, window)** | `A3 + A8` — share-side realized **plus** option-side realized, in the window. |
| **Total P&L (point-in-time)** | `(A1 − A2) + (A3 + A8)` — unrealized + realized. |
| **Income (period)** — *the "fully inclusive" definition* | `A4 + A3 + max(0, A8 filtered to long-puts)` — calls + puts collected, share gains realized, **plus** long-puts that were sold back at a profit. **This answers your "why not puts bought that were sold at a profit" point — it's just A8 with a long-put filter.** |
| **Net Premium Kept (period)** — *the "options-only" income view* | `A4 − A6` — premium collected minus buy-to-close debits. |
| **Put Protection Cost (open)** | `A10` filtered to `option_type=put`. |
| **Put Protection Coverage** | `(A8 filtered to short-calls, closed) / (A10 filtered to puts) × 100`. |
| **Weekly Portfolio Delta** | `A12(today) − A12(today − 5 trading days)`. |

> **Reading this table is the answer to "where did this number come from."**
> Every label on every screen should map to exactly one row. If you can't
> express a metric as atoms + filters, the metric isn't well-defined yet.

---

## **Canonical Income** (locked) — `A4 − A6`

> **Income = premium collected on short opens − debits paid to close shorts**,
> over a window.

The rent analogy: Income is what an asset *generates* without you selling it.
- **A4** = rent received this period (premium for short calls + short puts written)
- **A6** = expense this period (cost of buying back / closing those shorts)
- **Income = A4 − A6** = net "rent."

**Cash-flow basis.** Premium on still-open positions counts as income immediately
(you got the cash); the moment you buy-to-close any portion, A6 ticks up and the
window's Income falls accordingly. This is the correct behavior for a "money
made from the asset" metric.

### What Income explicitly excludes (and why)

| Atom | Why not Income |
|---|---|
| **A3** — share gains realized | Selling shares is liquidating the asset, not rent. Belongs to "Realized Capital Gains," not Income. |
| **A5** — premium paid on long opens (protection) | An expense, yes, but it's a separately-tracked expense (see Put Protection). Excluding keeps Income = "money I made writing options." See alt definition below if we want to net protection in. |
| **A7** — credit from selling longs | Recovery of A5, not new income. |
| **A8 filtered to long-puts** | Capital appreciation on a *bought* option — a P&L event, not rent. Belongs in Realized (long-put). |
| Mark-to-market on open positions | Unrealized; not income until realized via A6. |

### Alternative definitions (named explicitly when used)

If a surface ever needs a different definition, it must be named — never called just "Income."

| Name | Atoms | When you'd use it |
|---|---|---|
| **Gross premium collected** | `A4` | "How much cash did writing options generate, before any buybacks." |
| **Income (net of protection)** | `A4 − A6 − A5` | If we ever want a single "net cash from options" number that includes protection cost. |
| **Total realized cash flow** | `A4 − A6 + A3` | Income + share-side capital gains, all-realized. A "what hit the account" number. |

---



### `closeRealizedPL(close, open)`
P&L recognized on a single option close. `src/positions/types.ts`.
```
perShare = open.direction === 'short'
  ? open.premium − close.premium      // collected at open, paid at close
  : close.premium − open.premium      // paid at open, collected at close
return perShare × close.contracts × 100
```
Sign: `+` = realized gain, `−` = realized loss. **This is the canonical close P&L. Nothing else.**

---

## Portfolio-level metrics

### 1. Total Portfolio Value
- **Atom expression.** `A1`.
- **Definition.** `Σ (qty × current_price)` over OPEN positions. Closed rows (status='closed' or qty=0) contribute $0.
- **Inputs.** `positions.{quantity, current_price, status}`.
- **Window.** `now`.
- **Sign.** `+`.
- **Canonical hook (proposed).** `useTotalPortfolioValue()`.
- **Where it's computed today.**
  - `src/positions/types.ts::computePortfolio` — official, used by Positions page (`portfolio.total_market_value`).
  - `src/sunnyfi/dashboard/blocks.tsx::PortfolioBlock` — recomputes: `Σ (current_price ?? avg_cost) × quantity`. **DRIFT:** dashboard falls back to `avg_cost` when no live price; Positions page does not.
- **Notes.** Fallback behavior should be standardized.

### 2. Total Cost Basis
- **Atom expression.** `A2`.
- **Definition.** `Σ (qty × avg_cost)` over OPEN positions.
- **Inputs.** `positions.{quantity, avg_cost, status}`.
- **Window.** `now`.
- **Sign.** `+`.
- **Canonical hook (proposed).** `useTotalCostBasis()`.
- **Where it's computed today.** `types.ts::computePortfolio` only. ✓
- **Notes.** Cost basis does not include options. Reconsider when we add `share_lots` (PL-B).

### 3. **Unrealized P&L** (a.k.a. "open mark-to-market")
- **Atom expression.** `A1 − A2`. (Equivalent to `A3` applied to *current* holdings, ignoring sells.)
- **Definition.** `Σ ((current_price − avg_cost) × qty)` over OPEN positions. **Equity only — option MTM is not included** (we don't fetch live option mids).
- **Inputs.** `positions.{quantity, avg_cost, current_price, status}`.
- **Window.** `now`.
- **Sign.** `±`.
- **Canonical hook (proposed).** `useUnrealizedPL()`.
- **Where it's computed today.**
  - `types.ts::computePortfolio` returns it as `total_pnl` and `total_pnl_pct`. **NAMING BUG.** It's called `total_pnl` but is actually *unrealized only*. PositionsHero reads it into a variable also named `unrealized` (so the screen is correct, but the API field name is misleading).
  - `PositionsHero` (PositionsV2Body): `unrealized = portfolio.total_pnl` — relies on the misnamed field.
- **Notes / rename.** Rename `portfolio.total_pnl` → `portfolio.unrealized_pl` (and `_pct`). Will cascade through ~5 call sites. **Single biggest source of confusion.**

### 4. **Realized P&L**
- **Atom expression.** `A3 + A8` (window-filterable). Share-side + option-side realized.
- **Definition.** `Σ closeRealizedPL(close, open)` over all matched option close-pairs **+** `Σ positions.realized_stock_pl` over all positions.
- **Inputs.** `option_trades` (paired opens+closes) + `positions.realized_stock_pl`.
- **Window.** Currently **all-time**. Will need a windowed variant for Income.
- **Sign.** `±`.
- **Canonical hook (proposed).** `useRealizedPL(window?)`.
- **Where it's computed today.**
  - `realizedPLByTicker(trades)` in `types.ts` — option-only, per ticker.
  - `PositionsHero`: `Σ (r.realized_pl ?? 0) + (r.realized_stock_pl ?? 0)` over portfolio rows. **Notes:** `r.realized_pl` is the per-row option realized from `computePortfolio` (which reads `realizedPLByTicker`). So PositionsHero adds option + stock realized, which is right. ✓
  - `PositionInsightModal`: `realizedByTicker.get(t) + pos.realized_stock_pl` — same definition. ✓
- **Notes.** Consistent today *if* you remember that "realized" means option-pairs + stock-sells. The naming is also overloaded: some surfaces show "Realized" meaning option-only, others mean option + stock. **Must standardize the label.**

### 5. **Total P&L** (the headline "+$39,200" on Positions hero)
- **Atom expression.** `(A1 − A2) + (A3 + A8)` — unrealized + realized.
- **Definition.** `Unrealized P&L + Realized P&L` (#3 + #4).
- **Inputs.** Same as #3 + #4.
- **Window.** `now` for unrealized, `all-time` for realized.
- **Sign.** `±`.
- **Canonical hook (proposed).** `useTotalPL()`.
- **Where it's computed today.** Only in PositionsHero (`totalGain = unrealized + realized`). ✓
- **Notes.** The Dashboard "This week" pill (#7) is something **different** — not Total P&L over a window. Don't confuse them.

### 6. Per-position Market Value / Unrealized / Cost Basis / % Portfolio
- **Atom expression.** Same atoms (`A1`, `A2`, `A1 − A2`), filtered to `ticker = T`.
- **Definition.** Same shape as #1/#2/#3 but per ticker. Computed in `types.ts::computeRow`.
- **Where it's computed today.** Single site. ✓
- **Notes.** This is the canonical per-position object (`PositionComputed`). Page-level metrics SHOULD reduce these rather than redoing the math.

### 7. **Weekly Portfolio Delta** (Dashboard "This week +$251,426 +10.35% · 1 week")
- **Atom expression.** `A12(today) − A12(today − 5 trading sessions)`.
- **Definition.** `series[last] − series[base]`, where `series` is the historical portfolio value reconstructed via carry-forward over the last `SPARK_TRADING_DAYS`. `base` = `max(0, last − 5)` so we always show *something* even if history is short.
- **Inputs.** `positions.{ticker, quantity}` + `daily_closes.{ticker, date, close_price}`. Uses **today's shares × historical closes** — does NOT account for shares bought/sold mid-week.
- **Window.** Trailing 5 trading days (or as much as exists).
- **Sign.** `±`.
- **Canonical hook (proposed).** `usePortfolioValueSeries()` → consumers derive the delta.
- **Where it's computed today.** `blocks.tsx::valueSeries` + the two `PortfolioBlock` variants compute the delta inline. ✓ after the carry-forward fix.
- **Notes / known limitation.** Backfills today's qty against last week's prices; if you bought shares this week the base value is overstated. Acceptable for v1, flag for v2 (needs holdings-as-of-date — depends on `share_lots` in PL-B).

---

## Income / premium flow

### 8. **Net Premium Collected (current week)** — Dashboard `IncomeMix`
- **Atom expression.** `A4 − A6` filtered to trailing 7 days; the dashboard pill splits this further by `option_type` (call vs put).
- **Definition.** Per `option_type`: `Σ short opens premium − Σ short closes premium` over the trailing 7 days, then `max(0, …)`.
- **Inputs.** `option_trades` rows in the trailing 7 days.
- **Window.** Trailing 7 calendar days.
- **Sign.** `+` (clamped to 0).
- **Canonical hook (proposed).** `usePremiumIncome("week")` returning `{calls, puts, shares}`.
- **Where it's computed today.** `blocks.tsx::IncomeMix` AND independently in `incomeChart.tsx::callIncomeByBucket`. **DRIFT.**
- **Notes.** IncomeMix **nets** opens minus closes into a single "calls" number; IncomeScreen **splits** them (opens → `calls`, short closes → `debit`). Same underlying data, two presentations. The hook should return the *raw* `{calls, puts, debit, shares}` and let each surface choose how to roll up.

### 9. **Bought-back debit** — IncomeScreen
- **Atom expression.** `A6` (window-filterable, optionally split by call/put).
- **Definition.** `Σ short closes premium` (buy-to-close cost), bucketed by `trade_date`. Calls + puts combined.
- **Inputs.** `option_trades` rows where `action="close" && direction="short"`.
- **Window.** Period bucket (day/week/month/quarter/year).
- **Sign.** `+` (a cost, shown as `−$X` for display).
- **Where it's computed today.** `incomeChart.tsx::callIncomeByBucket`. ✓ (single site)
- **Notes.** Distinct from #4 *option realized*: this is the gross debit, not net P&L. They should never be confused.

### 10. **Net Premium Kept (income)** — IncomeScreen header
- **Atom expression.** **`A4 − A6`** — **THE canonical Income definition** (locked above).
- **Definition.** `collected − bought-back` for the current period bucket.
- **Where it's computed today.** Inline in IncomeScreen.
- **Notes.** This is `(short opens premium) − (short closes premium)` over the period. **Should equal** Realized Option P&L for closed pairs whose close date is in the window — but it currently isn't reconciled. Worth a sanity check.

### 11. **Shares income** — IncomeScreen "Shares" lane
- **Atom expression.** `A3` (window-filterable). Note: this is shown in the Income chart *as context*, but per the canonical Income definition above it is **not** part of Income — it's capital gains.
- **Definition.** `Σ share_sells.realized_pl` bucketed by `trade_date`, clamped to ≥ 0 per bucket.
- **Inputs.** `share_sells.{realized_pl, trade_date}`.
- **Window.** Period bucket.
- **Sign.** `+`.
- **Notes.** Dividends not tracked. Clamp at 0 hides loss buckets in the income lane (they don't go below the axis). Documented as a known limitation.

### 12. **Projected next-period income** — IncomeScreen
- **Atom expression.** Not a new atom — `weightedTrend()` extrapolates the series of `A4`, `A6`, `A3` over recent buckets and projects forward.
- **Definition.** `weightedTrend([calls, puts, shares, debit], steps)` — weighted-recent-trend extrapolation with damping, per series.
- **Where it's computed today.** `incomeChart.tsx::weightedTrend`. ✓
- **Notes.** Not "predictive" in any statistical sense — it's a smoothed extrapolation. UI labels it clearly.

---

## Put protection / strategy

### 13. **Open Put Cost** (ProtectionBlock "$X puts")
- **Atom expression.** `A10` filtered to `option_type = put`.
- **Definition.** `Σ (still-open contracts × 100 × premium)` for **long puts** where some contracts remain un-closed.
- **Inputs.** `option_trades` (opens with `direction="long" && option_type="put"`, less matched closes).
- **Where it's computed today.** Inline in `ProtectionBlock` (PositionsV2Body).
- **Notes.** "Still-open" means `contracts − Σ closed_contracts > 0`. Closed protective puts don't contribute — they're realized already.

### 14. **Call Income (realized, closed-pairs only)** — ProtectionBlock
- **Atom expression.** `A8` filtered to `direction = short && option_type = call`.
- **Definition.** `Σ closeRealizedPL(close, open)` over **closed short-call** pairs (any time).
- **Where it's computed today.** Inline in `ProtectionBlock`.
- **Notes.** Specifically *closed* call P&L. Open calls don't count toward "income that paid for puts" until they're realized.

### 15. **Net (Put Protection) Cost**
- **Atom expression.** Net cost = `A10(puts) − A8(short calls)`. Coverage % = `A8(short calls) / A10(puts) × 100`, capped at 100.
- **Definition.** `Open Put Cost − Call Income` (#13 − #14). Positive = net out-of-pocket, negative = call income covered all puts + more.
- **Coverage %.** `min(100, Call Income / Open Put Cost × 100)`.

---

## Sample drift the audit found

| What you see | Surface | Actual definition | Was confused with |
|---|---|---|---|
| **+$39,200** "Total P&L · Realized + Unrealized" | Positions hero | Unrealized (MV − cost) + Realized (opt-pairs + stock sells), all-time | The dashboard "+$251,426 / +10.35% / 1 week" delta — different concept |
| **+$251,426 +10.35% · 1 week** | Dashboard portfolio | Carry-forward value series delta over last ~5 sessions | The Positions hero's Realized number |
| **`portfolio.total_pnl`** in code | All over | Unrealized P&L only | "Total" implies realized + unrealized — **field name is a bug** |
| **"Calls sold $20,876"** | Dashboard IncomeMix this-week | Σ short call OPENS − Σ short call CLOSES, last 7d | IncomeScreen's "Collected $20,947" which is opens-only (no netting) |

---

## Proposed renames (immediate, no logic change)

| Today | Rename to | Why |
|---|---|---|
| `portfolio.total_pnl` | `portfolio.unrealized_pl` | It IS unrealized only |
| `portfolio.total_pnl_pct` | `portfolio.unrealized_pl_pct` | Same |
| "Total P&L · Realized + Unrealized" (UI label) | Keep, but only when actually summing both | Today this label sometimes shows just unrealized in older surfaces |
| "Realized" (UI label) | Disambiguate: "Realized (options)" vs "Realized (options + shares)" wherever both could appear | Spec which is shown |

---

## Proposed canonical hook layer

Living in `src/positions/metrics/` (new dir), each metric exported as one hook that wraps a TanStack Query. Pages import and read.

```
src/positions/metrics/
  index.ts                         // re-exports + types
  useTotalPortfolioValue.ts
  useTotalCostBasis.ts
  useUnrealizedPL.ts
  useRealizedPL.ts                 // (window?)
  useTotalPL.ts                    // = unrealized + realized
  usePortfolioValueSeries.ts       // returns the carry-forward series
  usePremiumIncome.ts              // returns { calls, puts, shares, debit } per period bucket
  useNetPremiumKept.ts             // wraps usePremiumIncome with the formula
  useOpenPutCost.ts
  useCallIncomeRealized.ts
  usePutProtection.ts              // returns { putCost, callIncome, netCost, coveredPct }
```

Migration strategy: **one metric at a time.** Pick #3 (Unrealized P&L, the `portfolio.total_pnl` misnomer) as the first cut — it'll touch ~5 files but the value is huge.

---

## Open questions for review

1. **Stock realized:** does "Realized P&L" always mean option-pairs + stock sells, or do we want separate metrics ("Realized Options" / "Realized Stock") with the sum being a derived "Realized Total"? *Recommendation: separate, with explicit sum.*
2. **Window semantics for Realized:** all-time is the current default. For the Portfolio (new) and Positions pages — do we want a window picker (12W/26W/52W/104W/All) on the Realized display? *Recommendation: yes, controlled by a single state.*
3. **Option mark-to-market in Unrealized.** Today, Unrealized = equity MTM only. When PL-C lands (Massive options snapshot), do we add option MTM into Unrealized? *Recommendation: yes, but ship as a separate metric `useOptionMTM()` and label clearly. Then Total P&L = equity MTM + option MTM + Realized.*
4. **Dividends.** Not tracked. Plan? *No urgency until #PL-B lands.*

---

## Where this lives next

- This doc → `docs/METRICS.md` (here).
- New hooks → `src/positions/metrics/*` (don't exist yet).
- Removed/inlined math → from `PortfolioBlock`, `PositionsHero`, `ProtectionBlock`, `IncomeMix`, `IncomeScreen`, `PositionInsightModal`.

Iterate this doc until we agree the definitions are right. **Then** we extract.
