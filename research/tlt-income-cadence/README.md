# TLT income cadence — weekly or every expiry?

Run 2026-08-22, for the proposed INCOME phase (hold the block, sell an ATM call
and an ATM put per 100 shares, until year end).

Real TLT closes and real Polygon option bars via `stock-history` / `opt-history`.
Window 2024-09-09 to 2026-08-21, the stretch where all three weekday expiries
exist. TLT fell 99.99 to 82.05 across it.

Every arm is **rolled on expiry**, so all four are continuously written and the
only thing that differs is tenor. Strike is the listed strike nearest spot on the
write date; the premium always comes from the real option bar. Settlement is the
straddle's intrinsic at expiry, `|S_exp - K|`, which is the true economic cost
whichever leg is assigned.

## The finding: cadence does not create edge

| arm | rolls/yr | gross/yr | settle/yr | NET/yr | 95% CI | spread bill |
|---|---|---|---|---|---|---|
| EVERY_EXP 2d | 149 | $10,704 | $10,209 | $495 | -$407 to $1,327 | 60% of net |
| WEEKLY 7d | 52 | $6,280 | $5,975 | $305 | -$605 to $1,228 | 34% of net |
| BIWEEKLY 14d | 27 | $4,684 | $3,979 | $705 | -$231 to $1,584 | 8% of net |
| MONTHLY 28d | 13 | $3,342 | $3,153 | $190 | -$815 to $1,116 | 14% of net |

Per 100 shares. Spread bill assumes $0.01 a leg, so 2 cents a straddle.

**Net is about 5% of gross at every cadence.** The market charges almost exactly
what TLT goes on to deliver. Writing three times a week collects 70% more premium
than weekly and hands back 70% more at settlement.

**Every confidence interval crosses zero, and they all overlap.** No cadence is
distinguishable from another, or from doing nothing. This is the same fact the
live scanner reports as `edge -0.6`: TLT's implied vol (11) sits just under its
realised (12). There is no cadence that rescues a ticker with no vol edge.

The one difference that is NOT noise is the transaction bill. Costs are certain
where the premium edge is not, so writing every expiry multiplies a sure cost
against an unsure gain.

## Regime matters more than cadence

| | TREND -12% | RANGE flat | RECENT 2026 |
|---|---|---|---|
| EVERY_EXP | **+$633** | +$875 | +$329 |
| WEEKLY | -$260 | +$509 | +$843 |
| BIWEEKLY | -$888 | **+$1,163** | +$852 |
| MONTHLY | -$878 | +$145 | -$565 |

In the only sustained decline in the window, short tenor was the **only** arm that
made money: it re-strikes ATM every two days and follows price down. Longer tenors
were written once and run over. In chop the ranking inverts.

The ranking flips with regime, which is another way of saying there is no durable
cadence edge to find.

## Two structural facts found on the way

**Calls already share the put expiry.** `tlt-planner/index.ts:890` takes the same
`expiry` the put leg picked. Nothing to change.

**Long tenors are Friday-only.** TLT lists its Mon/Wed weeklies about a week or two
out, so a 30-day Mon/Wed contract does not exist to be written. "Every available
expiry" is inherently a short-tenor policy. The first run scored MONTHLY on 9 of 24
rolls before this was understood.

## Recommendation

**Weekly, not every expiry.** It keeps enough frequency to re-strike as TLT moves,
which is what carried the short arm through the decline, at a third of the
transaction bill. Biweekly has the best point estimate but lost the most in the
trending leg, which is the regime the INCOME phase is being proposed for.

`fetch_hist.py` closes, `probe_expiries.py` the real expiry calendar (319 dates),
`build_plan.py` roll schedules, `fetch_marks.py` real bars, `sim2.py` sub-periods,
`sim3.py` bootstrap.
