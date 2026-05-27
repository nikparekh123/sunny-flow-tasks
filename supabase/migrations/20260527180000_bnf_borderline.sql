-- Borderline / near-miss flag for BNF candidates.
--
-- When a ticker's filter values land within 0.5% slack of any threshold
-- (deviation range, today's intraday floor, sector ETF dev floor) the
-- scanner now ADMITS the candidate and marks it as borderline. The UI
-- shows a yellow chip and the reasons. This fixes the flicker problem
-- where tickers like PARR / MTDR appear/disappear scan-to-scan as a
-- sector ETF oscillates across the -5% line.
--
-- borderline_reasons holds short tags like {'dev-low','sector-near'}
-- so the UI can render specifics on hover.

ALTER TABLE public.bnf_candidates
  ADD COLUMN IF NOT EXISTS borderline boolean NOT NULL DEFAULT false;

ALTER TABLE public.bnf_candidates
  ADD COLUMN IF NOT EXISTS borderline_reasons text[];
