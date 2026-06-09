/* ============================================================
   position_history — daily snapshot of qty + cost basis per ticker
   ============================================================
   `positions` is upserted in place (current state only). This new
   table captures one row per (snapshot_date, ticker) so we can
   plot cost basis / quantity over time, audit changes after
   trades / assignments, and show "your META holding has grown
   from N shares to M shares since X" style trajectories later.

   Written by the `position-snapshot` cron once a day post-close.
   ============================================================ */

CREATE TABLE IF NOT EXISTS public.position_history (
  snapshot_date date NOT NULL,
  ticker        text NOT NULL,
  quantity      numeric NOT NULL DEFAULT 0,
  avg_cost      numeric NOT NULL DEFAULT 0,
  current_price numeric,
  unrealized_pl numeric,
  -- Lifetime realized P&L on shares as of this snapshot. Useful for
  -- attributing changes between snapshots (a sale shows up as a
  -- drop in qty + jump in realized).
  realized_stock_pl numeric NOT NULL DEFAULT 0,
  captured_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (snapshot_date, ticker)
);

CREATE INDEX IF NOT EXISTS idx_position_history_ticker_date
  ON public.position_history (ticker, snapshot_date DESC);

ALTER TABLE public.position_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "position_history: authenticated read"
  ON public.position_history;
CREATE POLICY "position_history: authenticated read"
  ON public.position_history FOR SELECT TO authenticated USING (true);

-- Realtime (optional but cheap).
DO $$
BEGIN
  EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.position_history';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
