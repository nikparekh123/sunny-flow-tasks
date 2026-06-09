/* ============================================================
   Append-only refactor — option_greeks + ticker_quotes
   ============================================================
   Both tables were originally one-row-per-key with upsert-in-place
   so each cron run overwrote the prior capture. That's correct for
   "current spot" / "current Greeks" reads but throws away history.

   Refactor:
   • Drop the primary key constraint on the natural key
   • Add a surrogate `id uuid` PK (so duplicate captures within the
     same microsecond can't collide)
   • Add a (natural_key, captured_at DESC) index for cheap "latest"
     lookups
   • Expose `*_latest` views that return one row per natural key —
     the existing PostgREST queries point at these so no client
     change is required beyond the table name
   • Retention prunes: 90 days for greeks (intraday matters for
     theta-acceleration analysis), 30 days for quotes (daily-close
     history already lives in `daily_closes`)

   Backwards-compat: existing rows keep working; new captures
   become additive rather than replacing.
   ============================================================ */

-- ─── option_greeks → append-only ───────────────────────────────
DO $$
BEGIN
  -- Drop the natural-key PK if it still exists.
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'option_greeks_pkey'
      AND conrelid = 'public.option_greeks'::regclass
  ) THEN
    ALTER TABLE public.option_greeks DROP CONSTRAINT option_greeks_pkey;
  END IF;
END $$;

-- Add surrogate PK if not already present.
ALTER TABLE public.option_greeks
  ADD COLUMN IF NOT EXISTS id uuid NOT NULL DEFAULT gen_random_uuid();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.option_greeks'::regclass AND contype = 'p'
  ) THEN
    ALTER TABLE public.option_greeks ADD PRIMARY KEY (id);
  END IF;
END $$;

-- Fast "latest per trade" lookup.
CREATE INDEX IF NOT EXISTS idx_option_greeks_trade_captured
  ON public.option_greeks (option_trade_id, captured_at DESC);

-- One row per trade, latest capture. Used everywhere the old table
-- was queried — keep the read API identical from the client side.
CREATE OR REPLACE VIEW public.option_greeks_latest AS
SELECT DISTINCT ON (option_trade_id) *
FROM public.option_greeks
ORDER BY option_trade_id, captured_at DESC;

-- ─── ticker_quotes → append-only ───────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ticker_quotes_pkey'
      AND conrelid = 'public.ticker_quotes'::regclass
  ) THEN
    ALTER TABLE public.ticker_quotes DROP CONSTRAINT ticker_quotes_pkey;
  END IF;
END $$;

ALTER TABLE public.ticker_quotes
  ADD COLUMN IF NOT EXISTS id uuid NOT NULL DEFAULT gen_random_uuid();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.ticker_quotes'::regclass AND contype = 'p'
  ) THEN
    ALTER TABLE public.ticker_quotes ADD PRIMARY KEY (id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ticker_quotes_ticker_captured
  ON public.ticker_quotes (ticker, captured_at DESC);

CREATE OR REPLACE VIEW public.ticker_quotes_latest AS
SELECT DISTINCT ON (ticker) *
FROM public.ticker_quotes
ORDER BY ticker, captured_at DESC;

-- ─── Retention prune RPCs ──────────────────────────────────────
-- Idempotent helpers we'll schedule on a daily cron. Returning the
-- delete count is useful for monitoring later.

CREATE OR REPLACE FUNCTION public.prune_option_greeks_90d()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count integer;
BEGIN
  DELETE FROM public.option_greeks
  WHERE captured_at < now() - interval '90 days';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END $$;

CREATE OR REPLACE FUNCTION public.prune_ticker_quotes_30d()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count integer;
BEGIN
  DELETE FROM public.ticker_quotes
  WHERE captured_at < now() - interval '30 days';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END $$;

-- Lock down: only service role can execute prunes.
REVOKE ALL ON FUNCTION public.prune_option_greeks_90d() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prune_ticker_quotes_30d() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prune_option_greeks_90d() TO service_role;
GRANT EXECUTE ON FUNCTION public.prune_ticker_quotes_30d() TO service_role;
