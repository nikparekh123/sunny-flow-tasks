/* ============================================================
   FIFO share consumption reconcile  (tracker item #17)
   ============================================================
   THE GAP:
   ibkr-flex-sync writes every share SELL with
       realized_pl: 0,
       note: 'IBKR sync — FIFO consumption pending reconcile'
   …and nothing ever performed that reconcile. Consequences seen in
   prod (NVDA, 2026-07-22):
     • EVERY share_lot still has qty_remaining = qty_original — lots
       summed to 7,001 shares against a real position of ~1,800,
       because 1,800 shares sold (200 on 7/20, 1,600 on 7/22) never
       decremented a lot.
     • realized_pl is 0 on all 24 IBKR-sourced sells, so realized share
       P&L (including assignments) was invisible.

   THE FIX:
   reconcile_share_fifo() walks unreconciled sells oldest-first and
   consumes lots FIFO (acquired_date, fifo_order), decrementing
   qty_remaining and accumulating
       realized += (sell.price − lot.cost_per_share) × consumed
   then stamps fifo_reconciled_at so it is idempotent — re-running can
   never double-consume.

   Lots acquired AFTER the sell date are skipped (you can't sell what
   you didn't own yet). If a sell can't be fully covered — lot history
   predates the IBKR era — it consumes what exists and realizes on
   that portion rather than inventing basis.

   Legacy rows that already carry a realized_pl are marked reconciled
   up front so their history is preserved untouched.

   TO UNDO:
     UPDATE share_lots SET qty_remaining = qty_original;
     UPDATE share_sells SET fifo_reconciled_at = NULL, realized_pl = 0
       WHERE source = 'ibkr_flex';
   ============================================================ */

-- ── 1. Idempotency marker ──────────────────────────────────────
ALTER TABLE public.share_sells
  ADD COLUMN IF NOT EXISTS fifo_reconciled_at timestamptz;

COMMENT ON COLUMN public.share_sells.fifo_reconciled_at IS
  'Set once FIFO lot consumption has been applied for this sell. '
  'NULL = still pending. Guarantees reconcile_share_fifo() is idempotent.';

-- Preserve pre-existing history: anything that already booked a
-- realized P&L is treated as done.
UPDATE public.share_sells
   SET fifo_reconciled_at = now()
 WHERE fifo_reconciled_at IS NULL
   AND realized_pl IS DISTINCT FROM 0;

-- ── 2. The reconcile ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reconcile_share_fifo()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s        RECORD;
  l        RECORD;
  need     numeric;
  take     numeric;
  realized numeric;
  done     integer := 0;
BEGIN
  FOR s IN
    SELECT id, ticker, quantity, price, trade_date
      FROM public.share_sells
     WHERE fifo_reconciled_at IS NULL
       AND voided_at IS NULL
     ORDER BY trade_date, created_at
  LOOP
    need     := s.quantity;
    realized := 0;

    FOR l IN
      SELECT id, qty_remaining, cost_per_share
        FROM public.share_lots
       WHERE ticker = s.ticker
         AND voided_at IS NULL
         AND qty_remaining > 0
         AND acquired_date <= s.trade_date
       ORDER BY acquired_date, fifo_order
    LOOP
      EXIT WHEN need <= 0;
      take := LEAST(need, l.qty_remaining);

      UPDATE public.share_lots
         SET qty_remaining = qty_remaining - take
       WHERE id = l.id;

      realized := realized + (s.price - l.cost_per_share) * take;
      need     := need - take;
    END LOOP;

    UPDATE public.share_sells
       SET realized_pl        = realized,
           fifo_reconciled_at = now()
     WHERE id = s.id;

    done := done + 1;
  END LOOP;

  RETURN done;
END $$;

COMMENT ON FUNCTION public.reconcile_share_fifo() IS
  'Consumes share_lots FIFO for every unreconciled share_sell and books '
  'realized_pl. Idempotent via share_sells.fifo_reconciled_at.';

-- ── 3. Nightly cron — 09:30 UTC, after the 09:00 Daily Flex backfill ──
create extension if not exists pg_cron with schema extensions;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'share-fifo-reconcile-daily') then
    perform cron.unschedule('share-fifo-reconcile-daily');
  end if;

  perform cron.schedule(
    'share-fifo-reconcile-daily',
    '30 9 * * *',
    $cron$ select public.reconcile_share_fifo(); $cron$
  );
end $$;
