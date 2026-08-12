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
