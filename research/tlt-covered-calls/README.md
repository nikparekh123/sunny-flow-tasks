# TLT covered calls with shares (Nik's 7 Oct 2026 plan)

15,000 shares on margin (3.03%), 150 calls in three staggered weekly lines:
Mon ATM, Wed/Fri one strike up, each re-written at its own expiry a week out.

`build.py` roll plan + real option bars · `sim.py` week-by-week backtest
(real closes, opens, dividends, option bars; 9 Sep 2024 to 7 Oct 2026) ·
`forward.py` 12-month scenarios priced at the live 7 Oct chain
(`python3 forward.py fade` lets option prices drift back to realised).

## Findings

- Backtest: calls kept $135k after payouts over 2.1 years, but $110k of it came
  in the two falls (H2 2024 -12%, H2 2026 -9%). The flat 18 months kept $25k of
  $489k premium (5%), same as the Aug cadence study. Implied tracked realised
  within ~1pt in every half-year.
- Rebuying at the next open added ~$70k: TLT happened to fall overnight. Luck.
- 7 Oct 2026 the 7-day ATM is 14.7% implied vs ~10% realised (20-250 day),
  the widest gap in the window. That gap is the only source of edge.
- Forward: the plan does best flat and quiet; it gives back $75-190k if TLT
  rallies 15-30% (Nik's Fed-easing view), and cushions a 15% fall by ~$30-55k.

## Round 2 (forward2.py): fewer calls, further out, shares vs long calls

Live Oct 14 smile and Jan-2029 LEAP closes, option prices fading to realised.
- Once option prices normalise, calls add about nothing in a calm year with any
  count or strike (+$18k to +$26k total, vs +$23k with no calls). Calls only trade
  rally for cushion. Under Fed eases +15%: no calls +$196k, 50 calls $1 up +$174k,
  100 calls $1 up +$152k, plan +$105k.
- Shares beat 75C and 60C LEAPs in calm, Fed eases and QE; LEAPs lose less only
  in the -15% case (75C -$110k vs shares -$150k). LEAPs tie up $79k/$178k vs
  $769k borrowed.

## Round 3: puts only, in tranches (sim_puts.py, forward3.py)
- Backtest: puts kept ~8% of premium in the flat 18 months, lost $122k/$57k in
  the two falls. 150 at once -$132k, +10/week -$80k, vs shares -$312k.
- Forward: an ATM put ~= shares + ATM call. Calm: puts ~= shares (+$18-26k).
  Fed eases: puts +$78-88k vs shares +$201k. Inflation: puts -$72-92k vs -$154k.
  Tranches just make the position smaller for longer. Keeping assigned shares
  behaves like buying 1,000 a week.
