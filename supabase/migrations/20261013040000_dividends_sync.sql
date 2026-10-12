-- Declared dividends for the book, daily (dividends-sync, Polygon reference,
-- five calls a minute so names go 12.5 s apart in the background).
select cron.unschedule(jobid) from cron.job where jobname = 'dividends-sync-daily';
select cron.schedule('dividends-sync-daily', '35 5 * * *', $$ SELECT public.cron_invoke_function('dividends-sync') $$);
