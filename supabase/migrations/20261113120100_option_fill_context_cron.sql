-- option-fill-context every 5 minutes, 13:00 to 21:55 UTC on weekdays (handoff 2026-11-13-positions, A4): every open
-- sold option leg in every book that has no option_fill_context row gets one. The IBKR sync (ibkr-flex-sync-5min)
-- is not changed. A fill that lands after 21:55 UTC is backfilled on the next run from that day's leg_marks_daily.
select cron.unschedule('option-fill-context-5min') where exists (select 1 from cron.job where jobname = 'option-fill-context-5min');
select cron.schedule('option-fill-context-5min', '*/5 13-21 * * 1-5',
  $$ select public.cron_invoke_function_body('option-fill-context', '{}'::jsonb, 60000) $$);
