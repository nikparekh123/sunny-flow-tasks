-- BNF scanner: second universe = sector + industry ETFs. Additive only —
-- the existing equity scan and its filters are untouched.
--
-- Two tables share a single 'universe' column:
--   • bnf_candidates → EQUITY rows (existing) and ETF rows (new)
--   • bnf_positions  → same, lets us scope each table view by universe
--
-- New `category` column on bnf_candidates is null for equity rows and
-- holds 'Sector' | 'Industry' | 'Style' for ETFs.

ALTER TABLE public.bnf_candidates
  ADD COLUMN IF NOT EXISTS universe text NOT NULL DEFAULT 'EQUITY'
    CHECK (universe IN ('EQUITY', 'ETF')),
  ADD COLUMN IF NOT EXISTS category text
    CHECK (category IS NULL OR category IN ('Sector', 'Industry', 'Style')),
  -- Signal-day volume ratio: today's volume / 20-day avg volume.
  -- Surface-only on the ETF table; equity rows leave it null.
  ADD COLUMN IF NOT EXISTS signal_day_vol_ratio numeric;

ALTER TABLE public.bnf_positions
  ADD COLUMN IF NOT EXISTS universe text NOT NULL DEFAULT 'EQUITY'
    CHECK (universe IN ('EQUITY', 'ETF'));

-- Backfill any existing rows (defaults to 'EQUITY' but be defensive).
UPDATE public.bnf_candidates SET universe = 'EQUITY' WHERE universe IS NULL;
UPDATE public.bnf_positions  SET universe = 'EQUITY' WHERE universe IS NULL;

CREATE INDEX IF NOT EXISTS bnf_candidates_universe_idx
  ON public.bnf_candidates (user_id, universe);
CREATE INDEX IF NOT EXISTS bnf_positions_universe_idx
  ON public.bnf_positions (user_id, universe, status);
