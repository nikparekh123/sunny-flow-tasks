# ITM put overlay, forward test (Nik, 15 Oct 2026)

Nik's idea after selling all puts: buy ~3-5 month puts ~8% in the money on ~25 per 60 LEAPs,
sell ~15 weekly puts slightly out of the money (always at or below the long strike, so
covered), keep selling calls on the LEAPs. Names: NKE, LULU, BABA, NFLX.

NOT a backtest (the names fell 20-30% in two years, history would flatter any put).
`forward.py`: 12 months from the 15 Oct close, 300 paths per scenario, daily moves from
each stock's own 3 years (big days trimmed) bent to scenario waypoints, earnings jumps,
first long put at the live quote, later ones at today's term IV moved with the path's vol,
weekly options at 20-day realised x richness (today's, fading to 1.05). `grid.py` per-name
variants, `book.py` all four summed, `decomp.py` cost breakdown.

## Findings (all four names, vs no puts, 12 months, medians)
- Plan 25/15, ~8% ITM: flat -2.6K, up 15% -15.6K, rip +25% in 3m -54.3K, bull +40% -45.2K,
  down 15% +14.1K, crash -30% +66.3K, V -20% then back +22.6K. Instant -15% loss 33.3K -> 23.9K.
- The weekly puts are a dial: sell all 25 -> ~free in flat (+2.1K) but crash +50K and no
  margin relief; sell 8 -> crash +79K, flat -6.5K; none -> crash +93K, flat -11.8K,
  instant -15% loss only 6.5K. Weekly income is not profit: only the richness edge stays.
- Strike: 15% ITM more protection, costs more in rallies; ATM the reverse. 8-10% ITM middle.
- Tenor: March (5m) = January (3m) on protection, slightly cheaper in rallies, fewer rolls;
  June (8m) similar. Covers BABA/LULU/NFLX next two reports.
- NKE is the costly one in a flat year (-$3.9K): its puts are priced well above its realised vol.
- Fewer calls (42/60) and lotto calls (Dec 2027 +35%) both cost ~$4-5K a year on NKE and only
  help in big rallies; skip.
- Flat-year put spend ~$107K (rolling, mostly intrinsic coming back), overlay cost ~$4.5K (~4%).
