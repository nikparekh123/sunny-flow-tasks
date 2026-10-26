-- The Today cards show index futures from 18:00 to the 9:30 open every night (Nik, 25 Oct 2026), so the
-- tape runs every minute and decides itself: 4:00-20:00 ET weekdays, plus the futures hours (Sunday 18:00
-- to Friday 17:00, less 17:00-18:00). Replaces market-tape-day and market-tape-late.
select cron.unschedule('market-tape-day');
select cron.unschedule('market-tape-late');
select cron.schedule('market-tape', '* * * * *', $$ SELECT public.cron_invoke_function('market-tape') $$);
