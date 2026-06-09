-- ============================================================
-- 20260601000000_share_lots.sql
-- Phase 3 — FIFO share-lot tracking
-- ============================================================
-- Replaces the aggregate-only positions.{quantity, avg_cost} as
-- the source of truth for cost basis. Lots are consumed FIFO on
-- sells and short-call assignments; new lots are created on buys
-- and short-put assignments.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.share_lots (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticker               text NOT NULL,
  acquired_date        date NOT NULL,
  fifo_order           integer NOT NULL,
  qty_original         numeric NOT NULL CHECK (qty_original > 0),
  qty_remaining        numeric NOT NULL CHECK (qty_remaining >= 0),
  cost_per_share       numeric NOT NULL CHECK (cost_per_share >= 0),
  total_cost           numeric GENERATED ALWAYS AS (qty_original * cost_per_share) STORED,
  source               text NOT NULL DEFAULT 'manual'
                       CHECK (source IN ('manual','assignment','seed')),
  linked_assignment_id uuid REFERENCES public.option_trades(id) ON DELETE SET NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS share_lots_ticker_idx ON public.share_lots (ticker);
CREATE INDEX IF NOT EXISTS share_lots_fifo_idx
  ON public.share_lots (ticker, acquired_date, fifo_order)
  WHERE qty_remaining > 0;

-- Tracks which lot(s) a single sell event drew down, so realized P&L
-- is auditable lot-by-lot.
CREATE TABLE IF NOT EXISTS public.share_lot_consumptions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  share_sell_id uuid NOT NULL REFERENCES public.share_sells(id) ON DELETE CASCADE,
  lot_id        uuid NOT NULL REFERENCES public.share_lots(id),
  qty_consumed  numeric NOT NULL CHECK (qty_consumed > 0),
  realized_pl   numeric NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS share_lot_consumptions_sell_idx
  ON public.share_lot_consumptions (share_sell_id);

-- Per-ticker reconciliation note. Captures the small diff between
-- the broker's reported total cost basis and the sum of lot cost.
-- Diff is typically a few dollars from commission rounding.
CREATE TABLE IF NOT EXISTS public.position_reconciliation (
  ticker              text PRIMARY KEY,
  reported_total_cost numeric NOT NULL,
  computed_total_cost numeric NOT NULL,
  note                text,
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- RLS ──────────────────────────────────────────────────────────
ALTER TABLE public.share_lots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "share_lots: authenticated read"   ON public.share_lots;
DROP POLICY IF EXISTS "share_lots: authenticated insert" ON public.share_lots;
DROP POLICY IF EXISTS "share_lots: authenticated update" ON public.share_lots;
DROP POLICY IF EXISTS "share_lots: authenticated delete" ON public.share_lots;
CREATE POLICY "share_lots: authenticated read"   ON public.share_lots FOR SELECT TO authenticated USING (true);
CREATE POLICY "share_lots: authenticated insert" ON public.share_lots FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "share_lots: authenticated update" ON public.share_lots FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "share_lots: authenticated delete" ON public.share_lots FOR DELETE TO authenticated USING (true);

ALTER TABLE public.share_lot_consumptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "share_lot_consumptions: authenticated read"   ON public.share_lot_consumptions;
DROP POLICY IF EXISTS "share_lot_consumptions: authenticated insert" ON public.share_lot_consumptions;
DROP POLICY IF EXISTS "share_lot_consumptions: authenticated delete" ON public.share_lot_consumptions;
CREATE POLICY "share_lot_consumptions: authenticated read"   ON public.share_lot_consumptions FOR SELECT TO authenticated USING (true);
CREATE POLICY "share_lot_consumptions: authenticated insert" ON public.share_lot_consumptions FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "share_lot_consumptions: authenticated delete" ON public.share_lot_consumptions FOR DELETE TO authenticated USING (true);

ALTER TABLE public.position_reconciliation ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "position_reconciliation: authenticated read"   ON public.position_reconciliation;
DROP POLICY IF EXISTS "position_reconciliation: authenticated insert" ON public.position_reconciliation;
DROP POLICY IF EXISTS "position_reconciliation: authenticated update" ON public.position_reconciliation;
CREATE POLICY "position_reconciliation: authenticated read"   ON public.position_reconciliation FOR SELECT TO authenticated USING (true);
CREATE POLICY "position_reconciliation: authenticated insert" ON public.position_reconciliation FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "position_reconciliation: authenticated update" ON public.position_reconciliation FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- Realtime ─────────────────────────────────────────────────────
-- Wrap each ADD in a DO block so re-runs don't error on "relation
-- is already member of publication".
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.share_lots;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.share_lot_consumptions;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.position_reconciliation;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- Seed — 121 lots imported from Positions_lots_FIFO.xlsx
--                                    (snapshot 2026-05-31)
-- ============================================================

-- Seed lots — guard with NOT EXISTS so the migration is fully idempotent.
INSERT INTO public.share_lots (ticker, acquired_date, fifo_order, qty_original, qty_remaining, cost_per_share, source)
SELECT v.ticker, v.acquired_date::date, v.fifo_order, v.qty_original, v.qty_remaining, v.cost_per_share, v.source
FROM (VALUES
  ('ADBE', '2026-05-20', 1, 300, 300, 282.11, 'seed'),
  ('ADBE', '2026-05-28', 2, 16, 16, 241.64, 'seed'),
  ('ADBE', '2026-05-28', 3, 2, 2, 241.65, 'seed'),
  ('ADBE', '2026-05-28', 4, 10, 10, 241.64, 'seed'),
  ('ADBE', '2026-05-28', 5, 44, 44, 241.64, 'seed'),
  ('ADBE', '2026-05-28', 6, 14, 14, 241.65, 'seed'),
  ('ADBE', '2026-05-28', 7, 10, 10, 241.65, 'seed'),
  ('ADBE', '2026-05-28', 8, 10, 10, 241.65, 'seed'),
  ('ADBE', '2026-05-28', 9, 40, 40, 241.67, 'seed'),
  ('ADBE', '2026-05-28', 10, 54, 54, 241.64, 'seed'),
  ('BBY', '2026-05-19', 1, 120, 120, 59.44, 'seed'),
  ('BBY', '2026-05-19', 2, 180, 180, 59.44, 'seed'),
  ('FIG', '2026-05-26', 1, 145, 145, 22.35, 'seed'),
  ('FIG', '2026-05-26', 2, 50, 50, 22.32, 'seed'),
  ('FIG', '2026-05-26', 3, 247, 247, 22.32, 'seed'),
  ('FIG', '2026-05-26', 4, 300, 300, 22.35, 'seed'),
  ('FIG', '2026-05-26', 5, 4, 4, 22.34, 'seed'),
  ('FIG', '2026-05-26', 6, 205, 205, 22.35, 'seed'),
  ('FIG', '2026-05-26', 7, 5, 5, 22.33, 'seed'),
  ('FIG', '2026-05-26', 8, 103, 103, 22.32, 'seed'),
  ('FIG', '2026-05-26', 9, 52, 52, 22.32, 'seed'),
  ('FIG', '2026-05-26', 10, 40, 40, 22.33, 'seed'),
  ('FIG', '2026-05-26', 11, 100, 100, 22.32, 'seed'),
  ('FIG', '2026-05-26', 12, 14, 14, 22.33, 'seed'),
  ('FIG', '2026-05-26', 13, 171, 171, 22.32, 'seed'),
  ('FIG', '2026-05-26', 14, 2, 2, 22.32, 'seed'),
  ('FIG', '2026-05-26', 15, 9, 9, 22.33, 'seed'),
  ('FIG', '2026-05-26', 16, 100, 100, 22.31, 'seed'),
  ('FIG', '2026-05-26', 17, 24, 24, 22.33, 'seed'),
  ('FIG', '2026-05-26', 18, 41, 41, 22.33, 'seed'),
  ('FIG', '2026-05-26', 19, 46, 46, 22.32, 'seed'),
  ('FIG', '2026-05-26', 20, 42, 42, 22.3, 'seed'),
  ('FIG', '2026-05-26', 21, 300, 300, 22.3, 'seed'),
  ('HOOD', '2026-05-18', 1, 125, 125, 76.46, 'seed'),
  ('HOOD', '2026-05-18', 2, 125, 125, 76.46, 'seed'),
  ('HOOD', '2026-05-18', 3, 3, 3, 76.46, 'seed'),
  ('HOOD', '2026-05-18', 4, 42, 42, 76.46, 'seed'),
  ('HOOD', '2026-05-18', 5, 125, 125, 76.46, 'seed'),
  ('HOOD', '2026-05-18', 6, 1, 1, 76.46, 'seed'),
  ('HOOD', '2026-05-18', 7, 29, 29, 76.43, 'seed'),
  ('HOOD', '2026-05-18', 8, 48, 48, 76.43, 'seed'),
  ('HOOD', '2026-05-18', 9, 2, 2, 76.43, 'seed'),
  ('HOOD', '2026-05-28', 10, 50, 50, 82.67, 'seed'),
  ('HOOD', '2026-05-28', 11, 300, 300, 82.65, 'seed'),
  ('HOOD', '2026-05-28', 12, 100, 100, 82.65, 'seed'),
  ('HOOD', '2026-05-28', 13, 550, 550, 82.65, 'seed'),
  ('INTU', '2026-05-19', 1, 20, 20, 406.0, 'seed'),
  ('INTU', '2026-05-19', 2, 80, 80, 406.0, 'seed'),
  ('INTU', '2026-05-19', 3, 125, 125, 406.0, 'seed'),
  ('INTU', '2026-05-19', 4, 25, 25, 406.0, 'seed'),
  ('INTU', '2026-05-19', 5, 50, 50, 405.97, 'seed'),
  ('INTU', '2026-05-21', 6, 40, 40, 306.68, 'seed'),
  ('INTU', '2026-05-21', 7, 40, 40, 306.65, 'seed'),
  ('INTU', '2026-05-21', 8, 20, 20, 306.67, 'seed'),
  ('LULU', '2026-05-28', 1, 105, 105, 131.63, 'seed'),
  ('LULU', '2026-05-28', 2, 1, 1, 131.62, 'seed'),
  ('LULU', '2026-05-28', 3, 60, 60, 131.62, 'seed'),
  ('LULU', '2026-05-28', 4, 3, 3, 131.62, 'seed'),
  ('LULU', '2026-05-28', 5, 105, 105, 131.62, 'seed'),
  ('LULU', '2026-05-28', 6, 65, 65, 131.63, 'seed'),
  ('LULU', '2026-05-28', 7, 101, 101, 131.52, 'seed'),
  ('LULU', '2026-05-28', 8, 85, 85, 131.52, 'seed'),
  ('LULU', '2026-05-28', 9, 100, 100, 131.53, 'seed'),
  ('LULU', '2026-05-28', 10, 25, 25, 131.56, 'seed'),
  ('LULU', '2026-05-28', 11, 25, 25, 131.52, 'seed'),
  ('LULU', '2026-05-28', 12, 25, 25, 131.52, 'seed'),
  ('LULU', '2026-05-28', 13, 50, 50, 131.48, 'seed'),
  ('LULU', '2026-05-28', 14, 50, 50, 131.48, 'seed'),
  ('LULU', '2026-05-28', 15, 20, 20, 131.45, 'seed'),
  ('LULU', '2026-05-28', 16, 180, 180, 131.46, 'seed'),
  ('META', '2026-05-27', 1, 13, 13, 614.91, 'seed'),
  ('META', '2026-05-27', 2, 37, 37, 614.91, 'seed'),
  ('META', '2026-05-27', 3, 50, 50, 614.78, 'seed'),
  ('META', '2026-05-27', 4, 38, 38, 615.68, 'seed'),
  ('META', '2026-05-27', 5, 38, 38, 615.66, 'seed'),
  ('META', '2026-05-27', 6, 24, 24, 615.66, 'seed'),
  ('META', '2026-05-27', 7, 20, 20, 615.45, 'seed'),
  ('META', '2026-05-27', 8, 49, 49, 615.45, 'seed'),
  ('META', '2026-05-27', 9, 100, 100, 615.45, 'seed'),
  ('META', '2026-05-27', 10, 100, 100, 615.45, 'seed'),
  ('META', '2026-05-27', 11, 26, 26, 615.35, 'seed'),
  ('META', '2026-05-27', 12, 1, 1, 615.35, 'seed'),
  ('META', '2026-05-27', 13, 4, 4, 615.64, 'seed'),
  ('META', '2026-05-27', 14, 300, 300, 614.96, 'seed'),
  ('META', '2026-05-27', 15, 100, 100, 614.95, 'seed'),
  ('META', '2026-05-27', 16, 100, 100, 614.95, 'seed'),
  ('META', '2026-05-28', 17, 36, 36, 635.01, 'seed'),
  ('META', '2026-05-28', 18, 5, 5, 635.17, 'seed'),
  ('META', '2026-05-28', 19, 35, 35, 635.0, 'seed'),
  ('META', '2026-05-28', 20, 155, 155, 634.97, 'seed'),
  ('META', '2026-05-28', 21, 5, 5, 635.0, 'seed'),
  ('META', '2026-05-28', 22, 100, 100, 635.01, 'seed'),
  ('META', '2026-05-28', 23, 42, 42, 634.97, 'seed'),
  ('META', '2026-05-28', 24, 107, 107, 634.99, 'seed'),
  ('META', '2026-05-28', 25, 15, 15, 635.01, 'seed'),
  ('NFLX', '2026-01-26', 1, 500, 500, 85.81, 'seed'),
  ('NFLX', '2026-01-26', 2, 300, 300, 85.81, 'seed'),
  ('NFLX', '2026-01-26', 3, 100, 100, 85.81, 'seed'),
  ('NFLX', '2026-01-26', 4, 100, 100, 85.81, 'seed'),
  ('NFLX', '2026-03-09', 5, 500, 500, 97.86, 'seed'),
  ('NFLX', '2026-05-06', 6, 25, 25, 87.98, 'seed'),
  ('NKE', '2026-03-25', 1, 73, 73, 53.03, 'seed'),
  ('NKE', '2026-03-25', 2, 10, 10, 53.03, 'seed'),
  ('NKE', '2026-03-25', 3, 417, 417, 53.03, 'seed'),
  ('NKE', '2026-05-26', 4, 75, 75, 44.76, 'seed'),
  ('NKE', '2026-05-26', 5, 372, 372, 44.78, 'seed'),
  ('NKE', '2026-05-26', 6, 3, 3, 44.78, 'seed'),
  ('NKE', '2026-05-26', 7, 50, 50, 44.74, 'seed'),
  ('PYPL', '2026-05-19', 1, 11, 11, 44.31, 'seed'),
  ('PYPL', '2026-05-19', 2, 78, 78, 44.3, 'seed'),
  ('PYPL', '2026-05-19', 3, 78, 78, 44.3, 'seed'),
  ('PYPL', '2026-05-19', 4, 73, 73, 44.31, 'seed'),
  ('PYPL', '2026-05-19', 5, 78, 78, 44.31, 'seed'),
  ('PYPL', '2026-05-19', 6, 78, 78, 44.31, 'seed'),
  ('PYPL', '2026-05-19', 7, 4, 4, 44.3, 'seed'),
  ('PYPL', '2026-05-19', 8, 100, 100, 44.31, 'seed'),
  ('WDAY', '2026-05-18', 1, 100, 100, 127.47, 'seed'),
  ('WDAY', '2026-05-18', 2, 100, 100, 127.48, 'seed'),
  ('WDAY', '2026-05-18', 3, 100, 100, 127.48, 'seed'),
  ('WDAY', '2026-05-18', 4, 100, 100, 127.47, 'seed'),
  ('WDAY', '2026-05-18', 5, 100, 100, 127.48, 'seed')
) AS v (ticker, acquired_date, fifo_order, qty_original, qty_remaining, cost_per_share, source)
WHERE NOT EXISTS (SELECT 1 FROM public.share_lots WHERE source = 'seed');

INSERT INTO public.position_reconciliation (ticker, reported_total_cost, computed_total_cost, note) VALUES
  ('ADBE', 132962.56, 132962.56, 'broker P&L 2052.49 vs computed 2052.44 · diff -0.05 (commission)'),
  ('BBY', 17832.0, 17832.0, 'broker P&L 5554.50 vs computed 5553.00 · diff -1.50 (commission)'),
  ('FIG', 44653.07, 44653.07, 'broker P&L 7954.29 vs computed 7946.93 · diff -7.36 (commission)'),
  ('HOOD', 120878.63, 120878.63, 'broker P&L 22599.59 vs computed 22596.37 · diff -3.22 (commission)'),
  ('INTU', 152465.1, 152465.1, 'broker P&L -18332.18 vs computed -18333.10 · diff -0.92 (commission)'),
  ('LULU', 131541.4, 131541.4, 'broker P&L 460.34 vs computed 458.60 · diff -1.74 (commission)'),
  ('META', 932657.7, 932657.7, 'broker P&L 21348.23 vs computed 21342.30 · diff -5.93 (commission)'),
  ('NFLX', 136939.5, 136939.5, 'broker P&L -5654.63 vs computed -5652.25 · diff +2.38 (commission)'),
  ('NKE', 48901.5, 48901.5, 'broker P&L -3003.01 vs computed -3001.50 · diff +1.51 (commission)'),
  ('PYPL', 22153.4, 22153.4, 'broker P&L 248.01 vs computed 246.60 · diff -1.41 (commission)'),
  ('WDAY', 63738.0, 63738.0, 'broker P&L 11264.50 vs computed 11262.00 · diff -2.50 (commission)')
ON CONFLICT (ticker) DO NOTHING;
