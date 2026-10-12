-- Clocks go back on 1 Nov 2026 and pg_cron speaks UTC.
-- mp-refresh: fire 13-21 UTC; the function itself runs only 9:00-16:59 New
-- York, so the 4:00 close is marked in both EDT and EST.
-- ticker-iv-snapshot: 20:15 UTC was 4:15 PM in EDT but 3:15 PM in EST, before
-- the close; 21:15 UTC is after it in both (5:15 PM / 4:15 PM).
select cron.alter_job(jobid, schedule := '* 13-21 * * 1-5') from cron.job where jobname = 'mp-refresh-1min';
select cron.alter_job(jobid, schedule := '15 21 * * 1-5') from cron.job where jobname = 'ticker-iv-snapshot-daily';
