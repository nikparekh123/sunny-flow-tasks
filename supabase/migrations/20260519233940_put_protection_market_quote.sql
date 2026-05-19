-- Extend put_protection with the data we need to mark-to-market via the
-- Polygon (Massive) options API:
--   contracts            — integer, count of put contracts (each = 100 shares)
--   strike               — numeric, per-share strike price
--   current_premium      — numeric, latest per-share premium from Polygon
--   current_premium_at   — timestamptz, when current_premium was last refreshed
--
-- The refresh-put-quotes edge function (paired with this migration) builds
-- the OCC option symbol from ticker + expiry + strike, fetches the latest
-- trade/quote, and writes current_premium + current_premium_at.

ALTER TABLE public.put_protection
  ADD COLUMN IF NOT EXISTS contracts          integer,
  ADD COLUMN IF NOT EXISTS strike             numeric,
  ADD COLUMN IF NOT EXISTS current_premium    numeric,
  ADD COLUMN IF NOT EXISTS current_premium_at timestamptz;
