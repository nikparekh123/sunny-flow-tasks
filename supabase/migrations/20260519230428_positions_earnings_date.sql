-- Earnings handling simplified to a single date column on positions.
-- Replaces the (unused) earnings_events / ticker_peers tables from the
-- prior earnings module — those are dropped here. Anything captured in
-- those tables is lost; only the column matters now.

ALTER TABLE public.positions
  ADD COLUMN IF NOT EXISTS earnings_date date;

-- Clean up the abandoned earnings workbench schema. CASCADE removes the
-- indexes, RLS policies, and realtime publication entries automatically.
DROP TABLE IF EXISTS public.earnings_events CASCADE;
DROP TABLE IF EXISTS public.ticker_peers     CASCADE;
