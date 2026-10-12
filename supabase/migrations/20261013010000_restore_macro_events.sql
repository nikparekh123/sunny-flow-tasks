-- Restore macro_events from the 8 Oct cleanup: the new app's weekly report
-- lists Fed decisions and inflation reports under Coming up (Nik kept them,
-- 12 Oct 2026). Off the drop list so the 7 Nov purge does not take it.
alter table archive.macro_events set schema public;
delete from archive.retired_objects where name in ('macro_events', 'public.macro_events', 'archive.macro_events');

-- CPI and jobs-report dates from FRED, daily (macro-sync).
select cron.unschedule(jobid) from cron.job where jobname = 'macro-sync-daily';
select cron.schedule('macro-sync-daily', '25 5 * * *', $$ SELECT public.cron_invoke_function('macro-sync') $$);
