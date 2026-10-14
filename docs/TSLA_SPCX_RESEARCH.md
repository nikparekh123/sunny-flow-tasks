# TSLA and SpaceX (SPCX): LEAP plus weekly calls

Research for Nik, 14 Oct 2026. Not traded yet. When the names are added, the
Inventory write suggestions follow the rules at the bottom (already built,
`WRITE_RULES` in sunny-home).

## The question

Nik's view: SpaceX (SPCX, listed 12 Jun 2026) very bullish, TSLA mediocre,
more sideways. A long LEAP on each, a weekly call against part of it, never
100% sold (keep 50 to 60% delta), built 2 contracts at a time. Compare:

- **A:** 30% of the LEAPs at the money, the rest at 1 SD.
- **B:** 2 to 3% out of the money on 70% every week.
- other strikes (ATM, 2/3/5% out, 0.30 delta, 1 SD) and coverage 30 to 70%,
- weekly against three times a week (Mon, Wed, Fri expiries),
- LEAP at the money, about 0.75 delta, about 0.90 delta.

## Method

Real end-of-day bid and ask from Theta for every chain (Polygon's option
history now returns nothing). Sell at the close at mid less a quarter of the
spread, $0.65 a contract; settle at the expiry close at intrinsic (bought back,
never assigned). LEAPs bought and marked at real mids; TSLA's rolls into Jan 2028
at the same delta on 2 Jan 2026. Everything per 10 LEAPs.

Data: TSLA 14 Oct 2024 to 13 Oct 2026 (two +120% rips and a -54% crash);
SPCX 18 Jun to 13 Oct 2026 (four months). TSLA has had Mon/Wed expiries only
since Feb 2026, SPCX only since Oct 2026. Scripts and logs:
`research/tsla-spcx/` (not in git).

## Findings

**Weekly, not three times a week.** TSLA, Feb to Oct 2026: weekly calls made
$12K to $48K; three times a week lost money on every strike rule, though it
collected more premium. A new 2-day call resets the strike, so every up-swing
inside the week is paid for; a weekly lets the week's ups and downs cancel.

**TSLA: B beats A** everywhere except a monster rip.

| TSLA, per 10 LEAPs | A: 30% ATM + 1 SD | B: 2-3% out on 70% |
|---|---|---|
| sideways, 2026 | +$33K to +$36K | +$61K |
| crash, -54% | +$42K to +$46K | +$58K to +$65K |
| two years | +109% | +125% (LEAP alone +96%) |
| rip, +119% | gives back ~30% of it | gives back ~45% |

B keeps about 55 to 60 delta per 0.80-delta LEAP (Nik's 50 to 60%).

**SPCX: deep LEAP, fewer and further calls.** The at-the-money Jan 2028 (160,
$38) is all time value, 24% of the price: it loses everything if SPCX is flat
and only beats the deep one above about 237 (+52%) by Jan 2028. In both SPCX
windows (the IPO slide and the Aug to Oct rally) the deep LEAP did better, and
3 to 5% out (or 0.30 delta) beat at the money and the 30% ATM splits. On
TSLA's rips, 5% out and 1 SD gave back the least.

## The rules (built, dormant until held)

| | TSLA (sideways) | SPCX (very bullish) |
|---|---|---|
| LEAP | Jan 2028, about 0.80 delta (290 strike, about $131 on 13 Oct) | Jan 2028, deep: 95 to 105 strike, about $68 to $74 (0.85 to 0.88 delta) |
| calls | 3% out of the money on 70%, weekly | 5% out of the money on 50%, weekly |
| Inventory | full at 70% of the LEAPs | full at 50% of the LEAPs |

The research range was 2 to 3% for TSLA and 3 to 5% for SPCX; the rules take 3%
and 5% (the better full-period result and the bullish end). No earnings
adjustment: the research did not test one.

## Building in

Two contracts at a time is fine; match the calls as it builds: TSLA 1 call per 2
LEAPs, then 2 per 3, then 7 per 10; SPCX 1 per 2. SPCX listed on 12 Jun; IPO
lock-ups usually end about 180 days later (early December), which often weighs
on the price, a reason to buy slowly through December (check SPCX's own terms).

## Caveats

SPCX has four months of data. TSLA's two years had unusually large swings.
Weekly premiums are lower now than in the test (TSLA weekly IV about 35% on
13 Oct against a 43% average), so expect a little less income.
