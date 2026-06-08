/* ============================================================
   IBKR Flex sync — schema additions
   ============================================================
   Prepares option_trades, share_lots, share_sells for ingestion
   from IBKR's Trade Confirmation Flex Query (Edge function
   `ibkr-flex-sync`, separate file).

   Columns added to each trade-bearing table:
   • source           — extends existing convention; 'ibkr_flex'
                        joins 'manual', 'assignment', 'seed'.
   • ibkr_trade_id    — IBKR's per-execution unique id (text — they
                        can be 10+ digits). Partial UNIQUE index
                        ensures dedup without blocking manual rows
                        which leave it NULL.
   • last_synced_at   — wall-clock of most recent sync touch. Used
                        for the "Recently imported" UI badge and
                        for cron-stall detection.
   • voided_at        — soft delete. If IBKR's report drops a
                        previously-seen tradeID (correction, broker
                        break, cancellation), the row is marked
                        voided rather than hard-deleted, so we can
                        recover from transient IBKR bugs without
                        losing history. UI hides voided rows by
                        default.

   New table: ibkr_sync_runs
   • Audit log for every Edge-function invocation. Tracks counts
     (inserted/updated/voided/errored), elapsed time, errors as
     JSONB. Health-monitor cron reads this to detect stalls
     (see follow-up: 'cron.ibkr_flex_stale' system_alert).
   ============================================================ */

-- ── option_trades ──────────────────────────────────────────────
ALTER TABLE public.option_trades
  ADD COLUMN IF NOT EXISTS source         text NOT NULL DEFAULT 'manual'
                            CHECK (source IN ('manual','ibkr_flex','assignment','seed')),
  ADD COLUMN IF NOT EXISTS ibkr_trade_id  text,
  ADD COLUMN IF NOT EXISTS last_synced_at timestamptz,
  ADD COLUMN IF NOT EXISTS voided_at      timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS option_trades_ibkr_trade_id_uniq
  ON public.option_trades (ibkr_trade_id)
  WHERE ibkr_trade_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS option_trades_source_idx
  ON public.option_trades (source);

CREATE INDEX IF NOT EXISTS option_trades_recently_synced_idx
  ON public.option_trades (last_synced_at DESC)
  WHERE last_synced_at IS NOT NULL AND voided_at IS NULL;

-- ── share_lots ─────────────────────────────────────────────────
-- share_lots already has source ('manual','assignment','seed').
-- Drop and recreate the CHECK to allow 'ibkr_flex'.
ALTER TABLE public.share_lots
  DROP CONSTRAINT IF EXISTS share_lots_source_check;

ALTER TABLE public.share_lots
  ADD CONSTRAINT share_lots_source_check
    CHECK (source IN ('manual','ibkr_flex','assignment','seed'));

ALTER TABLE public.share_lots
  ADD COLUMN IF NOT EXISTS ibkr_trade_id  text,
  ADD COLUMN IF NOT EXISTS last_synced_at timestamptz,
  ADD COLUMN IF NOT EXISTS voided_at      timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS share_lots_ibkr_trade_id_uniq
  ON public.share_lots (ibkr_trade_id)
  WHERE ibkr_trade_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS share_lots_source_idx
  ON public.share_lots (source);

-- ── share_sells ────────────────────────────────────────────────
-- share_sells has source ('manual','assignment'). Extend.
ALTER TABLE public.share_sells
  DROP CONSTRAINT IF EXISTS share_sells_source_check;

ALTER TABLE public.share_sells
  ADD CONSTRAINT share_sells_source_check
    CHECK (source IN ('manual','ibkr_flex','assignment'));

ALTER TABLE public.share_sells
  ADD COLUMN IF NOT EXISTS ibkr_trade_id  text,
  ADD COLUMN IF NOT EXISTS last_synced_at timestamptz,
  ADD COLUMN IF NOT EXISTS voided_at      timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS share_sells_ibkr_trade_id_uniq
  ON public.share_sells (ibkr_trade_id)
  WHERE ibkr_trade_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS share_sells_source_idx
  ON public.share_sells (source);

/* ============================================================
   ibkr_sync_runs — audit log of every sync invocation
   ============================================================
   One row per Edge-function call. Health-monitor reads the
   freshest row to detect stalls during market hours.

   status:
   • 'running'   — function in flight (cleared when finished)
   • 'success'   — all rows processed without throw
   • 'partial'   — some rows errored but run completed
   • 'failed'    — fatal error (network, auth, parse, lock)

   counts:
   • rows_seen            — TradeConfirms in the IBKR XML
   • rows_inserted        — new ibkr_trade_ids written
   • rows_updated         — existing ibkr_trade_ids amended
   • rows_voided          — previously-seen ids missing from
                            this report, marked voided_at
   • rows_errored         — failed row inserts (see errors[])
   ============================================================ */

CREATE TABLE IF NOT EXISTS public.ibkr_sync_runs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at      timestamptz NOT NULL DEFAULT now(),
  finished_at     timestamptz,
  duration_ms     integer,
  status          text NOT NULL DEFAULT 'running'
                    CHECK (status IN ('running','success','partial','failed')),
  trigger         text NOT NULL DEFAULT 'cron'
                    CHECK (trigger IN ('cron','manual','backfill')),
  rows_seen       integer NOT NULL DEFAULT 0,
  rows_inserted   integer NOT NULL DEFAULT 0,
  rows_updated    integer NOT NULL DEFAULT 0,
  rows_voided     integer NOT NULL DEFAULT 0,
  rows_errored    integer NOT NULL DEFAULT 0,
  errors          jsonb NOT NULL DEFAULT '[]'::jsonb,
  reference_code  text,    -- IBKR Flex ReferenceCode for debugging
  ibkr_account_id text,
  notes           text     -- free-form: "advisory lock held by older run", etc.
);

CREATE INDEX IF NOT EXISTS ibkr_sync_runs_started_at_idx
  ON public.ibkr_sync_runs (started_at DESC);

CREATE INDEX IF NOT EXISTS ibkr_sync_runs_status_started_idx
  ON public.ibkr_sync_runs (status, started_at DESC);

ALTER TABLE public.ibkr_sync_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ibkr_sync_runs: authenticated read" ON public.ibkr_sync_runs;
CREATE POLICY "ibkr_sync_runs: authenticated read"
  ON public.ibkr_sync_runs
  FOR SELECT TO authenticated
  USING (true);
