# The keep model

Calibrated against Nik's own answers, 2026-08-09. Replaces the thirteen-factor week
score. **Not yet built** — this is the spec the build follows.

## Why the old score was replaced

It blended two opposite questions into one number: *am I paid to sell premium* and
*how much upside do I want to keep*. Those have opposite signs on the same facts, so
the halves cancelled and the number never moved. Run NVDA at 190, 224 and 275 after a
print and it returned 48 / 49 / 42, all SELL NORMAL, all 25-30 delta. For a name that
moves 8-15% in a week, that is a Coca-Cola score.

Two further faults, both found by scenario-testing rather than by reading code:

- **Size and distance were the same dial.** The stance set `sizePct` and the delta band
  together, so "sell lighter" silently also meant "sell further out". They are separate
  decisions.
- **It could not tell a dip from a break.** `stretch` read "washed out, do not cap"
  without asking *why* the stock was washed out, so a broken print and a healthy pullback
  scored the same.

## Two outputs, not three

**keep %** — how much of the share block stays unwritten. This is the model.
**distance** — how far out to sell, in % OTM. A narrow band, nudged by IV.

`size = 100 - keep`, capped by `capacityCt`. Nik's own answers had size as the exact
complement of keep in all six scenarios, so it is not an independent dial.

**There is no 0-100 score.** The headline number is "write 73%". A separate score would
only be `100 - keep` wearing a hat, and an abstract number is what let the old one drift
range-bound without anyone noticing.

## Baseline

Two axes. **Event state** is primary; price state is secondary.

- `PRE` — a print inside 7 days
- `POST` — within 5 sessions after a print
- `CLEAR` — neither, which is most weeks

Price state uses ±8% bands: the run over ~10 sessions into a print, or the reaction move
out of one. POST reuses the band `earnings_reactions` already computes.

### keep %, of the share block

|        | down | flat | up  |
|--------|------|------|-----|
| PRE    | 32   | 50   | 20  |
| CLEAR  | 20   | 20   | 20  |
| POST   | 18   | 5    | 5   |

The event is the dial, not the price. Before a print you hold back 20-50%; after one,
5-20%. That gap is larger than anything price does inside either half — the print is the
only thing that earns real retained upside, and once it is spent you write against almost
everything.

PRE peaks at **flat**, not at either extreme: maximum uncertainty is when optionality is
worth most. CLEAR is deliberately flat across all three — with no print in play the recent
move does not change how much you hold back, and the modifiers do all the work.

### distance, % out of the money

|        | down | flat | up  |
|--------|------|------|-----|
| PRE    | 1.5  | 0.0  | 2.5 |
| CLEAR  | 1.5  | 1.5  | 2.0 |
| POST   | 0.5  | 1.5  | 2.0 |

Everything sits between 0 and 3% OTM, roughly 35-45 delta at a week out. The old model's
*most aggressive* setting (35 delta) was still further out than this table's most
conservative one. Stated in % OTM rather than delta because delta is an **output** — it
falls out of the strike, the days and the IV. You choose a distance and read the delta
off, not the reverse.

`strike = round(spot × (1 + distance/100) / step) × step`

## Modifiers

**Every modifier measures DEVIATION from what is already implied** — by the cell (grade,
relative strength, RSI) or by the recent norm (sector). An absolute reading double-counts
what the baseline already knows. "SMH above its 200-day" is true most weeks of a bull
market: scored raw it added 2-4 points of keep to every single reading and pushed the
whole model positive.

Expected-by-cell values:

| cell | RSI | grade | NVDA less SMH |
|------|-----|-------|----------------|
| down | 30  | 2     | -8             |
| flat | 50  | 5     | 0              |
| up   | 70  | 9     | +12            |

| modifier | cap | arithmetic |
|---|---|---|
| IV percentile | ±4 | `-4 × (ivPct - 50) / 50` |
| Earnings grade | ±10 | `(grade - expect[px]) × 2.5 × decay` |
| Relative strength | ±5 | `((nvda - smh) - expect[px]) × 0.4` |
| Sector | ±4 | `(smhVs200Now - smhVs200Norm) × 0.5` |
| RSI | ±4 | `(rsi - expect[px]) × 0.15` |
| Macro inside the expiry | +4 | inside → 4, next two → 2 |
| Peer print inside the expiry | +3 | inside → 3, next two → 1.5 |

`grade` decay: `clamp((60 - sessionsSincePrint) / 50, 0, 1)`, so full weight for ten
sessions then fading to nothing by sixty.

Aggregate clamped to **±15**; final keep clamped to **5-55**.

Distance takes one modifier only: `clamp((ivPct - 50)/50, -0.5, +1.0)` percentage points,
clamped 0-4% overall. Rich IV buys the same premium further out, which holds the resulting
delta roughly steady as IV swings.

### The manual earnings grade

0-10, entered the morning after each print, carried until the next one. It is the only
input no feed provides: *was that actually a good quarter?*

Because it is scored as a deviation it fires **only when it disagrees with the price**.
A great quarter on a stock that ripped is not news. A great quarter on a stock that fell
is. Same price, opposite instruction:

| | keep |
|---|---|
| 190 after a print graded 2 | 15% |
| 190 after a print graded 8 | 25% |

### The put floor is not a modifier

It was, and it distorted PRE-up by 3 points. An unprotected book is a reason to **roll the
puts**, not a reason to write more calls — letting it move keep meant a stale floor quietly
argued for selling into exactly the weeks you were least covered. The floor is decided
first, on its own, before the sell decision.

## Calibration

| scenario | model | Nik |
|---|---|---|
| PRE down 15% | 29% | 30-35% |
| PRE flat | 47% | 50% |
| PRE up 20% | 18% | 20% |
| POST 190, graded 2 | 15% | 15-20% |
| POST 224, graded 5 | 6% | 5% |
| POST 275, graded 9 | 11% | 5% |
| today (CLEAR, flat) | 27%, write 73%, 227.50 | — |

The POST-275 residual is four small positive divergences stacking: it ripped harder than a
typical good print, RSI ran hotter, it led the sector by more. Left in place — on the ~1,000
shares surviving that assignment, 11% against 5% is one contract.

**Nik's six rows are a baseline, not ground truth.** They were produced reasoning from price
alone, without the technicals, IV, sector and grade the tool supplies. So the baseline is
what you would do knowing only the event and the price, and the modifiers are the tool's
actual contribution — measurable, later, as the distance they move you from it.

## Still to spec

- The three picks: target strike, one closer, one further. A spectrum, not a ranking.
- Contract count against `capacityCt`.
- Where the grade is entered and stored.

Working script: `scratchpad/baseline2.py` (session 47e7cc72).
