-- BNF research status — persists the user's "I've already looked at this"
-- decision across daily re-scans. The bnf_candidates table is wiped on
-- every scan; this table is keyed by (user, ticker) and outlives any
-- single scan. UI joins on (user, ticker) at render time.
--
-- Lifecycle:
--   • pending       — default / never reviewed. Same as "no row at all".
--   • skipped       — researched, not interested. Filter-out by default.
--   • considering   — researched, on the fence.
--   • approved      — researched and ready to buy / open a paper position.
--
-- Hitting "Buy" on a candidate moves it to bnf_positions and is
-- INDEPENDENT of this status — a row can be approved-but-not-yet-bought.

CREATE TABLE IF NOT EXISTS public.bnf_research_status (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ticker      text NOT NULL,
  status      text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'skipped', 'considering', 'approved')),
  note        text,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, ticker)
);

CREATE INDEX IF NOT EXISTS bnf_research_status_user_idx
  ON public.bnf_research_status (user_id);

ALTER TABLE public.bnf_research_status ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bnf_research_status_own" ON public.bnf_research_status
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
