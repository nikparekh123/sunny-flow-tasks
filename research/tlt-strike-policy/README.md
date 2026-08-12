# TLT strike policy — the test

Run 2026-08-12. Real TLT closes and real option marks (Polygon, via the
`stock-history` and `opt-history` edge functions). 105 weekly rolls,
2024-07-05 → 2026-08-07.

Strikes are placed at a target delta using 20-day realised vol; the **premium
always comes from the real option bar**, so nothing is priced and settled with
the same assumption — the circular-IV trap that reversed an earlier run.

Grid: put OTM(0.25) / ATM(0.50) / ITM(0.75) × calls none / far(0.15) / ATM(0.50).
Delta budget held constant across every arm at 846/wk × the price multiplier.
$400K ceiling enforced. Calls off below 5,000 delivered shares, 20% coverage.

**Whole-window results are misleading and the sub-periods are the finding.**
TLT fell 91.6 → 82.2 across the window, so any arm that sheds shares scores
well for reasons that have nothing to do with the overlay. Read the RALLY block.

`build.py` → roll schedule + strikes · `fetch.py` → real marks ·
`sim2.py` → the three windows.
