# TLT vs SLV vs URA for shares + weekly ATM calls (Nik, 8 Oct 2026)

`build.py`/`sim.py` real Friday-to-Friday ATM call bars, $1.15M each, Sep 2024 to
Oct 2026. `forward.py` 12-month scenarios at the 7 Oct chain + LEAP comparison.

- Backtest calls kept: TLT +$128k (19% of premium), SLV -$855k (silver +115%),
  URA +$149k (3%, after -$655k in rallies and +$800k in the falls).
- Today: TLT implied 14.7% vs realised 9.9% (edge). SLV 33.3% vs 38.0% and URA
  42.0% vs 43.9% (no edge, calls lose on average).
- Carry: TLT +2%/yr, SLV -3% (no dividend), URA ~0 (lumpy year-end payout).
- LEAP time value: TLT 8% of price, SLV 25%, URA 32% (Jan-29 ATM).
- URA weeklies trade 7-60 contracts a day; $1.15M needs ~288 a week.
