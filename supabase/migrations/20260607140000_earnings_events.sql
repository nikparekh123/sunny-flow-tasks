/* ============================================================
   earnings_events — quarterly earnings calendar
   ============================================================
   Sibling to macro_events but ticker-scoped. Each row is a single
   company's earnings release on a specific date, with forecast
   and actual values, market context, and a `scope_tag` that
   records WHY this ticker is in our calendar.

   Scope:
   • 'position' — ticker is in the firm's current book
   • 'peer'     — sector-ETF peer of a position
   • 'top50'    — high-impact name (mega-cap, heavy options volume)
   • 'other'    — manual/curated, doesn't fit the above

   `peer_of_tickers` records which holding(s) drove a peer's
   inclusion, so when a position is closed we can re-evaluate
   whether to keep its peers in the calendar.

   Numeric storage:
   • Money columns (market_cap, revenue_*) stored in raw dollars
     so 19.1B becomes 19100000000. Postgres numeric handles this
     cleanly and the iOS formatter renders back to "19.1B" / "$614B".
   • Percent columns stored as plain numbers (e.g. -9.59 for -9.59%).

   Dedup key is (ticker, report_date) — running the seed twice
   updates forecast/last_price etc. without dupes.
   ============================================================ */

CREATE TABLE IF NOT EXISTS public.earnings_events (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticker               text NOT NULL,
  company_name         text,
  report_date          date NOT NULL,
  report_time          text CHECK (report_time IN ('bmo','amc','tba')),  -- before-market | after-market | TBA
  fiscal_period        text,                                              -- 'Q1 2026', 'FY 2026'

  -- Forecast (analyst consensus prior to release)
  eps_forecast         numeric,
  revenue_forecast     numeric,                -- raw dollars

  -- Actual (populated post-release)
  eps_actual           numeric,
  revenue_actual       numeric,                -- raw dollars
  eps_surprise_pct     numeric,                -- (actual - forecast) / forecast * 100
  revenue_surprise_pct numeric,

  -- Market context at the time of the calendar capture
  market_cap           numeric,                -- raw dollars
  last_price           numeric,
  last_change_pct      numeric,                -- e.g. -2.70 for "-2.70%"
  extended_price       numeric,
  extended_change_pct  numeric,

  -- Analyst revisions in the run-up
  eps_revisions_up     integer,
  eps_revisions_down   integer,

  -- Why this ticker is here
  scope_tag            text NOT NULL CHECK (scope_tag IN ('position','peer','top50','other')),
  peer_of_tickers      text[],                 -- NULL unless scope_tag = 'peer'
  sector_etf           text,                   -- 'XLF', 'XLK', 'XLY', etc.

  -- Provenance
  source               text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','investing.com','fmp','iex','other')),
  source_id            text,
  notes                text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ticker, report_date)
);

CREATE INDEX IF NOT EXISTS idx_earnings_events_date
  ON public.earnings_events (report_date);

CREATE INDEX IF NOT EXISTS idx_earnings_events_ticker
  ON public.earnings_events (ticker);

CREATE INDEX IF NOT EXISTS idx_earnings_events_scope_date
  ON public.earnings_events (scope_tag, report_date);

-- updated_at trigger (reuse the helper pattern from macro_events; new
-- function name to keep them independent if either gets dropped)
CREATE OR REPLACE FUNCTION public.earnings_events_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_earnings_events_updated_at ON public.earnings_events;
CREATE TRIGGER trg_earnings_events_updated_at
  BEFORE UPDATE ON public.earnings_events
  FOR EACH ROW
  EXECUTE FUNCTION public.earnings_events_set_updated_at();

ALTER TABLE public.earnings_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "earnings_events: authenticated read" ON public.earnings_events;
CREATE POLICY "earnings_events: authenticated read"
  ON public.earnings_events
  FOR SELECT TO authenticated
  USING (true);

/* ============================================================
   Seed — Batch 1 (investing.com earnings calendar, 2026-06-07)
   ============================================================
   Positions held: META, WDAY, FIG (Figma), INTU, ADBE, DVN, UBER,
   BBY, HOOD, LULU, NFLX, PYPL, NKE.
   Filtered to direct positions + clear sector-ETF peers.
   Skipped 20+ XLP/XLV/weak-XLI names that don't peer well.
   ============================================================ */

INSERT INTO public.earnings_events
  (ticker, company_name, report_date, report_time, eps_forecast, revenue_forecast,
   market_cap, last_price, last_change_pct, extended_price, extended_change_pct,
   eps_revisions_up, eps_revisions_down,
   scope_tag, peer_of_tickers, sector_etf, source)
VALUES
  -- ── POSITIONS ──────────────────────────────────────────────
  ('ADBE', 'Adobe Inc.',              '2026-06-11', 'amc', 5.82,    6460000000,    101630000000, 251.44, -2.70, 249.59, -0.73, 24,  1,  'position', NULL,                              'XLK', 'investing.com'),
  ('NKE',  'NIKE Inc.',               '2026-06-30', 'amc', 0.1174,  10850000000,   63650000000,  42.98,  -1.47, 42.92,  -0.14, 2,   21, 'position', NULL,                              'XLY', 'investing.com'),

  -- ── XLF PEERS (HOOD, PYPL) ─────────────────────────────────
  ('JPM',  'JPMorgan Chase & Co.',    '2026-07-14', 'bmo', 5.43,    48700000000,   837000000000, 312.37, 0.48,  311.94, -0.14, 7,   2,  'peer',     ARRAY['HOOD','PYPL']::text[],      'XLF', 'investing.com'),
  ('BAC',  'Bank of America Corp.',   '2026-07-14', 'bmo', 1.10,    30110000000,   382010000000, 53.83,  -0.63, 53.70,  -0.24, 10,  3,  'peer',     ARRAY['HOOD','PYPL']::text[],      'XLF', 'investing.com'),
  ('C',    'Citigroup Inc.',          '2026-07-14', 'bmo', 2.65,    23250000000,   225940000000, 132.47, -1.98, 132.06, -0.31, 4,   4,  'peer',     ARRAY['HOOD','PYPL']::text[],      'XLF', 'investing.com'),
  ('GS',   'Goldman Sachs Group Inc.','2026-07-14', 'bmo', 13.69,   15650000000,   318460000000, 1038.68,-4.94, 1037.00,-0.16, 2,   14, 'peer',     ARRAY['HOOD','PYPL']::text[],      'XLF', 'investing.com'),
  ('WFC',  'Wells Fargo & Co.',       '2026-07-14', 'bmo', 1.70,    21760000000,   250750000000, 81.94,  0.39,  81.73,  -0.25, 0,   8,  'peer',     ARRAY['HOOD','PYPL']::text[],      'XLF', 'investing.com'),
  ('BNY',  'Bank of New York Mellon', '2026-07-15', 'bmo', 2.18,    5340000000,    97730000000,  142.39, -1.13, 142.57, 0.13,  8,   1,  'peer',     ARRAY['HOOD','PYPL']::text[],      'XLF', 'investing.com'),
  ('MS',   'Morgan Stanley',          '2026-07-15', 'bmo', 2.75,    19100000000,   334270000000, 211.93, -2.90, 211.20, -0.34, 10,  3,  'peer',     ARRAY['HOOD','PYPL']::text[],      'XLF', 'investing.com'),
  ('MTB',  'M&T Bank Corp.',          '2026-07-15', 'bmo', 4.63,    2460000000,    32580000000,  222.44, 0.32,  222.44, 0.00,  2,   10, 'peer',     ARRAY['HOOD','PYPL']::text[],      'XLF', 'investing.com'),
  ('PNC',  'PNC Financial Services',  '2026-07-15', 'bmo', 4.34,    6410000000,    91710000000,  228.37, 0.57,  228.37, 0.00,  7,   4,  'peer',     ARRAY['HOOD','PYPL']::text[],      'XLF', 'investing.com'),

  -- ── XLK PEERS (WDAY, INTU, ADBE, FIG) ──────────────────────
  ('ORCL', 'Oracle Corp.',            '2026-06-10', 'amc', 1.95,    19100000000,   614550000000, 213.68, -9.59, 209.80, -1.82, 17,  11, 'peer',     ARRAY['WDAY','INTU','ADBE','FIG']::text[], 'XLK', 'investing.com'),
  ('MU',   'Micron Technology Inc.',  '2026-06-24', 'amc', 19.55,   34270000000,   974370000000, 864.01, -13.25,857.00, -0.81, 26,  0,  'peer',     ARRAY['WDAY','INTU','ADBE','FIG']::text[], 'XLK', 'investing.com'),
  ('ASML', 'ASML Holding N.V. (ADR)', '2026-07-15', 'bmo', 8.07,    10480000000,   648240000000, 1641.74,-6.59, 1640.84,-0.05, 9,   0,  'peer',     ARRAY['WDAY','INTU','ADBE','FIG']::text[], 'XLK', 'investing.com'),

  -- ── XLY PEERS (UBER, BBY, LULU, NKE) ───────────────────────
  ('DRI',  'Darden Restaurants Inc.', '2026-06-25', 'bmo', 3.63,    3730000000,    22690000000,  198.12, 2.41,  195.55, -1.30, 21,  5,  'peer',     ARRAY['UBER','BBY','LULU','NKE']::text[],  'XLY', 'investing.com'),
  ('CCL',  'Carnival Corp.',          '2026-06-30', 'bmo', 0.3279,  6680000000,    37920000000,  27.41,  -1.58, 27.28,  -0.47, 0,   19, 'peer',     ARRAY['UBER','BBY','LULU','NKE']::text[],  'XLY', 'investing.com')

ON CONFLICT (ticker, report_date) DO UPDATE
SET
  company_name         = EXCLUDED.company_name,
  report_time          = EXCLUDED.report_time,
  eps_forecast         = EXCLUDED.eps_forecast,
  revenue_forecast     = EXCLUDED.revenue_forecast,
  market_cap           = EXCLUDED.market_cap,
  last_price           = EXCLUDED.last_price,
  last_change_pct      = EXCLUDED.last_change_pct,
  extended_price       = EXCLUDED.extended_price,
  extended_change_pct  = EXCLUDED.extended_change_pct,
  eps_revisions_up     = EXCLUDED.eps_revisions_up,
  eps_revisions_down   = EXCLUDED.eps_revisions_down,
  scope_tag            = EXCLUDED.scope_tag,
  peer_of_tickers      = EXCLUDED.peer_of_tickers,
  sector_etf           = EXCLUDED.sector_etf,
  source               = EXCLUDED.source,
  updated_at           = now();
