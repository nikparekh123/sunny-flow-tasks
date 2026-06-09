/* ============================================================
   ticker_iv_daily — append-only per-ticker IV history table
   ============================================================
   Powers the new Seller Score IV section on the Today screen.

   One row per (ticker, snapshot_date). Captured daily after market
   close by the `ticker-iv-snapshot` edge function. Drives:
     • current_iv (most recent atm_iv)
     • iv_low / iv_high (min/max over the window we have)
     • hv30 (30-day realized vol, computed daily from daily_closes)
     • spread = current_iv − hv30
     • IVR = (current_iv − iv_low) / (iv_high − iv_low) × 100
     • Seller Score = IVR×0.6 + normSpread×0.4

   "Build forward" strategy: starts empty, builds toward 365d over
   the year. The view (ticker_iv_summary) labels the window with
   actual days available so the UI can say "90d range" → "365d range"
   honestly.

   No retention prune — daily granularity for 365d is ~30 KB per
   held ticker. Trivial.
   ============================================================ */

CREATE TABLE IF NOT EXISTS public.ticker_iv_daily (
  ticker         text       NOT NULL,
  snapshot_date  date       NOT NULL,
  atm_iv         numeric    NOT NULL,           -- decimal, 0.42 = 42%
  hv30           numeric,                       -- decimal, 0.31 = 31% annualized
  source         text       NOT NULL DEFAULT 'cron'
                            CHECK (source IN ('cron','seed','backfill','manual')),
  contract_used  text,                          -- OCC ticker of the ATM 30d contract sampled
  captured_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ticker, snapshot_date)
);

CREATE INDEX IF NOT EXISTS idx_ticker_iv_daily_ticker_date
  ON public.ticker_iv_daily (ticker, snapshot_date DESC);

ALTER TABLE public.ticker_iv_daily ENABLE ROW LEVEL SECURITY;

-- Read for any authenticated user (single-user app + service-role writes).
DROP POLICY IF EXISTS ticker_iv_daily_read ON public.ticker_iv_daily;
CREATE POLICY ticker_iv_daily_read
  ON public.ticker_iv_daily
  FOR SELECT
  TO authenticated
  USING (true);

COMMENT ON TABLE public.ticker_iv_daily IS
  'Daily ATM-30d IV + HV30 per held ticker. Append-only, populated by ticker-iv-snapshot cron after market close. Window grows from 0 → 365d over the year.';
