-- BNF universe data cache — daily OHLCV per ticker, shared across users.
--
-- The bnf-scan function used to fetch 200 days of aggregates per ticker
-- from Polygon on every scan (999 calls). That blew through Polygon
-- rate limits and Supabase's edge function timeout. This table caches
-- the historical aggregates once; scans read from it in milliseconds.
--
-- Populated by:
--   bnf-cache-backfill   — one-time + manual, multi-day load
--   bnf-cache-update     — daily incremental (nightly cron)
--
-- Shared across users (no RLS) since the data isn't user-specific. The
-- candidate filtering still happens per user in bnf-scan.

CREATE TABLE IF NOT EXISTS public.bnf_universe_data (
  ticker      text NOT NULL,
  date        date NOT NULL,
  open        numeric,
  close       numeric NOT NULL,
  prev_close  numeric,
  volume      numeric,
  fetched_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ticker, date)
);

-- Per-ticker lookup (scan reads 200 dates for each of ~999 tickers).
CREATE INDEX IF NOT EXISTS bnf_universe_data_ticker_date_idx
  ON public.bnf_universe_data (ticker, date DESC);

-- Per-date lookup (cron pulls "yesterday's snapshot", reads all rows
-- on one date).
CREATE INDEX IF NOT EXISTS bnf_universe_data_date_idx
  ON public.bnf_universe_data (date);

-- No RLS — pricing data is public market data, no per-user scoping needed.
-- Edge functions write via the service role; clients don't read this
-- directly (they read bnf_candidates which is RLS'd).
