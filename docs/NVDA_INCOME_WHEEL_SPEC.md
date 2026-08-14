# NVDA Income Wheel — spec

Agreed 2026-08-14. This replaces the accumulation logic for NVDA puts and calls.

---

## What changes, in one line

NVDA stops chasing a share target. It becomes an income machine that buys on
weakness and sells upside into strength, and the share count lands where it lands.

**Old:** get to 15,000 shares, write puts every Friday, size from a weekly budget.
**New:** collect premium, write puts only after two red days, size from the price.

---

## The put side

### When to write
Only when **NVDA is red today and was red at the previous close.** It fires on the
second red day of a slide and on every further red day while the slide continues.

"Red today" is measured on the live price against the last completed close, not on
today's part-formed daily bar, so it does not flip on and off during the session.

Any size of drop counts. Do not wait for a 2% or 4% fall.

> Why: tested on NVDA 2018-2026. Writing on the second red day gets you in about 2.6
> percentage points cheaper than writing every Friday, and it beat the timetable in
> 76% of 12-week windows. Demanding a bigger drop made it worse: waiting for −4%
> cut both the income and the shares by about a third, because it only fires 26 times
> a year instead of 50.
>
> Skipping the FIRST red day matters and is not intuitive. NVDA bounces harder the
> longer a slide runs: +0.36% the day after one red day, +1.38% after four, against a
> +0.23% baseline. The first day of a drop is the expensive entry.

### What strike
**AT THE MONEY.** The nearest listed strike to the current price.

So NVDA at 211.20 writes the 210 strike.

> Why: income is time value, and time value is highest at the money. It falls away in
> both directions. From the live chain with NVDA at 225.15:
>
> | strike | premium | intrinsic | real income |
> |---|---|---|---|
> | 220 | 5.10 | 0 | 5.10 |
> | **225 at the money** | 7.33 | 0 | **7.33** |
> | 227.50 | 8.60 | 2.35 | 6.25 |
> | 230 | 10.05 | 4.85 | 5.20 |
>
> The 230 put pays 10.05, which LOOKS like more money than 7.33. But 4.85 of it is
> intrinsic: you are agreeing to buy NVDA 4.85 above where it trades, and you hand
> that straight back on assignment. Real income is 5.20, which is 29% less than at
> the money.
>
> **An earlier version of this spec said 1.5% ABOVE the price. That was wrong.** The
> backtest that produced it counted the whole premium as income, intrinsic included,
> so in-the-money strikes looked richer while mostly recycling their own intrinsic.
> It also credited them for ending up owning more NVDA, in a sample where NVDA rose
> almost throughout. Neither is income. The justification given at the time, that an
> in-the-money put frees the slot faster, was also wrong: these are weekly options, so
> the slot frees every week whatever the strike.

### How many
Set by NVDA's price. This is the maximum number **open at one time**, not per trade.

| NVDA price | max puts open | owed if all assign |
|---|---|---|
| above 200 | 15 | $337,500 at today's 225 |
| 175 to 200 | 25 | $437,500 |
| 150 to 175 | 35 | $525,000 |
| below 150 | 50 | $625,000 |

> Measured against not scaling at all: the bands earn $0.82m a year against $0.72m
> flat, and the worst two-year run is slightly BETTER, at -$2.94m against -$2.99m.
> Scaling into weakness is not costing you anything on the downside here.

If 8 are already open and the band allows 12, write 4.

> Note: the bottom two bands go past the $400,000 ceiling, deliberately. In the
> historical replay NVDA was above 200 on 86% of days, so the scaling rarely fired
> and the rule performed almost identically to writing 12 flat. It is built for the
> fall that has not happened yet, not for the average day.

### What expiry
**The COMING Friday.** The next Friday on the board, however close.

> Why the shortest: income is time value per day, and short contracts decay fastest.
> Measured with at-the-money strikes over 62 two-year runs:
>
> | expiry rule | premium/yr | writes/yr |
> |---|---|---|
> | **the coming Friday** | **$0.67m** | 30 |
> | Friday >=5 days out | $0.62m | 23 |
> | Friday >=12 days out | $0.50m | 16 |
>
> **An earlier version of this spec said "at least 5 days out". That was wrong, and
> for an instructive reason.** The test behind it measured ENTRY PRICE, not income:
> short contracts get you the shares more expensively, so they lost. That was the
> right answer while accumulation was the goal. When the goal changed to income I
> carried the old conclusion over instead of re-running it. Longer is better for
> entry price. Shorter is better for income. They are different questions.
>
> A Friday write into the following Monday is the most efficient of all, at 0.543 of
> time value per calendar day against 0.507 for the week: you are paid for a weekend
> of decay while carrying only one trading day of market risk. It is only available
> on a Friday, and taking the coming Friday every time captures it automatically.

---

## The call side

### When to write
Only when **NVDA is green today and was green at the previous close.** Same shape as
the put trigger, mirrored.

> Why: tested the same way. Selling into the second green day gets you about 1.6
> percentage points higher than selling on a timetable, in 71% of windows. Selling on
> the first green day alone was a coin flip and no better than the timetable.

### What strike
Three rungs. The anchor is **whichever is HIGHER, the current price or your average
basis.** Then:

| rung | strike | share of the block |
|---|---|---|
| 1 | anchor + 0% | 17% |
| 2 | anchor + 3% | 17% |
| 3 | anchor + 6% | 16% |

Total 50% covered. The other 50% of the block is left alone.

> **The anchor rule is the important part and it was a real bug in the first design.**
> Setting calls at your basis alone means that once NVDA rises above what you paid,
> every call you write is deep in the money and gets assigned immediately. In one
> test run it was selling shares at 275 while the market was at 300. Anchoring to the
> higher of the two stops that.
>
> Why 50% and not 75%: 75% coverage earned LESS and kept fewer shares. Covering more
> of the block stops it growing, so there is less to write against next time.
>
> Why a ladder instead of one strike: it does not earn more. It earns about the same
> as selling everything at the anchor, while keeping roughly 500 more shares. It is a
> balance, not an improvement.

### How many
Each rung is topped up to its own share of the block, independently. Never write more
calls in total than the shares held. Pending put assignments do not count as cover.

### What expiry
**The next Friday at least 5 days away.** NOT the same as the puts.

> The two sides want opposite tenors, and the reason is what limits each one.
>
> | call expiry | premium/yr | shares kept |
> |---|---|---|
> | the coming Friday | $0.56m | 2,700 |
> | **Friday >=5 days out** | **$0.67m** | 3,000 |
> | Friday >=12 days out | $0.69m | 3,200 |
>
> **Puts** are capped by how many can be open at once, and that slot refreshes weekly,
> so the shortest contract means the most turns.
>
> **Calls** are capped by shares owned, not by a slot. A longer call is simply more
> premium off the same shares, and it assigns less often, so more of the block
> survives to be written against next time.
>
> 12 days is marginally better again ($0.69m, 3,200 shares) if you want it. Kept at
> 5 because Nik prefers roughly a week.

---

## What this engine does NOT do

- **No share target.** No chase, no quarter budget, no horizon projection, no
  "on plan" standing.
- **No MA100 dial.** Replaced by the absolute price bands above.
- **Never sells naked calls.** Cover comes from delivered shares only.

Open question: whether the conviction score still drives anything, or becomes
display-only. My recommendation is display-only, since the price bands now do the
sizing. Needs a decision.

---

## Worked example

NVDA closed down Monday. Tuesday it is down again, trading 211.20.

```
PUT SIDE
  two red days                        yes, write
  strike        211.20 x 1.015 = 214.4 -> snaps to 215
  band          211.20 is above 200   -> max 12 open
  already open  4                     -> write 8
  expiry        next Friday, 10 days out
  premium       about 5.50            -> $4,400 collected

If assigned you own 800 shares at 215 less 5.50 = 209.50 basis.

CALL SIDE (a later day, after two green days, holding 4,000 shares at 209.50)
  NVDA now 218, so the anchor is 218, not the 209.50 basis
  rung 1   7 contracts at 217.50   (anchor + 0%)
  rung 2   7 contracts at 222.50   (anchor + 2%)
  rung 3   6 contracts at 227.50   (anchor + 4%)
  2,000 of the 4,000 shares covered, 2,000 left alone
```

---

## What the card should show

The put card leads with the gate, the way the TLT card does:

- **"Sell 8 puts at 215"** when the gate is open and there is room
- **"One green day. Wait for a second"** style copy when the trigger has not fired
- The band it is in, and how many puts are already open
- What it would cost if all assign

The call card shows the three rungs and how much of the block is left uncovered.

---

## Honest limits of the research

Everything here is measured on NVDA between 2018 and 2026, and NVDA rose almost the
whole way. Of 62 two-year windows, only 2 actually fell.

So the settings that look best are the ones that were most aggressive into dips,
because every dip recovered. **The bearish case Nik is positioning for is exactly the
case this data cannot check.** The price bands are the main protection against that,
and they are the one part of the design that is a judgement call rather than a
measured result.

Gross premium figures from the simulation (in the $1m to $4m range) are cash
collected before any assignment losses, and are inflated by a price path that ran
from 220 into the thousands in the best windows. Treat them as relative comparisons
between settings, never as forecasts.

---

## Build notes

The existing `nvda-accumulate` shares most of what this needs: chain fetching,
position netting, card rendering. Recommend adding this as a phase or mode inside it
rather than a new function, so the card, the book writer and the marks all keep
working unchanged.
