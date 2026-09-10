-- mp-refresh moves from every 15 minutes to every minute.
--
-- Nik, 2026-09-10, on the cards being an hour behind the market. Measured
-- before changing anything:
--
--   * a full run is 3.5s for 43 option legs and 8 tickers, 0 failures, so a
--     one-minute slot is not close to tight;
--   * Polygon's 15-minute-delayed feed is a ROLLING offset, not a staircase.
--     Two runs two minutes apart moved IV and delta on all 43 legs. A per
--     minute poll therefore returns genuinely new data every time;
--   * the free tier stops at 5 calls a minute and 43 sequential calls already
--     succeed, so the plan carries 44 a minute without trouble.
--
-- Cost is ~17,000 rows a day into option_greeks, up from ~1,200.
-- prune_option_greeks_90d already bounds that.
--
-- The old name said "15min" and would have been a lie, so the job is
-- rescheduled rather than altered. health-monitor keys off the age of
-- option_greeks, not the job name, so nothing downstream cares.
--
-- Hours widen to 13-20 UTC (Mon-Fri), 09:00 to 16:59 ET. The old window shut
-- at 15:45 ET, so the last mark of the day was fifteen minutes before the
-- close and Polygon's own delay made it more like half an hour. The extra hour
-- is what captures the true close, which only lands at about 16:15 ET.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'mp-refresh-15min') then
    perform cron.unschedule('mp-refresh-15min');
  end if;
  if not exists (select 1 from cron.job where jobname = 'mp-refresh-1min') then
    perform cron.schedule(
      'mp-refresh-1min',
      '* 13-20 * * 1-5',
      $cmd$SELECT public.cron_invoke_function('mp-refresh')$cmd$
    );
  end if;
end $$;
