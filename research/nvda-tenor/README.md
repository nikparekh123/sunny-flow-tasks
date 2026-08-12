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
