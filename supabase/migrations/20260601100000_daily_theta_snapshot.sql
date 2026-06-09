-- ============================================================
-- 20260601100000_daily_theta_snapshot.sql
-- Phase 2 — daily theta snapshot for the Hedge tab
-- ============================================================
-- One row per trading day capturing the portfolio-level hedge θ
-- burn at market close. Powers:
--   • Day-over-day Δ-change on the Hedge tab hero
--   • 14-day sparkline showing theta acceleration
--   • Prior-week history in the WEEK view (sum of daily snapshots
--     per week)
--
-- Cron writes once per weekday at ~16:15 ET (post-close). Schema
-- is intentionally tiny — just the aggregate and a per-ticker
-- JSON breakdown so the sparkline can drill in if we want it to
-- later.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.daily_theta_snapshot (
  snapshot_date   date PRIMARY KEY,
  total_burn      numeric NOT NULL DEFAULT 0,   -- Σ |θ| × remaining_contracts × 100 (long puts only)
  long_put_count  int     NOT NULL DEFAULT 0,
  per_ticker      jsonb   NOT NULL DEFAULT '{}'::jsonb,  -- { "META": 390.0, "ADBE": 840.0, ... }
  captured_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS daily_theta_snapshot_date_idx
  ON public.daily_theta_snapshot (snapshot_date DESC);

-- RLS — read for any authenticated user, writes only via service role
ALTER TABLE public.daily_theta_snapshot ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "daily_theta_snapshot: authenticated read" ON public.daily_theta_snapshot;
CREATE POLICY "daily_theta_snapshot: authenticated read"
  ON public.daily_theta_snapshot FOR SELECT TO authenticated USING (true);

-- Realtime — optional but cheap; lets the iOS app receive new rows
-- without a manual refetch the next morning.
DO $$
BEGIN
  EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.daily_theta_snapshot';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
