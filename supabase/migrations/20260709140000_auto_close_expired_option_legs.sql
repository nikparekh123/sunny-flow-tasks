/* ============================================================
   Auto-close expired option legs — recurrence guard
   ============================================================
   THE PROBLEM (2026-07-09):
   IBKR's TCF "Today" feed reports executions, not expiries. When a
   short call / long put simply EXPIRES (worthless or assigned), no
   close row ever arrives, so the leg sits "open" forever in
   option_trades. As of this migration 30 short calls (108 contracts,
   ~$19,814 premium) + 1 long put were still marked open with expiries
   from 2026-06-03 → 2026-07-06 — inflating "Open call credit" by 57%
   and 404-spamming mp-refresh every 15 min (Polygon returns 404 for
   expired contracts, freezing their greeks).

   THE FIX:
   A close row valued at premium 0 retires the leg through the app's
   pooled FIFO (OptionFIFO keys on ticker/type/direction/strike/expiry
   and ignores closes_trade_id). A short call closed at 0 keeps its
   full credit as realized (expired worthless / kept premium); a long
   put closed at 0 books the full debit as the realized loss. Both are
   correct for an expiry.

   close_expired_option_legs(buffer_days) flattens every pooled key
   whose expiry is > buffer_days in the past and still has net open
   contracts. It is idempotent (residual becomes 0 after the first
   pass). The nightly cron runs it with a 2-day buffer so IBKR's Daily
   Flex ("Last 5 Business Days") gets first crack at reporting a real
   close/assignment; FIFO safely dedups if both land.

   New `source = 'expiry'` marks the synthetic closes so they're
   identifiable and reversible:  DELETE ... WHERE source = 'expiry'.
   ============================================================ */

-- ── 1. Allow the new source value ──────────────────────────────
ALTER TABLE public.option_trades
  DROP CONSTRAINT IF EXISTS option_trades_source_check;
ALTER TABLE public.option_trades
  ADD CONSTRAINT option_trades_source_check
    CHECK (source IN ('manual','ibkr_flex','assignment','seed','expiry'));

-- ── 2. The sweep function ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.close_expired_option_legs(buffer_days integer DEFAULT 2)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  inserted integer;
BEGIN
  WITH keyagg AS (
    SELECT ticker, option_type, direction, strike, expiry,
           SUM(contracts) FILTER (WHERE action = 'open')  AS opened,
           COALESCE(SUM(contracts) FILTER (WHERE action = 'close'), 0) AS closed
    FROM public.option_trades
    WHERE voided_at IS NULL
    GROUP BY ticker, option_type, direction, strike, expiry
  ),
  residuals AS (
    SELECT ticker, option_type, direction, strike, expiry,
           opened - closed AS residual
    FROM keyagg
    WHERE expiry < current_date - make_interval(days => buffer_days)
      AND opened - closed > 0
  ),
  ins AS (
    INSERT INTO public.option_trades
      (ticker, trade_date, action, option_type, direction,
       contracts, strike, premium, expiry, source, note)
    SELECT ticker, expiry, 'close', option_type, direction,
           residual, strike, 0, expiry, 'expiry',
           'auto-closed at expiry'
    FROM residuals
    RETURNING 1
  )
  SELECT count(*) INTO inserted FROM ins;

  RETURN inserted;
END $$;

COMMENT ON FUNCTION public.close_expired_option_legs(integer) IS
  'Inserts premium-0 close rows for option legs whose expiry is > buffer_days '
  'past and still net-open. Retires them via pooled FIFO. Idempotent. '
  'Synthetic closes carry source = ''expiry'' (reversible).';

-- ── 3. Nightly cron — 10:00 UTC, after the 09:00 Daily Flex backfill ──
create extension if not exists pg_cron with schema extensions;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'close-expired-options-daily') then
    perform cron.unschedule('close-expired-options-daily');
  end if;

  perform cron.schedule(
    'close-expired-options-daily',
    '0 10 * * *',
    $cron$ select public.close_expired_option_legs(2); $cron$
  );
end $$;
