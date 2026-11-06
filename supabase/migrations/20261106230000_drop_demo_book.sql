-- Drop the demo book D (Nik, 6 Nov 2026: "delete the temporary positions in my cousin's account").
-- Undoes 20261102200000_demo_book.sql. Run by hand through the Management API on 6 Nov 2026 at ~23:12 UTC;
-- kept here so a replay of the migrations ends in the same place.
--
-- The cousin's login (book-n@sunnyfi.co) goes back to his real book N as owner. Nik's two logins are NOT added
-- to N yet: today's app opens the first owned book by book_id, and 'N' sorts before 'S', so Nik's phone would
-- open his cousin's book until the account strip ships (handoff 6 Nov 2026).
begin;

update book_members set book_id = 'N'
 where book_id = 'D'
   and user_id = (select id from auth.users where email = 'book-n@sunnyfi.co');

select cron.unschedule(jobname) from cron.job
 where jobname in ('demo-book-roll', 'sunny-home-D', 'account-history-daily-D');

-- leg_marks_daily, option_greeks and option_greeks_live cascade from option_trades
delete from option_trades           where book_id = 'D';
delete from account_positions_daily where book_id = 'D';
delete from account_daily           where book_id = 'D';
delete from account_history         where book_id = 'D';
delete from home_snapshot           where book_id = 'D';
delete from home_todo               where book_id = 'D';
delete from reports                 where book_id = 'D';
delete from theta_checks            where book_id = 'D';
delete from ibkr_sync_runs          where book_id = 'D';
delete from sync_heartbeat          where feed in ('sunny-home-D', 'account-history-D');
delete from books                   where id = 'D';

drop function if exists public.demo_book_roll();

commit;
