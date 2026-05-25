-- BNF scanner risk flags — three new display columns on bnf_candidates.
-- Populated by bnf-scan during the survivor-enrichment pass, and refresh-
-- able independently via the new bnf-refresh-flags function.
--
-- These are DISPLAY flags, not hard filters — the user reviews them and
-- decides whether to click Buy.

ALTER TABLE public.bnf_candidates
  ADD COLUMN IF NOT EXISTS days_since_earnings integer,         -- trading days since last reported earnings (null = >30d or unknown)
  ADD COLUMN IF NOT EXISTS insider_sales       jsonb,            -- { sellers_count, total_sold_usd, details: [...] }
  ADD COLUMN IF NOT EXISTS recent_8ks          jsonb;            -- [{ date, items: ["1.01", ...], url }]
