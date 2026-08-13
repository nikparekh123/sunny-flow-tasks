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
