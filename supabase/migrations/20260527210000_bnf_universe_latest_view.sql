-- bnf_universe_latest — one row per ticker with the most recent cached
-- bar plus SMA25 / SMA200 / deviation% / today's intraday%. Powers the
-- unified universe table on the New Strategy page so we can render all
-- ~1030 tickers (not just the BNF survivors), gray by default and
-- highlighted when the BNF setup criteria are hit.
--
-- All math is done in SQL via window functions over bnf_universe_data
-- so the frontend receives ~1030 small rows in a single query.

CREATE OR REPLACE VIEW public.bnf_universe_latest AS
WITH ranked AS (
  SELECT
    ticker,
    date,
    open,
    close,
    volume,
    ROW_NUMBER() OVER (PARTITION BY ticker ORDER BY date DESC) AS rn,
    COUNT(*)    OVER (PARTITION BY ticker)                     AS bars_count,
    -- Trailing 25-bar SMA ending on this row. Needs 25 prior bars to be
    -- complete — we expose `bars_count` so the UI can hide partial values.
    AVG(close)  OVER (
      PARTITION BY ticker ORDER BY date
      ROWS BETWEEN 24 PRECEDING AND CURRENT ROW
    ) AS sma25,
    -- Trailing 200-bar SMA. Tickers with <200 bars in the cache will get
    -- a partial value here too; UI filters those out.
    AVG(close)  OVER (
      PARTITION BY ticker ORDER BY date
      ROWS BETWEEN 199 PRECEDING AND CURRENT ROW
    ) AS sma200,
    -- 20-day average dollar volume (for the BNF ADV gate).
    AVG(close * COALESCE(volume, 0)) OVER (
      PARTITION BY ticker ORDER BY date
      ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) AS adv20_dollars
  FROM public.bnf_universe_data
)
SELECT
  ticker,
  date                                   AS latest_date,
  close                                  AS latest_close,
  open                                   AS latest_open,
  volume                                 AS latest_volume,
  sma25,
  sma200,
  CASE WHEN sma25  > 0 THEN ((close - sma25)  / sma25)  * 100 END AS deviation_pct,
  CASE WHEN open   > 0 THEN ((close - open)   / open)   * 100 END AS today_intraday_pct,
  adv20_dollars / 1000000.0              AS adv20_m,
  bars_count
FROM ranked
WHERE rn = 1;

-- The view inherits security from bnf_universe_data. That table has no
-- RLS today (public market data, written by service-role only). Enable
-- RLS + a permissive read policy so authenticated clients can read both
-- the base table and the view without the service role.
ALTER TABLE public.bnf_universe_data ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bnf_universe_data_read" ON public.bnf_universe_data;
CREATE POLICY "bnf_universe_data_read"
  ON public.bnf_universe_data
  FOR SELECT
  TO authenticated
  USING (true);

GRANT SELECT ON public.bnf_universe_latest TO authenticated;
