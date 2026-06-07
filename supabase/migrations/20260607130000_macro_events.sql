/* ============================================================
   macro_events — economic calendar
   ============================================================
   Replaces the hardcoded MacroEvents.swift list with a DB-backed
   calendar. The iOS client reads rows via PostgREST and renders
   the next ~5 days of events as Update cards on Home.

   Schema is generic enough to ingest from any source:
   • Manual entries (curated by SWM)
   • Investing.com scrape (current seed)
   • FRED API or other future feeds

   Each event has:
   • event_date / event_time / timezone — when it happens (we
     store ET strings on the time side; the client converts).
   • importance 1-3 stars matching investing.com convention
   • forecast / previous / actual — economists' values, kept as
     text since some are %, some are M, some are K, some null.
   • is_holiday + early_close — flags for market schedule events
     (Juneteenth, Christmas Eve early close, etc.)
   • source / source_id — provenance for dedup. Manual entries
     get source='manual' and a hand-picked source_id.

   Dedup key is (event_date, name, country) so a sync job can
   safely ON CONFLICT UPDATE without creating duplicates.
   ============================================================ */

CREATE TABLE IF NOT EXISTS public.macro_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_date      date NOT NULL,
  event_time      time,                    -- nullable for all-day events
  timezone        text NOT NULL DEFAULT 'America/New_York',
  country         text NOT NULL DEFAULT 'US',
  name            text NOT NULL,           -- "CPI (MoM) (May)", "Fed Interest Rate Decision"
  category        text,                    -- 'inflation' | 'rates' | 'jobs' | 'gdp' | 'housing' | 'pmi' | 'holiday' | 'auction' | 'energy' | 'manufacturing'
  importance      smallint NOT NULL DEFAULT 1 CHECK (importance BETWEEN 1 AND 3),
  forecast        text,
  previous        text,
  actual          text,                    -- populated post-release
  is_holiday      boolean NOT NULL DEFAULT false,
  early_close     boolean NOT NULL DEFAULT false,
  early_close_at  time,
  summary         text,                    -- free-form one-liner shown on the Home card
  source          text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','investing.com','fred','tradingeconomics','other')),
  source_id       text,                    -- external id for ingestion dedup
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_date, name, country)
);

CREATE INDEX IF NOT EXISTS idx_macro_events_date
  ON public.macro_events (event_date);

-- Hot path for the Home card query: "next N events from today"
CREATE INDEX IF NOT EXISTS idx_macro_events_upcoming
  ON public.macro_events (event_date, event_time)
  WHERE event_date >= CURRENT_DATE;

CREATE INDEX IF NOT EXISTS idx_macro_events_importance_upcoming
  ON public.macro_events (event_date)
  WHERE importance >= 3 AND event_date >= CURRENT_DATE;

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.macro_events_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_macro_events_updated_at ON public.macro_events;
CREATE TRIGGER trg_macro_events_updated_at
  BEFORE UPDATE ON public.macro_events
  FOR EACH ROW
  EXECUTE FUNCTION public.macro_events_set_updated_at();

ALTER TABLE public.macro_events ENABLE ROW LEVEL SECURITY;

-- Authenticated clients can read. Writes go through service-role
-- (Edge Function sync job or hand-curated SQL).
DROP POLICY IF EXISTS "macro_events: authenticated read" ON public.macro_events;
CREATE POLICY "macro_events: authenticated read"
  ON public.macro_events
  FOR SELECT TO authenticated
  USING (true);

/* ============================================================
   Seed: economic calendar June–December 2026
   ============================================================
   Source: investing.com US economic calendar, captured 2026-06-07.
   Re-running this migration is safe; ON CONFLICT (event_date,
   name, country) DO UPDATE refreshes forecast/previous values.
   ============================================================ */

INSERT INTO public.macro_events
  (event_date, event_time, name, category, importance, forecast, previous, is_holiday, early_close, early_close_at, summary, source)
VALUES
  -- Tue Jun 9
  ('2026-06-09', '10:00', 'Existing Home Sales (May)', 'housing', 3, '4.08M', '4.02M', false, false, NULL, NULL, 'investing.com'),

  -- Wed Jun 10 — CPI day
  ('2026-06-10', '08:30', 'CPI (MoM) (May)', 'inflation', 3, '0.3%', '0.6%', false, false, NULL, 'May headline CPI · MoM', 'investing.com'),
  ('2026-06-10', '08:30', 'Core CPI (MoM) (May)', 'inflation', 3, '0.5%', '0.4%', false, false, NULL, NULL, 'investing.com'),
  ('2026-06-10', '08:30', 'CPI (YoY) (May)', 'inflation', 3, '4.2%', '3.8%', false, false, NULL, NULL, 'investing.com'),
  ('2026-06-10', '10:30', 'Crude Oil Inventories', 'energy', 3, NULL, '-7.974M', false, false, NULL, NULL, 'investing.com'),
  ('2026-06-10', '13:00', '10-Year Note Auction', 'auction', 3, NULL, '4.468%', false, false, NULL, NULL, 'investing.com'),

  -- Thu Jun 11
  ('2026-06-11', '08:30', 'PPI (MoM) (May)', 'inflation', 3, '0.7%', '1.4%', false, false, NULL, NULL, 'investing.com'),
  ('2026-06-11', '08:30', 'Initial Jobless Claims', 'jobs', 3, '225K', '225K', false, false, NULL, NULL, 'investing.com'),

  -- Wed Jun 17 — FOMC
  ('2026-06-17', '08:30', 'Retail Sales (MoM) (May)', 'consumer', 3, NULL, '0.5%', false, false, NULL, NULL, 'investing.com'),
  ('2026-06-17', '08:30', 'Core Retail Sales (MoM) (May)', 'consumer', 3, NULL, '0.7%', false, false, NULL, NULL, 'investing.com'),
  ('2026-06-17', '14:00', 'Fed Interest Rate Decision', 'rates', 3, NULL, '3.75%', false, false, NULL, 'FOMC decision + presser', 'investing.com'),

  -- Thu Jun 18
  ('2026-06-18', '08:30', 'Philadelphia Fed Manufacturing Index (Jun)', 'manufacturing', 3, NULL, '-0.4', false, false, NULL, NULL, 'investing.com'),

  -- Fri Jun 19 — Juneteenth
  ('2026-06-19', NULL, 'Juneteenth', 'holiday', 3, NULL, NULL, true, false, NULL, 'US market closed', 'investing.com'),

  -- Tue Jun 23 — PMI
  ('2026-06-23', '09:45', 'S&P Global Services PMI (Jun)', 'pmi', 3, NULL, '50.7', false, false, NULL, NULL, 'investing.com'),
  ('2026-06-23', '09:45', 'S&P Global Manufacturing PMI (Jun)', 'pmi', 3, NULL, '55.1', false, false, NULL, NULL, 'investing.com'),

  -- Wed Jun 24
  ('2026-06-24', '10:00', 'New Home Sales (May)', 'housing', 3, NULL, '622K', false, false, NULL, NULL, 'investing.com'),

  -- Thu Jun 25 — PCE day
  ('2026-06-25', '08:30', 'Core PCE Price Index (YoY) (May)', 'inflation', 3, NULL, '3.3%', false, false, NULL, 'Fed''s preferred inflation gauge', 'investing.com'),
  ('2026-06-25', '08:30', 'Core PCE Price Index (MoM) (May)', 'inflation', 3, NULL, '0.2%', false, false, NULL, NULL, 'investing.com'),
  ('2026-06-25', '08:30', 'GDP (QoQ) (Q1)', 'gdp', 3, NULL, '1.6%', false, false, NULL, NULL, 'investing.com'),
  ('2026-06-25', '08:30', 'Durable Goods Orders (MoM) (May)', 'manufacturing', 3, NULL, '8.0%', false, false, NULL, NULL, 'investing.com'),

  -- Fri Jul 3 — Independence Day (observed; market closed)
  ('2026-07-03', NULL, 'Independence Day (Observed)', 'holiday', 3, NULL, NULL, true, false, NULL, 'US market closed (4th falls on Sat)', 'investing.com'),

  -- Wed Jul 29 — FOMC
  ('2026-07-29', '14:00', 'Fed Interest Rate Decision', 'rates', 3, NULL, NULL, false, false, NULL, 'FOMC decision + presser', 'investing.com'),

  -- Mon Sep 7 — Labor Day
  ('2026-09-07', NULL, 'Labor Day', 'holiday', 3, NULL, NULL, true, false, NULL, 'US market closed', 'investing.com'),

  -- Wed Sep 16 — FOMC
  ('2026-09-16', '14:00', 'Fed Interest Rate Decision', 'rates', 3, NULL, NULL, false, false, NULL, 'FOMC decision + presser · SEP/dot plot release', 'investing.com'),

  -- Wed Oct 28 — FOMC
  ('2026-10-28', '14:00', 'Fed Interest Rate Decision', 'rates', 3, NULL, NULL, false, false, NULL, 'FOMC decision + presser', 'investing.com'),

  -- Thu Nov 26 — Thanksgiving
  ('2026-11-26', NULL, 'Thanksgiving Day', 'holiday', 3, NULL, NULL, true, false, NULL, 'US market closed', 'investing.com'),

  -- Fri Nov 27 — Day after Thanksgiving (early close 13:00)
  ('2026-11-27', NULL, 'Day After Thanksgiving (Early Close)', 'holiday', 2, NULL, NULL, false, true, '13:00', 'US market closes early at 13:00 ET', 'investing.com'),

  -- Wed Dec 9 — FOMC
  ('2026-12-09', '14:00', 'Fed Interest Rate Decision', 'rates', 3, NULL, NULL, false, false, NULL, 'FOMC decision + presser · final 2026 meeting · SEP/dot plot release', 'investing.com'),

  -- Thu Dec 24 — Christmas Eve (early close 13:00)
  ('2026-12-24', NULL, 'Christmas Eve (Early Close)', 'holiday', 2, NULL, NULL, false, true, '13:00', 'US market closes early at 13:00 ET', 'investing.com'),

  -- Fri Dec 25 — Christmas Day
  ('2026-12-25', NULL, 'Christmas Day', 'holiday', 3, NULL, NULL, true, false, NULL, 'US market closed', 'investing.com')

ON CONFLICT (event_date, name, country) DO UPDATE
SET
  event_time     = EXCLUDED.event_time,
  category       = EXCLUDED.category,
  importance     = EXCLUDED.importance,
  forecast       = EXCLUDED.forecast,
  previous       = EXCLUDED.previous,
  is_holiday     = EXCLUDED.is_holiday,
  early_close    = EXCLUDED.early_close,
  early_close_at = EXCLUDED.early_close_at,
  summary        = EXCLUDED.summary,
  source         = EXCLUDED.source,
  updated_at     = now();
