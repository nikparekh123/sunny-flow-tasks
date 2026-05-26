-- BNF scan progress — one row per user. The bnf-scan edge function
-- upserts this row at each stage transition and every ~50 tickers
-- within the equity loop. Client subscribes via Supabase Realtime
-- (no polling) and renders a progress banner.
--
-- Stages walk through: starting → equity_pricing → equity_enriching
--                    → etf_pricing → etf_enriching → writing → done
--                    (or error)

CREATE TABLE IF NOT EXISTS public.bnf_scan_status (
  user_id              uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  scan_id              uuid NOT NULL,
  mode                 text NOT NULL DEFAULT 'both'
                         CHECK (mode IN ('equity', 'etf', 'both')),
  stage                text NOT NULL DEFAULT 'starting'
                         CHECK (stage IN (
                           'starting', 'equity_pricing', 'equity_enriching',
                           'etf_pricing', 'etf_enriching', 'writing',
                           'done', 'error'
                         )),
  equity_scanned       integer NOT NULL DEFAULT 0,
  equity_total         integer NOT NULL DEFAULT 0,
  equity_candidates    integer NOT NULL DEFAULT 0,
  etf_scanned          integer NOT NULL DEFAULT 0,
  etf_total            integer NOT NULL DEFAULT 0,
  etf_candidates       integer NOT NULL DEFAULT 0,
  message              text,                     -- error string when stage='error'
  started_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.bnf_scan_status ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bnf_scan_status_own" ON public.bnf_scan_status
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Enable Supabase Realtime push for this table so the client can see
-- updates without polling. Idempotent guard — adding twice errors.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'bnf_scan_status'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.bnf_scan_status;
  END IF;
END
$$;
