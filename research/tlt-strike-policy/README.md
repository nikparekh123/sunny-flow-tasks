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

## Round 2 — the extrinsic picker (12 Aug)

`build_ext.py` fetches a full ladder near spot for every roll (980 contracts with
bars) so the EXT arm can *choose* rather than be handed a target strike.
`sim3.py` adds EXT alongside OTM/ATM/ITM. `sim4.py` sweeps the delta floor.

The `EARNED` column is the finding: it separates extrinsic (income) from
intrinsic (a rebate handed back at assignment). ITM collects the largest
headline premium in every window and earns the least of it — $43,510 gross
against $7,747 earned over the full run.

Delta floor swept at 0.25 / 0.30 / 0.35 / 0.40. 0.25 and 0.30 are identical,
so the floor is a safety rail rather than an active constraint. Raising it buys
rally accumulation and costs more elsewhere; 0.25 stays.
