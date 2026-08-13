# Does a weak 30-year auction predict TLT?

Tested before being allowed to move size, on the same bar the NVDA conviction
families were held to: a tercile spread must beat 2x its own standard error.

Data: Treasury `auctions_query` (already called by tlt-planner for its issuance
figure), 91 30-Year auctions with published results, Feb 2001 - May 2026. TLT
closes from `stock-history`, 2003-09 onward.

## Bid-to-cover — weak (1.82-2.25) vs strong (2.41-2.77), n=30 each

| horizon | weak | strong | spread | se |
|---|---|---|---|---|
| 1d | +0.09% | +0.43% | -0.35% | 0.23% |
| 5d | +0.57% | +1.17% | -0.61% | 0.56% |
| **21d** | -0.04% | +1.46% | **-1.50%** | 1.04% |

## Indirect bidder % — no signal

Sign flips between 5d (+0.45%) and 21d (-0.76%). Noise.

## Verdict: display, do not weight

The 21d spread is **1.44x its standard error** — short of 2x. But the sign is
consistent across all three horizons and points the right way: weak demand,
weaker TLT. That is better than any of the six NVDA conviction candidates, where
the largest spread was 1.95 sigma and pointed BACKWARDS.

So it is shown and trailed, not weighted. 91 observations over 25 years is ~30 a
tercile against a 3.86% 21-day standard deviation; that is thin, and the honest
reading is "plausible, unproven".

**Timing.** Results publish about a day after the auction, so this can never
inform the day itself. It is a different signal from the calendar damper, which
fires BEFORE an event on the theory that unknowns deserve smaller size. Merging
them into one number would confuse two distinct claims.

Baseline: TLT 21d after any 30-year auction, +0.50% (sd 3.86, n=91).


## Should TLT hard-stop the roll that spans a heavy event? (`tlt_brake.py`)

TLT already damped events, but only through conviction: a -12 penalty on a score
feeding a 0.7-1.3 ramp, so the brake topped out near 0.9x. 1,079 windows x 72 weeks.
Auction dates are REAL, from Treasury's API (213 long-end auctions 2017-2026). FOMC
dates are hand-entered from the published schedule and are the weaker evidence.

| arm | shares | net | worst DD | net given up | DD saved | ratio |
|---|---|---|---|---|---|---|
| no brake (~0.9x) | 32,600 | -$1,875 | -$321,424 | — | — | — |
| **auctions: hard stop** | 30,400 | -$6,026 | -$262,578 | $4,151 | $58,846 | **14.2 : 1** |
| auctions: 0.25x | 30,700 | -$6,183 | -$275,808 | $4,308 | $45,616 | 10.6 : 1 |
| FOMC: hard stop | 31,200 | -$5,908 | -$304,995 | $4,033 | $16,429 | 4.1 : 1 |
| both: hard stop | 30,000 | -$7,709 | -$244,531 | $5,834 | $76,893 | 13.2 : 1 |

**Auctions are worth three times FOMC**, and the reason is mechanical: an auction is
a SUPPLY event landing exactly where TLT lives, while FOMC moves the front end
hardest and TLT sits at the other end of the curve.

**14.2:1 is the best ratio anything has produced on either ticker** — against ~2:1
for NVDA's earnings brake and 5.2:1 for its extended band.

Every arm's net is NEGATIVE: TLT fell hard through 2020-23, so "net given up" means
"loss deepened", not "profit forgone". The braking logic holds; the sign does not
make it a winner.

Shipped as Bonds only (20y and 30y). FOMC left to the existing soft damper, which is
about what it is worth.


## The dial: price bands, yield bands, or yield vs its own mean? (`tlt_bands.py`)

TLT's dial read an ABSOLUTE PRICE. 1,029 windows x 72 weeks, 2004-2025:

| bands | 0.25x | 0.75x | 1.25x | 1.75x | 2.50x |
|---|---|---|---|---|---|
| price 75/80/85 | **1074** | 27 | — | — | — |
| yield absolute 5.00-5.75 | 1058 | 37 | 6 | — | — |
| **yield vs its own 250d mean** | 308 | 240 | 267 | 181 | 105 |

**The dial sat at its slowest setting 98% of the time.** It was not a dial, it was a
constant, and TLT reached 32,500 shares of a 100,000 target. Absolute YIELD bands
failed the same way — levels drift over decades exactly as prices do.

Normalised per share, since the arms end up different sizes:

| | shares | net/share | drawdown/share |
|---|---|---|---|
| price bands | 32,500 | -$0.52 | -$10.12 |
| **yield vs 250d mean** | **98,000** | **+$0.98** | **-$7.43** |

Better on both, and it actually reaches the target.

**Why 25bp rungs.** TLT moves -0.16% per bp of the 30-year (R2 0.95, stable 2003-2026),
so 25bp is about 4% of TLT, or $3.30 at 82 — an equal-sized rung with a mechanism
behind it rather than a round number.

**Caveat, stated plainly:** this test is harsh on the price bands. TLT traded 85-180
for most of 2004-2020, so "above 85" swallowed that era. Those lines were calibrated
for today's TLT and are meaningless at any other level — which is the staleness
argument demonstrated, not a claim that they are wrong right now.

## Is it worth slowing down for an expected rate move? (`tlt_foresight.py`)

Perfect foresight of the 30-year four months out, braking when it is about to rise:

| your call | shares | basis | net | vs no view |
|---|---|---|---|---|
| no view | 98,000 | $111.75 | $96,403 | — |
| right | 83,300 | **$108.38** | $226,758 | **+$130,354** |
| wrong | 84,000 | $112.73 | $11,461 | **-$84,942** |
| no information (alternate weeks) | 57,500 | $110.73 | $85,704 | -$10,699 |

**Break-even hit rate 39%**, payoff asymmetric at about 1.5:1. Two things make 39%
harder than it sounds: the 30y rose 25bp+ over the next four months on 28% of Fridays
unconditionally, so the bar is well above the base rate; and the coin-flip arm lost
only $10,699, which says braking at random is nearly free — all the value AND all the
risk sit in whether the calls carry information.

Also measured, and the reason a rate FORECAST cannot be automated: effective fed funds
moves the 30-year +0.01bp per bp, R2 0.01 over 7,856 observations. Announced policy is
already in the long end. A view only pays where it DISAGREES with what is priced.
