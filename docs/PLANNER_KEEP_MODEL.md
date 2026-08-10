# The keep model

Calibrated against Nik's own scenario answers, 2026-08-09. Replaces the thirteen-factor
week score. **Not yet built** — this is the spec the build follows.
Reference implementation: `docs/planner_keep_model.py`.

## What it outputs

**delta kept %** — the share of your upside that stays uncapped after the trade.
**distance** — how far out to sell, in % OTM.

Contract count is arithmetic, not a third dial:

```
delta to sell = (1 - keep) x shares
contracts     = delta to sell / (delta x 100),  capped at shares/100
```

**There is no 0-100 score.** The headline is "keep 71%, sell 50 at 225". A separate
abstract number is what let the old score drift range-bound without anyone noticing.

## Why the old score was replaced

It blended two opposite questions — *am I paid to sell premium* and *how much upside do
I want* — which have opposite signs on the same facts. The halves cancelled and the
number never moved: NVDA at 190, 224 and 275 after a print returned 48 / 49 / 42, all
SELL NORMAL, all 25-30 delta. Three faults, all found by scenario-testing rather than by
reading code:

- **Size and distance were one dial.** The stance set `sizePct` and the delta band
  together, so "sell lighter" silently meant "sell further out".
- **It could not tell a dip from a break.** `stretch` read "washed out, do not cap"
  without asking why.
- **Its three picks were incomparable.** All sold the same contract count at different
  strikes, so they left 68% / 78% / 87% of delta — three different positions presented as
  three versions of one.

## The finding that shaped this

Nik's three pre-earnings answers were 32%, 50% and 20% **of shares**. Converted through
his own distance answers they all land on **~77% of delta**. He varied share count and
strike in opposite directions and they cancelled: down 15% → fewer shares held but sold
close at 34D; flat → half held but sold at the money, 44D; up 20% → least held but sold
furthest, 29D.

Three routes, one destination. The share number was the route. **Delta is what he was
actually targeting**, so delta is what the model controls.

## Baseline

One number per event state. Price state does not appear here.

| event | delta kept |
|-------|-----------|
| `PRE` — print inside 7 days | **77%** |
| `CLEAR` — neither | **68%** |
| `POST` — within 5 sessions after | **59%** |

The event is the whole dial. Before a print you hold ~77% of your upside; after one, ~59%.
The print is the only thing that earns retained delta, and once spent you write against
most of it.

### distance, % out of the money

Price state lives here, which is where it was doing its real work all along.

|        | down | flat | up  |
|--------|------|------|-----|
| PRE    | 1.5  | 0.0  | 2.5 |
| CLEAR  | 1.5  | 1.5  | 2.0 |
| POST   | 0.5  | 1.5  | 2.0 |

Price bands are ±8% — the run over ~10 sessions into a print, or the reaction out of one.
POST reuses the band `earnings_reactions` already computes.

**Scaled by sqrt(days/4).** A fixed % OTM does not hold its delta across expiry lengths:
1.5% out is 36D on a 4-day but only 30D on a 2-day. Since NVDA expires Mon/Wed/Fri, this
matters constantly. Square-root-of-time scaling keeps the resulting delta roughly steady.

```
otm    = base x sqrt(days/4) + ivNudge x sqrt(days/4),  clamped 0-4%
strike = round(spot x (1 + otm/100) / step) x step
```

Delta is an **output**. You choose a distance and read the delta off, never the reverse.

## Modifiers

**Every modifier measures DEVIATION from what is already implied** — by the cell (grade,
relative strength, RSI) or by the recent norm (sector). Absolute readings double-count
what the baseline knows: "SMH above its 200-day" is true most weeks of a bull market, and
scored raw it added 2-4 points to every single reading.

Expected-by-cell:

| cell | RSI | grade | NVDA less SMH |
|------|-----|-------|----------------|
| down | 30  | 2     | -8             |
| flat | 50  | 5     | 0              |
| up   | 70  | 9     | +12            |

All caps are in **delta points**, which is share-points / 2.8 — 15 points of share-keep is
only about 5 points of delta-keep.

| modifier | cap | arithmetic (before the /2.8) |
|---|---|---|
| IV percentile | ±1.4 | `-4 x (ivPct - 50) / 50` |
| Earnings grade | ±3.6 | `(grade - expect[px]) x 2.5 x decay` |
| Relative strength | ±1.8 | `((nvda - smh) - expect[px]) x 0.4` |
| Sector | ±1.4 | `(smhVs200Now - smhVs200Norm) x 0.5` |
| RSI | ±1.4 | `(rsi - expect[px]) x 0.15` |
| Macro inside the expiry | +1.4 | inside → 4, next two → 2 |
| Peer print inside the expiry | +1.1 | inside → 3, next two → 1.5 |

`grade` decay: `clamp((60 - sessionsSincePrint) / 50, 0, 1)`.
Aggregate clamped **±5**; keep clamped **55-95%**.

Distance takes one modifier: `clamp((ivPct - 50)/50, -0.5, +1.0)` points, then sqrt-scaled.

### The manual earnings grade

0-10, entered the morning after each print, carried until the next. The only input no feed
provides: *was that actually a good quarter?* Scored as a deviation, so it fires **only
when it disagrees with the price** — a great quarter on a stock that ripped is not news; a
great quarter on a stock that fell is.

| | keep | contracts |
|---|---|---|
| 190 after a print graded 2 | 58% | 62 |
| 190 after a print graded 8 | 62% | 57 |

### The put floor is not a modifier

It was, and it distorted PRE-up by 3 share-points. An unprotected book is a reason to roll
the puts, not to write more calls — letting it move keep meant a stale floor argued for
selling into exactly the weeks you were least covered. **The floor is decided first, on its
own, and read before the sell decision.**

## The hard ceiling

Covered calls cannot sell unlimited delta. At 3% out, 75 contracts sell only ~2,200 delta,
so keep can never fall below ~70%. A POST target of 59% is **unreachable at far strikes**
and forces the model near the money. When the target cannot be met the model must say so
rather than return an impossible pick — `capped: true`, with the achieved keep alongside
the target.

## Calibration

| scenario | target | achieved | strike | D | contracts |
|---|---|---|---|---|---|
| PRE down 15% | 76% | 76% | 192.50 | 38 | 47 |
| PRE flat | 76% | 76% | 225.00 | 45 | 40 |
| PRE up 20% | 76% | 76% | 275.00 | 27 | 66 |
| POST 190, graded 2 | 58% | 58% | 190.00 | 51 | 62 |
| POST 224, graded 5 | 59% | 59% | 225.00 | 43 | 71 |
| POST 275, graded 9 | 61% | 62% | 277.50 | 38 | 10 (capped) |
| today (CLEAR, flat) | 71% | 71% | 225.00 | 44 | 50 |

The pre-earnings row is the point: **one delta target, three contract counts.**

POST-up is unreliable — after assignment at 275 the block is ~1,000 shares, so one contract
is 10% of it and the reading is rounding noise. Revisit against a real post-assignment book.

**Nik's answers are a baseline, not ground truth.** They were produced reasoning from price
alone, without the technicals, IV, sector and grade the tool supplies. The baseline is what
he would do knowing only the event and the price; the modifiers are the tool's contribution,
measurable later as the distance they move him from it.

## The three picks

Target, one strike closer, one further. Each must show **delta kept**, not just premium —
that was the flaw in the first version. The contract count varies across the three, because
holding it fixed is what made them incomparable.

Each pick also needs the **expected move**: at 40% IV a 2-session sigma is ±3.6%, so a
strike 2.8% out sits *inside* one sigma. Without that, "out of the money" reads as safe
when it is not.

## Still to spec

- Where the grade is entered and stored.
- Whether `capped` should widen the distance automatically or just report.
