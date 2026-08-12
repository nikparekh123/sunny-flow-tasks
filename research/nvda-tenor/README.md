# NVDA accumulation: does expiry tenor matter?

Run 2026-08-12. Real NVDA closes and real option marks (Polygon, via
`stock-history` and `opt-history`). 2024-07 to 2026-08, NVDA 125.83 to 223.78.

Sized by **delta**, not by contract, so every arm accumulates at the same rate
(190 delta a week) and the only variable is how long each option lives.

| tenor | rolls | shares | delivery | net basis | peak cash | total |
|---|---|---|---|---|---|---|
| weekly | 104 | 18,500 | **98%** | 153.11 | $102K | **$1,312,354** |
| biweekly | 52 | 18,600 | 94% | 153.54 | $185K | $1,311,162 |
| monthly | 24 | 13,800 | **82%** | **142.18** | $360K | $1,129,477 |

**Delivery** is shares actually acquired against the delta written. It is the
finding. Delta is a RISK-NEUTRAL probability, and NVDA's real drift over this
window was far above risk-neutral, so puts finished out of the money more often
than their delta implied. Seven days barely feels that; thirty days feels it hard.
The longer the option lives, the more the stock's own drift outruns the
assumption the delta was priced under.

So the monthly gets the better basis it should get (10.92 a share cheaper) and
still loses, because it acquires 4,700 fewer shares of something that rose 78%.

**Weekly and biweekly are a tie** — 0.4 of a dollar apart on a $153 basis, $1,192
apart on $1.3M. Biweekly costs 1.8x the capital and half the decisions.

## A broken arm, corrected

The first monthly arm rolled `date + 28 days`, which lands on an arbitrary Friday:
a *weekly* expiry four weeks out. NVDA lists those only a few weeks ahead and they
barely trade. Five contracts did not exist on the day the test wanted to sell them,
and the rest first printed three to ten days late. Rebuilt on the real monthly
chain, third Friday to third Friday, listed months ahead: 22 of 24 priceable.

The conclusion survived the fix, which is the only reason it is reported here.

`nvda_tenor.py` builds the roll schedule and strikes · `nvda_sim.py` runs the arms.

## Strike distance (`nvda_strike.py`)

Same 190 delta a week, weekly, real marks.

| strike | ct/wk | shares | delivery | net basis | peak cash | total |
|---|---|---|---|---|---|---|
| ATM | 4.2 | 18,900 | **100%** | 151.84 | **$90K** | $1,359,528 |
| OTM 2% | 6.1 | 18,500 | 99% | **149.38** | $163K | **$1,376,230** |
| OTM 5% | 15.4 | 13,200 | **70%** | 125.91 | $929K | $1,291,787 |

2% is a coin-flip against ATM: +$16,702 on $1.36M, inside noise, for 80% more
capital. 5% fails on delivery for the same reason monthly did, and the rule that
covers both is **stay inside one sigma**. At 33% vol on a weekly that is 4.6%.

## Earnings (`nvda_earn.py`)

Eight prints in the window, dates validated against the tape (each shows a
distinct reaction; the pattern is late Feb, May, Aug, Nov). Reactions
−6.4 +0.5 −8.5 +3.3 −0.8 −3.2 −5.5 +0.8, averaging **−2.5%**.

Aggregate says play it by $141,980 over skipping, but that number is dominated by
direction, not by the earnings decision: it credits every assigned lot with the
stock's whole subsequent rise. Stripped to the option alone:

| | |
|---|---|
| 8 events, option P&L only | **−$808** |
| profitable | 4 of 8 |
| mean per event | −$101 |

**The option side of earnings week is a coin flip that nets to zero.** The premium
is fat because IV is elevated and you hand most of it back at assignment. So the
case for playing it is not that the premium is good. It is that skipping forfeits
8% of the year's accumulation, and accumulation is the objective.

n=8. Too small to settle anything on its own; it is consistent with the tenor and
strike findings rather than independent of them.

## What NVDA's biggest days actually were

Not earnings. The largest moves in the window are DeepSeek (−17.0%), the tariff
pause (+18.7%), and the July 2024 rotation (+12.8%). The worst earnings reaction
was −8.5%. Anything that hedges only the earnings calendar is guarding the wrong
date.

## Does the overwrite pay for the floor? (`nvda_collar2.py`)

One share path (accumulation alone, 1,500 to 20,400) held fixed across every arm.
Calls are ROLLED at expiry rather than assigned, so the block never leaves and the
cost of keeping it is exactly what a roll debits, `max(0, S_exp − K)`.

**Floor**, 10% OTM, rolled quarterly, sized to the block: paid $279,778, recovered
$16,330, **net −$263,448** over two years. At 15% OTM it recovered nothing at all.

**Overwrite**, net of roll costs, best case 0.30 delta at 50% coverage: **+$99,014**.

**No combination funds the floor.** The closest is still $164,434 short, and it gets
there by writing half the block at 4% out, which is a heavy overwrite on a position
being accumulated.

| call delta | avg OTM | rolls | net at 50% cover |
|---|---|---|---|
| 0.10 | 8.8% | 12/99 | +$32,002 |
| 0.20 | 6.2% | 16/99 | +$38,654 |
| 0.30 | 4.0% | 23/99 | +$99,014 |

Closer to the money retains more, because a far call collects too little to matter
while still being breached on the moves that count.

### Two bugs this run caught, both invalidating earlier results

**Call strike sign.** `K = S·exp((r+σ²/2)T + N⁻¹(δ)σ√T)` should be MINUS. With the
plus, a "0.10 delta call" was struck 6.7% BELOW spot, i.e. deep in the money at
about 0.90 delta. That is what called away 19,200 shares in the first collar run and
what produced $5M of premium on a $4.5M block. Both earlier collar numbers were
meaningless.

**Fallback direction.** When a strike had no print the ladder tried K−2.5 before
K+2.5. For a put that walks out of the money; for a call it walks INTO it. Calls now
walk up.

The `avg OTM` column exists because of these. A strike series that silently drifts
toward the money is invisible in the P&L and obvious the moment you print where it
actually struck.

## Do calls fight the accumulation target? (`nvda_calls_acc.py`)

`nvda_collar2` answered a different question. It held the share path FIXED and rolled
every call, so the block could never leave and the only cost was the roll debit. That
is right for "does the overwrite pay for the floor" and wrong for "should I write
calls while building a block", because the thing that would hurt — shares called away
that must then be re-bought — was defined out of existence.

Here the share path is endogenous: accumulation runs the live model (bounded chase,
MA100 dial, weekly 1% OTM puts) and calls may take shares. 38 windows of 72 weeks,
0.30 delta at 50% coverage.

| arm | median shares | called away | median basis | premium | roll debit |
|---|---|---|---|---|---|
| no calls | 14,100 | 0 | $138.13 | $91,961 | $0 |
| calls, **rolled** | 14,100 | 0 | **$134.06** | $546,483 | $425,538 |
| calls, **assigned** | **1,700** | **16,900** | $85.82 | $201,789 | $0 |

**The rule is not "calls or no calls". It is roll or die.** Rolled, the overwrite is
worth about $4/share of basis at no cost in shares — consistent with collar2's
+$99,014. Allowed to assign, it destroys the programme: 16,900 shares called away and
1,700 held against a 15,000 target. Weekly 0.30 delta calls on half a growing block,
in a stock that trends up, are in the money constantly; shares leave as fast as the
puts deliver them and the accumulation simply churns.

The cheap-looking $85.82 basis in that row is an artefact of the same thing — it is
the average of the few shares that survived, not a good outcome.

### Coverage is the dial, and the roll debit is what it costs

| coverage | shares | basis | premium | roll debit | net premium |
|---|---|---|---|---|---|
| none | 14,100 | $138.13 | $91,961 | $0 | $91,961 |
| 25% | 14,100 | $135.46 | $315,990 | $210,130 | $105,860 |
| 50% | 14,100 | $134.06 | $546,483 | $425,538 | $120,944 |
| 100% | 14,100 | $133.67 | $1,007,486 | $853,042 | $154,444 |

Basis improvement flattens hard after 25% while the gross cash through the roll grows
without limit. Going from 25% to 100% coverage buys **$1.79/share** and requires
**$643K more** of roll debits to be funded on demand, in the weeks NVDA has just
rallied. The premium column is not income — most of it is handed back at the roll.

## ATM but fewer, against further but more (`nvda_calls_atm.py`)

Nik's structure: on 5,000 shares sell 15-20 ATM calls, leaving 3,000 uncapped for a
wild run. Higher premium per contract, so fewer contracts. 38 windows x 72 weeks,
share path endogenous, calls rolled.

| structure | basis | net premium | roll debit | ITM rate | block capped |
|---|---|---|---|---|---|
| no calls | $138.13 | $91,961 | $0 | — | 0% |
| ATM @ 20% | $135.15 | $104,836 | $346,658 | 49% | 19% |
| ATM @ 30% | $134.29 | $113,854 | $519,585 | 49% | 29% |
| ATM @ 40% | $133.88 | $119,159 | $699,038 | 49% | 39% |
| 0.30d (4% out) @ 25% | $135.46 | $105,860 | **$210,130** | 24% | 24% |
| 0.30d (4% out) @ 50% | **$134.06** | $120,944 | $425,538 | 24% | 50% |

**The premise is right and the conclusion does not follow.** ATM collects far more
gross — $451K at 20% cover against $316K for 4%-out at 25%. Net of the roll it loses:
ATM @ 30% is DOMINATED by 4%-out @ 50%, which reaches a better basis ($134.06 vs
$134.29) for $94K less cash through the roll.

The ITM rate is why. An ATM call finishes in the money **49%** of the time against
**24%** at 4% out. Each roll debit is exactly the upside handed back, so the bigger
premium and the bigger debit are one fact seen twice.

**Why the intuition misfires here.** "Leave shares uncapped for a wild run" is correct
if calls are ASSIGNED — uncapped shares are then the only ones kept. Under roll-always
a capped share is never lost, only paid for, so the count of uncapped shares stops
mattering and total roll debit becomes the cost. The structure optimises the variable
the rolling discipline neutralises. It also ignores headroom: an ATM-capped share has
none, a 4%-out-capped share runs 4% free.

Basis gained per $1K of roll debt that must be funded on demand:

| | basis gained | roll debit | per $1K |
|---|---|---|---|
| 4% out @ 25% | $2.67 | $210K | **12.7c** |
| 4% out @ 50% | $4.07 | $426K | 9.6c |
| ATM @ 20% | $2.98 | $347K | 8.6c |
| ATM @ 30% | $3.84 | $520K | 7.4c |

Every ATM row is less efficient than every 4%-out row.

## Strike, filled in (1% and 3% added)

| strike | ct/wk | shares | delivery | net basis | peak cash | total |
|---|---|---|---|---|---|---|
| ATM | 4.2 | 18,900 | 100% | 151.84 | $90K | $1,359,528 |
| **OTM 1%** | **5.2** | **19,100** | **102%** | **148.95** | **$117K** | **$1,429,112** |
| OTM 2% | 6.1 | 18,500 | 99% | 149.38 | $163K | $1,376,230 |
| OTM 3% | 8.1 | 15,300 | 82% | 141.12 | $311K | $1,264,674 |
| OTM 5% | 15.4 | 13,200 | 70% | 125.91 | $929K | $1,291,787 |

**1% out is the optimum**, and it is not a coin flip against ATM the way 2% is:
+$69,583, MORE shares, a better basis, for only $27K more capital. The curve peaks
there and falls away on both sides.

Delivery over 100% is the tell. Near the money the stock's drift barely bites and
realised assignment slightly BEAT what delta priced; past two sigma-fifths it
collapses. That asymmetry is why the sweet spot sits just outside the money rather
than at it.

Weekly moves, last 12 months (49 weeks, sd 4.75%), which is what actually decides a
weekly put — not the daily distribution:

| strike | weeks assigned |
|---|---|
| ATM | 24 of 49 (49%) |
| 1% OTM | 22 of 49 (45%) |
| 2% OTM | 17 of 49 (35%) |
| 3% OTM | 10 of 49 (20%) |
| 5% OTM | 4 of 49 (8%) |

Between 1% and 2% the assignment rate falls ten points for one point of strike. That
is the edge of the cliff, and it is why 2% already costs shares.

## The reference for the speed dial (`nvda_trigger.py` builds on the same data)

Does distance BELOW a moving reference predict the next 20 sessions? If not, that
reference cannot drive a speed dial.

| reference | days below | forward 20d: deep / mid / shallow | spread |
|---|---|---|---|
| **MA 100** | 90 | +15.2% / +10.5% / +2.5% | **+12.7 pts** |
| EMA 100 | 74 | +17.4% / +9.2% / +6.6% | +10.8 |
| MA 50 | 116 | +11.7% / +6.6% / +3.3% | +8.4 |
| MA 200 | 48 | +18.4% / +14.9% / +12.5% | +5.9 |
| 52w high | 297 | +9.3% / +1.1% / +3.8% | +5.5 |

**MA 100.** Below it the next month averaged +9.4%, above it +2.6%. The 52-week high
fails because NVDA sits below it 297 days of 330, so it barely discriminates; MA 200
has the best absolute returns and almost no spread, on 48 observations.

Caveat: one regime, and a violent uptrend, so every bucket is positive. The ORDERING
is more trustworthy than the levels.

## Dip-triggered cadence

Strike held at 1% OTM and the same total delta deployed in every arm, so the only
variable is WHEN.

| cadence | entries | shares | delivery | richness | basis | peak cash | total |
|---|---|---|---|---|---|---|---|
| **every Friday** | 104 | **20,900** | **100%** | 0.1254 | 150.09 | **$126K** | **$1,540,078** |
| drop > 0.5% | 204 | 20,800 | 100% | 0.1540 | 152.32 | $281K | $1,486,187 |
| drop > 1% | 162 | 18,200 | 87% | 0.1604 | 147.05 | $335K | $1,396,373 |
| drop > 2% | 98 | 16,700 | 80% | 0.1721 | 139.53 | $369K | $1,406,852 |

**The premise is right and the conclusion is wrong.** Premium richness rises exactly
as expected, +23% / +28% / +37%, so a dip really does pay more. Every dip arm still
loses, and the deeper the trigger the worse: −$53,890, −$143,704, −$133,225.

Two reasons, and neither is the premium.

**Delivery falls.** 100% on Friday, 87% at the 1% trigger, 80% at 2%. Writing into a
drop means writing into the one condition where the stock is most likely to bounce
back above the strike, so fewer puts deliver shares. Richer premium, fewer shares.

**Capital doubles.** $126K to $281K–$369K. Dips cluster, so the arm writes several
entries in the same week and carries them all at once. The Friday cadence spreads
the same delta across the calendar by construction.

The dip is real. It is a better moment to be PAID and a worse moment to be DELIVERED,
and this book is paid in shares.

## Do any conviction signals predict? (`nvda_signals.py`)

62 weekly writes of a 1% OTM put, each scored on the option's own P&L per contract
and on whether it delivered shares. Baseline **+1.22 per contract, 34% delivery, sd
2.94**.

| signal | P&L low / mid / high | spread |
|---|---|---|
| implied level | +0.73 / +1.09 / +1.78 | +1.05 |
| 50 vs 200 day | +0.67 / +1.58 / +1.39 | +0.72 |
| variance premium, IV−HV | +1.19 / +0.99 / +1.44 | +0.25 |
| distance vs MA100 | +1.25 / +1.34 / +1.07 | −0.18 |
| realised vol | +1.61 / +0.93 / +1.13 | −0.47 |
| last week's move | +1.63 / +1.78 / +0.33 | **−1.29** |

**Nothing clears the noise.** With 20 weeks a tertile and a weekly sd of 2.94, the
standard error on a tertile mean is 0.66, so a difference needs roughly 1.9 to be
worth acting on. The largest is 1.29, and it is negative: after a strong week the put
does worse, which is mean reversion, not an edge to size on.

This kills the thesis these families were built on. **Rich premium does not predict a
better week** — the variance premium, the most defensible signal an option seller has,
scores +0.25 on a 2.94 sd. It is consistent with the dip result: a richer option is
compensation for a worse delivery, not a free lunch.

**So NVDA should not ship nine conviction families.** A ±30% trim driven by signals
that do not predict adds variance and subtracts nothing else. What ships is the part
that IS measured: weekly, 1% out, an MA100 speed dial, the ceiling, no calls, play
through earnings. Dampers and the liquidity gate stay, because they are risk
management rather than prediction and need no backtest to justify.

Conviction gets **computed and stored, but not weighted**, until the trail can test it.
That is what the TLT trail exists for and NVDA should start one on day one.

**MA100 survives** despite scoring −0.18 here, because this table asks a different
question. MA100 predicts the STOCK over the next month (+9.4% below vs +2.6% above).
It says nothing about whether this week's option pays, and the multiplier's job is to
decide how many shares to accumulate, not how well the option prices.
