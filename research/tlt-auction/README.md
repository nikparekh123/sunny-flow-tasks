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
