/* ============================================================
   Retention crons for the append-only greeks + quotes tables.
   Runs once a day at 06:00 UTC (~01:00–02:00 ET, well off-market).
   ============================================================ */

create extension if not exists pg_cron with schema extensions;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'prune-option-greeks-daily') then
    perform cron.unschedule('prune-option-greeks-daily');
  end if;
  if exists (select 1 from cron.job where jobname = 'prune-ticker-quotes-daily') then
    perform cron.unschedule('prune-ticker-quotes-daily');
  end if;

  perform cron.schedule(
    'prune-option-greeks-daily',
    '0 6 * * *',
    $cron$ select public.prune_option_greeks_90d(); $cron$
  );

  perform cron.schedule(
    'prune-ticker-quotes-daily',
    '5 6 * * *',
    $cron$ select public.prune_ticker_quotes_30d(); $cron$
  );
end $$;
