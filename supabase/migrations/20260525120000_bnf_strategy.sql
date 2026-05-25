-- BNF mean-reversion strategy — scanner + manual paper-trading tables.
--
-- Two tables:
--   bnf_candidates — scanner output. Replaced on every run (delete-then-
--                    insert by user). One row per qualifying ticker.
--   bnf_positions  — the user's paper-trading book. One row per "Buy"
--                    click; status flips from 'open' → 'closed' on Sell.
--
-- Both are RLS-scoped to the signed-in user. No shared global state.

-- ── bnf_candidates ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bnf_candidates (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scanned_at      timestamptz NOT NULL DEFAULT now(),
  ticker          text NOT NULL,
  sector          text,
  price           numeric NOT NULL,
  sma25           numeric NOT NULL,
  sma200          numeric NOT NULL,
  deviation_pct   numeric NOT NULL,   -- (price − sma25) / sma25 × 100; negative for dislocated longs
  adv20_m         numeric,            -- 20-day avg dollar volume, in millions
  days_to_earnings integer,           -- null when unknown; positive = future
  today_intraday_pct numeric,         -- (close − open) / open × 100
  sector_etf      text,
  sector_etf_dev_pct numeric,         -- the mapped ETF's own dev vs its SMA25
  -- Options risk context (nulls allowed; not all symbols have options)
  iv30            numeric,
  iv_rank         numeric,
  options_volume  integer,
  put_call_ratio  numeric,
  open_interest   integer
);

CREATE INDEX IF NOT EXISTS bnf_candidates_user_idx
  ON public.bnf_candidates (user_id, scanned_at DESC);

ALTER TABLE public.bnf_candidates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bnf_candidates_own" ON public.bnf_candidates
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── bnf_positions ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bnf_positions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ticker          text NOT NULL,
  status          text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  -- Entry snapshot — captured the moment the user clicks Buy
  entry_date      date NOT NULL DEFAULT CURRENT_DATE,
  entry_price     numeric NOT NULL,
  entry_deviation_pct numeric NOT NULL,
  entry_iv        numeric,
  -- Exit snapshot — populated when user clicks Sell
  exit_date       date,
  exit_price      numeric,
  exit_reason     text,               -- 'target_hit' | 'manual' | 'stale'
  realized_pct    numeric,            -- materialised at close so views are cheap
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS bnf_positions_user_status_idx
  ON public.bnf_positions (user_id, status);

ALTER TABLE public.bnf_positions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bnf_positions_own" ON public.bnf_positions
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
