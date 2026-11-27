-- The 4:30 PM close job copied whatever price ticker_quotes_latest held, even one the feed stopped updating: TLT left
-- the feed about 5 Nov and its close stayed at $81.95 for 15 sessions (found by Sundial's review, 27 Nov 2026), and KR
-- and PEP are the same. It also wrote a close on market holidays. Now it takes only prices updated in the last 2
-- hours, and nothing on a closed day.
select cron.alter_job((select jobid from cron.job where jobname = 'capture-daily-close'), command := $cmd$
    insert into public.daily_closes (ticker, date, close_price)
    select ticker, current_date, spot
    from public.ticker_quotes_latest
    where spot is not null
      and captured_at > now() - interval '2 hours'
      and not exists (select 1 from public.market_calendar m where m.date = current_date and m.kind = 'closed')
    on conflict (ticker, date) do update
      set close_price = excluded.close_price, captured_at = now();
$cmd$);
