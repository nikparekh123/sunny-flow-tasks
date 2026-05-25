-- BNF candidates: add company name column. Populated by the bnf-scan
-- edge function alongside the Yahoo earnings lookup so it costs no
-- extra API call. Existing rows get null until the next scan.

ALTER TABLE public.bnf_candidates
  ADD COLUMN IF NOT EXISTS name text;
