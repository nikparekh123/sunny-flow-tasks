/* ============================================================
   The share reconcile runs ONCE A DAY, so every share sale is invisible
   until the next morning.

   Three things must happen for a sale to reach the app:

     1. ibkr-flex-sync        every 15 min   writes share_sells
     2. reconcile_share_fifo  ONCE at 09:30  consumes lots, books realized_pl
     3. nvda_mirror/tlt_mirror every 3 min   copies into the app's tables

   Step 2 was the bottleneck. On 2026-08-14 Nik sold 3,000 NVDA and had 3,500
   called away; the sync had all seven rows within minutes, but the app still
   showed 7,500 shares eight hours later because step 2 had not run. Running it
   by hand moved the count to 1,000 immediately, which is what confirmed it.

   reconcile_share_fifo() is idempotent (guarded by share_sells.fifo_reconciled_at)
   so running it every 15 minutes only touches rows that are actually new.

   The nightly run STAYS. The Daily Flex backfill lands overnight and carries
   IBKR's own fifoPnlRealized, which is the only correct basis for shares that
   were called away, and that needs a pass after it arrives.
   ============================================================ */

create extension if not exists pg_cron with schema extensions;

do $$
begin
  -- the old once-a-day job, replaced by the pair below
  if exists (select 1 from cron.job where jobname = 'share-fifo-reconcile-daily') then
    perform cron.unschedule('share-fifo-reconcile-daily');
  end if;
  if exists (select 1 from cron.job where jobname = 'share-fifo-reconcile-15min') then
    perform cron.unschedule('share-fifo-reconcile-15min');
  end if;
  if exists (select 1 from cron.job where jobname = 'share-fifo-reconcile-nightly') then
    perform cron.unschedule('share-fifo-reconcile-nightly');
  end if;

  -- 13:00-22:00 UTC weekdays = 09:00-18:00 ET, matching the mirror's own window.
  -- Reconcile at :00/:15/:30/:45, mirror within 3 min, so a sale reaches the
  -- screen in under 20 minutes instead of the next morning.
  perform cron.schedule(
    'share-fifo-reconcile-15min',
    '*/15 13-22 * * 1-5',
    $cron$ select public.reconcile_share_fifo(); $cron$
  );

  -- The catch-up, after the overnight Daily Flex backfill.
  perform cron.schedule(
    'share-fifo-reconcile-nightly',
    '30 9 * * *',
    $cron$ select public.reconcile_share_fifo(); $cron$
  );
end $$;

select jobname, schedule, active
from cron.job
where jobname like 'share-fifo%'
order by jobname;
