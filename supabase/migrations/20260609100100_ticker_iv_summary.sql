/* ============================================================
   ticker_iv_summary — per-ticker IV roll-up view
   ============================================================
   One row per ticker that has any ticker_iv_daily history.
   This is what the iOS app reads — all the Seller Score math is
   done client-side from these primitives.

   Columns:
     ticker             — symbol
     current_iv         — latest atm_iv (decimal, 0.42 = 42%)
     current_hv30       — latest hv30   (decimal, 0.31 = 31%)
     iv_low             — min atm_iv over the window
     iv_high            — max atm_iv over the window
     iv_window_days     — actual count of distinct snapshot_dates
                          (UI labels "Xd range" honestly)
     last_snapshot_date — date of the most recent capture
     window_start       — earliest snapshot_date in the window

   Window is "all history we have" — no rolling 52w slice yet.
   Once we have ≥ 365 days, swap to a rolling 365d via a WHERE
   clause; the column names stay the same.
   ============================================================ */

CREATE OR REPLACE VIEW public.ticker_iv_summary AS
WITH latest AS (
  SELECT DISTINCT ON (ticker)
    ticker, atm_iv AS current_iv, hv30 AS current_hv30, snapshot_date AS last_snapshot_date
  FROM public.ticker_iv_daily
  ORDER BY ticker, snapshot_date DESC
),
agg AS (
  SELECT
    ticker,
    MIN(atm_iv)       AS iv_low,
    MAX(atm_iv)       AS iv_high,
    COUNT(DISTINCT snapshot_date) AS iv_window_days,
    MIN(snapshot_date) AS window_start
  FROM public.ticker_iv_daily
  GROUP BY ticker
)
SELECT
  l.ticker,
  l.current_iv,
  l.current_hv30,
  a.iv_low,
  a.iv_high,
  a.iv_window_days,
  l.last_snapshot_date,
  a.window_start
FROM latest l
JOIN agg a USING (ticker);

COMMENT ON VIEW public.ticker_iv_summary IS
  'Per-ticker IV roll-up: current IV/HV30, min/max over the available window, day count. Client computes IVR/spread/SellerScore from these.';
