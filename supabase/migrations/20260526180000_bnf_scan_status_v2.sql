-- Split bnf_scan_status.stage into equity_stage + etf_stage so the
-- parallel scans don't clobber each other's progress label. Also add
-- per-universe rate-limit counters so the banner can say "180 scanned ·
-- 50 rate-limited" without scrolling through function logs.

ALTER TABLE public.bnf_scan_status
  ADD COLUMN IF NOT EXISTS equity_stage text DEFAULT 'idle',
  ADD COLUMN IF NOT EXISTS etf_stage    text DEFAULT 'idle',
  ADD COLUMN IF NOT EXISTS equity_rate_limited integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS etf_rate_limited    integer NOT NULL DEFAULT 0;

-- Keep the existing 'stage' column for back-compat with current rows
-- (used as a coarse "overall" indicator: starting | running | done | error).
-- New per-universe writers update both: their own stage + the overall.

UPDATE public.bnf_scan_status
SET equity_stage = 'idle', etf_stage = 'idle'
WHERE equity_stage IS NULL OR etf_stage IS NULL;
